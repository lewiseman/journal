// Explicit opt-in physical-device diagnostic. Uses the phone's existing trust,
// captures only temporary audio, and never opens or writes the journal database.
// ALWAYS pass --no-uninstall: Flutter otherwise deletes the normal app's data.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:journal/modules/settings/companion/companion_store.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';
import 'package:journal/modules/voice/controllers/voice_capture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('RUN_REAL_VOICE_REPEAT');
  testWidgets(
    'three native phone recordings finish over the existing trusted LAN connection',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text(
                'Checking repeated voice capture · no journal entries are saved',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final store = ProtectedComputerStore();
        var records = await store.load();
        final transport = PinnedCompanionTransport();
        final statusClient = CompanionClient(transport);
        const raw = String.fromEnvironment('COMPANION_PAIRING_CODE');
        if (records.computers.isEmpty && raw.isNotEmpty) {
          final code = PairingCode.parse(raw);
          final pairing = await statusClient.beginPair(
            code,
            code.endpoints.first,
            'My Journal phone',
          );
          debugPrint('REAL_VOICE_PAIR_VERIFICATION ${pairing.verification}');
          final deadline = DateTime.now().add(const Duration(seconds: 110));
          var approved = false;
          while (DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(seconds: 1));
            final result = await transport.request(
              pairing.computer.endpoint,
              code.pin,
              'POST',
              '/v1/pair-status',
              body: {'ticket': pairing.ticket},
            );
            if (result['state'] == 'approved') {
              approved = true;
              break;
            }
            if (result['state'] == 'denied') fail('Pairing denied');
          }
          expect(
            approved,
            isTrue,
            reason: 'Approve the matching phone verification on the desktop.',
          );
          await statusClient.status(pairing.computer);
          records = ComputerRecords([pairing.computer], pairing.computer.id);
          await store.save(records);
        }
        final computer = records.computers
            .where((c) => c.id == records.selected)
            .firstOrNull;
        expect(
          computer,
          isNotNull,
          reason: 'Pair the regular app first. This diagnostic never creates trust.',
        );
        Future<void> requireReady() async {
          final status = await statusClient.status(computer!);
          final capabilities = (status['capabilities'] as List).cast<Map>();
          expect(
            capabilities.firstWhere(
              (c) => c['id'] == 'transcription',
            )['status'],
            'ready',
          );
          expect(
            capabilities.firstWhere((c) => c['id'] == 'text')['status'],
            'ready',
          );
        }

        try {
          await requireReady();
          for (var index = 0; index < 3; index++) {
            final capture = VoiceCapture(
              target: 'voice-repeat-diagnostic',
              computer: () => computer!,
            );
            try {
              await capture.start();
              expect(
                capture.phase,
                CapturePhase.recording,
                reason: capture.message,
              );
              final deadline = DateTime.now().add(const Duration(seconds: 8));
              while (capture.bytes < 32000 &&
                  DateTime.now().isBefore(deadline) &&
                  capture.recording) {
                await Future<void>.delayed(const Duration(milliseconds: 100));
              }
              expect(
                capture.bytes,
                greaterThanOrEqualTo(32000),
                reason: capture.message,
              );
              await capture.stop();
              debugPrint(
                'REAL_VOICE_REPEAT session=${index + 1} deliveredBytes=${capture.bytes} fileBytes=${await capture.audio!.length()} stopPhase=${capture.phase.name}',
              );
              final finished = DateTime.now().add(const Duration(seconds: 30));
              while (![
                    CapturePhase.review,
                    CapturePhase.error,
                  ].contains(capture.phase) &&
                  DateTime.now().isBefore(finished)) {
                await Future<void>.delayed(const Duration(milliseconds: 100));
              }
              expect(
                capture.phase,
                CapturePhase.review,
                reason: capture.message,
              );
              expect(capture.accepted, isTrue);
              // No transcript or trust credentials are included in test output.
              debugPrint(
                'REAL_VOICE_REPEAT session=${index + 1} capturedBytes=${capture.bytes} accepted=true review=true',
              );
            } finally {
              await capture.discard();
              capture.dispose();
            }
            if (index == 1) {
              await Future<void>.delayed(const Duration(seconds: 5));
            }
          }
          await Future<void>.delayed(const Duration(seconds: 12));
          await requireReady();
          debugPrint('REAL_VOICE_REPEAT sessions=3 modelsReadyAfterIdle=true');
        } finally {
          transport.close();
        }
      });
    },
    skip: !enabled,
  );
}
