import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/sync_backend.dart';
import '../engine/sync_engine.dart';
import '../network/network_service.dart';
import 'account_reset_storage.dart';

abstract interface class AccountResetLocalData {
  Future<void> clear();
}

class AccountResetState {
  final bool checking, running, pending, completed;
  final String? error;
  final String activity;
  const AccountResetState({
    this.checking = false,
    this.running = false,
    this.pending = false,
    this.error,
    this.activity = '',
    this.completed = false,
  });
  bool get blocksDataAccess => checking || running || pending;
}

class AccountResetConfig {
  final AccountResetStorage storage;
  final SyncEngine engine;
  final SyncBackend backend;
  final SyncNetwork network;
  final AccountResetLocalData localData;
  const AccountResetConfig({
    required this.storage,
    required this.engine,
    required this.backend,
    required this.network,
    required this.localData,
  });
}

class _ResetRun {
  final AccountResetConfig config;
  bool disposed = false;
  SyncSession? session;
  Future<void>? active;
  _ResetRun(this.config);
}

class AccountResetController extends Notifier<AccountResetState> {
  final AccountResetConfig Function(Ref) configure;
  _ResetRun? _current;
  _ResetRun get _run => _current!;
  late Future<void> ready;
  AccountResetController(this.configure);
  @override
  AccountResetState build() {
    final previous = _current;
    final run = _current = _ResetRun(configure(ref));
    ref.onDispose(() {
      run.disposed = true;
      run.session?.close();
    });
    ready = _initialize(run, previous);
    return const AccountResetState(checking: true);
  }

  bool _alive(_ResetRun run) =>
      !run.disposed && ref.mounted && identical(run, _run);
  Future<void> _initialize(_ResetRun run, _ResetRun? previous) async {
    await Future<void>.value();
    final interrupted = previous?.active;
    try {
      if (interrupted != null) await interrupted;
      if (!_alive(run)) return;
      final pending = !await run.config.storage.canSync();
      if (!_alive(run)) return;
      if (pending) {
        await run.config.engine.suspendForReset();
      } else if (interrupted != null) {
        run.config.engine.resumeAfterReset(completed: false);
      }
      if (_alive(run)) state = AccountResetState(pending: pending);
    } catch (error) {
      if (!_alive(run)) return;
      await run.config.engine.suspendForReset();
      if (_alive(run)) {
        state = AccountResetState(pending: true, error: '$error');
      }
    }
  }

  void _progress(_ResetRun run, String text) {
    if (_alive(run)) {
      state = AccountResetState(running: true, pending: true, activity: text);
    }
  }

  Future<void> reset({String? expectedAccountId}) {
    final run = _run;
    if (run.active != null) return run.active!;
    return run.active = _reset(
      run,
      ready,
      expectedAccountId,
    ).whenComplete(() => run.active = null);
  }

  Future<void> _reset(
    _ResetRun run,
    Future<void> initialization,
    String? expectedAccountId,
  ) async {
    await initialization;
    if (!_alive(run) || state.running) return;
    final config = run.config;
    final auth = config.backend.auth;
    var durable = state.pending;
    state = AccountResetState(
      running: true,
      pending: durable,
      activity: 'Pausing sync…',
    );
    try {
      await config.engine.suspendForReset();
      if (!_alive(run)) return;
      var intent = await config.storage.read();
      if (!_alive(run)) return;
      if (intent != null && intent.backendId != config.backend.id) {
        throw StateError('Reconnect the sync provider used for this reset.');
      }
      if (intent == null && expectedAccountId == null) {
        throw StateError('Confirm the account reset first.');
      }
      if (intent?.remoteDeleted != true) {
        if (!await config.network.isOnline()) {
          throw StateError(
            'Connect to the internet to delete the cloud backups.',
          );
        }
        if (!_alive(run)) return;
        final account = intent?.accountId ?? expectedAccountId!;
        if (intent != null && auth.currentUser?.id != account) {
          if (auth.currentUser != null) await auth.signOut();
          if (!_alive(run)) return;
          await auth.signIn();
        }
        if (!_alive(run)) return;
        if (auth.currentUser?.id != account) {
          throw StateError(
            'Connect the same account you confirmed for this reset.',
          );
        }
        run.session = await config.backend.openSession();
        if (!_alive(run)) return;
        if (run.session == null) {
          throw StateError('Connect your account before resetting data.');
        }
        intent ??= ResetIntent(account, backendId: config.backend.id);
        await config.storage.write(intent);
        durable = true;
        if (!_alive(run)) return;
        _progress(run, 'Deleting cloud backups…');
        await run.session!.client.permanentlyDeleteAllData(
          onProgress: (done, total) =>
              _progress(run, 'Deleting cloud data ($done of $total)…'),
        );
        if (!_alive(run)) return;
        await config.storage.write(
          ResetIntent(
            account,
            backendId: config.backend.id,
            remoteDeleted: true,
          ),
        );
      }
      if (!_alive(run)) return;
      _progress(run, 'Deleting local data…');
      await config.localData.clear();
      if (!_alive(run)) return;
      _progress(run, 'Disconnecting account…');
      await auth.signOut();
      if (!_alive(run)) return;
      await config.storage.finish();
      if (!_alive(run)) return;
      config.engine.resumeAfterReset(completed: true);
      state = const AccountResetState(completed: true);
    } catch (error) {
      if (!_alive(run)) return;
      if (!durable) config.engine.resumeAfterReset(completed: false);
      state = AccountResetState(pending: durable, error: '$error');
    } finally {
      run.session?.close();
      run.session = null;
    }
  }
}
