// Opt-in S03b device demonstration against an isolated companion fixture
// (desktop launched with --connection-demo=DIR --recovery-phone-fixture and
// Qwen3 Embedding loaded). Synthetic entries only; a temporary ObjectBox
// store; no journal data is read or written.
//
//   flutter test integration_test/recall_device_test.dart -d DEVICE \
//     --no-uninstall --dart-define-from-file=DIR/device-config.json
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:journal/modules/recall/hybrid_retriever.dart';
import 'package:journal/modules/recall/recall_contract.dart';
import 'package:journal/modules/recall/recall_embedder.dart';
import 'package:journal/modules/recall/recall_index.dart';
import 'package:journal/modules/recall/recall_indexer.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';
import 'package:journal/objectbox/objectbox.g.dart';
import 'package:path_provider/path_provider.dart';

const _trusted = String.fromEnvironment('RECOVERY_TRUSTED_COMPUTER');

class _Preference implements RecallPreference {
  @override
  Set<RecallKind> enabled = {RecallKind.diary, RecallKind.note};
  @override
  Future<void> set(RecallKind kind, bool value) async =>
      value ? enabled.add(kind) : enabled.remove(kind);
}

final _entries = {
  'edge': 'Felt on edge all day before the interview. Could not sit still.',
  'nervous': 'My hands were shaking before the presentation and my stomach was in knots.',
  'calm': 'A slow Sunday. Tea on the balcony, nothing to do, felt peaceful.',
  'amina': 'Lunch with Amina at the market. She told me about her new job.',
  'garden': 'Nilitembea bustani asubuhi na mbwa, then coffee with Joe.',
  'wasiwasi': 'Leo nilikuwa na wasiwasi mwingi kuhusu kazi na pesa.',
  'laundry': 'Laundry, groceries and an early night.',
  'run': 'Ran 5k along the river, legs tired but happy.',
  'dentist': 'Dentist appointment moved to Thursday the 14th.',
  'rain': 'It rained all afternoon; read a novel by the window.',
  'fight': 'Argued with my brother about the car again. Still annoyed.',
  'sleep': 'Barely slept, kept waking up at 3am worrying.',
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'S03b: index, hybrid search, fallback and opt-out on a real phone',
    (tester) async {
      expect(
        _trusted,
        isNotEmpty,
        reason: 'Pass the fixture device-config.json',
      );
      final computer = TrustedComputer.fromJson(
        jsonDecode(_trusted) as Map<String, dynamic>,
      );
      final status = await CompanionClient(PinnedCompanionTransport())
          .authenticated(computer, 'GET', '/v1/status');
      final capability = EmbeddingCapability.fromStatus(status);
      expect(
        capability,
        isNotNull,
        reason: 'Load Qwen3 Embedding on the fixture',
      );

      final dir = Directory(
        '${(await getTemporaryDirectory()).path}/s03b-${DateTime.now().millisecondsSinceEpoch}',
      );
      final store = await openStore(directory: dir.path);
      addTearDown(() async {
        store.close();
        await dir.delete(recursive: true);
      });
      final index = RecallIndex(store);
      final preference = _Preference();
      final sources = [
        for (final (i, MapEntry(:key, :value)) in _entries.entries.indexed)
          RecallSource(
            kind: RecallKind.diary,
            id: key,
            date: '2026-10-${(i + 1).toString().padLeft(2, '0')}',
            text: value,
          ),
      ];
      final notes = [
        RecallSource(
          kind: RecallKind.note,
          id: 'n1',
          date: '2026-10-20',
          text: 'Interview prep\nQuestions to ask about the team and the role.',
        ),
      ];
      final container = ProviderContainer(
        overrides: [
          recallIndexProvider.overrideWithValue(index),
          recallEmbedderProvider.overrideWithValue(
            CompanionTextEmbedder(computer: () => computer),
          ),
          recallPreferenceProvider.overrideWithValue(preference),
          recallCapabilityProvider.overrideWith((ref) => capability),
          recallSourcesProvider.overrideWithValue(
            (kind) => kind == RecallKind.diary ? sources : notes,
          ),
        ],
      );
      addTearDown(container.dispose);
      final indexer = container.read(recallIndexerProvider.notifier);
      final report = <String, Object>{'model': capability!.model};

      // Index 13 sources (two batches) and time it.
      var watch = Stopwatch()..start();
      await indexer.run();
      report['indexMs'] = watch.elapsedMilliseconds;
      report['indexed'] = container.read(recallIndexerProvider).done;
      expect(index.count(RecallKind.diary, capability.model), _entries.length);
      expect(index.count(RecallKind.note, capability.model), 1);

      // An edit re-embeds one entry only; an unchanged pass embeds nothing.
      sources[0] = RecallSource(
        kind: RecallKind.diary,
        id: 'edge',
        date: '2026-10-01',
        text: 'Felt on edge all morning before the interview, calmer by lunch.',
      );
      await indexer.run();
      expect(container.read(recallIndexerProvider).total, 1);
      await indexer.run();
      expect(container.read(recallIndexerProvider).total, 0);

      final retriever = HybridRetriever(
        index: index,
        embedder: CompanionTextEmbedder(computer: () => computer),
        capability: capability,
        enabled: preference.enabled,
      );
      final all = [...sources, ...notes];
      Future<RecallResult> search(String q) => retriever.search(
        q,
        sources: all,
        kinds: const {RecallKind.diary, RecallKind.note},
      );
      final latencies = <String, int>{};
      final tops = <String, List<String>>{};
      for (final q in [
        'when was I anxious',
        'Amina',
        'nilikuwa na wasiwasi',
        'dentist',
        'job interview',
      ]) {
        watch = Stopwatch()..start();
        final r = await search(q);
        latencies[q] = watch.elapsedMilliseconds;
        tops[q] = [for (final h in r.hits.take(4)) h.source.id];
        expect(r.semantic, isTrue, reason: q);
      }
      report['queryMs'] = latencies;
      report['top'] = tops;
      // Meaning finds what keywords miss; exact names stay first.
      expect(
        tops['when was I anxious']!.take(3).toSet(),
        containsAll(['nervous', 'sleep']),
      );
      expect(tops['Amina']!.first, 'amina');
      expect(tops['dentist']!.first, 'dentist');

      // Offline fallback: no capability means keyword ranking, labelled.
      final offline = await HybridRetriever(
        index: index,
        embedder: CompanionTextEmbedder(computer: () => computer),
        capability: null,
        enabled: preference.enabled,
      ).search('Amina', sources: all, kinds: const {RecallKind.diary});
      expect(offline.semantic, isFalse);
      expect(offline.fallback, startsWith('Keyword results'));
      expect(offline.hits.first.source.id, 'amina');

      // Interrupted indexing: pause, then resume picks up the rest.
      index.clear(RecallKind.diary);
      indexer.pause();
      await indexer.run();
      expect(index.count(RecallKind.diary, capability.model), 0);
      indexer.resume();
      await indexer.run();
      expect(index.count(RecallKind.diary, capability.model), _entries.length);

      // Opting out deletes that collection's vectors at once.
      await indexer.setEnabled(RecallKind.diary, false);
      expect(index.count(RecallKind.diary, capability.model), 0);
      expect(index.count(RecallKind.note, capability.model), 1);

      // ignore: avoid_print
      print('S03B_REPORT ${jsonEncode(report)}');
    },
  );
}
