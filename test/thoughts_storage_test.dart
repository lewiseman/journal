import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/flow/controllers/thoughts_repository.dart';
import 'package:journal/modules/root/controllers/journal_sync_store.dart';
import 'package:sync_wise/sync_wise.dart';

import 'support/sync_fixture.dart';

class _FailingOutboxStore extends JournalSyncKeyValueStore {
  _FailingOutboxStore(super.store);

  @override
  void write(String key, String value) {
    if (key.startsWith('operation/')) throw StateError('Outbox write failed');
    super.write(key, value);
  }
}

void main() {
  test('saving commits text and backup before notifying listeners', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    var notifications = 0;
    final repository = ThoughtsRepository(
      db: app.db,
      device: app.device,
      sync: app.storage,
      onDataChanged: () {
        notifications++;
        expect(app.db.thoughtBox.count(), 1);
        expect(app.storage.pendingCreations, hasLength(1));
      },
    );
    final thought = repository.saveThought(
      content: '  First line\nSecond line  ',
    );
    expect(thought.uuid, isNotEmpty);
    expect(thought.id, greaterThan(0));
    expect(thought.summary, '');
    expect(thought.content, 'First line\nSecond line');
    expect(thought.createdAt, app.now);
    expect(thought.updatedAt, app.now);
    expect(thought.lastEditedByDeviceId, 'phone');
    expect(thought.status, SyncStatus.pendingUpload);
    final operation = app.storage.pendingCreations.single;
    expect(operation.type, 'thought');
    expect(operation.id, thought.uuid);
    expect(operation.documentId, thought.uuid);
    expect(operation.payload, thought.toSyncJson('phone'));
    expect(app.storage.dirty('thought', thought.uuid), isTrue);
    expect(notifications, 1);
  });

  test('blank input creates neither a record nor an operation', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    for (final text in ['', '  \n\t ']) {
      expect(
        () => app.thoughts.saveThought(content: text),
        throwsArgumentError,
      );
    }
    expect(app.db.thoughtBox.count(), 0);
    expect(app.storage.pendingCreations, isEmpty);
  });

  test(
    'a failed outbox write rolls back the thought and edit metadata',
    () async {
      final app = await SyncFixture.create(MemoryDrive(), 'phone');
      var notified = false;
      final repository = ThoughtsRepository(
        db: app.db,
        device: app.device,
        sync: SyncStateStore(
          storage: _FailingOutboxStore(app.db.store),
          deviceId: 'phone',
        ),
        onDataChanged: () => notified = true,
      );
      expect(
        () => repository.saveThought(content: 'Keep my draft'),
        throwsStateError,
      );
      expect(app.db.thoughtBox.count(), 0);
      expect(app.storage.pendingCreations, isEmpty);
      expect(app.storage.storage.keys('edit/thought/'), isEmpty);
      expect(notified, isFalse);
    },
  );

  test(
    'watching starts empty and orders saved thoughts newest first',
    () async {
      final app = await SyncFixture.create(MemoryDrive(), 'phone');
      expect(await app.thoughts.watchThoughts().first, isEmpty);
      final first = app.thoughts.saveThought(content: 'Older');
      app.elapse(const Duration(seconds: 1));
      final second = app.thoughts.saveThought(content: 'Newer');
      final thoughts = await app.thoughts.watchThoughts().first;
      expect(thoughts.map((thought) => thought.uuid), [
        second.uuid,
        first.uuid,
      ]);
      expect(app.thoughts.getThoughtByUuid(first.uuid)!.content, 'Older');
      expect(app.thoughts.getThoughtByUuid('missing'), isNull);
    },
  );
}
