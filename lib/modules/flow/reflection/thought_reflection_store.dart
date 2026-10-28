import 'package:journal/modules/flow/reflection/thought_reflection_entity.dart';
import 'package:journal/objectbox/objectbox.g.dart';

/// Local reflections. A new proposal never touches the kept reflection; only
/// [keep] replaces it, in one transaction.
class ThoughtReflectionStore {
  ThoughtReflectionStore(this._store)
    : _box = _store.box<ThoughtReflectionEntity>();
  final Store _store;
  final Box<ThoughtReflectionEntity> _box;

  /// Unkept proposals are dropped after this long.
  static const proposalDays = 7;

  List<ThoughtReflectionEntity> _find(
    Condition<ThoughtReflectionEntity> where,
  ) {
    final query = _box
        .query(where)
        .order(ThoughtReflectionEntity_.created, flags: Order.descending)
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  List<ThoughtReflectionEntity> _for(String uuid, String status) => _find(
    ThoughtReflectionEntity_.thoughtUuid.equals(uuid) &
        ThoughtReflectionEntity_.status.equals(status),
  );

  ThoughtReflectionEntity? proposal(String uuid) =>
      _for(uuid, 'proposed').firstOrNull;
  ThoughtReflectionEntity? kept(String uuid) => _for(uuid, 'kept').firstOrNull;

  /// Saves [text] as the proposal for [uuid], replacing an older proposal.
  /// The same [taskId] twice returns the first row.
  ThoughtReflectionEntity propose({
    required String uuid,
    required String revision,
    required String text,
    required String taskId,
    int? now,
  }) => _store.runInTransaction(TxMode.write, () {
    final existing = _find(ThoughtReflectionEntity_.taskId.equals(taskId));
    if (existing.isNotEmpty) return existing.first;
    final created = now ?? DateTime.now().millisecondsSinceEpoch;
    final cutoff = created - const Duration(days: proposalDays).inMilliseconds;
    _box.removeMany([
      for (final old in _find(
        ThoughtReflectionEntity_.status.equals('proposed'),
      ))
        if (old.thoughtUuid == uuid || old.created < cutoff) old.id,
    ]);
    final row = ThoughtReflectionEntity(
      thoughtUuid: uuid,
      revision: revision,
      text: text,
      taskId: taskId,
      created: created,
    );
    _box.put(row);
    return row;
  });

  /// Keeps proposal [id], replacing the thought's earlier kept reflection.
  bool keep(int id) => _store.runInTransaction(TxMode.write, () {
    final row = _box.get(id);
    if (row == null || row.status != 'proposed') return false;
    _box.removeMany([for (final old in _for(row.thoughtUuid, 'kept')) old.id]);
    _box.put(row..status = 'kept');
    return true;
  });

  /// Removes one reflection, proposed or kept.
  void remove(int id) => _box.remove(id);

  void clear() => _box.removeAll();
}
