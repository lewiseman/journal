import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/notes/models/note_entity.dart';
import 'package:sync_wise/sync_wise.dart';

import 'support/sync_fixture.dart';

void main() {
  test(
    'first primary sync downloads all and uploads pending local notes',
    () async {
      final drive = MemoryDrive();
      drive.seed(
        'note',
        'remote',
        NoteEntity(uuid: 'remote', content: 'from cloud').toSyncJson('remote'),
      );
      final app = await SyncFixture.create(drive, 'primary');
      app.notes.saveNote(uuid: 'local', title: 'Local', content: 'saved first');
      await app.sync();
      expect(app.state.role, SyncDeviceRole.primary);
      expect(app.notes.getNoteByUuid('remote')!.content, 'from cloud');
      expect(drive.documents['note/local']!.payload['content'], 'saved first');
      expect(drive.listings, ['note', 'diary', 'thought']);
      expect(drive.migrationComplete, isTrue);
      expect(app.storage.pendingCreations, isEmpty);
      expect(app.backend.closed, app.backend.sessions);
    },
  );
  test('automatic primary sync uploads only; manual sync imports unrelated records', () async {
    final drive = MemoryDrive();
    final app = await SyncFixture.create(drive, 'primary');
    await app.sync();
    final lists = drive.listings.length;
    final reads = drive.reads;
    drive.seed(
      'note',
      'other',
      NoteEntity(uuid: 'other', content: 'unrelated').toSyncJson('secondary'),
    );
    app.notes.saveNote(uuid: 'mine', title: 'Mine', content: 'new');
    await app.sync();
    expect(drive.listings.length, lists);
    expect(drive.reads, reads);
    expect(app.notes.getNoteByUuid('other'), isNull);
    await app.sync(manual: true);
    expect(app.notes.getNoteByUuid('other')!.content, 'unrelated');
  });
  test('a secondary sends its new note without listing the journal', () async {
    final drive = MemoryDrive();
    final primary = await SyncFixture.create(drive, 'primary');
    await primary.sync();
    final secondary = await SyncFixture.create(drive, 'secondary');
    secondary.notes.saveNote(
      uuid: 'new',
      title: 'New',
      content: 'only creation',
    );
    final lists = drive.listings.length;
    await secondary.sync();
    expect(secondary.state.role, SyncDeviceRole.secondary);
    expect(drive.listings.length, lists);
    expect(drive.reads, 0);
    expect(drive.documents['note/new']!.payload['content'], 'only creation');
    expect(secondary.notes.getNoteByUuid('new')!.status, SyncStatus.synced);
    expect(
      () => secondary.notes.saveNote(
        uuid: 'new',
        title: 'edit',
        content: 'blocked',
      ),
      throwsStateError,
    );
    expect(() => secondary.notes.deleteNote('new'), throwsStateError);
  });
  test('secondary resolves an unknown role without publishing subsequent local edits', () async {
    final drive = MemoryDrive();
    final primary = await SyncFixture.create(drive, 'primary');
    await primary.sync();
    final secondary = await SyncFixture.create(drive, 'secondary');
    secondary.notes.saveNote(uuid: 'draft', title: 'First', content: 'initial');
    secondary.elapse(const Duration(seconds: 1));
    secondary.notes.saveNote(
      uuid: 'draft',
      title: 'Changed',
      content: 'local only',
    );
    await secondary.sync();
    expect(drive.documents['note/draft']!.payload['content'], 'initial');
    expect(secondary.notes.getNoteByUuid('draft')!.content, 'local only');
    expect(
      secondary.notes.getNoteByUuid('draft')!.status,
      SyncStatus.localOnly,
    );
  });
  test('primary pending edits win during full refresh without creating extra notes', () async {
    final drive = MemoryDrive();
    final app = await SyncFixture.create(drive, 'primary');
    app.notes.saveNote(uuid: 'same', title: 'Local', content: 'latest local');
    drive.seed(
      'note',
      'same',
      NoteEntity(uuid: 'same', content: 'older cloud').toSyncJson('primary'),
    );
    await app.sync(manual: true);
    expect(app.db.noteBox.count(), 1);
    expect(drive.documents['note/same']!.payload['content'], 'latest local');
  });
  test(
    'two-minute guard survives upload and expires at exactly two minutes',
    () async {
      final drive = MemoryDrive();
      final app = await SyncFixture.create(drive, 'primary');
      app.notes.saveNote(uuid: 'guard', title: 'Guard', content: 'local');
      await app.engine.syncNow();
      final changed = {
        ...drive.documents['note/guard']!.payload,
        'content': 'new cloud',
      };
      drive.seed('note', 'guard', changed);
      app.elapse(const Duration(seconds: 119));
      await app.engine.syncNow(manual: true);
      expect(app.notes.getNoteByUuid('guard')!.content, 'local');
      expect(app.state.status, EngineSyncState.pending);
      app.elapse(const Duration(seconds: 1));
      await app.engine.syncNow(manual: true);
      expect(app.notes.getNoteByUuid('guard')!.content, 'new cloud');
    },
  );
  test(
    'edit during a download is read again before applying cloud data',
    () async {
      final drive = MemoryDrive();
      final app = await SyncFixture.create(drive, 'primary');
      drive.seed(
        'note',
        'race',
        NoteEntity(uuid: 'race', content: 'remote').toSyncJson('primary'),
      );
      drive.beforeList = (type) async {
        if (type == 'note') {
          app.notes.saveNote(
            uuid: 'race',
            title: 'Typed',
            content: 'while downloading',
          );
        }
      };
      await app.sync();
      expect(app.notes.getNoteByUuid('race')!.content, 'while downloading');
      expect(
        drive.documents['note/race']!.payload['content'],
        'while downloading',
      );
    },
  );
  test(
    'edit during upload stays pending and is uploaded on a later request',
    () async {
      final drive = MemoryDrive();
      final app = await SyncFixture.create(drive, 'primary');
      app.notes.saveNote(uuid: 'race', title: 'First', content: 'first');
      var edited = false;
      drive.beforeUpload = (type, id) async {
        if (type == 'note' && !edited) {
          edited = true;
          app.notes.saveNote(uuid: 'race', title: 'Second', content: 'second');
        }
      };
      await app.sync();
      expect(app.notes.getNoteByUuid('race')!.status, SyncStatus.pendingUpload);
      expect(drive.documents['note/race']!.payload['content'], 'first');
      await app.sync();
      expect(drive.documents['note/race']!.payload['content'], 'second');
    },
  );
  test('offline attempts retain operations; a later sync sends them', () async {
    final drive = MemoryDrive();
    final app = await SyncFixture.create(drive, 'primary');
    app.notes.saveNote(uuid: 'offline', title: 'Offline', content: 'saved');
    app.network.online = false;
    await app.engine.syncNow();
    expect(app.state.status, EngineSyncState.offline);
    expect(app.storage.pendingCreations, hasLength(1));
    app.network.online = true;
    await app.sync(manual: true);
    expect(drive.documents.containsKey('note/offline'), isTrue);
  });
  test('failed initial listing retries a full sync', () async {
    final drive = MemoryDrive()..failDownloads = true;
    final app = await SyncFixture.create(drive, 'primary');
    await app.engine.syncNow();
    expect(app.state.status, EngineSyncState.error);
    drive.failDownloads = false;
    await app.sync();
    expect(drive.listings.where((type) => type == 'note').length, 2);
  });
  test(
    'a corrupt record blocks its upload but healthy records still sync',
    () async {
      final drive = MemoryDrive();
      final app = await SyncFixture.create(drive, 'primary');
      drive.seed('note', 'bad', NoteEntity(uuid: 'bad').toSyncJson('primary'));
      drive.unreadable.add('bad');
      app.notes.saveNote(uuid: 'bad', title: 'Keep', content: 'local');
      app.notes.saveNote(uuid: 'good', title: 'Good', content: 'healthy');
      await app.engine.syncNow();
      expect(app.state.status, EngineSyncState.error);
      expect(drive.documents['note/good']!.payload['content'], 'healthy');
      expect(drive.documents['note/bad']!.payload['content'], '');
    },
  );
  test('disposing a provider during a download prevents database writes and closes the session', () async {
    final drive = MemoryDrive();
    final app = await SyncFixture.create(drive, 'primary');
    final entered = Completer<void>(), release = Completer<void>();
    drive.beforeList = (type) async {
      if (type == 'note') {
        entered.complete();
        await release.future;
      }
    };
    final syncing = app.engine.syncNow();
    await entered.future;
    app.container.dispose();
    release.complete();
    await syncing;
    expect(app.db.noteBox.count(), 0);
    expect(app.backend.closed, 1);
  });
}
