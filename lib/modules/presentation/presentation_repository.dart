import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/objectbox/objectbox.dart';
import 'package:journal/objectbox/objectbox.g.dart';
import 'package:sync_wise/sync_wise.dart';

import 'presentation_contract.dart';
import 'presentation_entity.dart';

final presentationRepositoryProvider = Provider(
  (ref) => PresentationRepository(
    ref.watch(objectBoxProvider),
    ref.watch(syncStateStoreProvider),
  ),
);
final presentationRecordProvider =
    StreamProvider.family<PresentationEntity?, String>(
      (ref, key) => ref.watch(presentationRepositoryProvider).watch(key),
    );

final presentationSourceProvider =
    StreamProvider.family<PresentationSnapshot?, PresentationSourceRef>(
      (ref, source) =>
          ref.watch(presentationRepositoryProvider).watchSource(source),
    );

class PresentationRepository {
  PresentationRepository(this.db, this.sync);
  final ObjectBox db;
  final SyncStateStore sync;
  Box<PresentationEntity> get box => db.store.box<PresentationEntity>();
  PresentationEntity? get(String key) {
    final query = box.query(PresentationEntity_.sourceKey.equals(key)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  Stream<PresentationEntity?> watch(String key) => box
      .query(PresentationEntity_.sourceKey.equals(key))
      .watch(triggerImmediately: true)
      .map((q) => q.findFirst());
  Stream<PresentationSnapshot?> watchSource(PresentationSourceRef sourceRef) =>
      (sourceRef.kind == 'note'
              ? db.noteBox
                    .query(NoteEntity_.uuid.equals(sourceRef.id))
                    .watch(triggerImmediately: true)
              : db.diaryBox
                    .query(DiaryDayEntity_.dateString.equals(sourceRef.day!))
                    .watch(triggerImmediately: true))
          .map((_) => source(sourceRef));
  PresentationSnapshot? source(PresentationSourceRef ref) {
    if (ref.kind == 'note') {
      final query = db.noteBox.query(NoteEntity_.uuid.equals(ref.id)).build();
      final note = query.findFirst();
      query.close();
      if (note == null || note.isDeleted || note.isPermanentlyDeleted) {
        return null;
      }
      return PresentationSnapshot(ref, note.content, note.versionVectorJson);
    }
    final query = db.diaryBox
        .query(DiaryDayEntity_.dateString.equals(ref.day!))
        .build();
    final day = query.findFirst();
    query.close();
    if (day == null || day.isDeleted) return null;
    final item = day.items
        .where((i) => i.itemUuid == ref.id && !i.isDeleted)
        .firstOrNull;
    return item == null
        ? null
        : PresentationSnapshot(ref, item.content, jsonEncode(item.toJson()));
  }

  bool matches(PresentationSnapshot snapshot) =>
      source(snapshot.ref)?.encode() == snapshot.encode();
  void _editable() {
    if (!sync.canEdit) {
      throw StateError('Presentations are read-only on this device.');
    }
  }

  void accept({
    required String taskId,
    required PresentationSnapshot snapshot,
    required SafePresentationDocument document,
  }) {
    _editable();
    final blocks = PresentationBlocks(
      snapshot.content,
      markdown: snapshot.ref.kind == 'note',
    );
    final validated = SafePresentationDocument.decode(
      document.encode(),
      blocks.nodes.length,
    );
    db.store.runInTransaction(TxMode.write, () {
      _editable();
      if (!matches(snapshot)) {
        throw StateError('The source changed. Generate a new presentation.');
      }
      final previous = get(snapshot.ref.key);
      if (previous?.taskId == taskId) {
        throw StateError('This presentation was already accepted.');
      }
      box.put(
        PresentationEntity(
          id: previous?.id ?? 0,
          sourceKey: snapshot.ref.key,
          snapshot: snapshot.encode(),
          document: validated.encode(),
          taskId: taskId,
          created: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    });
  }

  void revert(PresentationSourceRef ref) {
    db.store.runInTransaction(TxMode.write, () {
      _editable();
      final row = get(ref.key);
      if (row != null) {
        row.enabled = false;
        box.put(row);
      }
    });
  }

  void remove(PresentationSourceRef ref) {
    _editable();
    final row = get(ref.key);
    if (row != null) box.remove(row.id);
  }
}
