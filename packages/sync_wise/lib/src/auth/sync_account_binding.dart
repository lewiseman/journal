import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Pins local data to both its provider and account. Backends call [verify]
/// before opening a session, including when restoring a native account.
class SyncAccountBinding {
  final Future<Directory> Function() directory;

  SyncAccountBinding({Future<Directory> Function()? directory})
    : directory = directory ?? getApplicationDocumentsDirectory;

  Future<void> verify({
    required String backendId,
    required String accountId,
  }) async {
    final root = await directory();
    final binding = File(p.join(root.path, 'sync_account.json'));
    if (await binding.exists()) {
      final owner = jsonDecode(await binding.readAsString());
      if (owner is! Map ||
          owner['backend_id'] != backendId ||
          owner['account_id'] != accountId) {
        throw StateError(
          'This local data belongs to a different sync account or provider. Reconnect the original account to sync.',
        );
      }
      return;
    }
    // Journal's previous Google-only binding remains authoritative on upgrade.
    final legacy = File(p.join(root.path, 'sync_account.id'));
    if (await legacy.exists() &&
        (backendId != 'google_drive' ||
            (await legacy.readAsString()).trim() != accountId)) {
      throw StateError(
        'This local data belongs to a different Google account. Reconnect the original account to sync.',
      );
    }
    final temporary = File('${binding.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'backend_id': backendId, 'account_id': accountId}),
      flush: true,
    );
    await temporary.rename(binding.path);
  }

  /// Call only after the app has cleared the old account's local data.
  Future<void> clear() async {
    final root = await directory();
    for (final name in [
      'sync_account.json',
      'sync_account.json.tmp',
      'sync_account.id',
      'sync_account.id.tmp',
    ]) {
      final file = File(p.join(root.path, name));
      if (await file.exists()) await file.delete();
    }
  }
}
