import 'diary_photo.dart';

class DiaryItem {
  final String itemUuid;
  final DateTime createdAt; // Exact time entry was recorded during the day
  final String content;
  final String? mood;
  final List<String> attachmentPaths;

  /// Ordered photo story (I01). Empty for text items; [attachmentPaths]
  /// mirrors its paths for readers that predate photo stories.
  final List<DiaryPhoto> photos;
  final String deviceId;
  final DateTime updatedAt;
  final bool isDeleted;

  const DiaryItem({
    required this.itemUuid,
    required this.createdAt,
    required this.content,
    this.mood,
    this.attachmentPaths = const [],
    this.photos = const [],
    this.deviceId = '',
    required this.updatedAt,
    this.isDeleted = false,
  });

  DiaryItem copyWith({
    String? itemUuid,
    DateTime? createdAt,
    String? content,
    String? mood,
    List<String>? attachmentPaths,
    List<DiaryPhoto>? photos,
    String? deviceId,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return DiaryItem(
      itemUuid: itemUuid ?? this.itemUuid,
      createdAt: createdAt ?? this.createdAt,
      content: content ?? this.content,
      mood: mood ?? this.mood,
      attachmentPaths: attachmentPaths ?? this.attachmentPaths,
      photos: photos ?? this.photos,
      deviceId: deviceId ?? this.deviceId,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toJson() => {
    'item_uuid': itemUuid,
    'created_at': createdAt.toIso8601String(),
    // Keep the original sync_kit wire field for older diary documents.
    'timestamp': createdAt.toIso8601String(),
    'content': content,
    if (mood != null) 'mood': mood,
    'attachment_paths': attachmentPaths,
    // Omitted for text items so their shared documents stay byte-identical.
    if (photos.isNotEmpty) 'photos': [for (final p in photos) p.toJson()],
    'device_id': deviceId,
    'updated_at': updatedAt.toIso8601String(),
    'is_deleted': isDeleted,
  };

  factory DiaryItem.fromJson(Map<String, dynamic> json) => DiaryItem(
    itemUuid: json['item_uuid'] as String,
    createdAt: DateTime.parse(
      (json['created_at'] ?? json['timestamp']) as String,
    ),
    content: json['content'] as String? ?? '',
    mood: json['mood'] as String?,
    attachmentPaths:
        (json['attachment_paths'] as List<dynamic>?)?.cast<String>() ??
        const [],
    photos: _photos(json['photos']),
    deviceId: json['device_id'] as String? ?? '',
    updatedAt: DateTime.parse(json['updated_at'] as String),
    isDeleted: json['is_deleted'] as bool? ?? false,
  );

  /// Tolerant reader: a malformed photo record never hides the entry's words.
  static List<DiaryPhoto> _photos(Object? raw) {
    if (raw is! List) return const [];
    final photos = <DiaryPhoto>[];
    for (final entry in raw) {
      try {
        photos.add(DiaryPhoto.fromJson(entry as Map<String, dynamic>));
      } catch (_) {
        // Skip it; the remaining photos keep their order.
      }
    }
    return photos;
  }
}
