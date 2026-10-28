import 'package:objectbox/objectbox.dart';

/// A reflection on one thought, kept on this device only. It is a derived
/// artifact, never written into [ThoughtEntity] or journal sync: thoughts
/// are creation-only and their sync records are add-only. Removed by account
/// reset. At most one proposal and one kept reflection exist per thought.
@Entity()
class ThoughtReflectionEntity {
  @Id()
  int id;

  @Index()
  String thoughtUuid;

  /// [thoughtRevision] of the thought it was written for; a mismatch hides it.
  String revision;
  String text;

  /// The AI task that produced it, so a repeated completion is idempotent.
  String taskId;

  /// 'proposed' until the user keeps it, then 'kept'.
  String status;
  int created;

  ThoughtReflectionEntity({
    this.id = 0,
    required this.thoughtUuid,
    required this.revision,
    required this.text,
    required this.taskId,
    this.status = 'proposed',
    required this.created,
  });
}
