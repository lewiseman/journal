import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_wise/src/engine/sync_backend.dart';

enum EngineSyncState { idle, pending, syncing, offline, unauthenticated, error }

@immutable
class SyncEngineState {
  final EngineSyncState status;
  final DateTime? lastSyncTime;
  final String? lastError;
  final String? activity;
  const SyncEngineState({
    this.status = EngineSyncState.idle,
    this.lastSyncTime,
    this.lastError,
    this.activity,
  });
  bool get isSyncing => status == EngineSyncState.syncing;
}

/// Schedules and reconciles replicas without depending on an app's database,
/// domain models, authentication SDK or cloud transport.
class SyncEngine extends Notifier<SyncEngineState> {
  static const _minimumSyncInterval = Duration(minutes: 1);

  final Provider<SyncBackend> backendProvider;

  SyncEngine({required this.backendProvider});

  @override
  SyncEngineState build() {
    return SyncEngineState();
  }

  Future<void> syncNow({bool manual = false}) {
    return Future.value();
  }
}
