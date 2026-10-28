import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/voice/controllers/pcm_recorder.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const codec = StandardMethodCodec();
  var stops = 0;
  var cancels = 0;
  late Completer<void> stopReply;
  Future<void> emit(Object value) async {
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      'journal/pcm_events',
      codec.encodeSuccessEnvelope(value),
      (_) {},
    );
  }

  setUp(() {
    stops = cancels = 0;
    stopReply = Completer<void>();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      PcmRecorder.methods,
      (call) async {
        if (call.method == 'stop') {
          stops++;
          stopReply.complete();
        }
        return null;
      },
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('journal/pcm_events'),
      (call) async {
        if (call.method == 'cancel') cancels++;
        return null;
      },
    );
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      PcmRecorder.methods,
      null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('journal/pcm_events'),
      null,
    );
  });

  test(
    'stop waits for final PCM and terminal event after the method reply',
    () async {
      final recorder = PcmRecorder(), chunks = <int>[];
      await recorder.start(
        path: '/synthetic.pcm',
        onData: (data) => chunks.add(data.length),
        onStopped: () {},
        onError: (e) => fail('$e'),
      );
      await emit(Uint8List(3200));
      var finished = false;
      final stop = recorder.stop().then((_) => finished = true);
      await stopReply.future;
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      expect(cancels, 0);
      await emit(Uint8List(1600));
      await emit({'stopped': true});
      await stop;
      expect(chunks, [3200, 1600]);
      expect(cancels, 1);
      // Disposing an already stopped controller cannot affect a later recorder.
      await recorder.stop();
      expect(stops, 1);
    },
  );

  test(
    'concurrent stops share one native stop and stream cancellation',
    () async {
      final recorder = PcmRecorder();
      await recorder.start(
        path: '/synthetic.pcm',
        onData: (_) {},
        onStopped: () {},
        onError: (e) => fail('$e'),
      );
      final first = recorder.stop(), second = recorder.stop();
      await stopReply.future;
      await emit({'stopped': true});
      await Future.wait([first, second]);
      expect(stops, 1);
      expect(cancels, 1);
    },
  );
}
