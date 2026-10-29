import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/images/note_scan.dart';
import 'package:journal/modules/notes/images/note_scan_page.dart';
import 'package:journal/modules/notes/images/note_scan_parts.dart';
import 'package:journal/modules/notes/images/note_scan_stage.dart';
import 'package:journal/modules/notes/views/widgets/note_ai_loading.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/summary/summary_store.dart';
import 'package:journal/modules/root/controllers/journal_account_reset_data.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:sync_wise/sync_wise.dart';

import 'note_image_test.dart' show ImageTransport, png;
import 'note_summary_test.dart' as summary;
import 'support/sync_fixture.dart';

String scanStatus = 'ready';

class ScanConnection extends summary.TestConnection {
  @override
  CompanionState build() => CompanionState(
    phase: CompanionPhase.connected,
    computers: [summary.computer],
    selectedId: summary.computer.id,
    status: {
      'recovery': 1,
      'capabilities': [
        {
          'id': 'vision',
          'status': scanStatus,
          'visionContract': 1,
          'scanContract': 1,
          'operations': [noteScanOperation],
        },
      ],
    },
  );
}

ProviderContainer scanContainer(
  SyncFixture app,
  SummaryStore store,
  ImageTransport wire,
  NoteScanStore scans, {
  SyncDeviceRole role = SyncDeviceRole.primary,
  Future<String?> Function(ImageSource)? picker,
}) => ProviderContainer(
  overrides: [
    notesRepositoryProvider.overrideWithValue(app.notes),
    summaryStoreProvider.overrideWithValue(store),
    companionTransportProvider.overrideWithValue(wire),
    companionControllerProvider.overrideWith(ScanConnection.new),
    accountResetProvider.overrideWith(summary.TestReset.new),
    syncDeviceRoleProvider.overrideWithValue(role),
    noteScanStoreProvider.overrideWithValue(scans),
    if (picker != null) noteScanPickerProvider.overrideWithValue(picker),
  ],
);

String scan(
  String text, {
  bool readable = true,
  List<(String, double)>? check,
}) => jsonEncode({
  'text': text,
  'readable': readable,
  'check': check == null
      ? null
      : [
          for (final (t, c) in check) {'text': t, 'confidence': c},
        ],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late NoteScanStore scans;
  setUp(() async {
    scanStatus = 'ready';
    dir = await Directory.systemTemp.createTemp('journal-i04-');
    scans = NoteScanStore(support: () async => dir);
  });
  tearDown(() => dir.delete(recursive: true));

  test('results keep the transcription verbatim and flag disagreements on numbers and names only', () {
    final result = NoteScanResult.parse(
      scan(
        'Call Mum about Sunday lunch\nDentist Tues 3:15pm\nIdeas for Priya\'s birthday [?]',
        check: [
          ('Cal Mum about Sunday', 0.89),
          ('Dentis} Tues 315pm', 0.56),
          ('Ideas for priyas birtday?', 0.73),
        ],
      ),
    );
    expect(result.text, contains('3:15pm'), reason: 'never corrected');
    expect(result.disagreements, ['3:15pm', "Priya's"]);
    expect(result.unreadableMarks, 1);
    final unchecked = NoteScanResult.parse(scan('Room B12'));
    expect(unchecked.check, isNull);
    expect(unchecked.disagreements, isEmpty);
    expect(NoteScanResult.parse(scan(' [?] ', readable: false)).empty, true);
    for (final bad in [
      '{}',
      '{"text":"x","readable":"yes","check":null}',
      '{"text":"a\\u0000","readable":true,"check":null}',
    ]) {
      expect(
        () => NoteScanResult.parse(bad),
        throwsFormatException,
        reason: bad,
      );
    }
  });

  test('scan copies are app-owned: the source is untouched, rotation swaps sides, sweep keeps referenced scans', () async {
    final source = File('${dir.path}/picked.png')
      ..writeAsBytesSync(await png(300, 100, Colors.white));
    final before = source.readAsBytesSync();
    final copy = await scans.import(source.path);
    expect(await scans.owns(copy), true);
    expect(await scans.owns(source.path), false);
    final rotated = await scans.rotate(copy);
    expect(File(copy).existsSync(), false);
    final descriptor = await ui.ImageDescriptor.encoded(
      await ui.ImmutableBuffer.fromUint8List(File(rotated).readAsBytesSync()),
    );
    expect([descriptor.width, descriptor.height], [100, 300]);
    expect(source.readAsBytesSync(), before);
    await scans.writeOriginal(rotated, 'n', 'Original text');
    expect(await scans.readOriginal(rotated), 'Original text');
    await expectLater(
      scans.writeOriginal(source.path, 'n', 'x'),
      throwsStateError,
    );
    final orphan = await scans.import(source.path);
    File(orphan)
        .setLastModifiedSync(DateTime.now().subtract(const Duration(days: 2)));
    final fresh = await scans.import(source.path);
    await scans.sweep({rotated});
    expect(File(rotated).existsSync(), true);
    expect(File('$rotated.json').existsSync(), true);
    expect(File(orphan).existsSync(), false);
    expect(
      File(fresh).existsSync(),
      true,
      reason: 'a page picked today may still be read',
    );
    await scans.delete(source.path);
    expect(
      source.existsSync(),
      true,
      reason: 'never deletes files it does not own',
    );
  });

  test('a scan sends only the page; inserting attaches it, keeps the original and is recoverable', () async {
    final drive = MemoryDrive();
    final app = await SyncFixture.create(drive, 'phone');
    app.notes.saveNote(
      uuid: 'chosen',
      title: 'Private',
      content: 'Existing body.',
    );
    final page = await scans.import(
      (File(
        '${dir.path}/p.png',
      )..writeAsBytesSync(await png(200, 260, Colors.white))).path,
    );
    final store = summary.MemorySummaries();
    final wire = ImageTransport(store)
      ..output = scan(
        'Buy: oats, lemons\nDentist Tues 3:15pm',
        check: [('Buy: oats, lemons', 0.7), ('Dentist Tues 315pm', 0.5)],
      );
    final container = scanContainer(app, store, wire, scans);
    addTearDown(container.dispose);
    container.read(noteSummaryProvider);
    await summary.settle();
    final controller = container.read(noteSummaryProvider.notifier);
    await controller.startNoteScan('chosen', path: page);
    expect(wire.routes, contains('POST /v1/image-jobs'));
    expect(wire.submitted.single['prompt'], noteScanPrompt);
    expect(wire.submitted.single.toString(), isNot(contains('Existing body')));
    expect(controller.noteScanResult()!.disagreements, ['3:15pm']);
    expect(
      app.notes.getNoteByUuid('chosen')!.attachments,
      isEmpty,
      reason: 'nothing changes before insertion',
    );
    expect(
      await controller.acceptNoteScan(
        'Buy: oats, lemons\nDentist Tues 3:15 pm',
      ),
      true,
    );
    final saved = app.notes.getNoteByUuid('chosen')!;
    expect(
      saved.content,
      'Existing body.\n\nBuy: oats, lemons\nDentist Tues 3:15 pm',
    );
    expect(saved.attachments.single['path'], page);
    expect(saved.status, SyncStatus.pendingUpload);
    expect(
      await scans.readOriginal(page),
      'Buy: oats, lemons\nDentist Tues 3:15pm',
    );
    final row = app.notes.transformationHistory('chosen').single;
    expect(row.operation, noteScanOperation);
    app.notes.restoreTransformation(row.id);
    expect(app.notes.getNoteByUuid('chosen')!.content, 'Existing body.');
    await app.sync();
    expect(drive.documents['note/chosen']!.payload['attachments'], [
      {'path': page, 'type': 'image/png'},
    ], reason: 'sync copies the path only');
  });

  test('stale notes, changed pages, foreign files, read-only devices and unready models are refused', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    app.notes.saveNote(uuid: 'chosen', title: 'T', content: 'Body.');
    final picked = File('${dir.path}/p.png')
      ..writeAsBytesSync(await png(64, 64, Colors.white));
    final page = await scans.import(picked.path);
    final store = summary.MemorySummaries();
    final wire = ImageTransport(store)
      ..output = scan('Hello')
      ..phase = 'running';
    final container = scanContainer(app, store, wire, scans);
    addTearDown(container.dispose);
    container.read(noteSummaryProvider);
    await summary.settle();
    final controller = container.read(noteSummaryProvider.notifier);
    await controller.startNoteScan('chosen', path: page);
    final note = app.notes.getNoteByUuid('chosen')!;
    app.notes.saveNote(
      uuid: 'chosen',
      expectedVersionVectorJson: note.versionVectorJson,
      title: 'T',
      content: 'Edited.',
    );
    wire.phase = 'completed';
    await controller.retry();
    expect(container.read(noteSummaryProvider).stale, true);
    expect(await controller.acceptNoteScan('Hello'), false);
    expect(app.notes.getNoteByUuid('chosen')!.content, 'Edited.');
    await controller.clear();

    wire
      ..job = null
      ..offline = true;
    await controller.startNoteScan('chosen', path: page);
    File(page).writeAsBytesSync(await png(64, 64, Colors.black));
    wire.offline = false;
    final posts = wire.posts;
    await controller.retry();
    expect(wire.posts, posts);
    expect(
      container.read(noteSummaryProvider).message,
      contains('page changed'),
    );
    await controller.clear();

    await controller.startNoteScan('chosen', path: picked.path);
    expect(container.read(noteSummaryProvider).message, contains('again'));
    await controller.clear();
    scanStatus = 'untested';
    container.invalidate(companionControllerProvider);
    await controller.startNoteScan('chosen', path: page);
    expect(container.read(noteSummaryProvider).message, contains('self-test'));
    await controller.clear();
    expect(wire.posts, posts);

    app.storage.setPrimary(
      const PrimaryDevice(
        deviceId: 'other',
        deviceName: 'Desktop',
        fileId: 'primary',
      ),
    );
    scanStatus = 'ready';
    container.invalidate(companionControllerProvider);
    await controller.startNoteScan('chosen', path: page);
    expect(container.read(noteSummaryProvider).message, contains('read-only'));
    expect(wire.posts, posts);
  });

  test(
    'account reset removes scan copies and original transcriptions',
    () async {
      final app = await SyncFixture.create(MemoryDrive(), 'phone');
      final page = await scans.import(
        (File(
          '${dir.path}/p.png',
        )..writeAsBytesSync(await png(8, 8, Colors.white))).path,
      );
      await scans.writeOriginal(page, 'n', 'text');
      await JournalAccountResetData(
        db: app.db,
        supportDirectory: () async => dir,
        clearCachedImages: () async {},
      ).clear();
      expect(Directory('${dir.path}/note_scans').existsSync(), false);
    },
  );

  testWidgets(
    'pick → read → unreadable explains; flagged words and [?] marks are shown before insertion',
    (tester) async {
      tester.view
        ..physicalSize = const Size(800, 3000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final app = await tester.runAsync(
        () => SyncFixture.create(MemoryDrive(), 'phone'),
      );
      app!.notes.saveNote(uuid: 'chosen', title: 'T', content: 'Body.');
      final picked = await tester.runAsync(
        () async => (File(
          '${dir.path}/p.png',
        )..writeAsBytesSync(await png(64, 64, Colors.white))).path,
      );
      final store = summary.MemorySummaries();
      final wire = ImageTransport(store)..output = scan('', readable: false);
      final container = scanContainer(
        app,
        store,
        wire,
        scans,
        picker: (_) async => picked,
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: NoteScanPage(noteId: 'chosen')),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('note-scan-start')),
        findsNothing,
        reason: 'Read text appears once there is a page',
      );
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('note-scan-gallery')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('note-scan-start')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('note-scan-unreadable')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('note-scan-insert')), findsNothing);
      wire.output = scan(
        'Room B12 at 14:30 [?]',
        check: [('Room B12 at 14.30', 0.6)],
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Try again with this page'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('note-scan-start')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(find.widgetWithText(Chip, '14:30'), findsOneWidget);
      expect(find.byKey(const ValueKey('note-scan-marks')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('note-scan-text')), ' ');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('note-scan-insert')),
            )
            .onPressed,
        isNull,
      );
      expect(app.notes.getNoteByUuid('chosen')!.content, 'Body.');
      await tester.pumpWidget(const SizedBox());
    },
  );

  /// Opens the scan page and starts reading a page the computer holds in
  /// 'running' until the test says otherwise.
  Future<ProviderContainer> startReading(
    WidgetTester tester, {
    required bool reduced,
    bool accessibleNavigation = false,
  }) async {
    tester.view
      ..physicalSize = const Size(800, 3000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = await tester.runAsync(
      () => SyncFixture.create(MemoryDrive(), 'phone'),
    );
    app!.notes.saveNote(uuid: 'chosen', title: 'T', content: 'Body.');
    final picked = await tester.runAsync(
      () async => (File(
        '${dir.path}/p.png',
      )..writeAsBytesSync(await png(64, 64, Colors.white))).path,
    );
    final store = summary.MemorySummaries();
    final wire = ImageTransport(store)
      ..output = scan('Hello')
      ..phase = 'running';
    final container = scanContainer(
      app,
      store,
      wire,
      scans,
      picker: (_) async => picked,
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reduced,
              accessibleNavigation: accessibleNavigation,
            ),
            child: child!,
          ),
          home: const NoteScanPage(noteId: 'chosen'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NoteScanEmpty), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('note-scan-gallery')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('note-scan-start')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    return container;
  }

  NoteScanPainter painter(WidgetTester tester) =>
      tester
              .widget<CustomPaint>(
                find.byKey(const ValueKey('note-scan-analyzing')),
              )
              .painter!
          as NoteScanPainter;

  void expectPageBeingRead(WidgetTester tester) {
    final stage = find.byKey(const ValueKey('note-scan-stage'));
    expect(
      find.descendant(of: stage, matching: find.byType(Image)),
      findsOneWidget,
      reason: 'the page itself stays on screen while it is read',
    );
    expect(find.byType(NoteScanReading), findsOneWidget);
    expect(find.byType(NoteAiLoading), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Reading'), findsOneWidget);
  }

  testWidgets(
    'a page being read stays on screen under a moving scan line and can be stopped',
    (tester) async {
      final container = await startReading(tester, reduced: false);
      expectPageBeingRead(tester);
      expect(painter(tester).moving, isTrue);
      final before = painter(tester).sweep.value;
      await tester.pump(const Duration(milliseconds: 400));
      expect(painter(tester).sweep.value, isNot(before));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Stop'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.byType(NoteScanReading), findsNothing);
      expect(container.read(noteSummaryProvider).phase, 'cancelled');
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'an accessibility service reading the screen does not stop the scan line',
    (tester) async {
      // Android reports accessible navigation for any accessibility service,
      // not only screen readers; only reduced motion keeps the page still.
      await startReading(tester, reduced: false, accessibleNavigation: true);
      expectPageBeingRead(tester);
      expect(painter(tester).moving, isTrue);
      final before = painter(tester).sweep.value;
      await tester.pump(const Duration(milliseconds: 400));
      expect(painter(tester).sweep.value, isNot(before));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'reduced motion shows the page being read still, without a line',
    (tester) async {
      await startReading(tester, reduced: true);
      expectPageBeingRead(tester);
      expect(painter(tester).moving, isFalse);
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpAndSettle();
      expectPageBeingRead(tester);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
