import 'dart:convert';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/drive/v2.dart' as drive_v2;
import 'package:http/http.dart' as http;

import '../../engine/sync_client.dart';
import '../../utils/canonical_json.dart';
import '../../utils/concurrent_sync.dart';

/// JSON storage only. Content reads and guarded updates use v2 file ETags;
/// v3 handles listing, ID allocation, role registration and reset.
class DriveSyncClient implements SyncClient {
  final http.Client _http;
  final drive.DriveApi _api;
  final Map<String, String> documentIdFields;
  PrimaryDevice? _primary;
  DriveSyncClient(http.Client client, {this.documentIdFields = const {}})
    : _http = client,
      _api = drive.DriveApi(client);

  Future<List<drive.File>> _list(String? query) async {
    final result = <drive.File>[];
    final seen = <String>{};
    String? token;
    do {
      final page = await _api.files.list(
        spaces: 'appDataFolder',
        q: query == null
            ? null
            : "'appDataFolder' in parents and trashed = false and ($query)",
        pageSize: 1000,
        pageToken: token,
        $fields: 'nextPageToken,incompleteSearch,files(id,createdTime,appProperties)',
      );
      if (page.incompleteSearch == true) {
        throw StateError('Drive returned an incomplete listing.');
      }
      for (final file in page.files ?? <drive.File>[]) {
        if (file.id == null || file.id!.isEmpty) {
          throw const FormatException('Missing Drive file ID.');
        }
        result.add(file);
      }
      token = page.nextPageToken;
      if (token != null && token.isNotEmpty && !seen.add(token)) {
        throw StateError('Drive repeated a listing page.');
      }
    } while (token != null && token.isNotEmpty);
    return result;
  }

  String _escape(String value) =>
      value.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
  String _property(String key, String value) =>
      "appProperties has { key='$key' and value='${_escape(value)}' }";
  Map<String, dynamic> _response(http.Response response) {
    if (response.statusCode == 412 || response.statusCode == 409) {
      throw const RemoteDocumentChanged();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Drive request failed (${response.statusCode}).');
    }
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Expected a JSON object.');
    }
    return json;
  }

  Future<Map<String, dynamic>> _metadata(String id) async => _response(
    await _http.get(
      Uri.https('www.googleapis.com', '/drive/v2/files/$id', {
        'fields': 'id,etag',
      }),
    ),
  );
  String _etag(Map<String, dynamic> metadata) {
    final token = metadata['etag'];
    if (token is! String || token.isEmpty || token.startsWith('W/')) {
      throw StateError('Drive did not return a strong revision token.');
    }
    return token;
  }

  Future<RemoteDocument> _read(
    String fileId,
    String type,
    String id, {
    String deviceId = '',
    bool isCanonical = true,
  }) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final before = _etag(await _metadata(fileId));
      final payload = _response(
        await _http.get(
          Uri.https('www.googleapis.com', '/drive/v2/files/$fileId', {
            'alt': 'media',
          }),
        ),
      );
      if (before != _etag(await _metadata(fileId))) continue;
      final field = documentIdFields[type];
      if (field != null && payload[field] != id) {
        throw const FormatException(
          'Document ID does not match Drive metadata.',
        );
      }
      return RemoteDocument(
        fileId: fileId,
        type: type,
        documentId: id,
        revision: before,
        payload: payload,
        deviceId: deviceId,
        isCanonical: isCanonical,
      );
    }
    throw const RemoteDocumentChanged();
  }

  Future<RemoteDocument> _replace(
    RemoteDocument baseline,
    Map<String, dynamic> payload,
  ) async {
    final result = _response(
      await _http.put(
        Uri.https(
          'www.googleapis.com',
          '/upload/drive/v2/files/${baseline.fileId}',
          {'uploadType': 'media', 'fields': 'id,etag'},
        ),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'If-Match': baseline.revision,
        },
        body: canonicalJson(payload),
      ),
    );
    return RemoteDocument(
      fileId: baseline.fileId,
      type: baseline.type,
      documentId: baseline.documentId,
      revision: _etag(result),
      payload: jsonDecode(canonicalJson(payload)) as Map<String, dynamic>,
    );
  }

  @override
  Future<PrimaryDevice> resolvePrimary({
    required String deviceId,
    required String deviceName,
  }) async {
    var claims = await _list(_property('type', 'sync_primary'));
    if (claims.isEmpty) {
      final bytes = utf8.encode(
        jsonEncode({
          'deviceId': deviceId,
          'deviceName': deviceName,
          'protocolVersion': 2,
          'documents': <String, String>{},
          'migrationComplete': false,
        }),
      );
      await _api.files.create(
        drive.File(
          name: 'sync_primary.json',
          parents: ['appDataFolder'],
          appProperties: {'type': 'sync_primary'},
        ),
        uploadMedia: drive.Media(
          Stream.value(bytes),
          bytes.length,
          contentType: 'application/json',
        ),
      );
      claims = await _list(_property('type', 'sync_primary'));
    }
    if (claims.isEmpty) {
      throw StateError('Primary registration is not visible yet. Retry sync.');
    }
    if (claims.any((file) => file.createdTime == null)) {
      throw const FormatException('Primary claim has no creation time.');
    }
    claims.sort((a, b) {
      final time = a.createdTime!.compareTo(b.createdTime!);
      return time != 0 ? time : a.id!.compareTo(b.id!);
    });
    final winner = claims.first;
    final record = await _read(winner.id!, 'sync_primary', winner.id!);
    return _primary = _decodePrimary(record);
  }

  PrimaryDevice _decodePrimary(RemoteDocument record) {
    final id = record.payload['deviceId'];
    final name = record.payload['deviceName'];
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        record.payload['protocolVersion'] != 2 ||
        record.payload['documents'] is! Map) {
      throw const FormatException('Invalid primary registry.');
    }
    return PrimaryDevice(
      deviceId: id,
      deviceName: name,
      fileId: record.fileId,
      migrationComplete: record.payload['migrationComplete'] == true,
    );
  }

  @override
  Future<PrimaryDevice> reclaimPrimary({
    required PrimaryDevice expectedPrimary,
    required String deviceId,
    required String deviceName,
  }) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final registry = await _registry();
      final current = _primary = _decodePrimary(registry);
      // A retry after an interrupted acknowledgement is already successful.
      if (current.deviceId == deviceId) return current;
      if (current.fileId != expectedPrimary.fileId ||
          current.deviceId != expectedPrimary.deviceId) {
        throw PrimaryDeviceChanged(current);
      }
      try {
        final updated = await _replace(registry, {
          ...registry.payload,
          'deviceId': deviceId,
          'deviceName': deviceName,
        });
        return _primary = _decodePrimary(updated);
      } on RemoteDocumentChanged {
        // Refetch to preserve new reservations; a changed owner is rejected.
      }
    }
    throw const RemoteDocumentChanged();
  }

  Future<RemoteDocument> _registry() {
    final primary = _primary;
    if (primary == null) {
      throw StateError('Resolve the primary before using shared documents.');
    }
    return _read(primary.fileId, 'sync_primary', primary.fileId);
  }

  Future<String> _reserve(
    String type,
    String id, {
    String? preferredFileId,
  }) async {
    String? generated = preferredFileId;
    for (var attempt = 0; attempt < 5; attempt++) {
      final registry = await _registry();
      final documents = (registry.payload['documents'] as Map)
          .cast<String, dynamic>();
      final key = '$type/$id';
      final existing = documents[key];
      if (existing is String && existing.isNotEmpty) return existing;
      generated ??= (await _api.files.generateIds(
        count: 1,
        space: 'appDataFolder',
      )).ids?.single;
      if (generated == null || generated.isEmpty) {
        throw StateError('Drive did not allocate a document ID.');
      }
      try {
        await _replace(registry, {
          ...registry.payload,
          'documents': {...documents, key: generated},
        });
        return generated;
      } on RemoteDocumentChanged {
        /* Another writer reserved an ID; reread it. */
      }
    }
    throw const RemoteDocumentChanged();
  }

  @override
  Future<void> completeMigration(PrimaryDevice primary) async {
    if (_primary?.deviceId != primary.deviceId) {
      throw StateError('Primary designation changed.');
    }
    for (var attempt = 0; attempt < 5; attempt++) {
      final registry = await _registry();
      if (registry.payload['migrationComplete'] == true) return;
      try {
        await _replace(registry, {
          ...registry.payload,
          'migrationComplete': true,
        });
        return;
      } on RemoteDocumentChanged {
        /* Preserve concurrent document reservations. */
      }
    }
    throw const RemoteDocumentChanged();
  }

  @override
  Future<RemoteDocument?> readDocument({
    required String type,
    required String documentId,
  }) async {
    final registry = await _registry();
    final fileId = (registry.payload['documents'] as Map)['$type/$documentId'];
    if (fileId == null) return null;
    if (fileId is! String || fileId.isEmpty) {
      throw const FormatException('Invalid reserved file ID.');
    }
    try {
      return await _read(fileId, type, documentId);
    } on StateError catch (error) {
      if (error.message == 'Drive request failed (404).') return null;
      rethrow;
    }
  }

  Future<List<RemoteDocument>> _documents(
    String type,
    bool legacy,
    void Function(String, Object)? onError,
  ) async {
    final files = (await _list(_property('type', type)))
        .where((file) => (file.appProperties?['syncSchema'] != '2') == legacy)
        .toList();
    final indexed = <String, String>{};
    if (!legacy && _primary != null) {
      final registry = await _registry();
      final directory = (registry.payload['documents'] as Map)
          .cast<String, dynamic>();
      final groups = <String, List<drive.File>>{};
      for (final file in files) {
        final id = file.appProperties?['docId'];
        if (id != null && id.isNotEmpty) {
          groups.putIfAbsent(id, () => []).add(file);
        }
      }
      for (final entry in groups.entries) {
        final reserved = directory['$type/${entry.key}'];
        if (reserved is String && reserved.isNotEmpty) {
          indexed[entry.key] = reserved;
        } else {
          entry.value.sort((a, b) => a.id!.compareTo(b.id!));
          indexed[entry.key] = await _reserve(
            type,
            entry.key,
            preferredFileId: entry.value.first.id!,
          );
        }
      }
    }
    final results = List<RemoteDocument?>.filled(files.length, null);
    await forEachConcurrent(List.generate(files.length, (i) => i), (i) async {
      final file = files[i];
      final id = file.appProperties?['docId'];
      try {
        if (id == null || id.isEmpty) {
          throw const FormatException('Missing document metadata.');
        }
        results[i] = await _read(
          file.id!,
          type,
          id,
          deviceId: file.appProperties?['deviceId'] ?? '',
          isCanonical:
              !legacy && (indexed[id] == null || indexed[id] == file.id),
        );
      } catch (error) {
        if (onError == null) rethrow;
        onError(id ?? '*', error);
      }
    });
    return results.whereType<RemoteDocument>().toList();
  }

  @override
  Future<List<RemoteDocument>> listDocuments({
    required String type,
    void Function(String, Object)? onError,
  }) => _documents(type, false, onError);
  @override
  Future<List<RemoteDocument>> listLegacyDocuments({
    required String type,
    void Function(String, Object)? onError,
  }) => _documents(type, true, onError);

  @override
  Future<RemoteDocument> writeDocument({
    required String type,
    required String documentId,
    required Map<String, dynamic> payload,
    RemoteDocument? baseline,
  }) async {
    final field = documentIdFields[type];
    if (field != null && payload[field] != documentId) {
      throw const FormatException('Invalid upload document ID.');
    }
    if (baseline != null) {
      if (baseline.type != type || baseline.documentId != documentId) {
        throw const FormatException('Invalid upload baseline.');
      }
      return _replace(baseline, payload);
    }
    final fileId = await _reserve(type, documentId);
    final bytes = utf8.encode(canonicalJson(payload));
    try {
      final created = await drive_v2.DriveApi(_http).files.insert(
        drive_v2.File(
          id: fileId,
          title: '$type/$documentId.json',
          parents: [drive_v2.ParentReference(id: 'appDataFolder')],
          properties: [
            drive_v2.Property(key: 'type', value: type, visibility: 'PRIVATE'),
            drive_v2.Property(
              key: 'docId',
              value: documentId,
              visibility: 'PRIVATE',
            ),
            drive_v2.Property(
              key: 'syncSchema',
              value: '2',
              visibility: 'PRIVATE',
            ),
          ],
        ),
        uploadMedia: drive.Media(
          Stream.value(bytes),
          bytes.length,
          contentType: 'application/json',
        ),
        $fields: 'id,etag',
      );
      if (created.id != fileId) {
        throw StateError('Drive did not acknowledge the reserved document ID.');
      }
      return RemoteDocument(
        fileId: fileId,
        type: type,
        documentId: documentId,
        revision: _etag({'etag': created.etag}),
        payload: jsonDecode(canonicalJson(payload)) as Map<String, dynamic>,
      );
    } on drive_v2.DetailedApiRequestError catch (error) {
      if (error.status != 409) rethrow;
    }
    // A retry may encounter an already-created file. Confirm that it contains
    // this exact creation, rather than authorizing an unconditional replacement.
    final remote = await _read(fileId, type, documentId);
    if (canonicalJson(remote.payload) != canonicalJson(payload)) {
      throw const RemoteDocumentChanged();
    }
    return remote;
  }

  @override
  Future<void> permanentlyDeleteAllData({
    void Function(int, int)? onProgress,
  }) async {
    final files = await _list(null);
    var done = 0;
    onProgress?.call(0, files.length);
    for (final file in files) {
      try {
        await _api.files.delete(file.id!);
      } on drive.DetailedApiRequestError catch (error) {
        if (error.status != 404) rethrow;
      }
      onProgress?.call(++done, files.length);
    }
    if ((await _list(null)).isNotEmpty) {
      throw StateError(
        'Drive still contains app data. Close other devices and retry reset.',
      );
    }
    _primary = null;
  }
}
