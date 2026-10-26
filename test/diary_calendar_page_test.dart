import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/config/theme.dart';
import 'package:journal/modules/diary/models/diary_calendar_day.dart';
import 'package:journal/utils/time_helper.dart';
import 'package:journal/modules/diary/models/sample.dart';
import 'package:journal/modules/diary/views/pages/diary_calendar_page.dart';
import 'package:journal/modules/settings/models/local_settings.dart';

final _today = DateTime(2026, 10, 26);
final _diaries = buildSampleDiaries(_today);
DiaryCalendarDay _dayData(DateTime date) => DiaryCalendarDay.fromEntity(
  _diaries
      .where((day) => day.dateString == TimeHelper.dateKey(date))
      .firstOrNull,
);
final _captureKey = GlobalKey();
final _scroll = find.byKey(const ValueKey('diary-calendar-scroll'));
final _yearPages = find.byKey(const ValueKey('calendar-year-pages'));
Finder _yearTab(int year) => find.byKey(ValueKey('calendar-year-tab-$year'));
Finder _day(DateTime date) =>
    find.byKey(ValueKey('calendar-day-${date.toIso8601String()}'));
Finder _month(DateTime date) =>
    find.byKey(ValueKey('calendar-month-${date.toIso8601String()}'));
Finder _week(DateTime date) =>
    find.byKey(ValueKey('calendar-week-summary-${date.toIso8601String()}'));
Finder _monthSummary(DateTime date) =>
    find.byKey(ValueKey('calendar-month-summary-${date.toIso8601String()}'));

Future<void> _mount(
  WidgetTester tester, {
  DateTime? initialDate,
  DateTime? lastDate,
  DateTime? firstDate,
  Size size = const Size(390, 844),
  double scale = 1,
  bool dark = false,
  bool reduced = false,
  AppAccent accent = AppAccent.indigo,
  List<DateTime?>? results,
  DiaryCalendarDay Function(DateTime)? dayData,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 16);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  final themes = AppThemeConfig.themesFor(accent);
  final theme = dark ? themes.dark : themes.light;
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'CalendarTest'),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduced,
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  final result = await Navigator.of(context).push<DateTime>(
                    MaterialPageRoute(
                      builder: (_) => DiaryCalendarPage(
                        initialDate: initialDate ?? _today,
                        lastDate: lastDate ?? _today,
                        firstDate: firstDate,
                        dayData: dayData ?? _dayData,
                      ),
                    ),
                  );
                  results?.add(result);
                },
                child: const Text('Open calendar'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open calendar'));
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CALENDAR_CAPTURES')) return;
  final context = tester.element(find.byType(DiaryCalendarPage));
  await tester.runAsync(() async {
    await precacheImage(
      const AssetImage('assets/images/diary_top_bg.png'),
      context,
    );
    await precacheImage(
      const AssetImage('assets/images/diary_calendar_pin.png'),
      context,
    );
  });
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/journal-calendar-$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final font = File.fromUri(
      File(Platform.resolvedExecutable).uri
          .resolve('../../material_fonts/Roboto-Regular.ttf'),
    );
    if (font.existsSync()) {
      await (FontLoader('CalendarTest')..addFont(
            Future.value(ByteData.sublistView(await font.readAsBytes())),
          ))
          .load();
    }
    final emoji = File('/System/Library/Fonts/Apple Color Emoji.ttc');
    if (const bool.fromEnvironment('CALENDAR_CAPTURES') && emoji.existsSync()) {
      await (FontLoader('Apple Color Emoji')..addFont(
            Future.value(ByteData.sublistView(await emoji.readAsBytes())),
          ))
          .load();
    }
  });

  test('sample dates are stable and include every mood and entry state', () {
    final moods = <DiaryCalendarMood>{};
    var empty = false;
    var entryWithoutMood = false;
    for (var i = 0; i < 30; i++) {
      final date = TimeHelper.addDays(_today, -i);
      final first = _dayData(date);
      final again = _dayData(DateTime(date.year, date.month, date.day, 23));
      expect(first.hasEntry, again.hasEntry);
      expect(first.mood, again.mood);
      empty |= !first.hasEntry;
      entryWithoutMood |= first.hasEntry && first.mood == null;
      if (first.mood != null) moods.add(first.mood!);
    }
    expect(moods, DiaryCalendarMood.values.toSet());
    expect(empty, isTrue);
    expect(entryWithoutMood, isTrue);
    expect(_dayData(DateTime(1)).hasEntry, isA<bool>());
  });

  testWidgets(
    'opens the selected month lazily and Today seeks without selecting',
    (tester) async {
      final datesBuilt = <DateTime>{};
      final results = <DateTime?>[];
      await _mount(
        tester,
        initialDate: DateTime(1980, 2, 4),
        results: results,
        dayData: (date) {
          datesBuilt.add(date);
          return _dayData(date);
        },
      );
      expect(_month(DateTime(1980, 2)), findsOneWidget);
      expect(_day(DateTime(1980, 2, 4)).hitTestable(), findsOneWidget);
      expect(datesBuilt.length, lessThan(200));
      await tester.tap(find.byKey(const ValueKey('calendar-today')));
      await tester.pumpAndSettle();
      expect(_month(DateTime(2026, 10)), findsOneWidget);
      expect(_day(_today).hitTestable(), findsOneWidget);
      expect(results, isEmpty);
      expect(datesBuilt.length, lessThan(400));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('returns an empty day as a normalized date and Back cancels', (
    tester,
  ) async {
    final results = <DateTime?>[];
    final emptyDate = DateTime(2026, 10, 3);
    await _mount(
      tester,
      initialDate: DateTime(2026, 10, 3, 14),
      results: results,
      dayData: (_) => const DiaryCalendarDay(hasEntry: false),
    );
    expect(
      tester.getSemantics(_day(emptyDate)).label,
      contains('No journal entry'),
    );
    await tester.tap(_day(emptyDate));
    await tester.pumpAndSettle();
    expect(results, [emptyDate]);
    expect(find.byType(DiaryCalendarPage), findsNothing);
    await tester.tap(find.text('Open calendar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(results, [emptyDate, null]);
  });

  testWidgets('year tabs and horizontal swipes agree and respect bounds', (
    tester,
  ) async {
    final results = <DateTime?>[];
    await _mount(
      tester,
      initialDate: DateTime(2025, 10, 2),
      firstDate: DateTime(2024),
      results: results,
    );
    expect(find.text('A little mood. A little memory.'), findsNothing);
    expect(find.text('Written'), findsNothing);
    expect(find.text('Mood'), findsNothing);
    await tester.tap(_yearTab(2024));
    await tester.pumpAndSettle();
    expect(_day(DateTime(2024, 1, 1)).hitTestable(), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Year 2024'))
          .flagsCollection
          .isSelected,
      ui.Tristate.isTrue,
    );
    await tester.drag(_yearPages, const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Year 2025'))
          .flagsCollection
          .isSelected,
      ui.Tristate.isTrue,
    );
    expect(_day(DateTime(2025, 10, 2)).hitTestable(), findsOneWidget);
    await tester.drag(_yearPages, const Offset(300, 0));
    await tester.pumpAndSettle();
    await tester.drag(_yearPages, const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(_day(DateTime(2024, 1, 1)).hitTestable(), findsOneWidget);
    await tester.tap(_yearTab(2026));
    await tester.pumpAndSettle();
    await tester.drag(_yearPages, const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(_day(_today).hitTestable(), findsOneWidget);
    expect(_yearTab(2027), findsNothing);
    expect(results, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('year pages remember their vertical month position', (
    tester,
  ) async {
    await _mount(
      tester,
      initialDate: DateTime(2025, 6, 15),
      firstDate: DateTime(2024),
    );
    await tester.drag(_scroll, const Offset(0, 500));
    await tester.pumpAndSettle();
    final offset = tester.widget<CustomScrollView>(_scroll).controller!.offset;
    expect(offset, lessThan(0));
    await tester.drag(_yearPages, const Offset(-300, 0));
    await tester.pumpAndSettle();
    await tester.drag(_yearPages, const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CustomScrollView>(_scroll).controller!.offset,
      closeTo(offset, .01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling the year strip can select an older year directly', (
    tester,
  ) async {
    await _mount(tester);
    await tester.drag(
      find.byKey(const ValueKey('calendar-year-tabs')),
      const Offset(280, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(_yearTab(2023));
    await tester.pumpAndSettle();
    expect(_day(DateTime(2023, 1, 1)).hitTestable(), findsOneWidget);
    expect(tester.getCenter(_yearTab(2023)).dx, closeTo(195, 1));
    await _capture(tester, 'year-tabs-2023');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Today restores the current month after changing year pages', (
    tester,
  ) async {
    await _mount(
      tester,
      initialDate: DateTime(2026, 2, 2),
      firstDate: DateTime(2024),
    );
    await tester.drag(_yearPages, const Offset(300, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-today')));
    await tester.pumpAndSettle();
    expect(_day(_today).hitTestable(), findsOneWidget);
    await tester.drag(_yearPages, const Offset(300, 0));
    await tester.pumpAndSettle();
    await tester.drag(_yearPages, const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(_day(_today).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'future dates are absent, Monday is first, and moods have semantics',
    (tester) async {
      await _mount(tester);
      expect(_day(DateTime(2026, 10, 27)), findsNothing);
      expect(_month(DateTime(2026, 11)), findsNothing);
      final thursday = tester.getCenter(_day(DateTime(2026, 10, 1)));
      final monday = tester.getCenter(_day(DateTime(2026, 10, 5)));
      expect(thursday.dx, greaterThan(monday.dx));
      expect(monday.dx, closeTo(16 + (390 - 32) / 14, .01));
      final today = tester.getSemantics(_day(_today));
      expect(today.label, contains('Today'));
      expect(today.flagsCollection.isSelected, ui.Tristate.isTrue);
      for (var i = 1; i <= _today.day; i++) {
        final date = DateTime(2026, 10, i);
        final data = _dayData(date);
        if (data.mood != null) {
          expect(
            tester.getSemantics(_day(date)).label,
            contains('${data.mood!.label} mood'),
          );
          break;
        }
      }
      await tester.drag(_scroll, const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(_month(DateTime(2026, 11)), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('history scrolls upwards and cross-month weeks appear once', (
    tester,
  ) async {
    await _mount(tester);
    expect(_week(DateTime(2026, 9, 28)), findsOneWidget);
    await tester.drag(_scroll, const Offset(0, 560));
    await tester.pumpAndSettle();
    expect(_day(DateTime(2026, 9, 20)).hitTestable(), findsOneWidget);
    expect(_monthSummary(DateTime(2026, 9)), findsOneWidget);
    expect(_week(DateTime(2026, 9, 28)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leap days and the earliest supported year render correctly', (
    tester,
  ) async {
    await _mount(tester, initialDate: DateTime(2024, 2, 29));
    expect(_day(DateTime(2024, 2, 29)), findsOneWidget);
    final monthDays = find.descendant(
      of: _month(DateTime(2024, 2)),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('calendar-day-'),
      ),
    );
    expect(monthDays, findsNWidgets(29));
    await tester.pumpWidget(const SizedBox());
    await _mount(
      tester,
      initialDate: DateTime(1),
      firstDate: DateTime(1),
      lastDate: DateTime(1, 1, 2),
    );
    expect(_day(DateTime(1)), findsOneWidget);
    expect(_day(DateTime(1, 1, 2)), findsOneWidget);
    expect(_day(DateTime(1, 1, 3)), findsNothing);
    await tester.drag(_scroll, const Offset(0, 1000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final config in [
    (today: DateTime(2026, 10, 25), week: false, month: false),
    (today: DateTime(2026, 10, 26), week: true, month: false),
    (today: DateTime(2026, 10, 31), week: true, month: false),
    (today: DateTime(2026, 11), week: true, month: true),
  ]) {
    testWidgets('periods finish the following local day: ${config.today}', (
      tester,
    ) async {
      await _mount(
        tester,
        initialDate: DateTime(2026, 10, 1),
        lastDate: config.today,
      );
      expect(
        _week(DateTime(2026, 10, 19)),
        config.week ? findsOneWidget : findsNothing,
      );
      expect(
        _monthSummary(DateTime(2026, 10)),
        config.month ? findsOneWidget : findsNothing,
      );
    });
  }

  testWidgets('completed years show inert links; the current year has none', (
    tester,
  ) async {
    final results = <DateTime?>[];
    await _mount(tester, initialDate: DateTime(2025), results: results);
    final year = find.byKey(const ValueKey('calendar-year-summary-2025'));
    expect(year, findsOneWidget);
    for (final link in [
      year,
      _monthSummary(DateTime(2025, 1)),
      _week(DateTime(2024, 12, 30)),
    ]) {
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(find.byType(DiaryCalendarPage), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(results, isEmpty);
    }
    await tester.pumpWidget(const SizedBox());
    await _mount(tester, initialDate: DateTime(2026));
    expect(
      find.byKey(const ValueKey('calendar-year-summary-2026')),
      findsNothing,
    );
  });

  for (final config in [
    (
      name: 'light',
      size: const Size(390, 844),
      scale: 1.0,
      dark: false,
      reduced: false,
      accent: AppAccent.indigo,
    ),
    (
      name: 'narrow',
      size: const Size(320, 640),
      scale: 1.0,
      dark: false,
      reduced: false,
      accent: AppAccent.indigo,
    ),
    (
      name: 'large-type',
      size: const Size(320, 700),
      scale: 2.0,
      dark: false,
      reduced: false,
      accent: AppAccent.indigo,
    ),
    (
      name: 'dark',
      size: const Size(390, 844),
      scale: 1.0,
      dark: true,
      reduced: false,
      accent: AppAccent.indigo,
    ),
    (
      name: 'tablet-teal',
      size: const Size(1024, 1100),
      scale: 1.0,
      dark: true,
      reduced: false,
      accent: AppAccent.teal,
    ),
    (
      name: 'reduced',
      size: const Size(390, 844),
      scale: 1.0,
      dark: false,
      reduced: true,
      accent: AppAccent.terracotta,
    ),
  ]) {
    testWidgets('calendar layout and interactions: ${config.name}', (
      tester,
    ) async {
      final results = <DateTime?>[];
      await _mount(
        tester,
        size: config.size,
        scale: config.scale,
        dark: config.dark,
        reduced: config.reduced,
        accent: config.accent,
        results: results,
      );
      final date = _day(DateTime(2026, 10, 1));
      expect(tester.getSize(date).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(date).height, greaterThanOrEqualTo(44));
      final press = await tester.startGesture(tester.getCenter(date));
      await tester.pump(const Duration(milliseconds: 100));
      final scale = tester.widget<AnimatedScale>(
        find.descendant(of: date, matching: find.byType(AnimatedScale)),
      );
      expect(scale.scale, config.reduced ? 1 : .94);
      await press.cancel();
      await tester.pumpAndSettle();
      await _capture(tester, config.name);
      await tester.drag(_scroll, const Offset(0, 500));
      await tester.pumpAndSettle();
      await _capture(tester, '${config.name}-history');
      await tester.tap(find.byKey(const ValueKey('calendar-today')));
      await tester.pumpAndSettle();
      final moodDate = DateTime(2026, 10, 3);
      final sticker = find.descendant(
        of: _day(moodDate),
        matching: find.text(_dayData(moodDate).mood!.emoji),
      );
      // Tap the part of the sticker below the paper, inside the day's target.
      await tester.tapAt(tester.getCenter(sticker) + const Offset(0, 8));
      await tester.pumpAndSettle();
      expect(results, [moodDate]);
      expect(tester.takeException(), isNull);
    });
  }
}
