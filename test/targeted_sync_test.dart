import 'package:flutter_test/flutter_test.dart';
import 'package:sync_wise/sync_wise.dart';

import 'support/sync_fixture.dart';

void main() {
  test('secondary fetches only the affected day and preserves reflection and prior items', () async {
    final drive = MemoryDrive();
    final primary = await SyncFixture.create(drive, 'primary');
    final date = diaryDate(primary);
    primary.diary.addTimelineItem(dateString: date, content: 'primary item');
    primary.diary.updateDayMetadata(
      dateString: date,
      daySummary: 'Keep summary',
      dayMood: 'Happy',
    );
    await primary.sync();
    final secondary = await SyncFixture.create(drive, 'secondary');
    await secondary.sync();
    final item = secondary.diary.addTimelineItem(
      dateString: date,
      content: 'secondary item',
    );
    final listings = drive.listings.length;
    await secondary.sync();
    expect(drive.listings.length, listings);
    expect(drive.reads, 1);
    final day = drive.documents['diary/$date']!.payload;
    expect(day['daySummary'], 'Keep summary');
    expect(day['dayMood'], 'Happy');
    expect((day['items'] as List).map((i) => i['content']), [
      'primary item',
      'secondary item',
    ]);
    expect(
      (day['items'] as List).where((i) => i['itemUuid'] == item.itemUuid),
      hasLength(1),
    );
    expect(secondary.storage.pendingCreations, isEmpty);
    expect(
      () => secondary.diary.updateDayMetadata(
        dateString: date,
        daySummary: 'blocked',
      ),
      throwsStateError,
    );
    expect(
      () => secondary.diary.deleteTimelineItem(
        dateString: date,
        itemUuid: item.itemUuid,
      ),
      throwsStateError,
    );
    expect(
      () => secondary.diary.addTimelineItem(
        dateString: '2026-10-25',
        content: 'yesterday',
      ),
      throwsStateError,
    );
  });
  test('stale automatic primary upload waits for full sync and preserves secondary additions', () async {
    final drive = MemoryDrive();
    final primary = await SyncFixture.create(drive, 'primary');
    final date = diaryDate(primary);
    final own = primary.diary.addTimelineItem(
      dateString: date,
      content: 'original',
    );
    await primary.sync();
    final secondary = await SyncFixture.create(drive, 'secondary');
    await secondary.sync();
    secondary.diary.addTimelineItem(dateString: date, content: 'new remote');
    await secondary.sync();
    primary.diary.updateTimelineItem(
      dateString: date,
      itemUuid: own.itemUuid,
      content: 'primary edit',
    );
    final reads = drive.reads, listings = drive.listings.length;
    await primary.sync();
    expect(primary.state.status, EngineSyncState.pending);
    expect(drive.reads, reads);
    expect(drive.listings.length, listings);
    expect(
      (drive.documents['diary/$date']!.payload['items'] as List).map(
        (i) => i['content'],
      ),
      contains('new remote'),
    );
    final uploads = drive.uploads;
    await primary.sync();
    expect(drive.uploads, uploads);
    await primary.sync(manual: true);
    expect(primary.diary.getDay(date)!.items.map((i) => i.content), [
      'primary edit',
      'new remote',
    ]);
    expect(
      (drive.documents['diary/$date']!.payload['items'] as List).map(
        (i) => i['content'],
      ),
      ['primary edit', 'new remote'],
    );
  });
  test('a racing secondary append is refetched and combined without duplicate items', () async {
    final drive = MemoryDrive();
    final primary = await SyncFixture.create(drive, 'primary');
    await primary.sync();
    final secondary = await SyncFixture.create(drive, 'secondary');
    await secondary.sync();
    final date = diaryDate(secondary);
    secondary.diary.addTimelineItem(dateString: date, content: 'mine');
    var raced = false;
    drive.beforeUpload = (type, id) async {
      if (type == 'diary' && !raced) {
        raced = true;
        final remote = secondary.diary.getDay(date)!.toSyncJson('other');
        remote['items'] = [
          {
            ...secondary.diary.getDay(date)!.items.single.toJson(),
            'itemUuid': 'another',
            'content': 'another device',
          },
        ];
        drive.seed(type, id, remote);
      }
    };
    await secondary.sync();
    final items = drive.documents['diary/$date']!.payload['items'] as List;
    expect(items, hasLength(2));
    expect(
      items.map((i) => i['content']),
      containsAll(['mine', 'another device']),
    );
    expect(drive.reads, 2);
  });
  test(
    'offline diary additions retain their creation date across midnight',
    () async {
      final drive = MemoryDrive();
      final primary = await SyncFixture.create(drive, 'primary');
      await primary.sync();
      final secondary = await SyncFixture.create(drive, 'secondary');
      await secondary.sync();
      final date = diaryDate(secondary);
      secondary.diary.addTimelineItem(
        dateString: date,
        content: 'queued yesterday',
      );
      secondary.elapse(const Duration(days: 1));
      await secondary.sync();
      expect(drive.documents['diary/$date'], isNotNull);
      expect(secondary.storage.pendingCreations, isEmpty);
    },
  );
  test(
    'a primary tombstone is not resurrected by a repeated diary addition',
    () async {
      final drive = MemoryDrive();
      final primary = await SyncFixture.create(drive, 'primary');
      await primary.sync();
      final secondary = await SyncFixture.create(drive, 'secondary');
      await secondary.sync();
      final date = diaryDate(secondary);
      final item = secondary.diary.addTimelineItem(
        dateString: date,
        content: 'to delete',
      );
      final operation = secondary.storage.pendingCreations.single;
      await secondary.sync();
      await primary.sync(manual: true);
      primary.diary.deleteTimelineItem(
        dateString: date,
        itemUuid: item.itemUuid,
      );
      await primary.sync();
      secondary.storage.enqueue(operation);
      await secondary.sync();
      expect(
        (drive.documents['diary/$date']!.payload['items'] as List)
            .single['isDeleted'],
        isTrue,
      );
    },
  );
}

String diaryDate(SyncFixture app) =>
    '${app.now.year}-${app.now.month.toString().padLeft(2, '0')}-${app.now.day.toString().padLeft(2, '0')}';
