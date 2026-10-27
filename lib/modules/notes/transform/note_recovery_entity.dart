import 'package:objectbox/objectbox.dart';

/// Local-only recovery text, protected like other note text in ObjectBox.
/// Deliberately excluded from journalSyncCollections.
@Entity()
class NoteRecoveryEntity {
  @Id()
  int id;
  @Unique()
  String taskId;
  String noteId;
  String operation;
  String beforeContent;
  String afterContent;
  String afterVersion;
  int created;
  bool restored;

  NoteRecoveryEntity({
    this.id = 0,
    required this.taskId,
    required this.noteId,
    required this.operation,
    required this.beforeContent,
    required this.afterContent,
    required this.afterVersion,
    required this.created,
    this.restored = false,
  });
}
