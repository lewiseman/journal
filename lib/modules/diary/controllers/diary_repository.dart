import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:journal/objectbox/objectbox.dart';

import 'package:sync_wise/sync_wise.dart';
import 'package:journal/modules/root/controllers/journal_sync_store.dart';

import 'package:journal/objectbox/objectbox.g.dart';

import '../models/diary_day_entity.dart';
import '../models/diary_item.dart';
import '../models/diary_photo.dart';
import '../suggestions/diary_suggestion_contract.dart';

class DiaryRepository {
  final ObjectBox _db;
  final DeviceIdentityService _device;
  final SyncStateStore sync;
  final void Function()? onDataChanged;

  DiaryRepository({
    ObjectBox? db,
    DeviceIdentityService? device,
    this.onDataChanged,
    SyncStateStore? sync,
  }) : _db = db ?? objectbox,
       _device = device ?? DeviceIdentityService.instance,
       sync =
           sync ??
           SyncStateStore(
             storage: JournalSyncKeyValueStore((db ?? objectbox).store),
             deviceId: (device ?? DeviceIdentityService.instance).deviceId,
           );

  Box<DiaryDayEntity> get _box => _db.diaryBox;

  static String formatDateKey(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  List<DiaryDayEntity> getAllDays() =>
      _box.getAll().where((day) => !day.isDeleted).toList();

  /// Returns a reactive stream of all diary days, ordered by date descending.
  Stream<List<DiaryDayEntity>> watchAllDays() {
    return _box
        .query(DiaryDayEntity_.isDeleted.equals(false))
        .order(DiaryDayEntity_.date, flags: Order.descending)
        .watch(triggerImmediately: true)
        .map((q) => q.find());
  }

  /// Gets or creates a DiaryDayEntity for the specified date string (e.g. "2026-10-15").
  DiaryDayEntity getOrCreateDay(String dateString) {
    final query = _box
        .query(DiaryDayEntity_.dateString.equals(dateString))
        .build();
    var day = query.findFirst();
    query.close();

    if (day == null) {
      final now = sync.now();
      day = DiaryDayEntity(
        dateString: dateString,
        createdAt: now,
        updatedAt: now,
        lastEditedByDeviceId: _device.deviceId,
        isDeleted: false,
      );
      _box.put(day);
    }
    return day;
  }

  /// Gets diary day by dateString or null if not found.
  DiaryDayEntity? getDay(String dateString) {
    final query = _box
        .query(DiaryDayEntity_.dateString.equals(dateString))
        .build();
    final result = query.findFirst();
    query.close();
    return result;
  }

  /// Returns all diary days pending upload to Google Drive.
  List<DiaryDayEntity> getPendingUploadDays() {
    final query = _box
        .query(
          DiaryDayEntity_.syncStatus
              .notEquals(SyncStatus.synced.value)
              .and(
                DiaryDayEntity_.syncStatus.notEquals(
                  SyncStatus.localOnly.value,
                ),
              ),
        )
        .build();
    final result = query.find();
    query.close();
    return result;
  }

  /// Adds a new timeline item to a day's diary entry.
  DiaryItem addTimelineItem({
    required String dateString,
    required String content,
    String? mood,
    List<String> attachmentPaths = const [],
    List<DiaryPhoto> photos = const [],
    DateTime? timestamp,
    String? itemUuid,
  }) {
    if (photos.isNotEmpty) {
      attachmentPaths = [for (final photo in photos) photo.path];
    }
    if (!sync.canEdit && dateString != formatDateKey(sync.now())) {
      throw StateError('This device can only add diary items for today.');
    }
    if (content.trim().isEmpty && attachmentPaths.isEmpty) {
      throw ArgumentError('A diary item needs text or an attachment.');
    }
    if (itemUuid != null) {
      final previous = getDay(dateString)?.items
          .where((item) => item.itemUuid == itemUuid)
          .firstOrNull;
      if (previous != null) {
        if (previous.isDeleted || previous.content != content) {
          throw StateError(
            'This conversation was already saved. Review its existing diary item before changing it.',
          );
        }
        return previous;
      }
    }
    final now = sync.now();

    final newItem = DiaryItem(
      itemUuid: itemUuid ?? const Uuid().v4(),
      createdAt: timestamp ?? now,
      content: content,
      mood: mood,
      attachmentPaths: attachmentPaths,
      photos: photos,
      deviceId: _device.deviceId,
      updatedAt: now,
      isDeleted: false,
    );

    _db.store.runInTransaction(TxMode.write, () {
      final day = getOrCreateDay(dateString);
      day.items = [...day.items, newItem]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      day.updatedAt = now;
      day.lastEditedByDeviceId = _device.deviceId;
      day.status = SyncStatus.pendingUpload;
      _box.put(day);
      sync.edited('diary', dateString, newItem.itemUuid);
      if (dateString == formatDateKey(now)) {
        sync.enqueue(
          PendingCreation(
            id: newItem.itemUuid,
            type: 'diary',
            documentId: dateString,
            payload: {'date_string': dateString, 'item': newItem.toJson()},
          ),
        );
      }
    });
    onDataChanged?.call();
    return newItem;
  }

  /// Updates an existing timeline item.
  void updateTimelineItem({
    required String dateString,
    required String itemUuid,
    required String content,
    String? mood,
    List<String>? attachmentPaths,
  }) {
    if (!sync.canEdit) {
      throw StateError('Diary entries are read-only on this device.');
    }
    final day = getDay(dateString);
    if (day == null) return;

    final now = sync.now();
    final updatedList = day.items.map((item) {
      if (item.itemUuid == itemUuid) {
        return item.copyWith(
          content: content,
          mood: mood ?? item.mood,
          attachmentPaths: attachmentPaths ?? item.attachmentPaths,
          updatedAt: now,
          deviceId: _device.deviceId,
        );
      }
      return item;
    }).toList();

    day.items = updatedList;
    day.updatedAt = now;
    day.lastEditedByDeviceId = _device.deviceId;
    day.status = SyncStatus.pendingUpload;

    _db.store.runInTransaction(TxMode.write, () {
      _box.put(day);
      sync.edited('diary', dateString, itemUuid);
    });
    onDataChanged?.call();
  }

  /// Replaces a saved photo story's photos, order, captions and reviewed
  /// words. Returns the item as it was so the caller can release copies the
  /// story no longer uses. Text is recomposed from the photos.
  DiaryItem updatePhotoStory({
    required String dateString,
    required String itemUuid,
    required List<DiaryPhoto> photos,
  }) {
    if (photos.isEmpty) {
      throw ArgumentError('A photo story needs at least one photo.');
    }
    late DiaryItem previous;
    _db.store.runInTransaction(TxMode.write, () {
      if (!sync.canEdit) {
        throw StateError('Diary entries are read-only on this device.');
      }
      final day = getDay(dateString);
      final items = day?.items ?? const <DiaryItem>[];
      final index = items.indexWhere(
        (item) => item.itemUuid == itemUuid && !item.isDeleted,
      );
      if (day == null || index < 0) {
        throw StateError('This photo story is no longer in your diary.');
      }
      final now = sync.now();
      previous = items[index];
      items[index] = previous.copyWith(
        content: DiaryPhoto.composeContent(photos),
        photos: photos,
        attachmentPaths: [for (final photo in photos) photo.path],
        updatedAt: now,
        deviceId: _device.deviceId,
      );
      day.items = items;
      day.updatedAt = now;
      day.lastEditedByDeviceId = _device.deviceId;
      day.status = SyncStatus.pendingUpload;
      _box.put(day);
      sync.edited('diary', dateString, itemUuid);
    });
    onDataChanged?.call();
    return previous;
  }

  /// Whether any live diary item other than [exceptItem] still uses [path].
  bool isPhotoReferenced(String path, {String? exceptItem}) => getAllDays().any(
    (day) => day.items.any(
      (item) =>
          !item.isDeleted &&
          item.itemUuid != exceptItem &&
          item.attachmentPaths.contains(path),
    ),
  );

  /// Soft deletes a timeline item (tombstone).
  void deleteTimelineItem({
    required String dateString,
    required String itemUuid,
  }) {
    if (!sync.canEdit) {
      throw StateError('Diary entries are read-only on this device.');
    }
    final day = getDay(dateString);
    if (day == null) return;

    final now = sync.now();
    final updatedList = day.items.map((item) {
      if (item.itemUuid == itemUuid) {
        return item.copyWith(
          isDeleted: true,
          updatedAt: now,
          deviceId: _device.deviceId,
        );
      }
      return item;
    }).toList();

    day.items = updatedList;
    day.updatedAt = now;
    day.lastEditedByDeviceId = _device.deviceId;
    day.status = SyncStatus.pendingUpload;

    _db.store.runInTransaction(TxMode.write, () {
      _box.put(day);
      sync.edited('diary', dateString, itemUuid);
    });
    onDataChanged?.call();
  }

  /// Updates overall day reflection metadata. Null leaves a field unchanged;
  /// an empty string (or `[]` for themes) clears it.
  void updateDayMetadata({
    required String dateString,
    String? dayMood,
    String? daySummary,
    String? dayTitle,
    String? dayThemes,
    bool preserveLocalDraft = false,
  }) {
    if (!sync.canEdit && !preserveLocalDraft) {
      throw StateError('Day reflection is read-only on this device.');
    }
    _db.store.runInTransaction(TxMode.write, () {
      _writeMetadata(
        getOrCreateDay(dateString),
        dayMood: dayMood,
        daySummary: daySummary,
        dayTitle: dayTitle,
        dayThemes: dayThemes,
      );
    });
    onDataChanged?.call();
  }

  void _writeMetadata(
    DiaryDayEntity day, {
    String? dayMood,
    String? daySummary,
    String? dayTitle,
    String? dayThemes,
  }) {
    final now = sync.now();
    if (dayMood != null) day.dayMood = dayMood;
    if (dayTitle != null) day.dayTitle = dayTitle;
    if (daySummary != null) day.daySummary = daySummary;
    if (dayThemes != null) day.dayThemes = dayThemes;
    day.updatedAt = now;
    day.lastEditedByDeviceId = _device.deviceId;
    day.status = sync.canEdit ? SyncStatus.pendingUpload : SyncStatus.localOnly;
    _box.put(day);
    sync.edited('diary', day.dateString, 'metadata');
  }

  /// Saves explicitly accepted suggestion fields (J01). The role and the exact
  /// saved entries are rechecked in the same transaction as the write, so a
  /// stale result can never be applied after an edit, deletion or role change.
  /// Entry text is never modified. Null fields are left unchanged.
  void applyDaySuggestions({
    required String dateString,
    required String expectedSource,
    String? dayTitle,
    String? dayMood,
    String? dayThemes,
  }) {
    if (dayTitle == null && dayMood == null && dayThemes == null) {
      throw StateError('Choose at least one suggestion to save.');
    }
    _db.store.runInTransaction(TxMode.write, () {
      if (!sync.canEdit) {
        throw StateError(
          'Diary details can be saved only on the primary device.',
        );
      }
      final day = getDay(dateString);
      if (DiarySuggestionSource.fromDay(day)?.encode() != expectedSource) {
        throw StateError(
          'The day’s entries changed. Request new suggestions before saving.',
        );
      }
      _writeMetadata(
        day!,
        dayTitle: dayTitle,
        dayMood: dayMood,
        dayThemes: dayThemes,
      );
    });
    onDataChanged?.call();
  }
}
