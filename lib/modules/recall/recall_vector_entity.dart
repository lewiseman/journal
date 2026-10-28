import 'package:objectbox/objectbox.dart';

/// S03b: one embedding of one diary entry, note or Flow thought. Derived,
/// device-local and never synced: each phone rebuilds it from its own text.
@Entity()
class RecallVectorEntity {
  RecallVectorEntity({
    this.id = 0,
    required this.key,
    required this.kind,
    required this.sourceId,
    required this.date,
    required this.hash,
    required this.model,
    required this.dimensions,
    this.vector,
  });

  @Id()
  int id;

  /// `kind:sourceId`, one row per source.
  @Unique(onConflict: ConflictStrategy.replace)
  String key;

  /// diary, note or thought.
  @Index()
  String kind;
  String sourceId;

  /// Civil date `YYYY-MM-DD` the source belongs to, for date scopes.
  @Index()
  String date;

  /// Hash of the exact text that was embedded; a change means re-embed.
  String hash;

  /// Embedding model id; rows from another model are never queried.
  @Index()
  String model;
  int dimensions;

  @HnswIndex(dimensions: 1024, distanceType: VectorDistanceType.cosine)
  @Property(type: PropertyType.floatVector)
  List<double>? vector;
}
