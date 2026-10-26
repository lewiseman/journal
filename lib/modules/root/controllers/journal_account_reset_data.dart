import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:journal/objectbox/objectbox.dart';
import 'package:objectbox/objectbox.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sync_wise/sync_wise.dart';

import 'journal_sync_store.dart';

/// Only app-owned copies select files for deletion, never synced path fields.
class JournalAccountResetData implements AccountResetLocalData {
  final ObjectBox db;
  final Future<Directory> Function() supportDirectory;
  final Future<void> Function() clearCachedImages;

  JournalAccountResetData({
    required this.db,
    Future<Directory> Function()? supportDirectory,
    Future<void> Function()? clearCachedImages,
  }) : supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
       clearCachedImages = clearCachedImages ?? _clearCachedImages;

  static Future<void> _clearCachedImages() =>
      CachedNetworkImageProvider.defaultCacheManager.emptyCache();

  @override
  Future<void> clear() async {
    final support = await supportDirectory();
    final mediaPath = p.join(support.path, 'note_backgrounds');
    final type = await FileSystemEntity.type(mediaPath, followLinks: false);
    if (type == FileSystemEntityType.link) {
      await Link(mediaPath).delete();
    } else if (type == FileSystemEntityType.directory) {
      await Directory(mediaPath).delete(recursive: true);
    }
    await clearCachedImages();
    db.store.runInTransaction(TxMode.write, () {
      db.noteBox.removeAll();
      db.diaryBox.removeAll();
      db.thoughtBox.removeAll();
      db.store.box<SyncRecordEntity>().removeAll();
    });
  }
}
