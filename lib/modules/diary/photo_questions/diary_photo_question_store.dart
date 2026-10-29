import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'diary_photo_question_contract.dart';

final diaryPhotoQuestionStoreProvider = Provider<DiaryPhotoQuestionStore>(
  (ref) => DiaryPhotoQuestionStore(),
);

/// Local-only files for I02 under `<support>/diary_photo_questions`.
///
/// * `<photoSha>.json`: generated questions for one photo, so a result that
///   arrives after the page closed is still there when the photo is opened
///   again. Kept for [keep], never synced, removed by account reset.
/// * `uploads/<taskId>.png`: the exact re-encoded upload, so a retry after an
///   interrupted submission sends identical bytes even if the story was never
///   saved. Deleted when its task is cleared.
class DiaryPhotoQuestionStore {
  DiaryPhotoQuestionStore({Future<Directory> Function()? supportDirectory})
    : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  static const folder = 'diary_photo_questions';
  static const keep = Duration(days: 30);
  static final _sha = RegExp(r'^[a-f0-9]{64}$');
  static final _task = RegExp(r'^[a-zA-Z0-9_-]{8,80}$');

  final Future<Directory> Function() _supportDirectory;
  Future<Directory>? _support;

  Future<Directory> get _root async => Directory(
    p.join((await (_support ??= _supportDirectory())).path, folder),
  );

  Future<File> _result(String photoSha) async {
    if (!_sha.hasMatch(photoSha)) throw ArgumentError('photoSha');
    return File(p.join((await _root).path, '$photoSha.json'));
  }

  Future<File> _upload(String taskId) async {
    if (!_task.hasMatch(taskId)) throw ArgumentError('taskId');
    return File(p.join((await _root).path, 'uploads', '$taskId.png'));
  }

  Future<void> _write(File file, List<int> bytes) async {
    await file.parent.create(recursive: true);
    final partial = File('${file.path}.partial');
    await partial.writeAsBytes(bytes, flush: true);
    await partial.rename(file.path);
  }

  /// Cached questions for [photoSha], or null when none are current.
  Future<DiaryPhotoQuestions?> read(String photoSha, {DateTime? now}) async {
    final file = await _result(photoSha);
    try {
      final json = jsonDecode(await file.readAsString());
      final created = json is Map ? json['created'] : null;
      if (created is! int ||
          DateTime.fromMillisecondsSinceEpoch(created)
              .add(keep)
              .isBefore(now ?? DateTime.now())) {
        await _delete(file);
        return null;
      }
      return DiaryPhotoQuestions.parse(jsonEncode(json['questions']));
    } on FileSystemException {
      return null;
    } catch (_) {
      await _delete(file);
      return null;
    }
  }

  Future<void> write(
    String photoSha,
    DiaryPhotoQuestions questions, {
    DateTime? now,
  }) async => _write(
    await _result(photoSha),
    utf8.encode(
      jsonEncode({
        'created': (now ?? DateTime.now()).millisecondsSinceEpoch,
        'questions': questions.toJson(),
      }),
    ),
  );

  Future<void> remove(String photoSha) async =>
      _delete(await _result(photoSha));

  Future<void> writeUpload(String taskId, Uint8List png) async =>
      _write(await _upload(taskId), png);

  Future<Uint8List?> readUpload(String taskId) async {
    try {
      return await (await _upload(taskId)).readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  /// Removes uploads other than [active]'s and results past [keep].
  Future<void> prune({String? active, DateTime? now}) async {
    final root = await _root;
    final uploads = Directory(p.join(root.path, 'uploads'));
    try {
      await for (final entry in uploads.list(followLinks: false)) {
        if (entry is File && p.basename(entry.path) != '$active.png') {
          await _delete(entry);
        }
      }
    } on FileSystemException {
      // No uploads yet.
    }
    try {
      await for (final entry in root.list(followLinks: false)) {
        final name = p.basenameWithoutExtension(entry.path);
        if (entry is File && _sha.hasMatch(name)) await read(name, now: now);
      }
    } on FileSystemException {
      // No results yet.
    }
  }

  Future<void> _delete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Account reset removes the whole folder.
    }
  }
}
