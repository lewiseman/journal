import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/objectbox/objectbox.dart';
import 'package:journal/modules/root/controllers/journal_sync_store.dart';
import 'package:journal/modules/root/controllers/journal_sync_collections.dart';
import 'package:journal/modules/diary/controllers/diary_repository.dart';
import 'package:journal/modules/notes/controllers/notes_repository.dart';
import 'package:journal/modules/flow/controllers/thoughts_repository.dart';
import 'package:journal/objectbox/objectbox.g.dart';
import 'package:sync_wise/sync_wise.dart';

import 'support/sync_fixture.dart'
    show TestDevice, MemoryDrive, MemoryBackend, TestNetwork;

void main() {
  test('secondary creations, role and edit timestamps survive closing and reopening ObjectBox', () async {
    final directory = await Directory.systemTemp.createTemp('sync-restart-');
    addTearDown(() => directory.delete(recursive: true));
    final device = TestDevice('secondary');
    final now = DateTime(2026, 10, 26, 12);
    late String thoughtUuid;
    final first = ObjectBox.fromStore(
      Store(getObjectBoxModel(), directory: directory.path),
    );
    try {
      final storage = SyncStateStore(
        storage: JournalSyncKeyValueStore(first.store),
        deviceId: device.deviceId,
        now: () => now,
      );
      storage.setPrimary(
        const PrimaryDevice(
          deviceId: 'primary',
          deviceName: 'Phone',
          fileId: 'registry',
        ),
      );
      final repo = NotesRepository(db: first, device: device, sync: storage);
      repo.saveNote(uuid: 'durable', title: 'Offline', content: 'persist me');
      DiaryRepository(db: first, device: device, sync: storage).addTimelineItem(
        dateString: '2026-10-26',
        content: 'Diary saved offline',
      );
      thoughtUuid = ThoughtsRepository(
        db: first,
        device: device,
        sync: storage,
      ).saveThought(content: 'Thought saved offline').uuid;
    } finally {
      first.close();
    }
    final reopened = ObjectBox.fromStore(
      Store(getObjectBoxModel(), directory: directory.path),
    );
    addTearDown(reopened.close);
    final storage = SyncStateStore(
      storage: JournalSyncKeyValueStore(reopened.store),
      deviceId: device.deviceId,
      now: () => now.add(const Duration(seconds: 30)),
    );
    expect(storage.role, SyncDeviceRole.secondary);
    expect(
      storage.pendingCreations.map((op) => op.documentId),
      containsAll(['durable', '2026-10-26', thoughtUuid]),
    );
    expect(
      reopened.diaryBox.getAll().single.items.single.content,
      'Diary saved offline',
    );
    expect(
      storage.protected('note', 'durable', 'record', storage.now()),
      isTrue,
    );
    final drive = MemoryDrive()
      ..primary = const PrimaryDevice(
        deviceId: 'primary',
        deviceName: 'Phone',
        fileId: 'registry',
      );
    final backend = MemoryBackend(drive);
    addTearDown(backend.dispose);
    final notes = NotesRepository(db: reopened, device: device, sync: storage);
    final diary = DiaryRepository(db: reopened, device: device, sync: storage);
    final thoughts = ThoughtsRepository(
      db: reopened,
      device: device,
      sync: storage,
    );
    final restoredThought = thoughts.getThoughtByUuid(thoughtUuid)!;
    expect(restoredThought.content, 'Thought saved offline');
    expect(restoredThought.summary, '');
    expect(restoredThought.createdAt, now);
    expect(restoredThought.lastEditedByDeviceId, 'secondary');
    expect(restoredThought.status, SyncStatus.pendingUpload);
    final provider = NotifierProvider<SyncEngine, SyncEngineState>(
      () => SyncEngine(
        (ref) => SyncEngineConfig(
          backend: backend,
          deviceId: device.deviceId,
          deviceName: device.deviceName,
          network: TestNetwork(),
          storage: storage,
          collections: journalSyncCollections(
            db: reopened,
            device: device,
            notes: notes,
            diary: diary,
            thoughts: thoughts,
            storage: storage,
          ),
        ),
      ),
      retry: (_, _) => null,
    );
    final container = ProviderContainer.test();
    await container.read(provider.notifier).syncNow();
    expect(drive.documents['note/durable']!.payload['content'], 'persist me');
    expect(storage.pendingCreations, isEmpty);
    expect(
      drive.documents['thought/$thoughtUuid']!.payload['content'],
      'Thought saved offline',
    );
    expect(thoughts.getThoughtByUuid(thoughtUuid)!.status, SyncStatus.synced);
    expect(
      (drive.documents['diary/2026-10-26']!.payload['items'] as List)
          .single['content'],
      'Diary saved offline',
    );
  });
}
