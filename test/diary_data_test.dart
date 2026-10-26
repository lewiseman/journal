import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/diary/models/diary_calendar_day.dart';
import 'package:journal/utils/time_helper.dart';
import 'package:journal/modules/diary/models/diary_day_entity.dart';
import 'package:journal/modules/diary/models/diary_item.dart';
import 'package:journal/modules/diary/models/sample.dart';

void main() {
  final today = DateTime(2026, 10, 26);

  test('sample data is deterministic with unique civil dates and item IDs', () {
    final days = buildSampleDiaries(today);
    final again = buildSampleDiaries(DateTime(2026, 10, 26, 23, 59));
    expect(
      days.map((day) => day.toSyncJson('sample')),
      again.map((day) => day.toSyncJson('sample')),
    );
    expect(days.map((day) => day.dateString).toSet().length, days.length);
    expect(days.first.calendarDate, today);
    expect(days.last.calendarDate, TimeHelper.addDays(today, -29));
    expect(days.length, lessThan(30));
    final items = days.expand((day) => day.items).toList();
    expect(items.map((item) => item.itemUuid).toSet().length, items.length);
    expect(items.every((item) => item.content.trim().isNotEmpty), isTrue);
    expect(items.any((item) => item.content.contains('\n\n')), isTrue);
    expect(days.map((day) => day.items.length).toSet().length, 3);
    for (final day in days) {
      expect(day.date.isUtc, isTrue);
      expect(day.date.hour, 0);
      expect(TimeHelper.dateKey(day.date), day.dateString);
      expect(
        TimeHelper.daysBetween(day.calendarDate, today),
        inInclusiveRange(0, 29),
      );
    }
  });

  test('sample builder crosses year and leap-day boundaries', () {
    for (final anchor in [DateTime(2026, 1, 2), DateTime(2024, 3, 1)]) {
      final days = buildSampleDiaries(anchor);
      expect(days.first.calendarDate, anchor);
      expect(days.last.calendarDate, TimeHelper.addDays(anchor, -29));
      expect(days[1].calendarDate, TimeHelper.addDays(anchor, -1));
    }
    expect(
      buildSampleDiaries(DateTime(2024, 3, 1))[1].dateString,
      '2024-02-29',
    );
    expect(TimeHelper.dateKey(DateTime(1, 2, 3)), '0001-02-03');
  });

  test('item and day serialization preserve content and existing fields', () {
    final item = DiaryItem(
      itemUuid: 'item-1',
      createdAt: DateTime.utc(2026, 10, 26, 8),
      updatedAt: DateTime.utc(2026, 10, 26, 9),
      content: 'First paragraph.\n\nSecond paragraph.',
      mood: 'calm',
      attachmentPaths: ['photo.jpg'],
      deviceId: 'sample-device',
      isDeleted: true,
    );
    expect(DiaryItem.fromJson(item.toJson()).toJson(), item.toJson());
    final day = DiaryDayEntity(
      dateString: '2026-10-26',
      dayTitle: 'A quiet day',
      daySummary: 'A short summary',
      dayMood: jsonEncode({'emoji': '😌', 'name': 'Calm', 'category': 'calm'}),
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
      lastEditedByDeviceId: 'sample-device',
    )..items = [item];
    expect(day.items.single.toJson(), item.toJson());
    final sync = day.toSyncJson('Sample device');
    expect(DiaryDayEntity.fromSyncJson(sync).toSyncJson('Sample device'), sync);
  });

  test(
    'calendar derives entry state and every mood from the sample entities',
    () {
      final days = buildSampleDiaries(today);
      final metadata = days.map(DiaryCalendarDay.fromEntity).toList();
      expect(metadata.every((day) => day.hasEntry), isTrue);
      expect(metadata.any((day) => day.mood == null), isTrue);
      expect(
        metadata.map((day) => day.mood).nonNulls.toSet(),
        DiaryCalendarMood.values.toSet(),
      );
      expect(DiaryCalendarDay.fromEntity(null).hasEntry, isFalse);
      for (final day in sampleDiaries) {
        final actual = DiaryCalendarDay.sample(day.calendarDate);
        final expected = DiaryCalendarDay.fromEntity(day);
        expect(actual.hasEntry, expected.hasEntry);
        expect(actual.mood, expected.mood);
      }
    },
  );

  test('calendar ignores invalid moods and days without visible prose', () {
    final day = buildSampleDiaries(today).first;
    for (final mood in [
      null,
      '',
      'broken json',
      '[]',
      '42',
      '{}',
      '{"name": 123}',
      '{"category": "unknown"}',
    ]) {
      day.dayMood = mood;
      final metadata = DiaryCalendarDay.fromEntity(day);
      expect(metadata.hasEntry, isTrue);
      expect(metadata.mood, isNull);
    }
    day.dayMood = '{"category":"calm"}';
    expect(DiaryCalendarDay.fromEntity(day).mood, DiaryCalendarMood.calm);
    day.items = day.items
        .map((item) => item.copyWith(isDeleted: true))
        .toList();
    expect(DiaryCalendarDay.fromEntity(day).hasEntry, isFalse);
    day.items = [day.items.first.copyWith(isDeleted: false, content: ' \n ')];
    expect(DiaryCalendarDay.fromEntity(day).hasEntry, isFalse);
    day.items = [day.items.first.copyWith(content: 'Visible words.')];
    day.isDeleted = true;
    expect(DiaryCalendarDay.fromEntity(day).hasEntry, isFalse);
  });
}
