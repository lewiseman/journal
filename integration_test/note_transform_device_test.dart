// Opt-in N01 device demo. Isolated synthetic notes, task storage and trust.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/controllers/notes_repository.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/summary/summary_store.dart';
import 'package:journal/modules/notes/views/pages/edit_note_page.dart';
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
  String get deviceId => 'n01-demo-phone';
  @override
  String get deviceName => 'N01 synthetic phone';
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
  int posts = 0;
  bool drop = true;
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
          'Test-only discarded real accepted response',
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
  const fixture = String.fromEnvironment('RECOVERY_TRUSTED_COMPUTER');
  testWidgets(
    'physical writing proposal acceptance, rejection, stale refusal and recovery',
    (tester) async {
      expect(
        fixture,
        isNotEmpty,
        reason: 'Provide the isolated desktop fixture configuration',
      );
      final support = await getApplicationSupportDirectory();
      final trust = ProtectedComputerStore(
        key: 'journal.companion.n01-demo.trust',
      );
      final trusted = TrustedComputer.fromJson(
        jsonDecode(fixture) as Map<String, dynamic>,
      );
      await trust.save(ComputerRecords([trusted], trusted.id));
      final db = ObjectBox.fromStore(
        await openStore(directory: '${support.path}/n01-synthetic-objectbox'),
      );
      final storage = SyncStateStore(
        storage: MemorySyncKeyValueStore(),
        deviceId: 'n01-demo-phone',
      );
      final repo = NotesRepository(db: db, device: _Device(), sync: storage);
      final store = ObjectBoxSummaryStore(
        db.store,
        protected: ProtectedSummaryStore(
          key: 'journal.companion.n01-demo.task',
        ),
      );
      await store.clearAll();
      db.noteBox.removeAll();
      final wire = _Wire();
      final container = ProviderContainer(
        overrides: [
          objectBoxProvider.overrideWithValue(db),
          notesRepositoryProvider.overrideWithValue(repo),
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
      final note = repo.saveNote(
        title: 'N01 synthetic planning',
        content:
            'i has a meeting with Mira on friday. budget approval are pending.',
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: EditNotePage(existingNote: note)),
        ),
      );
      Future<void> waitFor(bool Function() done) async {
        final deadline = DateTime.now().add(const Duration(seconds: 100));
        while (!done()) {
          if (DateTime.now().isAfter(deadline)) {
            fail(
              'N01 timeout: ${container.read(noteSummaryProvider).phase} ${container.read(noteSummaryProvider).message} ${container.read(companionControllerProvider).message}',
            );
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      debugPrint('N01_DEMO_CONNECTING');
      container.read(companionControllerProvider);
      container.read(noteSummaryProvider);
      await waitFor(
        () =>
            container.read(companionControllerProvider).phase ==
                CompanionPhase.connected &&
            !container.read(noteSummaryProvider).busy,
      );
      await tester.pump(const Duration(seconds: 2));
      debugPrint('N01_DEMO_OPENING_EDITOR_ACTION');
      await tester.tap(find.byTooltip('Writing help and recovery'));
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('Writing help'));
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('Format Markdown').last);
      await tester.pump(const Duration(seconds: 2));
      await tester.enterText(
        find.byType(TextField).first,
        'Use a heading and a bullet list.',
      );
      await tester.ensureVisible(find.text('Generate proposal'));
      await tester.tap(find.text('Generate proposal'));
      await tester.pump();
      await waitFor(() => container.read(noteSummaryProvider).phase == 'error');
      final controller = container.read(noteSummaryProvider.notifier);
      final id = container.read(noteSummaryProvider).handle!.id;
      debugPrint('N01_DEMO_RETRIEVING');
      await controller.retry();
      await waitFor(() => container.read(noteSummaryProvider).terminal);
      expect(container.read(noteSummaryProvider).phase, 'completed');
      expect(container.read(noteSummaryProvider).handle!.id, id);
      expect(wire.posts, 1);
      debugPrint('N01_DEMO_REVIEW_READY');
      final proposal = container.read(noteSummaryProvider).text!;
      expect(proposal, isNot(note.content));
      expect(repo.getNoteByUuid(note.uuid)!.content, note.content);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(const ValueKey('transform-original')), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('transform-accept')),
      );
      await tester.tap(find.byKey(const ValueKey('transform-accept')));
      await waitFor(() => container.read(noteSummaryProvider).handle == null);
      expect(repo.getNoteByUuid(note.uuid)!.content, proposal);
      expect(
        repo.transformationHistory(note.uuid).single.beforeContent,
        note.content,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(
        find.byKey(const ValueKey('note-content-preview')),
        findsOneWidget,
      );
      debugPrint('N01_DEMO_OPENING_EDITOR_ACTION');
      await tester.tap(find.byTooltip('Writing help and recovery'));
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('Prior content / recovery'));
      await tester.pump(const Duration(seconds: 2));
      await tester.ensureVisible(find.text('Restore prior body'));
      await tester.tap(find.text('Restore prior body'));
      await tester.pump(const Duration(seconds: 2));
      expect(repo.getNoteByUuid(note.uuid)!.content, note.content);
      final report = <String, dynamic>{
        'physicalAndroid': true,
        'realPinnedLanAndQvac': true,
        'syntheticFixtureBootstrap': true,
        'editorFormToReview': true,
        'discardedRealAcceptanceRetrievedSameId': true,
        'proposal': proposal,
        'explicitAcceptAndRestoreThroughUi': true,
        'recoveryOriginalPreserved': true,
      };
      await controller.start(note.uuid, operation: 'rewrite-note');
      await waitFor(() => container.read(noteSummaryProvider).terminal);
      expect(container.read(noteSummaryProvider).phase, 'completed');
      await controller.clear();
      expect(repo.getNoteByUuid(note.uuid)!.content, note.content);
      report['rejectionPreservedSource'] = true;
      await controller.start(note.uuid, operation: 'expand-note');
      repo.saveNote(
        uuid: note.uuid,
        title: note.title,
        content: 'A later manual edit.',
      );
      await waitFor(() => container.read(noteSummaryProvider).terminal);
      await controller.refreshSource();
      expect(container.read(noteSummaryProvider).stale, true);
      expect(await controller.acceptTransformation(), false);
      expect(repo.getNoteByUuid(note.uuid)!.content, 'A later manual edit.');
      await controller.clear();
      report['sourceChangeRefused'] = true;
      await controller.start(note.uuid, operation: 'clarify-note');
      storage.setPrimary(
        const PrimaryDevice(
          deviceId: 'other',
          deviceName: 'Other',
          fileId: 'primary',
        ),
      );
      await waitFor(() => container.read(noteSummaryProvider).terminal);
      expect(await controller.acceptTransformation(), false);
      expect(repo.getNoteByUuid(note.uuid)!.content, 'A later manual edit.');
      await controller.clear();
      report['roleChangeRefused'] = true;
      await container
          .read(companionControllerProvider.notifier)
          .forget(trusted.id);
      await store.clearAll();
      repo.clearTransformationHistory(note.uuid);
      db.noteBox.removeAll();
      await trust.save(const ComputerRecords([], null));
      report['isolatedDataAndTrustCleaned'] = true;
      binding.reportData = report;
      await File('${support.path}/n01-device-evidence.json')
          .writeAsString(jsonEncode(report), flush: true);
      debugPrint('N01_DEVICE_EVIDENCE ${jsonEncode(report)}');
      await tester.pumpWidget(const SizedBox());
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
