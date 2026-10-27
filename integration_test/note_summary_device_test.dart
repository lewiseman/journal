// Synthetic saved notes in an isolated ObjectBox directory. No user's notes are read.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/controllers/notes_repository.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/summary/summary_store.dart';
import 'package:journal/modules/notes/summary/summary_page.dart';
import 'package:journal/modules/notes/views/pages/edit_note_page.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';
import 'package:journal/objectbox/objectbox.dart';
import 'package:journal/objectbox/objectbox.g.dart';
import 'package:sync_wise/sync_wise.dart';

class _DemoDevice extends Fake implements DeviceIdentityService {
  @override
  String get deviceId => 'summary-demo-phone';
  @override
  String get deviceName => 'F01 phone';
}

class _DemoReset extends AccountResetController {
  _DemoReset() : super((_) => throw UnimplementedError());
  @override
  AccountResetState build() {
    ready = Future.value();
    return const AccountResetState();
  }
}

// Test-only fault after the REAL accepted HTTPS response. Retry uses production recovery.
class _LoseAcceptance implements CompanionTransport {
  final inner = PinnedCompanionTransport();
  bool lose = true;
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
      if (lose) {
        lose = false;
        throw const CompanionFailure(
          'UNAVAILABLE',
          'Test: accepted response was lost. Retry retrieves the same task.',
        );
      }
    }
    return result;
  }

  @override
  void close() => inner.close();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const raw = String.fromEnvironment('COMPANION_PAIRING_CODE');
  const restart = bool.fromEnvironment('SUMMARY_RESTART');
  const missing = bool.fromEnvironment('SUMMARY_MISSING_MODEL');
  testWidgets('physical phone previews a saved note summary from packaged QVAC', (
    tester,
  ) async {
    final directory = await getApplicationSupportDirectory();
    final db = ObjectBox.fromStore(
      await openStore(directory: '${directory.path}/f01-synthetic-objectbox'),
    );
    final sync = SyncStateStore(
      storage: MemorySyncKeyValueStore(),
      deviceId: 'summary-demo-phone',
    );
    final repo = NotesRepository(db: db, device: _DemoDevice(), sync: sync);
    final wire = _LoseAcceptance();
    final container = ProviderContainer(
      overrides: [
        objectBoxProvider.overrideWithValue(db),
        notesRepositoryProvider.overrideWithValue(repo),
        syncDeviceRoleProvider.overrideWithValue(SyncDeviceRole.secondary),
        accountResetProvider.overrideWith(_DemoReset.new),
        companionTransportProvider.overrideWithValue(wire),
      ],
    );
    addTearDown(() {
      container.dispose();
      wire.close();
      db.close();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: Text('Preparing F01 synthetic demo')),
        ),
      ),
    );
    Future<void> waitFor(bool Function() ready, {int seconds = 90}) async {
      final deadline = DateTime.now().add(Duration(seconds: seconds));
      String? verification;
      while (!ready()) {
        final current = container
            .read(companionControllerProvider)
            .verification;
        if (current != null && verification != current) {
          verification = current;
          debugPrint('F01_PHONE_VERIFICATION $verification');
        }
        if (DateTime.now().isAfter(deadline)) {
          fail(
            'F01 timeout: ${container.read(noteSummaryProvider).phase} / ${container.read(noteSummaryProvider).message} / ${container.read(companionControllerProvider).message}',
          );
        }
        await tester.pump(const Duration(milliseconds: 250));
      }
    }

    container.read(companionControllerProvider);
    await waitFor(
      () =>
          !container.read(companionControllerProvider).busy &&
          container.read(companionControllerProvider).phase !=
              CompanionPhase.loading,
    );
    if (raw.isNotEmpty) {
      final desktopId = (jsonDecode(raw) as Map<String, dynamic>)['id'];
      final connection = container.read(companionControllerProvider);
      if (connection.computers.any((c) => c.id == desktopId)) {
        await container
            .read(companionControllerProvider.notifier)
            .select(desktopId as String);
      } else {
        unawaited(
          container
              .read(companionControllerProvider.notifier)
              .pair(raw, 'F01 physical phone'),
        );
      }
    }
    await waitFor(
      () =>
          container.read(companionControllerProvider).phase ==
          CompanionPhase.connected,
      seconds: 150,
    );
    final report = <String, dynamic>{
      'physicalPhone': true,
      'syntheticNote': true,
      'restart': restart,
      'network': 'real private IPv4 LAN; WAN availability not controlled',
      'role': 'secondary (read existing notes, add only)',
    };
    container.read(noteSummaryProvider);
    if (missing) {
      await waitFor(
        () => container.read(noteSummaryProvider).phase == 'completed',
      );
      await container.read(noteSummaryProvider.notifier).clear();
      final note = repo.saveNote(
        title: 'Missing-model demo',
        content: 'This note must remain saved.',
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: NoteSummaryPage(noteId: note.uuid)),
        ),
      );
      await container.read(noteSummaryProvider.notifier).start(note.uuid);
      await tester.pump();
      expect(container.read(noteSummaryProvider).phase, 'error');
      expect(container.read(noteSummaryProvider).message, contains('model'));
      expect(container.read(noteSummaryProvider).handle, null);
      expect(
        repo.getNoteByUuid(note.uuid)!.content,
        'This note must remain saved.',
      );
      expect(wire.posts, 0);
      report['missingModelNoSubmission'] = true;
      await container.read(noteSummaryProvider.notifier).clear();
      // Remove only this explicitly isolated demo's notes, trust and retained work.
      final demoComputer = container
          .read(companionControllerProvider)
          .selected!;
      await container
          .read(companionControllerProvider.notifier)
          .forget(demoComputer.id);
      db.noteBox.removeAll();
      report['syntheticDataAndTrustCleaned'] = true;
    } else if (restart) {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: NoteSummaryPage()),
        ),
      );
      await waitFor(
        () => container.read(noteSummaryProvider).phase == 'completed',
      );
      expect(container.read(noteSummaryProvider).stale, true);
      expect(
        find.byKey(const ValueKey('summary-source-changed')),
        findsOneWidget,
      );
      report['protectedHandleRecovered'] = true;
      report['earlierSourceLabelAfterReopen'] = true;
      report['newSubmissions'] = wire.posts;
      expect(wire.posts, 0);
    } else {
      await container.read(summaryStoreProvider).save(null);
      // Start the summary provider afresh after clearing this synthetic demo's prior handle.
      container.invalidate(noteSummaryProvider);
      final note = repo.saveNote(
        title: 'Project meeting',
        content: 'The project meeting is on Friday. Mira will bring the draft. Budget approval remains pending.',
      );
      final before = jsonEncode(
        repo.getNoteByUuid(note.uuid)!.toSyncJson('F01 phone'),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: EditNotePage(existingNote: note)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Summarize saved note'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Summarize'));
      await tester.pump();
      await waitFor(() => container.read(noteSummaryProvider).phase == 'error');
      final id = container.read(noteSummaryProvider).handle!.id;
      expect(container.read(noteSummaryProvider).handle!.accepted, false);
      report['lostAcknowledgmentInjectedAfterRealAcceptance'] = true;
      await container.read(companionControllerProvider.notifier).disconnect();
      await container.read(noteSummaryProvider.notifier).retry();
      expect(container.read(noteSummaryProvider).message, contains('paused'));
      await container
          .read(companionControllerProvider.notifier)
          .disconnect(resume: true);
      await waitFor(
        () =>
            container.read(companionControllerProvider).phase ==
            CompanionPhase.connected,
      );
      await container.read(noteSummaryProvider.notifier).retry();
      await waitFor(
        () => container.read(noteSummaryProvider).phase == 'completed',
      );
      final summary = container.read(noteSummaryProvider);
      expect(summary.handle!.id, id);
      expect(wire.posts, 1);
      expect(summary.text, isNotEmpty);
      expect(summary.stale, false);
      expect(find.byKey(const ValueKey('summary-output')), findsOneWidget);
      expect(
        jsonEncode(repo.getNoteByUuid(note.uuid)!.toSyncJson('F01 phone')),
        before,
      );
      report['originalUnchanged'] = true;
      report['lostAckRecoveredWithoutResubmission'] = true;
      report['disconnectReconnectRetrieval'] = true;
      report['output'] = summary.text;
      // Explicitly change the isolated synthetic source, then retrieve the older task again.
      repo.saveNote(
        uuid: note.uuid,
        title: note.title,
        content: 'The meeting moved to Monday.',
      );
      await container.read(noteSummaryProvider.notifier).retry();
      await tester.pump();
      expect(container.read(noteSummaryProvider).stale, true);
      expect(
        find.byKey(const ValueKey('summary-source-changed')),
        findsOneWidget,
      );
      report['sourceChangeLabel'] = true;
    }
    binding.reportData = report;
    debugPrint('F01_PHONE_EVIDENCE ${jsonEncode(report)}');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
