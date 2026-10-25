import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/config/theme.dart';
import 'package:journal/modules/diary/models/diary_day.dart';
import 'package:journal/modules/diary/views/pages/diary_page.dart';
import 'package:journal/modules/diary/views/widgets/diary_calendar.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_curl.dart';
import 'package:journal/modules/diary/views/widgets/diary_scene.dart';
import 'package:journal/modules/root/views/widgets/bottom_navbar.dart';

final _today = DateTime(2026, 10, 25); // Short; the preceding day is long.
final _paper = find.byKey(const ValueKey('diary-active-paper'));
final _preview = find.byKey(const ValueKey('diary-previous-preview'));
final _captureKey = GlobalKey();

NestedScrollViewState _scroll(WidgetTester tester) =>
    tester.state<NestedScrollViewState>(find.byType(NestedScrollView));
DiaryScene _scene(WidgetTester tester) =>
    tester.widget(find.byType(DiaryScene));
DateTime _selected(WidgetTester tester) => _scene(tester).day.date;

Future<void> _mount(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double scale = 1,
  bool dark = false,
  bool reduced = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 24);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  final theme = dark ? AppThemeConfig.darkTheme : AppThemeConfig.lightTheme;
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'DiaryTest'),
          primaryTextTheme: theme.primaryTextTheme.apply(
            fontFamily: 'DiaryTest',
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduced,
          ),
          child: child!,
        ),
        home: _Tabs(today: _today),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => precacheImage(
      const AssetImage('assets/images/diary_top_bg.png'),
      tester.element(find.byType(DiaryPage)),
    ),
  );
  await tester.pump();
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('DIARY_CAPTURES')) return;
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/journal-diary-$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _choose(WidgetTester tester, DateTime date) async {
  tester.widget<DiaryCalendar>(find.byType(DiaryCalendar)).onDateChanged(date);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final font = File.fromUri(
      File(Platform.resolvedExecutable).uri
          .resolve('../../material_fonts/Roboto-Regular.ttf'),
    );
    if (font.existsSync()) {
      await (FontLoader('DiaryTest')..addFont(
            Future.value(ByteData.sublistView(await font.readAsBytes())),
          ))
          .load();
    }
  });

  test('samples are stable and civil days cross calendar boundaries', () {
    final first = DiaryDay.sample(DateTime(2026, 10, 24, 23));
    final again = DiaryDay.sample(DateTime(2026, 10, 24));
    expect(first.title, again.title);
    expect(
      first.items.map((item) => item.text),
      again.items.map((item) => item.text),
    );
    expect(first.date, DateTime(2026, 10, 24));
    expect(
      first.items.length,
      greaterThan(DiaryDay.sample(_today).items.length),
    );
    expect(DiaryDay.sample(DateTime(1900)).items, isNotEmpty);
    expect(diaryDayAfter(DateTime(2024, 3, 1), -1), DateTime(2024, 2, 29));
    expect(diaryDayAfter(DateTime(2026), -1), DateTime(2025, 12, 31));
    expect(diaryDaysBetween(DateTime(2024, 2, 28), DateTime(2024, 3, 1)), 2);
    expect(diaryDaysBetween(DateTime(2026, 3, 8), DateTime(2026, 3, 9)), 1);
  });

  testWidgets('short and long sheets share expansion and restoration', (
    tester,
  ) async {
    await _mount(tester);
    final rest = tester.getRect(_paper);
    expect(rest.left, closeTo(48, 1));
    expect(rest.top, closeTo(198, 1));
    expect(tester.getRect(_preview).right, greaterThan(0));
    expect(_scroll(tester).innerController.offset, 0);
    await _capture(tester, 'rest');

    _scroll(tester).outerController.jumpTo(40);
    await tester.pump();
    expect(_scene(tester).collapse, closeTo(.5, .01));
    expect(tester.getRect(_paper).width, greaterThan(rest.width));
    expect(_scroll(tester).innerController.offset, 0);
    expect(tester.getRect(_preview).right, lessThan(0));
    await _capture(tester, 'half');

    _scroll(tester).outerController.jumpTo(80);
    await tester.pumpAndSettle();
    final expanded = tester.getRect(_paper);
    expect(expanded.left, 0);
    expect(expanded.width, 390);
    expect(expanded.top, closeTo(106, .01));
    expect(_preview, findsNothing);
    expect(find.bySemanticsLabel('Notes tab').hitTestable(), findsOneWidget);
    await _capture(tester, 'short-expanded');

    _scroll(tester).outerController.jumpTo(0);
    await tester.pumpAndSettle();
    expect(tester.getRect(_paper), rest);
    await tester.dragFrom(rest.center, const Offset(0, -130));
    await tester.pumpAndSettle();
    expect(_scene(tester).collapse, 1);
    _scroll(tester).outerController.jumpTo(0);
    await tester.pumpAndSettle();

    await _choose(tester, diaryDayAfter(_today, -1));
    expect(_selected(tester), DateTime(2026, 10, 24));
    expect(tester.getRect(_paper), rest);
    await tester.dragFrom(rest.center, const Offset(0, -350));
    await tester.pumpAndSettle();
    expect(_scene(tester).collapse, 1);
    expect(_scroll(tester).innerController.offset, greaterThan(0));
    await _capture(tester, 'long-reading');

    await tester.dragFrom(expanded.center, const Offset(0, 60));
    await tester.pumpAndSettle();
    expect(_scene(tester).collapse, 1);
    _scroll(tester).outerController.jumpTo(0);
    await tester.pumpAndSettle();
    expect(tester.getRect(_paper), rest);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'paper follows a drag, cancels, commits once, and blocks tomorrow',
    (tester) async {
      await _mount(tester);
      final center = tester.getRect(_paper).center;
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(25, 0));
      await gesture.moveBy(const Offset(70, 0));
      await tester.pump();
      expect(find.byType(DiaryPaperCurl), findsOneWidget);
      expect(_selected(tester), _today);
      await _capture(tester, 'curl-right');
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(_selected(tester), _today);
      expect(find.byType(DiaryPaperCurl), findsNothing);

      await tester.dragFrom(center, const Offset(170, 0));
      await tester.pumpAndSettle();
      expect(_selected(tester), diaryDayAfter(_today, -1));
      expect(
        tester.widget<DiaryCalendar>(find.byType(DiaryCalendar)).selectedDate,
        _selected(tester),
      );

      final reverse = await tester.startGesture(center);
      await reverse.moveBy(const Offset(-25, 0));
      await reverse.moveBy(const Offset(-95, 0));
      await tester.pump();
      await _capture(tester, 'curl-left');
      await reverse.up();
      // A second gesture during the settling turn cannot skip another day.
      await tester.dragFrom(center, const Offset(-180, 0));
      await tester.pumpAndSettle();
      expect(_selected(tester), _today);
      await tester.flingFrom(center, const Offset(-180, 0), 1300);
      await tester.pumpAndSettle();
      expect(_selected(tester), _today);
      expect(find.byType(DiaryPaperCurl), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'header changes preserve reading mode and reset long-to-short content',
    (tester) async {
      await _mount(tester);
      await _choose(tester, diaryDayAfter(_today, -1));
      await tester.dragFrom(
        tester.getRect(_paper).center,
        const Offset(0, -450),
      );
      await tester.pumpAndSettle();
      final date = _selected(tester);
      await tester.dragFrom(
        tester.getRect(_paper).center,
        const Offset(180, 0),
      );
      await tester.pumpAndSettle();
      expect(_selected(tester), date);
      expect(_scene(tester).collapse, 1);
      await _choose(tester, _today);
      expect(_selected(tester), _today);
      expect(_scene(tester).collapse, 1);
      expect(_scroll(tester).innerController.offset, 0);
      expect(find.byType(DiaryPaperCurl), findsNothing);

      await _choose(tester, DateTime(1980, 2, 4));
      expect(_selected(tester), DateTime(1980, 2, 4));
      expect(_scene(tester).collapse, 1);
      await _choose(tester, diaryDayAfter(_today, 1));
      expect(_selected(tester), DateTime(1980, 2, 4));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'date picker excludes future dates and tab switches retain reading',
    (tester) async {
      await _mount(tester);
      await tester.tap(find.byTooltip('Choose date'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<DatePickerDialog>(find.byType(DatePickerDialog)).lastDate,
        _today,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await _choose(tester, diaryDayAfter(_today, -1));
      await tester.dragFrom(
        tester.getRect(_paper).center,
        const Offset(0, -350),
      );
      await tester.pumpAndSettle();
      final offset = _scroll(tester).innerController.offset;
      await tester.tap(find.bySemanticsLabel('Notes tab'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Diary tab'));
      await tester.pumpAndSettle();
      expect(_selected(tester), diaryDayAfter(_today, -1));
      expect(_scroll(tester).innerController.offset, offset);
      expect(_scene(tester).collapse, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'small drags restore, flicks commit, and previews do not select',
    (tester) async {
      await _mount(tester);
      final rect = tester.getRect(_paper);
      await tester.tapAt(Offset(12, rect.center.dy));
      await tester.pumpAndSettle();
      expect(_selected(tester), _today);
      final slow = await tester.startGesture(rect.center);
      await slow.moveBy(
        const Offset(24, 0),
        timeStamp: const Duration(milliseconds: 100),
      );
      await slow.moveBy(
        const Offset(28, 0),
        timeStamp: const Duration(milliseconds: 400),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await slow.up(timeStamp: const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(_selected(tester), _today);
      await tester.flingFrom(rect.center, const Offset(70, 0), 1400);
      await tester.pumpAndSettle();
      expect(_selected(tester), diaryDayAfter(_today, -1));
      await tester.dragFrom(rect.center, const Offset(20, -160));
      await tester.pumpAndSettle();
      expect(_selected(tester), diaryDayAfter(_today, -1));
      expect(_scene(tester).collapse, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'calendar taps commit with the sheet and a downward drag restores cards',
    (tester) async {
      await _mount(tester);
      final calendar = tester.element(find.byType(DiaryCalendar));
      final label = MaterialLocalizations.of(calendar)
          .formatFullDate(diaryDayAfter(_today, -1));
      await tester.tap(find.bySemanticsLabel(label).hitTestable());
      await tester.pumpAndSettle();
      expect(_selected(tester), diaryDayAfter(_today, -1));
      await tester.dragFrom(
        tester.getRect(_paper).center,
        const Offset(0, -280),
      );
      await tester.pumpAndSettle();
      final inner = _scroll(tester).innerController;
      inner.jumpTo(inner.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(
        find
            .byKey(ValueKey('diary-end-${_selected(tester).toIso8601String()}'))
            .hitTestable(),
        findsOneWidget,
      );
      await tester.timedDragFrom(
        tester.getRect(_paper).center,
        const Offset(0, 2400),
        const Duration(seconds: 2),
      );
      await tester.pumpAndSettle();
      expect(_scene(tester).collapse, 0);
      expect(_scroll(tester).innerController.offset, 0);
      expect(_preview, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final config in [
    (
      name: 'narrow',
      size: const Size(320, 640),
      scale: 1.0,
      dark: false,
      reduced: false,
    ),
    (
      name: 'large-type',
      size: const Size(390, 844),
      scale: 2.0,
      dark: false,
      reduced: false,
    ),
    (
      name: 'tablet-dark',
      size: const Size(1024, 1100),
      scale: 1.0,
      dark: true,
      reduced: false,
    ),
    (
      name: 'reduced',
      size: const Size(390, 844),
      scale: 1.0,
      dark: true,
      reduced: true,
    ),
  ]) {
    testWidgets('layout and navigation: ${config.name}', (tester) async {
      await _mount(
        tester,
        size: config.size,
        scale: config.scale,
        dark: config.dark,
        reduced: config.reduced,
      );
      expect(
        tester.getSize(find.byType(DiaryScene)).width,
        lessThanOrEqualTo(700),
      );
      await _capture(tester, config.name);
      await tester.dragFrom(
        tester.getRect(_paper).center,
        Offset(tester.getRect(_paper).width * .5, 0),
      );
      await tester.pumpAndSettle();
      expect(_selected(tester), diaryDayAfter(_today, -1));
      if (config.reduced) expect(find.byType(DiaryPaperCurl), findsNothing);
      _scroll(tester).outerController.jumpTo(200);
      await tester.pumpAndSettle();
      expect(_scene(tester).collapse, 1);
      await _capture(tester, '${config.name}-expanded');
      expect(tester.takeException(), isNull);
    });
  }
}

class _Tabs extends StatefulWidget {
  const _Tabs({required this.today});
  final DateTime today;
  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> {
  bool diary = true;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: diary ? 0 : 1,
      children: [
        TickerMode(
          enabled: diary,
          child: DiaryPage(clock: () => widget.today),
        ),
        const Center(child: Text('Notes')),
      ],
    ),
    bottomNavigationBar: JournalBottomNavbar(
      selectedIndex: diary ? 0 : 1,
      onSelected: (index) => setState(() => diary = index == 0),
    ),
  );
}
