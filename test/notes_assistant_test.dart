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
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/metadata/note_help_pages.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/summary/summary_store.dart';
import 'package:journal/modules/notes/views/pages/edit_note_page.dart';
import 'package:journal/modules/notes/views/pages/note_question_page.dart';
import 'package:journal/modules/notes/views/pages/notes_page.dart';
import 'package:journal/modules/notes/views/widgets/note_ai_widgets.dart';
import 'package:journal/modules/notes/views/widgets/note_card.dart';
import 'package:journal/modules/notes/views/widgets/notes_assistant.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:sync_wise/sync_wise.dart';

import 'note_help_test.dart' show HelpConnection;
import 'note_summary_test.dart' as summary;
import 'support/sync_fixture.dart';

typedef _Harness = ({
  SyncFixture app,
  ProviderContainer scope,
  summary.SummaryTransport wire,
});
final _captureKey = GlobalKey();
final _button = find.byKey(const ValueKey('qvac-assistant-button'));
final _menu = find.byKey(const ValueKey('notes-assistant-actions'));
final _ideas = find.byKey(const ValueKey('notes-assistant-ideas'));
final _search = find.byKey(const ValueKey('notes-assistant-search'));
const _idea = 'Plan a small garden for Saturday';

Future<_Harness> _mount(
  WidgetTester tester, {
  bool empty = false,
  bool dark = false,
  bool reducedMotion = true,
  double scale = 1,
}) async {
  final app = (await tester.runAsync(
    () => SyncFixture.create(MemoryDrive(), 'phone'),
  ))!;
  if (!empty) {
    app.notes.saveNote(
      uuid: 'garden',
      title: 'Garden plans',
      content: 'Plant tomatoes by the kitchen.',
      tags: ['🌱#Garden'],
    );
    app.notes.saveNote(
      uuid: 'weekend',
      title: 'Weekend list',
      content: 'Visit the market on Saturday.',
      tags: ['📝#Plans'],
    );
    app.notes.pinNote('garden');
  }
  final store = summary.MemorySummaries();
  final wire = summary.SummaryTransport(store)..output = '{"ideas":["$_idea"]}';
  final scope = ProviderContainer(
    overrides: [
      objectBoxProvider.overrideWithValue(app.db),
      syncStateStoreProvider.overrideWithValue(app.storage),
      notesRepositoryProvider.overrideWithValue(app.notes),
      summaryStoreProvider.overrideWithValue(store),
      companionTransportProvider.overrideWithValue(wire),
      companionControllerProvider.overrideWith(HelpConnection.new),
      accountResetProvider.overrideWith(summary.TestReset.new),
      syncDeviceRoleProvider.overrideWithValue(SyncDeviceRole.primary),
    ],
  );
  scope.read(noteSummaryProvider);
  await tester.runAsync(summary.settle);
  tester.view.physicalSize = scale > 1
      ? const Size(320, 568)
      : const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  final assistant = scope.read(qvacAssistantProvider);
  final nav = GlobalKey<NavigatorState>();
  final base = dark ? AppThemeConfig.darkTheme : AppThemeConfig.lightTheme;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: scope,
      child: RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: base.copyWith(
            textTheme: base.textTheme.apply(fontFamily: 'NotesAssistantTest'),
          ),
          navigatorKey: nav,
          navigatorObservers: [QvacAssistantObserver(assistant)],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reducedMotion,
              textScaler: TextScaler.linear(scale),
            ),
            child: QvacAssistantHost(
              controller: assistant,
              navigatorKey: nav,
              child: child!,
            ),
          ),
          home: QvacAssistantPage(
            label: 'Notes',
            root: true,
            child: Builder(
              // Pause the looping artwork, preserving normal sheet motion.
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: const Scaffold(body: NotesPage()),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.runAsync(summary.settle);
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    scope.dispose();
    app.container.dispose();
  });
  return (app: app, scope: scope, wire: wire);
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(_button);
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('QVAC_CAPTURES')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/journal-qvac-$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final font = File.fromUri(
      File(Platform.resolvedExecutable).uri
          .resolve('../../material_fonts/Roboto-Regular.ttf'),
    );
    await (FontLoader('NotesAssistantTest')..addFont(
          Future.value(ByteData.sublistView(await font.readAsBytes())),
        ))
        .load();
  });

  testWidgets(
    'the grid has only saved notes and QVAC has exactly two collection tools',
    (tester) async {
      final h = await _mount(tester);
      expect(find.byKey(const ValueKey('note-idea-shuffle')), findsNothing);
      expect(find.text('Idea shuffle'), findsNothing);
      expect(find.byType(NoteCard), findsNWidgets(2));
      final cards = tester.widgetList<NoteCard>(find.byType(NoteCard)).toList();
      expect(cards.map((card) => card.note.uuid), ['garden', 'weekend']);
      await _open(tester);
      expect(find.byType(NotesAssistant), findsOneWidget);
      expect(
        find.descendant(of: _menu, matching: find.byType(NoteAiToolCard)),
        findsNWidgets(2),
      );
      expect(tester.widget<NoteAiToolCard>(_ideas).onTap, isNotNull);
      expect(tester.widget<NoteAiToolCard>(_search).onTap, isNotNull);
      expect(find.text('AI note search'), findsOneWidget);
      expect(find.text('Coming soon'), findsNothing);
      expect(h.wire.posts, 0);
      expect(
        tester
            .widget<DraggableScrollableSheet>(
              find.byType(DraggableScrollableSheet),
            )
            .controller!
            .size,
        closeTo(.42, .01),
      );
      await _capture(tester, 'notes-menu');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('AI note search closes the sheet and opens a full page', (
    tester,
  ) async {
    final h = await _mount(tester);
    await _open(tester);
    await tester.tap(_search);
    await tester.pumpAndSettle();
    expect(find.byType(QvacAssistantSheet), findsNothing);
    expect(find.byType(NoteQuestionPage), findsOneWidget);
    expect(find.byKey(const ValueKey('note-question-field')), findsOneWidget);
    expect(h.wire.posts, 0);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(NotesPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the sheet follows a held phone swipe without snapping early',
    (tester) async {
      await _mount(tester, reducedMotion: false);
      await _open(tester);
      final sheet = tester
          .widget<DraggableScrollableSheet>(
            find.byType(DraggableScrollableSheet),
          )
          .controller!;
      final height = tester.getSize(find.byType(QvacAssistantSheet)).height;
      final initial = sheet.size;
      final gesture = await tester.startGesture(
        tester.getBottomLeft(_menu) + const Offset(195, -24),
      );
      await gesture.moveBy(const Offset(0, -50));
      await tester.pump(const Duration(milliseconds: 16));
      final held = sheet.size;
      expect(held, greaterThan(initial));
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        sheet.size,
        closeTo(held, .001),
        reason: 'Holding a finger still must not start a snap animation.',
      );
      for (var step = 0; step < 7; step++) {
        final before = sheet.size;
        await gesture.moveBy(const Offset(0, -40));
        await tester.pump(const Duration(milliseconds: 16));
        expect(sheet.size, closeTo(before + 40 / height, .001));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(sheet.size, closeTo(1, .001));

      final down = await tester.startGesture(tester.getCenter(_menu));
      for (var step = 0; step < 6; step++) {
        await down.moveBy(const Offset(0, 50));
        await tester.pump(const Duration(milliseconds: 16));
      }
      final collapsed = sheet.size;
      await tester.pump(const Duration(milliseconds: 80));
      expect(sheet.size, closeTo(collapsed, .001));
      await down.up();
      await tester.pumpAndSettle();
      expect(sheet.size, closeTo(initial, .001));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets('ideas open fully expanded and Back returns to the two tools', (
    tester,
  ) async {
    final h = await _mount(tester, reducedMotion: false);
    await _open(tester);
    await tester.tap(_ideas);
    await tester.pumpAndSettle();
    expect(find.byType(NoteIdeasPage), findsOneWidget);
    expect(find.byType(QvacAssistantSheet), findsOneWidget);
    expect(
      tester
          .widget<DraggableScrollableSheet>(
            find.byType(DraggableScrollableSheet),
          )
          .controller!
          .size,
      closeTo(1, .01),
    );
    final list = find.descendant(
      of: find.byType(NoteIdeasPage),
      matching: find.byType(ListView),
    );
    expect(
      PrimaryScrollController.of(tester.element(list)).positions.length,
      1,
    );
    expect(h.wire.posts, 0);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_menu, findsOneWidget);
    expect(find.byType(NoteIdeasPage), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(QvacAssistantSheet), findsNothing);
    expect(find.byType(NotesPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('using an AI idea closes the sheet and opens an unsaved note', (
    tester,
  ) async {
    final h = await _mount(tester);
    await _open(tester);
    await tester.tap(_ideas);
    await tester.pumpAndSettle();
    final start = find.byKey(const ValueKey('note-ideas-start'));
    await tester.scrollUntilVisible(
      start.hitTestable(),
      100,
      scrollable: find
          .descendant(
            of: find.byType(NoteIdeasPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.runAsync(() async {
      await tester.tap(start);
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pumpAndSettle();
    expect(h.wire.posts, 1);
    final idea = find.widgetWithText(ListTile, _idea);
    await tester.scrollUntilVisible(
      idea.hitTestable(),
      100,
      scrollable: find
          .descendant(
            of: find.byType(NoteIdeasPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.runAsync(() async {
      await tester.tap(idea);
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pumpAndSettle();
    expect(find.byType(QvacAssistantSheet), findsNothing);
    final editor = tester.widget<EditNotePage>(find.byType(EditNotePage));
    expect(editor.starterTitle, _idea);
    expect(editor.existingNote, isNull);
    final saved = await tester.runAsync(
      () => h.app.notes.watchActiveNotes().first,
    );
    expect(saved!.length, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an empty collection keeps its first-note action and QVAC tools',
    (tester) async {
      final h = await _mount(tester, empty: true);
      expect(find.byType(NoteCard), findsNothing);
      expect(find.text('Your first note'), findsOneWidget);
      expect(find.text('Idea shuffle'), findsNothing);
      await _open(tester);
      expect(_ideas, findsOneWidget);
      expect(_search, findsOneWidget);
      expect(h.wire.posts, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'both collection tools remain visible with large text on a small screen',
    (tester) async {
      await _mount(tester, dark: true, scale: 2);
      await _open(tester);
      expect(_ideas, findsOneWidget);
      expect(_search, findsOneWidget);
      expect(tester.getSize(_ideas).height, greaterThanOrEqualTo(48));
      final sheet = tester.getRect(
        find.byKey(const ValueKey('qvac-sheet-surface')),
      );
      expect(tester.getRect(_search).bottom, lessThanOrEqualTo(sheet.bottom));
      await _capture(tester, 'notes-menu-large-dark');
      expect(tester.takeException(), isNull);
    },
  );
}
