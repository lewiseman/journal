import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journal/modules/recall/recall_contract.dart';
import 'package:journal/modules/recall/recall_embedder.dart';
import 'package:journal/modules/recall/recall_index.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';
import 'package:journal/utils/cache.dart';

/// Device-local switches, one per collection, on unless turned off. Not
/// synced: each phone decides what it sends to its own paired computer.
const recallKeys = {
  RecallKind.diary: CacheKey<bool>(CacheNamespace.app, 'recallDiary'),
  RecallKind.note: CacheKey<bool>(CacheNamespace.app, 'recallNotes'),
  RecallKind.thought: CacheKey<bool>(CacheNamespace.app, 'recallThoughts'),
};

abstract interface class RecallPreference {
  Set<RecallKind> get enabled;
  Future<void> set(RecallKind kind, bool value);
}

class CachedRecallPreference implements RecallPreference {
  const CachedRecallPreference();
  @override
  Set<RecallKind> get enabled {
    try {
      return {
        for (final e in recallKeys.entries)
          if (CacheStorage.instance.get(e.value) ?? true) e.key,
      };
    } on StateError {
      return const {}; // Storage not initialized: stay off.
    }
  }

  @override
  Future<void> set(RecallKind kind, bool value) =>
      CacheStorage.instance.set(recallKeys[kind]!, value);
}

final recallPreferenceProvider = Provider<RecallPreference>(
  (ref) => const CachedRecallPreference(),
);

final recallIndexProvider = Provider<RecallIndex>(
  (ref) => RecallIndex(ref.watch(objectBoxProvider).store),
);

/// The paired computer's ready embedding model, or null.
final recallCapabilityProvider = Provider<EmbeddingCapability?>((ref) {
  final state = ref.watch(companionControllerProvider);
  return state.phase == CompanionPhase.connected
      ? EmbeddingCapability.fromStatus(state.status)
      : null;
});

final recallEmbedderProvider = Provider<TextEmbedder>(
  (ref) => CompanionTextEmbedder(
    computer: () {
      final c = ref.read(companionControllerProvider).selected;
      if (c == null) {
        throw const CompanionFailure(
          'UNAVAILABLE',
          'Pair your computer in More → Local QVAC.',
        );
      }
      return c;
    },
  ),
);

/// The texts each collection would index right now.
final recallSourcesProvider =
    Provider<Iterable<RecallSource> Function(RecallKind)>((ref) {
      final db = ref.watch(objectBoxProvider);
      return (kind) => switch (kind) {
        RecallKind.diary => RecallSource.diary(db.diaryBox.getAll()),
        RecallKind.note => RecallSource.notes(db.noteBox.getAll()),
        RecallKind.thought => RecallSource.thoughts(db.thoughtBox.getAll()),
      };
    });

class RecallIndexState {
  const RecallIndexState({
    required this.enabled,
    this.paused = false,
    this.running = false,
    this.done = 0,
    this.total = 0,
    this.indexed = const {},
    this.message,
  });
  final Set<RecallKind> enabled;
  final bool paused, running;

  /// Progress of the current pass.
  final int done, total;

  /// Vectors stored per collection for the current model.
  final Map<RecallKind, int> indexed;
  final String? message;

  RecallIndexState copyWith({
    Set<RecallKind>? enabled,
    bool? paused,
    bool? running,
    int? done,
    int? total,
    Map<RecallKind, int>? indexed,
    String? message,
    bool clearMessage = false,
  }) => RecallIndexState(
    enabled: enabled ?? this.enabled,
    paused: paused ?? this.paused,
    running: running ?? this.running,
    done: done ?? this.done,
    total: total ?? this.total,
    indexed: indexed ?? this.indexed,
    message: clearMessage ? null : message ?? this.message,
  );
}

/// S03b: keeps the phone's vectors in step with its opted-in text, only
/// while the app is in the foreground and the computer is connected. New
/// and edited sources are embedded in batches; deleted sources and vectors
/// from another embedding model are removed first.
class RecallIndexer extends Notifier<RecallIndexState> {
  Timer? _debounce;
  int _generation = 0;
  bool _foreground = true;

  RecallIndex get _index => ref.read(recallIndexProvider);

  @override
  RecallIndexState build() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    final listener = AppLifecycleListener(
      onStateChange: (value) {
        _foreground = value == AppLifecycleState.resumed;
        _foreground ? schedule() : _generation++;
      },
    );
    final changes = ref
        .read(journalChangesProvider)
        .stream
        .listen((_) => schedule(delay: const Duration(seconds: 3)));
    ref.listen(recallCapabilityProvider, (previous, next) {
      if (next?.model != previous?.model) schedule();
    });
    ref.onDispose(() {
      _generation++;
      _debounce?.cancel();
      listener.dispose();
      changes.cancel();
    });
    final enabled = ref.read(recallPreferenceProvider).enabled;
    scheduleMicrotask(schedule);
    return RecallIndexState(enabled: enabled, indexed: _counts(enabled));
  }

  Map<RecallKind, int> _counts(Set<RecallKind> enabled) {
    final model = ref.read(recallCapabilityProvider)?.model;
    if (model == null) return const {};
    try {
      return {for (final k in enabled) k: _index.count(k, model)};
    } catch (_) {
      return const {};
    }
  }

  void schedule({Duration delay = const Duration(milliseconds: 600)}) {
    if (!ref.mounted) return;
    _debounce?.cancel();
    _debounce = Timer(delay, () => unawaited(run()));
  }

  /// Turning a collection off deletes its vectors at once.
  Future<void> setEnabled(RecallKind kind, bool value) async {
    await ref.read(recallPreferenceProvider).set(kind, value);
    if (!ref.mounted) return;
    if (!value) {
      _generation++;
      _index.clear(kind);
    }
    final enabled = {...state.enabled};
    value ? enabled.add(kind) : enabled.remove(kind);
    state = state.copyWith(
      enabled: enabled,
      indexed: _counts(enabled),
      running: false,
      clearMessage: true,
    );
    schedule();
  }

  void pause() {
    _generation++;
    state = state.copyWith(paused: true, running: false);
  }

  void resume() {
    state = state.copyWith(paused: false, clearMessage: true);
    schedule(delay: Duration.zero);
  }

  /// One indexing pass. Safe to call repeatedly; stops at the next batch
  /// boundary when paused, backgrounded, opted out or disconnected.
  Future<void> run() async {
    if (!ref.mounted || state.running || state.paused || !_foreground) return;
    final enabled = state.enabled;
    if (enabled.isEmpty) return;
    final capability = ref.read(recallCapabilityProvider);
    if (capability == null) {
      state = state.copyWith(
        indexed: const {},
        message: 'Waiting for your computer and its embedding model. Search uses keywords until then.',
      );
      return;
    }
    final generation = ++_generation;
    final model = capability.model;
    final sources = ref.read(recallSourcesProvider);
    final todo = <RecallSource>[];
    for (final kind in RecallKind.values.where(enabled.contains)) {
      final current = {for (final s in sources(kind)) s.key: s};
      _index.prune(kind, model, current.keys.toSet());
      final stored = _index.hashes(kind, model);
      todo.addAll(current.values.where((s) => stored[s.key] != s.hash));
    }
    state = state.copyWith(
      running: todo.isNotEmpty,
      done: 0,
      total: todo.length,
      indexed: _counts(enabled),
      clearMessage: true,
    );
    if (todo.isEmpty) return;
    final embedder = ref.read(recallEmbedderProvider);
    var done = 0;
    try {
      for (final batch in _batches(todo)) {
        if (!ref.mounted || generation != _generation) return;
        final vectors = await embedder.embed(model, [
          for (final s in batch) EmbedItem(s.key, 'document', s.text),
        ]);
        if (!ref.mounted || generation != _generation) return;
        // A collection switched off mid-batch must not regain vectors.
        final still = ref.read(recallPreferenceProvider).enabled;
        for (final s in batch) {
          if (still.contains(s.kind)) _index.put(s, model, vectors[s.key]!);
        }
        done += batch.length;
        state = state.copyWith(done: done, indexed: _counts(state.enabled));
      }
      if (ref.mounted && generation == _generation) {
        state = state.copyWith(running: false, clearMessage: true);
      }
    } on CompanionFailure catch (e) {
      if (!ref.mounted || generation != _generation) return;
      state = state.copyWith(
        running: false,
        message: e.code == 'MODEL_CHANGED'
            ? 'Your computer switched embedding model. The index will rebuild after it reconnects.'
            : 'Indexing stopped: ${e.message} It continues when you return.',
      );
      if (e.code == 'MODEL_CHANGED') {
        unawaited(ref.read(companionControllerProvider.notifier).reconnect());
      }
    } finally {
      if (ref.mounted && generation == _generation && state.running) {
        state = state.copyWith(running: false);
      }
    }
  }

  /// Batches of at most [embedBatchItems] that fit [embedInputBytes].
  static Iterable<List<RecallSource>> _batches(List<RecallSource> todo) sync* {
    var batch = <RecallSource>[];
    var bytes = 64;
    for (final s in todo) {
      final size = utf8.encode(jsonEncode(s.text)).length + s.key.length + 48;
      if (batch.length == embedBatchItems ||
          (batch.isNotEmpty && bytes + size > embedInputBytes)) {
        yield batch;
        batch = [];
        bytes = 64;
      }
      batch.add(s);
      bytes += size;
    }
    if (batch.isNotEmpty) yield batch;
  }
}

final recallIndexerProvider = NotifierProvider<RecallIndexer, RecallIndexState>(
  RecallIndexer.new,
);
