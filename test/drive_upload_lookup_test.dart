import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sync_wise/google_drive.dart';
import 'package:sync_wise/sync_wise.dart';

import 'drive_sync_client_test.dart' show jsonResponse, registry;

void main() {
  test('concurrent document reservation reuses the winning ID instead of creating another file', () async {
    var data = registry();
    var revision = 1;
    var guarded = 0;
    var downloads = 0;
    String? created;
    final note = {'date_string': '2026-10-26', 'items': []};
    final client = MockClient((request) async {
      if (request.url.path == '/drive/v3/files') {
        return jsonResponse({
          'files': [
            {'id': 'registry', 'createdTime': '2026-10-26T00:00:00Z'},
          ],
        });
      }
      if (request.url.path.endsWith('/generateIds')) {
        return jsonResponse({
          'ids': ['unused-reservation'],
        });
      }
      if (request.method == 'PUT') {
        guarded++;
        expect(request.headers['if-match'], '"1"');
        data = registry(documents: {'diary/2026-10-26': 'winner'});
        revision = 2;
        return jsonResponse({}, status: 412);
      }
      if (request.method == 'POST') {
        expect(request.body, contains('winner'));
        expect(
          request.body,
          contains(base64Encode(utf8.encode(canonicalJson(note)))),
        );
        created = 'winner';
        return jsonResponse({'id': 'winner', 'etag': '"created"'});
      }
      if (request.url.path.endsWith('/registry')) {
        return request.url.queryParameters['alt'] == 'media'
            ? jsonResponse(data)
            : jsonResponse({'etag': '"$revision"'});
      }
      downloads++;
      expect(request.url.pathSegments.last, 'winner');
      return request.url.queryParameters['alt'] == 'media'
          ? jsonResponse(note)
          : jsonResponse({'etag': '"created"'});
    });
    addTearDown(client.close);
    final drive = DriveSyncClient(client);
    await drive.resolvePrimary(deviceId: 'primary', deviceName: 'Phone');
    final result = await drive.writeDocument(
      type: 'diary',
      documentId: '2026-10-26',
      payload: note,
    );
    expect(result.fileId, 'winner');
    expect(created, 'winner');
    expect(guarded, 1);
    expect(downloads, 0);
  });
}
