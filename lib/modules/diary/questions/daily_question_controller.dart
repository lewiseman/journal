import 'dart:async';

import 'package:journal/common.dart';
import 'package:journal/modules/diary/controllers/diary_repository.dart';
import 'package:journal/modules/diary/questions/daily_question_contract.dart';
import 'package:journal/modules/diary/questions/daily_question_store.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/local_ai/core/ai_router.dart';

/// Device-local opt-in. Not synced: each phone decides for itself.
const dailyQuestionsKey = CacheKey<bool>(CacheNamespace.app, 'dailyQuestions');

abstract interface class DailyQuestionPreference {
  bool get enabled;
  Future<void> setEnabled(bool value);
}

class CachedDailyQuestionPreference implements DailyQuestionPreference {
  const CachedDailyQuestionPreference();
  @override
  bool get enabled {
    try {
      return CacheStorage.instance.get(dailyQuestionsKey) ?? false;
    } on StateError {
      return false; // Storage not initialized: stay opted out.
    }
  }

  @override
  Future<void> setEnabled(bool value) =>
      CacheStorage.instance.set(dailyQuestionsKey, value);
}

final dailyQuestionPreferenceProvider = Provider<DailyQuestionPreference>(
  (ref) => const CachedDailyQuestionPreference(),
);

/// Whether daily questions are on, without building the task controller.
class DailyQuestionEnabled extends Notifier<bool> {
  @override
  bool build() => ref.read(dailyQuestionPreferenceProvider).enabled;

  Future<void> set(bool value) async {
    await ref.read(dailyQuestionPreferenceProvider).setEnabled(value);
    if (ref.mounted) state = value;
  }
}

final dailyQuestionEnabledProvider =
    NotifierProvider<DailyQuestionEnabled, bool>(DailyQuestionEnabled.new);

final dailyQuestionStoreProvider = Provider<DailyQuestionStore>(
  (ref) => DailyQuestionStore(ref.watch(objectBoxProvider).store),
);

/// The phone's current civil day. Overridable so tests can change dates.
final dailyQuestionClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

class DailyQuestionView {
  const DailyQuestionView(this.id, this.question);
  final int id;
  final DailyQuestion question;
}

class DailyQuestionState {
  const DailyQuestionState({
    required this.enabled,
    this.message,
    this.revision = 0,
  });
  final bool enabled;

  /// Why the last request produced no question, shown with the plain prompt.
  final String? message;

  /// Bumped when stored questions change so watchers rebuild.
  final int revision;
}

/// J02: an optional question for today. Once opted in, one is requested
/// automatically while the computer is connected and today has no current
/// question, and again after today's entries change. It never writes diary
/// data; the user can also ask for another one from the diary helper.
class DailyQuestionController extends Notifier<DailyQuestionState> {
  DailyQuestionStore get _store => ref.read(dailyQuestionStoreProvider);
  DiaryRepository get _diary => ref.read(diaryRepositoryProvider);
  String get _today =>
      DiaryRepository.formatDateKey(ref.read(dailyQuestionClockProvider)());

  /// Day and entries already asked about automatically on this connection,
  /// so a rejected or failed answer is not requested again in a loop.
  final _attempted = <String>{};

  /// Whether a daily question is being asked in the shared task slot.
  static bool asking(NoteSummaryState summary) =>
      summary.handle?.isDailyQuestion == true &&
      (!summary.terminal || summary.busy);

  @override
  DailyQuestionState build() {
    ref.listen(
      noteSummaryProvider,
      (_, next) => scheduleMicrotask(() {
        if (!ref.mounted) return;
        unawaited(_consume(next));
        ensure();
      }),
      fireImmediately: true,
    );
    ref.listen(aiOperationAvailableProvider(dailyQuestionOperation), (
      previous,
      next,
    ) {
      if (next && previous != next) {
        _attempted.clear();
      }
      ensure();
    });
    ref.listen(diaryDaysProvider, (_, _) => ensure());
    return DailyQuestionState(enabled: ref.watch(dailyQuestionEnabledProvider));
  }

  /// Requests today's question when none is current. Safe to call often:
  /// it does nothing while offline, while any task holds the slot, or when
  /// today's entries were already asked about on this connection.
  void ensure() => scheduleMicrotask(() {
    if (ref.mounted) unawaited(_auto());
  });

  Future<void> _auto() async {
    if (!state.enabled ||
        !ref.read(aiOperationAvailableProvider(dailyQuestionOperation))) {
      return;
    }
    final summary = ref.read(noteSummaryProvider);
    if (summary.handle != null || summary.busy) return;
    final day = _today;
    if (current(day) != null) return;
    if (!_attempted.add('$day|${dailyQuestionBasis(_diary.getDay(day))}')) {
      return;
    }
    await request(day);
  }

  void _set({String? message, bool clearMessage = false}) {
    state = DailyQuestionState(
      enabled: state.enabled,
      message: clearMessage ? null : message ?? state.message,
      revision: state.revision + 1,
    );
  }

  /// Today's question, or null when none is cached, it belongs to another
  /// civil day, today's entries changed since it was asked, or its source
  /// entry was edited or deleted since.
  DailyQuestionView? current(String day) {
    if (!state.enabled) return null;
    final row = _store.current(day);
    final question = _store.question(row);
    if (row == null || question == null) return null;
    return row.basis == dailyQuestionBasis(_diary.getDay(day)) &&
            question.stillGrounded(_diary.getDay)
        ? DailyQuestionView(row.id, question)
        : null;
  }

  /// The selection a request for [day] would send, for disclosure.
  DailyQuestionSource selection(String day) => DailyQuestionSource.select(
    today: day,
    day: _diary.getDay,
    avoid: _store.recent(dailyQuestionAvoid),
  );

  Future<void> setEnabled(bool value) async {
    final summary = ref.read(noteSummaryProvider);
    final controller = ref.read(noteSummaryProvider.notifier);
    final store = _store;
    // Rebuilds this controller with the new value.
    await ref.read(dailyQuestionEnabledProvider.notifier).set(value);
    if (!value) {
      if (summary.handle?.isDailyQuestion == true) {
        summary.terminal ? await controller.clear() : await controller.cancel();
      }
      store.clear();
    }
  }

  Future<void> request(String day) async {
    if (!state.enabled) return;
    _set(clearMessage: true);
    await ref
        .read(noteSummaryProvider.notifier)
        .startDailyQuestion(selection(day));
    final summary = ref.read(noteSummaryProvider);
    if (summary.handle == null && summary.message != null) {
      _set(message: summary.message);
    }
  }

  /// Hides today's question; it still counts as recently asked.
  void skip(DailyQuestionView view) {
    _store.skip(view.id);
    _set(clearMessage: true);
  }

  /// Keeps [view] until a replacement is saved, so an unavailable computer
  /// never takes away today's question. It is already in recent history.
  Future<void> regenerate(String day, DailyQuestionView view) => request(day);

  Future<void> _consume(NoteSummaryState summary) async {
    final handle = summary.handle;
    if (handle == null || !handle.isDailyQuestion || summary.busy) return;
    final controller = ref.read(noteSummaryProvider.notifier);
    if (!state.enabled) {
      if (summary.terminal) await controller.clear();
      return;
    }
    if (summary.phase == 'completed' && summary.text != null) {
      String? message;
      try {
        final source = DailyQuestionSource.decode(handle.localSource!);
        if (handle.noteId != _today || source.date != handle.noteId) {
          throw const DailyQuestionRejected(
            'The date changed while your computer was thinking. Ask again for today.',
          );
        }
        if (source.basis != dailyQuestionBasis(_diary.getDay(source.date))) {
          throw const DailyQuestionRejected(
            'Today’s entries changed while your computer was thinking, so a new question is needed.',
          );
        }
        final question = DailyQuestion.parse(
          summary.text!,
          source,
          history: _store.recent(),
        );
        if (!question.stillGrounded(_diary.getDay)) {
          throw const DailyQuestionRejected(
            'The entry this question followed up on changed, so it was not shown.',
          );
        }
        _store.add(handle.noteId, question, basis: source.basis);
      } on DailyQuestionRejected catch (error) {
        message = error.message;
      } catch (_) {
        message =
            'Your computer returned something that was not a usable question.';
      }
      await controller.clear();
      _set(message: message, clearMessage: message == null);
    } else if (summary.terminal) {
      final message =
          summary.message ??
          switch (summary.phase) {
            'cancelled' => 'The question request was cancelled.',
            'expired' => 'The question request expired.',
            _ => 'Your computer could not write a question.',
          };
      await controller.clear();
      _set(message: message);
    }
  }
}

final dailyQuestionProvider =
    NotifierProvider<DailyQuestionController, DailyQuestionState>(
      DailyQuestionController.new,
    );
