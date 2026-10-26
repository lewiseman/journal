import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/diary/models/diary_day_entity.dart';
import 'package:journal/modules/diary/models/diary_item.dart';
import 'package:journal/modules/diary/views/widgets/diary_sheet.dart';

DiaryItem _item(String id, String content, {bool deleted = false}) => DiaryItem(
  itemUuid: id,
  createdAt: DateTime.utc(2026, 10, 26, 8),
  updatedAt: DateTime.utc(2026, 10, 26, 9),
  content: content,
  isDeleted: deleted,
);

Future<void> _mount(WidgetTester tester, DiaryDayEntity day) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DiaryDayContent(key: const ValueKey('content'), day: day),
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
    expect(find.text('No diary entries for this day.'), findsNothing);
    for (final label in ['Add text', 'Add image', 'Add voice']) {
      final button = find.widgetWithText(TextButton, label);
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
    expect(find.textContaining('Mon, 26 Oct 2026'), findsOneWidget);
    expect(find.text('No diary entries for this day.'), findsOneWidget);
    expect(find.text('A day, held here.'), findsNothing);
    expect(find.text(''), findsNothing);
    for (final label in ['Add text', 'Add image', 'Add voice']) {
      expect(find.widgetWithText(TextButton, label), findsOneWidget);
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
    expect(find.text('No diary entries for this day.'), findsOneWidget);
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
}
