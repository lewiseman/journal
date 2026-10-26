import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/diary/controllers/diary_providers.dart';
import 'package:journal/modules/diary/controllers/diary_repository.dart';
import 'package:journal/modules/diary/views/pages/add_diary_text_page.dart';
import 'package:journal/modules/diary/views/pages/diary_page.dart';
import 'package:journal/modules/diary/views/widgets/diary_scene.dart';
import 'package:journal/modules/root/controllers/journal_sync_store.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/objectbox/objectbox.dart';
import 'package:journal/objectbox/objectbox.g.dart';
import 'package:sync_wise/sync_wise.dart';

import 'support/sync_fixture.dart' show TestDevice;

void main() {
  final today = DateTime(2026, 10, 26, 12);
  late Directory directory;
  late ObjectBox db;
  late DiaryRepository diary;
  late SyncStateStore storage;
  late int scheduled;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('diary-storage-');
    db = ObjectBox.fromStore(
      Store(getObjectBoxModel(), directory: directory.path),
    );
    storage = SyncStateStore(
      storage: JournalSyncKeyValueStore(db.store),
      deviceId: 'phone',
      now: () => today,
    );
    scheduled = 0;
    diary = DiaryRepository(
      db: db,
      device: TestDevice('phone'),
      sync: storage,
      onDataChanged: () => scheduled++,
    );
  });
  tearDown(() {
    db.close();
    directory.deleteSync(recursive: true);
  });

  Widget app(Widget home, {SyncDeviceRole role = SyncDeviceRole.primary}) =>
      ProviderScope(
        overrides: [
          diaryRepositoryProvider.overrideWithValue(diary),
          syncDeviceRoleProvider.overrideWithValue(role),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: home,
        ),
      );

  testWidgets(
    'Save persists text and its outbox before returning from the editor',
    (tester) async {
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AddDiaryTextPage(date: today),
                  ),
                ),
                child: const Text('Write'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Write'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('save-diary-text')))
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const ValueKey('diary-text-editor')),
        '  My actual diary.  ',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('save-diary-text')));
      await tester.pumpAndSettle();
      expect(find.byType(AddDiaryTextPage), findsNothing);
      expect(
        diary.getDay('2026-10-26')!.items.single.content,
        'My actual diary.',
      );
      expect(storage.pendingCreations.single.type, 'diary');
      expect(scheduled, 1);
    },
  );

  testWidgets(
    'a failed save keeps the draft and explains a secondary date restriction',
    (tester) async {
      storage.setPrimary(
        const PrimaryDevice(
          deviceId: 'other',
          deviceName: 'Other',
          fileId: 'role',
        ),
      );
      await tester.pumpWidget(
        app(
          AddDiaryTextPage(date: DateTime(2026, 10, 25)),
          role: SyncDeviceRole.secondary,
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('diary-text-editor')),
        'Keep this draft',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('save-diary-text')));
      await tester.pump();
      expect(
        find.text('This device can only add diary items for today.'),
        findsOneWidget,
      );
      expect(find.text('Keep this draft'), findsOneWidget);
      expect(db.diaryBox.count(), 0);
      expect(storage.pendingCreations, isEmpty);
    },
  );

  testWidgets(
    'default diary reader starts empty and reacts to persisted entries',
    (tester) async {
      await tester.pumpWidget(app(DiaryPage(clock: () => today)));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<DiaryScene>(find.byType(DiaryScene)).day.visibleItems,
        isEmpty,
      );
      diary.addTimelineItem(
        dateString: '2026-10-26',
        content: 'Written just now',
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DiaryScene>(find.byType(DiaryScene))
            .day
            .visibleItems
            .single
            .content,
        'Written just now',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
