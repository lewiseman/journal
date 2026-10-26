import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../auth/sync_account_binding.dart';

class ResetIntent {
  final String accountId;
  final String backendId;
  final bool remoteDeleted;
  const ResetIntent(
    this.accountId, {
    this.backendId = 'google_drive',
    this.remoteDeleted = false,
  });
}

/// The intent survives process death and blocks ordinary sync until reset ends.
class AccountResetStorage {
  final Future<Directory> Function() directory;
  AccountResetStorage({Future<Directory> Function()? directory})
    : directory = directory ?? getApplicationDocumentsDirectory;

  Future<File> get _marker async =>
      File(p.join((await directory()).path, 'account_reset.json'));
  Future<bool> canSync() async => !await (await _marker).exists();

  Future<ResetIntent?> read() async {
    final file = await _marker;
    if (!await file.exists()) return null;
    final value = jsonDecode(await file.readAsString());
    if (value is! Map ||
        value['accountId'] is! String ||
        (value['accountId'] as String).isEmpty ||
        (value['backendId'] != null && value['backendId'] is! String) ||
        value['remoteDeleted'] is! bool) {
      throw const FormatException(
        'The saved reset request cannot be read. Sync remains paused.',
      );
    }
    return ResetIntent(
      value['accountId'] as String,
      backendId: value['backendId'] as String? ?? 'google_drive',
      remoteDeleted: value['remoteDeleted'] as bool,
    );
  }

  Future<void> write(ResetIntent intent) async {
    final file = await _marker;
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'accountId': intent.accountId,
        'backendId': intent.backendId,
        'remoteDeleted': intent.remoteDeleted,
      }),
      flush: true,
    );
    await temporary.rename(file.path);
  }

  Future<void> finish() async {
    await SyncAccountBinding(directory: directory).clear();
    final root = await directory();
    for (final name in ['account_reset.json.tmp']) {
      final file = File(p.join(root.path, name));
      if (await file.exists()) await file.delete();
    }
    final marker = await _marker;
    if (await marker.exists()) await marker.delete();
  }
}
