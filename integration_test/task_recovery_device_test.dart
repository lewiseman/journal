// Opt-in physical recovery demo. Uses isolated notes, task references and trust keys.
// The first launch intentionally waits to be force-stopped after real acceptance.
// A second launch of the same test recovers the persisted task without a POST.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/controllers/notes_repository.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/summary/summary_history_page.dart';
import 'package:journal/modules/notes/summary/summary_store.dart';
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
  String get deviceId => 'r01-demo-phone';
  @override
  String get deviceName => 'R01 physical phone';
}

class _Reset extends AccountResetController {
  _Reset() : super((_) => throw UnimplementedError());
  @override
  AccountResetState build() {
    ready = Future.value();
    return const AccountResetState();
  }
}

class _DropAcceptance implements CompanionTransport {
  final inner = PinnedCompanionTransport();
  int posts = 0;
  bool drop = true;
  Future<void> Function(Map<String, dynamic>)? onAccepted;
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
        await onAccepted?.call(result);
        throw const CompanionFailure(
          'UNAVAILABLE',
          'Test-only: real accepted response discarded',
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
  const code = String.fromEnvironment('COMPANION_PAIRING_CODE');
  const fixture = String.fromEnvironment('RECOVERY_TRUSTED_COMPUTER');
  testWidgets('recover real accepted task after Android force-stop', (
    tester,
  ) async {
    final support = await getApplicationSupportDirectory();
    final marker = File('${support.path}/r01-force-close-marker.json');
    final restart = await marker.exists();
    final trust = ProtectedComputerStore(
      key: 'journal.companion.r01-demo.trust',
    );
    if (!restart && fixture.isNotEmpty) {
      final computer = TrustedComputer.fromJson(
        jsonDecode(fixture) as Map<String, dynamic>,
      );
      await trust.save(ComputerRecords([computer], computer.id));
    }
    final db = ObjectBox.fromStore(
      await openStore(directory: '${support.path}/r01-synthetic-objectbox'),
    );
    final repo = NotesRepository(
      db: db,
      device: _Device(),
      sync: SyncStateStore(
        storage: MemorySyncKeyValueStore(),
        deviceId: 'r01-demo-phone',
      ),
    );
    final wire = _DropAcceptance();
    final store = ObjectBoxSummaryStore(
      db.store,
      protected: ProtectedSummaryStore(
        key: 'journal.companion.r01-demo.summary',
      ),
    );
    if (!restart) {
      await store.clearAll();
      db.noteBox.removeAll();
    }
    final container = ProviderContainer(
      overrides: [
        objectBoxProvider.overrideWithValue(db),
        notesRepositoryProvider.overrideWithValue(repo),
        accountResetProvider.overrideWith(_Reset.new),
        syncDeviceRoleProvider.overrideWithValue(SyncDeviceRole.secondary),
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
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SummaryHistoryPage()),
      ),
    );
    Future<void> waitFor(bool Function() ready, {int seconds = 120}) async {
      final deadline = DateTime.now().add(Duration(seconds: seconds));
      String? verification;
      while (!ready()) {
        final value = container.read(companionControllerProvider).verification;
        if (value != null && verification != value) {
          verification = value;
          debugPrint('R01_PHONE_VERIFICATION $value');
        }
        if (DateTime.now().isAfter(deadline)) {
          fail(
            'R01 timeout: ${container.read(noteSummaryProvider).phase} ${container.read(noteSummaryProvider).message} ${container.read(companionControllerProvider).message}',
          );
        }
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await waitFor(() => !container.read(companionControllerProvider).busy);
    if (!restart &&
        container.read(companionControllerProvider).computers.isEmpty) {
      expect(
        code,
        isNotEmpty,
        reason: 'Provide a fresh full pairing code for the isolated demo',
      );
      unawaited(
        container
            .read(companionControllerProvider.notifier)
            .pair(code, 'R01 physical Android'),
      );
    }
    await waitFor(
      () =>
          container.read(companionControllerProvider).phase ==
          CompanionPhase.connected,
    );
    await waitFor(() => !container.read(noteSummaryProvider).busy);
    final controller = container.read(noteSummaryProvider.notifier);
    if (!restart) {
      final note = repo.saveNote(
        title: 'R01 synthetic planning',
        content:
            'The project meeting is Friday. Mira will bring the draft. Budget approval remains pending. ' *
            19,
      );
      final before = jsonEncode(
        repo.getNoteByUuid(note.uuid)!.toSyncJson('R01 physical phone'),
      );
      wire.onAccepted = (job) async {
        await marker.writeAsString(
          jsonEncode({
            'id': job['id'],
            'noteId': note.uuid,
            'before': before,
            'posts': wire.posts,
          }),
          flush: true,
        );
        debugPrint('R01_FORCE_CLOSE_READY ${job['id']} ${job['state']}');
      };
      await controller.start(note.uuid);
      expect(container.read(noteSummaryProvider).phase, 'error');
      expect(wire.posts, 1);
      expect(container.read(noteSummaryProvider).handle!.accepted, false);
      await Completer<void>()
          .future; // External adb force-stop is the intended first-run outcome.
    } else {
      final saved =
          jsonDecode(await marker.readAsString()) as Map<String, dynamic>;
      debugPrint('R01_RESTART_RETRIEVING');
      await waitFor(() => container.read(noteSummaryProvider).terminal);
      final recovered = container.read(noteSummaryProvider);
      expect(recovered.handle!.id, saved['id']);
      expect(recovered.phase, 'completed');
      expect(recovered.text, isNotEmpty);
      expect(wire.posts, 0);
      debugPrint('R01_RESTART_SAME_RESULT_ZERO_POSTS');
      expect(
        jsonEncode(
          repo
              .getNoteByUuid(saved['noteId'] as String)!
              .toSyncJson('R01 physical phone'),
        ),
        saved['before'],
      );
      await tester.pumpAndSettle();
      expect(find.text('Note summary · Completed'), findsOneWidget);
      await tester.tap(find.text('Open / recover task'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('summary-output')), findsOneWidget);
      final report = <String, dynamic>{
        'physicalAndroid': true,
        'realPinnedLanAndQvac': true,
        'sameIdAfterForceStop': true,
        'newSubmissionsAfterRestart': wire.posts,
        'originalPersistedSourceUnchanged': true,
        'historyOpenedRecoveredPreview': true,
        'output': recovered.text,
      };
      repo.deleteNote(saved['noteId'] as String);
      await controller.refreshSource();
      await tester.pump();
      expect(container.read(noteSummaryProvider).stale, true);
      expect(
        find.byKey(const ValueKey('summary-source-changed')),
        findsOneWidget,
      );
      report['deletedSourceDidNotReappear'] = repo
          .getNoteByUuid(saved['noteId'] as String)!
          .isDeleted;
      await controller.clear();
      expect((await store.history()).single.acknowledged, true);
      report['desktopResultAcknowledged'] = true;
      final computer = container.read(companionControllerProvider).selected!;
      await container
          .read(companionControllerProvider.notifier)
          .forget(computer.id);
      await store.clearAll();
      db.noteBox.removeAll();
      await marker.delete();
      report['isolatedTrustAndDataCleaned'] = true;
      binding.reportData = report;
      await File('${support.path}/r01-device-evidence.json')
          .writeAsString(jsonEncode(report), flush: true);
      debugPrint('R01_DEVICE_EVIDENCE ${jsonEncode(report)}');
      await tester.pumpWidget(const SizedBox());
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}
