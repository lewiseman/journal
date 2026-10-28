import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:journal/modules/voice/controllers/voice_store.dart';
import 'package:uuid/uuid.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android native PCM capture persists audio, streams frames, stops and rejects external paths',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Testing Android microphone capture')),
        ),
      );
      await tester.pumpAndSettle();
      expect(Platform.isAndroid, isTrue);
      const methods = MethodChannel('journal/pcm');
      // Grant RECORD_AUDIO to the test app with adb before running this test.
      expect(await methods.invokeMethod<bool>('permission'), isTrue);
      final directory = await VoiceStore().directory(), id = const Uuid().v4();
      final audio = File('${directory.path}/$id.pcm');
      var frames = 0, bytes = 0;
      final stopped = Completer<void>();
      final subscription = const EventChannel('journal/pcm_events')
          .receiveBroadcastStream()
          .listen((event) {
            if (event is Uint8List) {
              frames++;
              bytes += event.length;
            }
            if (event is Map &&
                event['stopped'] == true &&
                !stopped.isCompleted)
              stopped.complete();
          });
      try {
        await methods.invokeMethod<void>('start', {'path': audio.path});
        await tester.runAsync(() async {
          final deadline = DateTime.now().add(const Duration(seconds: 8));
          while (frames < 12 && DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        });
        await methods.invokeMethod<void>('stop');
        await stopped.future.timeout(const Duration(seconds: 3));
        expect(frames, greaterThan(5));
        expect(bytes, greaterThan(16000));
        expect(bytes % 2, 0);
        expect(await audio.length(), bytes);
        final afterStop = frames;
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(frames, afterStop);
        await expectLater(
          methods.invokeMethod<void>('start', {
            'path': '/sdcard/journal-voice-must-not-write.pcm',
          }),
          throwsA(isA<PlatformException>()),
        );
        // A test may capture emulator silence. Frame capture is not ASR quality evidence.
        // ignore: avoid_print
        print(
          'ANDROID_PCM_EVIDENCE frames=$frames bytes=$bytes format=s16le sampleRate=16000 channels=1',
        );
      } finally {
        await methods.invokeMethod<void>('stop');
        await subscription.cancel();
        if (await audio.exists()) await audio.delete();
      }
    },
  );
}
