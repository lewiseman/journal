import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/diary/controllers/diary_providers.dart';
import 'package:journal/modules/diary/controllers/diary_repository.dart';
import 'package:journal/config/theme.dart';
import 'package:journal/modules/diary/models/diary_ai_conversation.dart';
import 'package:journal/modules/diary/models/diary_day_entity.dart';
import 'package:journal/modules/diary/models/diary_item.dart';
import 'package:journal/modules/diary/views/pages/add_diary_photos_page.dart';
import 'package:journal/modules/diary/views/pages/add_diary_text_page.dart';
import 'package:journal/modules/diary/views/widgets/diary_sheet.dart';
import 'package:journal/modules/diary/views/widgets/diary_writing_prompt.dart';

final _prompt = find.byKey(const ValueKey('diary-writing-prompt'));
final _actions = find.byKey(const ValueKey('diary-add-actions'));
final _lines = find.byKey(const ValueKey('diary-prompt-lines'));

/// Voice only keeps a repository; nothing is saved without spoken words.
class _Diary extends Fake implements DiaryRepository {}

DiaryItem _item(String id, String content, {bool deleted = false}) => DiaryItem(
  itemUuid: id,
  createdAt: DateTime.utc(2026, 10, 26, 8),
  updatedAt: DateTime.utc(2026, 10, 26, 9),
  content: content,
  isDeleted: deleted,
);

Future<void> _mount(
  WidgetTester tester,
  DiaryDayEntity day, {
  double width = 390,
  double minimumHeight = 0,
  double scale = 1,
  bool dark = false,
  bool canEdit = true,
  TextDirection direction = TextDirection.ltr,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [diaryRepositoryProvider.overrideWithValue(_Diary())],
    child: MaterialApp(
      theme: dark ? AppThemeConfig.darkTheme : AppThemeConfig.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: Directionality(textDirection: direction, child: child!),
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(
              child: DiaryAccess(
                canEdit: canEdit,
                today: DateTime(2026, 10, 26),
                child: DiaryDayContent(
                  key: const ValueKey('content'),
                  day: day,
                  minimumHeight: minimumHeight,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('items render as ordered paragraphs with embedded line breaks', (
    tester,
  ) async {
    final day =
        DiaryDayEntity(dateString: '2026-10-26', dayTitle: 'A quiet day')
          ..items = [
            _item(
              'first',
              ' First paragraph.\n\nAnother paragraph in this item. ',
            ),
            _item('hidden', 'Deleted prose.', deleted: true),
            _item('blank', ' \n '),
            _item('last', 'Last paragraph.'),
          ];
    await _mount(tester, day);
    expect(find.text('A quiet day'), findsOneWidget);
    final first = find.text(
      'First paragraph.\n\nAnother paragraph in this item.',
    );
    final last = find.text('Last paragraph.');
    expect(first, findsOneWidget);
    expect(last, findsOneWidget);
    expect(tester.getTopLeft(first).dy, lessThan(tester.getTopLeft(last).dy));
    expect(find.text('Deleted prose.'), findsNothing);
    expect(find.text('Presentation'), findsNothing);
    expect(find.text('No diary entries for this day.'), findsNothing);
    expect(find.text(DiaryWritingPrompt.question), findsOneWidget);
    for (final tooltip in ['Add image entry', 'More diary actions']) {
      final button = find.byTooltip(tooltip);
      expect(button, findsOneWidget);
      expect(
        tester.getTopLeft(button).dy,
        greaterThan(tester.getBottomLeft(last).dy),
      );
    }
    expect(find.byType(Checkbox), findsNothing);
    expect(find.textContaining('08:00'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing titles are omitted and empty/deleted days stay dated', (
    tester,
  ) async {
    final day = DiaryDayEntity(dateString: '2026-10-26');
    await _mount(tester, day);
    expect(find.text('Mon, 26 Oct 2026'), findsOneWidget);
    expect(find.textContaining('SAMPLE DAY'), findsNothing);
    expect(find.text('No diary entries for this day.'), findsNothing);
    expect(_prompt, findsOneWidget);
    expect(find.text('A day, held here.'), findsNothing);
    expect(find.text(''), findsNothing);
    for (final tooltip in ['Add image entry', 'More diary actions']) {
      expect(find.byTooltip(tooltip), findsOneWidget);
    }

    day.dayTitle = '  ';
    day.items = [_item('first', 'Visible prose.')];
    await _mount(tester, day);
    expect(find.text('Visible prose.'), findsOneWidget);
    expect(find.text('No diary entries for this day.'), findsNothing);
    expect(find.text('  '), findsNothing);

    day.dayTitle = 'Deleted title';
    day.isDeleted = true;
    await _mount(tester, day);
    expect(find.text('Deleted title'), findsNothing);
    expect(find.text('Visible prose.'), findsNothing);
    expect(find.text('No diary entries for this day.'), findsNothing);
    expect(_prompt, findsOneWidget);
  });

  testWidgets('cached content updates when the same entity is edited', (
    tester,
  ) async {
    final day = DiaryDayEntity(
      dateString: '2026-10-26',
      dayTitle: 'First title',
    )..items = [_item('first', 'Original paragraph.')];
    await _mount(tester, day);
    final state = tester.state(find.byType(DiaryDayContent));
    day.dayTitle = 'Changed title';
    day.items = [_item('first', 'Changed paragraph.')];
    await _mount(tester, day);
    expect(tester.state(find.byType(DiaryDayContent)), same(state));
    expect(find.text('Original paragraph.'), findsNothing);
    expect(find.text('First title'), findsNothing);
    expect(find.text('Changed title'), findsOneWidget);
    expect(find.text('Changed paragraph.'), findsOneWidget);
  });

  testWidgets('empty and title-only days center below the heading', (
    tester,
  ) async {
    final day = DiaryDayEntity(dateString: '2026-10-26');
    for (final title in [null, 'A quiet day']) {
      day.dayTitle = title;
      await _mount(tester, day, minimumHeight: 700);
      final content = tester.getRect(find.byType(DiaryDayContent));
      final heading = tester.getRect(
        find.byKey(const ValueKey('diary-day-heading')),
      );
      final actions = tester.getRect(_actions);
      expect(content.height, 700);
      expect(heading.top, content.top + 24);
      expect(actions.center.dx, closeTo(content.center.dx, .01));
      expect(
        actions.center.dy,
        closeTo((heading.bottom + content.bottom - 24) / 2, .01),
      );
      expect(actions.width, lessThanOrEqualTo(320));
    }

    final previousPainter = tester.widget<CustomPaint>(_lines).painter!;
    final previousQuestion = tester.widget(
      find.byKey(const ValueKey('diary-prompt-question')),
    );
    await _mount(tester, day, minimumHeight: 760);
    final painter = tester.widget<CustomPaint>(_lines).painter!;
    expect(painter.shouldRepaint(previousPainter), isFalse);
    expect(
      tester.widget(find.byKey(const ValueKey('diary-prompt-question'))),
      same(previousQuestion),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'read-only days retain their explanation and today can be edited',
    (tester) async {
      await _mount(
        tester,
        DiaryDayEntity(dateString: '2026-10-25'),
        canEdit: false,
        minimumHeight: 500,
      );
      expect(_prompt, findsNothing);
      expect(find.byType(IconButton), findsNothing);
      expect(
        find.text(
          'This device can add diary entries for today. Older days are read-only.',
        ),
        findsOneWidget,
      );
      await _mount(
        tester,
        DiaryDayEntity(dateString: '2026-10-26'),
        canEdit: false,
      );
      expect(_prompt, findsOneWidget);
      await _mount(tester, DiaryDayEntity(dateString: '2026-10-25'));
      expect(_prompt, findsOneWidget);
    },
  );

  testWidgets('the card keeps photos and writing while voice moves to QVAC', (
    tester,
  ) async {
    final day = DiaryDayEntity(dateString: '2026-10-26');
    final before = day.toSyncJson('test');
    await _mount(tester, day);
    expect(find.byTooltip('Add voice entry'), findsNothing);
    expect(find.byKey(const ValueKey('diary-details-open')), findsNothing);
    for (final label in ['Voice', 'Image', 'More']) {
      expect(find.text(label), findsNothing);
    }
    expect(
      tester.getSemantics(find.bySemanticsLabel(DiaryWritingPrompt.question)),
      matchesSemantics(
        label: DiaryWritingPrompt.question,
        hint: 'Write a diary entry',
        isButton: true,
        hasTapAction: true,
      ),
    );
    for (final tooltip in ['Add image entry', 'More diary actions']) {
      final button = find.byTooltip(tooltip);
      expect(tester.getSize(button), const Size(48, 48));
      final description = tester.getSemantics(button).getSemanticsData();
      expect('${description.label} ${description.tooltip}', contains(tooltip));
      await tester.tap(button);
      if (tooltip == 'Add image entry') {
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<AddDiaryPhotosPage>(find.byType(AddDiaryPhotosPage))
              .date,
          DateTime(2026, 10, 26),
        );
        await tester.tap(find.byTooltip('Close without saving'));
      }
      await tester.pumpAndSettle();
      expect(_prompt, findsOneWidget);
      expect(day.toSyncJson('test'), before);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the question opens text entry for the selected day', (
    tester,
  ) async {
    await _mount(tester, DiaryDayEntity(dateString: '2026-10-24'));
    await tester.tap(find.text(DiaryWritingPrompt.question));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AddDiaryTextPage>(find.byType(AddDiaryTextPage)).date,
      DateTime(2026, 10, 24),
    );
  });

  for (final config in [
    (width: 320.0, scale: 1.0, dark: false, direction: TextDirection.ltr),
    (width: 240.0, scale: 2.0, dark: true, direction: TextDirection.ltr),
    (width: 390.0, scale: 1.8, dark: true, direction: TextDirection.rtl),
  ]) {
    testWidgets(
      'every wrapped question line has a rule plus two blank rules: $config',
      (tester) async {
        await _mount(
          tester,
          DiaryDayEntity(dateString: '2026-10-26'),
          width: config.width,
          scale: config.scale,
          dark: config.dark,
          direction: config.direction,
        );
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.byKey(const ValueKey('diary-prompt-question')),
            matching: find.byType(RichText),
          ),
        );
        // Union actual glyph boxes per line, excluding trailing whitespace and
        // combining separate bidi runs on the same visual line.
        final byBottom = <double, Rect>{};
        for (
          var index = 0;
          index < DiaryWritingPrompt.question.length;
          index++
        ) {
          if (DiaryWritingPrompt.question[index] == ' ') continue;
          for (final box in paragraph.getBoxesForSelection(
            TextSelection(baseOffset: index, extentOffset: index + 1),
          )) {
            final rect = box.toRect();
            byBottom[box.bottom] =
                byBottom[box.bottom]?.expandToInclude(rect) ?? rect;
          }
        }
        final boxes = byBottom.values.toList()
          ..sort((a, b) => a.top.compareTo(b.top));
        expect(boxes.length, greaterThan(1));
        final painter = tester.widget<CustomPaint>(_lines).painter!;
        final size = tester.getSize(_lines);
        void draw(Canvas canvas) => painter.paint(canvas, size);
        expect(draw, paintsExactlyCountTimes(#drawPath, boxes.length + 2));
        final paths = <Path>[];
        expect(
          draw,
          paints..everything((method, arguments) {
            if (method == #drawPath) paths.add(arguments.first as Path);
            return true;
          }),
        );
        for (final (index, box) in boxes.indexed) {
          final rule = paths[index].getBounds();
          expect(rule.left, closeTo(box.left, 2));
          expect(rule.right, closeTo(box.right, 2));
          expect(rule.top, greaterThan(box.bottom));
          expect(
            rule.bottom,
            lessThan(
              index + 1 < boxes.length
                  ? boxes[index + 1].top
                  : paragraph.size.height,
            ),
          );
        }
        for (final rule in paths.skip(boxes.length)) {
          final bounds = rule.getBounds();
          expect(bounds.top, greaterThan(paragraph.size.height));
          expect(bounds.bottom, lessThan(size.height));
          expect(bounds.left, greaterThanOrEqualTo(0));
          expect(bounds.right, lessThanOrEqualTo(size.width));
        }
        await tester.ensureVisible(find.byTooltip('More diary actions'));
        await tester.pumpAndSettle();
        expect(
          find.byTooltip('More diary actions').hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a conversation entry shows its chip and stays curl-safe', (
    tester,
  ) async {
    final day = DiaryDayEntity(dateString: '2026-10-26')
      ..items = [
        DiaryItem(
          itemUuid: 'talk',
          createdAt: DateTime.utc(2026, 10, 26, 8),
          updatedAt: DateTime.utc(2026, 10, 26, 9),
          content: '',
          aiConversation: DiaryAiConversation(
            createdAt: DateTime.utc(2026, 10, 26, 8),
            turns: const [
              {'speaker': 'assistant', 'text': 'How was your day?'},
              {'speaker': 'user', 'text': 'Calm.'},
            ],
          ),
        ),
        _item('words', 'A written entry.'),
      ];
    await _mount(tester, day);
    expect(find.text('Conversation · no entry yet'), findsOneWidget);
    // The page curl snapshots this content and refuses composited layers.
    expect(
      tester
          .renderObject(find.byKey(const ValueKey('content')))
          .needsCompositing,
      isFalse,
    );
  });
}
