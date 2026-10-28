import 'package:journal/utils/time_helper.dart';
import 'package:journal/modules/diary/history/diary_retrieval.dart';
import 'package:journal/modules/diary/models/diary_day_entity.dart';
import 'package:journal/modules/diary/models/diary_search_result.dart';
import 'package:journal/modules/recall/hybrid_retriever.dart';
import 'package:journal/modules/recall/recall_contract.dart';
import 'package:journal/objectbox/objectbox.dart';

abstract interface class DiarySearchService {
  Future<DiarySearchResult> search(String query);
}

/// S03b: searches every saved diary entry up to [lastDate] with the shared
/// hybrid retriever — by meaning when this phone has opted in and the
/// computer is ready, by keyword otherwise (and then labelled as such).
class HybridDiarySearchService implements DiarySearchService {
  HybridDiarySearchService({
    required DateTime lastDate,
    List<DiaryDayEntity>? diaries,
    HybridRetriever? retriever,
  }) : lastDate = TimeHelper.dateOnly(lastDate),
       _diaries = diaries == null ? null : List.unmodifiable(diaries),
       retriever = retriever ?? HybridRetriever.keywordOnly();

  final DateTime lastDate;
  final List<DiaryDayEntity>? _diaries;
  final HybridRetriever retriever;
  List<DiaryDayEntity> get diaries => _diaries ?? objectbox.diaryBox.getAll();

  static const resultLimit = 5;

  @override
  Future<DiarySearchResult> search(String query) async {
    if (diaryTerms(query).isEmpty && query.trim().runes.length < 3) {
      return const DiarySearchResult(answer: '', matches: []);
    }
    final days = {for (final d in diaries) d.dateString: d};
    final result = await retriever.search(
      query,
      sources: RecallSource.diary(days.values),
      kinds: const {RecallKind.diary},
      to: civilKey(lastDate),
      limit: 200,
    );
    // A passage written on several days appears once, at its best rank,
    // dated by its newest source.
    final newest = <String, RecallSource>{};
    for (final hit in result.hits) {
      final seen = newest[hit.source.full];
      if (seen == null || hit.source.date.compareTo(seen.date) > 0) {
        newest[hit.source.full] = hit.source;
      }
    }
    final matches = <DiarySearchMatch>[
      for (final source in newest.values.take(resultLimit))
        DiarySearchMatch(
          date: TimeHelper.dateOnly(civil(source.date)),
          title: days[source.date]?.dayTitle?.trim() ?? '',
          excerpt: source.full,
        ),
    ];
    if (matches.isEmpty) {
      return DiarySearchResult(
        answer: '',
        matches: const [],
        note: result.fallback,
      );
    }
    final first = matches.first;
    final sentence = first.excerpt.split(RegExp(r'(?<=[.!?])\s+')).first;
    return DiarySearchResult(
      answer: first.title.isEmpty
          ? 'You wrote: “$sentence”'
          : 'In “${first.title}”, you wrote: “$sentence”',
      matches: matches,
      note: result.fallback,
    );
  }
}
