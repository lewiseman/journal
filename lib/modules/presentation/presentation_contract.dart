import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:csslib/parser.dart' as css;
import 'package:csslib/visitor.dart' as cssast;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:markdown/markdown.dart' as md;

const presentationOperation = 'present-text';
const presentationPolicy = 1;
const presentationOutputBytes = 4096;

/// Presentations style saved notes only. Diary entries stay plain text.
class PresentationSourceRef {
  const PresentationSourceRef.note(this.id);
  final String id;
  String get key => 'note:$id';
  @override
  bool operator ==(Object other) =>
      other is PresentationSourceRef && key == other.key;
  @override
  int get hashCode => key.hashCode;
  Map<String, dynamic> toJson() => {'kind': 'note', 'id': id};
  factory PresentationSourceRef.fromJson(Map<String, dynamic> value) {
    final id = value['id'];
    if (id is! String ||
        id.isEmpty ||
        id.length > 80 ||
        id.contains(':') ||
        value['kind'] != 'note' ||
        value.containsKey('day')) {
      throw const FormatException('Invalid presentation source');
    }
    return PresentationSourceRef.note(id);
  }
}

class PresentationSnapshot {
  const PresentationSnapshot(this.ref, this.content, this.version);
  final PresentationSourceRef ref;
  final String content, version;
  String encode() => jsonEncode({
    'source': ref.toJson(),
    'content': content,
    'version': version,
  });
  factory PresentationSnapshot.decode(String raw) {
    final value = jsonDecode(raw) as Map<String, dynamic>;
    final result = PresentationSnapshot(
      PresentationSourceRef.fromJson(value['source'] as Map<String, dynamic>),
      value['content'] as String,
      value['version'] as String,
    );
    if (!presentationText(result.content, 65536) ||
        utf8.encode(result.version).length > 131072) {
      throw const FormatException('Invalid source snapshot');
    }
    return result;
  }
}

bool presentationText(String value, int maxBytes) =>
    value.trim().isNotEmpty &&
    utf8.encode(value).length <= maxBytes &&
    !RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]').hasMatch(value) &&
    !value.runes.any((r) => r >= 0xd800 && r <= 0xdfff);

/// Original AST nodes are never supplied by the model. Only references to these
/// immutable blocks can enter a presentation.
class PresentationBlocks {
  PresentationBlocks(String source) {
    if (!presentationText(source, 65536)) {
      throw const FormatException('Source must fit 64 KiB');
    }
    nodes = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    ).parseLines(const LineSplitter().convert(source));
    var count = 0;
    void check(md.Node node, int depth) {
      if (++count > 256 || depth > 16) {
        throw const FormatException('Source structure is too complex');
      }
      if (node is md.Element) {
        for (final child in node.children ?? <md.Node>[]) {
          check(child, depth + 1);
        }
      }
    }

    for (final node in nodes) {
      check(node, 1);
    }
    if (nodes.isEmpty || nodes.length > 16) {
      throw const FormatException('Choose text with 1–16 blocks');
    }
  }
  late final List<md.Node> nodes;
  String request(String intent) {
    if (intent.isNotEmpty && !presentationText(intent, 240)) {
      throw const FormatException('Styling intent must fit 240 bytes');
    }
    final raw = jsonEncode({
      'blocks': [
        for (var i = 0; i < nodes.length; i++)
          {'id': 'b$i', 'text': nodes[i].textContent},
      ],
      'intent': intent,
    });
    if (utf8.encode(raw).length > 2000) {
      throw const FormatException(
        'Text and styling intent must fit 2,000 bytes. Nothing was sent or truncated.',
      );
    }
    return raw;
  }
}

const presentationValues = <String, Set<String>>{
  'font-size': {'1em', '1.125em', '1.25em'},
  'font-weight': {'400', '500', '600', '700'},
  'font-style': {'normal', 'italic'},
  'line-height': {'1.4', '1.6', '1.8'},
  'margin-bottom': {'0', '0.5em', '1em', '1.5em'},
  'padding-left': {'0', '0.5em', '1em'},
};

class PresentationStyle {
  PresentationStyle(Map<String, String> values)
    : values = Map.unmodifiable(values);
  final Map<String, String> values;
}

class SafePresentationDocument {
  SafePresentationDocument(List<PresentationStyle> blocks)
    : blocks = List.unmodifiable(blocks);
  final List<PresentationStyle> blocks;
  String encode() => jsonEncode({
    'policy': presentationPolicy,
    'blocks': [for (final b in blocks) b.values],
  });
  factory SafePresentationDocument.decode(String raw, int count) {
    if (utf8.encode(raw).length > 8192) {
      throw const FormatException('Oversized presentation');
    }
    final value = jsonDecode(raw) as Map<String, dynamic>;
    final blocks = value['blocks'] as List;
    if (value['policy'] != presentationPolicy ||
        blocks.length != count ||
        count < 1 ||
        count > 16) {
      throw const FormatException('Unsupported presentation');
    }
    return SafePresentationDocument(
      blocks.map((b) {
        final values = Map<String, String>.from(b as Map);
        if (values.length > 6 ||
            values.entries.any(
              (e) => !(presentationValues[e.key]?.contains(e.value) ?? false),
            )) {
          throw const FormatException('Unsupported style');
        }
        return PresentationStyle(values);
      }).toList(),
    );
  }
}

/// Fail closed: no DOM/CSS is ever handed to a browser or rendering library.
SafePresentationDocument compilePresentation(String raw, int blockCount) {
  if (!presentationText(raw, presentationOutputBytes) ||
      blockCount < 1 ||
      blockCount > 16) {
    throw const FormatException('Invalid presentation');
  }
  final value = jsonDecode(raw) as Map<String, dynamic>;
  if (value.keys.toSet().difference({'html', 'css'}).isNotEmpty ||
      value.length != 2 ||
      value['html'] is! String ||
      value['css'] is! String) {
    throw const FormatException('Expected HTML and CSS only');
  }
  final parser = html.HtmlParser(value['html'] as String, strict: true);
  final fragment = parser.parseFragment();
  bool whitespace(dom.Node n) =>
      n is dom.Text && RegExp(r'^[\t\r\n ]*$').hasMatch(n.data);
  final roots = fragment.nodes.where((n) => !whitespace(n)).toList();
  if (parser.errors.isNotEmpty ||
      roots.length != 1 ||
      roots.single is! dom.Element) {
    throw const FormatException('Invalid template');
  }
  final article = roots.single as dom.Element;
  if (article.localName != 'article' ||
      article.namespaceUri != 'http://www.w3.org/1999/xhtml' ||
      article.attributes.isNotEmpty) {
    throw const FormatException('Invalid root');
  }
  final slots = article.nodes.where((n) => !whitespace(n)).toList();
  if (slots.length != blockCount) {
    throw const FormatException('Every source block is required');
  }
  final classes = <String>[];
  for (var i = 0; i < slots.length; i++) {
    final slot = slots[i];
    if (slot is! dom.Element ||
        slot.localName != 'section' ||
        slot.attributes.length != 2 ||
        slot.attributes['data-source'] != 'b$i' ||
        !RegExp(r'^s[0-7]$').hasMatch(slot.attributes['class'] ?? '') ||
        slot.nodes.any((n) => !whitespace(n))) {
      throw const FormatException('Invalid or reordered source reference');
    }
    classes.add(slot.attributes['class']!);
  }
  final cssText = value['css'] as String;
  if (cssText.contains('/*') ||
      cssText.contains('*/') ||
      cssText.contains('\\')) {
    throw const FormatException('CSS comments and escapes are unsupported');
  }
  final errors = <css.Message>[];
  final sheet = css.parse(cssText, errors: errors);
  if (errors.isNotEmpty || sheet.topLevels.length > 8) {
    throw const FormatException('Invalid CSS');
  }
  final styles = <String, PresentationStyle>{};
  // Inspect the parsed rule structure as well as its canonical span. The tiny
  // grammar deliberately excludes escapes, comments, cascade and functions.
  for (final rule in sheet.topLevels) {
    if (rule is! cssast.RuleSet) {
      throw const FormatException('Only class rules are supported');
    }
    final selector = rule.selectorGroup!.span!.text.trim();
    if (!RegExp(r'^\.s[0-7]$').hasMatch(selector) ||
        styles.containsKey(selector.substring(1))) {
      throw const FormatException('Invalid selector');
    }
    final declarations = rule.declarationGroup.declarations;
    if (declarations.length > 6) {
      throw const FormatException('Too many declarations');
    }
    final values = <String, String>{};
    for (final declaration in declarations) {
      if (declaration is! cssast.Declaration || declaration.important) {
        throw const FormatException('Invalid declaration');
      }
      final property = declaration.property;
      // csslib expression spans omit unit suffixes (for example em). Validate
      // the complete declaration span, after checking its parsed AST type.
      final literal = RegExp(r'^([a-z-]+)\s*:\s*([a-z0-9.]+)\s*;?$')
          .firstMatch(declaration.span.text.trim());
      final expression = literal?.group(2) ?? '';
      if (!(presentationValues[property]?.contains(expression) ?? false) ||
          values.containsKey(property) ||
          literal?.group(1) != property) {
        throw const FormatException('Unsupported CSS');
      }
      values[property] = expression;
    }
    styles[selector.substring(1)] = PresentationStyle(values);
  }
  if (classes.any((c) => !styles.containsKey(c))) {
    throw const FormatException('Undefined style');
  }
  return SafePresentationDocument([for (final c in classes) styles[c]!]);
}

/// A killable worker bounds parser execution, including malformed input.
Future<SafePresentationDocument> compilePresentationBounded(
  String raw,
  int count, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final port = ReceivePort();
  final elapsed = Stopwatch()..start();
  Isolate? worker;
  try {
    worker = await Isolate.spawn(
      (SendPort send) {
        try {
          send.send(compilePresentation(raw, count).encode());
        } catch (_) {
          send.send(null);
        }
      },
      port.sendPort,
      onError: port.sendPort,
      onExit: port.sendPort,
    );
    final remaining = timeout - elapsed.elapsed;
    if (remaining <= Duration.zero) {
      throw TimeoutException('Presentation parser timed out');
    }
    final result = await port.first.timeout(remaining);
    if (result is! String) {
      throw const FormatException('Presentation could not be rendered safely');
    }
    return SafePresentationDocument.decode(result, count);
  } finally {
    worker?.kill(priority: Isolate.immediate);
    port.close();
  }
}
