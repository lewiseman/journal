import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:journal/modules/notes/views/widgets/note_ai_widgets.dart';
import 'package:journal/modules/notes/views/widgets/note_ai_loading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/assistant/qvac_assistant.dart';
import 'package:journal/modules/assistant/qvac_assistant_scope.dart';
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/draft/note_draft_ai.dart';
import 'package:journal/modules/notes/draft/note_draft_pages.dart';
import 'package:journal/modules/notes/images/note_background_gen.dart';
import 'package:journal/modules/notes/images/note_scan.dart';
import 'package:journal/modules/notes/metadata/note_help_contract.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/views/pages/edit_note_page.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';
import 'package:sync_wise/sync_wise.dart';

import 'note_summary_test.dart' show TestReset, computer;
import 'support/sync_fixture.dart';

class _Connection extends CompanionController {
  _Connection([this.phase = CompanionPhase.connected]);
  final CompanionPhase phase;
  @override
  CompanionState build() => CompanionState(
    phase: phase,
    computers: [computer],
    selectedId: computer.id,
    status: {
      'recovery': 1,
      'capabilities': [
        {
          'id': 'text',
          'status': 'ready',
          'noteHelpContract': 1,
          'operations': [noteTemplateOperation],
        },
        {
          'id': 'vision',
          'status': 'ready',
          'scanContract': 1,
          'operations': [noteScanOperation],
        },
        {
          'id': 'image',
          'status': 'ready',
          'backgroundContract': 1,
          'operations': [noteBackgroundOperation],
        },
      ],
    },
  );
}

class _Summary extends NoteSummaryController {
  @override
  NoteSummaryState build() => const NoteSummaryState();
}

/// The companion's job routes, with each job finishing on [finish].
class _Desktop implements CompanionTransport {
  final routes = <String>[];
  final jobs = <String, Map<String, dynamic>>{};
  String? output;
  List<int> image = const [];
  bool finishOnSubmit = false;

  void finish(String text) {
    output = text;
    for (final job in jobs.values) {
      job['state'] = 'completed';
      job['text'] = text;
    }
  }

  Future<void> finishImage(List<int> png) async {
    image = png;
    finish(
      jsonEncode({
        'width': 64,
        'height': 96,
        'seed': 7,
        'bytes': png.length,
        'sha256': await hexHash(png),
      }),
    );
  }

  @override
  Future<Map<String, dynamic>> request(
    Uri endpoint,
    String pin,
    String method,
    String route, {
    Map<String, dynamic>? body,
    Map<String, String> headers = const {},
  }) async {
    if (route == '/v1/challenge') return {'nonce': 'a' * 43};
    routes.add('$method $route');
    if (method == 'POST' &&
        (route == '/v1/jobs' || route == '/v1/image-jobs')) {
      final job = jobs[body!['id'] as String] = {
        'id': body['id'],
        'device': computer.deviceId,
        'operation': body['operation'],
        'model': 'model',
        'state': finishOnSubmit ? 'completed' : 'running',
        if (finishOnSubmit) 'text': output,
      };
      return {...job};
    }
    final result = RegExp(r'^/v1/image-jobs/([^/]+)/result$').firstMatch(route);
    if (result != null) {
      return {'id': result[1], 'image': base64Encode(image)};
    }
    final id = route.split('/')[3];
    if (route.endsWith('/cancel')) jobs[id]?['state'] = 'cancelled';
    return {...?jobs[id]};
  }

  @override
  void close() {}
}

/// A minimal PNG header for [width] × [height].
Uint8List _png(int width, int height) {
  final bytes = Uint8List(40)
    ..setAll(0, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  ByteData.sublistView(bytes)
    ..setUint32(16, width)
    ..setUint32(20, height);
  return bytes;
}

const _template =
    '{"title":"Team meeting","body":"## Agenda\\n- \\n\\n## Actions\\n- [ ] "}';

void main() {
  late Directory support;
  late _Desktop desktop;
  setUp(() {
    support = Directory.systemTemp.createTempSync('journal-draft-ai-');
    desktop = _Desktop();
  });
  tearDown(() => support.deleteSync(recursive: true));

  ProviderContainer container({
    CompanionPhase phase = CompanionPhase.connected,
  }) => ProviderContainer.test(
    overrides: [
      companionTransportProvider.overrideWithValue(desktop),
      companionControllerProvider.overrideWith(() => _Connection(phase)),
      noteBackgroundStoreProvider.overrideWithValue(
        NoteBackgroundStore(support: () async => support),
      ),
      noteScanStoreProvider.overrideWithValue(
        NoteScanStore(support: () async => support),
      ),
    ],
  );

  testWidgets('a template is polled to completion, checked and acknowledged', (
    tester,
  ) async {
    final scope = container();
    final keep = scope.listen(noteDraftAiProvider, (_, _) {});
    final draft = scope.read(noteDraftAiProvider.notifier);
    await draft.template('Weekly team meeting');
    expect(scope.read(noteDraftAiProvider).phase, 'running');
    expect(desktop.routes, ['POST /v1/jobs']);
    desktop.finish(_template);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    final state = scope.read(noteDraftAiProvider);
    expect(state.phase, 'completed');
    expect(state.template!.title, 'Team meeting');
    expect(state.template!.body, startsWith('## Agenda'));
    expect(desktop.routes.last, endsWith('/ack'));
    keep.close();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('an invalid result fails without being acknowledged', (
    tester,
  ) async {
    final scope = container();
    final keep = scope.listen(noteDraftAiProvider, (_, _) {});
    desktop
      ..finishOnSubmit = true
      ..output = '{"title":"x","body":"a\\tb"}';
    await scope.read(noteDraftAiProvider.notifier).template('Anything');
    final state = scope.read(noteDraftAiProvider);
    expect(state.phase, 'failed');
    expect(state.template, isNull);
    expect(desktop.routes.where((r) => r.endsWith('/ack')), isEmpty);
    keep.close();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('offline, nothing is sent and the tool says why', (tester) async {
    final scope = container(phase: CompanionPhase.unavailable);
    final keep = scope.listen(noteDraftAiProvider, (_, _) {});
    await scope.read(noteDraftAiProvider.notifier).template('Anything');
    expect(scope.read(noteDraftAiProvider).phase, 'failed');
    expect(scope.read(noteDraftAiProvider).message, contains('Connect'));
    expect(desktop.routes, isEmpty);
    keep.close();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('closing while a task runs cancels it and keeps nothing', (
    tester,
  ) async {
    final scope = container();
    final keep = scope.listen(noteDraftAiProvider, (_, _) {});
    await scope.read(noteDraftAiProvider.notifier).template('Trip plan');
    keep.close();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    expect(desktop.routes.last, endsWith('/cancel'));
    await tester.pump(const Duration(seconds: 10));
    expect(desktop.routes.where((r) => r.startsWith('GET')), isEmpty);
  });

  testWidgets('a background is verified into a preview, removed on close', (
    tester,
  ) async {
    final scope = container();
    final keep = scope.listen(noteDraftAiProvider, (_, _) {});
    await tester.runAsync(() async {
      await desktop.finishImage(_png(64, 96));
      desktop.finishOnSubmit = true;
      await scope
          .read(noteDraftAiProvider.notifier)
          .background('Sea glass', 'light');
    });
    final preview = scope.read(noteDraftAiProvider).preview!;
    expect(preview.existsSync(), isTrue);
    final adopted = await tester.runAsync(
      () => scope
          .read(noteBackgroundStoreProvider)
          .adopt(preview.uri.pathSegments.last.replaceAll('.png', '')),
    );
    expect(File('${adopted!}.previous.json').existsSync(), isFalse);
    keep.close();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    expect(preview.existsSync(), isFalse);
    expect(File(adopted).existsSync(), isTrue);
  });

  group('new note editor', () {
    final button = find.byKey(const ValueKey('qvac-assistant-button'));

    Future<SyncFixture> mount(
      WidgetTester tester, {
      CompanionPhase phase = CompanionPhase.connected,
    }) async {
      final app = (await tester.runAsync(
        () => SyncFixture.create(MemoryDrive(), 'phone'),
      ))!;
      final scope = ProviderContainer.test(
        overrides: [
          objectBoxProvider.overrideWithValue(app.db),
          syncStateStoreProvider.overrideWithValue(app.storage),
          notesRepositoryProvider.overrideWithValue(app.notes),
          companionTransportProvider.overrideWithValue(desktop),
          companionControllerProvider.overrideWith(() => _Connection(phase)),
          noteSummaryProvider.overrideWith(_Summary.new),
          accountResetProvider.overrideWith(TestReset.new),
          syncDeviceRoleProvider.overrideWithValue(SyncDeviceRole.primary),
          noteBackgroundStoreProvider.overrideWithValue(
            NoteBackgroundStore(support: () async => support),
          ),
          noteScanStoreProvider.overrideWithValue(
            NoteScanStore(support: () async => support),
          ),
        ],
      );
      final assistant = scope.read(qvacAssistantProvider);
      final navigator = GlobalKey<NavigatorState>();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: scope,
          child: MaterialApp(
            navigatorKey: navigator,
            navigatorObservers: [QvacAssistantObserver(assistant)],
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: QvacAssistantHost(
                controller: assistant,
                navigatorKey: navigator,
                child: child!,
              ),
            ),
            home: const EditNotePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return app;
    }

    NoteAiToolCard tile(WidgetTester tester, String name) => tester
        .widget<NoteAiToolCard>(find.byKey(ValueKey('note-assistant-$name')));

    testWidgets('offers only the draft tools, resting while offline', (
      tester,
    ) async {
      final app = await mount(tester, phase: CompanionPhase.unavailable);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('QVAC'), findsNothing);
      expect(find.byTooltip('Close'), findsNothing);
      expect(
        find.byKey(const ValueKey('note-assistant-save-first')),
        findsNothing,
      );
      final tiles = tester.widgetList<NoteAiToolCard>(
        find.descendant(
          of: find.byKey(const ValueKey('note-assistant-actions')),
          matching: find.byType(NoteAiToolCard),
        ),
      );
      expect(tiles.map((t) => (t.key! as ValueKey).value), [
        'note-assistant-template',
        'note-assistant-scan',
        'note-assistant-background',
      ]);
      expect(tiles.every((t) => t.onTap == null), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      app.container.dispose();
    });

    testWidgets(
      'a running draft uses the shared loading view and can be stopped',
      (tester) async {
        final app = await mount(tester);
        await tester.tap(button);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('note-assistant-template')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('note-draft-template-topic')),
          'Meeting notes',
        );
        await tester.pump();
        final start = find.byKey(const ValueKey('note-draft-template-start'));
        await tester.scrollUntilVisible(
          start.hitTestable(),
          100,
          scrollable: find
              .descendant(
                of: find.byType(NoteDraftTemplatePage),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.runAsync(() async {
          await tester.tap(start);
          await Future<void>.delayed(const Duration(milliseconds: 60));
        });
        await tester.pumpAndSettle();
        expect(find.byType(NoteAiLoading), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('note-draft-cancel')));
        await tester.pumpAndSettle();
        expect(find.byType(NoteAiLoading), findsNothing);
        expect(
          find.byKey(const ValueKey('note-draft-template-topic')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        app.container.dispose();
      },
    );

    testWidgets('a template fills the draft and is dropped when discarded', (
      tester,
    ) async {
      final app = await mount(tester);
      desktop
        ..finishOnSubmit = true
        ..output = _template;
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(tile(tester, 'template').onTap, isNotNull);
      await tester.tap(find.byKey(const ValueKey('note-assistant-template')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DraggableScrollableSheet>(
              find.byType(DraggableScrollableSheet),
            )
            .controller!
            .size,
        closeTo(1, .01),
      );
      await tester.enterText(
        find.byKey(const ValueKey('note-draft-template-topic')),
        'Weekly team meeting',
      );
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('note-draft-template-start')).hitTestable(),
        120,
        scrollable: find
            .descendant(
              of: find.byType(NoteDraftTemplatePage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(
          find.byKey(const ValueKey('note-draft-template-start')),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('note-draft-template-preview')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('note-draft-template-use')),
      );
      await tester.tap(find.byKey(const ValueKey('note-draft-template-use')));
      await tester.pumpAndSettle();
      expect(find.byType(QvacAssistantSheet), findsNothing);
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((f) => f.controller?.text)
          .toList();
      expect(fields, contains('Team meeting'));
      expect(fields.any((t) => t?.startsWith('## Agenda') ?? false), isTrue);
      expect(
        (await tester.runAsync(() => app.notes.watchActiveNotes().first))!,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(
        (await tester.runAsync(() => app.notes.watchActiveNotes().first))!,
        isEmpty,
      );
      app.container.dispose();
    });

    testWidgets(
      'a generated background is kept when saved and deleted when discarded',
      (tester) async {
        for (final save in [false, true]) {
          final app = await mount(tester);
          await tester.runAsync(() => desktop.finishImage(_png(64, 96)));
          desktop.finishOnSubmit = true;
          await tester.tap(button);
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find
                .byKey(const ValueKey('note-assistant-background'))
                .hitTestable(),
            100,
            scrollable: find.descendant(
              of: find.byKey(const ValueKey('note-assistant-actions')),
              matching: find.byType(Scrollable),
            ),
          );
          await tester.tap(
            find.byKey(const ValueKey('note-assistant-background')),
          );
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<DraggableScrollableSheet>(
                  find.byType(DraggableScrollableSheet),
                )
                .controller!
                .size,
            closeTo(1, .01),
          );
          await tester.tap(find.text('Ocean'));
          await tester.pump();
          expect(
            tester
                .widget<TextField>(
                  find.byKey(const ValueKey('note-draft-background-prompt')),
                )
                .controller!
                .text,
            contains('ocean waves'),
          );
          await tester.pump();
          await tester.scrollUntilVisible(
            find
                .byKey(const ValueKey('note-draft-background-start'))
                .hitTestable(),
            120,
            scrollable: find
                .descendant(
                  of: find.byType(NoteDraftBackgroundPage),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            await tester.tap(
              find.byKey(const ValueKey('note-draft-background-start')),
            );
            await Future<void>.delayed(const Duration(milliseconds: 600));
          });
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('note-draft-background-use')),
            120,
            scrollable: find
                .descendant(
                  of: find.byType(NoteDraftBackgroundPage),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            await tester.tap(
              find.byKey(const ValueKey('note-draft-background-use')),
            );
            await Future<void>.delayed(const Duration(milliseconds: 400));
          });
          await tester.pumpAndSettle();
          final generated = Directory(
            '${support.path}/note_backgrounds/generated',
          ).listSync().whereType<File>().single;
          if (save) {
            await tester.enterText(
              find.byKey(const ValueKey('note-content-editor')),
              'With a background.',
            );
            await tester.tap(find.text('Save'));
            await tester.pumpAndSettle();
            final notes = await tester.runAsync(
              () => app.notes.watchActiveNotes().first,
            );
            expect(notes!.single.background['image'], generated.path);
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 200)),
          );
          expect(generated.existsSync(), save);
          if (save) generated.deleteSync();
          app.container.dispose();
        }
      },
    );
  });
}
