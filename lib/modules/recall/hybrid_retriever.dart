import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journal/modules/diary/history/diary_retrieval.dart';
import 'package:journal/modules/recall/recall_contract.dart';
import 'package:journal/modules/recall/recall_embedder.dart';
import 'package:journal/modules/recall/recall_index.dart';
import 'package:journal/modules/recall/recall_indexer.dart';

/// One ranked source. [keyword] and [meaning] say which signals found it.
class RecallHit {
  const RecallHit(this.source, this.score, {this.keyword = 0, this.meaning});
  final RecallSource source;
  final double score;

  /// Query terms matched; 0 when found by meaning alone.
  final int keyword;

  /// Cosine distance of the vector match, or null.
  final double? meaning;
}

class RecallResult {
  const RecallResult(this.hits, {required this.semantic, this.fallback});
  final List<RecallHit> hits;

  /// Whether vector search contributed. False means keyword-only ranking.
  final bool semantic;

  /// Why ranking fell back to keywords, for labelling results.
  final String? fallback;
}

/// Reciprocal-rank-fusion constant and the extra weight that keeps exact
/// keyword matches (names, places) above purely semantic neighbours.
const _rrfK = 60;
const _keywordWeight = 1.2;

/// Keyword score of [source] for [terms]: how many query terms its text
/// contains. The last term also matches as a prefix, for typing searches.
int keywordScore(RecallSource source, Set<String> terms, {String? last}) {
  if (terms.isEmpty) return 0;
  final words = diaryTerms('${source.context} ${source.full}');
  var score = 0;
  for (final t in terms) {
    if (words.contains(t) ||
        (t == last &&
            t.runes.length >= 2 &&
            words.any((w) => w.startsWith(t)))) {
      score++;
    }
  }
  return score;
}

/// S03b: one retriever for diary, notes and Flow. Keyword ranking always
/// runs on the phone; when the paired computer has an embedding model and
/// the collection is opted in, the query is embedded there and the nearest
/// stored vectors are fused with the keyword ranking.
class HybridRetriever {
  HybridRetriever({
    required this.index,
    required this.embedder,
    required this.capability,
    required this.enabled,
  });

  /// Keyword ranking only, for screens without the companion.
  HybridRetriever.keywordOnly()
    : index = null,
      embedder = null,
      capability = null,
      enabled = const {};
  final RecallIndex? index;
  final TextEmbedder? embedder;
  final EmbeddingCapability? capability;
  final Set<RecallKind> enabled;

  static final _queries = <String, List<double>>{};

  Future<List<double>> _queryVector(String model, String query) async {
    final key = '$model\n$query';
    final cached = _queries.remove(key);
    if (cached != null) return _queries[key] = cached;
    final vector = (await embedder!.embed(model, [
      EmbedItem('query', 'query', boundedEmbedText(query)),
    ]))['query']!;
    if (_queries.length >= 16) _queries.remove(_queries.keys.first);
    return _queries[key] = vector;
  }

  static Map<String, RecallSource> _pool(
    Iterable<RecallSource> sources,
    Set<RecallKind> kinds,
    String? from,
    String? to,
  ) => {
    for (final s in sources)
      if (kinds.contains(s.kind) &&
          (from == null || s.date.compareTo(from) >= 0) &&
          (to == null || s.date.compareTo(to) <= 0))
        s.key: s,
  };

  /// Keyword matches in [pool], best first, newer breaking ties.
  static List<(String, int)> _keywordRanked(
    String query,
    Map<String, RecallSource> pool,
    Set<String>? terms,
  ) {
    final words = terms ?? diaryTerms(query);
    final typed = RegExp(
      r'[\p{L}\p{N}]+$',
      unicode: true,
    ).firstMatch(query.trim().toLowerCase())?[0];
    final last = typed == null ? null : diaryTerms(typed).firstOrNull;
    return [
      for (final s in pool.values)
        if (keywordScore(s, words, last: last) case final k when k > 0)
          (s.key, k),
    ]..sort((a, b) {
      final s = b.$2.compareTo(a.$2);
      return s != 0 ? s : pool[b.$1]!.date.compareTo(pool[a.$1]!.date);
    });
  }

  /// Immediate keyword-only ranking, for showing results while typing.
  static List<RecallHit> keywordHits(
    String query, {
    required Iterable<RecallSource> sources,
    required Set<RecallKind> kinds,
    int limit = 20,
  }) {
    final pool = _pool(sources, kinds, null, null);
    return [
      for (final (i, (key, k)) in _keywordRanked(
        query,
        pool,
        null,
      ).take(limit).indexed)
        RecallHit(pool[key]!, _keywordWeight / (_rrfK + i + 1), keyword: k),
    ];
  }

  /// Ranks [sources] for [query]. [terms] defaults to the query's words;
  /// history questions pass them without their date phrase. [from]/[to]
  /// are inclusive civil dates.
  Future<RecallResult> search(
    String query, {
    required Iterable<RecallSource> sources,
    required Set<RecallKind> kinds,
    Set<String>? terms,
    String? from,
    String? to,
    int limit = 20,
  }) async {
    final pool = _pool(sources, kinds, from, to);
    final keywordList = _keywordRanked(query, pool, terms);
    final keyword = {for (final (key, k) in keywordList) key: k};
    final keywordRanked = [for (final (key, _) in keywordList) key];

    final model = capability?.model;
    final searchable = kinds.intersection(enabled);
    String? fallback;
    var meaning = <String, double>{};
    if (query.trim().isEmpty) {
      fallback = null;
    } else if (model == null) {
      fallback = 'Keyword results · connect your computer with its embedding model to search by meaning.';
    } else if (searchable.isEmpty) {
      fallback = 'Keyword results · turn on search by meaning in Settings → Local QVAC.';
    } else {
      try {
        final vector = await _queryVector(model, query.trim());
        meaning = {
          for (final n in index!.nearest(
            vector,
            model,
            kinds: searchable,
            limit: limit * 2,
            from: from,
            to: to,
          ))
            if (pool.containsKey('${n.kind.name}:${n.sourceId}'))
              '${n.kind.name}:${n.sourceId}': n.distance,
        };
      } catch (_) {
        fallback = 'Keyword results · your computer could not search by meaning just now.';
      }
    }
    final scores = <String, double>{};
    for (final (i, key) in keywordRanked.indexed) {
      scores[key] = _keywordWeight / (_rrfK + i + 1);
    }
    for (final (i, key) in meaning.keys.indexed) {
      scores[key] = (scores[key] ?? 0) + 1 / (_rrfK + i + 1);
    }
    final ranked = scores.keys.toList()
      ..sort((a, b) {
        final s = scores[b]!.compareTo(scores[a]!);
        return s != 0 ? s : pool[b]!.date.compareTo(pool[a]!.date);
      });
    return RecallResult(
      [
        for (final key in ranked.take(limit))
          RecallHit(
            pool[key]!,
            scores[key]!,
            keyword: keyword[key] ?? 0,
            meaning: meaning[key],
          ),
      ],
      semantic: fallback == null && meaning.isNotEmpty,
      fallback: fallback,
    );
  }
}

final hybridRetrieverProvider = Provider<HybridRetriever>(
  (ref) => HybridRetriever(
    index: ref.watch(recallIndexProvider),
    embedder: ref.watch(recallEmbedderProvider),
    capability: ref.watch(recallCapabilityProvider),
    enabled: ref.watch(recallIndexerProvider.select((s) => s.enabled)),
  ),
);
