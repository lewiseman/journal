import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/diary/models/diary_day_entity.dart';
import 'package:journal/modules/diary/models/diary_item.dart';

import 'support/sync_fixture.dart';

void main() {
  test(
    'new items import while locally edited item and day metadata are preserved',
    () async {
      final drive = MemoryDrive();
      final app = await SyncFixture.create(drive, 'primary');
      final item = app.diary.addTimelineItem(
        dateString: '2026-10-26',
        content: 'original',
      );
      await app.sync();
      app.diary.updateTimelineItem(
        dateString: '2026-10-26',
        itemUuid: item.itemUuid,
        content: 'local edit',
      );
      app.diary.updateDayMetadata(
        dateString: '2026-10-26',
        daySummary: 'local reflection',
        dayTitle: 'My title',
      );
      final remote = DiaryDayEntity.fromSyncJson(
        drive.documents['diary/2026-10-26']!.payload,
      );
      remote.daySummary = 'remote reflection';
      remote.dayTitle = 'Older title';
      remote.items = [
        item.copyWith(content: 'older remote'),
        DiaryItem(
          itemUuid: 'unseen',
          createdAt: app.now,
          updatedAt: app.now,
          content: 'new remote',
        ),
      ];
      drive.seed('diary', '2026-10-26', remote.toSyncJson('secondary'));
      await app.sync(manual: true);
      final actual = app.diary.getDay('2026-10-26')!;
      expect(actual.daySummary, 'local reflection');
      expect(actual.dayTitle, 'My title');
      expect(actual.items.map((i) => i.content), ['local edit', 'new remote']);
    },
  );
}
