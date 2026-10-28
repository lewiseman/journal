import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/diary/controllers/diary_photo_stories.dart';
import 'package:journal/modules/diary/controllers/diary_photo_store.dart';
import 'package:journal/modules/diary/models/diary_calendar_day.dart';
import 'package:journal/modules/diary/models/diary_day_entity.dart';
import 'package:journal/modules/diary/models/diary_item.dart';
import 'package:journal/modules/diary/models/diary_photo.dart';
import 'package:journal/modules/diary/views/widgets/diary_sheet.dart';
import 'package:journal/modules/root/controllers/journal_account_reset_data.dart';

import 'support/diary_photo_fixture.dart';

typedef _Photo = ({
  DiaryPhotoDraft draft,
  String caption,
  List<DiaryPhotoReflection> reflections,
});

_Photo _photo(int seed, {String caption = '', String answer = ''}) => (
  draft: DiaryPhotoDraft(
    bytes: Uint8List.fromList([seed, seed + 1, seed + 2]),
    sha256: 'sha-$seed',
    sourceExtension: '.JPG',
  ),
  caption: caption,
  reflections: [
    if (answer.isNotEmpty)
      DiaryPhotoReflection(question: 'Sample?', answer: answer),
  ],
);

_Photo _kept(DiaryPhoto photo, {String? caption}) => (
  draft: DiaryPhotoDraft(id: photo.id, path: photo.path, bytes: Uint8List(1)),
  caption: caption ?? photo.caption,
  reflections: photo.reflections,
);

void main() {
  late DiaryFixture app;
  late Directory support;
  late DiaryPhotoStore store;
  late DiaryPhotoStories stories;
  const date = '2026-10-27';

  setUp(() {
    app = DiaryFixture.create(DateTime(2026, 10, 27, 12));
    support = Directory('${app.directory.path}/support');
    store = DiaryPhotoStore(supportDirectory: () async => support);
    stories = DiaryPhotoStories(app.diary, store);
  });
  tearDown(() => app.dispose());

  File copy(String path) => File('${support.path}/$path');

  test('only well-formed app-owned paths resolve or delete', () async {
    for (final path in ['diary_photos/a.jpg', 'diary_photos/1f0c-uuid.webp']) {
      expect(DiaryPhotoStore.isOwned(path), isTrue, reason: path);
    }
    for (final path in [
      '/diary_photos/a.jpg',
      'diary_photos/../a.jpg',
      'diary_photos/..',
      'diary_photos/.hidden',
      'diary_photos/x/a.jpg',
      'note_backgrounds/a.jpg',
      r'diary_photos\..\a.jpg',
      '/private/var/mobile/picker/IMG_1.jpg',
    ]) {
      expect(DiaryPhotoStore.isOwned(path), isFalse, reason: path);
      expect(await store.resolve(path), isNull);
    }
    final original = File('${support.path}/original.jpg')
      ..createSync(recursive: true)
      ..writeAsStringSync('source');
    await store.delete(['diary_photos/../original.jpg', original.path]);
    expect(original.existsSync(), isTrue);
  });

  test('save keeps private copies, order and words across a restart', () async {
    final saved = await stories.save(
      dateString: date,
      newItemUuid: 'story',
      photos: [
        _photo(1, caption: ' The bus ', answer: 'Late again.'),
        _photo(2),
        _photo(3, caption: 'Home.'),
      ],
    );
    expect(saved.photos.map((p) => p.path), [
      for (final p in saved.photos) 'diary_photos/${p.id}.jpg',
    ]);
    expect(saved.attachmentPaths, saved.photos.map((p) => p.path));
    expect(saved.content, 'The bus\n\nLate again.\n\nHome.');
    expect(copy(saved.photos[1].path).readAsBytesSync(), [2, 3, 4]);
    expect(
      support
          .listSync(recursive: true)
          .where((f) => f.path.endsWith('.partial')),
      isEmpty,
    );

    app.restart();
    final item = app.diary.getDay(date)!.items.single;
    expect(item.photos.map((p) => p.caption), ['The bus', '', 'Home.']);
    expect(item.photos.first.reflections.single.answer, 'Late again.');
    expect(item.photos.map((p) => p.sha256), ['sha-1', 'sha-2', 'sha-3']);
    final drafts = await DiaryPhotoStories(app.diary, store).open(item);
    expect(drafts.map((d) => d.bytes.first), [1, 2, 3]);
    expect(drafts.every((d) => !d.missing), isTrue);
  });

  test('an edit releases removed copies after the record commits', () async {
    final first = await stories.save(
      dateString: date,
      photos: [_photo(1), _photo(2)],
    );
    final removed = first.photos.first;
    final edited = await stories.save(
      dateString: date,
      existingItemUuid: first.itemUuid,
      photos: [
        _kept(first.photos.last, caption: 'Only one.'),
        _photo(4),
      ],
    );
    expect(edited.photos.first.id, first.photos.last.id);
    expect(edited.photos.first.caption, 'Only one.');
    expect(edited.content, 'Only one.');
    expect(copy(removed.path).existsSync(), isFalse);
    expect(copy(edited.photos.first.path).existsSync(), isTrue);
    expect(copy(edited.photos.last.path).existsSync(), isTrue);
    expect(app.diary.getDay(date)!.items, hasLength(1));
  });

  test('a refused save removes the copies it made', () async {
    await expectLater(
      stories.save(
        dateString: date,
        existingItemUuid: 'gone',
        photos: [_photo(1), _photo(2)],
      ),
      throwsStateError,
    );
    expect(Directory('${support.path}/diary_photos').listSync(), isEmpty);
    expect(app.db.diaryBox.count(), 0);
  });

  test(
    'a secondary device adds today but cannot edit or add past days',
    () async {
      app.makeSecondary();
      final today = await stories.save(dateString: date, photos: [_photo(1)]);
      expect(app.sync.pendingCreations.single.payload['item'], today.toJson());
      await expectLater(
        stories.save(dateString: '2026-10-26', photos: [_photo(2)]),
        throwsStateError,
      );
      await expectLater(
        stories.save(
          dateString: date,
          existingItemUuid: today.itemUuid,
          photos: [_kept(today.photos.single, caption: 'Changed')],
        ),
        throwsStateError,
      );
      expect(
        app.diary.getDay(date)!.items.single.photos.single.caption,
        isEmpty,
      );
      expect(
        Directory('${support.path}/diary_photos').listSync(),
        hasLength(1),
      );
    },
  );

  test(
    'sync carries photo records, not bytes, and text items stay unchanged',
    () {
      final text = DiaryItem(
        itemUuid: 'text',
        createdAt: DateTime.utc(2026, 10, 27, 8),
        updatedAt: DateTime.utc(2026, 10, 27, 8),
        content: 'Words only.',
      );
      expect(text.toJson().containsKey('photos'), isFalse);
      final story = text.copyWith(
        itemUuid: 'story',
        content: '',
        attachmentPaths: ['diary_photos/a.jpg'],
        photos: const [
          DiaryPhoto(
            id: 'a',
            path: 'diary_photos/a.jpg',
            sha256: 'abc',
            caption: 'Hi',
            reflections: [DiaryPhotoReflection(question: 'Q', answer: 'A')],
          ),
        ],
      );
      final day = DiaryDayEntity(dateString: date)..items = [text, story];
      final wire = jsonDecode(jsonEncode(day.toSyncJson('Phone')));
      final remote = DiaryDayEntity.fromSyncJson(wire as Map<String, dynamic>);
      expect(
        remote.items.map((i) => i.toJson()),
        day.items.map((i) => i.toJson()),
      );
      expect(jsonEncode(wire), isNot(contains('base64')));

      final json = story.toJson()
        ..['photos'] = [
          {'path': 'no id'},
          story.photos.single.toJson(),
        ];
      expect(DiaryItem.fromJson(json).photos.single.id, 'a');
    },
  );

  testWidgets(
    'photo-only stories show on the page and calendar, not to text readers',
    (tester) async {
      final story = DiaryItem(
        itemUuid: 'story',
        createdAt: DateTime.utc(2026, 10, 27, 8),
        updatedAt: DateTime.utc(2026, 10, 27, 8),
        content: '',
        attachmentPaths: const ['diary_photos/a.jpg'],
        photos: const [DiaryPhoto(id: 'a', path: 'diary_photos/a.jpg')],
      );
      final day = DiaryDayEntity(dateString: date)..items = [story];
      expect(day.visibleItems, isEmpty);
      expect(day.displayItems.single.itemUuid, 'story');
      expect(DiaryCalendarDay.fromEntity(day).hasEntry, isTrue);

      DiaryPhotoStore.instance = MemoryPhotoStore();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DiaryAccess(
                canEdit: true,
                today: DateTime(2026, 10, 27),
                child: DiaryDayContent(day: day),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('diary-photo-story-story')),
        findsOneWidget,
      );
      expect(find.text('A day, held here.'), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('diary-image-count')))
            .data,
        '1',
      );
      expect(find.text('Day details'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test('account reset deletes diary photo copies and leaves sources', () async {
    final saved = await stories.save(dateString: date, photos: [_photo(1)]);
    final source = File('${app.directory.path}/DCIM/IMG_1.jpg')
      ..createSync(recursive: true)
      ..writeAsStringSync('camera roll');
    await JournalAccountResetData(
      db: app.db,
      supportDirectory: () async => support,
      clearCachedImages: () async {},
    ).clear();
    expect(copy(saved.photos.single.path).existsSync(), isFalse);
    expect(Directory('${support.path}/diary_photos').existsSync(), isFalse);
    expect(source.existsSync(), isTrue);
    expect(app.db.diaryBox.count(), 0);
  });
}
