import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/modules/settings/companion/companion_discovery.dart';
import 'package:journal/modules/settings/companion/companion_page.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';
import 'package:journal/modules/settings/companion/companion_store.dart';

TrustedComputer computer({
  String id = 'desktop-1',
  String host = '192.168.1.2',
  bool enabled = true,
}) => TrustedComputer(
  id: id,
  name: 'Desktop',
  pin: 'a' * 64,
  endpoint: Uri.parse('https://$host:47921'),
  seed: base64Encode(List.filled(32, 1)),
  publicKey: base64Encode(List.filled(32, 2)),
  deviceId: 'b' * 32,
  enabled: enabled,
);

class MemoryComputers implements ComputerStore {
  MemoryComputers(this.records);
  ComputerRecords records;
  Completer<ComputerRecords>? pending;
  int loads = 0;
  @override
  Future<ComputerRecords> load() async {
    loads++;
    return pending == null ? records : await pending!.future;
  }

  @override
  Future<void> save(ComputerRecords records) async {
    this.records = records;
  }
}

class FakeDiscovery implements ComputerDiscovery {
  List<DiscoveredComputer> candidates = [];
  int scans = 0, stops = 0;
  @override
  Future<void> scan(void Function(DiscoveredComputer) found) async {
    scans++;
    candidates.forEach(found);
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

class FakeTransport implements CompanionTransport {
  String? failure;
  String? unavailableHost;
  final List<String> routes = [];
  @override
  Future<Map<String, dynamic>> request(
    Uri endpoint,
    String pin,
    String method,
    String route, {
    Map<String, dynamic>? body,
    Map<String, String> headers = const {},
  }) async {
    routes.add(route);
    if (failure != null || endpoint.host == unavailableHost)
      throw CompanionFailure(failure ?? 'UNAVAILABLE', 'Synthetic failure');
    if (route == '/v1/challenge') return {'nonce': 'a' * 43};
    if (route == '/v1/status')
      return {
        'v': 1,
        'id': 'desktop-1',
        'transport': 'connected',
        'capabilities': [
          {
            'id': 'text',
            'status': 'unloaded',
            'implemented': true,
            'reason': 'Load the writing model',
          },
        ],
      };
    return {'ok': true};
  }

  @override
  void close() {}
}

void main() {
  testWidgets('foreground events wait for one protected-storage restoration', (
    tester,
  ) async {
    final store = MemoryComputers(const ComputerRecords([], null))
      ..pending = Completer<ComputerRecords>();
    final container = ProviderContainer(
      overrides: [
        companionStoreProvider.overrideWithValue(store),
        companionTransportProvider.overrideWithValue(FakeTransport()),
        companionDiscoveryProvider.overrideWithValue(FakeDiscovery()),
      ],
    );
    container.read(companionControllerProvider);
    await tester.pump();
    final controller = container.read(companionControllerProvider.notifier);
    controller.foreground(true);
    controller.foreground(true);
    expect(
      container.read(companionControllerProvider).phase,
      CompanionPhase.loading,
    );
    expect(container.read(companionControllerProvider).busy, true);
    expect(store.loads, 1);
    store.pending!.complete(const ComputerRecords([], null));
    await tester.pump();
    await tester.pump();
    expect(
      container.read(companionControllerProvider).phase,
      CompanionPhase.idle,
    );
    expect(container.read(companionControllerProvider).busy, false);
    container.dispose();
  });
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 5));
    }
  }

  testWidgets(
    'restored trust checks the actual companion; background clears readiness and disconnect persists',
    (tester) async {
      final store = MemoryComputers(ComputerRecords([computer()], 'desktop-1'));
      final transport = FakeTransport(), discovery = FakeDiscovery();
      final container = ProviderContainer(
        overrides: [
          companionStoreProvider.overrideWithValue(store),
          companionTransportProvider.overrideWithValue(transport),
          companionDiscoveryProvider.overrideWithValue(discovery),
        ],
      );
      container.read(companionControllerProvider);
      await settle(tester);
      expect(
        container.read(companionControllerProvider).phase,
        CompanionPhase.connected,
      );
      expect(
        (container.read(companionControllerProvider).status!['capabilities']
                as List)
            .single['status'],
        'unloaded',
      );
      final controller = container.read(companionControllerProvider.notifier);
      controller.foreground(false);
      final requests = transport.routes.length;
      await tester.pump(const Duration(minutes: 2));
      expect(transport.routes.length, requests);
      expect(container.read(companionControllerProvider).status, isNull);
      controller.foreground(true);
      await settle(tester);
      await controller.disconnect();
      expect(store.records.computers.single.enabled, false);
      final count = transport.routes.length;
      await tester.pump(const Duration(minutes: 1));
      expect(transport.routes.length, count);
      container.dispose();
    },
  );
  testWidgets(
    'changed address is saved only after authentication, while trust pin remains fixed',
    (tester) async {
      final store = MemoryComputers(ComputerRecords([computer()], 'desktop-1'));
      final transport = FakeTransport()..unavailableHost = '192.168.1.2';
      final discovery = FakeDiscovery()
        ..candidates = [
          DiscoveredComputer(
            name: 'Untrusted advertisement',
            id: 'desktop-1',
            version: '1',
            pin: 'forged TXT',
            endpoints: [Uri.parse('https://192.168.1.3:47921')],
          ),
        ];
      final container = ProviderContainer(
        overrides: [
          companionStoreProvider.overrideWithValue(store),
          companionTransportProvider.overrideWithValue(transport),
          companionDiscoveryProvider.overrideWithValue(discovery),
        ],
      );
      container.read(companionControllerProvider);
      await settle(tester);
      expect(
        container.read(companionControllerProvider).phase,
        CompanionPhase.connected,
      );
      expect(store.records.computers.single.endpoint.host, '192.168.1.3');
      expect(store.records.computers.single.pin, 'a' * 64);
      expect(discovery.scans, 1);
      container.dispose();
    },
  );
  testWidgets(
    'revoked, changed identity and incompatible versions stop automatic retry and clear cached status',
    (tester) async {
      for (final (failure, phase) in [
        ('UNAUTHORIZED', CompanionPhase.revoked),
        ('IDENTITY_CHANGED', CompanionPhase.identityChanged),
        ('INCOMPATIBLE_VERSION', CompanionPhase.incompatible),
      ]) {
        final transport = FakeTransport()..failure = failure;
        final discovery = FakeDiscovery();
        final container = ProviderContainer(
          overrides: [
            companionStoreProvider.overrideWithValue(
              MemoryComputers(ComputerRecords([computer()], 'desktop-1')),
            ),
            companionTransportProvider.overrideWithValue(transport),
            companionDiscoveryProvider.overrideWithValue(discovery),
          ],
        );
        container.read(companionControllerProvider);
        await settle(tester);
        expect(container.read(companionControllerProvider).phase, phase);
        expect(container.read(companionControllerProvider).status, isNull);
        expect(discovery.scans, 0);
        final requests = transport.routes.length;
        await tester.pump(const Duration(minutes: 2));
        expect(transport.routes.length, requests);
        container.dispose();
      }
    },
  );
  testWidgets(
    'Settings shows verified transport separately from an unloaded writing model, without sign-in',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            companionStoreProvider.overrideWithValue(
              MemoryComputers(ComputerRecords([computer()], 'desktop-1')),
            ),
            companionTransportProvider.overrideWithValue(FakeTransport()),
            companionDiscoveryProvider.overrideWithValue(FakeDiscovery()),
          ],
          child: const MaterialApp(home: CompanionPage()),
        ),
      );
      await settle(tester);
      expect(find.text('Connected · identity verified'), findsOneWidget);
      expect(find.textContaining('Writing model: unloaded'), findsOneWidget);
      expect(find.text('Scan desktop QR'), findsOneWidget);
      expect(find.text('Sign in'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
