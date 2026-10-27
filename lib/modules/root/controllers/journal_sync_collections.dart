import 'package:objectbox/objectbox.dart';
import 'package:sync_wise/sync_wise.dart';

import 'package:journal/objectbox/objectbox.dart';
import 'package:journal/modules/notes/controllers/notes_repository.dart';
import 'package:journal/modules/notes/models/note_entity.dart';
import 'package:journal/modules/diary/controllers/diary_repository.dart';
import 'package:journal/modules/diary/models/diary_day_entity.dart';
import 'package:journal/modules/diary/models/diary_item.dart';
import 'package:journal/modules/flow/controllers/thoughts_repository.dart';
import 'package:journal/modules/flow/models/thought_entity.dart';

List<SyncCollection> journalSyncCollections({
  required ObjectBox db,
  required DeviceIdentityService device,
  required NotesRepository notes,
  required DiaryRepository diary,
  required ThoughtsRepository thoughts,
  required SyncStateStore storage,
}) {
  // Once-only bridge for records saved by versions without a durable outbox.
  if (storage.storage.read('outboxMigrated') == null) {
    db.store.runInTransaction(TxMode.write, () {
      for (final note in notes.getPendingUploadNotes()) {
        if (!note.isDeleted) {
          storage.enqueue(
            PendingCreation(
              id: note.uuid,
              type: 'note',
              documentId: note.uuid,
              payload: note.toSyncJson(device.deviceName),
            ),
          );
        }
      }
      for (final day in diary.getPendingUploadDays()) {
        for (final item in day.items.where((item) => !item.isDeleted)) {
          storage.enqueue(
            PendingCreation(
              id: item.itemUuid,
              type: 'diary',
              documentId: day.dateString,
              payload: {'date_string': day.dateString, 'item': item.toJson()},
            ),
          );
        }
      }
      storage.storage.write('outboxMigrated', '1');
    });
  }
  return [
    _NotesCollection(db, device, notes, storage),
    _DiaryCollection(db, device, diary, storage),
    _ThoughtsCollection(db, device, thoughts, storage),
  ];
}

bool _same(Object? a, Object? b) => canonicalJson(a) == canonicalJson(b);
int _legacyRank(RemoteDocument a, RemoteDocument b, String primary) {
  // Shared documents supersede legacy metadata on a partially completed upgrade.
  final shared = (a.isCanonical ? 1 : 0).compareTo(b.isCanonical ? 1 : 0);
  if (shared != 0) return shared;
  final time = DateTime.parse(a.payload['updated_at'] as String)
      .compareTo(DateTime.parse(b.payload['updated_at'] as String));
  if (time != 0) return time;
  final preferred = (a.deviceId == primary ? 1 : 0).compareTo(
    b.deviceId == primary ? 1 : 0,
  );
  return preferred != 0 ? preferred : a.fileId.compareTo(b.fileId);
}

class _NotesCollection implements SyncCollection {
  final ObjectBox db;
  final DeviceIdentityService device;
  final NotesRepository notes;
  final SyncStateStore storage;
  _NotesCollection(this.db, this.device, this.notes, this.storage);
  @override
  String get type => 'note';
  @override
  String get label => 'notes';
  @override
  bool get requiresRemoteForCreation => false;
  SyncDocument _snapshot(NoteEntity note) => SyncDocument(
    id: note.uuid,
    payload: note.toSyncJson(device.deviceName),
    status: note.status,
  );
  @override
  List<String> get allIds => db.noteBox.getAll().map((n) => n.uuid).toList();
  @override
  List<String> get pendingIds =>
      notes.getPendingUploadNotes().map((n) => n.uuid).toList();
  @override
  SyncDocument? read(String id) {
    final note = notes.getNoteByUuid(id);
    return note == null ? null : _snapshot(note);
  }

  @override
  SyncDocument decode(Map<String, dynamic> payload) {
    final note = NoteEntity.fromSyncJson(payload);
    if (note.uuid.isEmpty) throw const FormatException('Empty note UUID.');
    return _snapshot(note);
  }

  @override
  bool mergeRemote(SyncDocument document, {required DateTime now}) => db.store
      .runInTransaction(TxMode.write, () => _mergeRemote(document, now));
  bool _mergeRemote(SyncDocument document, DateTime now) {
    final incoming = NoteEntity.fromSyncJson(document.payload);
    final local = notes.getNoteByUuid(document.id);
    if (local != null) {
      if (storage.dirty(type, local.uuid) ||
          local.status == SyncStatus.pendingUpload ||
          local.status == SyncStatus.localOnly) {
        markPending(local.uuid);
        return false;
      }
      if (storage.protected(type, local.uuid, 'record', now) &&
          !_same(read(local.uuid)!.payload, document.payload)) {
        return true;
      }
      incoming.id = local.id;
    }
    incoming.status = SyncStatus.synced;
    db.noteBox.put(incoming);
    return false;
  }

  @override
  SyncDocument appendCreations(
    SyncDocument? remote,
    List<PendingCreation> operations,
  ) => remote ?? decode(operations.single.payload);
  @override
  List<SyncDocument> migrateLegacy(
    List<RemoteDocument> documents,
    String primaryDeviceId,
  ) {
    final grouped = <String, List<RemoteDocument>>{};
    for (final document in documents) {
      final decoded = decode(document.payload);
      if (decoded.id != document.documentId) {
        throw const FormatException('Legacy note ID mismatch.');
      }
      grouped.putIfAbsent(decoded.id, () => []).add(document);
    }
    return grouped.values.map((list) {
      list.sort((a, b) => _legacyRank(a, b, primaryDeviceId));
      return decode(list.last.payload);
    }).toList();
  }

  @override
  void markPending(String id) {
    final note = notes.getNoteByUuid(id);
    if (note == null) return;
    note.status = SyncStatus.pendingUpload;
    db.noteBox.put(note);
  }

  @override
  void acknowledgeUpload(SyncDocument document) {
    db.store.runInTransaction(TxMode.write, () {
      final note = notes.getNoteByUuid(document.id)!;
      note.status = SyncStatus.synced;
      db.noteBox.put(note);
      storage.clean(type, document.id);
      for (final operation in storage.pendingCreations.where(
        (o) => o.type == type && o.documentId == document.id,
      )) {
        storage.acknowledgeCreation(operation);
      }
    });
  }

  @override
  void acknowledgeCreations(
    List<PendingCreation> operations,
    SyncDocument uploaded,
  ) {
    db.store.runInTransaction(TxMode.write, () {
      final note = notes.getNoteByUuid(uploaded.id)!;
      final unchanged = _same(_snapshot(note).payload, uploaded.payload);
      for (final operation in operations) {
        storage.acknowledgeCreation(operation);
      }
      note.status = unchanged ? SyncStatus.synced : SyncStatus.localOnly;
      if (unchanged) storage.clean(type, note.uuid);
      db.noteBox.put(note);
    });
  }

  @override
  void restrictToSecondary() {
    final pending = {
      for (final operation in storage.pendingCreations.where(
        (o) => o.type == type,
      ))
        operation.documentId: operation,
    };
    for (final id in pendingIds) {
      if (!_same(read(id)!.payload, pending[id]?.payload)) {
        final note = notes.getNoteByUuid(id)!;
        note.status = SyncStatus.localOnly;
        db.noteBox.put(note);
      }
    }
  }
}

class _ThoughtsCollection implements SyncCollection {
  final ObjectBox db;
  final DeviceIdentityService device;
  final ThoughtsRepository thoughts;
  final SyncStateStore storage;
  _ThoughtsCollection(this.db, this.device, this.thoughts, this.storage);

  @override
  String get type => 'thought';
  @override
  String get label => 'thoughts';
  @override
  bool get requiresRemoteForCreation => false;

  SyncDocument _snapshot(ThoughtEntity thought) => SyncDocument(
    id: thought.uuid,
    payload: thought.toSyncJson(device.deviceName),
    status: thought.status,
  );

  @override
  List<String> get allIds => db.thoughtBox.getAll().map((t) => t.uuid).toList();
  @override
  List<String> get pendingIds =>
      thoughts.getPendingUploadThoughts().map((t) => t.uuid).toList();
  @override
  SyncDocument? read(String id) {
    final thought = thoughts.getThoughtByUuid(id);
    return thought == null ? null : _snapshot(thought);
  }

  @override
  SyncDocument decode(Map<String, dynamic> payload) {
    final thought = ThoughtEntity.fromSyncJson(payload);
    if (thought.uuid.trim().isEmpty || thought.content.trim().isEmpty) {
      throw const FormatException('Empty thought UUID or content.');
    }
    return _snapshot(thought);
  }

  @override
  bool mergeRemote(SyncDocument document, {required DateTime now}) =>
      db.store.runInTransaction(TxMode.write, () {
        final incoming = ThoughtEntity.fromSyncJson(document.payload);
        final local = thoughts.getThoughtByUuid(document.id);
        if (local != null) {
          if (storage.dirty(type, local.uuid) ||
              local.status == SyncStatus.pendingUpload ||
              local.status == SyncStatus.localOnly) {
            if (local.status != SyncStatus.localOnly) markPending(local.uuid);
            return false;
          }
          if (storage.protected(type, local.uuid, 'record', now) &&
              !_same(read(local.uuid)!.payload, document.payload)) {
            return true;
          }
          incoming.id = local.id;
        }
        incoming.status = SyncStatus.synced;
        db.thoughtBox.put(incoming);
        return false;
      });

  @override
  SyncDocument appendCreations(
    SyncDocument? remote,
    List<PendingCreation> operations,
  ) => remote ?? decode(operations.single.payload);

  @override
  List<SyncDocument> migrateLegacy(
    List<RemoteDocument> documents,
    String primaryDeviceId,
  ) {
    final groups = <String, List<RemoteDocument>>{};
    for (final document in documents) {
      final decoded = decode(document.payload);
      if (decoded.id != document.documentId) {
        throw const FormatException('Legacy thought ID mismatch.');
      }
      groups.putIfAbsent(decoded.id, () => []).add(document);
    }
    return groups.values.map((group) {
      group.sort((a, b) => _legacyRank(a, b, primaryDeviceId));
      return decode(group.last.payload);
    }).toList();
  }

  @override
  void markPending(String id) {
    final thought = thoughts.getThoughtByUuid(id);
    if (thought == null) return;
    thought.status = SyncStatus.pendingUpload;
    db.thoughtBox.put(thought);
  }

  @override
  void acknowledgeUpload(SyncDocument document) {
    db.store.runInTransaction(TxMode.write, () {
      final thought = thoughts.getThoughtByUuid(document.id)!;
      thought.status = SyncStatus.synced;
      db.thoughtBox.put(thought);
      storage.clean(type, document.id);
      for (final operation in storage.pendingCreations.where(
        (o) => o.type == type && o.documentId == document.id,
      )) {
        storage.acknowledgeCreation(operation);
      }
    });
  }

  @override
  void acknowledgeCreations(
    List<PendingCreation> operations,
    SyncDocument uploaded,
  ) {
    db.store.runInTransaction(TxMode.write, () {
      final thought = thoughts.getThoughtByUuid(uploaded.id)!;
      final unchanged = _same(_snapshot(thought).payload, uploaded.payload);
      for (final operation in operations) {
        storage.acknowledgeCreation(operation);
      }
      thought.status = unchanged ? SyncStatus.synced : SyncStatus.localOnly;
      if (unchanged) storage.clean(type, thought.uuid);
      db.thoughtBox.put(thought);
    });
  }

  @override
  void restrictToSecondary() {
    final pending = {
      for (final operation in storage.pendingCreations.where(
        (o) => o.type == type,
      ))
        operation.documentId: operation,
    };
    for (final id in pendingIds) {
      if (!_same(read(id)!.payload, pending[id]?.payload)) {
        final thought = thoughts.getThoughtByUuid(id)!;
        thought.status = SyncStatus.localOnly;
        db.thoughtBox.put(thought);
      }
    }
  }
}

class _DiaryCollection implements SyncCollection {
  final ObjectBox db;
  final DeviceIdentityService device;
  final DiaryRepository diary;
  final SyncStateStore storage;
  _DiaryCollection(this.db, this.device, this.diary, this.storage);
  @override
  String get type => 'diary';
  @override
  String get label => 'diary entries';
  @override
  bool get requiresRemoteForCreation => true;
  SyncDocument _snapshot(DiaryDayEntity day) => SyncDocument(
    id: day.dateString,
    payload: day.toSyncJson(device.deviceName),
    status: day.status,
  );
  @override
  List<String> get allIds =>
      db.diaryBox.getAll().map((d) => d.dateString).toList();
  @override
  List<String> get pendingIds =>
      diary.getPendingUploadDays().map((d) => d.dateString).toList();
  @override
  SyncDocument? read(String id) {
    final day = diary.getDay(id);
    return day == null ? null : _snapshot(day);
  }

  @override
  SyncDocument decode(Map<String, dynamic> payload) {
    final day = DiaryDayEntity.fromSyncJson(payload);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day.dateString) ||
        DiaryRepository.formatDateKey(DateTime.parse(day.dateString)) !=
            day.dateString) {
      throw const FormatException('Invalid diary date.');
    }
    final ids = <String>{};
    for (final item in day.items) {
      if (item.itemUuid.isEmpty || !ids.add(item.itemUuid)) {
        throw const FormatException('Invalid or duplicate diary item UUID.');
      }
    }
    return _snapshot(day);
  }

  List<DiaryItem> _sorted(Iterable<DiaryItem> items) =>
      items.toList()..sort((a, b) {
        final time = a.createdAt.compareTo(b.createdAt);
        return time != 0 ? time : a.itemUuid.compareTo(b.itemUuid);
      });
  @override
  bool mergeRemote(SyncDocument document, {required DateTime now}) => db.store
      .runInTransaction(TxMode.write, () => _mergeRemote(document, now));
  bool _mergeRemote(SyncDocument document, DateTime now) {
    final remote = DiaryDayEntity.fromSyncJson(document.payload);
    final remotePayload = canonicalJson(remote.toSyncJson(device.deviceName));
    final local = diary.getDay(document.id);
    if (local == null) {
      db.diaryBox.put(remote);
      return false;
    }
    var deferred = false;
    final items = {for (final item in local.items) item.itemUuid: item};
    for (final incoming in remote.items) {
      final existing = items[incoming.itemUuid];
      if (existing != null &&
          storage.dirty(type, document.id, incoming.itemUuid)) {
        continue;
      }
      if (existing != null &&
          storage.protected(type, document.id, incoming.itemUuid, now) &&
          !_same(existing.toJson(), incoming.toJson())) {
        deferred = true;
        continue;
      }
      items[incoming.itemUuid] = incoming;
    }
    final dirtyMetadata = storage.dirty(type, document.id, 'metadata');
    final protectedMetadata =
        storage.protected(type, document.id, 'metadata', now) &&
        (local.dayMood != remote.dayMood ||
            local.dayTitle != remote.dayTitle ||
            local.daySummary != remote.daySummary ||
            local.dayThemes != remote.dayThemes);
    if (protectedMetadata && !dirtyMetadata) deferred = true;
    final result = (dirtyMetadata || protectedMetadata) ? local : remote;
    result.id = local.id;
    result.items = _sorted(items.values);
    result.status =
        canonicalJson(result.toSyncJson(device.deviceName)) == remotePayload
        ? SyncStatus.synced
        : SyncStatus.pendingUpload;
    if (storage.dirty(type, document.id)) {
      result.status = SyncStatus.pendingUpload;
    }
    db.diaryBox.put(result);
    return deferred;
  }

  @override
  SyncDocument appendCreations(
    SyncDocument? remote,
    List<PendingCreation> operations,
  ) {
    final day = remote == null
        ? DiaryDayEntity(
            dateString: operations.first.documentId,
            createdAt: DateTime.parse(
              (operations.first.payload['item'] as Map)['created_at'] as String,
            ),
          )
        : DiaryDayEntity.fromSyncJson(remote.payload);
    final items = {for (final item in day.items) item.itemUuid: item};
    for (final operation in operations) {
      if (operation.documentId != day.dateString ||
          operation.payload['date_string'] != day.dateString) {
        throw const FormatException('Diary addition targets another date.');
      }
      final item = DiaryItem.fromJson(
        (operation.payload['item'] as Map).cast<String, dynamic>(),
      );
      if (item.itemUuid != operation.id || item.isDeleted) {
        throw const FormatException('Invalid diary addition.');
      }
      items.putIfAbsent(item.itemUuid, () => item);
      if (item.updatedAt.isAfter(day.updatedAt)) day.updatedAt = item.updatedAt;
    }
    day.items = _sorted(items.values);
    return _snapshot(day);
  }

  @override
  List<SyncDocument> migrateLegacy(
    List<RemoteDocument> documents,
    String primaryDeviceId,
  ) {
    final groups = <String, List<RemoteDocument>>{};
    for (final document in documents) {
      if (decode(document.payload).id != document.documentId) {
        throw const FormatException('Legacy diary ID mismatch.');
      }
      groups.putIfAbsent(document.documentId, () => []).add(document);
    }
    return groups.values.map((group) {
      group.sort((a, b) => _legacyRank(a, b, primaryDeviceId));
      final day = DiaryDayEntity.fromSyncJson(group.last.payload);
      final items = <String, DiaryItem>{};
      for (final document in group) {
        for (final item in DiaryDayEntity.fromSyncJson(
          document.payload,
        ).items) {
          final previous = items[item.itemUuid];
          if (previous == null ||
              item.updatedAt.isAfter(previous.updatedAt) ||
              (item.updatedAt == previous.updatedAt &&
                  canonicalJson(item.toJson())
                          .compareTo(canonicalJson(previous.toJson())) >
                      0)) {
            items[item.itemUuid] = item;
          }
        }
      }
      // Shared item contents, including tombstones, supersede legacy copies.
      for (final document in group.where((d) => d.isCanonical)) {
        for (final item in DiaryDayEntity.fromSyncJson(
          document.payload,
        ).items) {
          items[item.itemUuid] = item;
        }
      }
      day.items = _sorted(items.values);
      return _snapshot(day);
    }).toList();
  }

  @override
  void markPending(String id) {
    final day = diary.getDay(id);
    if (day == null) return;
    day.status = SyncStatus.pendingUpload;
    db.diaryBox.put(day);
  }

  @override
  void acknowledgeUpload(SyncDocument document) {
    db.store.runInTransaction(TxMode.write, () {
      final day = diary.getDay(document.id)!;
      day.status = SyncStatus.synced;
      db.diaryBox.put(day);
      storage.clean(type, document.id);
      for (final operation in storage.pendingCreations.where(
        (o) => o.type == type && o.documentId == document.id,
      )) {
        storage.acknowledgeCreation(operation);
      }
    });
  }

  @override
  void acknowledgeCreations(
    List<PendingCreation> operations,
    SyncDocument uploaded,
  ) {
    db.store.runInTransaction(TxMode.write, () {
      final day = diary.getDay(uploaded.id)!;
      final local = {for (final item in day.items) item.itemUuid: item};
      for (final incoming in DiaryDayEntity.fromSyncJson(
        uploaded.payload,
      ).items) {
        local.putIfAbsent(incoming.itemUuid, () => incoming);
      }
      day.items = _sorted(local.values);
      final accepted = {
        for (final item in DiaryDayEntity.fromSyncJson(uploaded.payload).items)
          item.itemUuid: item,
      };
      for (final operation in operations) {
        if (_same(local[operation.id]?.toJson(), operation.payload['item']) &&
            _same(
              accepted[operation.id]?.toJson(),
              operation.payload['item'],
            )) {
          storage.cleanField(type, uploaded.id, operation.id);
        }
        storage.acknowledgeCreation(operation);
      }
      final pending = {
        for (final operation in storage.pendingCreations.where(
          (o) => o.type == type && o.documentId == uploaded.id,
        ))
          operation.id: operation,
      };
      final localOnly =
          storage.dirty(type, uploaded.id, 'metadata') ||
          day.items.any(
            (item) =>
                storage.dirty(type, uploaded.id, item.itemUuid) &&
                !_same(item.toJson(), pending[item.itemUuid]?.payload['item']),
          );
      day.status = localOnly
          ? SyncStatus.localOnly
          : pending.isNotEmpty
          ? SyncStatus.pendingUpload
          : SyncStatus.synced;
      db.diaryBox.put(day);
    });
  }

  @override
  void restrictToSecondary() {
    final ops = {
      for (final op in storage.pendingCreations.where((o) => o.type == type))
        op.id: op,
    };
    for (final id in pendingIds) {
      final day = diary.getDay(id)!;
      final localOnly =
          storage.dirty(type, id, 'metadata') ||
          day.items.any(
            (item) =>
                storage.dirty(type, id, item.itemUuid) &&
                !_same(item.toJson(), ops[item.itemUuid]?.payload['item']),
          );
      if (localOnly || !ops.values.any((o) => o.documentId == id)) {
        day.status = SyncStatus.localOnly;
        db.diaryBox.put(day);
      }
    }
  }
}
