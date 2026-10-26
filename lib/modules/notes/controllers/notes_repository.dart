import 'package:journal/common.dart';
import 'package:journal/objectbox/objectbox.g.dart';
import 'package:sync_wise/sync_wise.dart';
import 'package:uuid/uuid.dart';
import 'package:journal/modules/root/controllers/journal_sync_store.dart';

class NotesRepository {
  final void Function()? onDataChanged;

  final ObjectBox _db;
  final DeviceIdentityService _identity;
  final SyncStateStore sync;

  NotesRepository({
    ObjectBox? db,
    DeviceIdentityService? device,
    SyncStateStore? sync,
    this.onDataChanged,
  }) : _db = db ?? objectbox,
       _identity = device ?? DeviceIdentityService.instance,
       sync =
           sync ??
           SyncStateStore(
             storage: JournalSyncKeyValueStore((db ?? objectbox).store),
             deviceId: (device ?? DeviceIdentityService.instance).deviceId,
           );

  void _editable() {
    if (!sync.canEdit) {
      throw StateError('Existing notes are read-only on this device.');
    }
  }

  List<NoteEntity> getPendingUploadNotes() => _box
      .getAll()
      .where(
        (note) =>
            note.status != SyncStatus.synced &&
            note.status != SyncStatus.localOnly,
      )
      .toList();

  void _persist(NoteEntity note, {bool creation = false}) {
    _db.store.runInTransaction(TxMode.write, () {
      _box.put(note);
      sync.edited('note', note.uuid);
      if (creation) {
        sync.enqueue(
          PendingCreation(
            id: note.uuid,
            type: 'note',
            documentId: note.uuid,
            payload: note.toSyncJson(_identity.deviceName),
          ),
        );
      }
    });
    onDataChanged?.call();
  }

  Box<NoteEntity> get _box => _db.noteBox;

  String get device => _identity.deviceId;

  /// Returns a stream of non-deleted notes, ordered by update time descending.
  Stream<List<NoteEntity>> watchActiveNotes() {
    return _box
        .query(NoteEntity_.isDeleted.equals(false))
        .order(NoteEntity_.updatedAt, flags: Order.descending)
        .watch(triggerImmediately: true)
        .map((q) => q.find());
  }

  /// Returns a stream of soft-deleted notes (Trash).
  Stream<List<NoteEntity>> watchTrashNotes() {
    return _box
        .query(
          NoteEntity_.isDeleted
              .equals(true)
              .and(
                NoteEntity_.isPermanentlyDeleted
                    .equals(false)
                    .or(NoteEntity_.isPermanentlyDeleted.isNull()),
              ),
        )
        .order(NoteEntity_.deletedAt, flags: Order.descending)
        .watch(triggerImmediately: true)
        .map((q) => q.find());
  }

  /// Returns a stream of conflict notes.
  Stream<List<NoteEntity>> watchConflictNotes() {
    return _box
        .query(
          NoteEntity_.isConflict
              .equals(true)
              .and(NoteEntity_.isDeleted.equals(false)),
        )
        .watch(triggerImmediately: true)
        .map((q) => q.find());
  }

  /// Fetches note by UUID.
  NoteEntity? getNoteByUuid(String uuid) {
    final query = _box.query(NoteEntity_.uuid.equals(uuid)).build();
    final result = query.findFirst();
    query.close();
    return result;
  }

  NoteEntity saveNote({
    String? uuid,
    String? expectedVersionVectorJson,
    required String title,
    required String content,
    List<String> tags = const [],
    List<Map> attachmentPaths = const [],
    Map<String, dynamic>? background,
    bool preserveLocalDraft = false,
  }) {
    final effectiveUuid = uuid ?? const Uuid().v4();
    var existing = getNoteByUuid(effectiveUuid);
    final now = sync.now();
    final isNew = existing == null;
    if (!isNew && !preserveLocalDraft) _editable();
    if (existing != null &&
        expectedVersionVectorJson != null &&
        !existing.versionVector.isEqualTo(
          VersionVector.fromJsonString(expectedVersionVectorJson),
        )) {
      // The editor was opened before a remote update arrived. Preserve the
      // draft separately instead of assigning it the newer record's clock.
      final draft = NoteEntity(
        uuid: const Uuid().v4(),
        title: '$title (Conflict from local editor)',
        content: content,
        tags: tags,
        attachments: attachmentPaths
            .map((item) => Map<String, dynamic>.from(item))
            .toList(),
        background: Map.of(background ?? existing.background),
        createdAt: now,
        updatedAt: now,
        lastEditedByDeviceId: device,
        isConflict: true,
        conflictedWithUuid: effectiveUuid,
      );
      draft.versionVector = draft.versionVector.increment(device);
      _persist(draft, creation: true);
      return draft;
    }
    if (existing == null) {
      existing = NoteEntity(
        uuid: effectiveUuid,
        title: title,
        content: content,
        tags: tags,
        attachments: attachmentPaths
            .map((item) => Map<String, dynamic>.from(item))
            .toList(),
        background: Map.of(background ?? const {}),
        createdAt: now,
        updatedAt: now,
        lastEditedByDeviceId: device,
        isDeleted: false,
      );
      // Increment vector for new note
      existing.versionVector = existing.versionVector.increment(device);
      existing.status = SyncStatus.pendingUpload;
    } else {
      existing.title = title;
      existing.content = content;
      existing.tags = tags;
      if (background != null) existing.background = Map.of(background);
      existing.attachments = attachmentPaths
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      existing.updatedAt = now;
      existing.lastEditedByDeviceId = device;
      // Step 2: Mark note as pending sync & increment revision locally
      existing.versionVector = existing.versionVector.increment(device);
      existing.status = SyncStatus.pendingUpload;
    }

    if (!sync.canEdit && !isNew) existing.status = SyncStatus.localOnly;
    _persist(existing, creation: isNew);
    return existing;
  }

  /// Soft deletes a note (creates tombstone).
  void deleteNote(String uuid) {
    _editable();
    final note = getNoteByUuid(uuid);
    if (note == null) return;

    note.isDeleted = true;
    note.deletedAt = sync.now();
    note.updatedAt = sync.now();
    note.lastEditedByDeviceId = device;
    note.versionVector = note.versionVector.increment(device);
    note.status = SyncStatus.pendingUpload;

    _persist(note);
  }

  void pinNote(String uuid) {
    _editable();
    final note = getNoteByUuid(uuid);
    if (note == null) return;

    note.isPinned = !note.isPinned;
    note.updatedAt = sync.now();
    note.lastEditedByDeviceId = device;
    note.versionVector = note.versionVector.increment(device);
    note.status = SyncStatus.pendingUpload;

    _persist(note);
  }
}
