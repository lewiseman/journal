import 'package:objectbox/objectbox.dart';
import 'package:sync_wise/sync_wise.dart';

@Entity()
class NoteEntity {
  @Id()
  int id;

  @Index()
  @Unique()
  String uuid;

  String title;
  String content;

  /// Local references as `{'path': ..., 'type': <MIME type>}`; no file contents.
  List<Map<String, dynamic>> attachments;

  /// Color `type`, optional `image`, and `image_source` (`remote` or `local`).
  Map<String, dynamic> background;

  /// Tags stored as `emoji#name`, for example `🪣#Ideas`.
  List<String> tags;

  @Property(type: PropertyType.date)
  DateTime createdAt;

  @Property(type: PropertyType.date)
  DateTime updatedAt;

  bool isPinned;

  bool isDeleted;
  bool isPermanentlyDeleted;

  @Property(type: PropertyType.date)
  DateTime? deletedAt;

  String lastEditedByDeviceId;
  String versionVectorJson;
  int syncStatus;

  bool isConflict;
  String? conflictedWithUuid;

  NoteEntity({
    this.id = 0,
    required this.uuid,
    this.content = '',
    this.tags = const [],
    this.attachments = const [],
    this.background = const {},
    this.title = '',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isDeleted = false,
    this.isPinned = false,
    this.isPermanentlyDeleted = false,
    this.deletedAt,
    this.lastEditedByDeviceId = '',
    String? versionVectorJson,
    int? syncStatus,
    this.isConflict = false,
    this.conflictedWithUuid,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       versionVectorJson = versionVectorJson ?? '{}',
       syncStatus = syncStatus ?? SyncStatus.pendingUpload.value;

  @Transient()
  VersionVector get versionVector =>
      VersionVector.fromJsonString(versionVectorJson);

  set versionVector(VersionVector vector) {
    versionVectorJson = vector.toJsonString();
  }

  @Transient()
  SyncStatus get status => SyncStatus.fromValue(syncStatus);

  set status(SyncStatus s) {
    syncStatus = s.value;
  }

  Map<String, dynamic> toSyncJson(String deviceName) => {
    'uuid': uuid,
    'title': title,
    'content': content,
    'tags': tags,
    'attachments': attachments,
    'background': background,
    'isPinned': isPinned,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'isDeleted': isDeleted,
    'isPermanentlyDeleted': isPermanentlyDeleted,
    'deletedAt': deletedAt?.toIso8601String(),
    'deviceId': lastEditedByDeviceId,
    'deviceName': deviceName,
    'versionVectorJson': versionVectorJson,
  };

  factory NoteEntity.fromSyncJson(Map<String, dynamic> json) => NoteEntity(
    uuid: json['uuid'] as String,
    title: json['title'] as String? ?? '',
    content: json['content'] as String? ?? '',
    tags: (json['tags'] as List?)?.cast<String>() ?? const [],
    attachments:
        (json['attachments'] as List?)
            ?.map((value) => (value as Map).cast<String, dynamic>())
            .toList() ??
        (json['attachmentPaths'] as List?)
            ?.map(
              (path) => <String, dynamic>{
                'path': path,
                'type': 'application/octet-stream',
              },
            )
            .toList() ??
        const [],
    background:
        (json['background'] as Map?)?.cast<String, dynamic>() ?? const {},
    isPinned: json['isPinned'] as bool? ?? false,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    isDeleted: json['isDeleted'] as bool? ?? false,
    isPermanentlyDeleted: json['isPermanentlyDeleted'] as bool? ?? false,
    deletedAt: json['deletedAt'] == null
        ? null
        : DateTime.parse(json['deletedAt'] as String),
    lastEditedByDeviceId: json['deviceId'] as String? ?? '',
    versionVectorJson: json['versionVectorJson'] as String? ?? '{}',
    syncStatus: SyncStatus.synced.value,
  );
}
