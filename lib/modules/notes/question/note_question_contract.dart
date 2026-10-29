import 'dart:convert';

import 'package:journal/modules/diary/history/diary_history_contract.dart'
    show excerptFor;
import 'package:journal/modules/diary/history/diary_retrieval.dart';
import 'package:journal/modules/notes/models/note_entity.dart';

/// S02 (notes): grounded answers to a question about saved notes, from
/// excerpts the phone selects. The companion sees only the question, today's
/// date, the resolved scope and up to [noteQuestionMaxSources] excerpts.
const noteQuestionOperation = 'answer-note-question';
const noteQuestionContract = 1;
const noteQuestionInputBytes = 2000;
const noteQuestionOutputBytes = 2048;
const noteQuestionChars = 300;
const noteQuestionMaxSources = 8;
const noteQuestionTitleChars = 80;
const noteQuestionAnswerChars = 700;

final _dateKey = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _control = RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]');

/// A note version: its update time plus an FNV-1a hash of its title and
/// content, so an edit is detected even when clocks give the same timestamp.
String noteVersion(NoteEntity note) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode('${note.title}\n${note.content}')) {
    hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
  }
  return '${note.updatedAt.toUtc().toIso8601String()}#${hash.toRadixString(16)}';
}

bool _live(NoteEntity note) =>
    !note.isDeleted && !note.isPermanentlyDeleted && note.deletedAt == null;

/// One sent excerpt with a stable note identity and version.
class NoteQuestionSource {
  const NoteQuestionSource({
    required this.date,
    required this.uuid,
    required this.version,
    required this.title,
    required this.text,
    required this.truncated,
  });

  /// Civil date the note was created.
  final String date, uuid;

  /// [noteVersion] when selected; a different value means edited.
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
  factory NoteQuestionSource.fromJson(Map<String, dynamic> j) {
    if (j['date'] is! String ||
        !_dateKey.hasMatch(j['date'] as String) ||
        j['uuid'] is! String ||
        j['version'] is! String ||
        j['title'] is! String ||
        j['text'] is! String ||
        j['truncated'] is! bool) {
      throw const FormatException('Invalid note question source');
    }
    return NoteQuestionSource(
      date: j['date'] as String,
      uuid: j['uuid'] as String,
      version: j['version'] as String,
      title: j['title'] as String,
      text: j['text'] as String,
      truncated: j['truncated'] as bool,
    );
  }
}

enum NoteSourceStatus { current, edited, deleted }

/// Whether a cited note still exists unchanged.
NoteSourceStatus noteSourceStatus(
  NoteQuestionSource source,
  NoteEntity? Function(String uuid) note,
) {
  final n = note(source.uuid);
  if (n == null || !_live(n)) return NoteSourceStatus.deleted;
  return noteVersion(n) == source.version
      ? NoteSourceStatus.current
      : NoteSourceStatus.edited;
}

String _title(String title) {
  final t = title.trim().replaceAll(RegExp(r'\s+'), ' ');
  return t.runes.length <= noteQuestionTitleChars
      ? t
      : '${String.fromCharCodes(t.runes.take(noteQuestionTitleChars - 1))}…';
}

/// What was searched and what is sent with the question.
class NoteQuestionSelection {
  const NoteQuestionSelection({
    required this.question,
    required this.today,
    required this.scope,
    required this.sources,
    required this.notesSearched,
    required this.matching,
    this.semantic = false,
  });
  final String question, today;
  final DiaryDateScope? scope;

  /// Oldest first; request IDs are s0, s1… in this order.
  final List<NoteQuestionSource> sources;
  final int notesSearched, matching;

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
  /// [ranked], when given, is the hybrid retriever's order of note UUIDs
  /// (already limited to the scope); it replaces keyword-only ranking.
  static NoteQuestionSelection select({
    required String question,
    required DateTime today,
    required Iterable<NoteEntity> notes,
    List<String>? ranked,
  }) {
    final q = question.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (q.isEmpty ||
        q.runes.length > noteQuestionChars ||
        _control.hasMatch(q)) {
      throw const FormatException('Ask a question of up to 300 characters.');
    }
    final (:terms, :scope, today: t) = parse(q, today);
    final inScope = [
      for (final note in notes)
        if (_live(note) &&
            sendableText('${note.title}\n${note.content}'.trim()) &&
            (scope?.contains(_created(note)) ?? true))
          note,
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final overview = terms.isEmpty;
    final semantic = ranked != null && !overview;
    var candidates = <NoteEntity>[];
    if (semantic) {
      final byUuid = {for (final n in inScope) n.uuid: n};
      candidates = [for (final uuid in ranked) ?byUuid[uuid]];
    } else if (overview) {
      // A time with no topic: spread evenly across the scope.
      candidates = scope == null ? [] : _spread(inScope);
    } else {
      final scored =
          [
            for (final n in inScope)
              (
                note: n,
                score: diaryTerms('${n.title} ${n.content}')
                    .intersection(terms)
                    .length,
              ),
          ].where((c) => c.score > 0).toList()..sort((a, b) {
            final s = b.score.compareTo(a.score);
            return s != 0 ? s : b.note.updatedAt.compareTo(a.note.updatedAt);
          });
      candidates = [for (final c in scored) c.note];
    }
    final chosen = <NoteQuestionSource>[];
    NoteQuestionSelection build(List<NoteQuestionSource> sources) =>
        NoteQuestionSelection(
          question: q,
          today: civilKey(t),
          scope: scope,
          sources: List.unmodifiable(
            sources.toList()..sort((a, b) {
              final d = a.date.compareTo(b.date);
              return d != 0 ? d : a.uuid.compareTo(b.uuid);
            }),
          ),
          notesSearched: inScope.length,
          matching: overview ? inScope.length : candidates.length,
          semantic: semantic,
        );
    for (final note in candidates) {
      if (chosen.length == noteQuestionMaxSources) break;
      if (chosen.any((s) => s.uuid == note.uuid)) continue;
      final (text, truncated) = excerptFor(note.content, terms);
      final source = NoteQuestionSource(
        date: civilKey(_created(note)),
        uuid: note.uuid,
        version: noteVersion(note),
        title: _title(note.title),
        text: text,
        truncated: truncated,
      );
      if (utf8.encode(build([...chosen, source]).request()).length <=
          noteQuestionInputBytes) {
        chosen.add(source);
      }
    }
    return build(chosen);
  }

  static DateTime _created(NoteEntity note) {
    final local = note.createdAt.toLocal();
    return DateTime.utc(local.year, local.month, local.day);
  }

  static List<NoteEntity> _spread(List<NoteEntity> items) {
    if (items.length <= noteQuestionMaxSources) return items;
    final step = items.length / noteQuestionMaxSources;
    return [
      for (var i = 0; i < noteQuestionMaxSources; i++)
        items[(i * step).floor()],
      ...items,
    ];
  }

  String request() => jsonEncode({
    'question': question,
    'today': today,
    'scope': scope?.toJson(),
    'sources': [
      for (final (i, s) in sources.indexed)
        {'id': 's$i', 'date': s.date, 'title': s.title, 'text': s.text},
    ],
  });

  String encode() => jsonEncode({
    'question': question,
    'today': today,
    'scope': scope == null
        ? null
        : {...scope!.toJson(), 'phrase': scope!.phrase},
    'sources': [for (final s in sources) s.toJson()],
    'notesSearched': notesSearched,
    'matching': matching,
    'semantic': semantic,
  });

  factory NoteQuestionSelection.decode(String raw) {
    if (utf8.encode(raw).length > 131072) {
      throw const FormatException('Invalid note question snapshot');
    }
    final v = jsonDecode(raw);
    if (v is! Map ||
        v['question'] is! String ||
        v['today'] is! String ||
        !_dateKey.hasMatch(v['today'] as String) ||
        v['sources'] is! List ||
        (v['sources'] as List).length > noteQuestionMaxSources ||
        v['notesSearched'] is! int ||
        v['matching'] is! int) {
      throw const FormatException('Invalid note question snapshot');
    }
    final s = v['scope'];
    DiaryDateScope? scope;
    if (s != null) {
      if (s is! Map ||
          s['from'] is! String ||
          s['to'] is! String ||
          s['phrase'] is! String) {
        throw const FormatException('Invalid note question snapshot');
      }
      scope = DiaryDateScope(
        civil(s['from'] as String),
        civil(s['to'] as String),
        s['phrase'] as String,
      );
    }
    return NoteQuestionSelection(
      question: v['question'] as String,
      today: v['today'] as String,
      scope: scope,
      sources: [
        for (final e in v['sources'] as List)
          NoteQuestionSource.fromJson(Map<String, dynamic>.from(e as Map)),
      ],
      notesSearched: v['notesSearched'] as int,
      matching: v['matching'] as int,
      semantic: v['semantic'] == true,
    );
  }

  String get coverage {
    final where = scope == null
        ? 'all of your notes'
        : 'notes from ${scope!.label}';
    final notes = notesSearched == 1 ? '1 note' : '$notesSearched notes';
    return 'Searched $where ($notes). ${sources.length} of $matching '
        '${semantic ? 'notes matched by keywords or meaning' : 'matching notes'} '
        '${sources.length == 1 ? 'was' : 'were'} sent'
        '${sources.any((s) => s.truncated) ? ', some as shortened excerpts' : ''}.';
  }
}

/// The answer was well formed but cannot be shown as grounded.
class NoteAnswerRejected implements Exception {
  const NoteAnswerRejected(this.message);
  final String message;
  @override
  String toString() => message;
}

class NoteQuestionAnswer {
  const NoteQuestionAnswer({
    required this.answered,
    required this.text,
    required this.citations,
  });

  /// False when the computer said the excerpts were not enough.
  final bool answered;
  final String text;
  final List<NoteQuestionSource> citations;

  static NoteQuestionAnswer parse(String raw, NoteQuestionSelection selection) {
    if (utf8.encode(raw).length > noteQuestionOutputBytes) {
      throw const FormatException('Oversized answer');
    }
    final v = jsonDecode(raw);
    if (v is! Map ||
        v.length != 3 ||
        !['answered', 'insufficient'].contains(v['status']) ||
        v['answer'] is! String ||
        (v['answer'] as String).runes.length > noteQuestionAnswerChars ||
        v['citations'] is! List ||
        (v['citations'] as List).any((c) => c is! String)) {
      throw const FormatException('Invalid answer');
    }
    final answered = v['status'] == 'answered';
    final cited = <NoteQuestionSource>[];
    for (final id in List<String>.from(v['citations'] as List).toSet()) {
      final index = RegExp(r'^s(\d)$').firstMatch(id)?.group(1);
      final i = index == null ? -1 : int.parse(index);
      if (i < 0 || i >= selection.sources.length) {
        throw const NoteAnswerRejected(
          'Your computer cited a note it was not given, so the answer was not shown.',
        );
      }
      cited.add(selection.sources[i]);
    }
    // IDs never belong in the visible text.
    final text = (v['answer'] as String)
        .replaceAll(RegExp(r'\s*[\[(]s\d[\])]'), '')
        .trim();
    if (answered && (cited.isEmpty || text.isEmpty)) {
      throw const NoteAnswerRejected(
        'The answer did not point to any of your notes, so it was not shown.',
      );
    }
    return NoteQuestionAnswer(
      answered: answered,
      // A model's explanation of missing evidence can itself assert things,
      // so it is never shown.
      text: answered
          ? text
          : 'The notes searched were not enough to answer this.',
      citations: answered
          ? [
              for (final s in selection.sources)
                if (cited.contains(s)) s,
            ]
          : const [],
    );
  }
}
