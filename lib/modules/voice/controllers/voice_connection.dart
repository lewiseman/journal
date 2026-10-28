import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';

/// Verify the stored certificate before the WebSocket upgrade sends credentials.
Future<WebSocket> connectVoice(TrustedComputer computer, String id) =>
    connectCompanionSocket(computer, '/v1/voice/live/$id');

/// An authenticated WebSocket to [route] on the paired computer.
Future<WebSocket> connectCompanionSocket(
  TrustedComputer computer,
  String route,
) async {
  final transport = PinnedCompanionTransport();
  final client = HttpClient(context: SecurityContext(withTrustedRoots: false));
  try {
    final challenge = await transport.request(
      computer.endpoint,
      computer.pin,
      'GET',
      '/v1/challenge',
    );
    final nonce = challenge['nonce'] as String;
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(nonce)) {
      throw const FormatException('Invalid nonce');
    }
    final ed = Ed25519(),
        key = await Ed25519().newKeyPairFromSeed(base64Decode(computer.seed));
    final signature = await ed.sign(
      utf8.encode(
        requestCanonical(
          computer.deviceId,
          'GET',
          route,
          nonce,
          await hexHash([]),
        ),
      ),
      keyPair: key,
    );
    client.connectionTimeout = const Duration(seconds: 5);
    client.findProxy = (_) => 'DIRECT';
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      final task = await Socket.startConnect(uri.host, uri.port);
      return ConnectionTask.fromSocket(
        task.socket.then((socket) async {
          final secure = await SecureSocket.secure(
            socket,
            host: uri.host,
            context: SecurityContext(withTrustedRoots: false),
            onBadCertificate: (_) => true,
          );
          final cert = secure.peerCertificate;
          if (cert == null ||
              await hexHash(cert.der) != computer.pin ||
              cert.endValidity.isBefore(DateTime.now())) {
            secure.destroy();
            throw const CompanionFailure(
              'IDENTITY_CHANGED',
              'The computer identity changed. Verify trust in Settings.',
            );
          }
          return secure;
        }),
        task.cancel,
      );
    };
    final ws = await WebSocket.connect(
      computer.endpoint.resolve(route).replace(scheme: 'wss').toString(),
      customClient: client,
      compression: CompressionOptions.compressionOff,
      headers: {
        'x-journal-version': '1',
        'x-journal-device': computer.deviceId,
        'x-journal-nonce': nonce,
        'x-journal-signature': base64Encode(signature.bytes),
      },
    ).timeout(const Duration(seconds: 10));
    ws.pingInterval = const Duration(seconds: 10);
    ws.done.whenComplete(() => client.close(force: true));
    return ws;
  } catch (_) {
    client.close(force: true);
    rethrow;
  } finally {
    transport.close();
  }
}
