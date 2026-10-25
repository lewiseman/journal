import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_wise/src/engine/sync_backend.dart';

enum EngineSyncState {
  idle,
  pending,
  syncing,
  offline,
  unauthenticated,
  error;

  IconData get icon => switch (this) {
    EngineSyncState.idle => Icons.cloud_done_rounded,
    EngineSyncState.offline || EngineSyncState.error => Icons.cloud_off_rounded,
    EngineSyncState.syncing => Icons.sync_rounded,
    EngineSyncState.pending ||
    EngineSyncState.unauthenticated => Icons.cloud_outlined,
  };
}

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

  String get statusLabel => switch (status) {
    EngineSyncState.idle =>
      lastSyncTime == null ? 'Connected' : 'Notes backed up',
    EngineSyncState.pending => 'Checking connection',
    EngineSyncState.syncing => 'Syncing notes',
    EngineSyncState.offline => 'Not connected',
    EngineSyncState.unauthenticated => 'On this device',
    EngineSyncState.error => 'Sync needs attention',
  };

  String descriptionFor(SyncBackend backend) => switch (status) {
    EngineSyncState.idle =>
      lastSyncTime == null
          ? 'New note edits will back up to ${backend.displayName}.'
          : 'Your latest note upload is safely in ${backend.displayName}.',
    EngineSyncState.pending =>
      'Looking for your existing ${backend.displayName} connection.',
    EngineSyncState.syncing =>
      'Saving your latest note to ${backend.displayName}.',
    EngineSyncState.offline => 'Please check your connection and try again.',
    EngineSyncState.unauthenticated =>
      'Connect ${backend.displayName} to back up your notes as you write.',
    EngineSyncState.error =>
      lastError ?? 'Please check your connection and try again.',
  };
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
