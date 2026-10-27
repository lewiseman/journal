import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:journal/objectbox/objectbox.dart';

import 'package:sync_wise/sync_wise.dart';
import 'package:journal/modules/root/controllers/journal_sync_store.dart';

import 'package:journal/objectbox/objectbox.g.dart';

import '../models/diary_day_entity.dart';
import '../models/diary_item.dart';
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
    DateTime? timestamp,
  }) {
    if (!sync.canEdit && dateString != formatDateKey(sync.now())) {
      throw StateError('This device can only add diary items for today.');
    }
    if (content.trim().isEmpty && attachmentPaths.isEmpty) {
      throw ArgumentError('A diary item needs text or an attachment.');
    }
    final now = sync.now();

    final newItem = DiaryItem(
      itemUuid: const Uuid().v4(),
      createdAt: timestamp ?? now,
      content: content,
      mood: mood,
      attachmentPaths: attachmentPaths,
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
