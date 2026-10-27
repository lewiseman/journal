import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/objectbox/objectbox.g.dart';

import 'summary_task_entity.dart';
import '../transform/transform_contract.dart';
import '../../presentation/presentation_contract.dart';
import '../../diary/history/diary_history_contract.dart';
import '../../diary/questions/daily_question_contract.dart';
import '../../diary/suggestions/diary_suggestion_contract.dart';

// Shared saved-note AI slot, separate from trust and sync. One recoverable preview per phone.
class SummaryHandle {
  const SummaryHandle({
    required this.id,
    required this.noteId,
    required this.revision,
    required this.computerId,
    required this.created,
    this.pendingText,
    this.operation = 'summarize-note',
    this.localSource,
    this.presentationSource,
    this.accepted = false,
    this.cancelWanted = false,
    this.deviceId = '',
    this.phase = 'submitting',
    this.ackPending = false,
    this.acknowledged = false,
  });
  final String id, noteId, revision, computerId;
  final int created;
  final String? pendingText;
  final bool accepted, cancelWanted;
  final String deviceId, phase;
  final bool ackPending, acknowledged;
  final String operation;
  final String? localSource;
  final PresentationSourceRef? presentationSource;
  bool get isPresentation => operation == presentationOperation;
  bool get isTransformation => transformOperations.containsKey(operation);

  /// J01 diary-day suggestions. [noteId] holds the civil date key.
  bool get isDiarySuggestion => operation == diarySuggestionOperation;

  /// J02 daily questions. [noteId] holds the civil date the question is for.
  bool get isDailyQuestion => operation == dailyQuestionOperation;

  /// S01 historical answers. [noteId] holds the civil date asked on.
  bool get isDiaryAnswer => operation == historyOperation;

  /// Diary tasks keyed by a civil date rather than a note UUID.
  bool get isDiaryDay => isDiarySuggestion || isDailyQuestion || isDiaryAnswer;
  int get expires => created + const Duration(hours: 24).inMilliseconds;
  bool get expired =>
      DateTime.now().millisecondsSinceEpoch >=
      created + const Duration(hours: 24).inMilliseconds;
  SummaryHandle copyWith({
    bool? accepted,
    bool? cancelWanted,
    String? phase,
    String? deviceId,
    bool? ackPending,
    bool? acknowledged,
    bool dropSource = false,
  }) => SummaryHandle(
    id: id,
    operation: operation,
    localSource: dropSource ? null : localSource,
    presentationSource: presentationSource,
    noteId: noteId,
    revision: revision,
    computerId: computerId,
    created: created,
    pendingText: (accepted ?? this.accepted) ? null : pendingText,
    accepted: accepted ?? this.accepted,
    cancelWanted: cancelWanted ?? this.cancelWanted,
    phase: phase ?? this.phase,
    deviceId: deviceId ?? this.deviceId,
    ackPending: ackPending ?? this.ackPending,
    acknowledged: acknowledged ?? this.acknowledged,
  );
  SummaryHandle acceptedCopy() => copyWith(accepted: true);
  SummaryHandle cancelling() => copyWith(cancelWanted: true);
  Map<String, dynamic> toJson() => {
    'id': id,
    'operation': operation,
    'noteId': noteId,
    'revision': revision,
    'computerId': computerId,
    'created': created,
    'pendingText': pendingText,
    'localSource': localSource,
    if (presentationSource != null)
      'presentationSource': presentationSource!.toJson(),
    'accepted': accepted,
    'cancelWanted': cancelWanted,
    'deviceId': deviceId,
    'phase': phase,
    'ackPending': ackPending,
    'acknowledged': acknowledged,
  };
  factory SummaryHandle.fromJson(Map<String, dynamic> json) {
    final handle = SummaryHandle(
      id: json['id'] as String,
      operation: json['operation'] as String? ?? 'summarize-note',
      localSource: json['localSource'] as String?,
      presentationSource: json['presentationSource'] == null
          ? null
          : PresentationSourceRef.fromJson(
              json['presentationSource'] as Map<String, dynamic>,
            ),
      noteId: json['noteId'] as String,
      revision: json['revision'] as String,
      computerId: json['computerId'] as String,
      created: json['created'] as int,
      pendingText: json['pendingText'] as String?,
      accepted: json['accepted'] as bool,
      cancelWanted: json['cancelWanted'] as bool,
      deviceId: json['deviceId'] as String? ?? '',
      phase: json['phase'] as String? ?? 'retrieving',
      ackPending: json['ackPending'] as bool? ?? false,
      acknowledged: json['acknowledged'] as bool? ?? false,
    );
    if ((!handle.isTransformation &&
            !handle.isPresentation &&
            !handle.isDiaryDay &&
            handle.operation != 'summarize-note') ||
        (handle.isDiaryDay &&
            !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(handle.noteId)) ||
        !RegExp(r'^[a-zA-Z0-9_-]{8,80}$').hasMatch(handle.id) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(handle.revision) ||
        handle.noteId.length > 80 ||
        handle.computerId.length > 80 ||
        utf8.encode(handle.pendingText ?? '').length > 2000) {
      throw const FormatException('Invalid summary handle');
    }
    if (handle.isPresentation && handle.presentationSource == null) {
      throw const FormatException('Missing presentation source');
    }
    if (handle.localSource != null) {
      if (handle.isPresentation) {
        final snapshot = PresentationSnapshot.decode(handle.localSource!);
        if (snapshot.ref.key != handle.presentationSource!.key) {
          throw const FormatException('Mismatched source');
        }
      } else if (handle.isDiarySuggestion) {
        if (DiarySuggestionSource.decode(handle.localSource!).date !=
            handle.noteId) {
          throw const FormatException('Mismatched source');
        }
      } else if (handle.isDailyQuestion) {
        if (DailyQuestionSource.decode(handle.localSource!).date !=
            handle.noteId) {
          throw const FormatException('Mismatched source');
        }
      } else if (handle.isDiaryAnswer) {
        if (DiaryHistorySelection.decode(handle.localSource!).today !=
            handle.noteId) {
          throw const FormatException('Mismatched source');
        }
      } else {
        TransformSource.decode(handle.localSource!);
      }
    }
    return handle;
  }
}

abstract class SummaryStore {
  Future<SummaryHandle?> load();
  Future<void> save(SummaryHandle? handle);
  Future<List<SummaryHandle>> history() async => [?await load()];
  Future<void> clearAll() => save(null);
  Future<void> updateReceipt(SummaryHandle handle) async {}
}

final summaryStoreProvider = Provider<SummaryStore>(
  (ref) => ObjectBoxSummaryStore(ref.watch(objectBoxProvider).store),
);

class ProtectedSummaryStore extends SummaryStore {
  ProtectedSummaryStore({this.key = 'journal.companion.summary.v1'});
  final String key;
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      storageNamespace: 'journal_companion',
      resetOnError: false,
    ),
    iOptions: IOSOptions(
      accountName: 'journal.companion',
      accessibility: KeychainAccessibility.unlocked_this_device,
      synchronizable: false,
    ),
  );
  Future<void> _tail = Future.value();
  @override
  Future<SummaryHandle?> load() async {
    await _tail;
    final raw = await _storage.read(key: key);
    final handle = raw == null
        ? null
        : SummaryHandle.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    return handle;
  }

  @override
  Future<void> save(SummaryHandle? handle) {
    final next = _tail.then(
      (_) => handle == null
          ? _storage.delete(key: key)
          : _storage.write(key: key, value: jsonEncode(handle.toJson())),
    );
    _tail = next.catchError((Object _) {});
    return next;
  }
}

/// One active protected snapshot plus bounded local-only ObjectBox history.
/// Secure writes precede metadata commits; interrupted writes are imported on load.
class ObjectBoxSummaryStore extends SummaryStore {
  ObjectBoxSummaryStore(this.db, {SummaryStore? protected})
    : protected = protected ?? ProtectedSummaryStore();
  final Store db;
  final SummaryStore protected;
  Box<SummaryTaskEntity> get _box => db.box<SummaryTaskEntity>();
  SummaryHandle _decode(SummaryTaskEntity row) =>
      SummaryHandle.fromJson(jsonDecode(row.metadata) as Map<String, dynamic>);
  void _put(SummaryHandle handle, {required bool active}) {
    final query = _box
        .query(SummaryTaskEntity_.taskId.equals(handle.id))
        .build();
    final previous = query.findFirst();
    query.close();
    final metadata = handle.toJson()
      ..remove('pendingText')
      ..remove('localSource');
    _box.put(
      SummaryTaskEntity(
        id: previous?.id ?? 0,
        taskId: handle.id,
        created: handle.created,
        active: active,
        metadata: jsonEncode(metadata),
      ),
    );
  }

  @override
  Future<SummaryHandle?> load() async {
    var handle = await protected.load();
    if (handle == null) {
      final query = _box.query(SummaryTaskEntity_.active.equals(true)).build();
      final row = query.findFirst();
      query.close();
      if (row != null) handle = _decode(row);
    }
    if (handle != null) {
      if (handle.created + const Duration(days: 7).inMilliseconds <=
          DateTime.now().millisecondsSinceEpoch) {
        await save(null);
        final query = _box
            .query(SummaryTaskEntity_.taskId.equals(handle.id))
            .build();
        query.remove();
        query.close();
        return null;
      }
      if (handle.expired) {
        handle = handle.copyWith(
          accepted: true,
          phase: 'expired',
          dropSource: true,
        );
      }
      // Also migrates the existing v1 secure handle without resubmission.
      await save(handle);
    }
    return handle;
  }

  @override
  Future<void> save(SummaryHandle? handle) async {
    await protected.save(handle);
    db.runInTransaction(TxMode.write, () {
      final query = _box.query(SummaryTaskEntity_.active.equals(true)).build();
      final active = query.find();
      query.close();
      for (final row in active) {
        row.active = false;
        _box.put(row);
      }
      if (handle != null) _put(handle, active: true);
    });
  }

  @override
  Future<List<SummaryHandle>> history() async {
    final rows = _box.getAll();
    final now = DateTime.now().millisecondsSinceEpoch;
    final result = <SummaryHandle>[];
    for (final row in rows) {
      if (row.created + const Duration(days: 7).inMilliseconds <= now) {
        _box.remove(row.id);
        continue;
      }
      var handle = _decode(row);
      if (handle.expired && !handle.acknowledged) {
        handle = handle.copyWith(
          accepted: true,
          phase: 'expired',
          dropSource: true,
          ackPending: false,
        );
        _put(handle, active: row.active);
      }
      result.add(handle);
    }
    return result..sort((a, b) => b.created.compareTo(a.created));
  }

  @override
  Future<void> updateReceipt(SummaryHandle handle) async {
    _put(handle, active: false);
  }

  @override
  Future<void> clearAll() async {
    await protected.clearAll();
    _box.removeAll();
  }
}
