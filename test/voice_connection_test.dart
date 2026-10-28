import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/voice/controllers/voice_connection.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';

void main() {
  test('the actual Dart client upgrades pinned TLS and sends complete authenticated PCM', () async {
    final peer = await Process.start('node', [
      '../desktop/test/support/voice-dart-peer.cjs',
    ]);
    final lines = StreamIterator(
      peer.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    final errors = StringBuffer();
    peer.stderr.transform(utf8.decoder).listen(errors.write);
    addTearDown(() async {
      peer.stdin.writeln('quit');
      await peer.stdin.flush();
      await peer.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          peer.kill();
          return -1;
        },
      );
      await lines.cancel();
    });
    expect(
      await lines.moveNext().timeout(const Duration(seconds: 10)),
      isTrue,
      reason: errors.toString(),
    );
    final computer = TrustedComputer.fromJson(
      jsonDecode(lines.current) as Map<String, dynamic>,
    );
    final ws = await connectVoice(computer, 'dart-voice-probe');
    final ready = Completer<void>(), result = Completer<Map<String, dynamic>>();
    ws.listen((raw) {
      final event = jsonDecode(raw as String) as Map<String, dynamic>;
      if (event['type'] == 'ready') ready.complete();
      if (event['type'] == 'job') {
        result.complete(Map<String, dynamic>.from(event['job'] as Map));
      }
      if (event['type'] == 'error') {
        result.completeError(StateError(event['message'] as String));
      }
    }, onError: result.completeError);
    await ready.future.timeout(const Duration(seconds: 10));
    final pcm = Uint8List(3200), frame = Uint8List(3204);
    ByteData.sublistView(frame).setUint32(0, 0, Endian.big);
    ws.add(frame);
    ws.add(
      jsonEncode({
        'type': 'finish',
        'frames': 1,
        'bytes': pcm.length,
        'sha256': await hexHash(pcm),
      }),
    );
    final job = await result.future.timeout(const Duration(seconds: 10));
    expect(job['state'], 'completed');
    expect(job['accepted'], isTrue);
    expect(job['device'], computer.deviceId);
    expect(
      (job['segments'] as List).single['text'],
      'Synthetic transport probe',
    );
    await ws.close();
  }, skip: !File('../desktop/test/support/voice-dart-peer.cjs').existsSync());
}
