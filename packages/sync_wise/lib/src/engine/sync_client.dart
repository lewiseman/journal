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
    'deviceId': deviceId,
    'deviceName': deviceName,
    'fileId': fileId,
    'migrationComplete': migrationComplete,
  };
  factory PrimaryDevice.fromJson(Map<String, dynamic> json) => PrimaryDevice(
    deviceId: json['deviceId'] as String,
    deviceName: json['deviceName'] as String,
    fileId: json['fileId'] as String,
    migrationComplete: json['migrationComplete'] == true,
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
    'fileId': fileId,
    'type': type,
    'documentId': documentId,
    'revision': revision,
    'payload': payload,
    'deviceId': deviceId,
    'isCanonical': isCanonical,
  };
  factory RemoteDocument.fromJson(Map<String, dynamic> json) => RemoteDocument(
    fileId: json['fileId'] as String,
    type: json['type'] as String,
    documentId: json['documentId'] as String,
    revision: json['revision'] as String,
    payload: (json['payload'] as Map).cast<String, dynamic>(),
    deviceId: json['deviceId'] as String? ?? '',
    isCanonical: json['isCanonical'] != false,
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
