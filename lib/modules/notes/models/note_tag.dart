import 'package:flutter/widgets.dart' show StringCharacters;

/// A tag's existing storage format is `emoji#name`.
class NoteTag {
  const NoteTag({required this.name, required this.emoji});

  final String name;
  final String emoji;

  String get key => name.trim().toLowerCase();
  String get encoded => '$emoji#$name';

  static NoteTag? tryParse(String value) {
    if (value.isEmpty) return null;
    // A hash keycap emoji contains # itself; search after its first grapheme.
    final separator = value.indexOf('#', value.characters.first.length);
    if (separator < 0) return null;
    final emoji = value.substring(0, separator).trim();
    final name = value.substring(separator + 1).trim();
    if (emoji.isEmpty || name.isEmpty || name.toLowerCase() == 'all') {
      return null;
    }
    return NoteTag(name: name, emoji: emoji);
  }
}
