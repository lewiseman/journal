import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:googleapis/drive/v3.dart' as drive_api;
import 'package:sync_wise/google_drive.dart';

void main() {
  test(
    'reset snapshots every app-data page and tolerates files already deleted',
    () async {
      final remaining = {'registry', 'note', 'legacy'};
      final deleted = <String>[];
      final progress = <(int, int)>[];
      final client = MockClient((request) async {
        expect(request.url.path, startsWith('/drive/v3/files'));
        if (request.method == 'GET') {
          expect(request.url.queryParameters['spaces'], 'appDataFolder');
          final last = request.url.queryParameters['pageToken'] == 'last';
          return http.Response(
            jsonEncode(
              remaining.isEmpty
                  ? {'files': []}
                  : {
                      'files': (last ? ['legacy'] : ['registry', 'note'])
                          .map((id) => {'id': id})
                          .toList(),
                      if (!last) 'nextPageToken': 'last',
                    },
            ),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        expect(request.method, 'DELETE');
        final id = request.url.pathSegments.last;
        deleted.add(id);
        remaining.remove(id);
        return id == 'legacy'
            ? http.Response(
                '{}',
                404,
                headers: {'content-type': 'application/json'},
              )
            : http.Response('', 204);
      });
      addTearDown(client.close);
      await DriveSyncClient(client)
          .permanentlyDeleteAllData(onProgress: (a, b) => progress.add((a, b)));
      expect(deleted, ['registry', 'note', 'legacy']);
      expect(progress, [(0, 3), (1, 3), (2, 3), (3, 3)]);
    },
  );

  test(
    'a failed deletion can resume and remaining app-data prevents success',
    () async {
      final remaining = {'registry', 'note'};
      var fail = true, addNewFile = false;
      final client = MockClient((request) async {
        if (request.method == 'GET') {
          if (remaining.isEmpty && addNewFile) remaining.add('concurrent');
          return http.Response(
            jsonEncode({
              'files': remaining.map((id) => {'id': id}).toList(),
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        expect(request.method, 'DELETE');
        final id = request.url.pathSegments.last;
        if (id == 'note' && fail) {
          return http.Response(
            '{}',
            500,
            headers: {'content-type': 'application/json'},
          );
        }
        remaining.remove(id);
        return http.Response('', 204);
      });
      addTearDown(client.close);
      final drive = DriveSyncClient(client);
      await expectLater(
        drive.permanentlyDeleteAllData(),
        throwsA(
          isA<drive_api.DetailedApiRequestError>().having(
            (e) => e.status,
            'status',
            500,
          ),
        ),
      );
      expect(remaining, {'note'});
      fail = false;
      addNewFile = true;
      await expectLater(drive.permanentlyDeleteAllData(), throwsStateError);
      expect(remaining, {'concurrent'});
      addNewFile = false;
      await drive.permanentlyDeleteAllData();
      expect(remaining, isEmpty);
    },
  );
}
