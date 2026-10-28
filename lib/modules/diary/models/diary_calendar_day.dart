import 'dart:convert';

import 'package:journal/modules/diary/models/diary_day_entity.dart';

enum DiaryCalendarMood {
  happy('Happy', '😊'),
  calm('Calm', '😌'),
  excited('Excited', '🤩'),
  tired('Tired', '😴'),
  low('Low', '😔');

  const DiaryCalendarMood(this.label, this.emoji);

  final String label;
  final String emoji;
}

/// Lightweight, read-only calendar metadata, independent of diary sheet content.
class DiaryCalendarDay {
  const DiaryCalendarDay({required this.hasEntry, this.mood})
    : assert(hasEntry || mood == null);

  final bool hasEntry;
  final DiaryCalendarMood? mood;

  factory DiaryCalendarDay.fromEntity(DiaryDayEntity? day) {
    if (day == null || day.displayItems.isEmpty) {
      return const DiaryCalendarDay(hasEntry: false);
    }
    DiaryCalendarMood? mood;
    try {
      final decoded = jsonDecode(day.dayMood ?? 'null');
      if (decoded is Map<String, dynamic>) {
        for (final candidate in DiaryCalendarMood.values) {
          if (decoded['category'] == candidate.name ||
              decoded['name'] == candidate.label) {
            mood = candidate;
            break;
          }
        }
      }
    } on FormatException {
      // A malformed optional mood should not hide the day's entry marker.
    }
    return DiaryCalendarDay(hasEntry: true, mood: mood);
  }

  static DiaryCalendarDay empty(DateTime date) =>
      const DiaryCalendarDay(hasEntry: false);
}
