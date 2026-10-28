import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:journal/objectbox/objectbox.dart';
import 'package:objectbox/objectbox.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sync_wise/sync_wise.dart';

import 'journal_sync_store.dart';

import 'package:journal/modules/notes/transform/note_recovery_entity.dart';

import 'package:journal/modules/notes/summary/summary_task_entity.dart';
import 'package:journal/modules/presentation/presentation_entity.dart';
import 'package:journal/modules/diary/questions/daily_question_entity.dart';
import 'package:journal/modules/diary/controllers/diary_photo_store.dart';
import 'package:journal/modules/flow/reflection/thought_reflection_entity.dart';

/// Only app-owned copies select files for deletion, never synced path fields.
class JournalAccountResetData implements AccountResetLocalData {
  final ObjectBox db;
  final Future<Directory> Function() supportDirectory;
  final Future<void> Function() clearCachedImages;
  final Future<void> Function() clearSummaries;
  final Future<void> Function() clearVoice;

  JournalAccountResetData({
    required this.db,
    Future<Directory> Function()? supportDirectory,
    Future<void> Function()? clearCachedImages,
    Future<void> Function()? clearSummaries,
    Future<void> Function()? clearVoice,
  }) : supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
       clearCachedImages = clearCachedImages ?? _clearCachedImages,
       clearSummaries = clearSummaries ?? _noSummaries,
       clearVoice = clearVoice ?? _noSummaries;

  static Future<void> _noSummaries() async {}

  static Future<void> _clearCachedImages() =>
      CachedNetworkImageProvider.defaultCacheManager.emptyCache();

  @override
  Future<void> clear() async {
    await clearSummaries();
    await clearVoice();
    final support = await supportDirectory();
    for (final folder in ['note_backgrounds', DiaryPhotoStore.folder]) {
      final mediaPath = p.join(support.path, folder);
      final type = await FileSystemEntity.type(mediaPath, followLinks: false);
      if (type == FileSystemEntityType.link) {
        await Link(mediaPath).delete();
      } else if (type == FileSystemEntityType.directory) {
        await Directory(mediaPath).delete(recursive: true);
      }
    }
    await clearCachedImages();
    db.store.runInTransaction(TxMode.write, () {
      db.noteBox.removeAll();
      db.diaryBox.removeAll();
      db.thoughtBox.removeAll();
      db.store.box<SummaryTaskEntity>().removeAll();
      db.store.box<NoteRecoveryEntity>().removeAll();
      db.store.box<PresentationEntity>().removeAll();
      db.store.box<DailyQuestionEntity>().removeAll();
      db.store.box<ThoughtReflectionEntity>().removeAll();
      db.store.box<SyncRecordEntity>().removeAll();
    });
  }
}
