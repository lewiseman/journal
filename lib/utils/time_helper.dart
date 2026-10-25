import 'package:intl/intl.dart';

/// Reusable date and time patterns for TimeHelper.
///
/// For locale-specific date ordering, prefer an intl skeleton such as
/// DateFormat.yMMMd(locale) instead of a fixed pattern.
abstract final class TimeFormat {
  // Dates
  static const shortDate = 'd MMM yyyy';          // 16 Oct 2026
  static const longDate = 'd MMMM yyyy';         // 16 October 2026
  static const fullDate = 'EEEE, d MMMM yyyy';  // Friday, 16 October 2026
  static const numericDate = 'dd/MM/yyyy';      // 16/10/2026
  static const isoDate = 'yyyy-MM-dd';           // 2026-10-16
  static const monthDay = 'd MMM';              // 16 Oct
  static const monthYear = 'MMMM yyyy';         // October 2026
  static const month = 'MMMM';                  // October
  static const weekday = 'EEEE';               // Friday
  static const shortWeekday = 'EEE';            // Fri

  // Times
  static const time12 = 'h:mm a';               // 3:42 PM
  static const time24 = 'HH:mm';                // 15:42
  static const timeWithSeconds = 'HH:mm:ss';   // 15:42:00

  // Combined
  static const dateTime = 'd MMM yyyy, h:mm a';
  static const dateTime24 = 'yyyy-MM-dd HH:mm';
  static const fullDateTime = 'EEEE, d MMMM yyyy • h:mm a';
  static const storageDateTime = 'yyyy-MM-dd HH:mm:ss';
}

/// Formatting, parsing, comparisons and human-friendly relative dates.
///
/// Date formatting/parsing supports intl locales. Friendly/relative labels
/// (Today, Yesterday, "ago", etc.) are currently English-only.
abstract final class TimeHelper {
  // ------------------------------------------------------------
  // FORMATTING: DateTime -> String
  // ------------------------------------------------------------

  static String format(
    DateTime value, {
    String pattern = TimeFormat.shortDate,
    String? locale,
    bool toLocal = true,
  }) {
    return DateFormat(pattern, locale).format(
      toLocal ? value.toLocal() : value,
    );
  }

  static String now({
    String pattern = TimeFormat.dateTime,
    String? locale,
  }) {
    return format(DateTime.now(), pattern: pattern, locale: locale);
  }

  /// Format the same DateTime in several ways, keyed by your own labels.
  static Map<String, String> formatMany(
    DateTime value, {
    required Map<String, String> patterns,
    String? locale,
    bool toLocal = true,
  }) {
    return patterns.map(
      (label, pattern) => MapEntry(
        label,
        format(value, pattern: pattern, locale: locale, toLocal: toLocal),
      ),
    );
  }

  // ------------------------------------------------------------
  // PARSING: String -> DateTime
  // ------------------------------------------------------------

  /// Strict parsing: invalid/mismatching input throws FormatException.
  /// Without [utc], a date without timezone information is local time.
  static DateTime parse(
    String input, {
    String pattern = TimeFormat.storageDateTime,
    String? locale,
    bool utc = false,
  }) {
    return DateFormat(pattern, locale).parseStrict(input.trim(), utc);
  }

  /// Strict parsing that returns null for an invalid date/string.
  static DateTime? tryParse(
    String input, {
    String pattern = TimeFormat.storageDateTime,
    String? locale,
    bool utc = false,
  }) {
    return DateFormat(pattern, locale).tryParseStrict(input.trim(), utc);
  }

  /// Tries known patterns, then ISO 8601 including explicit timezone offsets.
  /// A date without a timezone is interpreted in the device's local zone.
  /// Ambiguous numeric dates use dd/MM/yyyy; supply your own patterns to change.
  static DateTime? parseAny(
    String input, {
    List<String> patterns = const [
      TimeFormat.storageDateTime,
      TimeFormat.dateTime24,
      TimeFormat.dateTime,
      TimeFormat.fullDateTime,
      TimeFormat.fullDate,
      TimeFormat.longDate,
      TimeFormat.shortDate,
      TimeFormat.numericDate,
      TimeFormat.isoDate,
      'yyyy-MM-dd HH:mm',
    ],
    String? locale,
  }) {
    final text = input.trim();
    if (text.isEmpty) return null;

    for (final pattern in patterns) {
      final parsed = tryParse(text, pattern: pattern, locale: locale);
      if (parsed != null) return parsed;
    }

    // DateTime.tryParse handles ISO timezone offsets (e.g. +03:00, Z),
    // which DateFormat's usual patterns do not handle reliably.
    // Guard against DateTime.parse normalizing impossible calendar days.
    if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(text) &&
        tryParse(
          text.substring(0, 10),
          pattern: TimeFormat.isoDate,
          utc: true,
        ) == null) {
      return null;
    }
    return DateTime.tryParse(text);
  }

  // ------------------------------------------------------------
  // RELATIVE TIME
  // ------------------------------------------------------------

  /// Examples: "moments ago", "5 minutes ago", "in 2 hours".
  /// Compact form: "now", "5m ago", "in 2h".
  /// Months and years are approximate elapsed-time units (30/365 days).
  static String timeAgo(
    DateTime value, {
    DateTime? now,
    bool short = false,
  }) {
    final current = now ?? DateTime.now();
    final difference = value.difference(current);
    final future = !difference.isNegative && difference != Duration.zero;
    final seconds = difference.inSeconds.abs();

    if (seconds < 60) {
      if (short) return 'now';
      return future ? 'in a moment' : 'moments ago';
    }

    late final int amount;
    late final String singular;
    late final String symbol;

    if (seconds < 3600) {
      amount = seconds ~/ 60;
      singular = 'minute';
      symbol = 'm';
    } else if (seconds < 86400) {
      amount = seconds ~/ 3600;
      singular = 'hour';
      symbol = 'h';
    } else if (seconds < 7 * 86400) {
      amount = seconds ~/ 86400;
      singular = 'day';
      symbol = 'd';
    } else if (seconds < 30 * 86400) {
      amount = seconds ~/ (7 * 86400);
      singular = 'week';
      symbol = 'w';
    } else if (seconds < 365 * 86400) {
      amount = seconds ~/ (30 * 86400);
      singular = 'month';
      symbol = 'mo';
    } else {
      amount = seconds ~/ (365 * 86400);
      singular = 'year';
      symbol = 'y';
    }

    if (short) {
      final label = '$amount$symbol';
      return future ? 'in $label' : '$label ago';
    }

    final label = '$amount $singular${amount == 1 ? '' : 's'}';
    return future ? 'in $label' : '$label ago';
  }

  // ------------------------------------------------------------
  // FRIENDLY DISPLAY
  // ------------------------------------------------------------

  /// "Today", "Yesterday", "Tomorrow", otherwise e.g. "16 Oct 2026".
  static String friendlyDate(
    DateTime value, {
    DateTime? now,
    String pattern = TimeFormat.shortDate,
    String? locale,
  }) {
    final current = now ?? DateTime.now();
    final days = _calendarDayDifference(current, value);

    return switch (days) {
      0 => 'Today',
      -1 => 'Yesterday',
      1 => 'Tomorrow',
      _ => format(value, pattern: pattern, locale: locale),
    };
  }

  /// E.g. "Today at 3:42 PM", "Yesterday at 8:00 AM".
  static String friendlyDateTime(
    DateTime value, {
    DateTime? now,
    String datePattern = TimeFormat.shortDate,
    String timePattern = TimeFormat.time12,
    String? locale,
  }) {
    final day = friendlyDate(
      value,
      now: now,
      pattern: datePattern,
      locale: locale,
    );
    final time = format(value, pattern: timePattern, locale: locale);
    return '$day at $time';
  }

  /// Relative within the given number of days, otherwise a normal date.
  static String smartDate(
    DateTime value, {
    DateTime? now,
    int relativeWithinDays = 7,
    bool short = false,
    String pattern = TimeFormat.shortDate,
    String? locale,
  }) {
    if (relativeWithinDays < 0) {
      throw ArgumentError.value(relativeWithinDays, 'relativeWithinDays');
    }
    final current = now ?? DateTime.now();
    if (value.difference(current).abs() < Duration(days: relativeWithinDays)) {
      return timeAgo(value, now: current, short: short);
    }
    return format(value, pattern: pattern, locale: locale);
  }

  // ------------------------------------------------------------
  // COMPARISON (LOCAL CALENDAR DAYS)
  // ------------------------------------------------------------

  static bool isSameDay(DateTime a, DateTime b) =>
      _calendarDayDifference(a, b) == 0;

  static bool isToday(DateTime value, {DateTime? now}) =>
      _calendarDayDifference(now ?? DateTime.now(), value) == 0;

  static bool isYesterday(DateTime value, {DateTime? now}) =>
      _calendarDayDifference(now ?? DateTime.now(), value) == -1;

  static bool isTomorrow(DateTime value, {DateTime? now}) =>
      _calendarDayDifference(now ?? DateTime.now(), value) == 1;

  static bool isPast(DateTime value, {DateTime? now}) =>
      value.isBefore(now ?? DateTime.now());

  static bool isFuture(DateTime value, {DateTime? now}) =>
      value.isAfter(now ?? DateTime.now());

  // Using UTC midnight *of each local calendar date* prevents daylight-saving
  // transitions from making a calendar day appear 23 or 25 hours long.
  static int _calendarDayDifference(DateTime from, DateTime to) {
    final a = from.toLocal();
    final b = to.toLocal();
    final aDay = DateTime.utc(a.year, a.month, a.day);
    final bDay = DateTime.utc(b.year, b.month, b.day);
    return bDay.difference(aDay).inDays;
  }

  // ------------------------------------------------------------
  // STORAGE / API: ISO 8601 & UNIX TIMESTAMPS
  // ------------------------------------------------------------

  /// UTC ISO 8601 keeps the instant unambiguous across devices/timezones.
  static String toIso(DateTime value) => value.toUtc().toIso8601String();

  static DateTime fromIso(String input) => DateTime.parse(input);

  static DateTime? tryFromIso(String input) => DateTime.tryParse(input);

  static int toTimestamp(
    DateTime value, {
    bool milliseconds = true,
  }) {
    final ms = value.millisecondsSinceEpoch;
    return milliseconds ? ms : (ms / 1000).floor();
  }

  static DateTime fromTimestamp(
    int value, {
    bool milliseconds = true,
    bool utc = false,
  }) {
    return DateTime.fromMillisecondsSinceEpoch(
      milliseconds ? value : value * 1000,
      isUtc: utc,
    );
  }
}
