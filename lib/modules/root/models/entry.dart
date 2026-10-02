import 'package:objectbox/objectbox.dart';

enum EntryType { note, diary }

@Entity()
class Entry {
  @Id()
  int id;

  /// Global ID used for sync between devices.
  @Unique()
  String uuid;

  /// note = 0
  /// diary = 1
  @Index()
  int type;

  String? title;

  /// Main note / diary text.
  List<Map<String, dynamic>> content;

  /// Actual time this record was created.
  @Property(type: PropertyType.dateUtc)
  DateTime createdAt;

  /// Last modification time.
  @Property(type: PropertyType.dateUtc)
  @Index()
  DateTime updatedAt;

  /// Used mainly by diary entries.
  /// Represents the date/time the user associates with the entry.
  @Property(type: PropertyType.dateUtc)
  @Index()
  DateTime? entryDate;

  /// Soft deletion for future synchronization.
  @Property(type: PropertyType.dateUtc)
  DateTime? deletedAt;

  bool isFavorite;

  bool isPinned;

  bool isArchived;

  /// Used later for synchronization.
  int revision;

  Entry({
    this.id = 0,
    required this.uuid,
    required this.type,
    this.title,
    this.content = const [],
    required this.createdAt,
    required this.updatedAt,
    this.entryDate,
    this.deletedAt,
    this.isFavorite = false,
    this.isPinned = false,
    this.isArchived = false,
    this.revision = 1,
  });
}

extension EntryTypeValue on Entry {
  EntryType get entryType => EntryType.values[type];
}


