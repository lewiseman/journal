import 'package:objectbox/objectbox.dart';

/// One question shown on this device. Local only: excluded from journal sync,
/// removed by account reset and when daily questions are turned off. Kept
/// only to show today's question again and to avoid immediate repetition.
@Entity()
class DailyQuestionEntity {
  @Id()
  int id;

  /// Civil day ("YYYY-MM-DD") the question was asked for.
  @Index()
  String day;
  String question;

  /// The entry it follows up on, or null for a general question.
  String? sourceDate;
  String? sourceItem;
  String evidence;
  int ago;

  /// 'shown' or 'skipped'.
  String status;
  int created;

  DailyQuestionEntity({
    this.id = 0,
    required this.day,
    required this.question,
    this.sourceDate,
    this.sourceItem,
    this.evidence = '',
    this.ago = 0,
    this.status = 'shown',
    required this.created,
  });
}
