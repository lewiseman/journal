import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/config/theme.dart';
import 'package:journal/modules/assistant/qvac_assistant.dart';
import 'package:journal/modules/assistant/qvac_assistant_scope.dart';
import 'package:journal/modules/diary/controllers/diary_providers.dart';
import 'package:journal/modules/diary/models/diary_calendar_day.dart';
import 'package:journal/modules/diary/questions/daily_question_contract.dart';
import 'package:journal/modules/diary/questions/daily_question_controller.dart';
import 'package:journal/modules/diary/questions/daily_question_store.dart';
import 'package:journal/modules/diary/suggestions/diary_details_page.dart';
import 'package:journal/modules/diary/suggestions/diary_suggestion_contract.dart';
import 'package:journal/modules/diary/views/pages/diary_page.dart';
import 'package:journal/modules/diary/views/widgets/diary_assistant.dart';
import 'package:journal/modules/diary/views/widgets/diary_calendar.dart';
import 'package:journal/modules/diary/views/widgets/diary_ink_action.dart';
import 'package:journal/modules/diary/views/widgets/diary_sheet.dart';
import 'package:journal/modules/local_ai/core/ai_router.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/summary/summary_store.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/modules/voice/views/pages/diary_talk_page.dart';
import 'package:journal/modules/voice/voice.dart';
import 'package:sync_wise/sync_wise.dart';

import 'note_summary_test.dart' show TestReset;
import 'support/sync_fixture.dart';

class _Connection extends CompanionController {
  _Connection([this.phase = CompanionPhase.connected]);
  final CompanionPhase phase;
  @override
  CompanionState build() => CompanionState(phase: phase);
}

class _Summary extends NoteSummaryController {
  _Summary([this.initial = const NoteSummaryState()]);
  final NoteSummaryState initial;
  @override
  NoteSummaryState build() => initial;
}

class _Questions implements DailyQuestionPreference {
  _Questions(this.enabled);
  @override
  bool enabled;
  @override
  Future<void> setEnabled(bool value) async => enabled = value;
}

/// Daily questions on, with today matching the diary page's clock.
List<Override> _questions({bool enabled = true}) => [
  dailyQuestionPreferenceProvider.overrideWithValue(_Questions(enabled)),
  dailyQuestionClockProvider.overrideWithValue(() => DateTime(2026, 10, 26, 9)),
];

final _card = find.byKey(const ValueKey('diary-assistant-question'));

final _button = find.byKey(const ValueKey('qvac-assistant-button'));
final _microphone = find.byKey(const ValueKey('diary-assistant-microphone'));
final _settings = find.byKey(const ValueKey('qvac-local-ai-settings'));
final _captureKey = GlobalKey();

Future<SyncFixture> _mount(
  WidgetTester tester, {
  bool secondary = false,
  bool dark = false,
  double scale = 1,
  Size size = const Size(390, 844),
  List<Override> overrides = const [],
  NoteSummaryState summary = const NoteSummaryState(),
  CompanionPhase phase = CompanionPhase.connected,
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
      companionControllerProvider.overrideWith(() => _Connection(phase)),
      noteSummaryProvider.overrideWith(() => _Summary(summary)),
      accountResetProvider.overrideWith(TestReset.new),
      syncDeviceRoleProvider.overrideWithValue(
        secondary ? SyncDeviceRole.secondary : SyncDeviceRole.primary,
      ),
      ...overrides,
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
        tester.widget<DiaryAssistant>(find.byType(DiaryAssistant)).date,
        DateTime(2026, 10, 24),
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
      expect(_microphone, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      app.container.dispose();
    },
  );

  for (final secondary in [false, true]) {
    testWidgets(
      'day details opens without AI and respects editing rights: secondary=$secondary',
      (tester) async {
        final app = await _mount(
          tester,
          secondary: secondary,
          phase: CompanionPhase.idle,
          overrides: [
            ..._questions(enabled: false),
            aiOperationAvailableProvider('suggest-diary-day')
                .overrideWithValue(false),
            aiOperationAvailableProvider('ask-diary-question')
                .overrideWithValue(false),
          ],
        );
        await _select(tester, 24);
        await tester.tap(_button);
        await tester.pumpAndSettle();
        expect(tester.widget<DiaryInkAction>(_microphone).onPressed, isNull);
        await tester.tap(find.text('Day details'));
        await tester.pumpAndSettle();
        expect(find.byType(DiaryDetailsPage), findsOneWidget);
        expect(
          find.byKey(const ValueKey('diary-suggest-unavailable')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<ButtonStyleButton>(
                find.byKey(const ValueKey('diary-suggest')),
              )
              .onPressed,
          isNull,
        );

        final edit = find.byKey(const ValueKey('diary-details-edit'));
        if (secondary) {
          expect(edit, findsNothing);
          expect(
            find.byKey(const ValueKey('diary-details-read-only')),
            findsOneWidget,
          );
        } else {
          await tester.tap(edit);
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('diary-manual-title')),
            'A quiet afternoon',
          );
          await tester.tap(
            find.byKey(const ValueKey('diary-manual-mood-calm')),
          );
          await tester.enterText(
            find.byKey(const ValueKey('diary-manual-themes')),
            'outdoors, rest',
          );
          await tester.tap(find.byKey(const ValueKey('diary-manual-save')));
          await tester.pumpAndSettle();
          final saved = app.diary.getDay('2026-10-24')!;
          expect(saved.dayTitle, 'A quiet afternoon');
          expect(decodeDayMood(saved.dayMood), DiaryCalendarMood.calm);
          expect(saved.themes, ['outdoors', 'rest']);
          // ObjectBox's native watch events arrive outside the fake frame clock.
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pumpAndSettle();
          expect(find.text('Title: A quiet afternoon'), findsOneWidget);
          expect(find.text('Themes: outdoors, rest'), findsOneWidget);
          final scope = ProviderScope.containerOf(
            tester.element(find.byType(DiaryDetailsPage)),
          );
          expect(scope.read(noteSummaryProvider).handle, isNull);
          await _capture(tester, 'diary-details-offline');
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        app.container.dispose();
      },
    );
  }

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
          _microphone,
          150,
          scrollable: find.descendant(
            of: find.byKey(const ValueKey('diary-assistant-actions')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.ensureVisible(_microphone);
        await tester.pumpAndSettle();
        await _capture(tester, 'diary-menu-${layout.name}');
        await tester.tap(_microphone);
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
          tester.widget<DiaryAssistant>(find.byType(DiaryAssistant)).date,
          DateTime(2026, 10, 24),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'today shows its question with another-question; other days do not',
    (tester) async {
      final app = await _mount(
        tester,
        overrides: _questions(),
        phase: CompanionPhase.idle,
      );
      DailyQuestionStore(app.db.store).add(
        '2026-10-26',
        const DailyQuestion(
          text: 'What made you smile today?',
          evidence: '',
          ago: 0,
        ),
        basis: dailyQuestionBasis(app.diary.getDay('2026-10-26')),
      );
      await tester.pumpAndSettle();
      await tester.tap(_button);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: _card,
          matching: find.text('What made you smile today?'),
        ),
        findsOneWidget,
      );
      final another = find.byKey(const ValueKey('daily-question-another'));
      expect(tester.widget<DiaryInkAction>(another).label, 'Another question');
      // Not connected: AI actions rest and the page offers to connect.
      expect(tester.widget<DiaryInkAction>(another).onPressed, isNull);
      expect(tester.widget<DiaryInkAction>(_microphone).onPressed, isNull);
      expect(
        find.byKey(const ValueKey('diary-assistant-connect')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('daily-question-loading')),
        findsNothing,
      );
      Navigator.of(tester.element(find.byType(QvacAssistantSheet))).pop();
      await tester.pumpAndSettle();
      await _select(tester, 24);
      await tester.tap(_button);
      await tester.pumpAndSettle();
      expect(_card, findsNothing);
      expect(tester.takeException(), isNull);
      app.container.dispose();
    },
  );

  testWidgets('a question already requested shows loading instead of asking', (
    tester,
  ) async {
    final app = await _mount(
      tester,
      overrides: _questions(),
      summary: NoteSummaryState(
        phase: 'running',
        handle: SummaryHandle(
          id: 'asking-question',
          noteId: '2026-10-26',
          revision: 'r',
          computerId: 'c',
          created: 0,
          operation: dailyQuestionOperation,
        ),
      ),
    );
    await tester.tap(_button);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('daily-question-loading')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('daily-question-another')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    app.container.dispose();
  });

  testWidgets('with daily questions off the page leaves the question out', (
    tester,
  ) async {
    final app = await _mount(tester, overrides: _questions(enabled: false));
    await tester.tap(_button);
    await tester.pumpAndSettle();
    expect(_card, findsNothing);
    expect(find.byKey(const ValueKey('daily-question-another')), findsNothing);
    expect(find.byKey(const ValueKey('diary-assistant-offline')), findsNothing);
    app.container.dispose();
  });

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
      final microphone = _microphone;
      expect(tester.widget<DiaryInkAction>(microphone).onPressed, isNull);
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
      expect(tester.widget<DiaryInkAction>(microphone).onPressed, isNotNull);
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
