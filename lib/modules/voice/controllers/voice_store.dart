import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// One protected, recoverable draft per destination. Never synced to Drive.
class VoiceStore {
  static int _epoch = 0;
  static Future<void> _tail = Future.value();
  final int _generation = _epoch;
  static Future<void> _serialize(Future<void> Function() action) {
    final next = _tail.catchError((_) {}).then((_) => action());
    _tail = next;
    return next;
  }

  static const storage = FlutterSecureStorage(
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
  Future<Directory> directory() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/voice_sessions').create(recursive: true);
  }

  Future<Map<String, dynamic>?> load(String target) async {
    final raw = await storage.read(key: 'voice.$target');
    if (raw == null) return null;
    final value = jsonDecode(raw) as Map<String, dynamic>;
    if ((value['created'] as int) + 86400000 <=
        DateTime.now().millisecondsSinceEpoch) {
      await clear(target);
      return null;
    }
    return value;
  }

  Future<void> save(String target, Map<String, dynamic> value) =>
      _serialize(() async {
        if (_generation == _epoch) {
          await storage.write(key: 'voice.$target', value: jsonEncode(value));
        }
      });
  Future<void> clear(String target) async {
    await _serialize(() async {
      if (_generation == _epoch) await storage.delete(key: 'voice.$target');
    });
  }

  Future<void> cleanup() async {
    final root = await directory(),
        cutoff = DateTime.now().subtract(const Duration(hours: 24));
    await for (final entity in root.list(followLinks: false)) {
      if (entity is File && (await entity.stat()).modified.isBefore(cutoff)) {
        await entity.delete();
      }
    }
  }

  Future<void> deleteAudio(String id) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]{8,80}$').hasMatch(id)) return;
    final file = File('${(await directory()).path}/$id.pcm');
    if (await file.exists()) await file.delete();
  }

  Future<void> consumed(String target) async {
    final data = await load(target);
    await clear(target);
    if (data != null) {
      await deleteAudio(data['id'] as String);
      for (final id in (data['previousIds'] as List? ?? []).cast<String>()) {
        await deleteAudio(id);
      }
    }
  }

  Future<void> clearAll() async {
    _epoch++;
    await _serialize(() async {
      for (final target in ['note', 'flow', 'diary', 'diary-audio']) {
        await storage.delete(key: 'voice.$target');
      }
    });
    final root = await directory();
    if (await root.exists()) await root.delete(recursive: true);
  }
}
