import 'dart:convert';

import '../engine/sync_client.dart';

enum SyncDeviceRole { unknown, primary, secondary }

/// Synchronous storage lets the host commit records and sync metadata together.
abstract interface class SyncKeyValueStore {
  String? read(String key);
  void write(String key, String value);
  void remove(String key);
  List<String> keys(String prefix);
  void clear();
}

class MemorySyncKeyValueStore implements SyncKeyValueStore {
  final _values = <String, String>{};
  @override
  String? read(String key) => _values[key];
  @override
  void write(String key, String value) => _values[key] = value;
  @override
  void remove(String key) => _values.remove(key);
  @override
  List<String> keys(String prefix) =>
      _values.keys.where((k) => k.startsWith(prefix)).toList();
  @override
  void clear() => _values.clear();
}

class PendingCreation {
  final String id;
  final String type;
  final String documentId;
  final Map<String, dynamic> payload;
  const PendingCreation({
    required this.id,
    required this.type,
    required this.documentId,
    required this.payload,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'documentId': documentId,
    'payload': payload,
  };
  factory PendingCreation.fromJson(Map<String, dynamic> json) =>
      PendingCreation(
        id: json['id'] as String,
        type: json['type'] as String,
        documentId: json['documentId'] as String,
        payload: (json['payload'] as Map).cast<String, dynamic>(),
      );
}

class SyncStateStore {
  final SyncKeyValueStore storage;
  final String deviceId;
  final DateTime Function() now;
  SyncStateStore({
    required this.storage,
    required this.deviceId,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  Map<String, dynamic>? _read(String key) {
    final value = storage.read(key);
    return value == null
        ? null
        : (jsonDecode(value) as Map).cast<String, dynamic>();
  }

  void _write(String key, Object value) =>
      storage.write(key, jsonEncode(value));
  PrimaryDevice? get primary {
    final value = _read('role');
    return value == null ? null : PrimaryDevice.fromJson(value);
  }

  SyncDeviceRole get role => primary == null
      ? SyncDeviceRole.unknown
      : primary!.deviceId == deviceId
      ? SyncDeviceRole.primary
      : SyncDeviceRole.secondary;
  bool get canEdit => role != SyncDeviceRole.secondary;
  void bind(String backend, String account) {
    final owner = '$backend/$account';
    final previous = storage.read('owner');
    if (previous != null && previous != owner) {
      throw StateError(
        'Local sync metadata belongs to another account. Reset it first.',
      );
    }
    storage.write('owner', owner);
  }

  void setPrimary(PrimaryDevice value) => _write('role', value.toJson());
  void edited(String type, String id, [String field = 'record']) => _write(
    'edit/$type/$id/$field',
    {'at': now().toUtc().toIso8601String(), 'dirty': true},
  );
  bool dirty(String type, String id, [String? field]) => field == null
      ? storage.keys('edit/$type/$id/').any((k) => _read(k)?['dirty'] == true)
      : _read('edit/$type/$id/$field')?['dirty'] == true;
  bool protected(String type, String id, String field, DateTime at) {
    final value = _read('edit/$type/$id/$field');
    return value != null &&
        at.toUtc().difference(DateTime.parse(value['at'] as String)) <
            const Duration(minutes: 2);
  }

  void cleanField(String type, String id, String field) {
    final key = 'edit/$type/$id/$field';
    final value = _read(key);
    if (value != null) {
      value['dirty'] = false;
      _write(key, value);
    }
  }

  void clean(String type, String id) {
    for (final key in storage.keys('edit/$type/$id/')) {
      final value = _read(key)!;
      value['dirty'] = false;
      _write(key, value);
    }
  }

  void enqueue(PendingCreation value) {
    final key = 'operation/${value.type}/${value.id}';
    if (storage.read(key) == null) _write(key, value.toJson());
  }

  List<PendingCreation> get pendingCreations => storage
      .keys('operation/')
      .map((k) => PendingCreation.fromJson(_read(k)!))
      .toList();
  void acknowledgeCreation(PendingCreation value) =>
      storage.remove('operation/${value.type}/${value.id}');
  RemoteDocument? baseline(String type, String id) {
    final value = _read('baseline/$type/$id');
    return value == null ? null : RemoteDocument.fromJson(value);
  }

  void saveBaseline(RemoteDocument value) =>
      _write('baseline/${value.type}/${value.documentId}', value.toJson());
  bool get hasBlockedDocuments => storage.keys('blocked/').isNotEmpty;
  void forgetBaseline(String type, String id) =>
      storage.remove('baseline/$type/$id');
  bool blocked(String type, String id) =>
      storage.read('blocked/$type/$id') != null;
  void block(String type, String id) => storage.write('blocked/$type/$id', '1');
  void unblock(String type, String id) => storage.remove('blocked/$type/$id');
  void clear() => storage.clear();
}
