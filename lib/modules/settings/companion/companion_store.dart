import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'companion_protocol.dart';

class ComputerRecords {
  const ComputerRecords(this.computers, this.selected);
  final List<TrustedComputer> computers;
  final String? selected;
}

abstract interface class ComputerStore {
  Future<ComputerRecords> load();
  Future<void> save(ComputerRecords records);
}

// Neither ObjectBox, CacheStorage nor Drive/sync_wise receives trust records.
class ProtectedComputerStore implements ComputerStore {
  ProtectedComputerStore({this.key = 'journal.companion.trust.v1'});
  final String key;
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      storageNamespace: 'journal_companion',
      resetOnError: false,
    ),
    iOptions: IOSOptions(
      accountName: 'journal.companion',
      accessibility: KeychainAccessibility.unlocked_this_device,
      synchronizable: false,
    ),
  );
  @override
  Future<ComputerRecords> load() async {
    try {
      final raw = await _storage.read(key: key);
      if (raw == null) return const ComputerRecords([], null);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['v'] != 1) throw const FormatException();
      final records = (json['computers'] as List)
          .map(
            (c) =>
                TrustedComputer.fromJson(Map<String, dynamic>.from(c as Map)),
          )
          .toList();
      if (records.length > 20) throw const FormatException();
      return ComputerRecords(records, json['selected'] as String?);
    } catch (_) {
      throw const CompanionFailure(
        'SECURE_STORAGE',
        'Could not unlock saved computer trust. Unlock the phone and retry. Reinstalling or resetting protected storage requires pairing again.',
      );
    }
  }

  @override
  Future<void> save(ComputerRecords records) async {
    try {
      await _storage.write(
        key: key,
        value: jsonEncode({
          'v': 1,
          'computers': records.computers.map((c) => c.toJson()).toList(),
          'selected': records.selected,
        }),
      );
    } catch (_) {
      throw const CompanionFailure(
        'SECURE_STORAGE',
        'Could not save trust securely. Unlock the phone and retry; pairing was not remembered.',
      );
    }
  }
}
