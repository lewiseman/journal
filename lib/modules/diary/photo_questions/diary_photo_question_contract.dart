import 'dart:convert';

/// I02: reflection questions about one diary photo the user chose. Only the
/// re-encoded photo and its optional caption are sent; no diary text.
const diaryPhotoQuestionOperation = 'diary-photo-questions';
const diaryPhotoQuestionContract = 1;
const diaryPhotoCaptionChars = 240;
const diaryPhotoQuestionOutputBytes = 4096;
const diaryPhotoQuestionChars = 160;

/// The three reflection groups, in the order the Reflect tab shows them.
const diaryPhotoGroups = [
  (key: 'moment', label: 'The moment'),
  (key: 'feeling', label: 'The feeling'),
  (key: 'little', label: 'The little things'),
];

final _control = RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]');
final _sha = RegExp(r'^[a-f0-9]{64}$');

/// What was asked about. Kept in protected task storage; only [caption] and
/// the re-encoded image are sent.
class DiaryPhotoQuestionSource {
  const DiaryPhotoQuestionSource({
    required this.date,
    required this.photoSha,
    required this.imageSha,
    this.caption = '',
  });

  /// The civil day of the story, for the history label only.
  final String date;

  /// SHA-256 of the photo's saved bytes: the key results are cached under.
  final String photoSha;

  /// SHA-256 of the re-encoded upload, so a retry sends identical bytes.
  final String imageSha;
  final String caption;

  String request() => jsonEncode({'caption': caption});

  String encode() => jsonEncode({
    'date': date,
    'photoSha': photoSha,
    'imageSha': imageSha,
    'caption': caption,
  });

  factory DiaryPhotoQuestionSource.decode(String raw) {
    final json = jsonDecode(raw);
    if (json is! Map ||
        [
          'date',
          'photoSha',
          'imageSha',
          'caption',
        ].any((k) => json[k] is! String) ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(json['date'] as String) ||
        !_sha.hasMatch(json['photoSha'] as String) ||
        !_sha.hasMatch(json['imageSha'] as String)) {
      throw const FormatException('Invalid photo question source');
    }
    validateCaption(json['caption'] as String);
    return DiaryPhotoQuestionSource(
      date: json['date'] as String,
      photoSha: json['photoSha'] as String,
      imageSha: json['imageSha'] as String,
      caption: json['caption'] as String,
    );
  }

  static String validateCaption(String caption) {
    final value = caption.trim();
    if (value.runes.length > diaryPhotoCaptionChars ||
        _control.hasMatch(value)) {
      throw const FormatException(
        'Captions sent with a photo are at most 240 characters.',
      );
    }
    return value;
  }
}

/// A validated result. [observations] are what the model could see; they are
/// shown apart from the user's own words and never saved unless chosen.
class DiaryPhotoQuestions {
  const DiaryPhotoQuestions({
    required this.observations,
    required this.clear,
    required this.groups,
  });
  final String observations;

  /// False when the model found the photo too dark, blurred or ambiguous.
  final bool clear;

  /// One to three questions per [diaryPhotoGroups] entry, in that order.
  final List<List<String>> groups;

  factory DiaryPhotoQuestions.parse(String raw) {
    final json = jsonDecode(raw);
    Never fail() => throw const FormatException('Invalid photo questions');
    if (json is! Map ||
        json.length != 5 ||
        json['clear'] is! bool ||
        json['observations'] is! String) {
      fail();
    }
    final observations = (json['observations'] as String).trim();
    if (observations.isEmpty ||
        observations.runes.length > 600 ||
        _control.hasMatch(observations)) {
      fail();
    }
    final seen = <String>{};
    final groups = <List<String>>[];
    for (final group in diaryPhotoGroups) {
      final list = json[group.key];
      if (list is! List || list.isEmpty || list.length > 3) fail();
      final questions = <String>[];
      for (final item in list) {
        final question = item is String ? item.trim() : '';
        if (question.isEmpty ||
            !question.endsWith('?') ||
            question.runes.length > diaryPhotoQuestionChars ||
            _control.hasMatch(question)) {
          fail();
        }
        if (seen.add(question.toLowerCase())) questions.add(question);
      }
      if (questions.isEmpty) fail();
      groups.add(questions);
    }
    return DiaryPhotoQuestions(
      observations: observations,
      clear: json['clear'] as bool,
      groups: groups,
    );
  }

  Map<String, dynamic> toJson() => {
    'observations': observations,
    'clear': clear,
    for (final (index, group) in diaryPhotoGroups.indexed)
      group.key: groups[index],
  };
}
