import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/root/controllers/journal_account_reset_data.dart';
import 'package:sync_wise/sync_wise.dart';

import 'support/sync_fixture.dart';

Future<
  ({
    AccountResetController controller,
    AccountResetState Function() state,
    AccountResetStorage storage,
  })
>
resetFor(SyncFixture app, {AccountResetLocalData? localData}) async {
  final storage = AccountResetStorage(directory: () async => app.directory);
  final provider = NotifierProvider<AccountResetController, AccountResetState>(
    () => AccountResetController(
      (ref) => AccountResetConfig(
        storage: storage,
        engine: app.engine,
        backend: app.backend,
        network: app.network,
        localData:
            localData ??
            JournalAccountResetData(
              db: app.db,
              supportDirectory: () async =>
                  Directory('${app.directory.path}/support'),
              clearCachedImages: () async {},
            ),
      ),
    ),
    retry: (_, _) => null,
  );
  final container = ProviderContainer.test();
  final controller = container.read(provider.notifier);
  await controller.ready;
  return (
    controller: controller,
    state: () => container.read(provider),
    storage: storage,
  );
}

void main() {
  test('reset clears journal, cloud backups, roles and private copies while preserving originals and identity', () async {
    final drive = MemoryDrive();
    final app = await SyncFixture.create(drive, 'phone');
    final original = File('${app.directory.path}/original.pdf')
      ..writeAsStringSync('original');
    final identity = File('${app.directory.path}/device_identity.id')
      ..writeAsStringSync('phone');
    final private = Directory('${app.directory.path}/support/note_backgrounds')
      ..createSync(recursive: true);
    File('${private.path}/orphan.jpg').writeAsStringSync('app copy');
    final preference = File('${app.directory.path}/support/preferences')
      ..writeAsStringSync('keep settings');
    app.notes.saveNote(
      uuid: 'one',
      title: 'Keep until reset',
      content: 'text',
      attachmentPaths: [
        {'path': original.path, 'type': 'application/pdf'},
      ],
      background: {'image': identity.path, 'image_source': 'local'},
    );
    app.notes.saveNote(uuid: 'trash', title: 'Trash', content: 'deleted');
    app.notes.deleteNote('trash');
    app.diary.addTimelineItem(dateString: '2026-10-26', content: 'Diary');
    await app.sync();
    // This edit and its timer must not survive reset and upload later.
    app.notes.saveNote(
      uuid: 'pending',
      title: 'Pending',
      content: 'not uploaded',
    );
    await SyncAccountBinding(directory: () async => app.directory)
        .verify(backendId: 'memory', accountId: 'owner');
    var cacheClears = 0;
    final reset = await resetFor(
      app,
      localData: JournalAccountResetData(
        db: app.db,
        supportDirectory: () async =>
            Directory('${app.directory.path}/support'),
        clearCachedImages: () async {
          cacheClears++;
        },
      ),
    );
    await reset.controller.reset(expectedAccountId: 'owner');
    expect(reset.state().completed, isTrue, reason: reset.state().error);
    expect(app.db.noteBox.count(), 0);
    expect(app.db.diaryBox.count(), 0);
    expect(app.storage.pendingCreations, isEmpty);
    expect(app.storage.role, SyncDeviceRole.unknown);
    expect(drive.documents, isEmpty);
    expect(drive.primary, isNull);
    expect(drive.legacy, isEmpty);
    expect(app.backend.auth.currentUser, isNull);
    expect(
      File('${app.directory.path}/sync_account.json').existsSync(),
      isFalse,
    );
    expect(await reset.storage.canSync(), isTrue);
    expect(private.existsSync(), isFalse);
    expect(cacheClears, 1);
    expect(original.readAsStringSync(), 'original');
    expect(identity.readAsStringSync(), 'phone');
    expect(preference.readAsStringSync(), 'keep settings');
    app.backend.auth.user = const SyncAccount(
      id: 'new-owner',
      email: 'new@example.test',
    );
    app.notes.saveNote(uuid: 'fresh', title: 'New account', content: 'fresh');
    await app.sync(manual: true);
    expect(drive.documents.keys, ['note/fresh']);
    expect(app.storage.storage.read('owner'), 'memory/new-owner');
  });

  test('failed cloud deletion retains local data and resumes from a persisted reset', () async {
    final drive = MemoryDrive();
    final app = await SyncFixture.create(drive, 'phone');
    app.notes.saveNote(
      uuid: 'one',
      title: 'Keep',
      content: 'until cloud cleared',
    );
    await app.sync();
    drive.failDelete = true;
    final first = await resetFor(app);
    await first.controller.reset(expectedAccountId: 'owner');
    expect(first.state().blocksDataAccess, isTrue);
    expect(app.db.noteBox.count(), 1);
    expect((await first.storage.read())!.remoteDeleted, isFalse);
    final restarted = await resetFor(app);
    expect(restarted.state().blocksDataAccess, isTrue);
    drive.failDelete = false;
    await restarted.controller.reset();
    expect(restarted.state().completed, isTrue);
    expect(app.db.noteBox.count(), 0);
  });

  test(
    'local cleanup retries offline without repeating completed cloud deletion',
    () async {
      final drive = MemoryDrive();
      final app = await SyncFixture.create(drive, 'phone');
      app.diary.addTimelineItem(dateString: '2026-10-26', content: 'saved');
      await app.sync();
      var fail = true;
      final local = JournalAccountResetData(
        db: app.db,
        supportDirectory: () async =>
            Directory('${app.directory.path}/support'),
        clearCachedImages: () async {
          if (fail) throw StateError('cache unavailable');
        },
      );
      final first = await resetFor(app, localData: local);
      await first.controller.reset(expectedAccountId: 'owner');
      expect(first.state().pending, isTrue);
      expect((await first.storage.read())!.remoteDeleted, isTrue);
      expect(app.db.diaryBox.count(), 1);
      fail = false;
      app.network.online = false;
      final restarted = await resetFor(app, localData: local);
      await restarted.controller.reset();
      expect(restarted.state().completed, isTrue);
      expect(drive.deletions, 1);
      expect(app.db.diaryBox.count(), 0);
    },
  );

  test('wrong account and offline preflight cannot delete any data', () async {
    final drive = MemoryDrive();
    final app = await SyncFixture.create(drive, 'phone');
    app.notes.saveNote(uuid: 'one', title: 'Keep', content: 'text');
    final reset = await resetFor(app);
    await reset.controller.reset(expectedAccountId: 'wrong');
    expect(reset.state().blocksDataAccess, isFalse);
    expect(drive.deletions, 0);
    app.network.online = false;
    await reset.controller.reset(expectedAccountId: 'owner');
    expect(reset.state().blocksDataAccess, isFalse);
    expect(drive.deletions, 0);
    expect(app.db.noteBox.count(), 1);
    expect(await reset.storage.canSync(), isTrue);
  });

  test(
    'an app media symlink never selects external files for deletion',
    () async {
      final app = await SyncFixture.create(MemoryDrive(), 'phone');
      final outside = Directory('${app.directory.path}/originals')
        ..createSync();
      final photo = File('${outside.path}/photo.jpg')
        ..writeAsStringSync('original');
      final support = Directory('${app.directory.path}/support')..createSync();
      final link = Link('${support.path}/note_backgrounds')
        ..createSync(outside.path);
      await JournalAccountResetData(
        db: app.db,
        supportDirectory: () async => support,
        clearCachedImages: () async {},
      ).clear();
      expect(link.existsSync(), isFalse);
      expect(photo.readAsStringSync(), 'original');
    },
  );
}
