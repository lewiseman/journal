import 'dart:async';

import 'package:journal/modules/local_ai/core/ai_router.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journal/modules/flow/controllers/thoughts_providers.dart';
import 'package:journal/modules/flow/models/thought_entity.dart';
import 'package:journal/modules/flow/reflection/thought_reflection_contract.dart';
import 'package:journal/modules/flow/reflection/thought_reflection_entity.dart';
import 'package:journal/modules/flow/reflection/thought_reflection_store.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';

final thoughtReflectionStoreProvider = Provider<ThoughtReflectionStore>(
  (ref) => ThoughtReflectionStore(ref.watch(objectBoxProvider).store),
);

/// Whether to offer reflections at all: only once a computer is paired, so
/// Flow stays exactly as it was for everyone else.
final thoughtReflectionAvailableProvider = Provider<bool>(
  (ref) =>
      ref.watch(
        companionControllerProvider.select((s) => s.computers.isNotEmpty),
      ) ||
      ref.watch(aiOperationAvailableProvider(thoughtReflectionOperation)),
);

class ThoughtReflectionView {
  const ThoughtReflectionView({this.kept, this.proposal});
  final ThoughtReflectionEntity? kept, proposal;
}

class ThoughtReflectionState {
  const ThoughtReflectionState({this.thought, this.message, this.revision = 0});

  /// The thought [message] is about.
  final String? thought;

  /// Why the last request for [thought] produced nothing to review.
  final String? message;

  /// Bumped when stored reflections change so watchers rebuild.
  final int revision;
}

/// L01: an optional one-line reflection on one saved thought, requested only
/// by the user. The thought itself is never changed, and capture never waits.
/// Writes no synced data, so secondary devices may use it too.
class ThoughtReflectionController extends Notifier<ThoughtReflectionState> {
  ThoughtReflectionStore get _store => ref.read(thoughtReflectionStoreProvider);
  bool get _blocked => ref.read(accountResetProvider).blocksDataAccess;

  @override
  ThoughtReflectionState build() {
    ref.listen(
      noteSummaryProvider,
      (_, next) => scheduleMicrotask(() {
        if (ref.mounted) unawaited(_consume(next));
      }),
      fireImmediately: true,
    );
    return const ThoughtReflectionState();
  }

  void _set(String? thought, String? message) => state = ThoughtReflectionState(
    thought: thought,
    message: message,
    revision: state.revision + 1,
  );

  /// What to show for [thought]. A reflection written for another version
  /// of the thought is never shown.
  ThoughtReflectionView view(ThoughtEntity thought) {
    if (_blocked) return const ThoughtReflectionView();
    final revision = thoughtRevision(thought);
    ThoughtReflectionEntity? current(ThoughtReflectionEntity? row) =>
        row?.revision == revision ? row : null;
    return ThoughtReflectionView(
      kept: current(_store.kept(thought.uuid)),
      proposal: current(_store.proposal(thought.uuid)),
    );
  }

  String? messageFor(ThoughtEntity thought) =>
      state.thought == thought.uuid ? state.message : null;

  /// Whether the shared AI task slot is working on [thought].
  bool working(ThoughtEntity thought, NoteSummaryState summary) =>
      summary.handle?.isThoughtReflection == true &&
      summary.handle!.noteId == thought.uuid;

  Future<void> request(ThoughtEntity thought) async {
    if (_blocked) return;
    final summary = ref.read(noteSummaryProvider);
    if (summary.handle != null && !working(thought, summary)) {
      _set(
        thought.uuid,
        'Another AI request is still open. Finish or clear it in More → Local QVAC → AI task history, then try again.',
      );
      return;
    }
    _set(thought.uuid, null);
    await ref
        .read(noteSummaryProvider.notifier)
        .startThoughtReflection(thought.uuid);
    final after = ref.read(noteSummaryProvider);
    if (ref.mounted && after.handle == null && after.message != null) {
      _set(thought.uuid, after.message);
    }
  }

  /// Keeps the proposal, replacing any earlier kept reflection.
  bool keep(ThoughtReflectionEntity proposal) {
    final kept = !_blocked && _store.keep(proposal.id);
    _set(proposal.thoughtUuid, null);
    return kept;
  }

  /// Dismisses a proposal or removes a kept reflection. The thought stays.
  void remove(ThoughtReflectionEntity row) {
    if (_blocked) return;
    _store.remove(row.id);
    _set(row.thoughtUuid, null);
  }

  Future<void> _consume(NoteSummaryState summary) async {
    final handle = summary.handle;
    if (handle == null || !handle.isThoughtReflection || summary.busy) return;
    final controller = ref.read(noteSummaryProvider.notifier);
    if (summary.phase == 'completed' && summary.text != null) {
      String? message;
      try {
        final thought = ref
            .read(thoughtsRepositoryProvider)
            .getThoughtByUuid(handle.noteId);
        if (thought == null || thoughtRevision(thought) != handle.revision) {
          throw const ThoughtReflectionRejected(
            'This thought changed while your computer was reflecting, so the result was not shown.',
          );
        }
        _store.propose(
          uuid: thought.uuid,
          revision: handle.revision,
          text: parseThoughtReflection(summary.text!, thought.content),
          taskId: handle.id,
        );
      } on ThoughtReflectionRejected catch (error) {
        message = error.message;
      } catch (_) {
        message = 'Your computer returned something that was not a usable reflection.';
      }
      await controller.clear();
      if (ref.mounted) _set(handle.noteId, message);
    } else if (summary.terminal) {
      // The slot's own messages talk about notes and previews.
      final message = switch (summary.phase) {
        'cancelled' =>
          'The reflection was cancelled. Your thought is unchanged.',
        'expired' =>
          'The reflection request expired. Your thought is unchanged.',
        _ => 'Your computer could not write a reflection. Check its writing model and try again.',
      };
      await controller.clear();
      if (ref.mounted) _set(handle.noteId, message);
    }
  }
}

final thoughtReflectionProvider =
    NotifierProvider<ThoughtReflectionController, ThoughtReflectionState>(
      ThoughtReflectionController.new,
    );
