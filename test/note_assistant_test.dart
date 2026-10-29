import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:journal/modules/notes/views/widgets/note_ai_widgets.dart';
import 'package:journal/modules/notes/views/widgets/note_ai_loading.dart';
import 'package:journal/modules/notes/summary/summary_store.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/config/theme.dart';
import 'package:journal/modules/assistant/qvac_assistant.dart';
import 'package:journal/modules/assistant/qvac_assistant_scope.dart';
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/images/note_background_page.dart';
import 'package:journal/modules/notes/images/note_image_page.dart';
import 'package:journal/modules/notes/images/note_scan_page.dart';
import 'package:journal/modules/notes/metadata/note_help_pages.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/summary/summary_page.dart';
import 'package:journal/modules/notes/transform/transform_page.dart';
import 'package:journal/modules/notes/views/pages/edit_note_page.dart';
import 'package:journal/modules/presentation/note_presentation_page.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
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

  void running(String operation) => state = NoteSummaryState(
    phase: 'running',
    handle: SummaryHandle(
      id: 'loading-preview',
      noteId: 'selected-note',
      revision: 'a' * 64,
      computerId: 'computer',
      created: DateTime.now().millisecondsSinceEpoch,
      operation: operation,
      accepted: true,
    ),
  );

  void idle() => state = const NoteSummaryState();
}

final _button = find.byKey(const ValueKey('qvac-assistant-button'));
final _menu = find.byKey(const ValueKey('note-assistant-actions'));
final _settings = find.byKey(const ValueKey('qvac-local-ai-settings'));
final _captureKey = GlobalKey();

Future<SyncFixture> _mount(
  WidgetTester tester, {
  bool withImage = false,
  bool secondary = false,
  bool newNote = false,
  bool dark = false,
  bool reducedMotion = true,
  double scale = 1,
  Size size = const Size(390, 844),
}) async {
  final app = (await tester.runAsync(
    () => SyncFixture.create(MemoryDrive(), 'phone'),
  ))!;
  final image = File('${app.directory.path}/photo.png');
  if (withImage) {
    image.writeAsBytesSync(
      File('assets/images/notes_add.png').readAsBytesSync(),
    );
  }
  final note = newNote
      ? null
      : app.notes.saveNote(
          uuid: 'selected-note',
          title: 'An afternoon outside',
          content: 'A quiet walk by the river.',
          attachmentPaths: withImage
              ? [
                  {'path': image.path, 'type': 'image/png'},
                ]
              : [],
        );
  if (secondary) {
    app.storage.setPrimary(
      const PrimaryDevice(deviceId: 'other', deviceName: 'Other', fileId: 'p'),
    );
  }
  final scope = ProviderContainer.test(
    overrides: [
      objectBoxProvider.overrideWithValue(app.db),
      syncStateStoreProvider.overrideWithValue(app.storage),
      notesRepositoryProvider.overrideWithValue(app.notes),
      companionControllerProvider.overrideWith(_Connection.new),
      noteSummaryProvider.overrideWith(_Summary.new),
      accountResetProvider.overrideWith(TestReset.new),
      syncDeviceRoleProvider.overrideWithValue(
        secondary ? SyncDeviceRole.secondary : SyncDeviceRole.primary,
      ),
    ],
  );
  final assistant = scope.read(qvacAssistantProvider);
  final navigator = GlobalKey<NavigatorState>();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  final theme = dark ? AppThemeConfig.darkTheme : AppThemeConfig.lightTheme;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: scope,
      child: RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'NoteAssistantTest'),
          ),
          navigatorKey: navigator,
          navigatorObservers: [QvacAssistantObserver(assistant)],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reducedMotion,
              textScaler: TextScaler.linear(scale),
            ),
            child: QvacAssistantHost(
              controller: assistant,
              navigatorKey: navigator,
              child: child!,
            ),
          ),
          home: EditNotePage(existingNote: note),
        ),
      ),
    ),
  );
  if (withImage) {
    await tester.runAsync(() async {
      await precacheImage(FileImage(image), navigator.currentContext!);
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
  }
  await tester.pumpAndSettle();
  return app;
}

Future<void> _open(WidgetTester tester, String action) async {
  final tile = find.byKey(ValueKey('note-assistant-$action'));
  await tester.scrollUntilVisible(
    tile.hitTestable(),
    160,
    scrollable: find.descendant(of: _menu, matching: find.byType(Scrollable)),
  );
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

Future<void> _unmount(WidgetTester tester, SyncFixture app) async {
  await tester.pumpWidget(const SizedBox.shrink());
  app.container.dispose();
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
    await (FontLoader(
      'Lora',
    )..addFont(rootBundle.load('assets/fonts/Lora-Regular.ttf'))).load();
    final font = File.fromUri(
      File(Platform.resolvedExecutable).uri
          .resolve('../../material_fonts/Roboto-Regular.ttf'),
    );
    if (font.existsSync()) {
      await (FontLoader('NoteAssistantTest')..addFont(
            Future.value(ByteData.sublistView(await font.readAsBytes())),
          ))
          .load();
    }
  });

  testWidgets(
    'all note AI tools move from the header into the shared QVAC sheet',
    (tester) async {
      final app = await _mount(tester, withImage: true);
      expect(find.byTooltip('Summarize saved note'), findsNothing);
      expect(find.byTooltip('Writing help and recovery'), findsNothing);
      expect(find.byTooltip('Note options'), findsOneWidget);
      await tester.tap(_button);
      await tester.pumpAndSettle();
      expect(find.text('QVAC'), findsNothing);
      expect(find.byTooltip('Close'), findsNothing);
      expect(find.byKey(const ValueKey('note-assistant-title')), findsNothing);
      expect(find.text('No computer connected'), findsNothing);
      expect(_settings, findsOneWidget);
      expect(
        tester
            .widget<DraggableScrollableSheet>(
              find.byType(DraggableScrollableSheet),
            )
            .controller!
            .size,
        closeTo(.64, .01),
      );
      await _capture(tester, 'note-menu');
      for (final tool in <String, Type>{
        'summary': NoteSummaryPage,
        'writing': NoteTransformPage,
        'metadata': NoteMetadataPage,
        'image': NoteImagePage,
        'scan': NoteScanPage,
        'background': NoteBackgroundPage,
        'presentation': NotePresentationPage,
      }.entries) {
        await _open(tester, tool.key);
        expect(find.byType(tool.value), findsOneWidget);
        expect(find.byType(QvacAssistantSheet), findsOneWidget);
        final list = find.descendant(
          of: find.byType(tool.value),
          matching: find.byType(ListView),
        );
        final controller = PrimaryScrollController.of(tester.element(list));
        expect(controller.positions.length, 1);
        expect(
          tester
              .widget<DraggableScrollableSheet>(
                find.byType(DraggableScrollableSheet),
              )
              .controller!
              .size,
          closeTo(1, .01),
        );
        expect(_settings, findsNothing);
        await tester.drag(list, const Offset(0, -500));
        await tester.pumpAndSettle();
        controller.jumpTo(0);
        await tester.pumpAndSettle();
        await _capture(tester, 'note-${tool.key}-expanded');
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(_menu, findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await _unmount(tester, app);
    },
  );

  testWidgets(
    'every saved-note tool shares the loading view while its task runs',
    (tester) async {
      final app = await _mount(tester, withImage: true);
      final scope = ProviderScope.containerOf(
        tester.element(find.byType(EditNotePage)),
        listen: false,
      );
      final tasks = scope.read(noteSummaryProvider.notifier) as _Summary;
      await tester.tap(_button);
      await tester.pumpAndSettle();
      for (final entry in {
        'summary': 'summarize-note',
        'writing': 'rewrite-note',
        'metadata': 'suggest-note-metadata',
        'image': 'ask-note-image',
        'scan': 'scan-note-image',
        'background': 'generate-note-background',
        'presentation': 'present-website',
      }.entries) {
        await _open(tester, entry.key);
        tasks.running(entry.value);
        await tester.pumpAndSettle();
        expect(find.byType(NoteAiLoading), findsOneWidget, reason: entry.key);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.text('Listen'), findsNothing);
        tasks.idle();
        await tester.pumpAndSettle();
        expect(find.byType(NoteAiLoading), findsNothing);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: entry.key);
      }
      await _unmount(tester, app);
    },
  );

  testWidgets('opening a feature animates the compact sheet to full height', (
    tester,
  ) async {
    final app = await _mount(tester, reducedMotion: false);
    await tester.tap(_button);
    await tester.pumpAndSettle();
    final sheet = tester
        .widget<DraggableScrollableSheet>(find.byType(DraggableScrollableSheet))
        .controller!;
    expect(sheet.size, closeTo(.64, .01));
    await _open(tester, 'writing');
    expect(sheet.size, closeTo(1, .01));
    expect(find.byType(NoteTransformPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester, app);
  });

  testWidgets('dragging down dismisses the tools and their feature pages', (
    tester,
  ) async {
    final app = await _mount(tester);
    final handle = find.byKey(const ValueKey('qvac-sheet-handle'));
    for (final tool in [null, 'writing']) {
      await tester.tap(_button);
      await tester.pumpAndSettle();
      if (tool != null) {
        await _open(tester, tool);
      }
      await tester.drag(tool == null ? _menu : handle, const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(find.byType(QvacAssistantSheet), findsNothing);
      expect(find.byType(EditNotePage), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await _unmount(tester, app);
  });

  testWidgets('accepted title changes refresh the note and preserve Undo', (
    tester,
  ) async {
    final app = await _mount(tester);
    await tester.tap(_button);
    await tester.pumpAndSettle();
    await _open(tester, 'metadata');
    final before = app.notes.getNoteByUuid('selected-note')!;
    final after = app.notes.updateNoteMetadata(
      uuid: before.uuid,
      expectedVersion: before.versionVectorJson,
      title: 'River light',
      tags: before.tags,
    );
    Navigator.of(tester.element(find.byType(NoteMetadataPage))).pop(
      NoteMetadataUndo(
        noteId: before.uuid,
        title: before.title,
        tags: before.tags,
        version: after.versionVectorJson,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(QvacAssistantSheet), findsNothing);
    expect(find.text('River light'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(app.notes.getNoteByUuid(before.uuid)!.title, before.title);
    expect(find.text(before.title), findsOneWidget);
    await _unmount(tester, app);
  });

  // New notes get their own draft tools; see note_draft_ai_test.dart.
  for (final newNote in [false]) {
    testWidgets('editor drafts of saved notes keep AI tools unavailable', (
      tester,
    ) async {
      final app = await _mount(tester, newNote: newNote);
      if (!newNote) {
        await tester.drag(_button, const Offset(0, -180));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Edit note'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('note-content-editor')),
          'A draft that has not been saved.',
        );
      }
      await tester.tap(_button);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('note-assistant-save-first')),
        findsOneWidget,
      );
      for (final tile in tester.widgetList<NoteAiToolCard>(
        find.descendant(of: _menu, matching: find.byType(NoteAiToolCard)),
      )) {
        expect(tile.onTap, isNull);
      }
      expect(find.byType(NoteSummaryPage), findsNothing);
      if (!newNote) {
        expect(
          app.notes.getNoteByUuid('selected-note')!.content,
          'A quiet walk by the river.',
        );
      }
      await _unmount(tester, app);
    });
  }

  testWidgets(
    'secondary devices retain read access and hide scan and background generation',
    (tester) async {
      final app = await _mount(tester, secondary: true);
      await tester.tap(_button);
      await tester.pumpAndSettle();
      await tester.drag(_menu, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('note-assistant-scan')), findsNothing);
      expect(
        find.byKey(const ValueKey('note-assistant-background')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('note-assistant-image')), findsNothing);
      await _open(tester, 'summary');
      expect(find.byType(NoteSummaryPage), findsOneWidget);
      await _unmount(tester, app);
    },
  );

  testWidgets('the visual toolbox exposes labelled, generous touch targets', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final app = await _mount(tester);
    await tester.tap(_button);
    await tester.pumpAndSettle();
    final writing = find.byKey(const ValueKey('note-assistant-writing'));
    expect(
      tester.getSemantics(writing),
      matchesSemantics(
        label: 'Improve writing. Rewrite, expand, or edit',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    expect(tester.getSize(writing).height, greaterThanOrEqualTo(48));
    await tester.tap(find.byKey(const ValueKey('qvac-sheet-handle')));
    await tester.pumpAndSettle();
    await _capture(tester, 'note-menu-expanded');
    await _unmount(tester, app);
    semantics.dispose();
  });

  testWidgets('every note tool adapts to a small screen with large text', (
    tester,
  ) async {
    final app = await _mount(
      tester,
      dark: true,
      scale: 2,
      size: const Size(320, 568),
    );
    await tester.tap(_button);
    await tester.pumpAndSettle();
    await _capture(tester, 'note-menu-large-dark');
    for (final tool in [
      'summary',
      'writing',
      'metadata',
      'scan',
      'background',
      'presentation',
    ]) {
      await _open(tester, tool);
      expect(find.byType(BackButton), findsOneWidget);
      await _capture(tester, 'note-$tool-large-dark');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tool);
    }
    await _unmount(tester, app);
  });

  testWidgets(
    'large text and native back keep navigation within the note sheet',
    (tester) async {
      final app = await _mount(
        tester,
        dark: true,
        scale: 2,
        size: const Size(320, 568),
      );
      await tester.tap(_button);
      await tester.pumpAndSettle();
      await _open(tester, 'presentation');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_menu, findsOneWidget);
      expect(find.byType(QvacAssistantSheet), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(QvacAssistantSheet), findsNothing);
      expect(find.byType(EditNotePage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _unmount(tester, app);
    },
  );
}
