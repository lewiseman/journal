import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/flow/models/thought_entity.dart';
import 'package:sync_wise/sync_wise.dart';

import 'support/sync_fixture.dart';

void main() {
  test(
    'primary restores thoughts and backs up pending local content',
    () async {
      final drive = MemoryDrive();
      final remote = ThoughtEntity(
        uuid: 'remote',
        summary: 'An existing summary',
        content: 'Full cloud content\nWith another line',
        createdAt: DateTime(2026, 10, 25),
        lastEditedByDeviceId: 'old-phone',
      );
      drive.seed('thought', remote.uuid, remote.toSyncJson('old-phone'));
      final app = await SyncFixture.create(drive, 'phone');
      final local = app.thoughts.saveThought(content: 'A local thought');
      await app.sync();
      final restored = app.thoughts.getThoughtByUuid(remote.uuid)!;
      expect(restored.content, remote.content);
      expect(restored.summary, remote.summary);
      expect(restored.createdAt, remote.createdAt);
      expect(restored.lastEditedByDeviceId, 'old-phone');
      expect(restored.status, SyncStatus.synced);
      final payload = drive.documents['thought/${local.uuid}']!.payload;
      expect(payload['summary'], '');
      expect(payload['content'], 'A local thought');
      expect(
        payload.keys,
        unorderedEquals([
          'uuid',
          'summary',
          'content',
          'created_at',
          'updated_at',
          'device_id',
          'device_name',
        ]),
      );
      expect(app.storage.pendingCreations, isEmpty);
      expect(app.thoughts.getPendingUploadThoughts(), isEmpty);
    },
  );

  test(
    'secondary creations upload without listing or reading other entries',
    () async {
      final drive = MemoryDrive();
      final primary = await SyncFixture.create(drive, 'primary');
      await primary.sync();
      final secondary = await SyncFixture.create(drive, 'secondary');
      await secondary.sync();
      expect(secondary.state.role, SyncDeviceRole.secondary);
      final lists = drive.listings.length;
      final reads = drive.reads;
      final thought = secondary.thoughts.saveThought(
        content: 'From another device',
      );
      await secondary.sync();
      expect(drive.listings.length, lists);
      expect(drive.reads, reads);
      expect(
        drive.documents['thought/${thought.uuid}']!.payload['content'],
        'From another device',
      );
      expect(
        secondary.thoughts.getThoughtByUuid(thought.uuid)!.status,
        SyncStatus.synced,
      );
      expect(secondary.storage.pendingCreations, isEmpty);
      await primary.sync();
      expect(primary.thoughts.getThoughtByUuid(thought.uuid), isNull);
      await primary.sync(manual: true);
      expect(
        primary.thoughts.getThoughtByUuid(thought.uuid)!.content,
        thought.content,
      );
    },
  );

  test(
    'real-clock precision and UTC timestamps survive secondary acknowledgement',
    () async {
      final drive = MemoryDrive();
      final primary = await SyncFixture.create(drive, 'primary');
      await primary.sync();
      final app = await SyncFixture.create(drive, 'secondary');
      app.now = DateTime.utc(2026, 10, 27, 8, 30, 0, 123, 456);
      final thought = app.thoughts.saveThought(
        content: 'A thought captured now',
      );
      final payload = app.storage.pendingCreations.single.payload;
      expect(
        payload,
        app.thoughts.getThoughtByUuid(thought.uuid)!.toSyncJson('secondary'),
      );
      await app.sync();
      expect(app.storage.pendingCreations, isEmpty);
      expect(
        app.thoughts.getThoughtByUuid(thought.uuid)!.status,
        SyncStatus.synced,
      );
    },
  );

  test(
    'offline and rejected uploads retain thoughts until a successful retry',
    () async {
      final drive = MemoryDrive();
      final app = await SyncFixture.create(drive, 'primary');
      final thought = app.thoughts.saveThought(content: 'Saved offline');
      app.network.online = false;
      await app.engine.syncNow();
      expect(app.state.status, EngineSyncState.offline);
      expect(app.storage.pendingCreations, hasLength(1));
      expect(
        app.thoughts.getThoughtByUuid(thought.uuid)!.content,
        'Saved offline',
      );
      app.network.online = true;
      drive.failUploads = true;
      await app.engine.syncNow(manual: true);
      expect(app.state.status, EngineSyncState.error);
      expect(app.storage.pendingCreations, hasLength(1));
      drive.failUploads = false;
      await app.sync(manual: true);
      expect(
        drive.documents['thought/${thought.uuid}']!.payload['content'],
        'Saved offline',
      );
      expect(app.storage.pendingCreations, isEmpty);
      expect(
        app.thoughts.getThoughtByUuid(thought.uuid)!.status,
        SyncStatus.synced,
      );
    },
  );

  test(
    'a retry after a lost secondary acknowledgement creates no duplicate',
    () async {
      final drive = MemoryDrive();
      final primary = await SyncFixture.create(drive, 'primary');
      await primary.sync();
      final app = await SyncFixture.create(drive, 'secondary');
      final thought = app.thoughts.saveThought(content: 'Send exactly once');
      drive.beforeUpload = (type, id) async {
        if (type != 'thought') return;
        drive.beforeUpload = null;
        drive.seed(type, id, app.storage.pendingCreations.single.payload);
        throw StateError('Connection lost after cloud accepted the thought');
      };
      await app.engine.syncNow();
      expect(app.state.status, EngineSyncState.error);
      expect(app.storage.pendingCreations, hasLength(1));
      await app.sync(manual: true);
      await app.sync(manual: true);
      expect(drive.documents.keys, ['thought/${thought.uuid}']);
      expect(app.db.thoughtBox.count(), 1);
      expect(app.storage.pendingCreations, isEmpty);
      expect(
        app.thoughts.getThoughtByUuid(thought.uuid)!.status,
        SyncStatus.synced,
      );
    },
  );

  test(
    'a full refresh preserves a pending local thought over a cloud copy',
    () async {
      final drive = MemoryDrive();
      final app = await SyncFixture.create(drive, 'primary');
      final thought = app.thoughts.saveThought(content: 'Local content');
      drive.seed('thought', thought.uuid, {
        ...thought.toSyncJson('primary'),
        'content': 'Stale cloud content',
      });
      await app.sync(manual: true);
      expect(app.db.thoughtBox.count(), 1);
      expect(
        app.thoughts.getThoughtByUuid(thought.uuid)!.content,
        'Local content',
      );
      expect(
        drive.documents['thought/${thought.uuid}']!.payload['content'],
        'Local content',
      );
      await app.sync(manual: true);
      expect(app.db.thoughtBox.count(), 1);
    },
  );

  test(
    'malformed thought backups report errors while healthy thoughts restore',
    () async {
      final drive = MemoryDrive();
      final thought = ThoughtEntity(
        uuid: 'good',
        content: 'Keep this',
        createdAt: DateTime(2026, 10, 26),
      );
      drive.seed('thought', 'good', thought.toSyncJson('primary'));
      drive.seed('thought', 'bad', {
        ...thought.toSyncJson('primary'),
        'uuid': 'bad',
        'content': 42,
      });
      final app = await SyncFixture.create(drive, 'primary');
      await app.engine.syncNow();
      expect(app.state.status, EngineSyncState.error);
      expect(app.thoughts.getThoughtByUuid('good')!.content, 'Keep this');
      expect(app.thoughts.getThoughtByUuid('bad'), isNull);
      expect(drive.documents['thought/bad']!.payload['content'], 42);
    },
  );
}
