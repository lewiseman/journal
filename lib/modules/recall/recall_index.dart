import 'package:journal/modules/recall/recall_contract.dart';
import 'package:journal/modules/recall/recall_vector_entity.dart';
import 'package:journal/objectbox/objectbox.g.dart';

/// One vector match: the source key and its cosine distance.
class RecallNeighbor {
  const RecallNeighbor(this.kind, this.sourceId, this.date, this.distance);
  final RecallKind kind;
  final String sourceId, date;
  final double distance;
}

/// The phone's vector store. Only rows of the current [model] are queried,
/// so vectors from two embedding models are never compared.
class RecallIndex {
  RecallIndex(Store store) : _box = store.box<RecallVectorEntity>();
  final Box<RecallVectorEntity> _box;

  List<RecallVectorEntity> _where(Condition<RecallVectorEntity> condition) {
    final query = _box.query(condition).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  /// Stored hash per source key for [kind] and [model].
  Map<String, String> hashes(RecallKind kind, String model) => {
    for (final row in _where(
      RecallVectorEntity_.kind.equals(kind.name) &
          RecallVectorEntity_.model.equals(model),
    ))
      row.key: row.hash,
  };

  int count(RecallKind kind, String model) => hashes(kind, model).length;

  void put(RecallSource source, String model, List<double> vector) => _box.put(
    RecallVectorEntity(
      key: source.key,
      kind: source.kind.name,
      sourceId: source.id,
      date: source.date,
      hash: source.hash,
      model: model,
      dimensions: vector.length,
      vector: vector,
    ),
  );

  /// Drops rows of [kind] whose key is not in [keep], plus any row of
  /// another model. Returns how many were removed.
  int prune(RecallKind kind, String model, Set<String> keep) {
    final stale = [
      for (final row in _where(RecallVectorEntity_.kind.equals(kind.name)))
        if (row.model != model || !keep.contains(row.key)) row.id,
    ];
    return _box.removeMany(stale);
  }

  /// Removes every vector of [kind], e.g. when its opt-in is turned off.
  int clear(RecallKind kind) => _box.removeMany(
    _where(RecallVectorEntity_.kind.equals(kind.name))
        .map((row) => row.id)
        .toList(),
  );

  void clearAll() => _box.removeAll();

  /// Nearest sources of [kinds] to [vector] within [recallMaxDistance],
  /// closest first. Asks the index for more than [limit] so date scopes
  /// and kind filters still leave enough.
  List<RecallNeighbor> nearest(
    List<double> vector,
    String model, {
    required Set<RecallKind> kinds,
    int limit = 40,
    String? from,
    String? to,
  }) {
    if (kinds.isEmpty) return const [];
    var condition =
        RecallVectorEntity_.vector.nearestNeighborsF32(vector, limit * 3) &
        RecallVectorEntity_.model.equals(model) &
        RecallVectorEntity_.kind.oneOf([for (final k in kinds) k.name]);
    if (from != null) {
      condition = condition & RecallVectorEntity_.date.greaterOrEqual(from);
    }
    if (to != null) {
      condition = condition & RecallVectorEntity_.date.lessOrEqual(to);
    }
    final query = _box.query(condition).build();
    try {
      return [
        for (final hit in query.findWithScores())
          if (hit.score <= recallMaxDistance)
            RecallNeighbor(
              RecallKind.values.byName(hit.object.kind),
              hit.object.sourceId,
              hit.object.date,
              hit.score,
            ),
      ].take(limit).toList();
    } finally {
      query.close();
    }
  }
}
