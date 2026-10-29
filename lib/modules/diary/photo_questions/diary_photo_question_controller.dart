import 'dart:async';
import 'dart:typed_data';

import 'package:journal/common.dart';
import 'package:journal/modules/diary/photo_questions/diary_photo_question_contract.dart';
import 'package:journal/modules/diary/photo_questions/diary_photo_question_store.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';

/// One photo to ask about: its saved-bytes hash, the bytes and its caption.
typedef DiaryPhotoAsk = ({String photoSha, Uint8List photo, String caption});

class DiaryPhotoQuestionState {
  const DiaryPhotoQuestionState({
    this.questions = const {},
    this.messages = const {},
    this.queued = const [],
    this.revision = 0,
  });

  /// Cached results by photo SHA-256.
  final Map<String, DiaryPhotoQuestions> questions;

  /// Why the last request for a photo produced no questions.
  final Map<String, String> messages;

  /// Photos from **Generate questions** not yet held by the task slot.
  final List<String> queued;
  final int revision;
}

/// I02: moves finished photo questions out of the shared task slot into the
/// local cache, then frees the slot for the next photo. It runs app-wide, so
/// a result that arrives after the photo page closed is still kept.
class DiaryPhotoQuestionController extends Notifier<DiaryPhotoQuestionState> {
  DiaryPhotoQuestionStore get _store =>
      ref.read(diaryPhotoQuestionStoreProvider);
  bool _pruned = false;

  /// The task being moved to the cache, so repeated slot updates don't
  /// consume it twice.
  String? _consuming;

  /// Photos from **Generate questions** not yet sent. The shared task slot
  /// holds one request at a time, so they go one after another.
  final _queue = <DiaryPhotoAsk>[];
  String _queueDate = '';
  bool _sending = false;

  @override
  DiaryPhotoQuestionState build() {
    ref.listen(
      noteSummaryProvider,
      (_, next) => scheduleMicrotask(() {
        if (ref.mounted) unawaited(_consume(next));
      }),
      fireImmediately: true,
    );
    return const DiaryPhotoQuestionState();
  }

  /// Whether questions for [photoSha] are being asked in the shared slot.
  static bool asking(NoteSummaryState summary, String photoSha) =>
      summary.handle?.isDiaryPhoto == true &&
      summary.handle!.noteId == photoSha &&
      (!summary.terminal || summary.busy);

  void _set({
    Map<String, DiaryPhotoQuestions>? questions,
    Map<String, String>? messages,
  }) {
    state = DiaryPhotoQuestionState(
      questions: questions ?? state.questions,
      messages: messages ?? state.messages,
      queued: [for (final ask in _queue) ask.photoSha],
      revision: state.revision + 1,
    );
  }

  void _message(String photoSha, String? message) => _set(
    messages: {
      for (final entry in state.messages.entries)
        if (entry.key != photoSha) entry.key: entry.value,
      photoSha: ?message,
    },
  );

  /// Reads cached questions for [photoShas] not loaded yet.
  Future<void> load(Iterable<String> photoShas) async {
    final found = <String, DiaryPhotoQuestions>{};
    for (final sha in photoShas.toSet()) {
      if (sha.isEmpty || state.questions.containsKey(sha)) continue;
      try {
        final questions = await _store.read(sha);
        if (questions != null) found[sha] = questions;
      } catch (_) {
        // An unreadable cache entry just means the usual questions.
      }
    }
    if (found.isNotEmpty && ref.mounted) {
      _set(questions: {...state.questions, ...found});
    }
  }

  /// **Generate questions**: asks the computer about each of [photos] that has
  /// no questions yet, one at a time. Photos already being asked about or
  /// waiting are not asked twice.
  Future<void> generate({
    required String date,
    required List<DiaryPhotoAsk> photos,
  }) async {
    final summary = ref.read(noteSummaryProvider);
    final waiting = {for (final ask in _queue) ask.photoSha};
    final fresh = [
      for (final ask in photos)
        if (ask.photo.isNotEmpty &&
            !state.questions.containsKey(ask.photoSha) &&
            !waiting.contains(ask.photoSha) &&
            !asking(summary, ask.photoSha))
          ask,
    ];
    if (fresh.isEmpty) return;
    if (summary.handle != null && !summary.handle!.isDiaryPhoto) {
      _set(
        messages: {
          ...state.messages,
          for (final ask in fresh) ask.photoSha: 'Another AI request is still open. Finish or clear it in More → Local QVAC → AI task history, then generate again.',
        },
      );
      return;
    }
    _queueDate = date;
    // Queued at once so the page shows it is working from the first frame.
    _queue.addAll(fresh);
    _set(
      messages: {
        for (final entry in state.messages.entries)
          if (!fresh.any((ask) => ask.photoSha == entry.key))
            entry.key: entry.value,
      },
    );
    // Photos answered on an earlier visit are cached: don't ask again.
    await load([for (final ask in fresh) ask.photoSha]);
    if (!ref.mounted) return;
    _queue.removeWhere(
      (ask) => !_sending && state.questions.containsKey(ask.photoSha),
    );
    _set();
    await _next();
  }

  /// Stops generating: drops waiting photos and cancels the one in progress.
  Future<void> stop() async {
    _queue.clear();
    _set();
    final summary = ref.read(noteSummaryProvider);
    if (summary.handle?.isDiaryPhoto == true &&
        !summary.terminal &&
        !summary.busy) {
      await ref.read(noteSummaryProvider.notifier).cancel();
    }
  }

  /// Sends the next waiting photo once the shared slot is free.
  Future<void> _next() async {
    if (_sending || _queue.isEmpty || !ref.mounted) return;
    final summary = ref.read(noteSummaryProvider);
    // Busy with the previous photo: [_consume] calls back when it's done.
    if (summary.handle != null || summary.busy) return;
    _sending = true;
    // Stays queued until the slot holds it, so nothing looks finished early.
    final ask = _queue.first;
    try {
      await request(
        date: _queueDate,
        photoSha: ask.photoSha,
        photo: ask.photo,
        caption: ask.caption,
      );
    } finally {
      _sending = false;
      _queue.remove(ask);
    }
    if (!ref.mounted) return;
    _set();
    final reason = state.messages[ask.photoSha];
    if (reason != null) {
      // Refused before sending (no model, not connected…): the rest would be
      // refused for the same reason, so say it once for each and stop.
      final rest = [for (final waiting in _queue) waiting.photoSha];
      _queue.clear();
      _set(messages: {...state.messages, for (final sha in rest) sha: reason});
    } else {
      await _next();
    }
  }

  /// Asks the computer about one photo.
  Future<void> request({
    required String date,
    required String photoSha,
    required Uint8List photo,
    String caption = '',
  }) async {
    _message(photoSha, null);
    final summary = ref.read(noteSummaryProvider.notifier);
    await summary.startDiaryPhotoQuestions(
      date: date,
      photoSha: photoSha,
      photo: photo,
      caption: caption,
    );
    if (!ref.mounted) return;
    final next = ref.read(noteSummaryProvider);
    if (next.handle == null && next.message != null) {
      _message(photoSha, next.message);
    } else if (next.handle?.noteId != photoSha) {
      _message(
        photoSha,
        next.handle == null
            ? 'Your computer is still finishing the previous request. Try again in a moment.'
            : 'Another AI request is still open. Finish or clear it in More → Local QVAC → AI task history, then ask again.',
      );
    }
  }

  /// Hides generated questions for [photoSha]; answers are kept.
  Future<void> forget(String photoSha) async {
    await _store.remove(photoSha);
    if (ref.mounted) {
      _set(questions: {...state.questions}..remove(photoSha));
    }
  }

  Future<void> _consume(NoteSummaryState summary) async {
    final handle = summary.handle;
    if (summary.phase == 'restoring') return;
    if (!_pruned) {
      _pruned = true;
      try {
        await _store.prune(
          active: handle?.isDiaryPhoto == true ? handle!.id : null,
        );
      } catch (_) {
        // Retried on the next start.
      }
    }
    if (handle == null || !handle.isDiaryPhoto || summary.busy) return;
    if (!summary.terminal || _consuming == handle.id) return;
    _consuming = handle.id;
    final controller = ref.read(noteSummaryProvider.notifier);
    final sha = handle.noteId;
    String? message;
    if (summary.phase == 'completed' && summary.text != null) {
      try {
        final questions = DiaryPhotoQuestions.parse(summary.text!);
        await _store.write(sha, questions);
        if (ref.mounted) _set(questions: {...state.questions, sha: questions});
      } catch (_) {
        message = 'Your computer returned something that was not usable. The usual questions are still here.';
      }
    } else if (summary.phase != 'completed') {
      message = switch (summary.phase) {
        'cancelled' => 'Stopped. The usual questions are still here.',
        'expired' => 'That request expired. Ask again for new questions.',
        'interrupted' =>
          'Your computer stopped before finishing. Ask again when it’s ready.',
        // Vision not ready, or the prepared photo is gone: say exactly why.
        _
            when summary.message?.contains('Qwen3-VL') == true ||
                summary.message?.contains('photo prepared') == true =>
          summary.message!,
        _ => 'Your computer couldn’t look at this photo. The usual questions are still here.',
      };
    }
    await controller.clear();
    try {
      await _store.prune();
    } catch (_) {
      // Removed on the next start.
    }
    if (ref.mounted) {
      _message(sha, message);
      await _next();
    }
  }
}

final diaryPhotoQuestionProvider =
    NotifierProvider<DiaryPhotoQuestionController, DiaryPhotoQuestionState>(
      DiaryPhotoQuestionController.new,
    );
