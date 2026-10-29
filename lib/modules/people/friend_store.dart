import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'people_models.dart';

abstract interface class FriendStore {
  Future<FriendRecords> load();
  Future<void> save(FriendRecords records);
  Future<void> clear();
}

class ProtectedFriendStore implements FriendStore {
  static const _key = 'journal.people.v1';
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      storageNamespace: 'journal_people',
      resetOnError: false,
    ),
    iOptions: IOSOptions(
      accountName: 'journal.people',
      accessibility: KeychainAccessibility.unlocked_this_device,
      synchronizable: false,
    ),
  );
  @override
  Future<FriendRecords> load() async {
    try {
      final raw = await _storage.read(key: _key);
      return raw == null
          ? const FriendRecords()
          : FriendRecords.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      throw const PeopleFailure(
        'Could not unlock your friends. Unlock the phone and retry.',
      );
    }
  }

  @override
  Future<void> save(FriendRecords records) async {
    try {
      await _storage.write(key: _key, value: jsonEncode(records.toJson()));
    } catch (_) {
      throw const PeopleFailure(
        'Could not securely save this friend. Please retry.',
      );
    }
  }

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
