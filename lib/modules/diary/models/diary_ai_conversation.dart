/// The spoken conversation a diary item was written from. Kept on the item so
/// the person can reopen it, and generate or regenerate the entry's words.
class DiaryAiConversation {
  const DiaryAiConversation({
    required this.turns,
    required this.createdAt,
    this.draftedAt,
  });

  /// `{speaker: user|assistant, text}` in the order they were said.
  final List<Map<String, String>> turns;
  final DateTime createdAt;

  /// When the entry's words were last written from these turns.
  final DateTime? draftedAt;

  bool get hasUserTurn => turns.any((t) => t['speaker'] == 'user');

  DiaryAiConversation copyWith({
    List<Map<String, String>>? turns,
    DateTime? draftedAt,
  }) => DiaryAiConversation(
    turns: turns ?? this.turns,
    createdAt: createdAt,
    draftedAt: draftedAt ?? this.draftedAt,
  );

  Map<String, dynamic> toJson() => {
    'turns': [for (final t in turns) Map<String, String>.from(t)],
    'created_at': createdAt.toIso8601String(),
    if (draftedAt != null) 'drafted_at': draftedAt!.toIso8601String(),
  };

  /// Tolerant reader: a malformed conversation never hides the entry's words.
  static DiaryAiConversation? tryParse(Object? raw) {
    if (raw is! Map) return null;
    try {
      final turns = <Map<String, String>>[];
      for (final t in raw['turns'] as List) {
        final speaker = (t as Map)['speaker'], text = t['text'];
        if ((speaker == 'user' || speaker == 'assistant') && text is String) {
          turns.add({'speaker': speaker as String, 'text': text});
        }
      }
      final drafted = raw['drafted_at'];
      return DiaryAiConversation(
        turns: turns,
        createdAt: DateTime.parse(raw['created_at'] as String),
        draftedAt: drafted is String ? DateTime.tryParse(drafted) : null,
      );
    } catch (_) {
      return null;
    }
  }
}
