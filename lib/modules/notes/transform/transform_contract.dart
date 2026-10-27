import 'dart:convert';

const transformOperations = {
  'rewrite-note': 'Rewrite',
  'expand-note': 'Expand',
  'tone-note': 'Adjust tone',
  'clarify-note': 'Grammar / clarity',
  'markdown-note': 'Format Markdown',
};
const transformOutputBytes = 4096;
const transformSourceBytes = 65536;

bool validTransformOutput(String text) =>
    text.trim().isNotEmpty &&
    utf8.encode(text).length <= transformOutputBytes &&
    !RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]').hasMatch(text) &&
    !text.runes.any((unit) => unit >= 0xd800 && unit <= 0xdfff) &&
    !RegExp(r'</?[a-z][^>]*>', caseSensitive: false).hasMatch(text) &&
    !RegExp(r'^\s*\{\s*"(?:text|content|replacement)"\s*:').hasMatch(text);

/// Private local snapshot. Only {text, intent} goes to the computer.
class TransformSource {
  const TransformSource({
    required this.content,
    required this.version,
    required this.start,
    required this.end,
  });
  final String content, version;
  final int start, end;
  String get selected => content.substring(start, end);
  String replace(String text) => content.replaceRange(start, end, text);
  String encode() => jsonEncode({
    'content': content,
    'version': version,
    'start': start,
    'end': end,
  });
  factory TransformSource.decode(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final source = TransformSource(
      content: json['content'] as String,
      version: json['version'] as String,
      start: json['start'] as int,
      end: json['end'] as int,
    );
    if (utf8.encode(source.content).length > transformSourceBytes ||
        source.start < 0 ||
        source.end <= source.start ||
        source.end > source.content.length) {
      throw const FormatException('Invalid transformation source');
    }
    return source;
  }
}
