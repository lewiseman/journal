import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/objectbox/objectbox.dart';
import 'package:journal/modules/root/controllers/journal_sync_collections.dart';
import 'package:journal/modules/root/controllers/journal_sync_store.dart';
import 'package:journal/modules/notes/controllers/notes_repository.dart';
import 'package:journal/modules/diary/controllers/diary_repository.dart';
import 'package:journal/objectbox/objectbox.g.dart';
import 'package:sync_wise/sync_wise.dart';

import '../../packages/sync_wise/test/support/memory_backend.dart';
export '../../packages/sync_wise/test/support/memory_backend.dart';

class TestDevice extends Fake implements DeviceIdentityService {
  @override
  final String deviceId;
  TestDevice(this.deviceId);
  @override
  String get deviceName => deviceId;
}

/// Reset storage without platform I/O for unrelated provider/widget tests.
class TestResetStorage extends AccountResetStorage {
  ResetIntent? intent;
  @override
  Future<bool> canSync() async => intent == null;
  @override
  Future<ResetIntent?> read() async => intent;
  @override
  Future<void> write(ResetIntent value) async {
    intent = value;
  }

  @override
  Future<void> finish() async {
    intent = null;
  }
}

class SyncFixture {
  final Directory directory;
  late final ObjectBox db;
  final TestDevice device;
  final TestNetwork network = TestNetwork();
  late final SyncStateStore storage;
  late final NotesRepository notes;
  late final DiaryRepository diary;
  late final List<SyncCollection> collections;
  late final MemoryBackend backend;
  late final ProviderContainer container;
  late final NotifierProvider<SyncEngine, SyncEngineState> provider;
  SyncEngine get engine => container.read(provider.notifier);
  SyncEngineState get state => container.read(provider);
  DateTime now = DateTime(2026, 10, 26, 12);
  SyncFixture._(this.directory, this.device);
  static Future<SyncFixture> create(
    MemoryDrive drive,
    String id, {
    Directory? directory,
  }) async {
    final fixture = SyncFixture._(
      directory ?? await Directory.systemTemp.createTemp('journal-sync-'),
      TestDevice(id),
    );
    fixture.db = ObjectBox.fromStore(
      Store(getObjectBoxModel(), directory: '${fixture.directory.path}/db'),
    );
    addTearDown(() async {
      fixture.db.close();
      if (directory == null) await fixture.directory.delete(recursive: true);
    });
    fixture.storage = SyncStateStore(
      storage: JournalSyncKeyValueStore(fixture.db.store),
      deviceId: id,
      now: () => fixture.now,
    );
    fixture.notes = NotesRepository(
      db: fixture.db,
      device: fixture.device,
      sync: fixture.storage,
      onDataChanged: () => fixture.engine.scheduleSync(),
    );
    fixture.diary = DiaryRepository(
      db: fixture.db,
      device: fixture.device,
      sync: fixture.storage,
      onDataChanged: () => fixture.engine.scheduleSync(),
    );
    fixture.collections = journalSyncCollections(
      db: fixture.db,
      device: fixture.device,
      notes: fixture.notes,
      diary: fixture.diary,
      storage: fixture.storage,
    );
    fixture.backend = MemoryBackend(drive);
    addTearDown(fixture.backend.dispose);
    fixture.provider = NotifierProvider<SyncEngine, SyncEngineState>(
      () => SyncEngine(
        (ref) => SyncEngineConfig(
          backend: fixture.backend,
          deviceId: id,
          deviceName: id,
          network: fixture.network,
          collections: fixture.collections,
          storage: fixture.storage,
        ),
      ),
      retry: (_, _) => null,
    );
    fixture.container = ProviderContainer.test();
    fixture.container.read(fixture.provider);
    return fixture;
  }

  void elapse([Duration duration = const Duration(minutes: 1)]) {
    now = now.add(duration);
  }

  Future<void> sync({bool manual = false}) async {
    elapse();
    await engine.syncNow(manual: manual);
    expect(state.status, isNot(EngineSyncState.error), reason: state.lastError);
  }
}
