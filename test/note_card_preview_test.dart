import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/notes/models/note_entity.dart';
import 'package:journal/modules/notes/views/widgets/note_card.dart';
import 'package:journal/modules/notes/views/widgets/note_markdown_preview.dart';

const _markdown = '''
# Heading

**Bold** and _italic_



- item
- [ ] todo
- [x] done''';

const _plain = '''
Heading

Bold and italic''';

void main() {
  testWidgets('grid previews use one body style without blank gaps', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (uuid, content) in [
                ('markdown', _markdown),
                ('plain', _plain),
              ])
                Expanded(
                  child: NoteCard(
                    key: ValueKey(uuid),
                    note: NoteEntity(uuid: uuid, title: uuid, content: content),
                    // index 1 allows 9 lines, so nothing is clipped.
                    index: 1,
                    onTap: () {},
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    List<RenderParagraph> paragraphs(String uuid) => tester
        .renderObjectList<RenderParagraph>(
          find.descendant(
            of: find.descendant(
              of: find.byKey(ValueKey(uuid)),
              matching: find.byType(NoteMarkdownPreview),
            ),
            matching: find.byType(RichText),
          ),
        )
        // Skip the hidden overflow indicator, list bullets and checkbox icons.
        .where((p) => p.text.toPlainText().trim().length > 1)
        .where((p) => p.strutStyle != null)
        .toList();

    final markdown = paragraphs('markdown');
    final plain = paragraphs('plain');
    expect(markdown.map((p) => p.text.toPlainText()), [
      'Heading',
      'Bold and italic',
      'item',
      'todo',
      'done',
    ]);
    expect(plain.map((p) => p.text.toPlainText()), [
      'Heading',
      'Bold and italic',
    ]);

    // Every run of text, including headings and emphasis, renders alike.
    final styles = <(double?, FontWeight?, FontStyle?, TextDecoration?)>{};
    for (final paragraph in [...markdown, ...plain]) {
      paragraph.text.visitChildren((span) {
        if (span is TextSpan && (span.text?.isNotEmpty ?? false)) {
          final style = _effectiveStyle(paragraph.text, span);
          styles.add((
            style.fontSize,
            style.fontWeight ?? FontWeight.normal,
            style.fontStyle ?? FontStyle.normal,
            style.decoration ?? TextDecoration.none,
          ));
        }
        return true;
      });
    }
    expect(styles, hasLength(1), reason: '$styles');
    expect(
      tester.getSize(find.text('Heading').first).height,
      tester.getSize(find.text('Heading').last).height,
    );

    // Blocks sit flush: each line starts where the previous one ended.
    for (final list in [markdown, plain]) {
      for (var i = 1; i < list.length; i++) {
        final previous =
            list[i - 1].localToGlobal(Offset.zero).dy + list[i - 1].size.height;
        expect(
          list[i].localToGlobal(Offset.zero).dy,
          moreOrLessEquals(previous, epsilon: .5),
          reason: '"${list[i].text.toPlainText()}" follows a gap',
        );
      }
    }

    // Lists and tasks keep their markers.
    final card = find.byKey(const ValueKey('markdown'));
    expect(find.descendant(of: card, matching: find.text('•')), findsOneWidget);
    expect(
      find.descendant(
        of: card,
        matching: find.byIcon(Icons.check_box_outline_blank),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.byIcon(Icons.check_box)),
      findsOneWidget,
    );
  });
}

/// Resolves [target]'s style through its ancestors in [root].
TextStyle _effectiveStyle(InlineSpan root, InlineSpan target) {
  TextStyle? walk(InlineSpan span, TextStyle inherited) {
    final style = inherited.merge(span.style);
    if (identical(span, target)) return style;
    if (span is TextSpan) {
      for (final child in span.children ?? const <InlineSpan>[]) {
        final found = walk(child, style);
        if (found != null) return found;
      }
    }
    return null;
  }

  return walk(root, const TextStyle())!;
}
