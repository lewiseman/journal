import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/diary/models/diary_day_entity.dart';
import 'package:journal/modules/diary/models/diary_item.dart';
import 'package:journal/modules/notes/models/note_entity.dart';

import 'support/sync_fixture.dart';

void main() {
  test(
    'restore preserves current note artwork, pinning and attachment metadata',
    () async {
      final drive = MemoryDrive();
      final note = NoteEntity(
        uuid: 'styled',
        title: 'Saved note',
        content: 'Real content',
        tags: ['🌱#Life'],
        isPinned: true,
        background: {
          'type': 'sage',
          'image': '/local/art.jpg',
          'image_source': 'local',
        },
        attachments: [
          {'path': '/local/document.pdf', 'type': 'application/pdf'},
        ],
      );
      drive.seed('note', note.uuid, note.toSyncJson('phone'));
      final app = await SyncFixture.create(drive, 'primary');
      await app.sync();
      final restored = app.notes.getNoteByUuid(note.uuid)!;
      expect(restored.background, note.background);
      expect(restored.attachments, note.attachments);
      expect(restored.tags, note.tags);
      expect(restored.isPinned, isTrue);
    },
  );

  test(
    'legacy timestamp diary items restore with titles into ObjectBox',
    () async {
      final drive = MemoryDrive();
      final day = DiaryDayEntity(
        dateString: '2026-10-26',
        dayTitle: 'A real title',
      );
      final item = DiaryItem(
        itemUuid: 'legacy',
        createdAt: day.createdAt,
        updatedAt: day.updatedAt,
        content: 'From an older journal',
      );
      final legacy = item.toJson()..remove('created_at');
      drive.seed('diary', day.dateString, {
        ...day.toSyncJson('phone'),
        'items': [legacy],
      });
      final app = await SyncFixture.create(drive, 'primary');
      await app.sync();
      final restored = app.diary.getDay(day.dateString)!;
      expect(restored.dayTitle, 'A real title');
      expect(restored.items.single.createdAt, item.createdAt);
      expect(restored.items.single.content, item.content);
      expect(app.db.diaryBox.count(), 1);
    },
  );
}
