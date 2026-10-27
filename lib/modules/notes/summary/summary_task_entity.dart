import 'package:objectbox/objectbox.dart';

/// Local recovery metadata only. Never registered as a sync collection.
@Entity()
class SummaryTaskEntity {
  @Id()
  int id;
  @Unique()
  String taskId;
  int created;
  bool active;
  // SummaryHandle without pendingText/localSource, credentials, title or result text.
  String metadata;

  SummaryTaskEntity({
    this.id = 0,
    required this.taskId,
    required this.created,
    required this.active,
    required this.metadata,
  });
}
