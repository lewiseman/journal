import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown/markdown.dart' as md;

import 'presentation_contract.dart';
import 'presentation_repository.dart';

/// Source and derivative streams are deliberately independent: local styling
/// never increments a source clock or inserts an upload operation.
class PresentationBody extends ConsumerWidget {
  const PresentationBody({
    super.key,
    required this.source,
    required this.content,
    required this.fallback,
    this.selectable = true,
  });
  final PresentationSourceRef source;
  final String content;
  final Widget fallback;
  final bool selectable;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(presentationRecordProvider(source.key)).value;
    if (record == null || !record.enabled) {
      return fallback;
    }
    final live = ref.watch(presentationSourceProvider(source));
    final current =
        live.value ?? ref.read(presentationRepositoryProvider).source(source);
    Widget original() => selectable
        ? SelectableText(current?.content ?? content)
        : Text(current?.content ?? content);
    if (live.hasValue && current == null) {
      return const Text('Source no longer available.');
    }
    if (record.policy != presentationPolicy) return original();
    try {
      final snapshot = PresentationSnapshot.decode(record.snapshot);
      if (snapshot.ref.key != source.key ||
          snapshot.content != content ||
          !ref.read(presentationRepositoryProvider).matches(snapshot)) {
        return original();
      }
      final blocks = PresentationBlocks(
        content,
        markdown: source.kind == 'note',
      );
      return SafePresentationBody(
        blocks: blocks,
        document: SafePresentationDocument.decode(
          record.document,
          blocks.nodes.length,
        ),
        original: content,
        selectable: selectable,
      );
    } catch (_) {
      return original();
    }
  }
}

class SafePresentationBody extends StatelessWidget {
  const SafePresentationBody({
    super.key,
    required this.blocks,
    required this.document,
    required this.original,
    this.selectable = true,
    this.renderBlock,
  });
  final PresentationBlocks blocks;
  final SafePresentationDocument document;
  final String original;
  final bool selectable;
  final Widget Function(md.Node)? renderBlock;
  @override
  Widget build(BuildContext context) {
    try {
      final safe = SafePresentationDocument.decode(
        document.encode(),
        blocks.nodes.length,
      );
      final base = DefaultTextStyle.of(context).style;
      final ink = base.color ?? Theme.of(context).colorScheme.onSurface;
      final body = (base.fontSize ?? 16).clamp(16.0, 32.0);
      final children = <Widget>[];
      for (var i = 0; i < blocks.nodes.length; i++) {
        final values = safe.blocks[i].values;
        double em(String? v, double fallback) =>
            v == null ? fallback : double.parse(v.replaceAll('em', ''));
        final size = body * em(values['font-size'], 1);
        final style = base.copyWith(
          color: ink,
          fontSize: size,
          height: em(values['line-height'], 1.6),
          fontStyle: values['font-style'] == 'italic'
              ? FontStyle.italic
              : FontStyle.normal,
          fontWeight: FontWeight
              .values[(int.parse(values['font-weight'] ?? '400') ~/ 100) - 1],
        );
        final theme = Theme.of(context);
        final styles =
            MarkdownStyleSheet.fromTheme(
              theme.copyWith(
                textTheme: theme.textTheme.apply(
                  bodyColor: ink,
                  displayColor: ink,
                ),
              ),
            ).copyWith(
              p: style,
              listBullet: style,
              blockquote: style,
              code: style.copyWith(fontFamily: 'monospace'),
              h1: style.copyWith(
                fontSize: size * 1.6,
                fontWeight: FontWeight.bold,
              ),
              h2: style.copyWith(
                fontSize: size * 1.4,
                fontWeight: FontWeight.bold,
              ),
              h3: style.copyWith(
                fontSize: size * 1.2,
                fontWeight: FontWeight.bold,
              ),
              h4: style.copyWith(fontWeight: FontWeight.bold),
              h5: style.copyWith(fontWeight: FontWeight.bold),
              h6: style.copyWith(fontWeight: FontWeight.bold),
              a: style,
            );
        final node = _offlineNode(blocks.nodes[i]);
        final builder = MarkdownBuilder(
          delegate: _OfflineDelegate(context),
          selectable: selectable,
          styleSheet: styles,
          imageDirectory: null,
          imageBuilder: (_, _, _) => const Text('[Image]'),
          checkboxBuilder: (checked) => Text(checked ? '☑' : '☐'),
          bulletBuilder: null,
          builders: {},
          paddingBuilders: {},
          listItemCrossAxisAlignment:
              MarkdownListItemCrossAxisAlignment.baseline,
        );
        Widget child =
            renderBlock?.call(node) ??
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: builder.build([node]),
            );
        if (node is md.Element && RegExp(r'^h[1-6]$').hasMatch(node.tag)) {
          child = Semantics(
            headingLevel: int.parse(node.tag.substring(1)),
            child: child,
          );
        }
        children.add(
          Padding(
            padding: EdgeInsets.only(
              left: body * em(values['padding-left'], 0),
              bottom: body * em(values['margin-bottom'], 1),
            ),
            child: child,
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      );
    } catch (_) {
      return selectable ? SelectableText(original) : Text(original);
    }
  }
}

md.Node _offlineNode(md.Node node) {
  if (node is! md.Element) return md.Text(node.textContent);
  if (node.tag == 'img') {
    return md.Text('[Image: ${node.attributes['alt'] ?? 'image'}]');
  }
  const tags = {
    'p',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'ul',
    'ol',
    'li',
    'blockquote',
    'em',
    'strong',
    'del',
    'code',
    'pre',
    'br',
    'hr',
    'table',
    'thead',
    'tbody',
    'tr',
    'th',
    'td',
    'input',
    'span',
  };
  if (node.tag == 'a') {
    return md.Element('span', [
      for (final c in node.children ?? <md.Node>[]) _offlineNode(c),
    ]);
  }
  if (!tags.contains(node.tag)) return md.Text(node.textContent);
  final result = md.Element(node.tag, [
    for (final c in node.children ?? <md.Node>[]) _offlineNode(c),
  ]);
  // Only source list numbering and inert checkbox state have rendering meaning.
  for (final key in ['start', 'checked', 'type']) {
    if (node.attributes.containsKey(key)) {
      result.attributes[key] = node.attributes[key]!;
    }
  }
  return result;
}

class _OfflineDelegate implements MarkdownBuilderDelegate {
  _OfflineDelegate(this.context);
  @override
  final BuildContext context;
  @override
  GestureRecognizer createLink(String text, String? href, String title) =>
      TapGestureRecognizer();
  @override
  TextSpan formatText(MarkdownStyleSheet styleSheet, String code) =>
      TextSpan(text: code, style: styleSheet.code);
}
