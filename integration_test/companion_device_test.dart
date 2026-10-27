// Explicit real-device, synthetic-only demonstration. See desktop/docs/CONNECTION.md.
// The short-lived QR is injected into this TEST binary, never into production.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/modules/settings/companion/companion_page.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const raw = String.fromEnvironment('COMPANION_PAIRING_CODE');
  const restart = bool.fromEnvironment('COMPANION_RESTART');
  const direct = bool.fromEnvironment('COMPANION_DIRECT_PAIR');
  const expectedPort = int.fromEnvironment('COMPANION_EXPECT_PORT');
  testWidgets(
    restart
        ? 'cold restart reconnects with protected device trust'
        : 'physical device pairs to packaged companion over LAN',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: CompanionPage()),
        ),
      );
      Future<void> waitFor(bool Function() ready, {int seconds = 30}) async {
        final deadline = DateTime.now().add(Duration(seconds: seconds));
        String? lastVerification;
        while (!ready()) {
          final verification = container
              .read(companionControllerProvider)
              .verification;
          if (verification != null && verification != lastVerification) {
            debugPrint('CONNECTION_TEST_VERIFICATION $verification');
            lastVerification = verification;
          }
          if (DateTime.now().isAfter(deadline)) {
            fail(
              'Timed out: ${container.read(companionControllerProvider).phase} / ${container.read(companionControllerProvider).message}. Preserve trust with --no-uninstall.',
            );
          }
          await tester.pump(const Duration(milliseconds: 250));
        }
      }

      await waitFor(
        () =>
            !container.read(companionControllerProvider).busy &&
            container.read(companionControllerProvider).phase !=
                CompanionPhase.loading,
      );
      if (!restart &&
          container.read(companionControllerProvider).phase !=
              CompanionPhase.connected) {
        expect(
          raw.isNotEmpty,
          true,
          reason:
              'Supply the private device-config.json from the demo companion.',
        );
        if (direct) {
          debugPrint(
            'CONNECTION_TEST_LIFECYCLE ${WidgetsBinding.instance.lifecycleState}',
          );
          final endpoint = PairingCode.parse(raw).endpoints.first;
          try {
            final socket = await Socket.connect(
              endpoint.host,
              endpoint.port,
              timeout: const Duration(seconds: 5),
            );
            socket.destroy();
            debugPrint('CONNECTION_TEST_LAN_TCP reachable');
          } on SocketException catch (e) {
            fail(
              'LAN TCP unavailable (${e.osError?.errorCode}); check shared Wi-Fi/firewall.',
            );
          }
          unawaited(
            container
                .read(companionControllerProvider.notifier)
                .pair(raw, 'My Journal phone'),
          );
        } else {
          await tester.tap(find.text('Paste pairing code'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), raw);
          await tester.tap(find.text('Continue'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Verify & request trust'));
          await tester.pump();
        }
        // The desktop must explicitly approve the displayed phone verification code.
        await waitFor(
          () =>
              container.read(companionControllerProvider).phase ==
              CompanionPhase.connected,
          seconds: 120,
        );
      } else {
        await waitFor(
          () =>
              container.read(companionControllerProvider).phase ==
              CompanionPhase.connected,
        );
      }
      final controller = container.read(companionControllerProvider.notifier);
      await controller.disconnect();
      expect(
        container.read(companionControllerProvider).selected!.enabled,
        false,
      );
      await controller.disconnect(resume: true);
      await waitFor(
        () =>
            container.read(companionControllerProvider).phase ==
            CompanionPhase.connected,
      );
      final scan = controller.discover();
      await waitFor(
        () => !container.read(companionControllerProvider).scanning,
      );
      await scan;
      final state = container.read(companionControllerProvider);
      final endpoint = state.selected!.endpoint;
      if (expectedPort != 0) expect(endpoint.port, expectedPort);
      expect(endpoint.host, isNot('127.0.0.1'));
      expect(
        endpoint.host,
        isNot('10.0.2.2'),
      ); // no emulator host bridge or adb reverse
      expect(
        (state.status!['capabilities'] as List).single['implemented'],
        true,
      );
      expect(state.status!['id'], state.selected!.id);
      final trusted = state.selected!;
      final unauthorized = TrustedComputer(
        id: trusted.id,
        name: trusted.name,
        pin: trusted.pin,
        endpoint: trusted.endpoint,
        seed: trusted.seed,
        publicKey: trusted.publicKey,
        deviceId: '0' * 32,
      );
      String? unauthorizedCode;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          await CompanionClient(container.read(companionTransportProvider))
              .status(unauthorized);
          fail('An unauthorized device was accepted.');
        } on CompanionFailure catch (error) {
          unauthorizedCode = error.code;
          if (error.code == 'UNAUTHORIZED') break;
          if (error.code != 'UNAVAILABLE') rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
      expect(unauthorizedCode, 'UNAUTHORIZED');
      binding.reportData = {
        'physical_device': true,
        'transport': 'pinned TLS + Ed25519',
        'desktop_id': state.selected!.id,
        'endpoint': endpoint.toString(),
        'capability_status':
            (state.status!['capabilities'] as List).single['status'],
        'cold_restart': restart,
        'bonjour_discovered': state.discovered.any(
          (d) => d.id == state.selected!.id,
        ),
        'disconnect_reconnect': true,
        'bootstrap': restart
            ? 'protected storage'
            : direct
            ? 'test controller with full QR code'
            : 'full code pasted through real UI',
        'unauthorized_device_rejected': true,
        'journal_content_sent': false,
      };
      debugPrint('COMPANION_DEVICE_EVIDENCE ${jsonEncode(binding.reportData)}');
      // Deterministic stale QR and unauthorized-device cases on the actual phone.
      if (!restart) {
        final expired = jsonDecode(raw) as Map<String, dynamic>;
        expired['expires'] = 1;
        await container
            .read(companionControllerProvider.notifier)
            .pair(jsonEncode(expired), 'Expired test');
        expect(
          container.read(companionControllerProvider).message,
          contains('fresh QR'),
        );
        await container.read(companionControllerProvider.notifier).reconnect();
        await waitFor(
          () =>
              container.read(companionControllerProvider).phase ==
              CompanionPhase.connected,
        );
      }
      expect(find.text('Connected · identity verified'), findsOneWidget);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
