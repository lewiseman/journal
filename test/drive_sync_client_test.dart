import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sync_wise/google_drive.dart';
import 'package:sync_wise/sync_wise.dart';

http.Response jsonResponse(Object value, {int status = 200}) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);
Map<String, dynamic> registry({Map<String, String> documents = const {}}) => {
  'deviceId': 'primary',
  'deviceName': 'Phone',
  'protocolVersion': 2,
  'migrationComplete': false,
  'documents': documents,
};
Map<String, dynamic> file(
  String id,
  String documentId, {
  bool legacy = false,
  String type = 'note',
}) => {
  'id': id,
  'createdTime': '2026-10-26T00:00:00Z',
  'appProperties': {
    'type': type,
    'docId': documentId,
    if (!legacy) 'syncSchema': '2',
    if (legacy) 'deviceId': 'old',
  },
};

void main() {
  test(
    'shared listing follows empty pages and excludes legacy files',
    () async {
      final client = MockClient((request) async {
        if (request.url.path == '/drive/v3/files') {
          switch (request.url.queryParameters['pageToken']) {
            case null:
              return jsonResponse({
                'files': [file('one', 'one'), file('old', 'old', legacy: true)],
                'nextPageToken': 'empty',
              });
            case 'empty':
              return jsonResponse({'files': [], 'nextPageToken': 'last'});
            default:
              return jsonResponse({
                'files': [file('two', 'two')],
              });
          }
        }
        final id = request.url.pathSegments.last;
        return request.url.queryParameters['alt'] == 'media'
            ? jsonResponse({'uuid': id})
            : jsonResponse({'id': id, 'etag': '"1"'});
      });
      addTearDown(client.close);
      final result = await DriveSyncClient(
        client,
        documentIdFields: {'note': 'uuid'},
      ).listDocuments(type: 'note');
      expect(result.map((d) => d.documentId), ['one', 'two']);
      expect(result.every((d) => d.revision == '"1"'), isTrue);
    },
  );
  test('individual bad documents do not hide healthy downloads', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/drive/v3/files') {
        return jsonResponse({
          'files': [file('good', 'good'), file('bad', 'bad')],
        });
      }
      if (request.url.queryParameters['alt'] == 'media') {
        return request.url.path.endsWith('/bad')
            ? http.Response('broken', 200)
            : jsonResponse({'uuid': 'good'});
      }
      return jsonResponse({'etag': '"1"'});
    });
    addTearDown(client.close);
    final errors = <String>[];
    final result = await DriveSyncClient(
      client,
      documentIdFields: {'note': 'uuid'},
    ).listDocuments(type: 'note', onError: (id, error) => errors.add(id));
    expect(result.single.documentId, 'good');
    expect(errors, ['bad']);
  });
  test('metadata and payload IDs are checked', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/drive/v3/files') {
        return jsonResponse({
          'files': [file('one', 'one')],
        });
      }
      return request.url.queryParameters['alt'] == 'media'
          ? jsonResponse({'uuid': 'wrong'})
          : jsonResponse({'etag': '"1"'});
    });
    addTearDown(client.close);
    await expectLater(
      DriveSyncClient(
        client,
        documentIdFields: {'note': 'uuid'},
      ).listDocuments(type: 'note'),
      throwsFormatException,
    );
  });
  for (final page in [
    {'files': [], 'incompleteSearch': true},
    {'files': [], 'nextPageToken': 'again'},
  ]) {
    test(
      'incomplete/repeating listing fails instead of implying missing data: $page',
      () async {
        final client = MockClient((_) async => jsonResponse(page));
        addTearDown(client.close);
        await expectLater(
          DriveSyncClient(client).listDocuments(type: 'note'),
          throwsStateError,
        );
      },
    );
  }
  test('conditional JSON update carries the exact baseline ETag and returns its acknowledgement token', () async {
    final client = MockClient((request) async {
      expect(request.method, 'PUT');
      expect(request.url.path, '/upload/drive/v2/files/file');
      expect(request.headers['if-match'], '"old"');
      expect(jsonDecode(request.body), {'uuid': 'one', 'content': 'new'});
      return jsonResponse({'id': 'file', 'etag': '"new"'});
    });
    addTearDown(client.close);
    final result = await DriveSyncClient(client).writeDocument(
      type: 'note',
      documentId: 'one',
      payload: {'uuid': 'one', 'content': 'new'},
      baseline: const RemoteDocument(
        fileId: 'file',
        type: 'note',
        documentId: 'one',
        revision: '"old"',
        payload: {'uuid': 'one'},
      ),
    );
    expect(result.revision, '"new"');
    expect(result.payload['content'], 'new');
  });
  test('stale upload is rejected with no unguarded retry', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return jsonResponse({}, status: 412);
    });
    addTearDown(client.close);
    await expectLater(
      DriveSyncClient(client).writeDocument(
        type: 'diary',
        documentId: '2026-10-26',
        payload: {},
        baseline: const RemoteDocument(
          fileId: 'file',
          type: 'diary',
          documentId: '2026-10-26',
          revision: '"old"',
          payload: {},
        ),
      ),
      throwsA(isA<RemoteDocumentChanged>()),
    );
    expect(calls, 1);
  });
  test(
    'missing strong acknowledgement token is never reported as upload success',
    () async {
      final client = MockClient((_) async => jsonResponse({'id': 'file'}));
      addTearDown(client.close);
      await expectLater(
        DriveSyncClient(client).writeDocument(
          type: 'note',
          documentId: 'one',
          payload: {},
          baseline: const RemoteDocument(
            fileId: 'file',
            type: 'note',
            documentId: 'one',
            revision: '"old"',
            payload: {},
          ),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'earliest server-created primary claim wins; file ID breaks timestamp ties',
    () async {
      final client = MockClient((request) async {
        if (request.url.path == '/drive/v3/files') {
          return jsonResponse({
            'files': [
              {'id': 'later', 'createdTime': '2026-10-26T00:01:00Z'},
              {'id': 'b', 'createdTime': '2026-10-26T00:00:00Z'},
              {'id': 'a', 'createdTime': '2026-10-26T00:00:00Z'},
            ],
          });
        }
        expect(request.url.pathSegments.last, 'a');
        return request.url.queryParameters['alt'] == 'media'
            ? jsonResponse(registry())
            : jsonResponse({'etag': '"1"'});
      });
      addTearDown(client.close);
      final result = await DriveSyncClient(client)
          .resolvePrimary(deviceId: 'secondary', deviceName: 'Web');
      expect(result.deviceId, 'primary');
      expect(result.fileId, 'a');
    },
  );
  test(
    'first registration re-lists claims before resolving its role',
    () async {
      var listed = 0, created = 0;
      final client = MockClient((request) async {
        if (request.method == 'POST') {
          created++;
          expect(request.body, contains('sync_primary.json'));
          return jsonResponse({'id': 'registry'});
        }
        if (request.url.path == '/drive/v3/files') {
          return jsonResponse({
            'files': ++listed == 1
                ? []
                : [
                    {'id': 'registry', 'createdTime': '2026-10-26T00:00:00Z'},
                  ],
          });
        }
        return request.url.queryParameters['alt'] == 'media'
            ? jsonResponse(registry())
            : jsonResponse({'etag': '"1"'});
      });
      addTearDown(client.close);
      final result = await DriveSyncClient(client)
          .resolvePrimary(deviceId: 'primary', deviceName: 'Phone');
      expect(result.deviceId, 'primary');
      expect(created, 1);
      expect(listed, 2);
    },
  );
  test(
    'read retries when metadata changes while content is downloading',
    () async {
      var noteMetadata = 0, downloads = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/drive/v3/files') {
          return jsonResponse({
            'files': [
              {'id': 'registry', 'createdTime': '2026-10-26T00:00:00Z'},
            ],
          });
        }
        if (request.url.path.endsWith('/registry')) {
          return request.url.queryParameters['alt'] == 'media'
              ? jsonResponse(registry(documents: {'note/one': 'one'}))
              : jsonResponse({'etag': '"registry"'});
        }
        if (request.url.queryParameters['alt'] == 'media') {
          downloads++;
          return jsonResponse({
            'uuid': 'one',
            'content': downloads == 1 ? 'old' : 'new',
          });
        }
        noteMetadata++;
        return jsonResponse({'etag': noteMetadata == 1 ? '"1"' : '"2"'});
      });
      addTearDown(client.close);
      final drive = DriveSyncClient(client);
      await drive.resolvePrimary(deviceId: 'primary', deviceName: 'Phone');
      final result = await drive.readDocument(type: 'note', documentId: 'one');
      expect(result!.payload['content'], 'new');
      expect(downloads, 2);
      expect(result.revision, '"2"');
    },
  );
}
