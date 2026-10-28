// Opt-in I01 device demonstration in two app processes. Every write goes to an
// isolated `<support>/i01-synthetic` folder (its own ObjectBox and
// diary_photos); the real journal database and photos are never opened.
//
//   flutter test integration_test/diary_photos_device_test.dart -d SERIAL \
//     --no-uninstall --dart-define=I01_PHASE=save
//   flutter test integration_test/diary_photos_device_test.dart -d SERIAL \
//     --no-uninstall --dart-define=I01_PHASE=reopen
//
// The system photo picker is replaced by bundled images: the picker UI itself
// is not exercised. Everything after the picker is the shipping code.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:integration_test/integration_test.dart';
import 'package:journal/modules/diary/controllers/diary_photo_stories.dart';
import 'package:journal/modules/diary/controllers/diary_photo_store.dart';
import 'package:journal/modules/diary/controllers/diary_providers.dart';
import 'package:journal/modules/diary/controllers/diary_repository.dart';
import 'package:journal/modules/diary/models/diary_item.dart';
import 'package:journal/modules/diary/views/pages/add_diary_photos_page.dart';
import 'package:journal/modules/diary/views/widgets/diary_photo_entry_book.dart';
import 'package:journal/modules/diary/views/widgets/diary_photo_widgets.dart';
import 'package:journal/modules/root/controllers/journal_account_reset_data.dart';
import 'package:journal/modules/root/controllers/journal_sync_store.dart';
import 'package:journal/objectbox/objectbox.dart';
import 'package:journal/objectbox/objectbox.g.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sync_wise/sync_wise.dart';

const _phase = String.fromEnvironment('I01_PHASE');
const _assets = ['diary.webp', 'cover.webp', 'birthdays.webp'];

class _Device implements DeviceIdentityService {
  @override
  String get deviceId => 'i01-synthetic-phone';
  @override
  String get deviceName => 'I01 synthetic phone';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('I01 photo story on a real device: $_phase', (tester) async {
    expect(_phase, anyOf('save', 'reopen'));
    final support = await getApplicationSupportDirectory();
    final root = Directory('${support.path}/i01-synthetic');
    if (_phase == 'save' && root.existsSync()) root.deleteSync(recursive: true);
    root.createSync(recursive: true);
    final db = ObjectBox.fromStore(
      await openStore(directory: '${root.path}/objectbox'),
    );
    final today = DateTime.now();
    final date = DateTime(today.year, today.month, today.day);
    final key = DiaryRepository.formatDateKey(date);
    final sync = SyncStateStore(
      storage: JournalSyncKeyValueStore(db.store),
      deviceId: _Device().deviceId,
    );
    final diary = DiaryRepository(db: db, device: _Device(), sync: sync);
    final store = DiaryPhotoStore(supportDirectory: () async => root);
    final evidence = <String, Object?>{
      'phase': _phase,
      'platform': Platform.operatingSystemVersion,
    };

    Future<void> mount({DiaryItem? story}) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            diaryPhotoStoriesProvider.overrideWithValue(
              DiaryPhotoStories(diary, store),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => AddDiaryPhotosPage(
                          date: date,
                          story: story,
                          imagePicker: () async => [
                            for (final name in _assets)
                              XFile.fromData(
                                (await rootBundle.load(
                                  'assets/images/onboarding/$name',
                                )).buffer.asUint8List(),
                                path: '/picker/$name',
                              ),
                          ],
                        ),
                      ),
                    ),
                    child: const Text('Open photos'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open photos'));
      await settle(tester);
    }

    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await settle(tester);
    }

    File file(String path) => File('${root.path}/$path');
    DiaryItem story() => diary.getDay(key)!.items.single;

    try {
      if (_phase == 'save') {
        await mount();
        expect(find.text('1 of 3 photos'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'Morning light.');
        FocusManager.instance.primaryFocus?.unfocus();
        await tap(find.text('Generate questions'));
        expect(
          find.byKey(const ValueKey('diary-photo-sample-note')),
          findsOneWidget,
        );
        await tester.enterText(
          find.byWidgetPredicate((w) => w is TextField && w.minLines == 3),
          'The kettle was already on.',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tap(find.text('Review'));
        expect(diary.getDay(key), isNull);
        await tap(find.text('Save to diary'));
        expect(find.byType(AddDiaryPhotosPage), findsNothing);
        final item = story();
        expect(item.photos, hasLength(3));
        for (final (index, photo) in item.photos.indexed) {
          final source = (await rootBundle.load(
            'assets/images/onboarding/${_assets[index]}',
          )).buffer.asUint8List();
          expect(file(photo.path).readAsBytesSync(), source);
        }
        evidence.addAll({
          'savedPhotos': item.photos.length,
          'paths': item.attachmentPaths,
          'bytesOnDisk': [
            for (final p in item.photos) file(p.path).lengthSync(),
          ],
          'captions': [for (final p in item.photos) p.caption],
          'answers': item.photos.first.reflections.length,
          'contentChars': item.content.length,
          'outbox': sync.pendingCreations.length,
        });
      } else {
        // A fresh process: nothing is cached from the save phase.
        final saved = story();
        expect(saved.photos.first.caption, 'Morning light.');
        final drafts = await DiaryPhotoStories(diary, store).open(saved);
        final decoded = <String>[];
        for (final draft in drafts) {
          final codec = await ui.instantiateImageCodec(draft.bytes);
          final frame = await codec.getNextFrame();
          decoded.add('${frame.image.width}x${frame.image.height}');
          frame.image.dispose();
          codec.dispose();
        }
        evidence['decodedAfterRestart'] = decoded;

        await mount(story: saved);
        expect(find.byType(DiaryPhotoEntryBook), findsOneWidget);
        expect(find.text('Morning light.'), findsOneWidget);
        expect(find.text('The kettle was already on.'), findsOneWidget);
        expect(find.byType(DiaryMissingPhoto), findsNothing);

        // Cancel an edit: nothing changes.
        await tap(find.text('Edit photos'));
        await tester.tap(find.byTooltip('Remove photo 1'));
        await settle(tester);
        await tester.binding.handlePopRoute();
        await settle(tester);
        await tap(find.byTooltip('Close without saving'));
        expect(jsonEncode(story().toJson()), jsonEncode(saved.toJson()));
        evidence['cancelUnchanged'] = true;

        // Edit: remove the first photo, save, and its copy is released.
        await mount(story: saved);
        await tap(find.text('Edit photos'));
        await tester.tap(find.byTooltip('Remove photo 1'));
        await settle(tester);
        await tap(find.text('Back to entry'));
        await tap(find.text('Save changes'));
        final edited = story();
        expect(
          edited.photos.map((p) => p.id),
          saved.photos.skip(1).map((p) => p.id),
        );
        expect(file(saved.photos.first.path).existsSync(), isFalse);
        evidence['afterEdit'] = {
          'photos': edited.photos.length,
          'removedCopyDeleted': !file(saved.photos.first.path).existsSync(),
        };

        // A copy that disappears is shown as missing, not as an error.
        file(edited.photos.last.path).deleteSync();
        await mount(story: edited);
        expect(find.byType(DiaryMissingPhoto), findsWidgets);
        expect(find.textContaining('kept only on the device'), findsOneWidget);
        evidence['missingShown'] = true;
        await tap(find.byTooltip('Close without saving'));

        await JournalAccountResetData(
          db: db,
          supportDirectory: () async => root,
          clearCachedImages: () async {},
        ).clear();
        expect(Directory('${root.path}/diary_photos').existsSync(), isFalse);
        expect(db.diaryBox.count(), 0);
        evidence['resetRemovedCopies'] = true;
      }
      expect(tester.takeException(), isNull);
    } finally {
      db.close();
      if (_phase == 'reopen' && root.existsSync()) {
        root.deleteSync(recursive: true);
      }
      // ignore: avoid_print
      print('I01_EVIDENCE ${jsonEncode(evidence)}');
    }
  });
}

/// Lets real file I/O and image decoding finish between frames.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pumpAndSettle();
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}
