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

  @Transient()
  Iterable<DiaryItem> get visibleItems => isDeleted
      ? const <DiaryItem>[]
      : items.where(
          (item) => !item.isDeleted && item.content.trim().isNotEmpty,
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

  @Transient()
  SyncStatus get status => SyncStatus.fromValue(syncStatus);

  set status(SyncStatus s) {
    syncStatus = s.value;
  }

  /// Exports diary day record as a shared sync document
  Map<String, dynamic> toSyncJson(String deviceName) {
    return {
      'dateString': dateString,
      'date': date.toIso8601String(),
      'dayMood': dayMood,
      'dayTitle': dayTitle,
      'daySummary': daySummary,
      'items': items.map((e) => e.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isDeleted': isDeleted,
      'deletedAt': deletedAt?.toIso8601String(),
      'deviceId': lastEditedByDeviceId,
      'deviceName': deviceName,
    };
  }

  /// Constructs a DiaryDayEntity from a shared sync document
  factory DiaryDayEntity.fromSyncJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? const [];
    final itemsList = rawItems
        .map((e) => DiaryItem.fromJson(e as Map<String, dynamic>))
        .toList();

    return DiaryDayEntity(
      dateString: json['dateString'] as String,
      date: DateTime.parse(json['date'] as String),
      dayMood: json['dayMood'] as String?,
      daySummary: json['daySummary'] as String?,
      dayTitle: json['dayTitle'] as String?,
      itemsJson: jsonEncode(itemsList.map((e) => e.toJson()).toList()),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      isDeleted: json['isDeleted'] as bool? ?? false,
      deletedAt: json['deletedAt'] != null
          ? DateTime.parse(json['deletedAt'] as String)
          : null,
      lastEditedByDeviceId: json['deviceId'] as String? ?? '',
      syncStatus: SyncStatus.synced.value,
    );
  }
}
