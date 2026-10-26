import 'package:journal/modules/diary/models/diary_day.dart';
import 'package:journal/modules/diary/models/diary_search_result.dart';

abstract interface class DiarySearchService {
  Future<DiarySearchResult> search(String query);
}

/// Read-only preview retrieval, with no network, storage, or generated claims.
/// Replace this adapter when real diary retrieval and AI are available.
class SampleDiarySearchService implements DiarySearchService {
  SampleDiarySearchService({required DateTime lastDate})
    : lastDate = diaryDate(lastDate);

  final DateTime lastDate;

  static const _stopWords = {
    'a',
    'about',
    'an',
    'and',
    'are',
    'as',
    'at',
    'be',
    'been',
    'can',
    'could',
    'day',
    'days',
    'did',
    'do',
    'does',
    'entry',
    'entries',
    'feel',
    'feeling',
    'felt',
    'find',
    'for',
    'from',
    'had',
    'has',
    'have',
    'how',
    'i',
    'in',
    'is',
    'it',
    'journal',
    'keeping',
    'last',
    'little',
    'me',
    'moment',
    'moments',
    'my',
    'of',
    'on',
    'or',
    'remember',
    'search',
    'show',
    'some',
    'something',
    'that',
    'the',
    'there',
    'these',
    'things',
    'this',
    'to',
    'was',
    'were',
    'what',
    'when',
    'where',
    'which',
    'with',
    'worth',
    'would',
    'write',
    'writing',
    'wrote',
    'you',
  };
  static const _concepts = [
    {'calm', 'quiet', 'peace', 'peaceful', 'present', 'wonder'},
    {'walk', 'walked', 'walking', 'route', 'garden', 'scenery', 'outside'},
    {
      'conversation',
      'conversations',
      'talk',
      'talked',
      'talking',
      'understood',
    },
  ];

  static Set<String> _words(String value) =>
      RegExp(r'[a-z0-9]+')
          .allMatches(value.toLowerCase())
          .map((match) => match.group(0)!)
          .toSet();

  @override
  Future<DiarySearchResult> search(String query) async {
    final terms = _words(query).difference(_stopWords);
    if (terms.isEmpty) {
      return const DiarySearchResult(answer: '', matches: []);
    }
    final expanded = {
      ...terms,
      for (final concept in _concepts)
        if (concept.intersection(terms).isNotEmpty) ...concept,
    };
    final unique = <String, ({DiarySearchMatch match, int score})>{};
    for (var offset = 0; offset < 30; offset++) {
      final day = DiaryDay.sample(diaryDayAfter(lastDate, -offset));
      for (final item in day.items) {
        final excerpt = item.text.isNotEmpty
            ? item.text
            : item.tasks.map((task) => task.text).join('\n');
        final words = _words('${item.title} $excerpt');
        final score =
            terms.intersection(words).length * 3 +
            expanded.intersection(words).length;
        if (score == 0) continue;
        final identity = '${item.kind.name}\n${item.title}\n$excerpt';
        // Newest-first traversal keeps the latest source of repeated samples.
        unique.putIfAbsent(
          identity,
          () => (
            match: DiarySearchMatch(
              date: day.date,
              title: item.title,
              excerpt: excerpt,
              kind: item.kind,
            ),
            score: score,
          ),
        );
      }
    }
    final ranked = unique.values.toList()
      ..sort((a, b) {
        final score = b.score.compareTo(a.score);
        return score != 0 ? score : b.match.date.compareTo(a.match.date);
      });
    final matches = List<DiarySearchMatch>.unmodifiable(
      ranked.take(5).map((item) => item.match),
    );
    if (matches.isEmpty) {
      return const DiarySearchResult(answer: '', matches: []);
    }
    final first = matches.first;
    final sentence = first.excerpt.split(RegExp(r'(?<=[.!?])\s+')).first;
    return DiarySearchResult(
      answer: 'In “${first.title}”, you wrote: “$sentence”',
      matches: matches,
    );
  }
}
