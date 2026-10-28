import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/diary/models/diary_day_entity.dart';
import 'package:journal/modules/diary/models/diary_item.dart';
import 'package:journal/modules/recall/hybrid_retriever.dart';
import 'package:journal/modules/recall/recall_contract.dart';
import 'package:journal/modules/recall/recall_embedder.dart';
import 'package:journal/modules/recall/recall_index.dart';
import 'package:journal/modules/recall/recall_indexer.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';
import 'package:journal/objectbox/objectbox.g.dart';

const qwen =
    'qwen3-embedding-0.6b-q8_0@370f27d7550e0def9b39c1f16d3fbaa13aa67728';
const qwenF16 =
    'qwen3-embedding-0.6b-f16@370f27d7550e0def9b39c1f16d3fbaa13aa67728';

/// Synthetic embedding: texts about the same topic share a direction, so
/// "anxious" and "on edge" are neighbours while keywords never overlap.
const _topics = [
  {'anxious', 'anxiety', 'edge', 'nervous', 'wasiwasi'},
  {'garden', 'walk', 'bustani'},
  {'amina'},
];

List<double> fakeVector(String text) {
  final v = List<double>.filled(recallDimensions, 0);
  final words = text.toLowerCase().split(RegExp(r'[^a-z]+'));
  var hit = false;
  for (final (i, topic) in _topics.indexed) {
    if (words.any(topic.contains)) {
      v[i] = 1;
      hit = true;
    }
  }
  if (!hit) v[100 + text.hashCode % 900] = 1;
  return v;
}

class FakeEmbedder implements TextEmbedder {
  final calls = <List<EmbedItem>>[];
  String? failWith;
  int? failAfter;

  @override
  Future<Map<String, List<double>>> embed(
    String model,
    List<EmbedItem> items,
  ) async {
    if (failAfter != null && calls.length >= failAfter!) {
      throw CompanionFailure(failWith ?? 'UNAVAILABLE', 'offline');
    }
    calls.add(items);
    return {for (final i in items) i.id: fakeVector(i.text)};
  }

  int get embedded =>
      calls.expand((b) => b).where((i) => i.kind == 'document').length;
}

class MemoryPreference implements RecallPreference {
  MemoryPreference(this.enabled);
  @override
  Set<RecallKind> enabled;
  @override
  Future<void> set(RecallKind kind, bool value) async =>
      value ? enabled.add(kind) : enabled.remove(kind);
}

RecallSource diary(String id, String date, String text) =>
    RecallSource(kind: RecallKind.diary, id: id, date: date, text: text);

void main() {
  late Directory directory;
  late Store store;
  late RecallIndex index;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('s03b');
    store = await openStore(directory: directory.path);
    index = RecallIndex(store);
  });
  tearDown(() async {
    store.close();
    await directory.delete(recursive: true);
  });

  test('vectors decode from little-endian base64 and reject wrong sizes', () {
    final data = ByteData(recallDimensions * 4)
      ..setFloat32(4, .5, Endian.little);
    final b64 = base64Encode(data.buffer.asUint8List());
    expect(decodeVector(b64, recallDimensions)[1], .5);
    expect(() => decodeVector(b64, 8), throwsFormatException);
  });

  test('embed text is cut to the byte limit on a character boundary', () {
    final long = 'é' * embedTextBytes;
    final bounded = boundedEmbedText(long);
    expect(utf8.encode(bounded).length, lessThanOrEqualTo(embedTextBytes));
    expect(bounded.runes.every((r) => r == 'é'.runes.first), isTrue);
    expect(recallHash('a'), isNot(recallHash('b')));
  });

  test('index finds neighbours of the current model only, within scope', () {
    final edge = diary('a', '2026-10-01', 'Felt on edge before the interview');
    final walk = diary('b', '2026-10-02', 'A long walk in the garden');
    index.put(edge, qwen, fakeVector(edge.text));
    index.put(walk, qwen, fakeVector(walk.text));
    final old = diary('c', '2026-10-03', 'nervous all day');
    index.put(old, qwenF16, fakeVector(old.text));
    final hits = index.nearest(
      fakeVector('anxious'),
      qwen,
      kinds: {RecallKind.diary},
    );
    expect(hits.map((h) => h.sourceId), ['a']);
    expect(
      index.nearest(
        fakeVector('anxious'),
        qwen,
        kinds: {RecallKind.diary},
        from: '2026-10-02',
      ),
      isEmpty,
    );
    expect(index.prune(RecallKind.diary, qwen, {'diary:a'}), 2);
    expect(index.hashes(RecallKind.diary, qwen).keys, ['diary:a']);
    expect(index.clear(RecallKind.diary), 1);
  });

  group('hybrid retriever', () {
    final sources = [
      diary('edge', '2026-10-01', 'Felt on edge all day before the interview.'),
      diary('amina', '2026-09-10', 'Lunch with Amina at the market.'),
      diary('garden', '2026-09-20', 'Nilitembea bustani asubuhi, then coffee.'),
      diary('plain', '2026-10-05', 'Laundry and an early night.'),
    ];
    late FakeEmbedder embedder;
    HybridRetriever retriever({EmbeddingCapability? capability}) =>
        HybridRetriever(
          index: index,
          embedder: embedder,
          capability: capability,
          enabled: {RecallKind.diary},
        );

    setUp(() {
      embedder = FakeEmbedder();
      for (final s in sources) {
        index.put(s, qwen, fakeVector(s.text));
      }
    });

    test('finds meaning that keywords miss', () async {
      final r = retriever(capability: const EmbeddingCapability(qwen, 1024));
      final result = await r.search(
        'when was I anxious',
        sources: sources,
        kinds: {RecallKind.diary},
      );
      expect(result.semantic, isTrue);
      expect(result.hits.first.source.id, 'edge');
      expect(result.hits.first.keyword, 0);
      expect(embedder.calls.single.single.kind, 'query');
    });

    test('exact names rank first and keep their keyword match', () async {
      final r = retriever(capability: const EmbeddingCapability(qwen, 1024));
      final result = await r.search(
        'Amina',
        sources: sources,
        kinds: {RecallKind.diary},
      );
      expect(result.hits.first.source.id, 'amina');
      expect(result.hits.first.keyword, 1);
    });

    test('English and Swahili words both match', () async {
      final r = retriever(capability: const EmbeddingCapability(qwen, 1024));
      final swahili = await r.search(
        'bustani',
        sources: sources,
        kinds: {RecallKind.diary},
      );
      expect(swahili.hits.first.source.id, 'garden');
      final english = await r.search(
        'garden walk',
        sources: sources,
        kinds: {RecallKind.diary},
      );
      expect(english.hits.first.source.id, 'garden');
      expect(english.hits.first.keyword, 0);
    });

    test(
      'falls back to labelled keyword ranking without the computer',
      () async {
        final r = retriever();
        final result = await r.search(
          'interview',
          sources: sources,
          kinds: {RecallKind.diary},
        );
        expect(result.semantic, isFalse);
        expect(result.fallback, startsWith('Keyword results'));
        expect(result.hits.single.source.id, 'edge');
        expect(embedder.calls, isEmpty);
        embedder.failAfter = 0;
        final failed = await retriever(
          capability: const EmbeddingCapability(qwen, 1024),
        ).search('anxious nobody', sources: sources, kinds: {RecallKind.diary});
        expect(failed.semantic, isFalse);
        expect(failed.fallback, contains('could not'));
      },
    );

    test('the last typed word matches as a prefix; scopes filter', () async {
      final r = retriever();
      final typing = await r.search(
        'laund',
        sources: sources,
        kinds: {RecallKind.diary},
      );
      expect(typing.hits.single.source.id, 'plain');
      final scoped = await r.search(
        'interview',
        sources: sources,
        kinds: {RecallKind.diary},
        to: '2026-09-30',
      );
      expect(scoped.hits, isEmpty);
    });
  });

  group('indexer', () {
    late FakeEmbedder embedder;
    late MemoryPreference preference;
    late List<RecallSource> diarySources;
    late ProviderContainer container;
    EmbeddingCapability? capability;

    ProviderContainer build() => ProviderContainer(
      overrides: [
        recallIndexProvider.overrideWithValue(index),
        recallEmbedderProvider.overrideWithValue(embedder),
        recallPreferenceProvider.overrideWithValue(preference),
        recallCapabilityProvider.overrideWith((ref) => capability),
        recallSourcesProvider.overrideWithValue(
          (kind) => kind == RecallKind.diary ? diarySources : const [],
        ),
      ],
    );

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      embedder = FakeEmbedder();
      preference = MemoryPreference({RecallKind.diary});
      capability = const EmbeddingCapability(qwen, 1024);
      diarySources = [
        for (var i = 0; i < 11; i++)
          diary('d$i', '2026-10-0${i % 9 + 1}', 'entry $i'),
      ];
      container = build();
    });
    tearDown(() => container.dispose());

    Future<RecallIndexState> pass() async {
      await container.read(recallIndexerProvider.notifier).run();
      return container.read(recallIndexerProvider);
    }

    test('embeds in batches, then only edits; deletes drop vectors', () async {
      final state = await pass();
      expect(state.done, 11);
      expect(embedder.calls.map((b) => b.length), [8, 3]);
      expect(index.count(RecallKind.diary, qwen), 11);
      diarySources[0] = diary('d0', '2026-10-01', 'entry 0 edited');
      diarySources.removeLast();
      embedder.calls.clear();
      await pass();
      expect(embedder.embedded, 1);
      expect(index.count(RecallKind.diary, qwen), 10);
    });

    test('an interrupted pass resumes with what is left', () async {
      embedder.failAfter = 1;
      final stopped = await pass();
      expect(stopped.message, startsWith('Indexing stopped'));
      expect(index.count(RecallKind.diary, qwen), 8);
      embedder.failAfter = null;
      embedder.calls.clear();
      await pass();
      expect(embedder.embedded, 3);
      expect(index.count(RecallKind.diary, qwen), 11);
    });

    test('a model swap rebuilds without mixing vectors', () async {
      await pass();
      capability = const EmbeddingCapability(qwenF16, 1024);
      container.dispose();
      container = build();
      embedder.calls.clear();
      await pass();
      expect(embedder.embedded, 11);
      expect(index.count(RecallKind.diary, qwen), 0);
      expect(index.count(RecallKind.diary, qwenF16), 11);
    });

    test('no computer means no indexing and a waiting message', () async {
      capability = null;
      container.dispose();
      container = build();
      final state = await pass();
      expect(embedder.calls, isEmpty);
      expect(state.message, startsWith('Waiting'));
    });

    test('opting out deletes that collection; pause stops a pass', () async {
      await pass();
      await container
          .read(recallIndexerProvider.notifier)
          .setEnabled(RecallKind.diary, false);
      expect(index.count(RecallKind.diary, qwen), 0);
      expect(preference.enabled, isEmpty);
      await container
          .read(recallIndexerProvider.notifier)
          .setEnabled(RecallKind.diary, true);
      container.read(recallIndexerProvider.notifier).pause();
      embedder.calls.clear();
      await pass();
      expect(embedder.calls, isEmpty);
    });
  });

  test('sources skip deleted diary days and carry the day title', () {
    final now = DateTime.utc(2026, 10, 1);
    final day = DiaryDayEntity(
      dateString: '2026-10-01',
      date: now,
      dayTitle: 'Interview day',
    );
    day.items = [
      DiaryItem(
        itemUuid: 'x',
        createdAt: now,
        content: 'Felt on edge',
        updatedAt: now,
      ),
    ];
    final s = RecallSource.diary([day]).single;
    expect(s.key, 'diary:x');
    expect(s.context, 'Interview day');
    expect(RecallSource.diary([day..isDeleted = true]), isEmpty);
  });
}
