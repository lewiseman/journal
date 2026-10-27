import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/summary/summary_page.dart';
import 'package:journal/modules/notes/summary/summary_store.dart';
import 'package:journal/modules/notes/summary/summary_task_entity.dart';
import 'package:journal/modules/notes/summary/summary_history_page.dart';
import 'package:journal/modules/root/controllers/journal_account_reset_data.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';
import 'package:sync_wise/sync_wise.dart';

import 'support/sync_fixture.dart';

final computer = TrustedComputer(
  id: 'desktop',
  name: 'Test computer',
  pin: 'a' * 64,
  endpoint: Uri.parse('https://192.168.1.2:47921'),
  seed: base64Encode(List.filled(32, 1)),
  publicKey: base64Encode(List.filled(32, 2)),
  deviceId: 'b' * 32,
);

class MemorySummaries extends SummaryStore {
  SummaryHandle? value;
  bool fail = false;
  Completer<SummaryHandle?>? pending;
  @override
  Future<SummaryHandle?> load() async =>
      pending == null ? value : await pending!.future;
  @override
  Future<void> save(SummaryHandle? handle) async {
    if (fail) throw StateError('disk');
    value = handle;
  }
}

class TestReset extends AccountResetController {
  TestReset() : super((_) => throw UnimplementedError());
  @override
  AccountResetState build() {
    ready = Future.value();
    return const AccountResetState();
  }

  void unblock() => state = const AccountResetState(error: 'Preflight failed');
  void block() => state = const AccountResetState(running: true, pending: true);
}

class TestConnection extends CompanionController {
  @override
  CompanionState build() => CompanionState(
    phase: CompanionPhase.connected,
    computers: [computer],
    selectedId: computer.id,
    status: {
      'recovery': 1,
      'capabilities': [
        {
          'id': 'text',
          'operations': ['summarize-note'],
          'status': 'ready',
        },
      ],
    },
  );
}

class SummaryTransport implements CompanionTransport {
  SummaryTransport(this.store);
  final MemorySummaries store;
  Map<String, dynamic>? job;
  int posts = 0;
  bool lostAck = false, offline = false, noModel = false;
  String output = 'The meeting is Friday; approval is pending.';
  String phase = 'completed';
  Completer<Map<String, dynamic>>? pendingGet;
  final submitted = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> request(
    Uri endpoint,
    String pin,
    String method,
    String route, {
    Map<String, dynamic>? body,
    Map<String, String> headers = const {},
  }) async {
    if (offline) {
      throw const CompanionFailure(
        'UNAVAILABLE',
        'Computer unreachable. Retry on the same Wi-Fi.',
      );
    }
    if (route == '/v1/challenge') return {'nonce': 'a' * 43};
    if (route.endsWith('/ack')) {
      job = null;
      return {'ok': true};
    }
    if (route.endsWith('/cancel')) {
      phase = 'cancelled';
      job ??= {
        'id': route.split('/')[3],
        'device': computer.deviceId,
        'operation': 'summarize-note',
        'model': 'pinned-model',
      };
      return {...job!, 'state': phase};
    }
    if (method == 'POST' && route == '/v1/jobs') {
      if (noModel) throw const CompanionFailure('NOT_READY', 'No model');
      expect(store.value?.id, body!['id'], reason: 'persist before send');
      posts++;
      submitted.add(Map.of(body));
      job = {
        'id': body['id'],
        'device': computer.deviceId,
        'operation': body['operation'],
        'model': 'pinned-model',
        'state': phase,
        'text': output,
      };
      if (lostAck) {
        lostAck = false;
        throw const CompanionFailure('UNAVAILABLE', 'Acceptance lost');
      }
      return job!;
    }
    if (method == 'GET' && route.startsWith('/v1/jobs/')) {
      if (pendingGet != null) return pendingGet!.future;
      if (job == null) throw const CompanionFailure('NOT_FOUND', 'Not found');
      return {...job!, 'state': phase, 'text': output};
    }
    throw StateError('Unexpected route $route');
  }

  @override
  void close() {}
}

ProviderContainer containerFor(
  SyncFixture app,
  SummaryStore store,
  SummaryTransport transport,
) => ProviderContainer(
  overrides: [
    notesRepositoryProvider.overrideWithValue(app.notes),
    summaryStoreProvider.overrideWithValue(store),
    companionTransportProvider.overrideWithValue(transport),
    companionControllerProvider.overrideWith(TestConnection.new),
    accountResetProvider.overrideWith(TestReset.new),
  ],
);
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('preview output remains inert selectable plain text', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [noteSummaryProvider.overrideWith(PreviewSummary.new)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: NoteSummaryPage()),
      ),
    );
    expect(
      tester
          .widget<SelectableText>(find.byKey(const ValueKey('summary-output')))
          .data,
      '<script>alert(1)</script> **literal**',
    );
    await tester.pumpWidget(const SizedBox());
  });
  test('UTF-8 limits and malformed text are explicit, fingerprints include source changes', () async {
    expect(validSummaryText('🦉' * 500, 2000), true);
    for (final text in ['', '   ', '\x00bad', '\ud800', '🦉' * 501]) {
      expect(validSummaryText(text, 2000), false);
    }
  });
  test('only the selected saved text is submitted; plain preview never saves or renders markup', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    final note = app.notes.saveNote(
      uuid: 'chosen',
      title: 'Meeting',
      content: 'Friday. Approval pending.',
      tags: ['secret'],
      attachmentPaths: [
        {'path': '/private/file', 'type': 'text/plain'},
      ],
    );
    app.notes.saveNote(
      uuid: 'other',
      title: 'Other private title',
      content: 'Do not send',
    );
    app.storage.setPrimary(
      const PrimaryDevice(
        deviceId: 'other-primary',
        deviceName: 'Desktop',
        fileId: 'primary',
      ),
    );
    expect(app.storage.canEdit, false);
    final before = jsonEncode(note.toSyncJson('phone'));
    final store = MemorySummaries();
    final client = SummaryTransport(store)
      ..output = '<script>alert(1)</script> **literal**';
    final container = containerFor(app, store, client);
    addTearDown(container.dispose);
    container.read(noteSummaryProvider);
    await settle();
    await container.read(noteSummaryProvider.notifier).start(note.uuid);
    expect(client.submitted.single.keys.toSet(), {
      'id',
      'operation',
      'prompt',
      'expires',
    });
    expect(
      client.submitted.single['prompt'],
      'Meeting\n\nFriday. Approval pending.',
    );
    expect(store.value!.accepted, true);
    expect(store.value!.pendingText, null);
    expect(
      jsonEncode(app.notes.getNoteByUuid(note.uuid)!.toSyncJson('phone')),
      before,
    );
    expect(app.db.noteBox.count(), 2);
    expect(container.read(noteSummaryProvider).text, client.output);
  });
  test('lost acceptance retains identity; reopen retrieves one task after disconnect', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    app.notes.saveNote(uuid: 'chosen', title: 'Meeting', content: 'Friday');
    final store = MemorySummaries();
    final wire = SummaryTransport(store)..lostAck = true;
    var container = containerFor(app, store, wire);
    container.read(noteSummaryProvider);
    await settle();
    await container.read(noteSummaryProvider.notifier).start('chosen');
    final id = store.value!.id;
    expect(container.read(noteSummaryProvider).phase, 'error');
    expect(store.value!.accepted, false);
    expect(wire.posts, 1);
    wire.offline = true;
    await container.read(noteSummaryProvider.notifier).retry();
    expect(store.value!.id, id);
    container.dispose();
    wire.offline = false;
    container = containerFor(app, store, wire);
    addTearDown(container.dispose);
    container.read(noteSummaryProvider);
    await settle();
    expect(container.read(noteSummaryProvider).phase, 'completed');
    expect(store.value!.id, id);
    expect(wire.posts, 1);
  });
  test('changes and deletion mark an earlier version; cancellation preserves source', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    app.notes.saveNote(uuid: 'chosen', title: 'Meeting', content: 'Friday');
    final store = MemorySummaries();
    final client = SummaryTransport(store)..phase = 'running';
    final container = containerFor(app, store, client);
    addTearDown(container.dispose);
    container.read(noteSummaryProvider);
    await settle();
    final controller = container.read(noteSummaryProvider.notifier);
    await controller.start('chosen');
    app.notes.saveNote(uuid: 'chosen', title: 'Meeting', content: 'Monday');
    client.phase = 'completed';
    await controller.retry();
    expect(container.read(noteSummaryProvider).stale, true);
    expect(app.notes.getNoteByUuid('chosen')!.content, 'Monday');
    app.notes.deleteNote('chosen');
    await controller.refreshSource();
    expect(container.read(noteSummaryProvider).stale, true);
    await controller.clear();
    app.notes.saveNote(uuid: 'new', title: 'Cancel', content: 'Keep');
    client.phase = 'running';
    await controller.start('new');
    await controller.cancel();
    expect(container.read(noteSummaryProvider).phase, 'cancelled');
    expect(app.notes.getNoteByUuid('new')!.content, 'Keep');
  });
  test('reset blocks late results and clears protected recovery data before local deletion', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    app.notes.saveNote(uuid: 'chosen', title: 'Meeting', content: 'Friday');
    final store = MemorySummaries();
    final client = SummaryTransport(store)..phase = 'running';
    final container = containerFor(app, store, client);
    addTearDown(container.dispose);
    container.read(noteSummaryProvider);
    await settle();
    final controller = container.read(noteSummaryProvider.notifier);
    await controller.start('chosen');
    client.pendingGet = Completer();
    final retrieving = controller.retry();
    await settle();
    (container.read(accountResetProvider.notifier) as TestReset).block();
    await JournalAccountResetData(
      db: app.db,
      supportDirectory: () async => app.directory,
      clearCachedImages: () async {},
      clearSummaries: () => store.save(null),
    ).clear();
    client.pendingGet!.complete({
      ...client.job!,
      'state': 'completed',
      'text': 'Late summary',
    });
    await retrieving;
    expect(container.read(noteSummaryProvider).handle, null);
    expect(container.read(noteSummaryProvider).text, null);
    expect(store.value, null);
    expect(app.db.noteBox.count(), 0);
  });
  test(
    'limits, failed secure storage and missing model do not claim acceptance',
    () async {
      final app = await SyncFixture.create(MemoryDrive(), 'phone');
      app.notes.saveNote(uuid: 'chosen', title: 'Long', content: '🦉' * 501);
      final store = MemorySummaries();
      final client = SummaryTransport(store);
      final container = containerFor(app, store, client);
      addTearDown(container.dispose);
      container.read(noteSummaryProvider);
      await settle();
      final controller = container.read(noteSummaryProvider.notifier);
      await controller.start('chosen');
      expect(store.value, null);
      expect(
        container.read(noteSummaryProvider).message,
        contains('never truncated'),
      );
      await controller.clear();
      app.notes.saveNote(uuid: 'chosen', title: 'Short', content: 'Saved');
      store.fail = true;
      await controller.start('chosen');
      expect(store.value, null);
      store.fail = false;
      await controller.clear();
      client.noModel = true;
      await controller.start('chosen');
      expect(store.value!.accepted, false);
      expect(
        container.read(noteSummaryProvider).message,
        contains('writing model'),
      );
      await controller.cancel();
      expect(container.read(noteSummaryProvider).phase, 'cancelled');
    },
  );
  test('protected-store restoration blocks new submissions and failed reset preflight recovers the existing task', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    final note = app.notes.saveNote(
      uuid: 'chosen',
      title: 'Meeting',
      content: 'Friday',
    );
    final store = MemorySummaries()..pending = Completer<SummaryHandle?>();
    final client = SummaryTransport(store);
    final container = containerFor(app, store, client);
    addTearDown(container.dispose);
    container.read(noteSummaryProvider);
    final controller = container.read(noteSummaryProvider.notifier);
    await controller.start('chosen');
    expect(client.posts, 0);
    final handle = SummaryHandle(
      id: 'persisted_summary',
      noteId: note.uuid,
      revision: await summaryRevision(app.notes.getNoteByUuid(note.uuid)!),
      computerId: computer.id,
      created: DateTime.now().millisecondsSinceEpoch,
      accepted: true,
    );
    client.job = {
      'id': handle.id,
      'operation': 'summarize-note',
      'device': computer.deviceId,
      'model': 'pinned-model',
      'state': 'completed',
      'text': 'Friday meeting',
    };
    store.value = handle;
    store.pending!.complete(handle);
    await settle();
    expect(container.read(noteSummaryProvider).phase, 'completed');
    final reset = container.read(accountResetProvider.notifier) as TestReset;
    reset.block();
    expect(container.read(noteSummaryProvider).handle, null);
    reset.unblock();
    await settle();
    expect(container.read(noteSummaryProvider).handle!.id, handle.id);
    expect(client.posts, 0);
  });
  test(
    'a changed source with no accepted work is never submitted on retry',
    () async {
      final app = await SyncFixture.create(MemoryDrive(), 'phone');
      app.notes.saveNote(uuid: 'chosen', title: 'Saved', content: 'Original');
      final store = MemorySummaries();
      final client = SummaryTransport(store)..noModel = true;
      final container = containerFor(app, store, client);
      addTearDown(container.dispose);
      container.read(noteSummaryProvider);
      await settle();
      final controller = container.read(noteSummaryProvider.notifier);
      await controller.start('chosen');
      app.notes.deleteNote('chosen');
      client.noModel = false;
      await controller.retry();
      expect(client.posts, 0);
      expect(container.read(noteSummaryProvider).phase, 'failed');
      expect(container.read(noteSummaryProvider).stale, true);
      await controller.clear();
      expect(store.value, null);
    },
  );
  test(
    'invalid completed output can be cleared without modifying the note',
    () async {
      final app = await SyncFixture.create(MemoryDrive(), 'phone');
      app.notes.saveNote(uuid: 'chosen', title: 'Meeting', content: 'Friday');
      final store = MemorySummaries();
      final client = SummaryTransport(store)..output = ' ';
      final container = containerFor(app, store, client);
      addTearDown(container.dispose);
      container.read(noteSummaryProvider);
      await settle();
      final controller = container.read(noteSummaryProvider.notifier);
      await controller.start('chosen');
      expect(container.read(noteSummaryProvider).phase, 'failed');
      expect(container.read(noteSummaryProvider).text, null);
      await controller.clear();
      expect(store.value, null);
      expect(app.notes.getNoteByUuid('chosen')!.content, 'Friday');
    },
  );
  test('ObjectBox history excludes content, migrates protected handles, and retries offline acknowledgment', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    app.notes.saveNote(
      uuid: 'chosen',
      title: 'Private title',
      content: 'Private body',
    );
    final protected = MemorySummaries();
    final store = ObjectBoxSummaryStore(app.db.store, protected: protected);
    final wire = SummaryTransport(protected);
    var container = containerFor(app, store, wire);
    container.read(noteSummaryProvider);
    await settle();
    await container.read(noteSummaryProvider.notifier).start('chosen');
    final id = container.read(noteSummaryProvider).handle!.id;
    expect((await store.history()).single.phase, 'completed');
    final raw = app.db.store.box<SummaryTaskEntity>().getAll().single.metadata;
    expect(raw, isNot(contains('Private')));
    expect(raw, isNot(contains(wire.output)));
    expect(raw, isNot(contains('pendingText')));
    wire.offline = true;
    await container.read(noteSummaryProvider.notifier).clear();
    expect(await store.load(), null);
    expect((await store.history()).single.ackPending, true);
    container.dispose();
    wire.offline = false;
    container = containerFor(app, store, wire);
    addTearDown(container.dispose);
    container.read(noteSummaryProvider);
    await settle();
    final receipt = (await store.history()).single;
    expect(receipt.id, id);
    expect(receipt.acknowledged, true);
    expect(receipt.ackPending, false);
    expect(wire.posts, 1);
    expect(wire.job, null);
    expect(app.collections.map((c) => c.type), ['note', 'diary', 'thought']);
    await JournalAccountResetData(
      db: app.db,
      supportDirectory: () async => app.directory,
      clearCachedImages: () async {},
      clearSummaries: store.clearAll,
    ).clear();
    expect(await store.history(), isEmpty);
    expect(protected.value, null);
  });

  test(
    'expired protected request becomes visible metadata and never resubmits',
    () async {
      final app = await SyncFixture.create(MemoryDrive(), 'phone');
      final protected = MemorySummaries()
        ..value = SummaryHandle(
          id: 'expired_request',
          noteId: 'deleted-source',
          revision: 'a' * 64,
          computerId: computer.id,
          deviceId: computer.deviceId,
          created: DateTime.now()
              .subtract(const Duration(hours: 25))
              .millisecondsSinceEpoch,
          pendingText: 'Private pending input',
        );
      final store = ObjectBoxSummaryStore(app.db.store, protected: protected);
      final wire = SummaryTransport(protected);
      final container = containerFor(app, store, wire);
      addTearDown(container.dispose);
      container.read(noteSummaryProvider);
      await settle();
      expect(container.read(noteSummaryProvider).phase, 'expired');
      expect(protected.value!.pendingText, null);
      expect((await store.history()).single.phase, 'expired');
      await container.read(noteSummaryProvider.notifier).retry();
      expect(wire.posts, 0);
    },
  );

  test(
    'unknown acceptance cancellation uses a durable fence without submitting',
    () async {
      final app = await SyncFixture.create(MemoryDrive(), 'phone');
      app.notes.saveNote(uuid: 'chosen', title: 'Meeting', content: 'Friday');
      final store = MemorySummaries();
      final wire = SummaryTransport(store)..noModel = true;
      final container = containerFor(app, store, wire);
      addTearDown(container.dispose);
      container.read(noteSummaryProvider);
      await settle();
      final controller = container.read(noteSummaryProvider.notifier);
      await controller.start('chosen');
      expect(store.value!.accepted, false);
      await controller.cancel();
      expect(store.value!.cancelWanted, true);
      expect(container.read(noteSummaryProvider).phase, 'cancelled');
      expect(wire.posts, 0);
    },
  );

  test('task ownership survives pairing changes without resubmitting private input', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    final store = MemorySummaries()
      ..value = SummaryHandle(
        id: 'older_pairing_task',
        noteId: 'chosen',
        revision: 'a' * 64,
        computerId: computer.id,
        deviceId: 'c' * 32,
        created: DateTime.now().millisecondsSinceEpoch,
        pendingText: 'Private input',
      );
    final wire = SummaryTransport(store);
    final container = containerFor(app, store, wire);
    addTearDown(container.dispose);
    container.read(noteSummaryProvider);
    await settle();
    expect(container.read(noteSummaryProvider).phase, 'failed');
    expect(container.read(noteSummaryProvider).message, contains('authorizes'));
    expect(wire.posts, 0);
  });

  testWidgets(
    'history shows each status and opens recovery on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer(
        overrides: [
          noteSummaryProvider.overrideWith(PreviewSummary.new),
          companionControllerProvider.overrideWith(TestConnection.new),
          summaryHistoryProvider.overrideWith(
            (_) async => [
              for (final phase in [
                'queued',
                'running',
                'completed',
                'failed',
                'cancelled',
                'expired',
              ])
                SummaryHandle(
                  id: 'history_$phase',
                  noteId: 'source',
                  revision: 'a' * 64,
                  computerId: computer.id,
                  created: DateTime.now().millisecondsSinceEpoch,
                  accepted: true,
                  phase: phase,
                ),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SummaryHistoryPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('AI task history'), findsOneWidget);
      expect(find.text('Note summary · Accepted · waiting'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.text('Note summary · Expired'), findsOneWidget);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test('only explicit retry of terminal work creates a new identity, with the same unchanged source', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    app.notes.saveNote(uuid: 'chosen', title: 'Meeting', content: 'Friday');
    final store = MemorySummaries();
    final wire = SummaryTransport(store)..lostAck = true;
    final container = containerFor(app, store, wire);
    addTearDown(container.dispose);
    container.read(noteSummaryProvider);
    await settle();
    final controller = container.read(noteSummaryProvider.notifier);
    await controller.start('chosen');
    final original = store.value!.id;
    await controller.retryAsNew();
    expect(
      wire.posts,
      1,
      reason: 'unknown acceptance must not create another task',
    );
    wire.phase = 'failed';
    await controller.retry();
    expect(container.read(noteSummaryProvider).phase, 'failed');
    wire.phase = 'completed';
    await controller.retryAsNew();
    expect(wire.posts, 2);
    expect(store.value!.id, isNot(original));
    expect(app.notes.getNoteByUuid('chosen')!.content, 'Friday');
    wire.phase = 'failed';
    await controller.retry();
    app.notes.deleteNote('chosen');
    await controller.retryAsNew();
    expect(wire.posts, 2, reason: 'deleted content cannot be resurrected');
  });
}

class PreviewSummary extends NoteSummaryController {
  @override
  NoteSummaryState build() => const NoteSummaryState(
    phase: 'completed',
    text: '<script>alert(1)</script> **literal**',
  );
}
