import 'package:objectbox/objectbox.dart';

/// Local derivative and recoverable source, excluded from journal sync.
@Entity()
class PresentationEntity {
  @Id()
  int id;
  @Unique()
  String sourceKey;
  String snapshot;
  String document;
  String taskId;
  int policy;
  int created;
  bool enabled;
  PresentationEntity({
    this.id = 0,
    required this.sourceKey,
    required this.snapshot,
    required this.document,
    required this.taskId,
    this.policy = 1,
    required this.created,
    this.enabled = true,
  });
}
