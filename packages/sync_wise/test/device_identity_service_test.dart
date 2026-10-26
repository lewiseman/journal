import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sync_wise/sync_wise.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sync-device-');
  });
  tearDown(() => directory.delete(recursive: true));

  Future<DeviceIdentityService> load({Future<String> Function()? name}) =>
      DeviceIdentityService.load(
        directory: () async => directory,
        resolveDeviceName: name ?? () async => 'Test phone',
      );

  test('retains the device ID created before package extraction', () async {
    await File('${directory.path}/device_identity.id')
        .writeAsString('original-device\n');
    final device = await load();
    expect(device.deviceId, 'original-device');
    expect(device.deviceName, 'Test phone');
  });

  test('creates an ID once and restores it on another load', () async {
    final first = await load();
    final second = await load();
    expect(first.deviceId, matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(second.deviceId, first.deviceId);
    expect(
      await File('${directory.path}/device_identity.id').readAsString(),
      first.deviceId,
    );
  });

  test('repairs an empty persisted ID and keeps the repaired value', () async {
    await File('${directory.path}/device_identity.id').writeAsString(' \n');
    final first = await load();
    expect(first.deviceId, isNotEmpty);
    expect((await load()).deviceId, first.deviceId);
  });

  test(
    'device metadata failures do not prevent loading the identity',
    () async {
      final device = await load(
        name: () async => throw StateError('Platform unavailable'),
      );
      expect(device.deviceId, isNotEmpty);
      expect(device.deviceName, 'Device');
    },
  );

  test('overlapping startup calls share one initialized identity', () async {
    final release = Completer<Directory>();
    var directoryCalls = 0;
    Future<Directory> root() {
      directoryCalls++;
      return release.future;
    }

    final first = DeviceIdentityService.initialize(
      directory: root,
      resolveDeviceName: () async => 'Shared phone',
    );
    final second = DeviceIdentityService.initialize(directory: root);
    expect(directoryCalls, 1);
    release.complete(directory);
    expect(await second, same(await first));
    expect(DeviceIdentityService.instance, same(await first));
  });
}
