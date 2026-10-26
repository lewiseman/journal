import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sync_wise/google_drive.dart';
import 'package:sync_wise/sync_wise.dart';

class _RegistryServer {
  Map<String, dynamic> payload = {
    'device_id': 'old',
    'device_name': 'Old phone',
    'protocol_version': 2,
    'migration_complete': true,
    'documents': {'note/one': 'note-file', 'diary/2026-10-26': 'diary-file'},
    'extra': 'preserve unknown fields',
  };
  int revision = 1, writes = 0;
  void Function()? race;
  late final http.Client httpClient = MockClient((request) async {
    http.Response json(Object value, [int code = 200]) => http.Response(
      jsonEncode(value),
      code,
      headers: {'content-type': 'application/json'},
    );
    if (request.method == 'GET' && request.url.path == '/drive/v3/files') {
      return json({
        'files': [
          {'id': 'registry', 'createdTime': '2026-10-26T00:00:00Z'},
        ],
      });
    }
    if (request.method == 'GET' &&
        request.url.path == '/drive/v2/files/registry') {
      return request.url.queryParameters['alt'] == 'media'
          ? json(payload)
          : json({'id': 'registry', 'etag': '"$revision"'});
    }
    if (request.method == 'PUT' &&
        request.url.path == '/upload/drive/v2/files/registry') {
      writes++;
      expect(request.headers['if-match'], '"$revision"');
      if (writes == 1 && race != null) {
        race!();
        revision++;
        return json({}, 412);
      }
      payload = (jsonDecode(request.body) as Map).cast<String, dynamic>();
      revision++;
      return json({'id': 'registry', 'etag': '"$revision"'});
    }
    throw StateError('Unexpected ${request.method} ${request.url}');
  });
}

void main() {
  test('guarded recovery preserves the registry, migration marker and document IDs', () async {
    final server = _RegistryServer();
    addTearDown(server.httpClient.close);
    final client = DriveSyncClient(server.httpClient);
    final old = await client.resolvePrimary(
      deviceId: 'new',
      deviceName: 'New phone',
    );
    final documents = Map.of(server.payload['documents'] as Map);
    final result = await client.reclaimPrimary(
      expectedPrimary: old,
      deviceId: 'new',
      deviceName: 'New phone',
    );
    expect(result.deviceId, 'new');
    expect(result.fileId, 'registry');
    expect(result.migrationComplete, isTrue);
    expect(server.payload['documents'], documents);
    expect(server.payload['extra'], 'preserve unknown fields');
    expect(server.payload['device_name'], 'New phone');
    expect(server.writes, 1);
    await client.reclaimPrimary(
      expectedPrimary: old,
      deviceId: 'new',
      deviceName: 'New phone',
    );
    expect(server.writes, 1);
    final reopened = DriveSyncClient(server.httpClient);
    expect(
      (await reopened.resolvePrimary(
        deviceId: 'new',
        deviceName: 'New phone',
      )).deviceId,
      'new',
    );
  });

  test(
    'a concurrent document reservation is retained when recovery retries',
    () async {
      final server = _RegistryServer();
      addTearDown(server.httpClient.close);
      final client = DriveSyncClient(server.httpClient);
      final old = await client.resolvePrimary(
        deviceId: 'new',
        deviceName: 'New phone',
      );
      server.race = () =>
          (server.payload['documents'] as Map)['note/two'] = 'new-file';
      await client.reclaimPrimary(
        expectedPrimary: old,
        deviceId: 'new',
        deviceName: 'New phone',
      );
      expect((server.payload['documents'] as Map)['note/two'], 'new-file');
      expect(server.payload['device_id'], 'new');
      expect(server.writes, 2);
    },
  );

  test(
    'another recovery winning the ETag race is not silently replaced',
    () async {
      final server = _RegistryServer();
      addTearDown(server.httpClient.close);
      final client = DriveSyncClient(server.httpClient);
      final old = await client.resolvePrimary(
        deviceId: 'new',
        deviceName: 'New phone',
      );
      server.race = () => server.payload['device_id'] = 'other';
      await expectLater(
        client.reclaimPrimary(
          expectedPrimary: old,
          deviceId: 'new',
          deviceName: 'New phone',
        ),
        throwsA(isA<PrimaryDeviceChanged>()),
      );
      expect(server.payload['device_id'], 'other');
      expect(server.writes, 1);
    },
  );
}
