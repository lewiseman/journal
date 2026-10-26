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
    'is_pinned': isPinned,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'is_deleted': isDeleted,
    'is_permanently_deleted': isPermanentlyDeleted,
    'deleted_at': deletedAt?.toIso8601String(),
    'device_id': lastEditedByDeviceId,
    'device_name': deviceName,
    'version_vector_json': versionVectorJson,
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
        (json['attachment_paths'] as List?)
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
    isPinned: json['is_pinned'] as bool? ?? false,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    isDeleted: json['is_deleted'] as bool? ?? false,
    isPermanentlyDeleted: json['is_permanently_deleted'] as bool? ?? false,
    deletedAt: json['deleted_at'] == null
        ? null
        : DateTime.parse(json['deleted_at'] as String),
    lastEditedByDeviceId: json['device_id'] as String? ?? '',
    versionVectorJson: json['version_vector_json'] as String? ?? '{}',
    syncStatus: SyncStatus.synced.value,
  );
}
