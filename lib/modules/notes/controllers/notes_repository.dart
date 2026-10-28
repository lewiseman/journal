import 'dart:convert';

import 'package:journal/common.dart';

import '../transform/note_recovery_entity.dart';
import '../transform/transform_contract.dart';
import '../models/note_tag.dart';

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
  Stream<NoteEntity?> watchNoteByUuid(String uuid) => _box
      .query(NoteEntity_.uuid.equals(uuid))
      .watch(triggerImmediately: true)
      .map((query) => query.findFirst());

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

  /// Compare and commit synchronously. AI proposals never create conflict drafts.
  /// Backup and normal repository/sync writes share one ObjectBox transaction.
  NoteEntity acceptTransformation({
    required String taskId,
    required String uuid,
    required String operation,
    required TransformSource source,
    required String replacement,
  }) {
    _editable();
    if (!transformOperations.containsKey(operation) ||
        replacement.trim().isEmpty ||
        utf8.encode(replacement).length > transformOutputBytes ||
        !validTransformOutput(replacement)) {
      throw StateError('Invalid replacement. Your note is unchanged.');
    }
    TransformSource.decode(source.encode());
    late NoteEntity saved;
    _db.store.runInTransaction(TxMode.write, () {
      final history = _db.store.box<NoteRecoveryEntity>();
      if (history.getAll().any((row) => row.taskId == taskId)) {
        throw StateError(
          'This proposal was already accepted. Open recovery history.',
        );
      }
      final note = getNoteByUuid(uuid);
      if (note == null ||
          note.isDeleted ||
          note.isPermanentlyDeleted ||
          note.content != source.content ||
          !note.versionVector.isEqualTo(
            VersionVector.fromJsonString(source.version),
          )) {
        throw StateError(
          'The note changed. This proposal cannot replace a newer edit.',
        );
      }
      final content = source.replace(replacement);
      if (content == source.content) {
        throw StateError('The proposal has no changes to accept.');
      }
      saved = saveNote(
        uuid: uuid,
        expectedVersionVectorJson: source.version,
        title: note.title,
        content: content,
        tags: note.tags,
        attachmentPaths: note.attachments,
        background: note.background,
      );
      history.put(
        NoteRecoveryEntity(
          taskId: taskId,
          noteId: uuid,
          operation: operation,
          beforeContent: source.content,
          afterContent: content,
          afterVersion: saved.versionVectorJson,
          created: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      final rows = history.getAll()..sort((a, b) => b.id.compareTo(a.id));
      // Ten most recent acceptances on this phone, at most ~1.4 MiB.
      for (final row in rows.skip(10)) {
        history.remove(row.id);
      }
    });
    return saved;
  }

  /// Sets exactly [title] and [tags] if the note still has [expectedVersion].
  /// Used for reviewed suggestions and their undo; never creates a conflict draft.
  NoteEntity updateNoteMetadata({
    required String uuid,
    required String expectedVersion,
    required String title,
    required List<String> tags,
  }) {
    _editable();
    final cleanTitle = title.trim();
    final keys = <String>{};
    if (cleanTitle.isEmpty ||
        cleanTitle.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        tags.any((t) {
          final tag = NoteTag.tryParse(t);
          return tag == null || !keys.add(tag.key);
        })) {
      throw StateError('Invalid title or tags. Your note is unchanged.');
    }
    late NoteEntity saved;
    _db.store.runInTransaction(TxMode.write, () {
      final note = getNoteByUuid(uuid);
      if (note == null ||
          note.isDeleted ||
          note.isPermanentlyDeleted ||
          !note.versionVector.isEqualTo(
            VersionVector.fromJsonString(expectedVersion),
          )) {
        throw StateError(
          'The note changed. These suggestions cannot replace a newer edit.',
        );
      }
      saved = saveNote(
        uuid: uuid,
        expectedVersionVectorJson: expectedVersion,
        title: cleanTitle,
        content: note.content,
        tags: tags,
        attachmentPaths: note.attachments,
        background: note.background,
      );
    });
    return saved;
  }

  /// Appends reviewed AI-derived [text] to the body if the note still has
  /// [expectedVersion], keeping a local recovery copy like transformations.
  NoteEntity appendToNote({
    required String taskId,
    required String uuid,
    required String expectedVersion,
    required String operation,
    required String text,
    Map<String, dynamic>? attachment,
  }) {
    _editable();
    final addition = text.trim();
    if (addition.isEmpty ||
        utf8.encode(addition).length > transformOutputBytes ||
        addition.contains(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]'))) {
      throw StateError('Invalid text to insert. Your note is unchanged.');
    }
    late NoteEntity saved;
    _db.store.runInTransaction(TxMode.write, () {
      final history = _db.store.box<NoteRecoveryEntity>();
      if (history.getAll().any((row) => row.taskId == taskId)) {
        throw StateError(
          'This result was already inserted. Open recovery history.',
        );
      }
      final note = getNoteByUuid(uuid);
      if (note == null ||
          note.isDeleted ||
          note.isPermanentlyDeleted ||
          !note.versionVector.isEqualTo(
            VersionVector.fromJsonString(expectedVersion),
          )) {
        throw StateError(
          'The note changed. This result cannot be inserted into a newer edit.',
        );
      }
      final before = note.content;
      final content = before.trimRight().isEmpty
          ? addition
          : '${before.trimRight()}\n\n$addition';
      if (utf8.encode(content).length > transformSourceBytes) {
        throw StateError('The note would exceed 64 KiB. Nothing was inserted.');
      }
      saved = saveNote(
        uuid: uuid,
        expectedVersionVectorJson: expectedVersion,
        title: note.title,
        content: content,
        tags: note.tags,
        attachmentPaths: [
          ...note.attachments,
          if (attachment != null &&
              !note.attachments.any((a) => a['path'] == attachment['path']))
            attachment,
        ],
        background: note.background,
      );
      history.put(
        NoteRecoveryEntity(
          taskId: taskId,
          noteId: uuid,
          operation: operation,
          beforeContent: before,
          afterContent: content,
          afterVersion: saved.versionVectorJson,
          created: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      final rows = history.getAll()..sort((a, b) => b.id.compareTo(a.id));
      for (final row in rows.skip(10)) {
        history.remove(row.id);
      }
    });
    return saved;
  }

  List<NoteRecoveryEntity> transformationHistory(String uuid) =>
      (_db.store
          .box<NoteRecoveryEntity>()
          .getAll()
          .where((row) => row.noteId == uuid)
          .toList()
        ..sort((a, b) => b.id.compareTo(a.id)));

  void clearTransformationHistory(String uuid) {
    final box = _db.store.box<NoteRecoveryEntity>();
    box.removeMany(transformationHistory(uuid).map((row) => row.id).toList());
  }

  NoteEntity restoreTransformation(int recoveryId) {
    _editable();
    late NoteEntity saved;
    _db.store.runInTransaction(TxMode.write, () {
      final history = _db.store.box<NoteRecoveryEntity>();
      final row = history.get(recoveryId);
      final note = row == null ? null : getNoteByUuid(row.noteId);
      if (row == null ||
          row.restored ||
          note == null ||
          note.isDeleted ||
          note.isPermanentlyDeleted ||
          note.content != row.afterContent ||
          !note.versionVector.isEqualTo(
            VersionVector.fromJsonString(row.afterVersion),
          )) {
        throw StateError(
          'The note changed since acceptance. Copy the prior content to recover it manually.',
        );
      }
      saved = saveNote(
        uuid: note.uuid,
        expectedVersionVectorJson: row.afterVersion,
        title: note.title,
        content: row.beforeContent,
        tags: note.tags,
        attachmentPaths: note.attachments,
        background: note.background,
      );
      row.restored = true;
      history.put(row);
    });
    return saved;
  }

  /// Sets [background] only if the note's background still equals [expected];
  /// other fields and later text edits are kept. Never creates a conflict draft.
  NoteEntity setNoteBackground({
    required String uuid,
    required Map<String, dynamic> expected,
    required Map<String, dynamic> background,
  }) {
    _editable();
    String canonical(Map<String, dynamic> value) => jsonEncode({
      for (final key in value.keys.toList()..sort()) key: value[key],
    });
    late NoteEntity saved;
    _db.store.runInTransaction(TxMode.write, () {
      final note = getNoteByUuid(uuid);
      if (note == null || note.isDeleted || note.isPermanentlyDeleted) {
        throw StateError('This note is no longer available.');
      }
      if (canonical(note.background) != canonical(expected)) {
        throw StateError(
          'The background changed since then. Choose it again from Background.',
        );
      }
      saved = saveNote(
        uuid: uuid,
        expectedVersionVectorJson: note.versionVectorJson,
        title: note.title,
        content: note.content,
        tags: note.tags,
        attachmentPaths: note.attachments,
        background: background,
      );
    });
    return saved;
  }

  /// Saves a generated [html] page as the note's preview, keeping its content,
  /// if the note still has [expectedVersion].
  NoteEntity setWebsite({
    required String uuid,
    required String expectedVersion,
    required String html,
    required String sourceHash,
  }) {
    if (html.trim().isEmpty ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sourceHash)) {
      throw StateError('Invalid website. Your note is unchanged.');
    }
    return _present(uuid, expectedVersion: expectedVersion, (note) {
      note
        ..website = html
        ..websiteSourceHash = sourceHash
        ..presentationMode = 'html';
    });
  }

  /// Removes the note's website; its preview returns to the content.
  NoteEntity clearWebsite(String uuid) => _present(uuid, (note) {
    note
      ..website = ''
      ..websiteSourceHash = '';
    if (note.presentationMode == 'html') note.presentationMode = '';
  });

  /// Records the chosen presentation. Markdown has no separate page, so
  /// choosing it removes any website.
  NoteEntity setPresentationMode(String uuid, String mode) {
    if (!const {'', 'markdown', 'html'}.contains(mode)) {
      throw StateError('Unknown presentation.');
    }
    return _present(uuid, (note) {
      note.presentationMode = mode;
      if (mode == 'markdown') {
        note
          ..website = ''
          ..websiteSourceHash = '';
      }
    });
  }

  NoteEntity _present(
    String uuid,
    void Function(NoteEntity note) change, {
    String? expectedVersion,
  }) {
    _editable();
    late NoteEntity saved;
    _db.store.runInTransaction(TxMode.write, () {
      final note = getNoteByUuid(uuid);
      if (note == null || note.isDeleted || note.isPermanentlyDeleted) {
        throw StateError('This note is no longer available.');
      }
      if (expectedVersion != null &&
          !note.versionVector.isEqualTo(
            VersionVector.fromJsonString(expectedVersion),
          )) {
        throw StateError(
          'The note changed. Generate its website again from the new text.',
        );
      }
      change(note);
      note
        ..updatedAt = sync.now()
        ..lastEditedByDeviceId = device
        ..versionVector = note.versionVector.increment(device)
        ..status = SyncStatus.pendingUpload;
      _persist(note);
      saved = note;
    });
    return saved;
  }

  /// Every attachment path on any stored note, including notes in Trash.
  Set<String> allAttachmentPaths() => {
    for (final note in _box.getAll())
      for (final attachment in note.attachments)
        if (attachment['path'] case final String path) path,
  };

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
