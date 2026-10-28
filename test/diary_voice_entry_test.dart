import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/diary/controllers/diary_repository.dart';
import 'package:journal/modules/diary/models/diary_ai_conversation.dart';
import 'package:journal/modules/diary/models/diary_item.dart';
import 'package:journal/modules/root/controllers/journal_sync_store.dart';
import 'package:journal/modules/voice/controllers/diary_talk_sources.dart';
import 'package:journal/objectbox/objectbox.dart';
import 'package:journal/objectbox/objectbox.g.dart';
import 'package:sync_wise/sync_wise.dart';

import 'diary_conversation_test.dart' show MemoryVoiceStore;
import 'support/sync_fixture.dart' show TestDevice;

final today = DateTime(2026, 10, 28, 12);
final date = DiaryRepository.formatDateKey(today);

DiaryAiConversation talk(List<String> said) => DiaryAiConversation(
  createdAt: today,
  turns: [
    {'speaker': 'assistant', 'text': 'How was your day?'},
    for (final s in said) {'speaker': 'user', 'text': s},
  ],
);

void main() {
  late Directory directory;
  late ObjectBox db;
  late DiaryRepository diary;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('diary-voice-');
    db = ObjectBox.fromStore(
      Store(getObjectBoxModel(), directory: directory.path),
    );
    diary = DiaryRepository(
      db: db,
      device: TestDevice('phone'),
      sync: SyncStateStore(
        storage: JournalSyncKeyValueStore(db.store),
        deviceId: 'phone',
        now: () => today,
      ),
    );
  });
  tearDown(() {
    db.close();
    directory.deleteSync(recursive: true);
  });

  test('ai_conversation round-trips and is omitted for other items', () {
    final item = DiaryItem(
      itemUuid: 'a',
      createdAt: today,
      content: '',
      updatedAt: today,
      aiConversation: talk(['Calm.']),
    );
    final json = item.toJson();
    expect(json['ai_conversation']['turns'], hasLength(2));
    final back = DiaryItem.fromJson(json);
    expect(back.aiConversation!.turns.last, {
      'speaker': 'user',
      'text': 'Calm.',
    });
    expect(
      DiaryItem(
        itemUuid: 'b',
        createdAt: today,
        content: 'Words',
        updatedAt: today,
      ).toJson().containsKey('ai_conversation'),
      isFalse,
    );
  });

  test('a malformed conversation never hides the entry words', () {
    final item = DiaryItem.fromJson({
      'item_uuid': 'a',
      'created_at': today.toIso8601String(),
      'updated_at': today.toIso8601String(),
      'content': 'Kept',
      'ai_conversation': {'turns': 'nope'},
    });
    expect(item.content, 'Kept');
    expect(item.aiConversation, isNull);
  });

  test('saving a conversation creates an empty entry, then updates it', () {
    diary.saveAiConversation(
      dateString: date,
      itemUuid: 'talk',
      conversation: talk(['Calm.']),
    );
    var item = diary.getDay(date)!.items.single;
    expect(item.content, isEmpty);
    expect(item.aiConversation!.turns, hasLength(2));
    expect(diary.getDay(date)!.displayItems, hasLength(1));
    expect(diary.getDay(date)!.visibleItems, isEmpty);

    diary.saveAiConversation(
      dateString: date,
      itemUuid: 'talk',
      conversation: talk(['Calm.', 'Then rain.']),
      content: 'A calm day, then rain.',
    );
    item = diary.getDay(date)!.items.single;
    expect(item.content, 'A calm day, then rain.');
    expect(item.aiConversation!.turns, hasLength(3));
  });

  test('a leftover local talk moves into the diary and is cleared', () async {
    final store = MemoryVoiceStore()
      ..data = {
        'id': 'old',
        'date': date,
        'created': today.millisecondsSinceEpoch,
        'turns': talk(['Old words.']).turns,
        'draft': '',
        'saved': false,
      };
    await adoptLeftoverDiaryTalk(diary, store: store);
    expect(store.data, isNull);
    expect(
      diary.getDay(date)!.items.single.aiConversation!.turns.last['text'],
      'Old words.',
    );
  });
}
