import 'dart:convert';

import 'package:journal/modules/notes/models/note_entity.dart';
import 'package:journal/modules/notes/models/note_tag.dart';

/// N02: optional title/tag suggestions and starting ideas.
const noteMetadataOperation = 'suggest-note-metadata';
const noteIdeasOperation = 'suggest-note-ideas';
const noteHelpContract = 1;
const noteHelpInputBytes = 2000;
const noteHelpOutputBytes = 1536;
const noteTitleChars = 80;
const noteTagChars = 24;
const noteIdeaChars = 100;
const noteIdeaTopicChars = 120;
const noteIdeaContextNotes = 3;
const noteIdeaExcerptChars = 240;

/// The handle key for idea tasks, which belong to no note.
const noteIdeasKey = 'note-ideas';

/// The tag picker's palette; suggested tags must use one of these.
const noteTagEmojis = [
  '🏷️',
  '💡',
  '📝',
  '💼',
  '🌱',
  '🏡',
  '❤️',
  '✨',
  '📚',
  '🎯',
  '🧠',
  '☕',
  '🎨', //
  '🎵',
  '📷',
  '🌍',
  '🏃',
  '🍜',
  '💰',
  '🛠️',
  '🌿',
  '🌙',
  '☀️',
  '🔥',
  '🧘',
  '🎉',
  '🐾',
  '💭',
];

final _control = RegExp(r'[\x00-\x1f\x7f]');
bool _plain(Object? value, int chars, {bool empty = false}) =>
    value is String &&
    (empty || value.trim().isNotEmpty) &&
    value.runes.length <= chars &&
    !_control.hasMatch(value) &&
    !value.runes.any((unit) => unit >= 0xd800 && unit <= 0xdfff);
String _collapse(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Tags naming sensitive personal attributes are never suggested, even when
/// the note (or text injected into it) asks; the user can still add them.
final _sensitiveTag = RegExp(
  r'\b(depress\w*|anxi\w*|adhd|autis\w*|bipolar|cancer|diabet\w*|pregnan\w*|hiv|'
  r'mental|therap\w*|diagnos\w*|medicat\w*|illness|disab\w*|religio\w*|christian|'
  r'muslim|jewish|hindu|buddhis\w*|atheis\w*|gay|lesbian|bisexual|trans\w*|queer|'
  r'sexual\w*|politic\w*|democrat\w*|republican\w*|ethnic\w*|racial|race)\b',
  caseSensitive: false,
);

/// Notes shorter than this many words get no suggestions: a few words are
/// not enough to describe without inventing.
const noteMetadataMinWords = 4;

/// Whether [name] is usable as the name half of an `emoji#name` tag.
bool validNoteTagName(String name) =>
    _plain(name, noteTagChars) &&
    !name.contains('#') &&
    name.trim().toLowerCase() != 'all';

/// The saved note a metadata request was made from. It stays in protected
/// task storage on the phone; only title, body and tag names are sent.
class NoteMetadataSource {
  const NoteMetadataSource({
    required this.noteId,
    required this.title,
    required this.content,
    required this.tags,
    required this.version,
  });
  final String noteId, title, content, version;
  final List<String> tags;

  factory NoteMetadataSource.fromNote(NoteEntity note) => NoteMetadataSource(
    noteId: note.uuid,
    title: note.title,
    content: note.content,
    tags: List.of(note.tags),
    version: note.versionVectorJson,
  );

  List<NoteTag> get parsedTags =>
      tags.map(NoteTag.tryParse).whereType<NoteTag>().toList();

  /// Throws [FormatException] when the body is empty or the request would
  /// exceed the limit. Nothing is shortened.
  String request() {
    if (content.trim().isEmpty) {
      throw const FormatException(
        'Write something in the note body first. Suggestions are based only on what it says.',
      );
    }
    if (content.trim().split(RegExp(r'\s+')).length < noteMetadataMinWords) {
      throw const FormatException(
        'This note is too short to suggest a title or tags without guessing. Add a little more first.',
      );
    }
    // The placeholder and very long titles carry no useful context.
    final current = _collapse(title);
    final value = jsonEncode({
      'title': current == 'Untitled Note' || current.runes.length > 200
          ? ''
          : current,
      'text': content.trim(),
      'tags': [for (final tag in parsedTags.take(12)) tag.name],
    });
    if (utf8.encode(value).length > noteHelpInputBytes) {
      throw const FormatException(
        'This note is longer than 2,000 UTF-8 bytes including its title. Nothing was sent; notes are never shortened.',
      );
    }
    return value;
  }

  bool matches(NoteEntity? note) =>
      note != null &&
      !note.isDeleted &&
      !note.isPermanentlyDeleted &&
      note.title == title &&
      note.content == content &&
      note.versionVectorJson == version &&
      note.tags.length == tags.length &&
      note.tags.every(tags.contains);

  String encode() => jsonEncode({
    'noteId': noteId,
    'title': title,
    'content': content,
    'tags': tags,
    'version': version,
  });
  factory NoteMetadataSource.decode(String raw) {
    final json = jsonDecode(raw);
    if (json is! Map ||
        json['noteId'] is! String ||
        json['title'] is! String ||
        json['content'] is! String ||
        json['version'] is! String ||
        json['tags'] is! List ||
        (json['tags'] as List).any((t) => t is! String) ||
        utf8.encode(json['content'] as String).length > noteHelpInputBytes) {
      throw const FormatException('Invalid metadata source');
    }
    return NoteMetadataSource(
      noteId: json['noteId'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      tags: (json['tags'] as List).cast<String>(),
      version: json['version'] as String,
    );
  }
}

/// Suggestions after the phone's checks: no repeats of the current title or
/// existing tags, no duplicates, palette emoji only. A suggested tag whose
/// name matches a tag used elsewhere reuses that tag's spelling and emoji.
class NoteMetadataSuggestions {
  const NoteMetadataSuggestions(this.titles, this.tags);
  final List<String> titles;
  final List<NoteTag> tags;
  bool get isEmpty => titles.isEmpty && tags.isEmpty;

  /// Throws [FormatException] for a broken envelope.
  factory NoteMetadataSuggestions.parse(
    String text,
    NoteMetadataSource source, {
    Iterable<NoteTag> library = const [],
  }) {
    final json = jsonDecode(text);
    if (json is! Map ||
        json.keys.toSet().difference({'titles', 'tags'}).isNotEmpty ||
        json['titles'] is! List ||
        json['tags'] is! List) {
      throw const FormatException('Invalid suggestions');
    }
    final titles = <String>[];
    final seenTitles = {_collapse(source.title).toLowerCase(), ''};
    for (final value in json['titles'] as List) {
      if (!_plain(value, noteTitleChars)) {
        throw const FormatException('Invalid title');
      }
      final title = _collapse(value as String)
          .replaceAll(RegExp(r'''^["'“‘]+|["'”’]+$'''), '');
      if (title.isNotEmpty && seenTitles.add(title.toLowerCase())) {
        titles.add(title);
      }
    }
    final known = {for (final tag in library) tag.key: tag};
    final seenTags = {for (final tag in source.parsedTags) tag.key};
    final tags = <NoteTag>[];
    for (final value in json['tags'] as List) {
      if (value is! Map ||
          !_plain(value['name'], noteTagChars) ||
          !noteTagEmojis.contains(value['emoji'])) {
        throw const FormatException('Invalid tag');
      }
      final name = _collapse(value['name'] as String)
          .replaceAll(RegExp(r'^#+'), '');
      if (!validNoteTagName(name) || _sensitiveTag.hasMatch(name)) continue;
      final tag =
          known[name.toLowerCase()] ??
          NoteTag(name: name, emoji: value['emoji'] as String);
      if (NoteTag.tryParse(tag.encoded)?.key == tag.key &&
          seenTags.add(tag.key)) {
        tags.add(tag);
      }
    }
    return NoteMetadataSuggestions(titles, tags);
  }
}

class NoteIdeaContext {
  const NoteIdeaContext({
    required this.noteId,
    required this.title,
    required this.excerpt,
  });
  final String noteId, title, excerpt;

  /// The disclosed excerpt: the title and the start of the body, whitespace
  /// collapsed, up to [noteIdeaExcerptChars] characters.
  factory NoteIdeaContext.fromNote(NoteEntity note) {
    final body = _collapse(note.content);
    final runes = body.runes.toList();
    final title = _collapse(note.title);
    return NoteIdeaContext(
      noteId: note.uuid,
      title: title.runes.length > noteTitleChars
          ? String.fromCharCodes(title.runes.take(noteTitleChars))
          : title,
      excerpt: runes.length > noteIdeaExcerptChars
          ? String.fromCharCodes(runes.take(noteIdeaExcerptChars))
          : body,
    );
  }
  Map<String, dynamic> toJson() => {
    'noteId': noteId,
    'title': title,
    'excerpt': excerpt,
  };
}

/// An explicit request for starting ideas: an optional topic and at most
/// three notes the user selected. With neither, nothing personal is sent.
class NoteIdeaSource {
  const NoteIdeaSource({this.topic = '', this.notes = const []});
  final String topic;
  final List<NoteIdeaContext> notes;

  String request() {
    final cleanTopic = _collapse(topic);
    if (!_plain(cleanTopic, noteIdeaTopicChars, empty: true) ||
        notes.length > noteIdeaContextNotes) {
      throw const FormatException(
        'Use a topic of at most 120 characters and up to 3 notes.',
      );
    }
    final value = jsonEncode({
      'topic': cleanTopic,
      'notes': [
        for (final (i, note) in notes.indexed)
          {'id': 'n$i', 'title': note.title, 'excerpt': note.excerpt},
      ],
    });
    if (utf8.encode(value).length > noteHelpInputBytes) {
      throw const FormatException(
        'The selected notes exceed 2,000 UTF-8 bytes. Choose fewer notes.',
      );
    }
    return value;
  }

  String encode() => jsonEncode({
    'topic': topic,
    'notes': [for (final note in notes) note.toJson()],
  });
  factory NoteIdeaSource.decode(String raw) {
    final json = jsonDecode(raw);
    if (json is! Map || json['topic'] is! String || json['notes'] is! List) {
      throw const FormatException('Invalid idea source');
    }
    return NoteIdeaSource(
      topic: json['topic'] as String,
      notes: [
        for (final note in json['notes'] as List)
          if (note is Map &&
              note['noteId'] is String &&
              note['title'] is String &&
              note['excerpt'] is String)
            NoteIdeaContext(
              noteId: note['noteId'] as String,
              title: note['title'] as String,
              excerpt: note['excerpt'] as String,
            )
          else
            throw const FormatException('Invalid idea context'),
      ],
    );
  }
}

/// Throws [FormatException] for a broken envelope; drops repeats.
List<String> parseNoteIdeas(String text) {
  final json = jsonDecode(text);
  if (json is! Map ||
      json.keys.length != 1 ||
      json['ideas'] is! List ||
      (json['ideas'] as List).isEmpty) {
    throw const FormatException('Invalid ideas');
  }
  final seen = <String>{};
  return [
    for (final value in json['ideas'] as List)
      if (!_plain(value, noteIdeaChars))
        throw const FormatException('Invalid idea')
      else if (seen.add(_collapse(value as String).toLowerCase()))
        _collapse(value),
  ];
}
