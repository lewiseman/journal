import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/config/theme.dart';
import 'package:journal/modules/diary/models/diary_day.dart';
import 'package:journal/modules/diary/views/pages/diary_page.dart';
import 'package:journal/modules/diary/views/pages/diary_calendar_page.dart';
import 'package:journal/modules/diary/views/pages/diary_search_page.dart';
import 'package:journal/modules/diary/views/widgets/diary_calendar.dart';
import 'package:journal/modules/diary/views/widgets/diary_header_control.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_curl.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_material.dart';
import 'package:journal/modules/diary/views/widgets/diary_scene.dart';
import 'package:journal/modules/root/views/widgets/bottom_navbar.dart';

final _today = DateTime(2026, 10, 25); // Short; the preceding day is long.
final _paper = find.byKey(const ValueKey('diary-active-paper'));
final _turnFace = find.byWidgetPredicate(
  (widget) => widget is DiaryPaperCurl && widget.visible && !widget.flat,
);
Finder _preview(WidgetTester tester) => find.byWidgetPredicate(
  (widget) =>
      widget is DiaryPaperCurl &&
      widget.visible &&
      widget.flat &&
      widget.shape ==
          DiaryPaperShape.forDate(diaryDayAfter(_selected(tester), -1)),
);
Finder _face(DateTime date) => find.byWidgetPredicate(
  (widget) =>
      widget is DiaryPaperCurl && widget.shape == DiaryPaperShape.forDate(date),
);
final _captureKey = GlobalKey();

NestedScrollViewState _scroll(WidgetTester tester) =>
    tester.state<NestedScrollViewState>(find.byType(NestedScrollView));
DiaryScene _scene(WidgetTester tester) =>
    tester.widget(find.byType(DiaryScene));
DateTime _selected(WidgetTester tester) => _scene(tester).day.date;
DiaryCalendar _calendar(WidgetTester tester) =>
    tester.widget<DiaryCalendar>(find.byType(DiaryCalendar));
Finder _calendarDate(DateTime date) =>
    find.byKey(ValueKey('diary-calendar-date-${date.toIso8601String()}'));

void _expectCalendarWithPaper(WidgetTester tester) {
  final scene = _scene(tester);
  expect(_calendar(tester).selectedDate, scene.day.date);
  expect(
    _calendar(tester).dayOffset,
    closeTo(-scene.direction * scene.turn, .00001),
  );
}

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
      tester
          .widget<Image>(find.byKey(const ValueKey('diary-header-artwork')))
          .image,
      tester.element(find.byType(DiaryPage)),
    ),
  );
  await tester.pump();
  if (!reduced) await _warmFaces(tester);
}

Future<void> _warmFaces(WidgetTester tester) async {
  final faces = tester
      .renderObjectList<RenderDiaryCurl>(find.byType(DiaryPaperCurl))
      .toList();
  for (var attempt = 0; attempt < 30; attempt++) {
    await tester.runAsync(() async {
      for (final face in faces) {
        face.prepareTextures();
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    });
    await tester.pump();
    if (faces.every((face) => face.debugReady)) return;
  }
  expect(faces.every((face) => face.debugReady), isTrue);
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
  await _warmFaces(tester);
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
    expect(tester.getRect(_preview(tester)).right, greaterThan(0));
    expect(_scroll(tester).innerController.offset, 0);
    await _capture(tester, 'rest');

    _scroll(tester).outerController.jumpTo(40);
    await tester.pump();
    expect(_scene(tester).collapse, closeTo(.5, .01));
    expect(tester.getRect(_paper).width, greaterThan(rest.width));
    expect(_scroll(tester).innerController.offset, 0);
    expect(_preview(tester), findsNothing);
    await _capture(tester, 'half');

    _scroll(tester).outerController.jumpTo(80);
    await tester.pumpAndSettle();
    final expanded = tester.getRect(_paper);
    expect(expanded.left, 0);
    expect(expanded.width, 390);
    expect(expanded.top, closeTo(106, .01));
    expect(_preview(tester), findsNothing);
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

  testWidgets('date-specific faces survive repeated swipes without recapture', (
    tester,
  ) async {
    await _mount(tester);
    for (final direction in [1, 1, 1, -1, -1, -1]) {
      final from = _selected(tester);
      final target = diaryDayAfter(from, -direction);
      final incoming = tester.renderObject<RenderDiaryCurl>(_face(target));
      expect(incoming.debugReady, isTrue);
      final captures = (
        incoming.debugFrontCaptures,
        incoming.debugBackCaptures,
      );
      final gesture = await tester.startGesture(tester.getRect(_paper).center);
      await gesture.moveBy(Offset(24.0 * direction, 0));
      await gesture.moveBy(Offset(140.0 * direction, 0));
      await tester.pump();
      expect(_turnFace, findsOneWidget);
      await gesture.up();
      var frames = 0;
      while (_scene(tester).busy && frames < 32) {
        await tester.pump(const Duration(milliseconds: 16));
        _expectCalendarWithPaper(tester);
        frames++;
      }
      expect(
        _scene(tester).busy,
        isFalse,
        reason: 'Release the turn at its visible endpoint',
      );
      expect(_selected(tester), target);
      expect(
        tester.renderObject<RenderDiaryCurl>(_face(target)),
        same(incoming),
      );
      expect((
        incoming.debugFrontCaptures,
        incoming.debugBackCaptures,
      ), captures);
      final source = tester.widget<DiaryPaperCurl>(_face(target));
      final live =
          tester.widget<CustomPaint>(_paper).painter! as DiaryPaperPainter;
      expect(source.shape, live.shape);
      expect(source.flat, isTrue);
      expect(source.visible, isFalse, reason: 'Resting text stays native');
      expect(
        find.byType(DiaryPaperCurl).evaluate().length,
        lessThanOrEqualTo(3),
      );
      await _warmFaces(tester);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'paper follows a drag, cancels, commits once, and blocks tomorrow',
    (tester) async {
      await _mount(tester);
      final center = tester.getRect(_paper).center;
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(25, 0));
      await gesture.moveBy(const Offset(110, 0));
      await tester.pump();
      expect(_turnFace, findsOneWidget);
      expect(_selected(tester), _today);
      _expectCalendarWithPaper(tester);
      await _capture(tester, 'curl-right');
      await gesture.cancel();
      await tester.pump(const Duration(milliseconds: 32));
      _expectCalendarWithPaper(tester);
      await tester.pumpAndSettle();
      expect(_selected(tester), _today);
      expect(_calendar(tester).dayOffset, 0);
      expect(_turnFace, findsNothing);

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
      await tester.pump(const Duration(milliseconds: 32));
      _expectCalendarWithPaper(tester);
      await tester.pumpAndSettle();
      expect(_selected(tester), _today);
      expect(_turnFace, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('calendar and paper share every turn frame in both directions', (
    tester,
  ) async {
    await _mount(tester);
    await _choose(tester, diaryDayAfter(_today, -1));
    for (final direction in [1, -1]) {
      final from = _selected(tester);
      final target = diaryDayAfter(from, -direction);
      final before = tester.getCenter(_calendarDate(target)).dx;
      final calendarCenter = tester.getCenter(find.byType(DiaryCalendar)).dx;
      final gesture = await tester.startGesture(tester.getRect(_paper).center);
      await gesture.moveBy(Offset(24.0 * direction, 0));
      await gesture.moveBy(Offset(110.0 * direction, 0));
      await tester.pump();
      _expectCalendarWithPaper(tester);
      expect(_selected(tester), from);
      expect(_calendar(tester).dayOffset.abs(), greaterThan(.25));
      expect(
        (tester.getCenter(_calendarDate(target)).dx - calendarCenter).abs(),
        lessThan((before - calendarCenter).abs()),
      );
      await gesture.up();
      var frames = 0;
      while (_scene(tester).busy && frames < 90) {
        await tester.pump(const Duration(milliseconds: 16));
        _expectCalendarWithPaper(tester);
        frames++;
      }
      expect(frames, greaterThan(2));
      expect(_scene(tester).busy, isFalse);
      expect(_selected(tester), target);
      expect(_calendar(tester).dayOffset, 0);
      final landed = tester.getCenter(_calendarDate(target));
      expect(landed.dx, closeTo(calendarCenter, .001));
      // A second calendar spring must never start after the paper lands.
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.getCenter(_calendarDate(target)), landed);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'calendar drags turn the paper and retain an expanded reading view',
    (tester) async {
      await _mount(tester);
      final center = tester.getCenter(find.byType(DiaryCalendar));
      final drag = await tester.startGesture(center);
      await drag.moveBy(const Offset(24, 0));
      await drag.moveBy(const Offset(30, 0));
      await tester.pump();
      expect(_turnFace, findsOneWidget);
      _expectCalendarWithPaper(tester);
      await drag.cancel();
      await tester.pumpAndSettle();
      expect(_selected(tester), _today);
      expect(_calendar(tester).dayOffset, 0);

      final blocked = await tester.startGesture(center);
      await blocked.moveBy(const Offset(-24, 0));
      await blocked.moveBy(const Offset(-90, 0));
      await tester.pump();
      expect(_scene(tester).blocked, isTrue);
      expect(_turnFace, findsNothing);
      _expectCalendarWithPaper(tester);
      await blocked.up();
      await tester.pumpAndSettle();
      expect(_selected(tester), _today);

      await tester.dragFrom(center, const Offset(80, 0));
      await tester.pumpAndSettle();
      expect(_selected(tester), diaryDayAfter(_today, -1));
      _scroll(tester).outerController.jumpTo(80);
      await tester.pumpAndSettle();
      _scroll(tester).innerController.jumpTo(100);
      await tester.pump();
      final reading = await tester.startGesture(
        tester.getCenter(find.byType(DiaryCalendar)),
      );
      await reading.moveBy(const Offset(24, 0));
      await reading.moveBy(const Offset(28, 0));
      await tester.pump();
      expect(_calendar(tester).dayOffset, lessThan(-.25));
      expect(_scene(tester).collapse, 1);
      expect(_turnFace, findsNothing);
      await reading.up();
      await tester.pumpAndSettle();
      expect(_selected(tester), diaryDayAfter(_today, -2));
      expect(_scene(tester).collapse, 1);
      expect(_scroll(tester).innerController.offset, 0);
      expect(_calendar(tester).dayOffset, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'month labels follow the turn and distant dates land immediately',
    (tester) async {
      await _mount(tester);
      final march = DateTime(2024, 3, 1);
      _calendar(tester).onDateChanged(march);
      await tester.pump();
      expect(_selected(tester), march);
      expect(_calendar(tester).selectedDate, march);
      expect(_calendar(tester).dayOffset, 0);
      expect(tester.getCenter(_calendarDate(march)).dx, 195);
      await tester.pumpAndSettle();

      final leap = DateTime(2024, 2, 29);
      final drag = await tester.startGesture(tester.getRect(_paper).center);
      await drag.moveBy(const Offset(24, 0));
      await drag.moveBy(const Offset(190, 0));
      await tester.pump();
      expect(_selected(tester), march);
      _expectCalendarWithPaper(tester);
      expect(
        tester
            .widget<DiaryHeaderControl>(
              find.byKey(const ValueKey('diary-date-control')),
            )
            .date,
        leap,
      );
      await drag.up();
      await tester.pumpAndSettle();
      expect(_selected(tester), leap);
      expect(tester.getCenter(_calendarDate(leap)).dx, 195);
      expect(_calendar(tester).dayOffset, 0);

      await _choose(tester, DateTime(2026, 1, 1));
      await tester.dragFrom(
        tester.getRect(_paper).center,
        const Offset(180, 0),
      );
      await tester.pumpAndSettle();
      expect(_selected(tester), DateTime(2025, 12, 31));
      _expectCalendarWithPaper(tester);
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
      expect(_turnFace, findsNothing);

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
        tester
            .widget<DiaryCalendarPage>(find.byType(DiaryCalendarPage))
            .lastDate,
        _today,
      );
      expect(find.byType(DatePickerDialog), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await _choose(tester, diaryDayAfter(_today, -1));
      await tester.dragFrom(
        tester.getRect(_paper).center,
        const Offset(0, -350),
      );
      await tester.pumpAndSettle();
      final offset = _scroll(tester).innerController.offset;
      await tester.tap(find.byTooltip('Choose date'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(_selected(tester), diaryDayAfter(_today, -1));
      expect(_scroll(tester).innerController.offset, offset);
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
    'full-page calendar returns a date into the existing reading view',
    (tester) async {
      await _mount(tester);
      await tester.dragFrom(
        tester.getRect(_paper).center,
        const Offset(0, -350),
      );
      await tester.pumpAndSettle();
      expect(_scene(tester).collapse, 1);
      await tester.tap(find.byTooltip('Choose date'));
      await tester.pumpAndSettle();
      final target = DateTime(2026, 10, 3);
      await tester.tap(
        find.byKey(ValueKey('calendar-day-${target.toIso8601String()}')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DiaryCalendarPage), findsNothing);
      expect(_selected(tester), target);
      expect(_calendar(tester).selectedDate, target);
      expect(_scene(tester).collapse, 1);
      expect(_scroll(tester).innerController.offset, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('expanded diary opens search and a result selects its day', (
    tester,
  ) async {
    await _mount(tester, reduced: true);
    await tester.tap(find.byTooltip('Search diary'));
    await tester.pumpAndSettle();
    expect(find.byType(DiarySearchPage), findsOneWidget);
    expect(find.bySemanticsLabel('Notes tab').hitTestable(), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(_selected(tester), _today);
    expect(_scene(tester).collapse, 0);

    await tester.tap(find.byTooltip('Search diary'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('diary-search-input')),
      'walk',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    final result = find.byKey(const ValueKey('diary-search-match-0'));
    await tester.ensureVisible(result);
    await tester.tap(result);
    await tester.pumpAndSettle();
    expect(find.byType(DiarySearchPage), findsNothing);
    expect(_selected(tester), diaryDayAfter(_today, -1));
    expect(_calendar(tester).selectedDate, _selected(tester));
    expect(_scroll(tester).innerController.offset, 0);
    expect(find.bySemanticsLabel('Notes tab').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'collapsed search cancels in place and reopens the same day at its start',
    (tester) async {
      await _mount(tester, reduced: true);
      await _choose(tester, diaryDayAfter(_today, -1));
      await tester.dragFrom(
        tester.getRect(_paper).center,
        const Offset(0, -450),
      );
      await tester.pumpAndSettle();
      final date = _selected(tester);
      final offset = _scroll(tester).innerController.offset;
      expect(offset, greaterThan(0));
      expect(_scene(tester).collapse, 1);
      await tester.tap(find.byTooltip('Search diary'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(_selected(tester), date);
      expect(_scroll(tester).innerController.offset, offset);

      await tester.tap(find.byTooltip('Search diary'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('diary-search-input')),
        'walk',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      final result = find.byKey(const ValueKey('diary-search-match-0'));
      await tester.ensureVisible(result);
      await tester.tap(result);
      await tester.pumpAndSettle();
      expect(_selected(tester), date);
      expect(_scene(tester).collapse, 1);
      expect(_scroll(tester).innerController.offset, 0);
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(_scene(tester).turn, greaterThan(0));
      expect(_selected(tester), _today);
      _expectCalendarWithPaper(tester);
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
      expect(_preview(tester), findsOneWidget);
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
      if (config.reduced) expect(_turnFace, findsNothing);
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
