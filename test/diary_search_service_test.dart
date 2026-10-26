import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/diary/controllers/diary_search_service.dart';
import 'package:journal/modules/diary/models/diary_day.dart';

void main() {
  final today = DateTime(2026, 10, 26);
  final service = SampleDiarySearchService(lastDate: today);

  test('suggested concepts find the corresponding sample passages', () async {
    for (final example in [
      ('When did I feel calm?', 'A little more present'),
      ('That walk I wrote about', 'Taking the long way'),
      ('A conversation worth keeping', 'A conversation to keep'),
    ]) {
      final result = await service.search(example.$1);
      expect(result.matches, isNotEmpty);
      expect(result.matches.first.title, example.$2);
      expect(result.answer, contains(example.$2));
      expect(
        result.answer,
        contains(result.matches.first.excerpt.split('. ').first),
      );
    }
  });

  test(
    'blank, filler-only, and unknown queries return no fabricated answer',
    () async {
      for (final query in [
        '',
        '   ',
        'what did I write about?',
        'submarine zeppelin',
      ]) {
        final result = await service.search(query);
        expect(result.matches, isEmpty);
        expect(result.answer, isEmpty);
      }
    },
  );

  test(
    'free text is case insensitive and results are capped and deduplicated',
    () async {
      final result = await service.search(
        'CALM walk conversation rain coffee space room',
      );
      expect(result.matches.length, 5);
      expect(result.matches.map((match) => match.excerpt).toSet().length, 5);
      final again = await service.search(
        'calm walk conversation rain coffee space room',
      );
      expect(
        again.matches.map((match) => match.title),
        result.matches.map((match) => match.title),
      );
      expect(again.answer, result.answer);
    },
  );

  test('every excerpt exists on its latest source day in the 30 day window', () async {
    // Exercise month, year, and leap-day boundaries with a non-midnight input.
    for (final last in [DateTime(2026, 1, 2, 23), DateTime(2024, 3, 1, 17)]) {
      final search = SampleDiarySearchService(lastDate: last);
      final result = await search.search(
        'calm walk conversation rain coffee space room intentions',
      );
      final normalized = diaryDate(last);
      for (final match in result.matches) {
        expect(match.date, diaryDate(match.date));
        expect(match.date.isAfter(normalized), isFalse);
        expect(diaryDaysBetween(match.date, normalized), lessThan(30));
        String passage(DiaryItem item) => item.text.isNotEmpty
            ? item.text
            : item.tasks.map((task) => task.text).join('\n');
        bool contains(DateTime date) => DiaryDay.sample(date).items.any(
          (item) =>
              item.kind == match.kind &&
              item.title == match.title &&
              passage(item) == match.excerpt,
        );
        expect(contains(match.date), isTrue);
        for (
          var date = diaryDayAfter(match.date, 1);
          !date.isAfter(normalized);
          date = diaryDayAfter(date, 1)
        ) {
          expect(
            contains(date),
            isFalse,
            reason: 'Repeated sample must keep its newest source',
          );
        }
      }
    }
  });

  test('checklist retrieval retains the source task text', () async {
    final result = await service.search('intentions');
    expect(result.matches.single.kind, DiaryItemKind.checklist);
    expect(
      result.matches.single.excerpt,
      contains('Step outside for a little while'),
    );
  });
}
