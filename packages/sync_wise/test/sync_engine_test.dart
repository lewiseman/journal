import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_wise/sync_wise.dart';

import 'support/memory_backend.dart';

class _Tasks implements SyncCollection {
  final SyncStateStore storage;
  final records = <String, SyncDocument>{};
  _Tasks(this.storage);
  @override
  String get type => 'task';
  @override
  String get label => 'tasks';
  @override
  bool get requiresRemoteForCreation => false;
  void edit(String id, String content) {
    final isNew = !records.containsKey(id);
    records[id] = SyncDocument(
      id: id,
      payload: {'id': id, 'content': content},
      status: SyncStatus.pendingUpload,
    );
    storage.edited(type, id);
    if (isNew) {
      storage.enqueue(
        PendingCreation(
          id: id,
          type: type,
          documentId: id,
          payload: records[id]!.payload,
        ),
      );
    }
  }

  @override
  List<String> get allIds => records.keys.toList();
  @override
  List<String> get pendingIds => records.values
      .where((d) => d.status == SyncStatus.pendingUpload)
      .map((d) => d.id)
      .toList();
  @override
  SyncDocument? read(String id) => records[id];
  @override
  SyncDocument decode(Map<String, dynamic> json) =>
      SyncDocument(id: json['id'] as String, payload: json);
  @override
  bool mergeRemote(SyncDocument document, {required DateTime now}) {
    if (!storage.dirty(type, document.id)) records[document.id] = document;
    return false;
  }

  @override
  SyncDocument appendCreations(
    SyncDocument? remote,
    List<PendingCreation> operations,
  ) => remote ?? decode(operations.single.payload);
  @override
  List<SyncDocument> migrateLegacy(List<RemoteDocument> docs, String primary) =>
      docs.map((d) => decode(d.payload)).toList();
  @override
  void markPending(String id) {
    final d = records[id]!;
    records[id] = SyncDocument(
      id: id,
      payload: d.payload,
      status: SyncStatus.pendingUpload,
    );
  }

  @override
  void acknowledgeUpload(SyncDocument document) {
    records[document.id] = decode(document.payload);
    storage.clean(type, document.id);
    for (final op
        in storage.pendingCreations
            .where((o) => o.documentId == document.id)
            .toList()) {
      storage.acknowledgeCreation(op);
    }
  }

  @override
  void acknowledgeCreations(
    List<PendingCreation> operations,
    SyncDocument uploaded,
  ) {
    for (final op in operations) {
      storage.acknowledgeCreation(op);
    }
    records[uploaded.id] = uploaded;
  }

  @override
  void restrictToSecondary() {}
}

class _Harness {
  late final MemoryBackend backend;
  late final SyncStateStore storage;
  late final _Tasks tasks;
  late final ProviderContainer container;
  late final NotifierProvider<SyncEngine, SyncEngineState> provider;
  final network = TestNetwork();
  DateTime now = DateTime.utc(2026, 10, 26);
  SyncEngine get engine => container.read(provider.notifier);
  SyncEngineState get state => container.read(provider);
  _Harness(MemoryDrive drive) {
    backend = MemoryBackend(drive);
    addTearDown(backend.dispose);
    storage = SyncStateStore(
      storage: MemorySyncKeyValueStore(),
      deviceId: 'device',
      now: () => now,
    );
    tasks = _Tasks(storage);
    provider = NotifierProvider<SyncEngine, SyncEngineState>(
      () => SyncEngine(
        (ref) => SyncEngineConfig(
          backend: backend,
          deviceId: 'device',
          deviceName: 'Device',
          network: network,
          storage: storage,
          collections: [tasks],
        ),
      ),
      retry: (_, _) => null,
    );
    container = ProviderContainer.test();
    container.read(provider);
  }
}

void main() {
  test(
    'provider-neutral collections sync through a non-Google backend',
    () async {
      final drive = MemoryDrive();
      final h = _Harness(drive);
      h.tasks.edit('one', 'text');
      await h.engine.syncNow();
      expect(drive.documents['task/one']!.payload['content'], 'text');
      expect(h.state.status, EngineSyncState.idle);
      expect(h.state.role, SyncDeviceRole.primary);
      expect(h.backend.closed, h.backend.sessions);
    },
  );
  test(
    'automatic cooldown is enforced and manual requests bypass it',
    () async {
      final drive = MemoryDrive();
      final h = _Harness(drive);
      await h.engine.syncNow();
      h.tasks.edit('one', 'new');
      await h.engine.syncNow();
      expect(drive.uploads, 0);
      await h.engine.syncNow(manual: true);
      expect(drive.uploads, 1);
    },
  );
  testWidgets('scheduled writes are retained until the cooldown expires', (
    tester,
  ) async {
    final drive = MemoryDrive();
    final h = _Harness(drive);
    await h.engine.syncNow();
    h.tasks.edit('one', 'queued');
    h.engine.scheduleSync();
    h.now = h.now.add(const Duration(seconds: 59));
    await tester.pump(const Duration(seconds: 59));
    expect(drive.uploads, 0);
    h.now = h.now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(drive.uploads, 1);
  });
  testWidgets('debounce coalesces several writes', (tester) async {
    final drive = MemoryDrive();
    final h = _Harness(drive);
    h.tasks.edit('one', 'a');
    h.engine.scheduleSync();
    await tester.pump(const Duration(milliseconds: 100));
    h.tasks.edit('one', 'b');
    h.engine.scheduleSync();
    await tester.pump(const Duration(milliseconds: 299));
    expect(drive.uploads, 0);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(drive.uploads, 1);
    expect(drive.documents['task/one']!.payload['content'], 'b');
  });
  testWidgets('offline retry waits at least one minute', (tester) async {
    final drive = MemoryDrive();
    final h = _Harness(drive);
    h.tasks.edit('one', 'offline');
    h.network.online = false;
    await h.engine.syncNow();
    expect(h.state.status, EngineSyncState.offline);
    h.network.online = true;
    h.now = h.now.add(const Duration(minutes: 1));
    await tester.pump(const Duration(minutes: 1));
    await tester.pump();
    expect(drive.uploads, 1);
  });
  test('suspend drains the active request before deletion and reset clears cached roles', () async {
    final drive = MemoryDrive();
    final h = _Harness(drive);
    h.tasks.edit('one', 'upload');
    final entered = Completer<void>(), release = Completer<void>();
    drive.beforeUpload = (_, _) async {
      entered.complete();
      await release.future;
    };
    final syncing = h.engine.syncNow();
    await entered.future;
    await expectLater(
      h.engine.suspendForReset(requireIdle: true),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Wait for sync to finish'),
        ),
      ),
    );
    expect(h.state.isSyncing, isTrue);
    var drained = false;
    final draining = h.engine.suspendForReset().then((_) => drained = true);
    await Future<void>.delayed(Duration.zero);
    expect(drained, isFalse);
    release.complete();
    await syncing;
    await draining;
    h.engine.resumeAfterReset(completed: true);
    expect(h.storage.role, SyncDeviceRole.unknown);
    expect(h.state.lastSyncTime, isNull);
    expect(h.state.status, EngineSyncState.unauthenticated);
  });
  test('invalidating a provider discards old async continuations', () async {
    final drive = MemoryDrive();
    final h = _Harness(drive);
    final entered = Completer<void>(), release = Completer<void>();
    drive.seed('task', 'old', {'id': 'old', 'content': 'stale'});
    drive.beforeList = (_) async {
      entered.complete();
      await release.future;
    };
    final syncing = h.engine.syncNow();
    await entered.future;
    h.container.invalidate(h.provider);
    h.container.read(h.provider);
    release.complete();
    await syncing;
    expect(h.tasks.records, isEmpty);
    expect(h.backend.closed, 1);
  });
  test(
    'provider construction failures do not cause Riverpod retries',
    () async {
      var attempts = 0;
      final provider = NotifierProvider<SyncEngine, SyncEngineState>(
        () => SyncEngine((ref) {
          attempts++;
          throw StateError('configuration');
        }),
        retry: (_, _) => null,
      );
      final container = ProviderContainer.test();
      expect(
        () => container.read(provider),
        throwsA(
          predicate((error) => error.toString().contains('configuration')),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(attempts, 1);
    },
  );
  test('reset suspension survives a provider rebuild', () async {
    final drive = MemoryDrive();
    final h = _Harness(drive);
    await h.engine.suspendForReset();
    h.container.invalidate(h.provider);
    h.container.read(h.provider);
    await h.engine.syncNow(manual: true);
    expect(drive.registrations, 0);
    h.engine.resumeAfterReset(completed: false);
    await h.engine.syncNow(manual: true);
    expect(drive.registrations, 1);
  });
}
