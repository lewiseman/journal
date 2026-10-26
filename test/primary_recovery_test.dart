import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sync_wise/sync_wise.dart';

import 'support/sync_fixture.dart';

void main() {
  test('reinstalled primary restores notes and diaries without replacing cloud records', () async {
    final drive = MemoryDrive();
    final original = await SyncFixture.create(drive, 'original-install');
    original.notes.saveNote(
      uuid: 'note',
      title: 'Keep me',
      content: 'Saved before uninstall',
    );
    original.diary.addTimelineItem(
      dateString: '2026-10-26',
      content: 'Saved diary',
    );
    original.diary.updateDayMetadata(
      dateString: '2026-10-26',
      dayTitle: 'My day',
    );
    await original.sync();
    final before = canonicalJson({
      for (final entry in drive.documents.entries)
        entry.key: entry.value.toJson(),
    });
    final uploads = drive.uploads;
    final reinstalled = await SyncFixture.create(drive, 'new-install');
    await reinstalled.sync();
    expect(reinstalled.state.role, SyncDeviceRole.secondary);
    expect(reinstalled.db.noteBox.count(), 0);
    expect(reinstalled.db.diaryBox.count(), 0);

    await reinstalled.engine.reclaimPrimary();

    expect(
      reinstalled.state.status,
      EngineSyncState.idle,
      reason: reinstalled.state.lastError,
    );
    expect(reinstalled.state.role, SyncDeviceRole.primary);
    expect(reinstalled.storage.primary!.deviceId, 'new-install');
    expect(
      reinstalled.notes.getNoteByUuid('note')!.content,
      'Saved before uninstall',
    );
    expect(
      reinstalled.diary.getDay('2026-10-26')!.items.single.content,
      'Saved diary',
    );
    expect(reinstalled.diary.getDay('2026-10-26')!.dayTitle, 'My day');
    expect(
      canonicalJson({
        for (final entry in drive.documents.entries)
          entry.key: entry.value.toJson(),
      }),
      before,
    );
    expect(drive.uploads, uploads);
    expect(drive.deletions, 0);
    expect(drive.migrationComplete, isTrue);
    expect(reinstalled.backend.closed, reinstalled.backend.sessions);

    await original.sync(manual: true);
    expect(original.state.role, SyncDeviceRole.secondary);
    expect(() => original.notes.deleteNote('note'), throwsStateError);
    reinstalled.notes.saveNote(
      uuid: 'note',
      title: 'Keep me',
      content: 'Editable after recovery',
    );
  });

  test(
    'offline, signed-out and reset-suspended devices cannot reclaim',
    () async {
      final drive = MemoryDrive()
        ..primary = const PrimaryDevice(
          deviceId: 'old',
          deviceName: 'Old phone',
          fileId: 'registry',
        );
      final app = await SyncFixture.create(drive, 'new');
      await app.sync();
      app.network.online = false;
      await app.engine.reclaimPrimary();
      expect(app.state.status, EngineSyncState.offline);
      expect(app.state.role, SyncDeviceRole.secondary);
      expect(drive.reclaims, 0);
      app.network.online = true;
      await app.backend.auth.signOut();
      await app.engine.reclaimPrimary();
      expect(app.state.status, EngineSyncState.unauthenticated);
      expect(drive.reclaims, 0);
      await app.backend.auth.signIn();
      await app.engine.suspendForReset();
      await app.engine.reclaimPrimary();
      expect(drive.primary!.deviceId, 'old');
      expect(drive.reclaims, 0);
    },
  );

  test('failed transfer leaves role unchanged; failed restore can retry without another transfer', () async {
    final drive = MemoryDrive();
    final old = await SyncFixture.create(drive, 'old');
    old.diary.addTimelineItem(dateString: '2026-10-26', content: 'Cloud diary');
    await old.sync();
    final app = await SyncFixture.create(drive, 'new');
    await app.sync();
    drive.failReclaim = true;
    await app.engine.reclaimPrimary();
    expect(app.state.status, EngineSyncState.error);
    expect(app.state.role, SyncDeviceRole.secondary);
    expect(drive.primary!.deviceId, 'old');
    drive.failReclaim = false;
    drive.failDownloads = true;
    await app.engine.reclaimPrimary();
    expect(app.state.role, SyncDeviceRole.primary);
    expect(app.state.status, EngineSyncState.error);
    final reclaims = drive.reclaims;
    drive.failDownloads = false;
    await app.sync(manual: true);
    expect(app.diary.getDay('2026-10-26')!.items.single.content, 'Cloud diary');
    expect(drive.reclaims, reclaims);
  });

  test('a concurrent primary claim is surfaced and not overwritten', () async {
    final drive = MemoryDrive()
      ..primary = const PrimaryDevice(
        deviceId: 'old',
        deviceName: 'Old phone',
        fileId: 'registry',
      );
    final app = await SyncFixture.create(drive, 'new');
    await app.sync();
    drive.beforeReclaim = () async {
      drive.primary = const PrimaryDevice(
        deviceId: 'other',
        deviceName: 'Other phone',
        fileId: 'registry',
      );
    };
    await app.engine.reclaimPrimary();
    expect(app.state.status, EngineSyncState.error);
    expect(app.state.lastError, contains('primary device changed'));
    expect(app.state.primary!.deviceId, 'other');
    expect(drive.primary!.deviceId, 'other');
    expect(drive.listings, isEmpty);
  });

  test(
    'recovery waits for an active sync before opening its session',
    () async {
      final drive = MemoryDrive()
        ..primary = const PrimaryDevice(
          deviceId: 'old',
          deviceName: 'Old phone',
          fileId: 'registry',
        );
      final app = await SyncFixture.create(drive, 'new');
      app.notes.saveNote(
        uuid: 'queued',
        title: 'Queued',
        content: 'Save first',
      );
      final entered = Completer<void>(), release = Completer<void>();
      drive.beforeUpload = (type, id) async {
        entered.complete();
        await release.future;
      };
      final syncing = app.engine.syncNow();
      await entered.future;
      final recovering = app.engine.reclaimPrimary();
      expect(drive.reclaims, 0);
      expect(app.backend.sessions, 1);
      release.complete();
      await syncing;
      await recovering;
      expect(
        app.state.status,
        EngineSyncState.idle,
        reason: app.state.lastError,
      );
      expect(app.state.role, SyncDeviceRole.primary);
      expect(app.backend.sessions, 2);
      expect(app.backend.closed, 2);
      expect(drive.documents['note/queued']!.payload['content'], 'Save first');
    },
  );
}
