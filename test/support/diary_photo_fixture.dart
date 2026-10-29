import 'dart:io';
import 'dart:typed_data';

import 'package:journal/modules/diary/controllers/diary_photo_store.dart';
import 'package:journal/modules/diary/controllers/diary_repository.dart';
import 'package:journal/modules/diary/photo_questions/diary_photo_question_contract.dart';
import 'package:journal/modules/diary/photo_questions/diary_photo_question_store.dart';
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

/// Photo question results and uploads in memory, for widget tests.
class MemoryPhotoQuestionStore extends DiaryPhotoQuestionStore {
  final results = <String, DiaryPhotoQuestions>{};
  final uploads = <String, Uint8List>{};

  @override
  Future<DiaryPhotoQuestions?> read(String photoSha, {DateTime? now}) async =>
      results[photoSha];

  @override
  Future<void> write(
    String photoSha,
    DiaryPhotoQuestions questions, {
    DateTime? now,
  }) async => results[photoSha] = questions;

  @override
  Future<void> remove(String photoSha) async => results.remove(photoSha);

  @override
  Future<void> writeUpload(String taskId, Uint8List png) async =>
      uploads[taskId] = png;

  @override
  Future<Uint8List?> readUpload(String taskId) async => uploads[taskId];

  @override
  Future<void> prune({String? active, DateTime? now}) async =>
      uploads.removeWhere((id, _) => id != active);
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
