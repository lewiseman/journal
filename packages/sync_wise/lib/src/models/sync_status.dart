/// Sync status for locally persisted entities.
enum SyncStatus {
  synced(0),
  pendingUpload(1),
  syncing(2),
  error(3),
  localOnly(4);

  final int value;
  const SyncStatus(this.value);

  static SyncStatus fromValue(int value) {
    return SyncStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => SyncStatus.pendingUpload,
    );
  }
}
