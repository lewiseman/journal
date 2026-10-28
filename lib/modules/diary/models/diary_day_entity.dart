import 'dart:convert';

import 'package:journal/modules/diary/models/diary_item.dart';
import 'package:journal/utils/time_helper.dart';
import 'package:objectbox/objectbox.dart';
import 'package:sync_wise/sync_wise.dart';

@Entity()
class DiaryDayEntity {
  @Id()
  int id;

  @Index()
  @Unique()
  String dateString; // "YYYY-MM-DD" unique key per calendar day

  @Property(type: PropertyType.date)
  DateTime date; // Normalized date at midnight UTC

  /// JSON containing the mood emoji, name, and category.
  String? dayMood;
  String? daySummary;

  String? dayTitle;

  /// JSON list of up to three short, user-approved emotional themes.
  /// Kept separate so themes never overload the mood or reflection fields.
  String? dayThemes;

  String itemsJson;

  @Property(type: PropertyType.date)
  DateTime createdAt;

  @Property(type: PropertyType.date)
  DateTime updatedAt;

  bool isDeleted;

  @Property(type: PropertyType.date)
  DateTime? deletedAt;

  String lastEditedByDeviceId;
  int syncStatus;

  DiaryDayEntity({
    this.id = 0,
    required this.dateString,
    DateTime? date,
    this.dayMood,
    this.dayTitle,
    this.daySummary,
    this.dayThemes,
    this.itemsJson = '[]',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isDeleted = false,
    this.deletedAt,
    this.lastEditedByDeviceId = '',
    int? syncStatus,
  }) : date = date ?? _parseDateFromDateString(dateString),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       syncStatus = syncStatus ?? SyncStatus.pendingUpload.value;

  static DateTime _parseDateFromDateString(String dateString) {
    try {
      final parts = dateString.split('-');
      if (parts.length == 3) {
        return DateTime.utc(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
      }
    } catch (_) {}
    return DateTime.now().toUtc();
  }

  /// A diary key denotes a civil date, regardless of the stored UTC timestamp.
  @Transient()
  DateTime get calendarDate =>
      TimeHelper.dateOnly(TimeHelper.fromIso(dateString));

  /// Items with words. Text readers (search, AI questions, suggestions,
  /// summaries) use this, so a photo-only story is never sent as empty text.
  @Transient()
  Iterable<DiaryItem> get visibleItems => isDeleted
      ? const <DiaryItem>[]
      : items.where(
          (item) => !item.isDeleted && item.content.trim().isNotEmpty,
        );

  /// Everything shown on the diary page, including photo-only stories.
  @Transient()
  Iterable<DiaryItem> get displayItems => isDeleted
      ? const <DiaryItem>[]
      : items.where(
          (item) =>
              !item.isDeleted &&
              (item.content.trim().isNotEmpty || item.photos.isNotEmpty),
        );

  /// Parses items JSON into a list of DiaryItem objects
  @Transient()
  List<DiaryItem> get items {
    if (itemsJson.trim().isEmpty) return [];
    final decoded = jsonDecode(itemsJson);
    if (decoded is! List) {
      throw const FormatException('Invalid diary items.');
    }
    return decoded
        .map((item) => DiaryItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Serializes a list of DiaryItem objects into itemsJson
  set items(List<DiaryItem> list) {
    itemsJson = jsonEncode(list.map((e) => e.toJson()).toList());
  }

  /// Tolerant reader: malformed optional metadata never hides a day.
  @Transient()
  List<String> get themes {
    try {
      final decoded = jsonDecode(dayThemes ?? '[]');
      if (decoded is List) return decoded.whereType<String>().toList();
    } on FormatException {
      // Ignore malformed optional metadata.
    }
    return const [];
  }

  @Transient()
  SyncStatus get status => SyncStatus.fromValue(syncStatus);

  set status(SyncStatus s) {
    syncStatus = s.value;
  }

  /// Exports diary day record as a shared sync document
  Map<String, dynamic> toSyncJson(String deviceName) {
    return {
      'date_string': dateString,
      'date': date.toIso8601String(),
      'day_mood': dayMood,
      'day_title': dayTitle,
      'day_summary': daySummary,
      // Omitted when unset so existing shared documents stay byte-identical.
      if (dayThemes != null) 'day_themes': dayThemes,
      'items': items.map((e) => e.toJson()).toList(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_deleted': isDeleted,
      'deleted_at': deletedAt?.toIso8601String(),
      'device_id': lastEditedByDeviceId,
      'device_name': deviceName,
    };
  }

  /// Constructs a DiaryDayEntity from a shared sync document
  factory DiaryDayEntity.fromSyncJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? const [];
    final itemsList = rawItems
        .map((e) => DiaryItem.fromJson(e as Map<String, dynamic>))
        .toList();

    return DiaryDayEntity(
      dateString: json['date_string'] as String,
      date: DateTime.parse(json['date'] as String),
      dayMood: json['day_mood'] as String?,
      daySummary: json['day_summary'] as String?,
      dayTitle: json['day_title'] as String?,
      dayThemes: json['day_themes'] as String?,
      itemsJson: jsonEncode(itemsList.map((e) => e.toJson()).toList()),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      isDeleted: json['is_deleted'] as bool? ?? false,
      deletedAt: json['deleted_at'] != null
          ? DateTime.parse(json['deleted_at'] as String)
          : null,
      lastEditedByDeviceId: json['device_id'] as String? ?? '',
      syncStatus: SyncStatus.synced.value,
    );
  }
}
