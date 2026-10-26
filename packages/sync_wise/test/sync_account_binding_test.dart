import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sync_wise/sync_wise.dart';

void main() {
  late Directory directory;
  late SyncAccountBinding binding;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sync-binding-');
    binding = SyncAccountBinding(directory: () async => directory);
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'migrates the existing Google owner without accepting a different account',
    () async {
      await File('${directory.path}/sync_account.id').writeAsString('original');
      await expectLater(
        binding.verify(backendId: 'google_drive', accountId: 'other'),
        throwsStateError,
      );
      await expectLater(
        binding.verify(backendId: 'native', accountId: 'original'),
        throwsStateError,
      );
      await binding.verify(backendId: 'google_drive', accountId: 'original');
      expect(
        jsonDecode(
          await File('${directory.path}/sync_account.json').readAsString(),
        ),
        {'backendId': 'google_drive', 'accountId': 'original'},
      );
    },
  );

  test(
    'pins both provider and account until local data is explicitly cleared',
    () async {
      await binding.verify(backendId: 'native', accountId: 'owner');
      await binding.verify(backendId: 'native', accountId: 'owner');
      await expectLater(
        binding.verify(backendId: 'other', accountId: 'owner'),
        throwsStateError,
      );
      await expectLater(
        binding.verify(backendId: 'native', accountId: 'other'),
        throwsStateError,
      );
      await binding.clear();
      await binding.verify(backendId: 'other', accountId: 'new-owner');
    },
  );
}
