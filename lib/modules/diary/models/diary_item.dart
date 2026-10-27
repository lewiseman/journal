class DiaryItem {
  final String itemUuid;
  final DateTime createdAt; // Exact time entry was recorded during the day
  final String content;
  final String? mood;
  final List<String> attachmentPaths;
  final String deviceId;
  final DateTime updatedAt;
  final bool isDeleted;

  const DiaryItem({
    required this.itemUuid,
    required this.createdAt,
    required this.content,
    this.mood,
    this.attachmentPaths = const [],
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
    deviceId: json['device_id'] as String? ?? '',
    updatedAt: DateTime.parse(json['updated_at'] as String),
    isDeleted: json['is_deleted'] as bool? ?? false,
  );
}
