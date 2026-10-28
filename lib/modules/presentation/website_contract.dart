import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

/// A self-contained website generated from one saved note.
const noteWebsiteOperation = 'present-website';
const noteWebsiteContract = 1;
const noteWebsiteInputBytes = 2000;
const noteWebsiteDescriptionChars = 240;
const noteWebsiteOutputBytes = 16384;

final _control = RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]');

/// SHA-256 of [content], kept beside a website to notice later edits.
String websiteContentHash(String content) => Sha256()
    .toSync()
    .hashSync(utf8.encode(content))
    .bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

/// What was asked for, and the note at that moment. Only the title, content
/// and description are sent.
class WebsiteRequest {
  const WebsiteRequest({
    required this.noteId,
    required this.version,
    required this.title,
    required this.content,
    required this.description,
  });
  final String noteId, version, title, content, description;

  String get contentHash => websiteContentHash(content);

  /// Throws [FormatException] when the note or description does not fit.
  String request() {
    final clean = description.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty ||
        clean.runes.length > noteWebsiteDescriptionChars ||
        content.trim().isEmpty ||
        _control.hasMatch(content) ||
        _control.hasMatch(title)) {
      throw const FormatException(
        'Describe the website in one line of at most 240 characters.',
      );
    }
    final value = jsonEncode({
      'title': title.trim(),
      'text': content,
      'description': clean,
    });
    if (utf8.encode(value).length > noteWebsiteInputBytes) {
      throw const FormatException(
        'This note is longer than a website can be made from (2,000 bytes with its title and description). Nothing was sent.',
      );
    }
    return value;
  }

  String encode() => jsonEncode({
    'noteId': noteId,
    'version': version,
    'title': title,
    'content': content,
    'description': description,
  });

  factory WebsiteRequest.decode(String raw) {
    final json = jsonDecode(raw);
    if (json is! Map ||
        [
          'noteId',
          'version',
          'title',
          'content',
          'description',
        ].any((key) => json[key] is! String)) {
      throw const FormatException('Invalid website request');
    }
    return WebsiteRequest(
      noteId: json['noteId'] as String,
      version: json['version'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      description: json['description'] as String,
    );
  }
}

const _removed = {
  'script',
  'iframe',
  'frame',
  'frameset',
  'object',
  'embed',
  'applet',
  'form',
  'link',
  'base',
  'noscript',
  'template',
  'portal',
  'audio',
  'video',
  'source',
  'track',
};
const _urlAttributes = {
  'src',
  'href',
  'srcset',
  'action',
  'formaction',
  'poster',
  'background',
  'xlink:href',
  'ping',
};
// Any url() that is not inline data, imported sheets, and legacy expressions.
final _remoteCss = RegExp(
  r'url\(\s*(?![\x22\x27]?\s*data:)[^)]*\)|@import[^;]*;?|expression\s*\(',
  caseSensitive: false,
);

/// The policy every rendered page carries, in addition to the web view
/// having JavaScript and navigation off.
const websitePolicy =
    "default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:";

/// Rebuilds [raw] as an inert page: no scripts, handlers, frames, forms or
/// remote resources, with a strict content policy. Throws [FormatException]
/// when nothing usable is left.
String sanitizeWebsite(String raw) {
  var text = raw.trim();
  final fence = RegExp(
    r'^```(?:html)?\s*\n([\s\S]*?)\n?```$',
    caseSensitive: false,
  ).firstMatch(text);
  if (fence != null) text = fence.group(1)!.trim();
  if (text.isEmpty ||
      utf8.encode(text).length > noteWebsiteOutputBytes ||
      _control.hasMatch(text)) {
    throw const FormatException('Invalid website');
  }
  final document = html.parse(text);
  for (final element in document.querySelectorAll('*').toList()) {
    final name = element.localName ?? '';
    final refresh =
        name == 'meta' && element.attributes.containsKey('http-equiv');
    if (_removed.contains(name) || refresh) {
      element.remove();
      continue;
    }
    for (final key in element.attributes.keys.toList()) {
      final attribute = key.toString().toLowerCase();
      final value = element.attributes[key] ?? '';
      final local =
          value.trim().startsWith('#') ||
          value.trim().toLowerCase().startsWith('data:image/');
      if (attribute.startsWith('on') ||
          (_urlAttributes.contains(attribute) && !local) ||
          (attribute == 'style' && _remoteCss.hasMatch(value))) {
        element.attributes.remove(key);
      }
    }
    if (name == 'style' && _remoteCss.hasMatch(element.text)) {
      element.text = element.text.replaceAll(_remoteCss, 'none');
    }
  }
  final body = document.body;
  if (body == null || body.text.trim().isEmpty) {
    throw const FormatException('The website has no content');
  }
  final head = document.head ?? (dom.Element.tag('head'));
  if (document.head == null) document.documentElement!.insertBefore(head, body);
  head.nodes.insert(
    0,
    dom.Element.tag('meta')
      ..attributes['http-equiv'] = 'Content-Security-Policy'
      ..attributes['content'] = websitePolicy,
  );
  head.nodes.insert(
    1,
    dom.Element.tag('meta')
      ..attributes['name'] = 'viewport'
      ..attributes['content'] = 'width=device-width, initial-scale=1',
  );
  head.nodes.insert(
    0,
    dom.Element.tag('meta')..attributes['charset'] = 'utf-8',
  );
  final result = '<!doctype html>\n${document.documentElement!.outerHtml}';
  if (utf8.encode(result).length > noteWebsiteOutputBytes + 1024) {
    throw const FormatException('Oversized website');
  }
  return result;
}

/// A killable worker bounds the parser, including on malformed input.
Future<String> sanitizeWebsiteBounded(
  String raw, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final port = ReceivePort();
  Isolate? worker;
  try {
    worker = await Isolate.spawn(
      (SendPort send) {
        try {
          send.send(sanitizeWebsite(raw));
        } catch (_) {
          send.send(null);
        }
      },
      port.sendPort,
      onError: port.sendPort,
      onExit: port.sendPort,
    );
    final result = await port.first.timeout(timeout);
    if (result is! String) {
      throw const FormatException('This website could not be made safe.');
    }
    return result;
  } finally {
    worker?.kill(priority: Isolate.immediate);
    port.close();
  }
}
