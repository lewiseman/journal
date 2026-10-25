import 'package:journal/modules/diary/models/diary_day.dart';

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

  /// Preview data is tied to civil dates, never the current viewport or clock.
  /// Empty days and entries without a mood deliberately remain in the mix.
  static DiaryCalendarDay sample(DateTime date) {
    final seed = diaryDaysBetween(DateTime(1970), date);
    final bucket = (seed * 17 + 23) % 19;
    if (const [1, 4, 9, 13, 18].contains(bucket)) {
      return const DiaryCalendarDay(hasEntry: false);
    }
    return DiaryCalendarDay(
      hasEntry: true,
      mood: bucket % 4 == 0
          ? null
          : DiaryCalendarMood.values[bucket % DiaryCalendarMood.values.length],
    );
  }
}
