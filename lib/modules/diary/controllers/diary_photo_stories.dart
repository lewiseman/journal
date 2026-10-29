import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/diary_item.dart';
import '../models/diary_photo.dart';
import 'diary_photo_store.dart';
import 'diary_repository.dart';

/// A photo as it stands in the editor. [path] is set once it has a saved copy.
class DiaryPhotoDraft {
  DiaryPhotoDraft({
    String? id,
    this.path,
    required this.bytes,
    this.sha256 = '',
    this.sourceExtension = '',
  }) : id = id ?? const Uuid().v4();

  final String id;
  final String? path;

  /// Empty when a saved photo isn't on this device.
  final Uint8List bytes;
  final String sha256;
  final String sourceExtension;

  bool get missing => bytes.isEmpty;
}

/// Saves photo stories so the diary record and its private copies agree.
///
/// Copies are made only when the person saves, so closing the editor leaves
/// nothing behind. A failed write removes the copies it made; an edit
/// releases copies the story stopped using once the new record is committed.
class DiaryPhotoStories {
  DiaryPhotoStories(this.repository, this.store);

  final DiaryRepository repository;
  final DiaryPhotoStore store;

  Future<DiaryItem> save({
    required String dateString,
    required List<
      ({
        DiaryPhotoDraft draft,
        String caption,
        List<DiaryPhotoReflection> reflections,
        String seen,
      })
    >
    photos,
    String? existingItemUuid,
    String? newItemUuid,
  }) async {
    if (photos.isEmpty) {
      throw ArgumentError('A photo story needs at least one photo.');
    }
    if (existingItemUuid == null && !repository.sync.canEdit) {
      if (dateString != DiaryRepository.formatDateKey(repository.sync.now())) {
        throw StateError('This device can only add diary items for today.');
      }
    }
    final written = <String>[];
    try {
      final saved = <DiaryPhoto>[];
      for (final photo in photos) {
        var path = photo.draft.path;
        if (path == null) {
          path = await store.write(
            photo.draft.id,
            photo.draft.bytes,
            extension: photo.draft.sourceExtension,
          );
          written.add(path);
        }
        saved.add(
          DiaryPhoto(
            id: photo.draft.id,
            path: path,
            sha256: photo.draft.sha256,
            caption: photo.caption.trim(),
            reflections: [
              for (final reflection in photo.reflections)
                if (reflection.answer.trim().isNotEmpty)
                  DiaryPhotoReflection(
                    question: reflection.question,
                    answer: reflection.answer.trim(),
                    group: reflection.group,
                    fromPhoto: reflection.fromPhoto,
                  ),
            ],
            seen: photo.seen.trim(),
          ),
        );
      }
      if (existingItemUuid == null) {
        return repository.addTimelineItem(
          dateString: dateString,
          content: DiaryPhoto.composeContent(saved),
          photos: saved,
          itemUuid: newItemUuid,
        );
      }
      final previous = repository.updatePhotoStory(
        dateString: dateString,
        itemUuid: existingItemUuid,
        photos: saved,
      );
      final kept = {for (final photo in saved) photo.path};
      await store.delete(
        previous.attachmentPaths.where(
          (path) =>
              !kept.contains(path) &&
              DiaryPhotoStore.isOwned(path) &&
              !repository.isPhotoReferenced(path, exceptItem: existingItemUuid),
        ),
      );
      return repository
          .getDay(dateString)!
          .items
          .firstWhere((item) => item.itemUuid == existingItemUuid);
    } catch (_) {
      await store.delete(written);
      rethrow;
    }
  }

  /// Loads a saved story for reopening. Missing copies come back empty.
  Future<List<DiaryPhotoDraft>> open(DiaryItem item) async => [
    for (final photo in item.photos)
      DiaryPhotoDraft(
        id: photo.id,
        path: photo.path,
        bytes: await store.read(photo.path) ?? Uint8List(0),
        sha256: photo.sha256,
        sourceExtension: p.extension(photo.path),
      ),
  ];
}
