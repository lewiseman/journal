/// Shared diary retrieval: civil dates, date scopes, which items count as
/// sendable text, and word normalization. Used by S01 historical answers and
/// J02 daily questions so both select diary content the same way.
library;

import 'package:journal/modules/diary/models/diary_day_entity.dart';
import 'package:journal/modules/diary/models/diary_item.dart';

final _unsendable = RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]');

/// True for text the companion accepts: no control characters but tab and
/// line breaks.
bool sendableText(String text) =>
    text.trim().isNotEmpty && !_unsendable.hasMatch(text);

/// A day's visible text entries, newest first. Photo-only items and text the
/// companion would reject are left out.
List<DiaryItem> diaryTextItems(DiaryDayEntity? day) =>
    (day?.visibleItems ?? const <DiaryItem>[])
        .where((i) => sendableText(i.content))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

DateTime civil(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2]);
}

String civilKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

const _months = {
  'january': 1,
  'jan': 1,
  'february': 2,
  'feb': 2,
  'march': 3,
  'mar': 3,
  'april': 4,
  'apr': 4,
  'may': 5,
  'june': 6,
  'jun': 6,
  'july': 7,
  'jul': 7,
  'august': 8,
  'aug': 8,
  'september': 9,
  'sep': 9,
  'sept': 9,
  'october': 10,
  'oct': 10,
  'november': 11,
  'nov': 11,
  'december': 12,
  'dec': 12,
};
const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
String _readable(DateTime d) =>
    '${d.day} ${_monthNames[d.month - 1]} ${d.year}';

/// A civil date range resolved from the user's words, relative to their
/// current civil date. English phrases only.
class DiaryDateScope {
  const DiaryDateScope(this.from, this.to, this.phrase);
  final DateTime from, to;

  /// The words that set this scope, removed before keyword matching.
  final String phrase;

  String get label =>
      from == to ? _readable(from) : '${_readable(from)} – ${_readable(to)}';

  bool contains(DateTime day) => !day.isBefore(from) && !day.isAfter(to);

  /// The [days] civil days before [today], excluding today.
  factory DiaryDateScope.previousDays(DateTime today, int days) {
    final t = DateTime.utc(today.year, today.month, today.day);
    return DiaryDateScope(
      t.subtract(Duration(days: days)),
      t.subtract(const Duration(days: 1)),
      'the past $days days',
    );
  }

  /// Civil date keys in this scope, newest first.
  Iterable<String> get keysNewestFirst sync* {
    for (
      var d = to;
      !d.isBefore(from);
      d = d.subtract(const Duration(days: 1))
    ) {
      yield civilKey(d);
    }
  }

  Map<String, String> toJson() => {'from': civilKey(from), 'to': civilKey(to)};

  static DateTime _monthEnd(int year, int month) =>
      DateTime.utc(year, month + 1, 0);

  /// Returns null when the question names no time: all history is searched.
  static DiaryDateScope? parse(String question, DateTime today) {
    final t = DateTime.utc(today.year, today.month, today.day);
    final q = question.toLowerCase();
    DiaryDateScope clamp(DateTime from, DateTime to, String phrase) =>
        DiaryDateScope(from, to.isAfter(t) ? t : to, phrase);
    RegExpMatch? m;
    const numbers = {
      'a': 1,
      'one': 1,
      'two': 2,
      'three': 3,
      'four': 4,
      'five': 5,
      'six': 6,
    };
    int? count(String v) => int.tryParse(v) ?? numbers[v];

    if ((m = RegExp(
          r'\b(?:(?:around|about|at)\s+)?this time (?:last year|(\w+) years? ago)\b',
        ).firstMatch(q)) !=
        null) {
      final years = m!.group(1) == null ? 1 : count(m.group(1)!) ?? 1;
      final anchor = DateTime.utc(t.year - years, t.month, t.day);
      return clamp(
        anchor.subtract(const Duration(days: 14)),
        anchor.add(const Duration(days: 14)),
        m.group(0)!,
      );
    }
    if ((m = RegExp(r'\b(\w+) (day|week|month|year)s? ago\b').firstMatch(q)) !=
        null) {
      final n = count(m!.group(1)!);
      if (n != null) {
        switch (m.group(2)) {
          case 'day':
            final d = t.subtract(Duration(days: n));
            return clamp(
              d.subtract(const Duration(days: 1)),
              d.add(const Duration(days: 1)),
              m.group(0)!,
            );
          case 'week':
            final d = t.subtract(Duration(days: 7 * n));
            return clamp(
              d.subtract(const Duration(days: 3)),
              d.add(const Duration(days: 3)),
              m.group(0)!,
            );
          case 'month':
            final first = DateTime.utc(t.year, t.month - n, 1);
            return clamp(
              first,
              _monthEnd(first.year, first.month),
              m.group(0)!,
            );
          case 'year':
            return clamp(
              DateTime.utc(t.year - n, 1, 1),
              DateTime.utc(t.year - n, 12, 31),
              m.group(0)!,
            );
        }
      }
    }
    if ((m = RegExp(r'\byesterday\b').firstMatch(q)) != null) {
      final d = t.subtract(const Duration(days: 1));
      return DiaryDateScope(d, d, m!.group(0)!);
    }
    if ((m = RegExp(r'\b(last|this|past) (week|month|year)\b').firstMatch(q)) !=
        null) {
      final last = m!.group(1) != 'this';
      switch (m.group(2)) {
        case 'week':
          final monday = t.subtract(Duration(days: t.weekday - 1));
          return last
              ? DiaryDateScope(
                  monday.subtract(const Duration(days: 7)),
                  monday.subtract(const Duration(days: 1)),
                  m.group(0)!,
                )
              : DiaryDateScope(monday, t, m.group(0)!);
        case 'month':
          final first = DateTime.utc(t.year, last ? t.month - 1 : t.month, 1);
          return clamp(first, _monthEnd(first.year, first.month), m.group(0)!);
        case 'year':
          final year = last ? t.year - 1 : t.year;
          return clamp(
            DateTime.utc(year, 1, 1),
            DateTime.utc(year, 12, 31),
            m.group(0)!,
          );
      }
    }
    final monthPattern = _months.keys.join('|');
    if ((m = RegExp('\\b($monthPattern)\\b(?:\\s+(\\d{4}))?').firstMatch(q)) !=
            null &&
        // "may" alone is too often a verb.
        (m!.group(1) != 'may' || m.group(2) != null)) {
      final month = _months[m.group(1)]!;
      var year = m.group(2) == null ? t.year : int.parse(m.group(2)!);
      if (m.group(2) == null && month > t.month) year--;
      return clamp(
        DateTime.utc(year, month, 1),
        _monthEnd(year, month),
        m.group(0)!,
      );
    }
    if ((m = RegExp(r'\b(?:in )?((?:19|20)\d{2})\b').firstMatch(q)) != null) {
      final year = int.parse(m!.group(1)!);
      if (year <= t.year) {
        return clamp(
          DateTime.utc(year, 1, 1),
          DateTime.utc(year, 12, 31),
          m.group(0)!,
        );
      }
    }
    return null;
  }
}

const _stopWords = {
  'like',
  'would',
  'one',
  'out',
  'a',
  'about',
  'after',
  'again',
  'all',
  'an',
  'and',
  'any',
  'are',
  'around',
  'as',
  'at',
  'be',
  'been',
  'before',
  'can',
  'could',
  'day',
  'days',
  'did',
  'diary',
  'do',
  'does',
  'doing',
  'during',
  'entry',
  'entries',
  'ever',
  'first',
  'for',
  'from',
  'get',
  'go',
  'going',
  'got',
  'had',
  'has',
  'have',
  'how',
  'i',
  'if',
  'in',
  'into',
  'is',
  'it',
  'journal',
  'just',
  'last',
  'me',
  'mention',
  'mentioned',
  'my',
  'of',
  'on',
  'or',
  'remember',
  'said',
  'say',
  'since',
  'so',
  'some',
  'start',
  'started',
  'tell',
  'that',
  'the',
  'then',
  'there',
  'this',
  'time',
  'to',
  'up',
  'was',
  'were',
  'what',
  'when',
  'where',
  'which',
  'who',
  'why',
  'with',
  'write',
  'wrote',
  'written',
  'you',
  'your',
  'ago',
  'week',
  'weeks',
  'month',
  'months',
  'year',
  'years',
  'yesterday',
  'today',
  'lately',
  'recently',
};

// Crude English stemming so "noticed", "notice" and "notices" compare equal.
String _stem(String word) {
  for (final suffix in ['ing', 'ed', 'es', 's', 'e']) {
    // "class" keeps its "s" so it matches "classes" → "class".
    if (suffix == 's' && word.endsWith('ss')) continue;
    if (word.length > suffix.length + 3 && word.endsWith(suffix)) {
      return word.substring(0, word.length - suffix.length);
    }
  }
  return word;
}

/// Unicode words, lowercased, without English stop words, contractions
/// ("what's" → "what") or short words, lightly stemmed. Non-English text
/// matches exact word forms only.
Set<String> diaryTerms(String value) => {
  for (final m in RegExp(
    r"[\p{L}\p{N}]+(?:['’][\p{L}]+)?",
    unicode: true,
  ).allMatches(value.toLowerCase()))
    if (m[0]!.replaceAll(RegExp(r"['’](s|re|ll|ve|d|t|m)$"), '') case final w
        when w.runes.length >= 2 && !_stopWords.contains(w))
      _stem(w),
};
