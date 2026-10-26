import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sync_wise/google_drive.dart';

import 'drive_sync_client_test.dart' show jsonResponse, file;

void main() {
  test('JSON downloads are bounded to four workers', () async {
    var active = 0, max = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/drive/v3/files') {
        return jsonResponse({
          'files': List.generate(12, (i) => file('n$i', 'n$i')),
        });
      }
      if (request.url.queryParameters['alt'] == 'media') {
        active++;
        if (active > max) max = active;
        await Future<void>.delayed(const Duration(milliseconds: 1));
        active--;
        return jsonResponse({'uuid': request.url.pathSegments.last});
      }
      return jsonResponse({'etag': '"1"'});
    });
    addTearDown(client.close);
    final result = await DriveSyncClient(client).listDocuments(type: 'note');
    expect(result, hasLength(12));
    expect(max, inInclusiveRange(2, 4));
  });
}
