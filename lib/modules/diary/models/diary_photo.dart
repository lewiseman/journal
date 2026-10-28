/// One photo in a saved diary photo story (I01).
///
/// [path] is relative to the app support directory and names an app-owned
/// copy, so it stays valid if the platform moves the container. Sync carries
/// this record, never the image bytes: on another device the path resolves
/// to nothing and the photo is shown as kept on the device that added it.
class DiaryPhoto {
  /// Stable across edits and reorders, so later features can cite a photo.
  final String id;
  final String path;

  /// SHA-256 of the saved bytes; identifies the source image without
  /// recording picker paths, file names or location metadata.
  final String sha256;
  final String caption;
  final List<DiaryPhotoReflection> reflections;

  const DiaryPhoto({
    required this.id,
    required this.path,
    this.sha256 = '',
    this.caption = '',
    this.reflections = const [],
  });

  /// The reviewed words, in entry order, without the prompts.
  Iterable<String> get words sync* {
    if (caption.trim().isNotEmpty) yield caption.trim();
    for (final reflection in reflections) {
      if (reflection.answer.trim().isNotEmpty) yield reflection.answer.trim();
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    if (sha256.isNotEmpty) 'sha256': sha256,
    if (caption.isNotEmpty) 'caption': caption,
    if (reflections.isNotEmpty)
      'reflections': [for (final r in reflections) r.toJson()],
  };

  factory DiaryPhoto.fromJson(Map<String, dynamic> json) => DiaryPhoto(
    id: json['id'] as String,
    path: json['path'] as String,
    sha256: json['sha256'] as String? ?? '',
    caption: json['caption'] as String? ?? '',
    reflections: [
      for (final reflection in json['reflections'] as List? ?? const [])
        DiaryPhotoReflection.fromJson(reflection as Map<String, dynamic>),
    ],
  );

  /// Diary text readers (search, questions, suggestions) see only these words.
  static String composeContent(List<DiaryPhoto> photos) =>
      photos.expand((photo) => photo.words).join('\n\n');
}

/// A user's answer, kept with the sample prompt it answered.
class DiaryPhotoReflection {
  final String question;
  final String answer;

  const DiaryPhotoReflection({required this.question, required this.answer});

  Map<String, dynamic> toJson() => {'question': question, 'answer': answer};

  factory DiaryPhotoReflection.fromJson(Map<String, dynamic> json) =>
      DiaryPhotoReflection(
        question: json['question'] as String? ?? '',
        answer: json['answer'] as String? ?? '',
      );
}
