import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/local_ai/core/ai_router.dart';
import 'package:journal/modules/local_ai/core/ai_settings.dart';
import 'package:journal/modules/local_ai/core/on_device_engine.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';

import 'fake_engine.dart';

class RejectRemote implements CompanionTransport {
  @override
  Future<Map<String, dynamic>> request(
    Uri endpoint,
    String pin,
    String method,
    String route, {
    Map<String, dynamic>? body,
    Map<String, String> headers = const {},
  }) async => throw StateError('No remote request is permitted');
  @override
  void close() {}
}

void main() {
  for (final mode in AiMode.values) {
    for (final connected in [false, true]) {
      for (final ready in [false, true]) {
        test('${mode.name}, companion=$connected, device=$ready', () {
          final expected = mode == AiMode.device
              ? (ready ? AiProviderKind.device : null)
              : mode == AiMode.companion
              ? (connected ? AiProviderKind.companion : null)
              : connected
              ? AiProviderKind.companion
              : ready
              ? AiProviderKind.device
              : null;
          AiProviderKind run() => chooseAiProvider(
            mode: mode,
            companionConnected: connected,
            deviceReady: ready,
          );
          if (expected == null) {
            expect(run, throwsA(isA<CompanionFailure>()));
          } else {
            expect(run(), expected);
          }
        });
      }
    }
  }
  test('an explicit task override wins and never falls back', () {
    expect(
      chooseAiProvider(
        mode: AiMode.companion,
        override: AiMode.device,
        companionConnected: true,
        deviceReady: true,
      ),
      AiProviderKind.device,
    );
    expect(
      () => chooseAiProvider(
        mode: AiMode.auto,
        override: AiMode.device,
        companionConnected: true,
        deviceReady: false,
      ),
      throwsA(isA<CompanionFailure>()),
    );
  });
  test(
    'engine removal resolves retained local jobs without contacting a computer',
    () async {
      final client = AiJobClient(
        companion: CompanionClient(RejectRemote()),
        device: () => null,
        router: () => throw StateError('Routing must remain pinned'),
      );
      const provider = AiJobProvider.device('summarize-note', accepted: true);
      expect(
        (await client.authenticated(
          provider,
          'GET',
          '/v1/jobs/retained-123',
        ))['state'],
        'interrupted',
      );
      expect(
        (await client.authenticated(
          provider,
          'POST',
          '/v1/jobs/retained-123/cancel',
        ))['state'],
        'cancelled',
      );
      expect(
        () => client.authenticated(provider, 'POST', '/v1/jobs', body: {}),
        throwsA(isA<CompanionFailure>()),
      );
    },
  );
  test('empty registry has no device path, even with an assignment', () {
    final router = AiRouter(
      settings: const AiSettings(
        mode: AiMode.device,
        assignments: {AiTask.writing: 'model'},
      ),
      engine: null,
      companionConnected: true,
      models: const [],
    );
    expect(
      () => router.select('summarize-note'),
      throwsA(isA<CompanionFailure>()),
    );
  });
  test('vision and OCR never run on an engine advertising only primitives', () {
    final router = AiRouter(
      settings: const AiSettings(mode: AiMode.device),
      engine: FakeOnDeviceEngine(),
      companionConnected: true,
      models: const [],
    );
    expect(operationTask('scan-note-image'), isNull);
    expect(
      () => router.select('scan-note-image'),
      throwsA(isA<CompanionFailure>()),
    );
  });
}
