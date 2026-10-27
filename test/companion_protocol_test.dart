import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';

void main() {
  Map<String, dynamic> code() => {
    'v': 1,
    'id': '12345678-1234-1234-1234-123456789abc',
    'name': 'Desktop',
    'pin': 'a' * 64,
    'secret': 'b' * 43,
    'endpoints': ['https://192.168.1.10:47921'],
    'expires': 101000,
  };
  test('pairing validates expiry, version, local endpoints and credential-bearing URLs', () {
    final time = DateTime.fromMillisecondsSinceEpoch(100000);
    expect(
      PairingCode.parse(jsonEncode(code()), now: time).endpoints.single.host,
      '192.168.1.10',
    );
    for (final endpoint in [
      'http://192.168.1.10:47921',
      'https://example.com',
      'https://user:pass@192.168.1.10',
      'https://192.168.1.10/path',
      'https://192.168.1.10?secret=1',
      'https://8.8.8.8',
    ]) {
      expect(
        () => PairingCode.parse(
          jsonEncode({
            ...code(),
            'endpoints': [endpoint],
          }),
          now: time,
        ),
        throwsA(isA<CompanionFailure>()),
      );
    }
    expect(
      () => PairingCode.parse(jsonEncode({...code(), 'v': 2}), now: time),
      throwsA(
        isA<CompanionFailure>().having(
          (e) => e.code,
          'code',
          'INCOMPATIBLE_VERSION',
        ),
      ),
    );
    expect(
      () => PairingCode.parse(
        jsonEncode({...code(), 'expires': 100000}),
        now: time,
      ),
      throwsA(
        isA<CompanionFailure>().having(
          (e) => e.code,
          'code',
          'PAIRING_EXPIRED',
        ),
      ),
    );
  });
  test('Dart and Node pair and authenticate over actual pinned TLS; changed pin and revocation fail', () async {
    final peer = await Process.start('node', [
      '../desktop/test/support/dart-peer.cjs',
    ]);
    final lines = peer.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .asBroadcastStream();
    final transport = PinnedCompanionTransport();
    final client = CompanionClient(transport);
    addTearDown(() async {
      transport.close();
      peer.stdin.writeln('quit');
      await peer.stdin.flush();
      await peer.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          peer.kill();
          return -1;
        },
      );
    });
    final pairing = PairingCode.parse(
      await lines.first.timeout(const Duration(seconds: 10)),
    );
    final endpoint = pairing.endpoints.single;
    await expectLater(
      transport.request(endpoint, '0' * 64, 'GET', '/v1/info'),
      throwsA(
        isA<CompanionFailure>().having(
          (e) => e.code,
          'code',
          'IDENTITY_CHANGED',
        ),
      ),
    );
    final pending = await client.beginPair(
      pairing,
      endpoint,
      'Dart synthetic phone',
    );
    final status = await client.status(pending.computer);
    expect(status['transport'], 'connected');
    expect((status['capabilities'] as List).single['status'], 'unloaded');
    final revoked = lines.first;
    peer.stdin.writeln('revoke');
    await peer.stdin.flush();
    await revoked;
    await expectLater(
      client.status(pending.computer),
      throwsA(
        isA<CompanionFailure>().having((e) => e.code, 'code', 'UNAUTHORIZED'),
      ),
    );
  }, timeout: const Timeout(Duration(seconds: 40)));
}
