import 'dart:convert';

import 'package:journal/modules/diary/models/diary_day_entity.dart';
import 'package:journal/modules/diary/models/diary_item.dart';
import 'package:journal/modules/diary/history/diary_retrieval.dart';

export 'package:journal/modules/diary/history/diary_retrieval.dart';

/// S01: grounded answers to questions about the past, from excerpts the phone
/// selects. The companion sees only the question, today's date, the resolved
/// scope and up to [historyMaxSources] dated excerpts.
const historyOperation = 'answer-diary-question';
const historyContract = 1;
const historyInputBytes = 2000;
const historyOutputBytes = 2048;
const historyQuestionChars = 300;
const historyMaxSources = 8;
const historyExcerptChars = 280;
const historyAnswerChars = 700;

final _dateKey = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _control = RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]');

/// One sent excerpt with a stable diary identity and version.
class DiaryHistorySource {
  const DiaryHistorySource({
    required this.date,
    required this.uuid,
    required this.version,
    required this.text,
    required this.truncated,
    required this.created,
  });
  final String date, uuid;

  /// [itemVersion] when selected; a different value means edited.
  final String version;
  final String text;
  final bool truncated;
  final String created;

  Map<String, dynamic> toJson() => {
    'date': date,
    'uuid': uuid,
    'version': version,
    'text': text,
    'truncated': truncated,
    'created': created,
  };
  factory DiaryHistorySource.fromJson(Map<String, dynamic> j) {
    if (j['date'] is! String ||
        !_dateKey.hasMatch(j['date'] as String) ||
        j['uuid'] is! String ||
        j['version'] is! String ||
        j['text'] is! String ||
        j['truncated'] is! bool ||
        j['created'] is! String) {
      throw const FormatException('Invalid history source');
    }
    return DiaryHistorySource(
      date: j['date'] as String,
      uuid: j['uuid'] as String,
      version: j['version'] as String,
      text: j['text'] as String,
      truncated: j['truncated'] as bool,
      created: j['created'] as String,
    );
  }
}

/// An entry version: its update time plus an FNV-1a hash of its text, so an
/// edit is detected even when clocks give the same timestamp.
String itemVersion(DiaryItem item) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(item.content)) {
    hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
  }
  return '${item.updatedAt.toIso8601String()}#${hash.toRadixString(16)}';
}

enum DiarySourceStatus { current, edited, deleted }

/// Whether a cited entry still exists unchanged.
DiarySourceStatus sourceStatus(
  DiaryHistorySource source,
  DiaryDayEntity? Function(String date) day,
) {
  final item = day(source.date)?.visibleItems
      .where((i) => i.itemUuid == source.uuid)
      .firstOrNull;
  if (item == null) return DiarySourceStatus.deleted;
  return itemVersion(item) == source.version
      ? DiarySourceStatus.current
      : DiarySourceStatus.edited;
}

/// The bounded excerpt of [content] around the sentence with most [terms].
(String, bool) excerptFor(String content, Set<String> terms) {
  final text = content.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (text.runes.length <= historyExcerptChars) return (text, false);
  final sentences = text
      .split(RegExp(r'(?<=[.!?。！？])\s+'))
      .where((s) => s.isNotEmpty)
      .toList();
  var best = 0, bestScore = -1;
  for (final (i, s) in sentences.indexed) {
    final score = diaryTerms(s).intersection(terms).length;
    if (score > bestScore) (best, bestScore) = (i, score);
  }
  var start = best, end = best;
  String join() => sentences.sublist(start, end + 1).join(' ');
  while (true) {
    final grew =
        end + 1 < sentences.length &&
        [...join().runes].length + sentences[end + 1].runes.length + 1 <=
            historyExcerptChars;
    if (grew) {
      end++;
      continue;
    }
    if (start > 0 &&
        join().runes.length + sentences[start - 1].runes.length + 1 <=
            historyExcerptChars) {
      start--;
      continue;
    }
    break;
  }
  var out = join();
  if (out.runes.length > historyExcerptChars - 2) {
    final cut = String.fromCharCodes(out.runes.take(historyExcerptChars - 2));
    final space = cut.lastIndexOf(' ');
    out = space > 40 ? cut.substring(0, space) : cut;
  }
  return (
    '${start > 0 ? '… ' : ''}$out${end < sentences.length - 1 || out != join() ? ' …' : ''}',
    true,
  );
}

/// What was searched, what matched and what is sent. Shown before sending.
class DiaryHistorySelection {
  const DiaryHistorySelection({
    required this.question,
    required this.today,
    required this.scope,
    required this.sources,
    required this.daysSearched,
    required this.matching,
    required this.overview,
    this.semantic = false,
  });
  final String question, today;
  final DiaryDateScope? scope;

  /// Chronological; request IDs are s0, s1… in this order.
  final List<DiaryHistorySource> sources;
  final int daysSearched, matching;

  /// The question named only a time, so entries in scope were sampled.
  final bool overview;

  /// S03b: candidates were ranked by keywords and meaning together.
  final bool semantic;

  /// The words matched and the date scope of [question] relative to [today].
  static ({Set<String> terms, DiaryDateScope? scope, DateTime today}) parse(
    String question,
    DateTime today,
  ) {
    final q = question.trim().replaceAll(RegExp(r'\s+'), ' ');
    final t = DateTime.utc(today.year, today.month, today.day);
    final scope = DiaryDateScope.parse(q, t);
    return (
      terms: diaryTerms(
        scope == null ? q : q.toLowerCase().replaceFirst(scope.phrase, ' '),
      ),
      scope: scope,
      today: t,
    );
  }

  bool get sendable => sources.isNotEmpty;

  /// [ranked], when given, is the hybrid retriever's order of item UUIDs
  /// (already limited to the scope); it replaces keyword-only ranking.
  static DiaryHistorySelection select({
    required String question,
    required DateTime today,
    required Iterable<DiaryDayEntity> days,
    List<String>? ranked,
  }) {
    final q = question.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (q.isEmpty ||
        q.runes.length > historyQuestionChars ||
        _control.hasMatch(q)) {
      throw const FormatException('Ask a question of up to 300 characters.');
    }
    final (:terms, :scope, today: t) = parse(q, today);
    final inScope = [
      for (final day in days)
        if (!day.isDeleted &&
            _dateKey.hasMatch(day.dateString) &&
            !civil(day.dateString).isAfter(t) &&
            (scope?.contains(civil(day.dateString)) ?? true))
          day,
    ]..sort((a, b) => a.dateString.compareTo(b.dateString));
    final candidates = <({DiaryDayEntity day, DiaryItem item, int score})>[];
    for (final day in inScope) {
      final title = day.dayTitle ?? '';
      for (final item in day.visibleItems) {
        if (!sendableText(item.content)) continue;
        final score = terms.isEmpty
            ? 1
            : diaryTerms('$title ${item.content}').intersection(terms).length;
        if (score > 0) candidates.add((day: day, item: item, score: score));
      }
    }
    final overview = terms.isEmpty;
    final semantic = ranked != null && !overview;
    if (semantic) {
      // Hybrid mode: the retriever's fused order, including entries found
      // by meaning that share no keyword.
      final byUuid = {
        for (final day in inScope)
          for (final item in day.visibleItems)
            if (sendableText(item.content)) item.itemUuid: (day, item),
      };
      candidates
        ..clear()
        ..addAll([
          for (final (i, uuid) in ranked.indexed)
            if (byUuid[uuid] case (final day, final item))
              (day: day, item: item, score: ranked.length - i),
        ]);
    }
    // Keyword mode: best matches first, newer breaking ties. Overview mode:
    // spread evenly across the scope so one busy week does not dominate.
    final order = overview
        ? _spread(candidates)
        : semantic
        ? candidates
        : (candidates.toList()..sort((a, b) {
            final s = b.score.compareTo(a.score);
            return s != 0 ? s : b.day.dateString.compareTo(a.day.dateString);
          }));
    final chosen = <DiaryHistorySource>[];
    DiaryHistorySelection build(List<DiaryHistorySource> sources) =>
        DiaryHistorySelection(
          question: q,
          today: civilKey(t),
          scope: scope,
          sources: List.unmodifiable(
            sources.toList()..sort((a, b) {
              final d = a.date.compareTo(b.date);
              return d != 0 ? d : a.created.compareTo(b.created);
            }),
          ),
          daysSearched: inScope.length,
          matching: candidates.length,
          overview: overview && scope != null,
          semantic: semantic,
        );
    if (overview && scope == null) return build(const []);
    for (final c in order) {
      if (chosen.length == historyMaxSources) break;
      if (chosen.any((s) => s.uuid == c.item.itemUuid)) continue;
      final (text, truncated) = overview
          ? excerptFor(c.item.content, const {})
          : excerptFor(c.item.content, terms);
      final source = DiaryHistorySource(
        date: c.day.dateString,
        uuid: c.item.itemUuid,
        version: itemVersion(c.item),
        text: text,
        truncated: truncated,
        created: c.item.createdAt.toIso8601String(),
      );
      if (utf8.encode(build([...chosen, source]).request()).length <=
          historyInputBytes) {
        chosen.add(source);
      }
    }
    return build(chosen);
  }

  static List<T> _spread<T>(List<T> items) {
    if (items.length <= historyMaxSources) return items;
    final step = items.length / historyMaxSources;
    return [
      for (var i = 0; i < historyMaxSources; i++) items[(i * step).floor()],
      ...items,
    ];
  }

  String request() => jsonEncode({
    'question': question,
    'today': today,
    'scope': scope?.toJson(),
    'sources': [
      for (final (i, s) in sources.indexed)
        {'id': 's$i', 'date': s.date, 'text': s.text},
    ],
  });

  String encode() => jsonEncode({
    'question': question,
    'today': today,
    'scope': scope == null
        ? null
        : {...scope!.toJson(), 'phrase': scope!.phrase},
    'sources': [for (final s in sources) s.toJson()],
    'daysSearched': daysSearched,
    'matching': matching,
    'overview': overview,
    'semantic': semantic,
  });

  factory DiaryHistorySelection.decode(String raw) {
    if (utf8.encode(raw).length > 131072) {
      throw const FormatException('Invalid history snapshot');
    }
    final v = jsonDecode(raw);
    if (v is! Map ||
        v['question'] is! String ||
        v['today'] is! String ||
        !_dateKey.hasMatch(v['today'] as String) ||
        v['sources'] is! List ||
        (v['sources'] as List).length > historyMaxSources ||
        v['daysSearched'] is! int ||
        v['matching'] is! int ||
        v['overview'] is! bool) {
      throw const FormatException('Invalid history snapshot');
    }
    final s = v['scope'];
    DiaryDateScope? scope;
    if (s != null) {
      if (s is! Map ||
          s['from'] is! String ||
          s['to'] is! String ||
          s['phrase'] is! String) {
        throw const FormatException('Invalid history snapshot');
      }
      scope = DiaryDateScope(
        civil(s['from'] as String),
        civil(s['to'] as String),
        s['phrase'] as String,
      );
    }
    return DiaryHistorySelection(
      question: v['question'] as String,
      today: v['today'] as String,
      scope: scope,
      sources: [
        for (final e in v['sources'] as List)
          DiaryHistorySource.fromJson(Map<String, dynamic>.from(e as Map)),
      ],
      daysSearched: v['daysSearched'] as int,
      matching: v['matching'] as int,
      overview: v['overview'] as bool,
      semantic: v['semantic'] == true,
    );
  }

  String get coverage {
    final where = scope == null ? 'all of your diary' : scope!.label;
    final days = daysSearched == 1 ? '1 day' : '$daysSearched days';
    return 'Searched $where ($days with entries). '
        '${sources.length} of $matching ${overview
            ? 'entries'
            : semantic
            ? 'entries matched by keywords or meaning'
            : 'matching entries'} '
        '${sources.length == 1 ? 'is' : 'are'} sent'
        '${sources.any((s) => s.truncated) ? ', some as shortened excerpts' : ''}.';
  }
}

/// The answer was well formed but cannot be shown as grounded.
class DiaryAnswerRejected implements Exception {
  const DiaryAnswerRejected(this.message);
  final String message;
  @override
  String toString() => message;
}

class DiaryHistoryAnswer {
  const DiaryHistoryAnswer({
    required this.answered,
    required this.text,
    required this.citations,
  });

  /// False when the computer said the excerpts were not enough.
  final bool answered;
  final String text;
  final List<DiaryHistorySource> citations;

  static DiaryHistoryAnswer parse(String raw, DiaryHistorySelection selection) {
    if (utf8.encode(raw).length > historyOutputBytes) {
      throw const FormatException('Oversized answer');
    }
    final v = jsonDecode(raw);
    if (v is! Map ||
        v.length != 3 ||
        !['answered', 'insufficient'].contains(v['status']) ||
        v['answer'] is! String ||
        (v['answer'] as String).runes.length > historyAnswerChars ||
        v['citations'] is! List ||
        (v['citations'] as List).any((c) => c is! String)) {
      throw const FormatException('Invalid answer');
    }
    final answered = v['status'] == 'answered';
    final ids = List<String>.from(v['citations'] as List);
    final cited = <DiaryHistorySource>[];
    for (final id in ids.toSet()) {
      final index = RegExp(r'^s(\d)$').firstMatch(id)?.group(1);
      final i = index == null ? -1 : int.parse(index);
      if (i < 0 || i >= selection.sources.length) {
        throw const DiaryAnswerRejected(
          'Your computer cited an excerpt it was not given, so the answer was not shown.',
        );
      }
      cited.add(selection.sources[i]);
    }
    // IDs never belong in the visible text.
    final text = (v['answer'] as String)
        .replaceAll(RegExp(r'\s*[\[(]s\d[\])]'), '')
        .trim();
    if (answered && (cited.isEmpty || text.isEmpty)) {
      throw const DiaryAnswerRejected(
        'The answer did not point to any of your entries, so it was not shown.',
      );
    }
    cited.sort((a, b) {
      final d = a.date.compareTo(b.date);
      return d != 0 ? d : a.created.compareTo(b.created);
    });
    return DiaryHistoryAnswer(
      answered: answered,
      // A model's explanation of missing evidence can itself assert things
      // (observed: "You went skydiving on a date not mentioned"), so it is
      // never shown.
      text: answered
          ? text
          : 'The excerpts searched were not enough to answer this.',
      citations: answered ? cited : const [],
    );
  }
}
