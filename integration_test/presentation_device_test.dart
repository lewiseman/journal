// Opt-in synthetic H01 device demonstration. Run online, stop the isolated
// companion, then rerun with H01_OFFLINE=true to prove process-restart reading.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:journal/modules/diary/controllers/diary_providers.dart';
import 'package:journal/modules/diary/controllers/diary_repository.dart';
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/controllers/notes_repository.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/summary/summary_store.dart';
import 'package:journal/modules/notes/views/pages/edit_note_page.dart';
import 'package:journal/modules/presentation/presentation_body.dart';
import 'package:journal/modules/presentation/presentation_contract.dart';
import 'package:journal/modules/presentation/presentation_entity.dart';
import 'package:journal/modules/presentation/presentation_page.dart';
import 'package:journal/modules/presentation/presentation_repository.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';
import 'package:journal/modules/settings/companion/companion_store.dart';
import 'package:journal/objectbox/objectbox.dart';
import 'package:journal/objectbox/objectbox.g.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sync_wise/sync_wise.dart';

class _Device extends Fake implements DeviceIdentityService {
  @override
  String get deviceId => 'h01-synthetic-phone';
  @override
  String get deviceName => 'H01 synthetic phone';
}

class _Reset extends AccountResetController {
  _Reset() : super((_) => throw UnimplementedError());
  @override
  AccountResetState build() {
    ready = Future.value();
    return const AccountResetState();
  }
}

class _Wire implements CompanionTransport {
  final inner = PinnedCompanionTransport();
  bool drop = true;
  int posts = 0;
  @override
  Future<Map<String, dynamic>> request(
    Uri endpoint,
    String pin,
    String method,
    String route, {
    Map<String, dynamic>? body,
    Map<String, String> headers = const {},
  }) async {
    final result = await inner.request(
      endpoint,
      pin,
      method,
      route,
      body: body,
      headers: headers,
    );
    if (method == 'POST' && route == '/v1/jobs') {
      posts++;
      if (drop) {
        drop = false;
        throw const CompanionFailure(
          'UNAVAILABLE',
          'Test-only discarded real acceptance',
        );
      }
    }
    return result;
  }

  @override
  void close() => inner.close();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const fixture = String.fromEnvironment('RECOVERY_TRUSTED_COMPUTER');
  const offline = bool.fromEnvironment('H01_OFFLINE');
  testWidgets('H01 native adversarial rendering and failure fallback', (
    tester,
  ) async {
    const html =
        '<article><section data-source="b0" class="s0"></section></article>';
    const css = '.s0 {font-size:1.125em;line-height:1.6;}';
    final attacks = [
      {'html': '<script>evil()</script>$html', 'css': css},
      {
        'html': html.replaceFirst(
          '</section>',
          '<img src="https://example.invalid/leak"></section>',
        ),
        'css': css,
      },
      {
        'html': html.replaceFirst(
          '</section>',
          '<iframe src="file:///private"></iframe></section>',
        ),
        'css': css,
      },
      {'html': html.replaceFirst('b0', 'b1'), 'css': css},
      {'html': html, 'css': '.s0 {display:none}'},
      {'html': html, 'css': '.s0 {position:fixed;opacity:0}'},
      {'html': html, 'css': '@import "https://example.invalid";'},
      {'html': html, 'css': r'.\73 0 {font-size:1em}'},
    ];
    for (final attack in attacks) {
      await expectLater(
        compilePresentationBounded(jsonEncode(attack), 1),
        throwsA(isA<FormatException>()),
      );
    }
    const source =
        '[word](https://example.invalid) ![alt](file:///private) <script>literal</script>';
    final blocks = PresentationBlocks(source);
    final document = await compilePresentationBounded(
      jsonEncode({'html': html, 'css': css}),
      1,
    );
    final originalOverrides = HttpOverrides.current;
    final guard = _NoRendererNetwork();
    HttpOverrides.global = guard;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SafePresentationBody(
              blocks: blocks,
              document: document,
              original: source,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(guard.clients, 0);
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), null);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SafePresentationBody(
              blocks: blocks,
              document: document,
              original: source,
              renderBlock: (_) =>
                  throw StateError('Test-only renderer failure'),
            ),
          ),
        ),
      );
      expect(find.text(source), findsOneWidget);
      expect(guard.clients, 0);
    } finally {
      HttpOverrides.global = originalOverrides;
    }
    debugPrint(
      'H01_SECURITY_EVIDENCE ${jsonEncode({'platform': Platform.operatingSystem, 'injectedAdversarialCasesRejected': attacks.length, 'rendererCreatedNetworkClients': guard.clients, 'injectedRendererFailureRecoveredSource': true})}',
    );
  });
  testWidgets('H01 real generation or offline restart reading', (tester) async {
    final support = await getApplicationSupportDirectory();
    final trust = ProtectedComputerStore(
      key: 'journal.companion.h01-demo.trust',
    );
    final protected = ProtectedSummaryStore(
      key: 'journal.companion.h01-demo.task',
    );
    final db = ObjectBox.fromStore(
      await openStore(directory: '${support.path}/h01-synthetic-objectbox'),
    );
    final sync = SyncStateStore(
      storage: MemorySyncKeyValueStore(),
      deviceId: 'h01-synthetic-phone',
    );
    final notes = NotesRepository(db: db, device: _Device(), sync: sync);
    final diary = DiaryRepository(db: db, device: _Device(), sync: sync);
    final store = ObjectBoxSummaryStore(db.store, protected: protected);
    final wire = _Wire();
    if (!offline) {
      expect(fixture, isNotEmpty);
      final trusted = TrustedComputer.fromJson(
        jsonDecode(fixture) as Map<String, dynamic>,
      );
      await trust.save(ComputerRecords([trusted], trusted.id));
      await store.clearAll();
      db.noteBox.removeAll();
      db.diaryBox.removeAll();
      db.store.box<PresentationEntity>().removeAll();
    }
    final container = ProviderContainer(
      overrides: [
        objectBoxProvider.overrideWithValue(db),
        syncStateStoreProvider.overrideWithValue(sync),
        notesRepositoryProvider.overrideWithValue(notes),
        diaryRepositoryProvider.overrideWithValue(diary),
        accountResetProvider.overrideWith(_Reset.new),
        syncDeviceRoleProvider.overrideWithValue(SyncDeviceRole.primary),
        companionStoreProvider.overrideWithValue(trust),
        summaryStoreProvider.overrideWithValue(store),
        companionTransportProvider.overrideWithValue(wire),
      ],
    );
    addTearDown(() {
      container.dispose();
      wire.close();
      db.close();
    });
    Future<void> show(Widget page) => tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(colorSchemeSeed: Colors.indigo),
          home: page,
        ),
      ),
    );
    Future<void> waitFor(bool Function() done) async {
      final deadline = DateTime.now().add(const Duration(seconds: 100));
      while (!done()) {
        if (DateTime.now().isAfter(deadline)) {
          fail(
            'H01 timeout: ${container.read(noteSummaryProvider).phase} ${container.read(noteSummaryProvider).message}',
          );
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> reveal(String key) async {
      final target = find.byKey(ValueKey(key));
      if (target.evaluate().isEmpty) {
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pump();
        await tester.scrollUntilVisible(
          target,
          150,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 30,
        );
      }
      await tester.ensureVisible(target);
      await tester.pump(const Duration(milliseconds: 300));
    }

    final repository = container.read(presentationRepositoryProvider);
    final report = <String, dynamic>{
      'platform': Platform.operatingSystem,
      'offlinePhase': offline,
      'syntheticSourceAndTrust': true,
      'physicalAndroid': Platform.isAndroid,
      'iOSSimulator': Platform.isIOS,
    };
    if (offline) {
      final records = db.store.box<PresentationEntity>().getAll();
      expect(records.length, 2);
      for (final record in records) {
        final saved = PresentationSnapshot.decode(record.snapshot);
        expect(repository.matches(saved), true);
        await show(PresentationPage(source: saved.ref));
        await tester.pump(const Duration(seconds: 2));
        expect(find.byType(SafePresentationBody), findsWidgets);
        expect(tester.takeException(), null);
      }
      report['persistedBothSourcesAfterAppRestart'] = true;
      report['renderedWhileCompanionStopped'] = true;
      // Recovery and reversion remain usable with no companion process.
      final source = PresentationSnapshot.decode(records.first.snapshot);
      repository.revert(source.ref);
      expect(repository.get(source.ref.key)!.enabled, false);
      expect(repository.source(source.ref)!.content, source.content);
      report['offlineRevertPreservedSource'] = true;
      await show(const SizedBox.shrink());
      await store.clearAll();
      await trust.save(const ComputerRecords([], null));
      db.noteBox.removeAll();
      db.diaryBox.removeAll();
      db.store.box<PresentationEntity>().removeAll();
      report['isolatedDataAndTrustCleaned'] = true;
    } else {
      final note = notes.saveNote(
        uuid: 'h01-note',
        title: 'Synthetic private title',
        content: '# Plans for Friday\n\nMeet Mira at noon.',
      );
      await show(EditNotePage(existingNote: note));
      container.read(companionControllerProvider);
      container.read(noteSummaryProvider);
      await waitFor(
        () =>
            container.read(companionControllerProvider).phase ==
                CompanionPhase.connected &&
            !container.read(noteSummaryProvider).busy,
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byTooltip('Writing help and recovery'));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Presentation'));
      await tester.pump(const Duration(seconds: 1));
      await tester.ensureVisible(
        find.byKey(const ValueKey('presentation-generate')),
      );
      await tester.tap(find.byKey(const ValueKey('presentation-generate')));
      await waitFor(() => container.read(noteSummaryProvider).phase == 'error');
      final controller = container.read(noteSummaryProvider.notifier);
      final taskId = container.read(noteSummaryProvider).handle!.id;
      await controller.retry();
      await waitFor(() => container.read(noteSummaryProvider).terminal);
      expect(container.read(noteSummaryProvider).phase, 'completed');
      expect(container.read(noteSummaryProvider).handle!.id, taskId);
      expect(wire.posts, 1);
      report['retrievedDiscardedRealAcceptanceWithoutResubmit'] = true;
      await tester.pump(const Duration(seconds: 1));
      await reveal('presentation-accept');
      await tester.tap(find.byKey(const ValueKey('presentation-accept')));
      await waitFor(() => container.read(noteSummaryProvider).handle == null);
      final noteRef = PresentationSourceRef.note(note.uuid);
      expect(repository.get(noteRef.key)!.enabled, true);
      expect(notes.getNoteByUuid(note.uuid)!.content, note.content);
      report['noteUiGeneratedPreviewedAccepted'] = true;
      report['noteDocument'] = jsonDecode(
        repository.get(noteRef.key)!.document,
      );
      // Exercise local reversion without changing text, then accept a fresh task.
      await tester.pump(const Duration(seconds: 1));
      await reveal('presentation-revert');
      await tester.tap(find.byKey(const ValueKey('presentation-revert')));
      expect(repository.get(noteRef.key)!.enabled, false);
      report['uiRevertPreservedSource'] = true;
      await controller.startPresentation(noteRef);
      await waitFor(() => container.read(noteSummaryProvider).terminal);
      expect(container.read(noteSummaryProvider).phase, 'completed');
      await controller.clear();
      expect(repository.get(noteRef.key)!.enabled, false);
      report['rejectionPreservedSource'] = true;
      await controller.startPresentation(noteRef);
      await waitFor(() => container.read(noteSummaryProvider).terminal);
      expect(await controller.acceptPresentation(), true);
      // A fresh proposal cannot apply after a source change.
      await controller.startPresentation(noteRef);
      notes.saveNote(
        uuid: note.uuid,
        title: note.title,
        content: 'Later manual words.',
      );
      await waitFor(() => container.read(noteSummaryProvider).terminal);
      expect(await controller.acceptPresentation(), false);
      await controller.clear();
      report['changedSourceRefused'] = true;
      notes.saveNote(uuid: note.uuid, title: note.title, content: note.content);
      await controller.startPresentation(noteRef);
      await waitFor(() => container.read(noteSummaryProvider).terminal);
      sync.setPrimary(
        const PrimaryDevice(
          deviceId: 'other',
          deviceName: 'Other',
          fileId: 'test-only',
        ),
      );
      expect(await controller.acceptPresentation(), false);
      report['changedRoleRefused'] = true;
      sync.setPrimary(
        const PrimaryDevice(
          deviceId: 'h01-synthetic-phone',
          deviceName: 'H01',
          fileId: 'test-only',
        ),
      );
      expect(await controller.acceptPresentation(), true);
      await tester.pump(const Duration(seconds: 1));
      report['realPinnedTlsAndQvac'] = true;
      report['readyForOfflineRestart'] = true;
      const captureSeconds = int.fromEnvironment('H01_CAPTURE_SECONDS');
      if (captureSeconds > 0) {
        await show(PresentationPage(source: noteRef));
        await tester.pump(const Duration(seconds: 1));
        await reveal('presentation-revert');
        debugPrint('H01_CAPTURE_READY');
        await Future<void>.delayed(Duration(seconds: captureSeconds));
      }
    }
    await File(
      '${support.path}/h01-device-${offline ? 'offline' : 'online'}.json',
    ).writeAsString(jsonEncode(report));
    debugPrint('H01_DEVICE_EVIDENCE ${jsonEncode(report)}');
    expect(tester.takeException(), null);
  });
}

class _NoRendererNetwork extends HttpOverrides {
  int clients = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clients++;
    throw StateError('Renderer must remain offline');
  }
}
