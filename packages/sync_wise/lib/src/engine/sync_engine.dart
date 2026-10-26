import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/network_service.dart';
import '../storage/sync_state_store.dart';
import '../utils/canonical_json.dart';
import '../utils/concurrent_sync.dart';
import 'sync_backend.dart';
import 'sync_client.dart';
import 'sync_collection.dart';

enum EngineSyncState {
  idle,
  pending,
  syncing,
  offline,
  unauthenticated,
  error;

  String get statusLabel => switch (this) {
    idle => 'Connected',
    pending => 'Changes pending',
    syncing => 'Syncing journal',
    offline => 'Offline',
    unauthenticated => 'On this device',
    error => 'Sync needs attention',
  };
  IconData get icon => switch (this) {
    idle => Icons.cloud_done_rounded,
    offline || error => Icons.cloud_off_rounded,
    syncing => Icons.sync_rounded,
    pending || unauthenticated => Icons.cloud_outlined,
  };
}

@immutable
class SyncEngineState {
  final EngineSyncState status;
  final DateTime? lastSyncTime;
  final String? lastError;
  final String? activity;
  final SyncDeviceRole role;
  final PrimaryDevice? primary;
  const SyncEngineState({
    this.status = EngineSyncState.idle,
    this.lastSyncTime,
    this.lastError,
    this.activity,
    this.role = SyncDeviceRole.unknown,
    this.primary,
  });
  bool get isSyncing => status == EngineSyncState.syncing;
  String get statusLabel =>
      status == EngineSyncState.idle && lastSyncTime != null
      ? 'Journal synced'
      : status.statusLabel;
  String descriptionFor(SyncBackend backend) => switch (status) {
    EngineSyncState.idle =>
      role == SyncDeviceRole.secondary
          ? 'New entries are sent to ${backend.displayName}.'
          : 'Notes and diaries sync with ${backend.displayName}.',
    EngineSyncState.pending =>
      activity ?? 'Your changes are saved locally and waiting to sync.',
    EngineSyncState.syncing =>
      activity ?? 'Syncing with ${backend.displayName}.',
    EngineSyncState.offline =>
      'Your changes are saved here and will retry when connected.',
    EngineSyncState.unauthenticated =>
      'Connect ${backend.displayName} to sync notes and diaries.',
    EngineSyncState.error =>
      lastError ?? 'Sync could not finish. Your changes are saved here.',
  };
}

class SyncEngineConfig {
  final SyncBackend backend;
  final String deviceId;
  final String deviceName;
  final SyncNetwork network;
  final List<SyncCollection> collections;
  final SyncStateStore storage;
  final Future<bool> Function()? canSync;
  final DateTime Function() now;
  SyncEngineConfig({
    required this.backend,
    required this.deviceId,
    required this.deviceName,
    required this.network,
    required List<SyncCollection> collections,
    required this.storage,
    this.canSync,
    DateTime Function()? now,
  }) : collections = List.unmodifiable(collections),
       now = now ?? storage.now;
}

class _Runtime {
  final SyncEngineConfig config;
  bool disposed = false, suspended = false, initialFullRequired = true;
  bool trailing = false;
  int failures = 0;
  Timer? debounce, retry;
  DateTime? finished;
  Future<void>? active;
  SyncSession? session;
  _Runtime(this.config);
  void cancelTimers() {
    debounce?.cancel();
    retry?.cancel();
  }
}

/// Handwritten Notifier: dependencies are supplied by the host's provider factory.
class SyncEngine extends Notifier<SyncEngineState> {
  final SyncEngineConfig Function(Ref) configure;
  late _Runtime _runtime;
  bool _resetSuspended = false;
  SyncEngine(this.configure);
  @override
  SyncEngineState build() {
    final runtime = _runtime = _Runtime(configure(ref))
      ..suspended = _resetSuspended;
    ref.onDispose(() {
      runtime.disposed = true;
      runtime.cancelTimers();
      runtime.session?.close();
    });
    return SyncEngineState(
      role: runtime.config.storage.role,
      primary: runtime.config.storage.primary,
    );
  }

  bool _alive(_Runtime run) =>
      !run.disposed && ref.mounted && identical(run, _runtime);
  void _set(
    _Runtime run,
    EngineSyncState status, {
    String? activity,
    String? error,
    DateTime? completed,
  }) {
    if (!_alive(run)) return;
    state = SyncEngineState(
      status: status,
      activity: activity,
      lastError: error,
      lastSyncTime: completed ?? state.lastSyncTime,
      role: run.config.storage.role,
      primary: run.config.storage.primary,
    );
  }

  Duration _remaining(_Runtime run) {
    if (run.finished == null) return Duration.zero;
    final left =
        const Duration(minutes: 1) - run.config.now().difference(run.finished!);
    return left.isNegative ? Duration.zero : left;
  }

  void scheduleSync({Duration debounce = const Duration(milliseconds: 300)}) {
    final run = _runtime;
    if (!_alive(run) || run.suspended) return;
    if (run.active != null) {
      run.trailing = true;
      return;
    }
    run.cancelTimers();
    final remaining = _remaining(run);
    _set(run, EngineSyncState.pending);
    run.debounce = Timer(
      remaining > debounce ? remaining : debounce,
      () => syncNow(),
    );
  }

  Future<void> syncNow({bool manual = false}) {
    return _start(manual: manual);
  }

  /// Explicit recovery after reinstall. Serialized with ordinary sync, then
  /// performs a full restore as the newly designated primary.
  Future<void> reclaimPrimary({PrimaryDevice? expectedPrimary}) async {
    final run = _runtime;
    final expected = expectedPrimary ?? run.config.storage.primary;
    while (_alive(run) && !run.suspended && run.active != null) {
      await run.active;
    }
    if (!_alive(run) || run.suspended) return;
    await _start(manual: true, reclaim: true, expectedPrimary: expected);
  }

  Future<void> _start({
    required bool manual,
    bool reclaim = false,
    PrimaryDevice? expectedPrimary,
  }) {
    final run = _runtime;
    if (!_alive(run) || run.suspended || run.active != null) {
      return Future.value();
    }
    if (!manual && _remaining(run) > Duration.zero) return Future.value();
    run.cancelTimers();
    final completion = Completer<void>();
    run.active = completion.future;
    unawaited(
      _execute(
        run,
        manual,
        completion,
        reclaim: reclaim,
        expectedPrimary: expectedPrimary,
      ),
    );
    return completion.future;
  }

  Future<void> _execute(
    _Runtime run,
    bool manual,
    Completer<void> completion, {
    bool reclaim = false,
    PrimaryDevice? expectedPrimary,
  }) async {
    var attempted = false;
    try {
      final config = run.config;
      final storage = config.storage;
      final hasPending =
          config.collections.any(
            (c) => c.pendingIds.any((id) => !storage.blocked(c.type, id)),
          ) ||
          storage.pendingCreations.isNotEmpty;
      if (!manual && !run.initialFullRequired && !hasPending) {
        if (state.status == EngineSyncState.pending) {
          _set(
            run,
            storage.hasBlockedDocuments
                ? EngineSyncState.pending
                : EngineSyncState.idle,
            activity: storage.hasBlockedDocuments
                ? 'Use Sync Now to refresh shared data.'
                : null,
          );
        }
        return;
      }
      attempted = true;
      _set(run, EngineSyncState.syncing, activity: 'Checking connection…');
      if (config.canSync != null && !await config.canSync!()) {
        throw StateError('Finish the account reset before syncing.');
      }
      if (!_alive(run)) return;
      if (!await config.network.isOnline()) {
        _set(run, EngineSyncState.offline);
        return;
      }
      if (!_alive(run)) return;
      run.session = await config.backend.openSession();
      if (!_alive(run)) return;
      final session = run.session;
      final account = config.backend.auth.currentUser;
      if (session == null || account == null) {
        _set(run, EngineSyncState.unauthenticated);
        return;
      }
      storage.bind(config.backend.id, account.id);
      var primary = await session.client.resolvePrimary(
        deviceId: config.deviceId,
        deviceName: config.deviceName,
      );
      if (!_alive(run)) return;
      final previous = storage.role;
      storage.setPrimary(primary);
      if (reclaim) {
        _set(
          run,
          EngineSyncState.syncing,
          activity: 'Reclaiming primary role…',
        );
        primary = await session.client.reclaimPrimary(
          expectedPrimary: expectedPrimary ?? primary,
          deviceId: config.deviceId,
          deviceName: config.deviceName,
        );
        if (!_alive(run)) return;
        storage.setPrimary(primary);
        run.initialFullRequired = true;
      }
      if (previous == SyncDeviceRole.secondary &&
          storage.role == SyncDeviceRole.primary) {
        run.initialFullRequired = true;
      }
      _set(
        run,
        EngineSyncState.syncing,
        activity: storage.role == SyncDeviceRole.primary
            ? 'Syncing primary device…'
            : 'Sending new entries…',
      );
      final errors = <String>[];
      var deferred = false;
      if (storage.role == SyncDeviceRole.secondary) {
        for (final collection in config.collections) {
          collection.restrictToSecondary();
        }
        await _secondary(run, session.client, errors);
        if (!_alive(run)) return;
        run.initialFullRequired = false;
      } else {
        final full = manual || run.initialFullRequired;
        final blocked = <String>{};
        var listingFailed = false;
        if (full) {
          for (final collection in config.collections) {
            final type = collection.type;
            try {
              void failure(String id, Object error) {
                blocked.add('$type/$id');
                errors.add('$type $id: $error');
                listingFailed = true;
              }

              final listed = await session.client.listDocuments(
                type: type,
                onError: failure,
              );
              if (!_alive(run)) return;
              final old = primary.migrationComplete
                  ? <RemoteDocument>[]
                  : await session.client.listLegacyDocuments(
                      type: type,
                      onError: failure,
                    );
              if (!_alive(run)) return;
              List<RemoteDocument> validated(List<RemoteDocument> documents) {
                final valid = <RemoteDocument>[];
                for (final document in documents) {
                  try {
                    if (document.type != type ||
                        collection.decode(document.payload).id !=
                            document.documentId) {
                      throw const FormatException(
                        'Document ID or type does not match its metadata.',
                      );
                    }
                    valid.add(document);
                  } catch (error) {
                    failure(document.documentId, error);
                  }
                }
                return valid;
              }

              final remote = validated(listed);
              final legacy = validated(old);
              final canonical = <String, RemoteDocument>{};
              for (final document in remote) {
                final previous = canonical[document.documentId];
                if (previous == null || document.isCanonical) {
                  canonical[document.documentId] = document;
                }
              }
              final incoming =
                  legacy.isEmpty && canonical.length == remote.length
                  ? remote.map((d) => collection.decode(d.payload)).toList()
                  : collection.migrateLegacy([
                      ...legacy,
                      ...remote,
                    ], primary.deviceId);
              for (final document in incoming) {
                if (blocked.contains('$type/${document.id}')) continue;
                try {
                  final waiting = collection.mergeRemote(
                    document,
                    now: config.now(),
                  );
                  if (waiting) {
                    storage.block(type, document.id);
                    deferred = true;
                  } else {
                    storage.unblock(type, document.id);
                    final baseline = canonical[document.id];
                    if (baseline != null && baseline.isCanonical) {
                      storage.saveBaseline(baseline);
                      if (canonicalJson(
                            collection.decode(baseline.payload).payload,
                          ) !=
                          canonicalJson(document.payload)) {
                        collection.markPending(document.id);
                      }
                    } else {
                      storage.forgetBaseline(type, document.id);
                      collection.markPending(document.id);
                    }
                  }
                } catch (error) {
                  blocked.add('$type/${document.id}');
                  errors.add('$type ${document.id}: $error');
                }
              }
              // A complete listing also repairs missing primary backups.
              if (!listingFailed) {
                for (final id in collection.allIds) {
                  if (!canonical.containsKey(id) &&
                      !incoming.any((document) => document.id == id)) {
                    storage.forgetBaseline(type, id);
                    storage.unblock(type, id);
                    collection.markPending(id);
                  }
                }
              }
            } catch (error) {
              blocked.add('$type/*');
              errors.add('$type listing: $error');
              listingFailed = true;
            }
          }
          if (!listingFailed) run.initialFullRequired = false;
        }
        if (!_alive(run)) return;
        await _primaryUploads(
          run,
          session.client,
          blocked,
          errors,
          full: full,
          onDeferred: () => deferred = true,
        );
        if (!_alive(run)) return;
        if (full &&
            !primary.migrationComplete &&
            errors.isEmpty &&
            !deferred &&
            config.collections.every((c) => c.pendingIds.isEmpty)) {
          await session.client.completeMigration(primary);
        }
      }
      if (!_alive(run)) return;
      if (errors.isNotEmpty) throw StateError(errors.take(3).join(' | '));
      run.failures = 0;
      final waiting =
          deferred ||
          storage.hasBlockedDocuments ||
          config.collections.any(
            (c) =>
                c.pendingIds.isNotEmpty &&
                storage.role == SyncDeviceRole.primary,
          ) ||
          storage.pendingCreations.isNotEmpty;
      _set(
        run,
        waiting ? EngineSyncState.pending : EngineSyncState.idle,
        activity: waiting
            ? 'Changes pending. Use Sync Now to refresh shared data.'
            : null,
        completed: waiting ? null : config.now(),
      );
    } catch (error) {
      if (error is PrimaryDeviceChanged && _alive(run)) {
        run.config.storage.setPrimary(error.primary);
      }
      _set(run, EngineSyncState.error, error: error.toString());
    } finally {
      run.session?.close();
      run.session = null;
      if (attempted) run.finished = run.config.now();
      run.active = null;
      if (_alive(run) && !run.suspended) {
        if (attempted &&
            (state.status == EngineSyncState.error ||
                state.status == EngineSyncState.offline)) {
          final seconds = (5 * (1 << run.failures.clamp(0, 6))).clamp(60, 320);
          run.failures++;
          run.retry = Timer(Duration(seconds: seconds), () => syncNow());
        } else if (run.trailing) {
          run.trailing = false;
          scheduleSync();
        }
      }
      completion.complete();
    }
  }

  Future<void> _primaryUploads(
    _Runtime run,
    SyncClient client,
    Set<String> blocked,
    List<String> errors, {
    required bool full,
    required void Function() onDeferred,
  }) async {
    final tasks = <Future<void> Function()>[];
    final storage = run.config.storage;
    for (final collection in run.config.collections) {
      for (final id in collection.pendingIds) {
        if (storage.blocked(collection.type, id) ||
            blocked.contains('${collection.type}/*') ||
            blocked.contains('${collection.type}/$id')) {
          continue;
        }
        tasks.add(() async {
          for (var attempt = 0; attempt < (full ? 3 : 1); attempt++) {
            if (!_alive(run)) return;
            try {
              final snapshot = collection.read(id);
              if (snapshot == null) return;
              final remote = await client.writeDocument(
                type: collection.type,
                documentId: id,
                payload: snapshot.payload,
                baseline: storage.baseline(collection.type, id),
              );
              if (!_alive(run)) return;
              storage.saveBaseline(remote);
              if (canonicalJson(collection.read(id)?.payload) ==
                  canonicalJson(snapshot.payload)) {
                collection.acknowledgeUpload(snapshot);
              } else {
                run.trailing = true;
              }
              return;
            } on RemoteDocumentChanged {
              if (!full || attempt == 2) {
                storage.block(collection.type, id);
                onDeferred();
                return;
              }
              final latest = await client.readDocument(
                type: collection.type,
                documentId: id,
              );
              if (!_alive(run)) return;
              if (latest == null) {
                storage.forgetBaseline(collection.type, id);
                continue;
              }
              if (collection.mergeRemote(
                collection.decode(latest.payload),
                now: run.config.now(),
              )) {
                storage.block(collection.type, id);
                onDeferred();
                return;
              }
              storage.saveBaseline(latest);
            } catch (error) {
              errors.add('${collection.type} $id: $error');
              return;
            }
          }
        });
      }
    }
    await forEachConcurrent(tasks, (task) => task());
  }

  Future<void> _secondary(
    _Runtime run,
    SyncClient client,
    List<String> errors,
  ) async {
    final groups = <String, List<PendingCreation>>{};
    for (final operation in run.config.storage.pendingCreations) {
      groups
          .putIfAbsent('${operation.type}/${operation.documentId}', () => [])
          .add(operation);
    }
    await forEachConcurrent(groups.values, (operations) async {
      final first = operations.first;
      final collection = run.config.collections.singleWhere(
        (c) => c.type == first.type,
      );
      for (var attempt = 0; attempt < 3; attempt++) {
        if (!_alive(run)) return;
        try {
          final latest = !collection.requiresRemoteForCreation
              ? null
              : await client.readDocument(
                  type: first.type,
                  documentId: first.documentId,
                );
          if (!_alive(run)) return;
          final snapshot = collection.appendCreations(
            latest == null ? null : collection.decode(latest.payload),
            operations,
          );
          final uploaded = await client.writeDocument(
            type: first.type,
            documentId: first.documentId,
            payload: snapshot.payload,
            baseline: latest,
          );
          if (!_alive(run)) return;
          run.config.storage.saveBaseline(uploaded);
          collection.acknowledgeCreations(operations, snapshot);
          return;
        } on RemoteDocumentChanged {
          if (!collection.requiresRemoteForCreation) {
            final existing = await client.readDocument(
              type: first.type,
              documentId: first.documentId,
            );
            if (!_alive(run)) return;
            if (existing != null) {
              collection.acknowledgeCreations(
                operations,
                collection.decode(existing.payload),
              );
              return;
            }
          }
          if (attempt == 2) {
            errors.add(
              '${first.type} ${first.documentId}: retry sending this entry.',
            );
          }
        } catch (error) {
          errors.add('${first.type} ${first.documentId}: $error');
          return;
        }
      }
    });
  }

  Future<void> suspendForReset({bool requireIdle = false}) async {
    final run = _runtime;
    if (requireIdle && run.active != null) {
      throw StateError(
        'Wait for sync to finish before resetting account data.',
      );
    }
    _resetSuspended = true;
    run.suspended = true;
    run.cancelTimers();
    await run.active;
  }

  void resumeAfterReset({required bool completed}) {
    final run = _runtime;
    if (!_alive(run)) return;
    _resetSuspended = false;
    run.suspended = false;
    if (completed) {
      run.config.storage.clear();
      run.initialFullRequired = true;
      run.finished = null;
      run.failures = 0;
      run.trailing = false;
      state = const SyncEngineState(status: EngineSyncState.unauthenticated);
    }
  }
}
