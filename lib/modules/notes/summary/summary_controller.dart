import 'dart:async';
import 'dart:convert';

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

import 'package:journal/modules/notes/models/note_tag.dart';

import '../../presentation/presentation_contract.dart';
import '../../presentation/presentation_repository.dart';

import 'package:journal/modules/diary/controllers/diary_providers.dart';
import 'package:journal/modules/diary/history/diary_history_contract.dart';
import 'package:journal/modules/diary/questions/daily_question_contract.dart';
import 'package:journal/modules/diary/suggestions/diary_suggestion_contract.dart';

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
        handle?.presentationSource?.key ??
        (handle?.isDiaryDay == true
            ? '${handle!.operation}:${handle.noteId}'
            : handle?.noteId);
    if (_watchedNote == key) return;
    unawaited(_source?.cancel());
    _source = null;
    _watchedNote = key;
    if (handle != null) {
      final stream =
          handle.presentationSource?.kind == 'diary' || handle.isDiaryDay
          ? ref.read(diaryRepositoryProvider).watchAllDays()
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
    if (handle.isDiarySuggestion) {
      final source = DiarySuggestionSource.fromDay(
        ref.read(diaryRepositoryProvider).getDay(handle.noteId),
      );
      return source != null &&
          await hexHash(utf8.encode(source.encode())) == handle.revision;
    }
    if (handle.isNoteIdeas) return true;
    if (handle.isNoteMetadata) {
      return handle.localSource != null &&
          NoteMetadataSource.decode(handle.localSource!).matches(
            ref.read(notesRepositoryProvider).getNoteByUuid(handle.noteId),
          );
    }
    if (handle.isPresentation) {
      final source = ref
          .read(presentationRepositoryProvider)
          .source(handle.presentationSource!);
      return source != null &&
          await hexHash(utf8.encode(source.encode())) == handle.revision;
    }
    final note = ref.read(notesRepositoryProvider).getNoteByUuid(handle.noteId);
    return note != null &&
        !note.isDeleted &&
        !note.isPermanentlyDeleted &&
        await summaryRevision(note) == handle.revision;
  }

  Future<void> startPresentation(
    PresentationSourceRef sourceRef, {
    String intent = '',
  }) async {
    if (!await _readyToStart()) return;
    final generation = ++_generation;
    _show('submitting', busy: true, stale: false);
    try {
      final source = ref.read(presentationRepositoryProvider).source(sourceRef);
      if (source == null) {
        throw const CompanionFailure(
          'SOURCE_MISSING',
          'This saved text is no longer available.',
        );
      }
      final blocks = PresentationBlocks(
        source.content,
        markdown: sourceRef.kind == 'note',
      );
      final input = blocks.request(intent);
      final connection = ref.read(companionControllerProvider);
      final computer = connection.selected;
      if (computer == null ||
          !computer.enabled ||
          connection.phase != CompanionPhase.connected) {
        throw const CompanionFailure(
          'UNAVAILABLE',
          'Connect your trusted computer in Settings → Local AI computer.',
        );
      }
      final capabilities = connection.status?['capabilities'] as List? ?? [];
      final capability = capabilities
          .whereType<Map>()
          .where((c) => c['id'] == 'text')
          .firstOrNull;
      if (connection.status?['recovery'] != 1 ||
          capability?['presentationContract'] != 1 ||
          capability?['operations'] is! List ||
          !(capability!['operations'] as List).contains(
            presentationOperation,
          )) {
        throw const CompanionFailure(
          'INCOMPATIBLE_VERSION',
          'Update the companion to support safe presentations.',
        );
      }
      if (!['ready', 'busy'].contains(capability['status'])) {
        throw const CompanionFailure(
          'NOT_READY',
          'Load the writing model on your computer.',
        );
      }
      final handle = SummaryHandle(
        id: const Uuid().v4(),
        noteId: sourceRef.id,
        revision: await hexHash(utf8.encode(source.encode())),
        computerId: computer.id,
        deviceId: computer.deviceId,
        created: DateTime.now().millisecondsSinceEpoch,
        pendingText: input,
        operation: presentationOperation,
        localSource: source.encode(),
        presentationSource: sourceRef,
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

  /// The connected computer when it advertises [operation] at [contract].
  TrustedComputer _capableComputer({
    required String contractKey,
    required int contract,
    required String operation,
    required String fallback,
    required String update,
  }) {
    final connection = ref.read(companionControllerProvider);
    final computer = connection.selected;
    if (computer == null ||
        !computer.enabled ||
        connection.phase != CompanionPhase.connected) {
      throw CompanionFailure(
        'UNAVAILABLE',
        'Connect your trusted computer in Settings → Local AI computer. $fallback',
      );
    }
    final capabilities = connection.status?['capabilities'] as List? ?? [];
    final capability = capabilities
        .whereType<Map>()
        .where((c) => c['id'] == 'text')
        .firstOrNull;
    if (connection.status?['recovery'] != 1 ||
        capability?[contractKey] != contract ||
        capability?['operations'] is! List ||
        !(capability!['operations'] as List).contains(operation)) {
      throw CompanionFailure('INCOMPATIBLE_VERSION', update);
    }
    if (!['ready', 'busy'].contains(capability['status'])) {
      throw CompanionFailure(
        'NOT_READY',
        'Load the writing model on your computer. $fallback',
      );
    }
    return computer;
  }

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

  /// Persists the retry identity and bounded input before any submission.
  Future<void> _submitNew(
    int generation, {
    required String noteId,
    required String local,
    required String input,
    required String operation,
    required TrustedComputer computer,
  }) async {
    final handle = SummaryHandle(
      id: const Uuid().v4(),
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
          'Connect your trusted computer in Settings → Local AI computer, then retry.',
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
        job = await _client.authenticated(
          computer,
          'POST',
          '/v1/jobs',
          body: {
            'id': handle.id,
            'operation': handle.operation,
            'prompt': handle.pendingText,
            'expires': handle.expires,
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
        (handle.isNoteMetadata || handle.isNoteIdeas)) {
      try {
        if (handle.isNoteIdeas) {
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
        handle.isPresentation) {
      try {
        if (handle.localSource == null) {
          throw const FormatException('Missing protected source');
        }
        final snapshot = PresentationSnapshot.decode(handle.localSource!);
        final blocks = PresentationBlocks(
          snapshot.content,
          markdown: snapshot.ref.kind == 'note',
        );
        await compilePresentationBounded(
          job['text'] as String,
          blocks.nodes.length,
        );
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
    final matches = await _matches(accepted);
    if (!_alive(generation)) return;
    _show(
      phase,
      handle: accepted,
      text: text,
      stale: !matches,
      message: switch (phase) {
        'queued' => 'Accepted by the computer. Waiting for the writing model.',
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
        handle.isTransformation || handle.isPresentation
            ? transformOutputBytes
            : handle.isDiarySuggestion
            ? diaryOutputBytes
            : handle.isDailyQuestion
            ? dailyQuestionOutputBytes
            : handle.isDiaryAnswer
            ? historyOutputBytes
            : handle.isNoteMetadata || handle.isNoteIdeas
            ? noteHelpOutputBytes
            : summaryOutputBytes,
      ) &&
      (!handle.isTransformation || validTransformOutput(text));

  Future<bool> acceptPresentation() async {
    final handle = state.handle, text = state.text, generation = _generation;
    if (handle == null ||
        !handle.isPresentation ||
        handle.localSource == null ||
        state.phase != 'completed' ||
        state.busy ||
        _working ||
        _blocked ||
        text == null) {
      return false;
    }
    try {
      final source = PresentationSnapshot.decode(handle.localSource!);
      final blocks = PresentationBlocks(
        source.content,
        markdown: source.ref.kind == 'note',
      );
      final document = await compilePresentationBounded(
        text,
        blocks.nodes.length,
      );
      if (!_alive(generation) || state.handle?.id != handle.id) return false;
      ref
          .read(presentationRepositoryProvider)
          .accept(taskId: handle.id, snapshot: source, document: document);
      await clear();
      return true;
    } catch (error) {
      if (_alive(generation)) {
        _show(
          'completed',
          text: text,
          message: error is StateError
              ? error.message.toString()
              : 'This presentation could not be accepted safely.',
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
            handle.isPresentation ||
            handle.isNoteMetadata ||
            handle.isNoteIdeas ||
            handle.isDiaryDay) ||
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
