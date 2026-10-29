import 'dart:convert';

import 'package:journal/modules/diary/history/diary_history_contract.dart'
    show excerptFor;
import 'package:journal/modules/diary/history/diary_retrieval.dart';
import 'package:journal/modules/flow/models/thought_entity.dart';
import 'package:journal/modules/notes/models/note_entity.dart';
import 'package:journal/modules/recall/recall_contract.dart';

export 'package:journal/modules/recall/recall_contract.dart' show RecallKind;

/// S02: grounded answers to a question about saved notes or Flow thoughts,
/// from excerpts the phone selects. Each collection is asked separately, so
/// one never leaks into the other. The companion sees only the question,
/// today's date, the resolved scope and up to [recallQuestionMaxSources]
/// excerpts.
const noteQuestionOperation = 'answer-note-question';
const thoughtQuestionOperation = 'answer-thought-question';
const recallQuestionContract = 1;
const recallQuestionInputBytes = 2000;
const recallQuestionOutputBytes = 2048;
const recallQuestionChars = 300;
const recallQuestionMaxSources = 8;
const recallQuestionTitleChars = 80;
const recallQuestionAnswerChars = 700;

final _dateKey = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _control = RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]');

/// What differs between asking about notes and asking about thoughts.
extension RecallQuestionKind on RecallKind {
  String get questionOperation => switch (this) {
    RecallKind.note => noteQuestionOperation,
    RecallKind.thought => thoughtQuestionOperation,
    RecallKind.diary => throw UnsupportedError('Diary questions are S01'),
  };

  /// The companion capability key advertising [questionOperation].
  String get questionContractKey => switch (this) {
    RecallKind.note => 'noteQuestionContract',
    _ => 'thoughtQuestionContract',
  };

  String get one => this == RecallKind.note ? 'note' : 'thought';
  String get many => this == RecallKind.note ? 'notes' : 'thoughts';
}

/// One searchable note or thought. Thoughts have no title.
class RecallItem {
  const RecallItem({
    required this.uuid,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });
  final String uuid, title, content;
  final DateTime createdAt, updatedAt;

  /// Null for a deleted note.
  static RecallItem? note(NoteEntity note) =>
      note.isDeleted || note.isPermanentlyDeleted || note.deletedAt != null
      ? null
      : RecallItem(
          uuid: note.uuid,
          title: note.title,
          content: note.content,
          createdAt: note.createdAt,
          updatedAt: note.updatedAt,
        );

  static RecallItem thought(ThoughtEntity thought) => RecallItem(
    uuid: thought.uuid,
    title: '',
    content: thought.content,
    createdAt: thought.createdAt,
    updatedAt: thought.updatedAt,
  );

  static List<RecallItem> notes(Iterable<NoteEntity> notes) => [
    for (final n in notes) ?RecallItem.note(n),
  ];

  static List<RecallItem> thoughts(Iterable<ThoughtEntity> thoughts) => [
    for (final t in thoughts) RecallItem.thought(t),
  ];

  /// The update time plus an FNV-1a hash of the title and content, so an edit
  /// is detected even when clocks give the same timestamp.
  String get version {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode('$title\n$content')) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
    return '${updatedAt.toUtc().toIso8601String()}#${hash.toRadixString(16)}';
  }

  /// Civil date created, in the device's time zone.
  DateTime get created {
    final local = createdAt.toLocal();
    return DateTime.utc(local.year, local.month, local.day);
  }
}

/// One sent excerpt with a stable identity and version.
class RecallQuestionSource {
  const RecallQuestionSource({
    required this.date,
    required this.uuid,
    required this.version,
    required this.title,
    required this.text,
    required this.truncated,
  });

  /// Civil date the note or thought was created.
  final String date, uuid;

  /// [RecallItem.version] when selected; a different value means edited.
  final String version;
  final String title, text;
  final bool truncated;

  Map<String, dynamic> toJson() => {
    'date': date,
    'uuid': uuid,
    'version': version,
    'title': title,
    'text': text,
    'truncated': truncated,
  };
  factory RecallQuestionSource.fromJson(Map<String, dynamic> j) {
    if (j['date'] is! String ||
        !_dateKey.hasMatch(j['date'] as String) ||
        j['uuid'] is! String ||
        j['version'] is! String ||
        j['title'] is! String ||
        j['text'] is! String ||
        j['truncated'] is! bool) {
      throw const FormatException('Invalid question source');
    }
    return RecallQuestionSource(
      date: j['date'] as String,
      uuid: j['uuid'] as String,
      version: j['version'] as String,
      title: j['title'] as String,
      text: j['text'] as String,
      truncated: j['truncated'] as bool,
    );
  }
}

enum RecallSourceStatus { current, edited, deleted }

/// Whether a cited note or thought still exists unchanged.
RecallSourceStatus recallSourceStatus(
  RecallQuestionSource source,
  RecallItem? Function(String uuid) lookup,
) {
  final item = lookup(source.uuid);
  if (item == null) return RecallSourceStatus.deleted;
  return item.version == source.version
      ? RecallSourceStatus.current
      : RecallSourceStatus.edited;
}

String _title(String title) {
  final t = title.trim().replaceAll(RegExp(r'\s+'), ' ');
  return t.runes.length <= recallQuestionTitleChars
      ? t
      : '${String.fromCharCodes(t.runes.take(recallQuestionTitleChars - 1))}…';
}

/// What was searched and what is sent with the question.
class RecallQuestionSelection {
  const RecallQuestionSelection({
    required this.kind,
    required this.question,
    required this.today,
    required this.scope,
    required this.sources,
    required this.searched,
    required this.matching,
    this.semantic = false,
  });
  final RecallKind kind;
  final String question, today;
  final DiaryDateScope? scope;

  /// Oldest first; request IDs are s0, s1… in this order.
  final List<RecallQuestionSource> sources;
  final int searched, matching;

  /// Candidates were ranked by keywords and meaning together.
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

  /// Throws [FormatException] for an empty, over-long or malformed question.
  /// [items] must all be of [kind]. [ranked], when given, is the hybrid
  /// retriever's order of UUIDs; it replaces keyword-only ranking.
  static RecallQuestionSelection select({
    required RecallKind kind,
    required String question,
    required DateTime today,
    required Iterable<RecallItem> items,
    List<String>? ranked,
  }) {
    final q = question.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (q.isEmpty ||
        q.runes.length > recallQuestionChars ||
        _control.hasMatch(q)) {
      throw const FormatException('Ask a question of up to 300 characters.');
    }
    final (:terms, :scope, today: t) = parse(q, today);
    final inScope = [
      for (final item in items)
        if (sendableText('${item.title}\n${item.content}'.trim()) &&
            (scope?.contains(item.created) ?? true))
          item,
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final overview = terms.isEmpty;
    final semantic = ranked != null && !overview;
    var candidates = <RecallItem>[];
    if (semantic) {
      final byUuid = {for (final i in inScope) i.uuid: i};
      candidates = [for (final uuid in ranked) ?byUuid[uuid]];
    } else if (overview) {
      // A time with no topic: spread evenly across the scope.
      candidates = scope == null ? [] : _spread(inScope);
    } else {
      final scored =
          [
            for (final i in inScope)
              (
                item: i,
                score: diaryTerms('${i.title} ${i.content}')
                    .intersection(terms)
                    .length,
              ),
          ].where((c) => c.score > 0).toList()..sort((a, b) {
            final s = b.score.compareTo(a.score);
            return s != 0 ? s : b.item.updatedAt.compareTo(a.item.updatedAt);
          });
      candidates = [for (final c in scored) c.item];
    }
    final chosen = <RecallQuestionSource>[];
    RecallQuestionSelection build(List<RecallQuestionSource> sources) =>
        RecallQuestionSelection(
          kind: kind,
          question: q,
          today: civilKey(t),
          scope: scope,
          sources: List.unmodifiable(
            sources.toList()..sort((a, b) {
              final d = a.date.compareTo(b.date);
              return d != 0 ? d : a.uuid.compareTo(b.uuid);
            }),
          ),
          searched: inScope.length,
          matching: overview ? inScope.length : candidates.length,
          semantic: semantic,
        );
    for (final item in candidates) {
      if (chosen.length == recallQuestionMaxSources) break;
      if (chosen.any((s) => s.uuid == item.uuid)) continue;
      final (text, truncated) = excerptFor(item.content, terms);
      final source = RecallQuestionSource(
        date: civilKey(item.created),
        uuid: item.uuid,
        version: item.version,
        title: _title(item.title),
        text: text,
        truncated: truncated,
      );
      if (utf8.encode(build([...chosen, source]).request()).length <=
          recallQuestionInputBytes) {
        chosen.add(source);
      }
    }
    return build(chosen);
  }

  static List<RecallItem> _spread(List<RecallItem> items) {
    if (items.length <= recallQuestionMaxSources) return items;
    final step = items.length / recallQuestionMaxSources;
    return [
      for (var i = 0; i < recallQuestionMaxSources; i++)
        items[(i * step).floor()],
      ...items,
    ];
  }

  /// Thoughts are sent without a title field.
  String request() => jsonEncode({
    'question': question,
    'today': today,
    'scope': scope?.toJson(),
    'sources': [
      for (final (i, s) in sources.indexed)
        {
          'id': 's$i',
          'date': s.date,
          if (kind == RecallKind.note) 'title': s.title,
          'text': s.text,
        },
    ],
  });

  String encode() => jsonEncode({
    'kind': kind.name,
    'question': question,
    'today': today,
    'scope': scope == null
        ? null
        : {...scope!.toJson(), 'phrase': scope!.phrase},
    'sources': [for (final s in sources) s.toJson()],
    'searched': searched,
    'matching': matching,
    'semantic': semantic,
  });

  factory RecallQuestionSelection.decode(String raw) {
    if (utf8.encode(raw).length > 131072) {
      throw const FormatException('Invalid question snapshot');
    }
    final v = jsonDecode(raw);
    if (v is! Map ||
        !['note', 'thought'].contains(v['kind']) ||
        v['question'] is! String ||
        v['today'] is! String ||
        !_dateKey.hasMatch(v['today'] as String) ||
        v['sources'] is! List ||
        (v['sources'] as List).length > recallQuestionMaxSources ||
        v['searched'] is! int ||
        v['matching'] is! int) {
      throw const FormatException('Invalid question snapshot');
    }
    final s = v['scope'];
    DiaryDateScope? scope;
    if (s != null) {
      if (s is! Map ||
          s['from'] is! String ||
          s['to'] is! String ||
          s['phrase'] is! String) {
        throw const FormatException('Invalid question snapshot');
      }
      scope = DiaryDateScope(
        civil(s['from'] as String),
        civil(s['to'] as String),
        s['phrase'] as String,
      );
    }
    return RecallQuestionSelection(
      kind: RecallKind.values.byName(v['kind'] as String),
      question: v['question'] as String,
      today: v['today'] as String,
      scope: scope,
      sources: [
        for (final e in v['sources'] as List)
          RecallQuestionSource.fromJson(Map<String, dynamic>.from(e as Map)),
      ],
      searched: v['searched'] as int,
      matching: v['matching'] as int,
      semantic: v['semantic'] == true,
    );
  }

  String get coverage {
    final many = kind.many;
    final where = scope == null
        ? 'all of your $many'
        : '$many from ${scope!.label}';
    final count = searched == 1 ? '1 ${kind.one}' : '$searched $many';
    return 'Searched $where ($count). ${sources.length} of $matching '
        '${semantic ? '$many matched by keywords or meaning' : 'matching $many'} '
        '${sources.length == 1 ? 'was' : 'were'} sent'
        '${sources.any((s) => s.truncated) ? ', some as shortened excerpts' : ''}.';
  }
}

/// The answer was well formed but cannot be shown as grounded.
class RecallAnswerRejected implements Exception {
  const RecallAnswerRejected(this.message);
  final String message;
  @override
  String toString() => message;
}

class RecallQuestionAnswer {
  const RecallQuestionAnswer({
    required this.answered,
    required this.text,
    required this.citations,
  });

  /// False when the computer said the excerpts were not enough.
  final bool answered;
  final String text;
  final List<RecallQuestionSource> citations;

  static RecallQuestionAnswer parse(
    String raw,
    RecallQuestionSelection selection,
  ) {
    if (utf8.encode(raw).length > recallQuestionOutputBytes) {
      throw const FormatException('Oversized answer');
    }
    final v = jsonDecode(raw);
    if (v is! Map ||
        v.length != 3 ||
        !['answered', 'insufficient'].contains(v['status']) ||
        v['answer'] is! String ||
        (v['answer'] as String).runes.length > recallQuestionAnswerChars ||
        v['citations'] is! List ||
        (v['citations'] as List).any((c) => c is! String)) {
      throw const FormatException('Invalid answer');
    }
    final kind = selection.kind;
    final answered = v['status'] == 'answered';
    final cited = <RecallQuestionSource>[];
    for (final id in List<String>.from(v['citations'] as List).toSet()) {
      final index = RegExp(r'^s(\d)$').firstMatch(id)?.group(1);
      final i = index == null ? -1 : int.parse(index);
      if (i < 0 || i >= selection.sources.length) {
        throw RecallAnswerRejected(
          'Your computer cited a ${kind.one} it was not given, so the answer was not shown.',
        );
      }
      cited.add(selection.sources[i]);
    }
    // IDs never belong in the visible text.
    final text = (v['answer'] as String)
        .replaceAll(RegExp(r'\s*[\[(]s\d[\])]'), '')
        .trim();
    if (answered && (cited.isEmpty || text.isEmpty)) {
      throw RecallAnswerRejected(
        'The answer did not point to any of your ${kind.many}, so it was not shown.',
      );
    }
    return RecallQuestionAnswer(
      answered: answered,
      // A model's explanation of missing evidence can itself assert things,
      // so it is never shown.
      text: answered
          ? text
          : 'The ${kind.many} searched were not enough to answer this.',
      citations: answered
          ? [
              for (final s in selection.sources)
                if (cited.contains(s)) s,
            ]
          : const [],
    );
  }
}
