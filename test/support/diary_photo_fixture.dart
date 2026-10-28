import 'dart:io';
import 'dart:typed_data';

import 'package:journal/modules/diary/controllers/diary_photo_store.dart';
import 'package:journal/modules/diary/controllers/diary_repository.dart';
import 'package:journal/modules/root/controllers/journal_sync_store.dart';
import 'package:journal/objectbox/objectbox.dart';
import 'package:journal/objectbox/objectbox.g.dart';
import 'package:sync_wise/sync_wise.dart';

import 'sync_fixture.dart' show TestDevice;

/// Keeps photo copies in memory so widget tests need no real file I/O.
class MemoryPhotoStore extends DiaryPhotoStore {
  final files = <String, Uint8List>{};
  bool failWrites = false;

  @override
  Future<File?> resolve(String path) async =>
      DiaryPhotoStore.isOwned(path) ? File('/memory/$path') : null;

  @override
  Future<Uint8List?> read(String path) async => files[path];

  @override
  Future<String> write(
    String id,
    Uint8List bytes, {
    String extension = '',
  }) async {
    if (failWrites) throw const FileSystemException('Disk full');
    final path = '${DiaryPhotoStore.folder}/$id.jpg';
    files[path] = bytes;
    return path;
  }

  @override
  Future<void> delete(Iterable<String> paths) async {
    for (final path in paths.toList()) {
      if (DiaryPhotoStore.isOwned(path)) files.remove(path);
    }
  }
}

/// An ObjectBox-backed diary on a temp directory; reopenable for restarts.
class DiaryFixture {
  DiaryFixture._(this.directory, this.today);

  final Directory directory;
  final DateTime today;
  late ObjectBox db;
  late SyncStateStore sync;
  late DiaryRepository diary;

  static DiaryFixture create(DateTime today) => DiaryFixture._(
    Directory.systemTemp.createTempSync('diary-photos-'),
    today,
  )..open();

  void open({String deviceId = 'phone'}) {
    db = ObjectBox.fromStore(
      Store(getObjectBoxModel(), directory: '${directory.path}/db'),
    );
    sync = SyncStateStore(
      storage: JournalSyncKeyValueStore(db.store),
      deviceId: deviceId,
      now: () => today,
    );
    diary = DiaryRepository(db: db, device: TestDevice(deviceId), sync: sync);
  }

  void restart() {
    db.close();
    open();
  }

  void makeSecondary() => sync.setPrimary(
    const PrimaryDevice(deviceId: 'other', deviceName: 'Other', fileId: 'role'),
  );

  void dispose() {
    db.close();
    directory.deleteSync(recursive: true);
  }
}
