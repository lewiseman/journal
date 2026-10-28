import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/config/theme.dart';
import 'package:journal/modules/assistant/qvac_assistant.dart';
import 'package:journal/modules/assistant/qvac_assistant_scope.dart';
import 'package:journal/modules/diary/controllers/diary_providers.dart';
import 'package:journal/modules/diary/suggestions/diary_details_page.dart';
import 'package:journal/modules/diary/views/pages/diary_page.dart';
import 'package:journal/modules/diary/views/widgets/diary_calendar.dart';
import 'package:journal/modules/diary/views/widgets/diary_sheet.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/modules/voice/views/pages/diary_talk_page.dart';
import 'package:journal/modules/voice/voice.dart';
import 'package:sync_wise/sync_wise.dart';

import 'note_summary_test.dart' show TestReset;
import 'support/sync_fixture.dart';

class _Connection extends CompanionController {
  @override
  CompanionState build() => const CompanionState(phase: CompanionPhase.idle);
}

class _Summary extends NoteSummaryController {
  @override
  NoteSummaryState build() => const NoteSummaryState();
}

final _button = find.byKey(const ValueKey('qvac-assistant-button'));
final _settings = find.byKey(const ValueKey('qvac-local-ai-settings'));
final _captureKey = GlobalKey();

Future<SyncFixture> _mount(
  WidgetTester tester, {
  bool secondary = false,
  bool dark = false,
  double scale = 1,
  Size size = const Size(390, 844),
}) async {
  final app = (await tester.runAsync(
    () => SyncFixture.create(MemoryDrive(), 'phone'),
  ))!;
  app.diary.addTimelineItem(
    dateString: '2026-10-24',
    content: 'I enjoyed a quiet afternoon outside.',
  );
  if (secondary) {
    app.storage.setPrimary(
      const PrimaryDevice(deviceId: 'other', deviceName: 'Other', fileId: 'p'),
    );
  }
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  final scope = ProviderContainer.test(
    overrides: [
      objectBoxProvider.overrideWithValue(app.db),
      syncStateStoreProvider.overrideWithValue(app.storage),
      diaryRepositoryProvider.overrideWithValue(app.diary),
      companionControllerProvider.overrideWith(_Connection.new),
      noteSummaryProvider.overrideWith(_Summary.new),
      accountResetProvider.overrideWith(TestReset.new),
      syncDeviceRoleProvider.overrideWithValue(
        secondary ? SyncDeviceRole.secondary : SyncDeviceRole.primary,
      ),
    ],
  );
  final assistant = scope.read(qvacAssistantProvider);
  final nav = GlobalKey<NavigatorState>();
  final theme = dark ? AppThemeConfig.darkTheme : AppThemeConfig.lightTheme;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: scope,
      child: RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'QvacDiaryTest'),
          ),
          navigatorKey: nav,
          navigatorObservers: [QvacAssistantObserver(assistant)],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(scale),
            ),
            child: QvacAssistantHost(
              controller: assistant,
              navigatorKey: nav,
              child: child!,
            ),
          ),
          home: QvacAssistantPage(
            label: 'Diary',
            root: true,
            child: Scaffold(
              body: DiaryAccess(
                canEdit: !secondary,
                today: DateTime(2026, 10, 26),
                child: DiaryPage(
                  clock: () => DateTime(2026, 10, 26),
                  diaries: app.diary.getAllDays(),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
  return app;
}

Future<void> _select(WidgetTester tester, int day) async {
  tester
      .widget<DiaryCalendar>(find.byType(DiaryCalendar))
      .onDateChanged(DateTime(2026, 10, day));
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('QVAC_CAPTURES')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/journal-qvac-$name.png')
        .writeAsBytes(data!.buffer.asUint8List());
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
      await (FontLoader('QvacDiaryTest')..addFont(
            Future.value(ByteData.sublistView(await font.readAsBytes())),
          ))
          .load();
    }
  });

  testWidgets(
    'selected day details expand with scrolling and save in the sheet',
    (tester) async {
      final app = await _mount(tester);
      await _select(tester, 24);
      expect(find.byTooltip('Add voice entry'), findsNothing);
      expect(find.byKey(const ValueKey('diary-details-open')), findsNothing);
      await tester.tap(_button);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('diary-assistant-date')))
            .data,
        'Sat, 24 Oct 2026',
      );
      expect(_settings, findsOneWidget);
      expect(
        tester.getBottomLeft(_settings).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('qvac-sheet-surface')))
              .dy,
        ),
      );
      await _capture(tester, 'diary-menu');
      await tester.tap(find.text('Day details'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DiaryDetailsPage>(find.byType(DiaryDetailsPage))
            .dateString,
        '2026-10-24',
      );
      final sheet = tester
          .widget<DraggableScrollableSheet>(
            find.byType(DraggableScrollableSheet),
          )
          .controller!;
      final before = sheet.size;
      final list = find.descendant(
        of: find.byType(DiaryDetailsPage),
        matching: find.byType(ListView),
      );
      await tester.drag(list, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(sheet.size, greaterThan(before));
      expect(sheet.size, closeTo(1, .01));
      expect(_settings, findsNothing);
      await _capture(tester, 'diary-details-expanded');
      await tester.ensureVisible(find.text('Edit details yourself'));
      await tester.tap(find.text('Edit details yourself'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('diary-manual-title')),
        'A quiet afternoon',
      );
      await tester.tap(find.byKey(const ValueKey('diary-manual-save')));
      await tester.pumpAndSettle();
      expect(app.diary.getDay('2026-10-24')!.dayTitle, 'A quiet afternoon');
      expect(app.diary.getDay('2026-10-26'), isNull);
      expect(find.byType(QvacAssistantSheet), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Microphone'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      app.container.dispose();
    },
  );

  for (final layout in [
    (name: 'light', dark: false, scale: 1.0, size: const Size(390, 844)),
    (name: 'large-dark', dark: true, scale: 2.0, size: const Size(320, 568)),
  ]) {
    testWidgets(
      'microphone replaces the sheet with the full voice page in ${layout.name}',
      (tester) async {
        final app = await _mount(
          tester,
          dark: layout.dark,
          scale: layout.scale,
          size: layout.size,
        );
        await _select(tester, 24);
        final before = app.diary.getDay('2026-10-24')!.toSyncJson('test');
        await tester.tap(_button);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Microphone'),
          150,
          scrollable: find.descendant(
            of: find.byKey(const ValueKey('diary-assistant-actions')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.tap(find.text('Microphone'));
        await tester.pumpAndSettle();
        final voice = tester.widget<VoiceSessionPage>(
          find.byType(VoiceSessionPage),
        );
        expect(voice.mode, VoiceSessionMode.conversation);
        expect(voice.date, DateTime(2026, 10, 24));
        final talk = tester.widget<DiaryTalkPage>(find.byType(DiaryTalkPage));
        expect(talk.date, DateTime(2026, 10, 24));
        expect(talk.scrollController, isNull);
        expect(
          find.byType(QvacAssistantSheet, skipOffstage: false),
          findsNothing,
        );
        expect(find.byType(DraggableScrollableSheet), findsNothing);
        expect(_settings, findsNothing);
        await _capture(tester, 'diary-microphone-${layout.name}');
        await tester.ensureVisible(find.byTooltip('Close'));
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(find.byType(QvacAssistantSheet), findsNothing);
        expect(find.byType(VoiceSessionPage), findsNothing);
        expect(app.diary.getDay('2026-10-24')!.toSyncJson('test'), before);
        await tester.tap(_button);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('diary-assistant-date')))
              .data,
          'Sat, 24 Oct 2026',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('the diary menu offers no presentation styling', (tester) async {
    final app = await _mount(tester);
    await tester.tap(_button);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('diary-assistant-actions')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('diary-assistant-presentation')),
      findsNothing,
    );
    expect(find.text('Presentation'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    app.container.dispose();
  });

  testWidgets(
    'secondary devices can speak today but cannot change older days',
    (tester) async {
      await _mount(tester, secondary: true);
      await _select(tester, 24);
      await tester.tap(_button);
      await tester.pumpAndSettle();
      final microphone = find.descendant(
        of: find.byKey(const ValueKey('diary-assistant-microphone')),
        matching: find.byType(ListTile),
      );
      expect(tester.widget<ListTile>(microphone).enabled, false);
      await tester.tap(find.text('Day details'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('diary-details-read-only')),
        findsOneWidget,
      );
      Navigator.of(tester.element(find.byType(DiaryDetailsPage))).pop();
      await tester.pumpAndSettle();
      await _select(tester, 26);
      await tester.tap(_button);
      await tester.pumpAndSettle();
      expect(tester.widget<ListTile>(microphone).enabled, true);
      await tester.tap(microphone);
      await tester.pumpAndSettle();
      expect(
        find.byType(QvacAssistantSheet, skipOffstage: false),
        findsNothing,
      );
      expect(
        tester.widget<DiaryTalkPage>(find.byType(DiaryTalkPage)).date,
        DateTime(2026, 10, 26),
      );
    },
  );
}
