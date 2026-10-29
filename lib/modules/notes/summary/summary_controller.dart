import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/models/note_entity.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';

import 'summary_store.dart';
import '../transform/transform_contract.dart';
import '../metadata/note_help_contract.dart';
import '../images/note_image_contract.dart';
import '../images/note_scan.dart';
import '../images/note_background_gen.dart';

import 'package:journal/modules/notes/models/note_attachment.dart';

import 'package:journal/modules/notes/models/note_tag.dart';

import '../../presentation/website_contract.dart';

import 'package:journal/modules/diary/controllers/diary_providers.dart';
import 'package:journal/modules/diary/history/diary_history_contract.dart';
import 'package:journal/modules/notes/question/note_question_contract.dart';
import 'package:journal/modules/diary/questions/daily_question_contract.dart';
import 'package:journal/modules/diary/photo_questions/diary_photo_question_contract.dart';
import 'package:journal/modules/diary/photo_questions/diary_photo_question_store.dart';
import 'package:journal/modules/diary/suggestions/diary_suggestion_contract.dart';
import 'package:journal/modules/flow/controllers/thoughts_providers.dart';
import 'package:journal/modules/flow/reflection/thought_reflection_contract.dart';

const summaryInputBytes = 2000;
const summaryOutputBytes = 2048;
String summaryNoteText(NoteEntity note) =>
    '${note.title}\n\n${note.content}'.trim();
Future<String> summaryRevision(NoteEntity note) => hexHash(
  utf8.encode(
    jsonEncode([
      note.uuid,
      note.createdAt.toIso8601String(),
      note.updatedAt.toIso8601String(),
      note.versionVectorJson,
      note.title,
      note.content,
      note.isDeleted,
      note.isPermanentlyDeleted,
    ]),
  ),
);
bool validSummaryText(String text, int limit) =>
    text.trim().isNotEmpty &&
    utf8.encode(text).length <= limit &&
    !RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]').hasMatch(text) &&
    const Utf8Encoder().convert(text).isNotEmpty &&
    _wellFormed(text);
bool _wellFormed(String text) {
  try {
    const Utf8Decoder(allowMalformed: false).convert(utf8.encode(text));
    // Dart replaces unmatched surrogates during encoding; explicitly refuse them.
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++i == text.length ||
            text.codeUnitAt(i) < 0xdc00 ||
            text.codeUnitAt(i) > 0xdfff) {
          return false;
        }
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        return false;
      }
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// The connected computer when it advertises [operation] at [contract].
TrustedComputer capableComputer(
  CompanionState connection, {
  required String contractKey,
  required int contract,
  required String operation,
  required String fallback,
  required String update,
  String capabilityId = 'text',
  String notReady = 'Load the writing model on your computer.',
  String notReadyCode = 'NOT_READY',
}) {
  final computer = connection.selected;
  if (computer == null ||
      !computer.enabled ||
      connection.phase != CompanionPhase.connected) {
    throw CompanionFailure(
      'UNAVAILABLE',
      'Connect your trusted computer in More → Local QVAC. $fallback',
    );
  }
  final capabilities = connection.status?['capabilities'] as List? ?? [];
  final capability = capabilities
      .whereType<Map>()
      .where((c) => c['id'] == capabilityId)
      .firstOrNull;
  if (connection.status?['recovery'] != 1 ||
      capability?[contractKey] != contract ||
      capability?['operations'] is! List ||
      !(capability!['operations'] as List).contains(operation)) {
    throw CompanionFailure('INCOMPATIBLE_VERSION', update);
  }
  if (!['ready', 'busy'].contains(capability['status'])) {
    throw CompanionFailure(notReadyCode, '$notReady $fallback');
  }
  return computer;
}

class NoteSummaryState {
  const NoteSummaryState({
    this.handle,
    this.phase = 'idle',
    this.message,
    this.text,
    this.stale = false,
    this.busy = false,
  });
  final SummaryHandle? handle;
  final String phase;
  final String? message, text;
  final bool stale, busy;
  bool get terminal => [
    'completed',
    'cancelled',
    'failed',
    'interrupted',
    'expired',
  ].contains(phase);
}

final noteSummaryProvider =
    NotifierProvider<NoteSummaryController, NoteSummaryState>(
      NoteSummaryController.new,
    );

final summaryHistoryProvider = FutureProvider<List<SummaryHandle>>((ref) {
  if (ref.watch(accountResetProvider).blocksDataAccess) return [];
  return ref.watch(summaryStoreProvider).history();
});

class NoteSummaryController extends Notifier<NoteSummaryState> {
  Timer? _poll;
  StreamSubscription<Object?>? _source;
  String? _watchedNote;
  AppLifecycleListener? _lifecycle;
  int _generation = 0;
  bool _working = false, _foreground = true;

  /// Completes when the in-flight [retry] finishes.
  Completer<void>? _idle;
  Future<void>? _restoration;
  bool get _blocked => ref.read(accountResetProvider).blocksDataAccess;
  SummaryStore get _store => ref.read(summaryStoreProvider);
  CompanionClient get _client =>
      CompanionClient(ref.read(companionTransportProvider));
  @override
  NoteSummaryState build() {
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _lifecycle = AppLifecycleListener(
      onStateChange: (value) {
        _foreground = value == AppLifecycleState.resumed;
        _poll?.cancel();
        if (_foreground) unawaited(reconcile());
      },
    );
    ref.listen(accountResetProvider, (previous, next) {
      if (next.blocksDataAccess) {
        _generation++;
        _poll?.cancel();
        state = const NoteSummaryState();
        _watchSource(null);
      } else if (previous?.blocksDataAccess == true && !next.completed) {
        scheduleMicrotask(() {
          if (ref.mounted) unawaited(restore());
        });
      }
    });
    ref.listen(companionControllerProvider, (previous, next) {
      if (next.phase == CompanionPhase.connected &&
          (previous?.phase != next.phase ||
              previous?.selected?.endpoint != next.selected?.endpoint)) {
        scheduleMicrotask(() {
          if (ref.mounted) unawaited(reconcile());
        });
      }
    });
    ref.onDispose(() {
      _generation++;
      _poll?.cancel();
      _lifecycle?.dispose();
      unawaited(_source?.cancel());
    });
    scheduleMicrotask(() {
      if (ref.mounted) unawaited(restore());
    });
    return const NoteSummaryState(phase: 'restoring', busy: true);
  }

  bool _alive(int generation) =>
      ref.mounted && generation == _generation && !_blocked;

  /// How long a user action waits for in-flight work before reporting busy.
  @visibleForTesting
  static Duration settleLimit = const Duration(seconds: 25);

  static const _busyMessage =
      'Your computer is still finishing the previous request. Nothing new was sent; try again in a moment.';

  /// Waits a bounded time for an in-flight retrieval or restore, so a user
  /// action right after one is not dropped.
  Future<void> _settle() async {
    final limit = settleLimit;
    final restoration = _restoration;
    if (restoration != null) {
      await restoration.timeout(limit, onTimeout: () {});
    }
    final idle = _idle;
    if (_working && idle != null) {
      await idle.future.timeout(limit, onTimeout: () {});
    }
  }

  /// Whether a new task may start now. A busy controller says so in [state];
  /// a slot owned by another task is left alone, since its page explains it.
  Future<bool> _readyToStart() async {
    if (_blocked) return false;
    await _settle();
    if (!ref.mounted || _blocked || state.handle != null) return false;
    if (_working || state.busy) {
      _show(state.phase, text: state.text, message: _busyMessage, busy: true);
      return false;
    }
    return true;
  }

  Future<void> _save(SummaryHandle? handle) async {
    await _store.save(handle);
    if (ref.mounted) ref.invalidate(summaryHistoryProvider);
  }

  Future<void> reconcile() async {
    await retry();
    if (!ref.mounted || _blocked || !_foreground) return;
    final generation = _generation;
    try {
      for (final handle in await _store.history()) {
        if (!_alive(generation) || !_foreground) return;
        if (handle.ackPending && !handle.expired) await acknowledge(handle);
      }
      if (_alive(generation)) ref.invalidate(summaryHistoryProvider);
    } catch (_) {
      /* Retain receipts for an explicit retry or next reconnect. */
    }
  }

  Future<void> acknowledge(SummaryHandle handle) async {
    final generation = _generation;
    if (_blocked || !_foreground || handle.expired) return;
    try {
      await _client.authenticated(
        _computer(handle),
        'POST',
        '/v1/jobs/${handle.id}/ack',
        body: {},
      );
      if (!_alive(generation)) return;
      await _store.updateReceipt(
        handle.copyWith(ackPending: false, acknowledged: true),
      );
      if (_alive(generation)) ref.invalidate(summaryHistoryProvider);
    } catch (_) {
      /* Keep ackPending; remote expiry remains bounded. */
    }
  }

  void _show(
    String phase, {
    SummaryHandle? handle,
    String? text,
    String? message,
    bool busy = false,
    bool? stale,
  }) {
    state = NoteSummaryState(
      handle: handle ?? state.handle,
      phase: phase,
      text: text,
      message: message,
      busy: busy,
      stale: stale ?? state.stale,
    );
    _watchSource(state.handle);
  }

  void _watchSource(SummaryHandle? handle) {
    final key =
        (handle?.isThoughtReflection == true
            ? 'thought:${handle!.noteId}'
            : null) ??
        (handle?.isDiaryDay == true || handle?.isNoteQuestion == true
            ? '${handle!.operation}:${handle.noteId}'
            : handle?.noteId);
    if (_watchedNote == key) return;
    unawaited(_source?.cancel());
    _source = null;
    _watchedNote = key;
    if (handle != null && !handle.isDiaryPhoto) {
      final Stream<Object?> stream = handle.isThoughtReflection
          ? ref.read(thoughtsRepositoryProvider).watchThoughts()
          : handle.isDiaryDay
          ? ref.read(diaryRepositoryProvider).watchAllDays()
          : handle.isNoteQuestion
          ? ref.read(notesRepositoryProvider).watchActiveNotes()
          : ref.read(notesRepositoryProvider).watchNoteByUuid(handle.noteId);
      _source = stream.listen((_) {
        unawaited(refreshSource());
      });
    }
  }

  Future<void> restore() {
    final pending = _restoration;
    if (pending != null) return pending;
    final future = _restore();
    _restoration = future;
    return future.whenComplete(() => _restoration = null);
  }

  Future<void> _restore() async {
    final generation = _generation;
    try {
      await ref.read(accountResetProvider.notifier).ready;
      if (!_alive(generation)) return;
      final handle = await _store.load();
      if (!_alive(generation)) return;
      if (handle == null) {
        state = const NoteSummaryState();
        _watchSource(null);
        await reconcile();
        return;
      }
      _show(handle.phase, handle: handle);
      await refreshSource();
      await reconcile();
    } catch (_) {
      if (_alive(generation)) {
        _show(
          'storageError',
          message: 'Could not unlock the saved note request. Unlock the phone and retry.',
        );
      }
    }
  }

  Future<bool> _matches(SummaryHandle handle) async {
    if (handle.isDiaryAnswer) {
      // Unchanged when every sent excerpt's entry still has its version.
      final diary = ref.read(diaryRepositoryProvider);
      final selection = handle.localSource == null
          ? null
          : DiaryHistorySelection.decode(handle.localSource!);
      return selection != null &&
          selection.sources.every(
            (s) => sourceStatus(s, diary.getDay) == DiarySourceStatus.current,
          );
    }
    if (handle.isNoteQuestion) {
      // Unchanged when every sent note still has its version.
      final notes = ref.read(notesRepositoryProvider);
      final selection = handle.localSource == null
          ? null
          : NoteQuestionSelection.decode(handle.localSource!);
      return selection != null &&
          selection.sources.every(
            (s) =>
                noteSourceStatus(s, notes.getNoteByUuid) ==
                NoteSourceStatus.current,
          );
    }
    if (handle.isDailyQuestion) {
      // Unchanged when every selected entry still exists with the same text.
      final diary = ref.read(diaryRepositoryProvider);
      final source = handle.localSource == null
          ? null
          : DailyQuestionSource.decode(handle.localSource!);
      return source != null &&
          [...source.today, ...source.prior].every(
            (e) =>
                diary
                    .getDay(e.date)
                    ?.visibleItems
                    .where((i) => i.itemUuid == e.uuid)
                    .firstOrNull
                    ?.content ==
                e.text,
          );
    }
    if (handle.isThoughtReflection) {
      final thought = ref
          .read(thoughtsRepositoryProvider)
          .getThoughtByUuid(handle.noteId);
      return thought != null && thoughtRevision(thought) == handle.revision;
    }
    if (handle.isDiarySuggestion) {
      final source = DiarySuggestionSource.fromDay(
        ref.read(diaryRepositoryProvider).getDay(handle.noteId),
      );
      return source != null &&
          await hexHash(utf8.encode(source.encode())) == handle.revision;
    }
    if (handle.isNoteIdeas) return true;
    // The saved upload is the snapshot; it is checked against its hash on retry.
    if (handle.isDiaryPhoto) return true;
    if (handle.isNoteBackground) {
      final request = handle.localSource == null
          ? null
          : NoteBackgroundRequest.decode(handle.localSource!);
      final note = ref
          .read(notesRepositoryProvider)
          .getNoteByUuid(handle.noteId);
      return request != null &&
          note != null &&
          !note.isDeleted &&
          !note.isPermanentlyDeleted &&
          canonicalBackground(note.background) ==
              canonicalBackground(request.background);
    }
    if (handle.isNoteScan) {
      final source = handle.localSource == null
          ? null
          : NoteScanRequest.decode(handle.localSource!);
      final note = ref
          .read(notesRepositoryProvider)
          .getNoteByUuid(handle.noteId);
      return source != null &&
          note != null &&
          !note.isDeleted &&
          note.versionVectorJson == source.version &&
          File(source.path).existsSync();
    }
    if (handle.isNoteImage) {
      final source = handle.localSource == null
          ? null
          : NoteImageRequest.decode(handle.localSource!);
      final note = ref
          .read(notesRepositoryProvider)
          .getNoteByUuid(handle.noteId);
      return source != null &&
          note?.versionVectorJson == source.version &&
          noteImageAttachment(note, source.path) != null;
    }
    if (handle.isNoteMetadata) {
      return handle.localSource != null &&
          NoteMetadataSource.decode(handle.localSource!).matches(
            ref.read(notesRepositoryProvider).getNoteByUuid(handle.noteId),
          );
    }
    if (handle.isNoteWebsite) {
      if (handle.localSource == null) return false;
      final request = WebsiteRequest.decode(handle.localSource!);
      final note = ref
          .read(notesRepositoryProvider)
          .getNoteByUuid(handle.noteId);
      return note != null &&
          !note.isDeleted &&
          !note.isPermanentlyDeleted &&
          note.versionVectorJson == request.version &&
          note.content == request.content;
    }
    final note = ref.read(notesRepositoryProvider).getNoteByUuid(handle.noteId);
    return note != null &&
        !note.isDeleted &&
        !note.isPermanentlyDeleted &&
        await summaryRevision(note) == handle.revision;
  }

  /// A self-contained website from saved note [noteId], shown as its
  /// preview. Only the title, content and [description] are sent.
  Future<void> startNoteWebsite(String noteId, String description) async {
    if (!await _readyToStart()) return;
    final generation = ++_generation;
    _show('submitting', busy: true, stale: false);
    try {
      final repository = ref.read(notesRepositoryProvider);
      if (!repository.sync.canEdit) {
        throw const CompanionFailure(
          'READ_ONLY',
          'Existing notes are read-only on this device, so a website cannot be saved here. Nothing was sent.',
        );
      }
      final note = repository.getNoteByUuid(noteId);
      if (note == null || note.isDeleted || note.isPermanentlyDeleted) {
        throw const CompanionFailure(
          'SOURCE_MISSING',
          'This note is no longer available.',
        );
      }
      final request = WebsiteRequest(
        noteId: noteId,
        version: note.versionVectorJson,
        title: note.title,
        content: note.content,
        description: description,
      );
      final input = request.request();
      final computer = _capableComputer(
        contractKey: 'websiteContract',
        contract: noteWebsiteContract,
        operation: noteWebsiteOperation,
        fallback: 'Your note is unchanged.',
        update: 'Update the companion to make websites.',
      );
      await _submitNew(
        generation,
        noteId: noteId,
        local: request.encode(),
        input: input,
        operation: noteWebsiteOperation,
        computer: computer,
      );
    } catch (error) {
      if (_alive(generation)) {
        _failure(
          error is FormatException
              ? CompanionFailure('INPUT_LIMIT', error.message)
              : error,
        );
      }
    }
  }

  /// J01: sends only the selected day's saved entry text, after the same
  /// persisted-before-send recovery as every other task.
  Future<void> startDiarySuggestion(String dateString) async {
    if (!await _readyToStart()) return;
    final generation = ++_generation;
    _show('submitting', busy: true, stale: false);
    try {
      final repository = ref.read(diaryRepositoryProvider);
      if (!repository.sync.canEdit) {
        throw const CompanionFailure(
          'READ_ONLY',
          'Diary details can be suggested and saved only on the primary device. Nothing was sent.',
        );
      }
      final source = DiarySuggestionSource.fromDay(
        repository.getDay(dateString),
      );
      if (source == null) {
        throw const CompanionFailure(
          'SOURCE_MISSING',
          'This day has no saved entries to suggest from.',
        );
      }
      final input = source.request();
      final computer = _capableComputer(
        contractKey: 'diaryContract',
        contract: diarySuggestionContract,
        operation: diarySuggestionOperation,
        fallback: 'You can still edit details yourself.',
        update: 'Update the companion to support diary suggestions.',
      );
      final handle = SummaryHandle(
        id: const Uuid().v4(),
        noteId: dateString,
        revision: await hexHash(utf8.encode(source.encode())),
        computerId: computer.id,
        deviceId: computer.deviceId,
        created: DateTime.now().millisecondsSinceEpoch,
        pendingText: input,
        operation: diarySuggestionOperation,
        localSource: source.encode(),
      );
      if (!_alive(generation)) return;
      await _save(handle);
      if (!_alive(generation)) return;
      _show('submitting', handle: handle, busy: true);
      await retry();
    } catch (error) {
      if (_alive(generation)) {
        _failure(
          error is FormatException
              ? CompanionFailure('INPUT_LIMIT', error.message)
              : error,
        );
      }
    }
  }

  TrustedComputer _capableComputer({
    required String contractKey,
    required int contract,
    required String operation,
    required String fallback,
    required String update,
    String capabilityId = 'text',
    String notReady = 'Load the writing model on your computer.',
    String notReadyCode = 'NOT_READY',
  }) => capableComputer(
    ref.read(companionControllerProvider),
    contractKey: contractKey,
    contract: contract,
    operation: operation,
    fallback: fallback,
    update: update,
    capabilityId: capabilityId,
    notReady: notReady,
    notReadyCode: notReadyCode,
  );

  /// S01: one grounded answer about the past from [selection]'s excerpts.
  /// Read-only, so secondary devices may ask too.
  Future<void> startDiaryAnswer(DiaryHistorySelection selection) async {
    if (!await _readyToStart()) return;
    final generation = ++_generation;
    _show('submitting', busy: true, stale: false);
    try {
      if (!selection.sendable) {
        throw const CompanionFailure(
          'SOURCE_MISSING',
          'No entries matched, so nothing was sent.',
        );
      }
      final input = selection.request();
      if (utf8.encode(input).length > historyInputBytes) {
        throw const FormatException(
          'The selected excerpts exceed 2,000 UTF-8 bytes. Nothing was sent.',
        );
      }
      final computer = _capableComputer(
        contractKey: 'historyContract',
        contract: historyContract,
        operation: historyOperation,
        fallback: 'Keyword search still works without it.',
        update: 'Update the companion to answer diary questions.',
      );
      final local = selection.encode();
      final handle = SummaryHandle(
        id: const Uuid().v4(),
        noteId: selection.today,
        revision: await hexHash(utf8.encode(local)),
        computerId: computer.id,
        deviceId: computer.deviceId,
        created: DateTime.now().millisecondsSinceEpoch,
        pendingText: input,
        operation: historyOperation,
        localSource: local,
      );
      if (!_alive(generation)) return;
      await _save(handle);
      if (!_alive(generation)) return;
      _show('submitting', handle: handle, busy: true);
      await retry();
    } catch (error) {
      if (_alive(generation)) {
        _failure(
          error is FormatException
              ? CompanionFailure('INPUT_LIMIT', error.message)
              : error,
        );
      }
    }
  }

  /// S02: one grounded answer about saved notes from [selection]'s
  /// excerpts. Read-only, so secondary devices may ask too.
  Future<void> startNoteQuestion(NoteQuestionSelection selection) async {
    if (!await _readyToStart()) return;
    final generation = ++_generation;
    _show('submitting', busy: true, stale: false);
    try {
      if (!selection.sendable) {
        throw const CompanionFailure(
          'SOURCE_MISSING',
          'No notes matched, so nothing was sent.',
        );
      }
      final input = selection.request();
      if (utf8.encode(input).length > noteQuestionInputBytes) {
        throw const FormatException(
          'The selected excerpts exceed 2,000 UTF-8 bytes. Nothing was sent.',
        );
      }
      final computer = _capableComputer(
        contractKey: 'noteQuestionContract',
        contract: noteQuestionContract,
        operation: noteQuestionOperation,
        fallback: 'Keyword search on the Notes page still works without it.',
        update: 'Update the companion to answer questions about notes.',
      );
      final local = selection.encode();
      final handle = SummaryHandle(
        id: const Uuid().v4(),
        noteId: selection.today,
        revision: await hexHash(utf8.encode(local)),
        computerId: computer.id,
        deviceId: computer.deviceId,
        created: DateTime.now().millisecondsSinceEpoch,
        pendingText: input,
        operation: noteQuestionOperation,
        localSource: local,
      );
      if (!_alive(generation)) return;
      await _save(handle);
      if (!_alive(generation)) return;
      _show('submitting', handle: handle, busy: true);
      await retry();
    } catch (error) {
      if (_alive(generation)) {
        _failure(
          error is FormatException
              ? CompanionFailure('INPUT_LIMIT', error.message)
              : error,
        );
      }
    }
  }

  /// J02: one reflection question for [source]'s civil day. It writes no
  /// synced data, so secondary devices may ask too.
  Future<void> startDailyQuestion(DailyQuestionSource source) async {
    if (!await _readyToStart()) return;
    final generation = ++_generation;
    _show('submitting', busy: true, stale: false);
    try {
      final input = source.request();
      if (utf8.encode(input).length > dailyQuestionInputBytes) {
        throw const FormatException(
          'The selected entries exceed 2,000 UTF-8 bytes. Nothing was sent.',
        );
      }
      final computer = _capableComputer(
        contractKey: 'questionContract',
        contract: dailyQuestionContract,
        operation: dailyQuestionOperation,
        fallback: 'You can keep writing with the usual prompt.',
        update: 'Update the companion to ask daily questions.',
      );
      final local = source.encode();
      final handle = SummaryHandle(
        id: const Uuid().v4(),
        noteId: source.date,
        revision: await hexHash(utf8.encode(local)),
        computerId: computer.id,
        deviceId: computer.deviceId,
        created: DateTime.now().millisecondsSinceEpoch,
        pendingText: input,
        operation: dailyQuestionOperation,
        localSource: local,
      );
      if (!_alive(generation)) return;
      await _save(handle);
      if (!_alive(generation)) return;
      _show('submitting', handle: handle, busy: true);
      await retry();
    } catch (error) {
      if (_alive(generation)) {
        _failure(
          error is FormatException
              ? CompanionFailure('INPUT_LIMIT', error.message)
              : error,
        );
      }
    }
  }

  /// N02: title and tag suggestions grounded in one saved note. Only its
  /// title, body and tag names are sent; nothing is applied automatically.
  Future<void> startNoteMetadata(String noteId) async {
    if (!await _readyToStart()) return;
    final generation = ++_generation;
    _show('submitting', busy: true, stale: false);
    try {
      final repository = ref.read(notesRepositoryProvider);
      if (!repository.sync.canEdit) {
        throw const CompanionFailure(
          'READ_ONLY',
          'Existing notes are read-only on this device, so suggestions could not be applied. Nothing was sent.',
        );
      }
      final note = repository.getNoteByUuid(noteId);
      if (note == null || note.isDeleted || note.isPermanentlyDeleted) {
        throw const CompanionFailure(
          'SOURCE_MISSING',
          'This note is no longer available.',
        );
      }
      final source = NoteMetadataSource.fromNote(note);
      final input = source.request();
      final computer = _capableComputer(
        contractKey: 'noteHelpContract',
        contract: noteHelpContract,
        operation: noteMetadataOperation,
        fallback: 'You can still edit the title and tags yourself.',
        update: 'Update the companion to suggest titles and tags.',
      );
      final local = source.encode();
      await _submitNew(
        generation,
        noteId: noteId,
        local: local,
        input: input,
        operation: noteMetadataOperation,
        computer: computer,
      );
    } catch (error) {
      if (_alive(generation)) {
        _failure(
          error is FormatException
              ? CompanionFailure('INPUT_LIMIT', error.message)
              : error,
        );
      }
    }
  }

  /// N02: starting ideas from an optional topic and notes the user chose.
  /// Creates nothing, so secondary devices may ask too.
  Future<void> startNoteIdeas(NoteIdeaSource source) async {
    if (!await _readyToStart()) return;
    final generation = ++_generation;
    _show('submitting', busy: true, stale: false);
    try {
      final input = source.request();
      final computer = _capableComputer(
        contractKey: 'noteHelpContract',
        contract: noteHelpContract,
        operation: noteIdeasOperation,
        fallback: 'The idea shuffle still works without it.',
        update: 'Update the companion to suggest starting ideas.',
      );
      await _submitNew(
        generation,
        noteId: noteIdeasKey,
        local: source.encode(),
        input: input,
        operation: noteIdeasOperation,
        computer: computer,
      );
    } catch (error) {
      if (_alive(generation)) {
        _failure(
          error is FormatException
              ? CompanionFailure('INPUT_LIMIT', error.message)
              : error,
        );
      }
    }
  }

  /// I03: one question about one image attached to a saved note. Only the
  /// re-encoded image and {mode, question} are sent; nothing is applied.
  Future<void> startNoteImage(
    String noteId, {
    required String path,
    required String mode,
    String question = '',
  }) async {
    if (!await _readyToStart()) return;
    final generation = ++_generation;
    _show('submitting', busy: true, stale: false);
    try {
      NoteImageRequest.validate(mode, question);
      final note = ref.read(notesRepositoryProvider).getNoteByUuid(noteId);
      final attachment = noteImageAttachment(note, path);
      if (attachment == null) {
        throw const CompanionFailure(
          'SOURCE_MISSING',
          'This image is no longer attached to the saved note.',
        );
      }
      final computer = _capableComputer(
        capabilityId: 'vision',
        contractKey: 'visionContract',
        contract: noteImageContract,
        operation: noteImageOperation,
        fallback: 'Your note and image are unchanged.',
        update: 'Update the companion to ask about note images.',
        notReady:
            'Download Qwen3-VL and run the image self-test on your computer.',
        notReadyCode: 'VISION_NOT_READY',
      );
      final image = await prepareNoteImage(attachment);
      final source = NoteImageRequest(
        noteId: noteId,
        version: note!.versionVectorJson,
        path: path,
        mode: mode,
        question: question.trim(),
        imageSha: await hexHash(image),
      );
      await _submitNew(
        generation,
        noteId: noteId,
        local: source.encode(),
        input: source.request(),
        operation: noteImageOperation,
        computer: computer,
      );
    } catch (error) {
      if (_alive(generation)) {
        _failure(
          error is FormatException
              ? CompanionFailure('INPUT_LIMIT', error.message)
              : error,
        );
      }
    }
  }

  /// I02: reflection questions about one diary photo the user chose. Only the
  /// re-encoded photo and its caption are sent. It writes no synced data, so
  /// secondary devices may ask too. [photo] is the photo's saved bytes.
  Future<void> startDiaryPhotoQuestions({
    required String date,
    required String photoSha,
    required Uint8List photo,
    String caption = '',
    int group = -1,
    List<String> avoid = const [],
  }) async {
    if (!await _readyToStart()) return;
    final generation = ++_generation;
    _show('submitting', busy: true, stale: false);
    try {
      final computer = _capableComputer(
        capabilityId: 'vision',
        contractKey: 'photoContract',
        contract: diaryPhotoQuestionContract,
        operation: diaryPhotoQuestionOperation,
        fallback: 'The usual questions are still here.',
        update: 'Update the companion to ask about diary photos.',
        notReady:
            'Download Qwen3-VL and run the image self-test on your computer.',
        notReadyCode: 'VISION_NOT_READY',
      );
      final image = await prepareImageBytes(photo);
      final source = DiaryPhotoQuestionSource(
        date: date,
        photoSha: photoSha,
        imageSha: await hexHash(image),
        caption: DiaryPhotoQuestionSource.validateCaption(caption),
        group: group,
        avoid: avoid,
      );
      final id = const Uuid().v4();
      // The exact upload is kept until the task is cleared, so a retry after
      // an interrupted submission can resend it without the unsaved story.
      await ref.read(diaryPhotoQuestionStoreProvider).writeUpload(id, image);
      await _submitNew(
        generation,
        id: id,
        noteId: photoSha,
        local: source.encode(),
        input: source.request(),
        operation: diaryPhotoQuestionOperation,
        computer: computer,
      );
    } catch (error) {
      if (_alive(generation)) {
        _failure(
          error is FormatException
              ? CompanionFailure('INPUT_LIMIT', error.message)
              : error,
        );
      }
    }
  }

  Future<Uint8List> _diaryPhotoUpload(SummaryHandle handle) async {
    final source = DiaryPhotoQuestionSource.decode(handle.localSource!);
    final image = await ref
        .read(diaryPhotoQuestionStoreProvider)
        .readUpload(handle.id);
    if (image == null || await hexHash(image) != source.imageSha) {
      throw const CompanionFailure(
        'SOURCE_CHANGED',
        'The photo prepared for this request is no longer on this phone. Nothing was sent; ask about the photo again.',
      );
    }
    return image;
  }

  /// I06: generate a background from the user's own description and tone.
  /// No note text is sent; nothing changes until the preview is accepted.
  Future<void> startNoteBackground(
    String noteId, {
    required String prompt,
    required String tone,
  }) async {
    if (!await _readyToStart()) return;
    final generation = ++_generation;
    _show('submitting', busy: true, stale: false);
    try {
      final repository = ref.read(notesRepositoryProvider);
      if (!repository.sync.canEdit) {
        throw const CompanionFailure(
          'READ_ONLY',
          'Existing notes are read-only on this device, so their background cannot change. Nothing was sent.',
        );
      }
      final note = repository.getNoteByUuid(noteId);
      if (note == null || note.isDeleted || note.isPermanentlyDeleted) {
        throw const CompanionFailure(
          'SOURCE_MISSING',
          'This note is no longer available.',
        );
      }
      final request = NoteBackgroundRequest(
        noteId: noteId,
        prompt: prompt.trim(),
        tone: tone,
        background: Map.of(note.background),
      );
      final input = request.request();
      final computer = _capableComputer(
        capabilityId: 'image',
        contractKey: 'backgroundContract',
        contract: noteBackgroundContract,
        operation: noteBackgroundOperation,
        fallback: 'You can still choose a color or photo background.',
        update: 'Update the companion to generate backgrounds.',
        notReady: 'Download, assign and test an image model on your computer.',
        notReadyCode: 'IMAGE_NOT_READY',
      );
      await _submitNew(
        generation,
        noteId: noteId,
        local: request.encode(),
        input: input,
        operation: noteBackgroundOperation,
        computer: computer,
      );
    } catch (error) {
      if (_alive(generation)) {
        _failure(
          error is FormatException
              ? CompanionFailure('INPUT_LIMIT', error.message)
              : error,
        );
      }
    }
  }

  /// Collects the finished image into a local preview, verifying its digest.
  Future<void> _collectBackground(
    SummaryHandle handle,
    String text,
    TrustedComputer computer,
  ) async {
    final store = ref.read(noteBackgroundStoreProvider);
    if (await (await store.preview(handle.id)).exists()) return;
    final result = NoteBackgroundResult.parse(text);
    final response = await _client.authenticated(
      computer,
      'GET',
      '/v1/image-jobs/${handle.id}/result',
    );
    final image = response['image'];
    final bytes = image is String ? base64Decode(image) : Uint8List(0);
    if (response['id'] != handle.id ||
        !result.matches(bytes, await hexHash(bytes))) {
      throw const CompanionFailure(
        'INVALID_OUTPUT',
        'The computer returned a different image than it described. Nothing was saved.',
      );
    }
    await store.savePreview(handle.id, bytes);
  }

  /// The local preview of the current background task, once collected.
  Future<File?> noteBackgroundPreview() async {
    final handle = state.handle;
    if (handle == null || !handle.isNoteBackground) return null;
    final file = await ref.read(noteBackgroundStoreProvider).preview(handle.id);
    return await file.exists() ? file : null;
  }

  /// Applies the previewed image as the note's background, keeping what it
  /// replaced for [revertNoteBackground].
  Future<bool> acceptNoteBackground() async {
    final handle = state.handle, generation = _generation;
    if (handle == null ||
        !handle.isNoteBackground ||
        handle.localSource == null ||
        state.phase != 'completed' ||
        state.busy ||
        _working ||
        _blocked) {
      return false;
    }
    try {
      if (await noteBackgroundPreview() == null) return false;
      if (!await _matches(handle)) {
        if (_alive(generation)) await refreshSource();
        return false;
      }
      if (!_alive(generation) || state.handle?.id != handle.id) return false;
      final request = NoteBackgroundRequest.decode(handle.localSource!);
      final store = ref.read(noteBackgroundStoreProvider);
      final accepted = await store.accept(
        handle.id,
        handle.noteId,
        request.background,
      );
      if (!_alive(generation) || state.handle?.id != handle.id) return false;
      ref
          .read(notesRepositoryProvider)
          .setNoteBackground(
            uuid: handle.noteId,
            expected: request.background,
            background: accepted,
          );
      await clear();
      await store.deletePreview(handle.id);
      return true;
    } catch (error) {
      if (_alive(generation)) {
        _show(
          'completed',
          text: state.text,
          message: error is StateError
              ? error.message.toString()
              : 'Could not apply this background. Your note is unchanged.',
        );
      }
      return false;
    }
  }

  /// Restores the background a generated one replaced, if it is still current.
  Future<void> revertNoteBackground(String noteId) async {
    final repository = ref.read(notesRepositoryProvider);
    final note = repository.getNoteByUuid(noteId);
    if (note == null) throw StateError('This note is no longer available.');
    final recovery = await ref
        .read(noteBackgroundStoreProvider)
        .recovery(noteId, note.background);
    if (recovery == null) {
      throw StateError('There is no earlier background to restore.');
    }
    repository.setNoteBackground(
      uuid: noteId,
      expected: recovery.accepted,
      background: recovery.previous,
    );
  }

  /// I04: transcribe an app-owned scan copy for the saved note [noteId].
  /// Only the re-encoded page goes to the computer.
  Future<void> startNoteScan(String noteId, {required String path}) async {
    if (!await _readyToStart()) return;
    final generation = ++_generation;
    _show('submitting', busy: true, stale: false);
    try {
      final repository = ref.read(notesRepositoryProvider);
      if (!repository.sync.canEdit) {
        throw const CompanionFailure(
          'READ_ONLY',
          'Existing notes are read-only on this device, so a scan could not be added. Nothing was sent.',
        );
      }
      final note = repository.getNoteByUuid(noteId);
      if (note == null || note.isDeleted || note.isPermanentlyDeleted) {
        throw const CompanionFailure(
          'SOURCE_MISSING',
          'This note is no longer available.',
        );
      }
      if (!await ref.read(noteScanStoreProvider).owns(path)) {
        throw const CompanionFailure(
          'INVALID_IMAGE',
          'Take or choose the page again.',
        );
      }
      final computer = _capableComputer(
        capabilityId: 'vision',
        contractKey: 'scanContract',
        contract: noteScanContract,
        operation: noteScanOperation,
        fallback: 'Your note is unchanged.',
        update: 'Update the companion to scan pages.',
        notReady:
            'Download Qwen3-VL and run the image self-test on your computer.',
        notReadyCode: 'VISION_NOT_READY',
      );
      final image = await prepareNoteImage(
        NoteAttachment(path: path, type: 'image/*'),
      );
      final request = NoteScanRequest(
        noteId: noteId,
        version: note.versionVectorJson,
        path: path,
        imageSha: await hexHash(image),
      );
      await _submitNew(
        generation,
        noteId: noteId,
        local: request.encode(),
        input: noteScanPrompt,
        operation: noteScanOperation,
        computer: computer,
      );
    } catch (error) {
      if (_alive(generation)) _failure(error);
    }
  }

  NoteScanResult? noteScanResult() {
    final handle = state.handle, text = state.text;
    if (handle == null || !handle.isNoteScan || text == null) return null;
    try {
      return NoteScanResult.parse(text);
    } catch (_) {
      return null;
    }
  }

  /// Appends the reviewed transcription and attaches the scan, keeping the
  /// unedited transcription beside the scan and a prior-body recovery copy.
  Future<bool> acceptNoteScan(String text) async {
    final handle = state.handle, generation = _generation;
    final result = noteScanResult();
    if (handle == null ||
        !handle.isNoteScan ||
        handle.localSource == null ||
        result == null ||
        state.phase != 'completed' ||
        state.busy ||
        _working ||
        _blocked) {
      return false;
    }
    try {
      if (!await _matches(handle)) {
        if (_alive(generation)) await refreshSource();
        return false;
      }
      if (!_alive(generation) || state.handle?.id != handle.id) return false;
      final request = NoteScanRequest.decode(handle.localSource!);
      await ref
          .read(noteScanStoreProvider)
          .writeOriginal(request.path, handle.noteId, result.text);
      if (!_alive(generation) || state.handle?.id != handle.id) return false;
      ref
          .read(notesRepositoryProvider)
          .appendToNote(
            taskId: handle.id,
            uuid: handle.noteId,
            expectedVersion: request.version,
            operation: noteScanOperation,
            text: text,
            attachment: NoteAttachment.fromPath(request.path).toMap(),
          );
      await clear();
      return true;
    } catch (error) {
      if (_alive(generation)) {
        _show(
          'completed',
          text: state.text,
          message: error is StateError
              ? error.message.toString()
              : 'Could not insert the scan. Your note is unchanged.',
        );
      }
      return false;
    }
  }

  /// Re-reads and re-encodes the attachment for (re)submission; refuses if it
  /// no longer matches what the user asked about.
  Future<Uint8List> _noteImageUpload(SummaryHandle handle) async {
    if (handle.isNoteScan) {
      final request = NoteScanRequest.decode(handle.localSource!);
      final image = await prepareNoteImage(
        NoteAttachment(path: request.path, type: 'image/*'),
      );
      if (await hexHash(image) != request.imageSha) {
        throw const CompanionFailure(
          'SOURCE_CHANGED',
          'The scanned page changed since you asked. Nothing was sent; clear this request and scan again.',
        );
      }
      return image;
    }
    final source = NoteImageRequest.decode(handle.localSource!);
    final attachment = noteImageAttachment(
      ref.read(notesRepositoryProvider).getNoteByUuid(handle.noteId),
      source.path,
    );
    if (attachment == null) {
      throw const CompanionFailure(
        'SOURCE_CHANGED',
        'The image is no longer attached. Nothing was sent.',
      );
    }
    final image = await prepareNoteImage(attachment);
    if (await hexHash(image) != source.imageSha) {
      throw const CompanionFailure(
        'SOURCE_CHANGED',
        'The image file changed since you asked. Nothing was sent; clear this request and ask again.',
      );
    }
    return image;
  }

  NoteImageAnswer? noteImageAnswer() {
    final handle = state.handle, text = state.text;
    if (handle == null || !handle.isNoteImage || text == null) return null;
    try {
      return NoteImageAnswer.parse(text);
    } catch (_) {
      return null;
    }
  }

  /// Appends the reviewed (possibly edited) [text] to the note body as an
  /// explicit, version-checked edit with a local recovery copy.
  Future<bool> acceptNoteImage(String text) async {
    final handle = state.handle, generation = _generation;
    if (handle == null ||
        !handle.isNoteImage ||
        handle.localSource == null ||
        state.phase != 'completed' ||
        state.busy ||
        _working ||
        _blocked ||
        state.text == null) {
      return false;
    }
    try {
      if (!await _matches(handle)) {
        if (_alive(generation)) await refreshSource();
        return false;
      }
      if (!_alive(generation) || state.handle?.id != handle.id) return false;
      ref
          .read(notesRepositoryProvider)
          .appendToNote(
            taskId: handle.id,
            uuid: handle.noteId,
            expectedVersion: NoteImageRequest.decode(handle.localSource!)
                .version,
            operation: noteImageOperation,
            text: text,
          );
      await clear();
      return true;
    } catch (error) {
      if (_alive(generation)) {
        _show(
          'completed',
          text: state.text,
          message: error is StateError
              ? error.message.toString()
              : 'Could not insert the text. Your note is unchanged.',
        );
      }
      return false;
    }
  }

  /// Persists the retry identity and bounded input before any submission.
  Future<void> _submitNew(
    int generation, {
    String? id,
    required String noteId,
    required String local,
    required String input,
    required String operation,
    required TrustedComputer computer,
  }) async {
    final handle = SummaryHandle(
      id: id ?? const Uuid().v4(),
      noteId: noteId,
      revision: await hexHash(utf8.encode(local)),
      computerId: computer.id,
      deviceId: computer.deviceId,
      created: DateTime.now().millisecondsSinceEpoch,
      pendingText: input,
      operation: operation,
      localSource: local,
    );
    if (!_alive(generation)) return;
    await _save(handle);
    if (!_alive(generation)) return;
    _show('submitting', handle: handle, busy: true);
    await retry();
  }

  /// The current metadata result after the phone's convention checks.
  NoteMetadataSuggestions? noteMetadataSuggestions({
    Iterable<NoteTag> library = const [],
  }) {
    final handle = state.handle, text = state.text;
    if (handle == null ||
        !handle.isNoteMetadata ||
        handle.localSource == null ||
        text == null) {
      return null;
    }
    try {
      return NoteMetadataSuggestions.parse(
        text,
        NoteMetadataSource.decode(handle.localSource!),
        library: library,
      );
    } catch (_) {
      return null;
    }
  }

  List<String>? noteIdeas() {
    final handle = state.handle, text = state.text;
    if (handle == null || !handle.isNoteIdeas || text == null) return null;
    try {
      return parseNoteIdeas(text);
    } catch (_) {
      return null;
    }
  }

  /// Applies only the explicitly chosen title and added tags. Existing tags
  /// are kept; the repository rechecks role and the exact version.
  Future<bool> acceptNoteMetadata({
    String? title,
    List<NoteTag> tags = const [],
  }) async {
    final handle = state.handle, generation = _generation;
    if (handle == null ||
        !handle.isNoteMetadata ||
        handle.localSource == null ||
        state.phase != 'completed' ||
        state.busy ||
        _working ||
        _blocked ||
        state.text == null ||
        (title == null && tags.isEmpty)) {
      return false;
    }
    try {
      if (!await _matches(handle)) {
        if (_alive(generation)) await refreshSource();
        return false;
      }
      if (!_alive(generation) || state.handle?.id != handle.id) return false;
      final source = NoteMetadataSource.decode(handle.localSource!);
      final current = {for (final tag in source.parsedTags) tag.key};
      ref
          .read(notesRepositoryProvider)
          .updateNoteMetadata(
            uuid: handle.noteId,
            expectedVersion: source.version,
            title: title ?? source.title,
            tags: [
              ...source.tags,
              for (final tag in tags)
                if (current.add(tag.key)) tag.encoded,
            ],
          );
      await clear();
      return true;
    } catch (error) {
      if (_alive(generation)) {
        _show(
          'completed',
          text: state.text,
          message: error is StateError
              ? error.message.toString()
              : 'Could not apply these suggestions. Your note is unchanged.',
        );
      }
      return false;
    }
  }

  /// L01: one reflection on the saved thought [uuid]. Sends exactly its
  /// text. It writes no synced data, so secondary devices may ask too.
  Future<void> startThoughtReflection(String uuid) async {
    if (!await _readyToStart()) return;
    final generation = ++_generation;
    _show('submitting', busy: true, stale: false);
    try {
      final thought = ref
          .read(thoughtsRepositoryProvider)
          .getThoughtByUuid(uuid);
      if (thought == null) {
        throw const CompanionFailure(
          'SOURCE_MISSING',
          'This thought is no longer saved. Nothing was sent.',
        );
      }
      final input = thought.content;
      if (!validSummaryText(input, thoughtReflectionInputBytes)) {
        throw const FormatException(
          'This thought is longer than 2,000 UTF-8 bytes. Nothing was sent or shortened.',
        );
      }
      final computer = _capableComputer(
        contractKey: 'reflectionContract',
        contract: thoughtReflectionContract,
        operation: thoughtReflectionOperation,
        fallback: 'Your thought is saved either way.',
        update: 'Update the companion to reflect on thoughts.',
      );
      final handle = SummaryHandle(
        id: const Uuid().v4(),
        noteId: uuid,
        revision: thoughtRevision(thought),
        computerId: computer.id,
        deviceId: computer.deviceId,
        created: DateTime.now().millisecondsSinceEpoch,
        pendingText: input,
        operation: thoughtReflectionOperation,
      );
      if (!_alive(generation)) return;
      await _save(handle);
      if (!_alive(generation)) return;
      _show('submitting', handle: handle, busy: true);
      await retry();
    } catch (error) {
      if (_alive(generation)) {
        _failure(
          error is FormatException
              ? CompanionFailure('INPUT_LIMIT', error.message)
              : error,
        );
      }
    }
  }

  /// Parses the current diary result against its protected local snapshot.
  DiarySuggestions? diarySuggestions() {
    final handle = state.handle, text = state.text;
    if (handle == null ||
        !handle.isDiarySuggestion ||
        handle.localSource == null ||
        text == null) {
      return null;
    }
    try {
      return DiarySuggestions.parse(
        text,
        DiarySuggestionSource.decode(handle.localSource!),
      );
    } catch (_) {
      return null;
    }
  }

  /// Writes only the fields the user explicitly accepted (possibly edited).
  /// Null fields are untouched; existing choices are otherwise preserved.
  Future<bool> acceptDiarySuggestion({
    String? title,
    String? mood,
    String? themes,
  }) async {
    final handle = state.handle, generation = _generation;
    if (handle == null ||
        !handle.isDiarySuggestion ||
        handle.localSource == null ||
        state.phase != 'completed' ||
        state.busy ||
        _working ||
        _blocked ||
        state.text == null) {
      return false;
    }
    try {
      if (!await _matches(handle)) {
        if (_alive(generation)) await refreshSource();
        return false;
      }
      if (!_alive(generation) || state.handle?.id != handle.id) return false;
      // The repository rechecks role and exact entries inside its write.
      ref
          .read(diaryRepositoryProvider)
          .applyDaySuggestions(
            dateString: handle.noteId,
            expectedSource: handle.localSource!,
            dayTitle: title,
            dayMood: mood,
            dayThemes: themes,
          );
      await clear();
      return true;
    } catch (error) {
      if (_alive(generation)) {
        _show(
          'completed',
          text: state.text,
          message: error is StateError
              ? error.message.toString()
              : error is ArgumentError
              ? error.message.toString()
              : 'Could not save these details. Your diary is unchanged.',
        );
      }
      return false;
    }
  }

  Future<void> refreshSource() async {
    final handle = state.handle, generation = _generation;
    if (handle == null || _blocked) return;
    final matches = await _matches(handle);
    if (_alive(generation) && state.handle?.id == handle.id && !matches) {
      _show(
        state.phase,
        text: state.text,
        message: state.message,
        busy: state.busy,
        stale: true,
      );
    }
  }

  Future<void> start(
    String noteId, {
    String operation = 'summarize-note',
    int? start,
    int? end,
    String intent = '',
    String? expectedContent,
    String? expectedVersion,
  }) async {
    if (!await _readyToStart()) return;
    final generation = ++_generation;
    _show('submitting', busy: true, stale: false);
    try {
      final note = ref.read(notesRepositoryProvider).getNoteByUuid(noteId);
      if (note == null || note.isDeleted || note.isPermanentlyDeleted) {
        throw const CompanionFailure(
          'SOURCE_MISSING',
          'This note is no longer available.',
        );
      }
      if ((expectedContent != null && note.content != expectedContent) ||
          (expectedVersion != null &&
              note.versionVectorJson != expectedVersion)) {
        throw const CompanionFailure(
          'SOURCE_CHANGED',
          'The saved note changed. Reopen writing help to select its current text. Nothing was sent.',
        );
      }
      final transform = transformOperations.containsKey(operation);
      TransformSource? source;
      if (transform) {
        if (utf8.encode(note.content).length > transformSourceBytes) {
          throw const CompanionFailure(
            'INPUT_LIMIT',
            'This note is too large for local recovery (64 KiB). Choose a smaller note.',
          );
        }
        if ((start ?? 0) < 0 ||
            (end ?? note.content.length) <= (start ?? 0) ||
            (end ?? note.content.length) > note.content.length) {
          throw const CompanionFailure(
            'INPUT_LIMIT',
            'Select a nonempty saved body or passage. Nothing was sent.',
          );
        }
        source = TransformSource.decode(
          TransformSource(
            content: note.content,
            version: note.versionVectorJson,
            start: start ?? 0,
            end: end ?? note.content.length,
          ).encode(),
        );
        if (!validSummaryText(source.selected, summaryInputBytes) ||
            (intent.isNotEmpty && !validSummaryText(intent, 240)) ||
            (operation == 'tone-note' && intent.trim().isEmpty)) {
          throw const CompanionFailure(
            'INPUT_LIMIT',
            'Select nonempty text and an intent of at most 240 UTF-8 bytes. Tone requires an intent. Nothing was sent.',
          );
        }
      } else if (operation != 'summarize-note') {
        throw const CompanionFailure(
          'INVALID_INPUT',
          'Choose a supported note operation.',
        );
      }
      final text = source == null
          ? summaryNoteText(note)
          : jsonEncode({'text': source.selected, 'intent': intent});
      if (!validSummaryText(text, summaryInputBytes)) {
        throw CompanionFailure(
          'INPUT_LIMIT',
          transform
              ? 'The selected text and intent must fit 2,000 UTF-8 bytes including JSON encoding. Nothing was sent; requests are never truncated.'
              : 'Choose a nonempty saved note of at most 2,000 UTF-8 bytes, including title and body. This note was not sent; longer notes are never truncated.',
        );
      }
      final connection = ref.read(companionControllerProvider);
      final computer = connection.selected;
      if (computer == null ||
          !computer.enabled ||
          connection.phase != CompanionPhase.connected) {
        throw const CompanionFailure(
          'UNAVAILABLE',
          'Connect your trusted computer in More → Local QVAC, then retry.',
        );
      }
      if (connection.status?['recovery'] != 1) {
        throw const CompanionFailure(
          'INCOMPATIBLE_VERSION',
          'Update the desktop companion to enable recoverable task history.',
        );
      }
      final capabilities = connection.status?['capabilities'] as List? ?? [];
      final capability = capabilities
          .whereType<Map>()
          .where((c) => c['id'] == 'text')
          .firstOrNull;
      if (capability == null ||
          capability['operations'] is! List ||
          !(capability['operations'] as List).contains(operation)) {
        throw const CompanionFailure(
          'INCOMPATIBLE_VERSION',
          'Update the companion to a version that supports this note operation.',
        );
      }
      if (!['ready', 'busy'].contains(capability['status'])) {
        throw const CompanionFailure(
          'NOT_READY',
          'The writing model is unavailable. Download, assign and load it on the computer, then retry.',
        );
      }
      final handle = SummaryHandle(
        id: const Uuid().v4(),
        noteId: noteId,
        revision: await summaryRevision(note),
        computerId: computer.id,
        deviceId: computer.deviceId,
        created: DateTime.now().millisecondsSinceEpoch,
        pendingText: text,
        operation: operation,
        localSource: source?.encode(),
      );
      if (!_alive(generation)) return;
      // Persist the exact retry identity and bounded input BEFORE any submission.
      await _save(handle);
      if (!_alive(generation)) return;
      _show('submitting', handle: handle, busy: true);
      await retry();
    } catch (error) {
      if (_alive(generation)) _failure(error);
    }
  }

  TrustedComputer _computer(SummaryHandle handle) {
    final computer = ref
        .read(companionControllerProvider)
        .computers
        .where((c) => c.id == handle.computerId)
        .firstOrNull;
    if (computer == null) {
      throw const CompanionFailure(
        'UNAUTHORIZED',
        'This computer is no longer trusted. Pair again in Settings; retained work expires on the desktop within 24 hours.',
      );
    }
    if (!computer.enabled) {
      throw const CompanionFailure(
        'UNAVAILABLE',
        'Connection is paused. Resume it in Settings to retrieve or cancel this task.',
      );
    }
    if (handle.deviceId.isNotEmpty && handle.deviceId != computer.deviceId) {
      throw const CompanionFailure(
        'UNAUTHORIZED',
        'This task belongs to an earlier phone pairing. It cannot be submitted with new credentials. Its desktop copy expires within 24 hours.',
      );
    }
    return computer;
  }

  Future<void> retry() async {
    final handle = state.handle;
    if (_working || handle == null || _blocked || !_foreground) return;
    _poll?.cancel();
    if (handle.expired) {
      try {
        await _save(
          handle.copyWith(
            accepted: true,
            phase: 'expired',
            ackPending: false,
            dropSource: true,
          ),
        );
      } catch (error) {
        _failure(error);
        return;
      }
      if (!ref.mounted || _blocked) return;
      _show(
        'expired',
        handle: handle.copyWith(
          accepted: true,
          phase: 'expired',
          dropSource: true,
          ackPending: false,
        ),
        message: 'This preview expired after 24 hours. Clear it before requesting another.',
      );
      return;
    }
    _working = true;
    _idle = Completer<void>();
    final generation = _generation;
    _show(handle.accepted ? 'retrieving' : 'submitting', busy: true);
    try {
      final computer = _computer(handle);
      Map<String, dynamic> job;
      try {
        job = handle.cancelWanted
            ? await _client.authenticated(
                computer,
                'POST',
                '/v1/jobs/${handle.id}/cancel',
                body: {'operation': handle.operation},
              )
            : await _client.authenticated(
                computer,
                'GET',
                '/v1/jobs/${handle.id}',
              );
      } on CompanionFailure catch (error) {
        if (!_alive(generation)) return;
        if (error.code != 'NOT_FOUND' || handle.accepted) rethrow;
        if (handle.cancelWanted) {
          _show(
            'cancelled',
            message:
                'No accepted task was found. Nothing further was submitted.',
          );
          return;
        }
        if (!await _matches(handle)) {
          if (_alive(generation)) {
            await _save(handle.copyWith(phase: 'failed'));
            if (!_alive(generation)) return;
            _show(
              'failed',
              stale: true,
              message: 'The source changed or was deleted before acceptance could be confirmed. No new submission was made. Clear this preview before starting again.',
            );
          }
          return;
        }
        if (handle.pendingText == null ||
            [
              'failed',
              'cancelled',
              'expired',
              'interrupted',
              'completed',
            ].contains(handle.phase)) {
          throw const CompanionFailure(
            'INVALID_RESPONSE',
            'The original protected input is unavailable. This task was not submitted again. Clear the preview before starting explicitly.',
          );
        }
        if (!_alive(generation)) return;
        final image = handle.isNoteImage || handle.isNoteScan
            ? await _noteImageUpload(handle)
            : handle.isDiaryPhoto
            ? await _diaryPhotoUpload(handle)
            : null;
        if (!_alive(generation)) return;
        job = await _client.authenticated(
          computer,
          'POST',
          image == null ? '/v1/jobs' : '/v1/image-jobs',
          body: {
            'id': handle.id,
            'operation': handle.operation,
            'prompt': handle.pendingText,
            'expires': handle.expires,
            if (image != null) 'image': base64Encode(image),
          },
        );
      }
      if (!_alive(generation)) return;
      if (handle.cancelWanted && ['queued', 'running'].contains(job['state'])) {
        job = await _client.authenticated(
          computer,
          'POST',
          '/v1/jobs/${handle.id}/cancel',
          body: {},
        );
      }
      if (!_alive(generation)) return;
      await _consume(handle, job, computer, generation);
    } catch (error) {
      if (_alive(generation)) _failure(error);
    } finally {
      _working = false;
      final idle = _idle;
      _idle = null;
      idle?.complete();
      if (ref.mounted &&
          generation != _generation &&
          state.handle != null &&
          !_blocked) {
        _poll = Timer(Duration.zero, () => unawaited(retry()));
      }
    }
  }

  Future<void> _consume(
    SummaryHandle handle,
    Map<String, dynamic> job,
    TrustedComputer computer,
    int generation,
  ) async {
    final phase = job['state'];
    if (job['id'] != handle.id ||
        job['device'] != computer.deviceId ||
        job['operation'] != handle.operation ||
        job['model'] is! String ||
        ![
          'queued',
          'running',
          'completed',
          'failed',
          'cancelled',
          'interrupted',
          'expired',
        ].contains(phase)) {
      throw const CompanionFailure(
        'INVALID_RESPONSE',
        'The computer returned an invalid note task. Update both apps and retry.',
      );
    }
    var invalidOutput =
        phase == 'completed' &&
        job['acknowledged'] != true &&
        (job['text'] is! String ||
            !_validOutput(handle, job['text'] as String));
    if (phase == 'completed' &&
        job['acknowledged'] != true &&
        !invalidOutput &&
        handle.isDiarySuggestion) {
      try {
        DiarySuggestions.parse(
          job['text'] as String,
          DiarySuggestionSource.decode(handle.localSource!),
        );
      } catch (_) {
        invalidOutput = true;
      }
    }
    if (phase == 'completed' &&
        job['acknowledged'] != true &&
        !invalidOutput &&
        (handle.isNoteMetadata ||
            handle.isNoteIdeas ||
            handle.isNoteImage ||
            handle.isNoteScan ||
            handle.isNoteBackground ||
            handle.isDiaryPhoto)) {
      try {
        if (handle.isDiaryPhoto) {
          DiaryPhotoQuestions.parse(job['text'] as String);
        } else if (handle.isNoteBackground) {
          NoteBackgroundResult.parse(job['text'] as String);
        } else if (handle.isNoteScan) {
          NoteScanResult.parse(job['text'] as String);
        } else if (handle.isNoteImage) {
          NoteImageAnswer.parse(job['text'] as String);
        } else if (handle.isNoteIdeas) {
          parseNoteIdeas(job['text'] as String);
        } else {
          NoteMetadataSuggestions.parse(
            job['text'] as String,
            NoteMetadataSource.decode(handle.localSource!),
          );
        }
      } catch (_) {
        invalidOutput = true;
      }
    }
    if (phase == 'completed' &&
        job['acknowledged'] != true &&
        !invalidOutput &&
        handle.isDiaryAnswer) {
      try {
        DiaryHistoryAnswer.parse(
          job['text'] as String,
          DiaryHistorySelection.decode(handle.localSource!),
        );
      } on DiaryAnswerRejected {
        // Valid output that is not shown; the answer page explains why.
      } catch (_) {
        invalidOutput = true;
      }
    }
    if (phase == 'completed' &&
        job['acknowledged'] != true &&
        !invalidOutput &&
        handle.isNoteQuestion) {
      try {
        NoteQuestionAnswer.parse(
          job['text'] as String,
          NoteQuestionSelection.decode(handle.localSource!),
        );
      } on NoteAnswerRejected {
        // Valid output that is not shown; the answer page explains why.
      } catch (_) {
        invalidOutput = true;
      }
    }
    if (phase == 'completed' &&
        job['acknowledged'] != true &&
        !invalidOutput &&
        handle.isDailyQuestion) {
      // Content checks run when shown; only a broken envelope is invalid.
      try {
        DailyQuestion.parse(
          job['text'] as String,
          DailyQuestionSource.decode(handle.localSource!),
        );
      } on DailyQuestionRejected {
        // Valid output that is not shown; the question page explains why.
      } catch (_) {
        invalidOutput = true;
      }
    }
    if (phase == 'completed' &&
        job['acknowledged'] != true &&
        !invalidOutput &&
        handle.isNoteWebsite) {
      try {
        await sanitizeWebsiteBounded(job['text'] as String);
      } catch (_) {
        invalidOutput = true;
      }
    }
    final accepted = handle.copyWith(
      accepted: true,
      phase: invalidOutput ? 'failed' : phase as String,
      deviceId: computer.deviceId,
      acknowledged: job['acknowledged'] == true,
    );
    await _save(accepted);
    if (!_alive(generation)) return;
    _show('accepted', handle: accepted);
    String? text;
    if (phase == 'completed' && !accepted.acknowledged) {
      final output = job['text'];
      if (invalidOutput || output is! String || !_validOutput(handle, output)) {
        throw const CompanionFailure(
          'INVALID_OUTPUT',
          'The computer returned an empty or invalid result. Your original note is unchanged.',
        );
      }
      text = output.trim();
    }
    if (text != null && handle.isNoteBackground) {
      await _collectBackground(accepted, text, computer);
      if (!_alive(generation)) return;
    }
    final matches = await _matches(accepted);
    if (!_alive(generation)) return;
    final progress = switch (job['progress']) {
      {'step': final int step, 'total': final int total} => (
        step: step,
        total: total,
      ),
      _ => null,
    };
    _show(
      phase,
      handle: accepted,
      text: text,
      stale: !matches,
      message: switch (phase) {
        'queued' => 'Accepted by the computer. Waiting for the writing model.',
        'running' when progress != null =>
          'Generating on your computer: step ${progress.step} of ${progress.total}. You can close this page and return later.',
        'running' => 'Running on your computer. You can close this preview and return later.',
        'failed' =>
          job['error'] == 'INVALID_OUTPUT'
              ? 'The model returned an invalid result. Clear this preview to retry explicitly.'
              : job['error'] == 'OUTPUT_LIMIT'
              ? 'The result reached its output limit. No partial result was returned. Clear this preview and try a shorter note.'
              : 'The computer could not finish. Check its writing model and clear this preview to retry explicitly.',
        'interrupted' => 'The desktop stopped during generation. Clear this preview to retry explicitly.',
        'cancelled' => 'Task cancelled. Your note is unchanged.',
        'expired' => 'The desktop result expired. Clear this preview before starting explicitly.',
        'completed' when accepted.acknowledged => 'Result acknowledged and removed from the desktop. Your note is unchanged.',
        _ => null,
      },
    );
    if (!state.terminal) {
      _poll = Timer(const Duration(seconds: 3), () => unawaited(retry()));
    } else if (!accepted.expired) {
      _poll = Timer(
        Duration(
          milliseconds:
              accepted.expires - DateTime.now().millisecondsSinceEpoch,
        ),
        () => unawaited(retry()),
      );
    }
  }

  bool _validOutput(SummaryHandle handle, String text) =>
      validSummaryText(
        text,
        handle.isNoteWebsite
            ? noteWebsiteOutputBytes
            : handle.isTransformation
            ? transformOutputBytes
            : handle.isDiarySuggestion
            ? diaryOutputBytes
            : handle.isDailyQuestion
            ? dailyQuestionOutputBytes
            : handle.isDiaryAnswer
            ? historyOutputBytes
            : handle.isNoteQuestion
            ? noteQuestionOutputBytes
            : handle.isNoteMetadata || handle.isNoteIdeas
            ? noteHelpOutputBytes
            : handle.isNoteImage
            ? noteImageOutputBytes
            : handle.isNoteScan
            ? noteScanOutputBytes
            : handle.isDiaryPhoto
            ? diaryPhotoQuestionOutputBytes
            : handle.isNoteBackground
            ? 1024
            : handle.isThoughtReflection
            ? thoughtReflectionOutputBytes
            : summaryOutputBytes,
      ) &&
      (!handle.isTransformation || validTransformOutput(text)) &&
      (!handle.isThoughtReflection || validThoughtReflectionLine(text));

  /// The sanitized page of the current website task, for previewing.
  Future<String?> noteWebsitePreview() async {
    final handle = state.handle, text = state.text;
    if (handle == null || !handle.isNoteWebsite || text == null) return null;
    try {
      return await sanitizeWebsiteBounded(text);
    } catch (_) {
      return null;
    }
  }

  /// Saves the generated page on the note, keeping its content.
  Future<bool> acceptNoteWebsite() async {
    final handle = state.handle, text = state.text, generation = _generation;
    if (handle == null ||
        !handle.isNoteWebsite ||
        handle.localSource == null ||
        state.phase != 'completed' ||
        state.busy ||
        _working ||
        _blocked ||
        text == null) {
      return false;
    }
    try {
      if (!await _matches(handle)) {
        if (_alive(generation)) await refreshSource();
        return false;
      }
      final request = WebsiteRequest.decode(handle.localSource!);
      final html = await sanitizeWebsiteBounded(text);
      if (!_alive(generation) || state.handle?.id != handle.id) return false;
      ref
          .read(notesRepositoryProvider)
          .setWebsite(
            uuid: handle.noteId,
            expectedVersion: request.version,
            html: html,
            sourceHash: request.contentHash,
          );
      await clear();
      return true;
    } catch (error) {
      if (_alive(generation)) {
        _show(
          'completed',
          text: text,
          message: error is StateError ? error.message.toString() : 'This website could not be saved safely. Your note is unchanged.',
        );
      }
      return false;
    }
  }

  Future<bool> acceptTransformation() async {
    final handle = state.handle, text = state.text, generation = _generation;
    if (handle == null ||
        !handle.isTransformation ||
        handle.localSource == null ||
        state.phase != 'completed' ||
        state.busy ||
        _working ||
        _blocked ||
        text == null) {
      return false;
    }
    try {
      if (!await _matches(handle)) {
        if (_alive(generation)) await refreshSource();
        return false;
      }
      if (!_alive(generation) || state.handle?.id != handle.id) return false;
      // No await between the repository's version check and its atomic write.
      ref
          .read(notesRepositoryProvider)
          .acceptTransformation(
            taskId: handle.id,
            uuid: handle.noteId,
            operation: handle.operation,
            source: TransformSource.decode(handle.localSource!),
            replacement: text,
          );
      await clear();
      return true;
    } catch (error) {
      if (_alive(generation)) {
        _show(
          'completed',
          text: text,
          message: error is StateError
              ? error.message.toString()
              : 'Could not accept the proposal. Your note is unchanged.',
        );
      }
      return false;
    }
  }

  void _failure(Object error) {
    final failure = error is CompanionFailure
        ? error
        : const CompanionFailure(
            'SECURE_STORAGE',
            'Could not save or retrieve this request securely. Unlock the phone and retry.',
          );
    _show(
      switch (failure.code) {
        'NOT_FOUND' || 'EXPIRED' => 'expired',
        'INVALID_OUTPUT' => 'failed',
        'UNAUTHORIZED' ||
        'IDENTITY_CHANGED' ||
        'INVALID_RESPONSE' ||
        'SOURCE_CHANGED' ||
        'ID_CONFLICT' => 'failed',
        _ => 'error',
      },
      message: switch (failure.code) {
        'NOT_FOUND' => 'This accepted task is no longer retained on the computer. Clear this preview to request another.',
        'UNAUTHORIZED' => 'The computer no longer authorizes this phone. Review trust in Settings and pair again.',
        'NOT_READY' => 'Load and assign the writing model on your computer, then retry this same request.',
        _ => failure.message,
      },
    );
  }

  Future<void> cancel() async {
    final handle = state.handle, generation = _generation;
    if (handle == null || _blocked || state.terminal || state.busy) return;
    try {
      final cancelling = handle.cancelling();
      await _save(cancelling);
      if (!_alive(generation)) return;
      _show(
        'retrieving',
        handle: cancelling,
        message: 'Requesting cancellation…',
      );
      await retry();
    } catch (error) {
      if (_alive(generation)) _failure(error);
    }
  }

  Future<void> retryAsNew() async {
    final handle = state.handle, generation = _generation;
    if (handle == null ||
        (handle.isTransformation ||
            handle.isNoteWebsite ||
            handle.isRetiredPresentation ||
            handle.isNoteMetadata ||
            handle.isNoteIdeas ||
            handle.isNoteImage ||
            handle.isNoteScan ||
            handle.isNoteBackground ||
            handle.isDiaryPhoto ||
            handle.isDiaryDay ||
            handle.isNoteQuestion ||
            handle.isThoughtReflection) ||
        !state.terminal ||
        state.phase == 'completed' ||
        state.busy ||
        _working ||
        _blocked) {
      return;
    }
    await refreshSource();
    if (!_alive(generation) || state.stale || !await _matches(handle)) return;
    await clear();
    if (!ref.mounted ||
        _blocked ||
        state.handle != null ||
        state.phase != 'idle') {
      return;
    }
    await start(handle.noteId);
  }

  Future<void> clear() async {
    if (_blocked) return;
    await _settle();
    if (!ref.mounted || _blocked) return;
    if (_working) {
      _show(
        state.phase,
        text: state.text,
        message: 'Still talking to your computer. Tap Clear again in a moment.',
        busy: state.busy,
      );
      return;
    }
    if (state.handle != null && !state.terminal) return;
    final generation = ++_generation;
    _poll?.cancel();
    try {
      final handle = state.handle;
      if (handle != null) {
        // Persist the receipt before the network: a lost ack is retried safely.
        final receipt = handle.copyWith(
          phase: state.phase,
          accepted: true,
          ackPending: handle.accepted && state.phase != 'expired',
        );
        await _save(receipt);
        if (!_alive(generation)) return;
        await _save(null);
        if (!_alive(generation)) return;
        // Free the slot before the network: an acknowledgment can take
        // several timeouts, and its receipt is already persisted for retry.
        state = const NoteSummaryState();
        _watchSource(null);
        if (receipt.ackPending) await acknowledge(receipt);
      } else {
        await _save(null);
      }
      if (_alive(generation)) {
        state = const NoteSummaryState();
        _watchSource(null);
      }
    } catch (error) {
      if (_alive(generation)) _failure(error);
    }
  }
}
