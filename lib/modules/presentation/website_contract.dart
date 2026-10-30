import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

/// The retired freehand website, written whole by the model. It is no longer
/// requested; the name stays so saved pages and older jobs still read.
const noteWebsiteOperation = 'present-website';
const noteWebsiteInputBytes = 2000;
const noteWebsiteDescriptionChars = 240;
const noteWebsiteOutputBytes = 16384;

/// A themed website: the computer returns a [WebsiteSpec] of the note's own
/// words, and this phone draws it with a hand-built theme.
const noteWebsiteDesignOperation = 'design-website';
const noteWebsiteDesignContract = 1;
const websiteThemeIds = [
  'editorial',
  'zine',
  'garden',
  'notebook',
  'night',
  'postcard',
];
const websiteAccents = ['ink', 'rose', 'ocean', 'forest', 'sun', 'plum'];
const websiteSectionKinds = [
  'text',
  'cards',
  'list',
  'timeline',
  'quote',
  'stats',
  'photos',
];
const websiteMaxPhotos = 6;
const websiteSpecBytes = 8192;

final _control = RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]');

/// SHA-256 of [content], kept beside a website to notice later edits.
String websiteContentHash(String content) => Sha256()
    .toSync()
    .hashSync(utf8.encode(content))
    .bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

/// What was asked for, and the note at that moment. Only the title, content
/// and description are sent, plus for a themed website the theme and how
/// many photos the note has; the photos themselves stay on this phone.
class WebsiteRequest {
  const WebsiteRequest({
    required this.noteId,
    required this.version,
    required this.title,
    required this.content,
    required this.description,
    this.theme = '',
    this.photos = 0,
  });
  final String noteId, version, title, content, description;

  /// A [websiteThemeIds] entry or `auto`; empty for a freehand website.
  final String theme;
  final int photos;

  bool get themed => theme.isNotEmpty;
  String get operation =>
      themed ? noteWebsiteDesignOperation : noteWebsiteOperation;

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
    if (themed &&
        ((theme != 'auto' && !websiteThemeIds.contains(theme)) ||
            photos < 0 ||
            photos > websiteMaxPhotos)) {
      throw const FormatException('Choose one of the website themes.');
    }
    final value = jsonEncode({
      'title': title.trim(),
      'text': content,
      'description': clean,
      if (themed) ...{'theme': theme, 'photos': photos},
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
    if (themed) ...{'theme': theme, 'photos': photos},
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
      theme: json['theme'] is String ? json['theme'] as String : '',
      photos: json['photos'] is int ? json['photos'] as int : 0,
    );
  }
}

/// One titled entry of a cards, list, timeline or stats section.
class WebsiteItem {
  const WebsiteItem({required this.title, required this.text});
  final String title, text;

  Map<String, Object> toJson() => {'title': title, 'text': text};
}

class WebsiteSection {
  const WebsiteSection({
    required this.kind,
    this.heading = '',
    this.body = '',
    this.items = const [],
    this.photo = -1,
  });
  final String kind, heading, body;
  final List<WebsiteItem> items;

  /// Index into the note's image attachments, or -1 for none.
  final int photo;

  Map<String, Object> toJson() => {
    'kind': kind,
    'heading': heading,
    'body': body,
    'items': [for (final item in items) item.toJson()],
    'photo': photo,
  };
}

/// The structure of a themed website, in the note's own words. Every string
/// is plain text; the renderer escapes it.
class WebsiteSpec {
  const WebsiteSpec({
    required this.theme,
    required this.accent,
    required this.heading,
    this.tagline = '',
    required this.sections,
  });
  final String theme, accent, heading, tagline;
  final List<WebsiteSection> sections;

  WebsiteSpec withStyle({String? theme, String? accent}) => WebsiteSpec(
    theme: theme ?? this.theme,
    accent: accent ?? this.accent,
    heading: heading,
    tagline: tagline,
    sections: sections,
  );

  String encode() => jsonEncode({
    'theme': theme,
    'accent': accent,
    'hero': {'heading': heading, 'tagline': tagline},
    'sections': [for (final section in sections) section.toJson()],
  });

  /// Throws [FormatException] unless [raw] is a spec within the contract.
  /// [photos] bounds photo indexes; null skips that check (a synced page
  /// may come from a device with different attachments).
  factory WebsiteSpec.decode(String raw, {int? photos}) {
    var text = raw.trim();
    final fence = RegExp(
      r'^```(?:json)?\s*\n([\s\S]*?)\n?```$',
      caseSensitive: false,
    ).firstMatch(text);
    if (fence != null) text = fence.group(1)!.trim();
    if (utf8.encode(text).length > websiteSpecBytes) {
      throw const FormatException('Oversized website');
    }
    Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw const FormatException('Invalid website');
    }
    String plain(Object? value, int chars, {bool lines = false}) {
      if (value is! String ||
          value.runes.length > chars ||
          (lines ? _control : RegExp(r'[\x00-\x1f\x7f]')).hasMatch(value)) {
        throw const FormatException('Invalid website');
      }
      return value;
    }

    Map keyed(Object? value, String keys) {
      if (value is! Map ||
          (value.keys.map((k) => '$k').toList()..sort()).join(',') != keys) {
        throw const FormatException('Invalid website');
      }
      return value;
    }

    final spec = keyed(json, 'accent,hero,sections,theme');
    final hero = keyed(spec['hero'], 'heading,tagline');
    final sections = spec['sections'];
    if (!websiteThemeIds.contains(spec['theme']) ||
        !websiteAccents.contains(spec['accent']) ||
        sections is! List ||
        sections.isEmpty ||
        sections.length > 8) {
      throw const FormatException('Invalid website');
    }
    return WebsiteSpec(
      theme: spec['theme'] as String,
      accent: spec['accent'] as String,
      heading: plain(hero['heading'], 80),
      tagline: plain(hero['tagline'], 160),
      sections: [
        for (final value in sections)
          () {
            final section = keyed(value, 'body,heading,items,kind,photo');
            final items = section['items'], photo = section['photo'];
            if (!websiteSectionKinds.contains(section['kind']) ||
                items is! List ||
                items.length > 6 ||
                photo is! int ||
                photo < -1 ||
                photo >= (photos ?? websiteMaxPhotos)) {
              throw const FormatException('Invalid website');
            }
            return WebsiteSection(
              kind: section['kind'] as String,
              heading: plain(section['heading'], 80),
              body: plain(section['body'], 600, lines: true),
              items: [
                for (final item in items)
                  () {
                    final entry = keyed(item, 'text,title');
                    return WebsiteItem(
                      title: plain(entry['title'], 80),
                      text: plain(entry['text'], 240, lines: true),
                    );
                  }(),
              ],
              photo: photo,
            );
          }(),
      ],
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
