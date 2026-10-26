import 'dart:async';
import 'dart:convert';

import 'package:sync_wise/sync_wise.dart';

Map<String, dynamic> detached(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

class TestNetwork implements SyncNetwork {
  bool online = true;
  @override
  Future<bool> isOnline() async => online;
}

class MemoryAuth implements SyncAuth {
  SyncAccount? user = const SyncAccount(
    id: 'owner',
    email: 'owner@example.test',
  );
  final changes = StreamController<SyncAccount?>.broadcast();
  @override
  SyncAccount? get currentUser => user;
  @override
  bool get isSignedIn => user != null;
  @override
  Stream<SyncAccount?> get onAuthStateChanged => changes.stream;
  @override
  Future<SyncAccount?> signIn() async {
    user = const SyncAccount(id: 'owner', email: 'owner@example.test');
    changes.add(user);
    return user;
  }

  @override
  Future<SyncAccount?> trySilentSignIn() async => user;
  @override
  Future<void> signOut() async {
    user = null;
    changes.add(null);
  }
}

class MemoryBackend implements SyncBackend {
  final MemoryDrive drive;
  @override
  final MemoryAuth auth;
  int sessions = 0, closed = 0;
  MemoryBackend(this.drive, {MemoryAuth? auth}) : auth = auth ?? MemoryAuth();
  @override
  String get id => 'memory';
  @override
  String get displayName => 'Memory Cloud';
  @override
  Future<SyncSession?> openSession() async {
    if (!auth.isSignedIn) return null;
    sessions++;
    return _Session(drive, () => closed++);
  }

  @override
  void dispose() {
    auth.changes.close();
  }
}

class _Session implements SyncSession {
  @override
  final SyncClient client;
  final void Function() onClose;
  bool _closed = false;
  _Session(this.client, this.onClose);
  @override
  void close() {
    if (!_closed) {
      _closed = true;
      onClose();
    }
  }
}

class MemoryDrive implements SyncClient {
  final documents = <String, RemoteDocument>{};
  final legacy = <RemoteDocument>[];
  PrimaryDevice? primary;
  bool migrationComplete = false,
      failUploads = false,
      failDownloads = false,
      failReclaim = false,
      failDelete = false;
  int uploads = 0, reads = 0, registrations = 0, deletions = 0;
  int activeWrites = 0, maxWrites = 0;
  int reclaims = 0;
  Future<void> Function()? beforeReclaim;
  final listings = <String>[];
  final unreadable = <String>{};
  Future<void> Function(String type, String id)? beforeUpload, beforeRead;
  Future<void> Function(String type)? beforeList;
  String key(String type, String id) => '$type/$id';
  RemoteDocument seed(
    String type,
    String id,
    Map<String, dynamic> payload, {
    String deviceId = '',
  }) {
    final previous = documents[key(type, id)];
    final document = RemoteDocument(
      fileId: key(type, id),
      type: type,
      documentId: id,
      revision: '${int.parse(previous?.revision ?? '0') + 1}',
      payload: detached(payload),
      deviceId: deviceId,
    );
    documents[key(type, id)] = document;
    return document;
  }

  @override
  Future<PrimaryDevice> resolvePrimary({
    required String deviceId,
    required String deviceName,
  }) async {
    registrations++;
    primary ??= PrimaryDevice(
      deviceId: deviceId,
      deviceName: deviceName,
      fileId: 'registry',
    );
    return PrimaryDevice(
      deviceId: primary!.deviceId,
      deviceName: primary!.deviceName,
      fileId: primary!.fileId,
      migrationComplete: migrationComplete,
    );
  }

  @override
  Future<PrimaryDevice> reclaimPrimary({
    required PrimaryDevice expectedPrimary,
    required String deviceId,
    required String deviceName,
  }) async {
    reclaims++;
    await beforeReclaim?.call();
    if (failReclaim) throw StateError('Primary recovery failed');
    final current = primary!;
    if (current.deviceId != deviceId &&
        (current.deviceId != expectedPrimary.deviceId ||
            current.fileId != expectedPrimary.fileId)) {
      throw PrimaryDeviceChanged(current);
    }
    return primary = PrimaryDevice(
      deviceId: deviceId,
      deviceName: deviceName,
      fileId: current.fileId,
      migrationComplete: migrationComplete,
    );
  }

  @override
  Future<void> completeMigration(PrimaryDevice primary) async {
    migrationComplete = true;
  }

  @override
  Future<List<RemoteDocument>> listDocuments({
    required String type,
    void Function(String, Object)? onError,
  }) async {
    listings.add(type);
    await beforeList?.call(type);
    if (failDownloads) throw StateError('Download failed');
    final results = <RemoteDocument>[];
    for (final document
        in documents.values.where((d) => d.type == type).toList()) {
      if (unreadable.contains(document.documentId)) {
        if (onError == null) throw StateError('Corrupt backup');
        onError(document.documentId, StateError('Corrupt backup'));
      } else {
        results.add(RemoteDocument.fromJson(detached(document.toJson())));
      }
    }
    return results;
  }

  @override
  Future<List<RemoteDocument>> listLegacyDocuments({
    required String type,
    void Function(String, Object)? onError,
  }) async => legacy.where((d) => d.type == type).toList();
  @override
  Future<RemoteDocument?> readDocument({
    required String type,
    required String documentId,
  }) async {
    reads++;
    await beforeRead?.call(type, documentId);
    if (failDownloads) throw StateError('Download failed');
    final value = documents[key(type, documentId)];
    return value == null
        ? null
        : RemoteDocument.fromJson(detached(value.toJson()));
  }

  @override
  Future<RemoteDocument> writeDocument({
    required String type,
    required String documentId,
    required Map<String, dynamic> payload,
    RemoteDocument? baseline,
  }) async {
    uploads++;
    activeWrites++;
    if (activeWrites > maxWrites) maxWrites = activeWrites;
    try {
      await beforeUpload?.call(type, documentId);
      if (failUploads) throw StateError('Upload rejected');
      final current = documents[key(type, documentId)];
      if (current != null && baseline == null) {
        if (canonicalJson(current.payload) == canonicalJson(payload)) {
          return current;
        }
        throw const RemoteDocumentChanged();
      }
      if (baseline != null && current?.revision != baseline.revision) {
        throw const RemoteDocumentChanged();
      }
      return seed(type, documentId, payload);
    } finally {
      activeWrites--;
    }
  }

  @override
  Future<void> permanentlyDeleteAllData({
    void Function(int, int)? onProgress,
  }) async {
    deletions++;
    if (failDelete) throw StateError('Deletion interrupted');
    documents.clear();
    legacy.clear();
    primary = null;
    migrationComplete = false;
  }
}
