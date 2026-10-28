import 'package:journal/modules/flow/models/thought_entity.dart';
import 'package:journal/objectbox/objectbox.dart';
import 'package:journal/objectbox/objectbox.g.dart';
import 'package:sync_wise/sync_wise.dart';
import 'package:uuid/uuid.dart';

/// Creation-only storage. Committing a thought also commits its durable outbox.
class ThoughtsRepository {
  final ObjectBox db;
  final DeviceIdentityService device;
  final SyncStateStore sync;
  final void Function()? onDataChanged;

  ThoughtsRepository({
    required this.db,
    required this.device,
    required this.sync,
    this.onDataChanged,
  });

  ThoughtEntity saveThought({required String content, String? uuid}) {
    if (uuid != null) {
      final previous = getThoughtByUuid(uuid);
      if (previous != null) {
        if (previous.content != content.trim()) {
          throw StateError(
            'This recording was already saved with different text. Start a new thought explicitly.',
          );
        }
        return previous;
      }
    }
    final text = content.trim();
    if (text.isEmpty) {
      throw ArgumentError.value(content, 'content', 'Empty thought');
    }
    final now = sync.now();
    // Match ObjectBox's precision so a reloaded record equals its outbox snapshot.
    final storedTime = DateTime.fromMillisecondsSinceEpoch(
      now.millisecondsSinceEpoch,
      isUtc: now.isUtc,
    );
    final thought = ThoughtEntity(
      uuid: uuid ?? const Uuid().v4(),
      content: text,
      createdAt: storedTime,
      lastEditedByDeviceId: device.deviceId,
    );
    db.store.runInTransaction(TxMode.write, () {
      db.thoughtBox.put(thought);
      sync.edited('thought', thought.uuid);
      sync.enqueue(
        PendingCreation(
          id: thought.uuid,
          type: 'thought',
          documentId: thought.uuid,
          payload: thought.toSyncJson(device.deviceName),
        ),
      );
    });
    onDataChanged?.call();
    return thought;
  }

  Stream<List<ThoughtEntity>> watchThoughts() => db.thoughtBox
      .query()
      .order(ThoughtEntity_.createdAt, flags: Order.descending)
      .order(ThoughtEntity_.uuid)
      .watch(triggerImmediately: true)
      .map((query) => query.find());

  ThoughtEntity? getThoughtByUuid(String uuid) {
    final query = db.thoughtBox.query(ThoughtEntity_.uuid.equals(uuid)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  List<ThoughtEntity> getPendingUploadThoughts() => db.thoughtBox
      .getAll()
      .where((thought) => thought.status == SyncStatus.pendingUpload)
      .toList();
}
