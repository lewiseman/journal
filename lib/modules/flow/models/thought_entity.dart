import 'package:objectbox/objectbox.dart';
import 'package:sync_wise/sync_wise.dart';

@Entity()
class ThoughtEntity {
  @Id()
  int id;

  @Unique()
  String uuid;

  String summary;
  String content;

  @Property(type: PropertyType.date)
  DateTime createdAt;

  @Property(type: PropertyType.date)
  DateTime updatedAt;

  String lastEditedByDeviceId;
  int syncStatus;

  ThoughtEntity({
    this.id = 0,
    required this.uuid,
    this.summary = '',
    required this.content,
    required this.createdAt,
    DateTime? updatedAt,
    this.lastEditedByDeviceId = '',
    int? syncStatus,
  }) : updatedAt = updatedAt ?? createdAt,
       syncStatus = syncStatus ?? SyncStatus.pendingUpload.value;

  @Transient()
  SyncStatus get status => SyncStatus.fromValue(syncStatus);

  set status(SyncStatus value) => syncStatus = value.value;

  Map<String, dynamic> toSyncJson(String deviceName) => {
    'uuid': uuid,
    'summary': summary,
    'content': content,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'deviceId': lastEditedByDeviceId,
    'deviceName': deviceName,
  };

  factory ThoughtEntity.fromSyncJson(Map<String, dynamic> json) =>
      ThoughtEntity(
        uuid: json['uuid'] as String,
        summary: json['summary'] as String? ?? '',
        content: json['content'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        lastEditedByDeviceId: json['deviceId'] as String? ?? '',
        syncStatus: SyncStatus.synced.value,
      );
}
