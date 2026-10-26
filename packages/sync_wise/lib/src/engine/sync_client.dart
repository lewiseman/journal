class PrimaryDevice {
  final String deviceId;
  final String deviceName;
  final String fileId;
  final bool migrationComplete;
  const PrimaryDevice({
    required this.deviceId,
    required this.deviceName,
    required this.fileId,
    this.migrationComplete = false,
  });
  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'device_name': deviceName,
    'file_id': fileId,
    'migration_complete': migrationComplete,
  };
  factory PrimaryDevice.fromJson(Map<String, dynamic> json) => PrimaryDevice(
    deviceId: json['device_id'] as String,
    deviceName: json['device_name'] as String,
    fileId: json['file_id'] as String,
    migrationComplete: json['migration_complete'] == true,
  );
}

class RemoteDocument {
  final String fileId;
  final String type;
  final String documentId;
  final String revision;
  final Map<String, dynamic> payload;
  final String deviceId;

  /// The elected registry points to this file. Other files are retained only
  /// as migration inputs after simultaneous registration.
  final bool isCanonical;
  const RemoteDocument({
    required this.fileId,
    required this.type,
    required this.documentId,
    required this.revision,
    required this.payload,
    this.deviceId = '',
    this.isCanonical = true,
  });
  Map<String, dynamic> toJson() => {
    'file_id': fileId,
    'type': type,
    'document_id': documentId,
    'revision': revision,
    'payload': payload,
    'device_id': deviceId,
    'is_canonical': isCanonical,
  };
  factory RemoteDocument.fromJson(Map<String, dynamic> json) => RemoteDocument(
    fileId: json['file_id'] as String,
    type: json['type'] as String,
    documentId: json['document_id'] as String,
    revision: json['revision'] as String,
    payload: (json['payload'] as Map).cast<String, dynamic>(),
    deviceId: json['device_id'] as String? ?? '',
    isCanonical: json['is_canonical'] != false,
  );
}

/// A write was rejected because its baseline is no longer current.
class RemoteDocumentChanged implements Exception {
  const RemoteDocumentChanged();
  @override
  String toString() =>
      'The shared document changed. Run a full sync to refresh it.';
}

/// Recovery was requested for a primary that another device has since replaced.
class PrimaryDeviceChanged implements Exception {
  final PrimaryDevice primary;
  const PrimaryDeviceChanged(this.primary);

  @override
  String toString() =>
      'The primary device changed. Review the current primary and try again.';
}

abstract interface class SyncClient {
  Future<PrimaryDevice> resolvePrimary({
    required String deviceId,
    required String deviceName,
  });

  /// Transfers the existing registry without removing documents or reservations.
  /// Rejects a different primary than the one the user reviewed.
  Future<PrimaryDevice> reclaimPrimary({
    required PrimaryDevice expectedPrimary,
    required String deviceId,
    required String deviceName,
  });
  Future<void> completeMigration(PrimaryDevice primary);
  Future<List<RemoteDocument>> listDocuments({
    required String type,
    void Function(String id, Object error)? onError,
  });
  Future<List<RemoteDocument>> listLegacyDocuments({
    required String type,
    void Function(String id, Object error)? onError,
  });
  Future<RemoteDocument?> readDocument({
    required String type,
    required String documentId,
  });

  /// Reserves a shared identity, then creates once or conditionally replaces.
  /// A null baseline never authorizes replacing an existing document.
  Future<RemoteDocument> writeDocument({
    required String type,
    required String documentId,
    required Map<String, dynamic> payload,
    RemoteDocument? baseline,
  });
  Future<void> permanentlyDeleteAllData({
    void Function(int completed, int total)? onProgress,
  });
}
