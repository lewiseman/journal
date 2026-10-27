import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/diary/history/diary_retrieval.dart';
import 'package:journal/modules/diary/models/diary_day_entity.dart';
import 'package:journal/modules/diary/models/diary_item.dart';

void main() {
  test('diaryTerms: shared normalization for S01 matching and J02 repetition', () {
    expect(diaryTerms("What's on your mind?"), {'mind'});
    expect(diaryTerms('noticed'), diaryTerms('notice'));
    expect(diaryTerms('Pottery classes'), diaryTerms('pottery class'));
    expect(diaryTerms('Clase de cerámica'), containsAll(['clas', 'cerámica']));
    expect(diaryTerms('陶芸教室に行った'), {'陶芸教室に行った'});
  });

  test('previousDays crosses month and year ends and lists newest first', () {
    final scope = DiaryDateScope.previousDays(DateTime(2027, 1, 2, 23, 30), 4);
    expect(scope.keysNewestFirst.toList(), [
      '2027-01-01',
      '2026-12-31',
      '2026-12-30',
      '2026-12-29',
    ]);
    expect(scope.contains(DateTime.utc(2027, 1, 2)), false);
  });

  test('diaryTextItems keeps sendable text entries, newest first', () {
    DiaryItem item(String id, String content, int minute) => DiaryItem(
      itemUuid: id,
      createdAt: DateTime.utc(2026, 1, 1, 8, minute),
      content: content,
      deviceId: 'phone',
      updatedAt: DateTime.utc(2026),
    );
    final day = DiaryDayEntity(
      dateString: '2026-01-01',
      date: DateTime.utc(2026),
      itemsJson: jsonEncode([
        item('a', 'Morning walk.', 1).toJson(),
        item('photo', '', 2).toJson(),
        item('bad', 'bell\u0007', 3).toJson(),
        item('b', 'Evening tea.\nThen bed.', 4).toJson(),
      ]),
    );
    expect(diaryTextItems(day).map((i) => i.itemUuid), ['b', 'a']);
    expect(diaryTextItems(null), isEmpty);
  });
}
