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
    'itemUuid': itemUuid,
    'createdAt': createdAt.toIso8601String(),
    'content': content,
    if (mood != null) 'mood': mood,
    'attachmentPaths': attachmentPaths,
    'deviceId': deviceId,
    'updatedAt': updatedAt.toIso8601String(),
    'isDeleted': isDeleted,
  };

  factory DiaryItem.fromJson(Map<String, dynamic> json) => DiaryItem(
    itemUuid: json['itemUuid'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    content: json['content'] as String? ?? '',
    mood: json['mood'] as String?,
    attachmentPaths:
        (json['attachmentPaths'] as List<dynamic>?)?.cast<String>() ?? const [],
    deviceId: json['deviceId'] as String? ?? '',
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    isDeleted: json['isDeleted'] as bool? ?? false,
  );
}
