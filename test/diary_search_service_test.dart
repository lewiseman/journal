import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/diary/controllers/diary_search_service.dart';
import 'package:journal/utils/time_helper.dart';
import 'package:journal/modules/diary/models/diary_day_entity.dart';
import 'package:journal/modules/diary/models/diary_item.dart';

import 'support/sample_diaries.dart';

DiaryDayEntity _day(DateTime date, String content, {String? title}) =>
    DiaryDayEntity(dateString: TimeHelper.dateKey(date), dayTitle: title)
      ..items = [
        DiaryItem(
          itemUuid: TimeHelper.dateKey(date),
          createdAt: date,
          updatedAt: date,
          content: content,
        ),
      ];

void main() {
  final today = DateTime(2026, 10, 26);
  final diaries = buildSampleDiaries(today);
  final service = LocalDiarySearchService(lastDate: today, diaries: diaries);

  test('suggested concepts find the corresponding sample passages', () async {
    for (final example in [
      ('When did I feel calm?', 'I felt calm'),
      ('That walk I wrote about', 'on my walk'),
      ('A conversation worth keeping', 'our conversation'),
    ]) {
      final result = await service.search(example.$1);
      expect(result.matches, isNotEmpty);
      expect(result.matches.first.excerpt, contains(example.$2));
      expect(result.answer, contains(result.matches.first.title));
      expect(
        result.answer,
        contains(result.matches.first.excerpt.split('. ').first),
      );
    }
  });

  test('blank, filler-only, and unknown queries return no answer', () async {
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
  });

  test('free text is case insensitive, capped, and deduplicated', () async {
    final result = await service.search(
      'CALM walk conversation rain coffee space room',
    );
    expect(result.matches.length, 5);
    expect(result.matches.map((match) => match.excerpt).toSet().length, 5);
    final again = await service.search(
      'calm walk conversation rain coffee space room',
    );
    expect(
      again.matches.map((match) => match.excerpt),
      result.matches.map((match) => match.excerpt),
    );
    expect(again.answer, result.answer);
  });

  test('excerpts come from their newest source in the 30 day window', () async {
    for (final last in [DateTime(2026, 1, 2, 23), DateTime(2024, 3, 1, 17)]) {
      final source = buildSampleDiaries(last);
      final search = LocalDiarySearchService(lastDate: last, diaries: source);
      final result = await search.search(
        'calm walk conversation rain coffee space room',
      );
      expect(result.matches, isNotEmpty);
      for (final match in result.matches) {
        expect(match.date, TimeHelper.dateOnly(match.date));
        expect(
          TimeHelper.daysBetween(match.date, last),
          inInclusiveRange(0, 29),
        );
        final day = source.singleWhere(
          (day) => day.dateString == TimeHelper.dateKey(match.date),
        );
        expect(day.dayTitle, match.title);
        expect(
          day.visibleItems.any((item) => item.content.trim() == match.excerpt),
          isTrue,
        );
        expect(
          source
              .where((day) => day.calendarDate.isAfter(match.date))
              .any(
                (day) => day.visibleItems.any(
                  (item) => item.content.trim() == match.excerpt,
                ),
              ),
          isFalse,
        );
      }
    }
  });

  test(
    'injected data respects civil dates, deletions, blanks, and bounds',
    () async {
      final retained = _day(
        TimeHelper.addDays(today, -29),
        'copper at the boundary',
      );
      final keyed = _day(today, 'copper on the keyed day')
        ..date = DateTime.utc(2026, 10, 25, 23);
      final deletedDay = _day(
        TimeHelper.addDays(today, -1),
        'copper deleted day',
      )..isDeleted = true;
      final hiddenItems = _day(
        TimeHelper.addDays(today, -2),
        'copper deleted item',
      );
      hiddenItems.items = [
        hiddenItems.items.single.copyWith(isDeleted: true),
        hiddenItems.items.single.copyWith(itemUuid: 'blank', content: ' \n '),
      ];
      final result = await LocalDiarySearchService(
        lastDate: DateTime(2026, 10, 26, 23),
        diaries: [
          _day(TimeHelper.addDays(today, -30), 'copper too old'),
          _day(TimeHelper.addDays(today, 1), 'copper tomorrow'),
          retained,
          keyed,
          deletedDay,
          hiddenItems,
        ],
      ).search('copper');
      expect(result.matches.map((match) => match.excerpt), [
        'copper on the keyed day',
        'copper at the boundary',
      ]);
      expect(result.matches.first.date, today);
      expect(result.matches.first.title, isEmpty);
      expect(result.answer, 'You wrote: “copper on the keyed day”');
    },
  );

  test(
    'titles are searchable and matching content determines relevance',
    () async {
      final result = await LocalDiarySearchService(
        lastDate: today,
        diaries: [
          _day(today, 'A brief pause.', title: 'Copper'),
          _day(TimeHelper.addDays(today, -1), 'Copper garden flowers.'),
          _day(TimeHelper.addDays(today, -2), 'A garden bench.'),
        ],
      ).search('copper garden');
      expect(result.matches.first.excerpt, 'Copper garden flowers.');
      expect(result.matches.any((match) => match.title == 'Copper'), isTrue);
    },
  );

  test(
    'repeated content keeps its latest source even with different titles',
    () async {
      final latest = _day(today, 'A copper sunrise.', title: 'Today');
      final result = await LocalDiarySearchService(
        lastDate: today,
        diaries: [
          _day(
            TimeHelper.addDays(today, -2),
            'A copper sunrise.',
            title: 'Earlier',
          ),
          latest,
        ],
      ).search('copper');
      expect(result.matches.single.date, today);
      expect(result.matches.single.title, 'Today');
    },
  );

  test(
    'an explicitly empty collection does not fall back to samples',
    () async {
      final result = await LocalDiarySearchService(
        lastDate: today,
        diaries: [],
      ).search('calm');
      expect(result.matches, isEmpty);
      expect(result.answer, isEmpty);
    },
  );
}
