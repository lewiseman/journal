import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

class CompanionFailure implements Exception {
  const CompanionFailure(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

// Pairing codes are data, never arbitrary URLs or navigation instructions.
Uri localEndpoint(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.port < 1 ||
      uri.port > 65535) {
    throw const CompanionFailure(
      'INVALID_CODE',
      'Use the full pairing code from Journal Companion.',
    );
  }
  final host = uri.host.toLowerCase();
  final ip = InternetAddress.tryParse(host);
  final bytes = ip?.rawAddress;
  final local =
      ip?.type == InternetAddressType.IPv4 &&
      (bytes![0] == 10 ||
          bytes[0] == 127 ||
          (bytes[0] == 192 && bytes[1] == 168) ||
          (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
          (bytes[0] == 169 && bytes[1] == 254));
  if (!local) {
    throw const CompanionFailure(
      'INVALID_ENDPOINT',
      'This preview requires an IPv4 local network address from the companion.',
    );
  }
  return uri.replace(path: '');
}

class PairingCode {
  PairingCode({
    required this.id,
    required this.name,
    required this.pin,
    required this.endpoints,
    required this.secret,
    required this.expires,
  });
  final String id, name, pin, secret;
  final List<Uri> endpoints;
  final int expires;
  factory PairingCode.parse(String raw, {DateTime? now}) {
    try {
      if (utf8.encode(raw).length > 8192) throw const FormatException();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['v'] != 1) {
        throw const CompanionFailure(
          'INCOMPATIBLE_VERSION',
          'Update Journal and the companion to matching versions.',
        );
      }
      final expires = data['expires'] as int;
      final time = (now ?? DateTime.now()).millisecondsSinceEpoch;
      if (expires <= time || expires > time + 180000) {
        throw const CompanionFailure(
          'PAIRING_EXPIRED',
          'Create a fresh QR on the desktop. Check both clocks if it still appears expired.',
        );
      }
      final id = data['id'] as String,
          name = data['name'] as String,
          pin = data['pin'] as String,
          secret = data['secret'] as String;
      if (!RegExp(r'^[a-f0-9-]{36}$').hasMatch(id) ||
          name.isEmpty ||
          name.length > 48 ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(pin) ||
          !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(secret)) {
        throw const FormatException();
      }
      final endpoints = (data['endpoints'] as List)
          .cast<String>()
          .map(localEndpoint)
          .toList();
      if (endpoints.isEmpty || endpoints.length > 8) {
        throw const FormatException();
      }
      return PairingCode(
        id: id,
        name: name,
        pin: pin,
        endpoints: endpoints,
        secret: secret,
        expires: expires,
      );
    } on CompanionFailure {
      rethrow;
    } catch (_) {
      throw const CompanionFailure(
        'INVALID_CODE',
        'This is not a valid Journal Companion QR. Create a new one on your computer.',
      );
    }
  }
}

class TrustedComputer {
  const TrustedComputer({
    required this.id,
    required this.name,
    required this.pin,
    required this.endpoint,
    required this.seed,
    required this.publicKey,
    required this.deviceId,
    this.enabled = true,
  });
  final String id, name, pin, seed, publicKey, deviceId;
  final Uri endpoint;
  final bool enabled;
  TrustedComputer copyWith({Uri? endpoint, bool? enabled}) => TrustedComputer(
    id: id,
    name: name,
    pin: pin,
    endpoint: endpoint ?? this.endpoint,
    seed: seed,
    publicKey: publicKey,
    deviceId: deviceId,
    enabled: enabled ?? this.enabled,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'pin': pin,
    'endpoint': endpoint.toString(),
    'seed': seed,
    'publicKey': publicKey,
    'deviceId': deviceId,
    'enabled': enabled,
  };
  factory TrustedComputer.fromJson(Map<String, dynamic> json) {
    final seed = json['seed'] as String,
        key = json['publicKey'] as String,
        pin = json['pin'] as String;
    if (base64Decode(seed).length != 32 ||
        base64Decode(key).length != 32 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(pin)) {
      throw const FormatException();
    }
    return TrustedComputer(
      id: json['id'] as String,
      name: json['name'] as String,
      pin: pin,
      endpoint: localEndpoint(json['endpoint'] as String),
      seed: seed,
      publicKey: key,
      deviceId: json['deviceId'] as String,
      enabled: json['enabled'] as bool,
    );
  }
}

Future<String> hexHash(List<int> bytes) async =>
    (await Sha256().hash(bytes)).bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
String requestCanonical(
  String device,
  String method,
  String route,
  String nonce,
  String digest,
) => 'v1\n$device\n$method\n$route\n$nonce\n$digest';

abstract interface class CompanionTransport {
  Future<Map<String, dynamic>> request(
    Uri endpoint,
    String pin,
    String method,
    String route, {
    Map<String, dynamic>? body,
    Map<String, String> headers,
  });
  void close();
}

class PinnedCompanionTransport implements CompanionTransport {
  final Set<HttpClient> _clients = {};
  bool _closed = false;
  @override
  Future<Map<String, dynamic>> request(
    Uri endpoint,
    String pin,
    String method,
    String route, {
    Map<String, dynamic>? body,
    Map<String, String> headers = const {},
  }) async {
    if (_closed) {
      throw const CompanionFailure('CANCELLED', 'Connection closed.');
    }
    localEndpoint(endpoint.toString());
    // No public roots: every server must pass the exact QR/stored certificate pin.
    // Verify before handing the socket to HTTP, before any credentials are sent.
    final client = HttpClient(
      context: SecurityContext(withTrustedRoots: false),
    );
    _clients.add(client);
    client.connectionTimeout = const Duration(seconds: 5);
    client.idleTimeout = const Duration(seconds: 1);
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
          final certificate = secure.peerCertificate;
          if (certificate == null ||
              await hexHash(certificate.der) != pin ||
              certificate.endValidity.isBefore(DateTime.now())) {
            secure.destroy();
            throw const CompanionFailure(
              'IDENTITY_CHANGED',
              'Computer identity verification failed. Keep the existing trust; verify the intended computer and pair again explicitly.',
            );
          }
          return secure;
        }),
        task.cancel,
      );
    };
    try {
      final request = await client
          .openUrl(method, endpoint.resolve(route))
          .timeout(const Duration(seconds: 7));
      request.followRedirects = false;
      request.headers.set('x-journal-version', '1');
      headers.forEach(request.headers.set);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(body)));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 7),
      );
      final bytes = <int>[];
      // Only a generated background (I06) is larger than ordinary responses.
      final limit =
          RegExp(r'^/v1/image-jobs/[A-Za-z0-9_-]+/result$').hasMatch(route)
          ? 6 * 1024 * 1024
          : 65536;
      await for (final chunk in response.timeout(const Duration(seconds: 7))) {
        bytes.addAll(chunk);
        if (bytes.length > limit) {
          throw const CompanionFailure(
            'INVALID_RESPONSE',
            'The computer sent an oversized response.',
          );
        }
      }
      final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        final error = data['error'] as Map<String, dynamic>?;
        throw CompanionFailure(
          error?['code'] as String? ?? 'UNAVAILABLE',
          error?['message'] as String? ?? 'The companion is unavailable.',
        );
      }
      return data;
    } on CompanionFailure {
      rethrow;
    } on HandshakeException {
      throw const CompanionFailure(
        'IDENTITY_CHANGED',
        'The computer identity could not be verified. Check the intended desktop and create a fresh QR.',
      );
    } on SocketException catch (e) {
      if (e.osError?.errorCode == 1 || e.osError?.errorCode == 13) {
        throw const CompanionFailure(
          'PERMISSION_DENIED',
          'Allow Journal local network access in system Settings, then retry.',
        );
      }
      throw const CompanionFailure(
        'UNAVAILABLE',
        'Computer unreachable. Open the companion on the same Wi-Fi, allow local network access, then retry. A hotspot or guest network may block devices.',
      );
    } catch (e) {
      throw const CompanionFailure(
        'UNAVAILABLE',
        'No verified response. Check the companion, local network permission and Wi-Fi, then retry.',
      );
    } finally {
      client.close(force: true);
      _clients.remove(client);
    }
  }

  @override
  void close() {
    _closed = true;
    for (final client in _clients) {
      client.close(force: true);
    }
    _clients.clear();
  }
}

class CompanionClient {
  CompanionClient(this.transport);
  final CompanionTransport transport;
  final _ed = Ed25519();
  Future<Map<String, dynamic>> authenticated(
    TrustedComputer computer,
    String method,
    String route, {
    Map<String, dynamic>? body,
  }) async {
    final challenge = await transport.request(
      computer.endpoint,
      computer.pin,
      'GET',
      '/v1/challenge',
    );
    final nonce = challenge['nonce'] as String;
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(nonce)) {
      throw const CompanionFailure(
        'INVALID_RESPONSE',
        'Invalid verification challenge.',
      );
    }
    final digest = await hexHash(
      utf8.encode(body == null ? '' : jsonEncode(body)),
    );
    final key = await _ed.newKeyPairFromSeed(base64Decode(computer.seed));
    final signature = await _ed.sign(
      utf8.encode(
        requestCanonical(computer.deviceId, method, route, nonce, digest),
      ),
      keyPair: key,
    );
    return transport.request(
      computer.endpoint,
      computer.pin,
      method,
      route,
      body: body,
      headers: {
        'x-journal-device': computer.deviceId,
        'x-journal-nonce': nonce,
        'x-journal-signature': base64Encode(signature.bytes),
      },
    );
  }

  Future<({TrustedComputer computer, String ticket, String verification})>
  beginPair(PairingCode code, Uri endpoint, String phoneName) async {
    final seed = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final key = await _ed.newKeyPairFromSeed(seed);
    final pub = (await key.extractPublicKey()).bytes;
    final encoded = base64Encode(pub);
    final proof = await _ed.sign(
      utf8.encode('pair-v1\n${code.id}\n${code.secret}\n$encoded\n$phoneName'),
      keyPair: key,
    );
    final info = await transport.request(endpoint, code.pin, 'GET', '/v1/info');
    if (info['v'] != 1) {
      throw const CompanionFailure(
        'INCOMPATIBLE_VERSION',
        'Update Journal and the companion.',
      );
    }
    if (info['id'] != code.id) {
      throw const CompanionFailure(
        'IDENTITY_CHANGED',
        'This is a different computer. Scan the intended desktop QR.',
      );
    }
    final result = await transport.request(
      endpoint,
      code.pin,
      'POST',
      '/v1/pair',
      body: {
        'secret': code.secret,
        'name': phoneName,
        'publicKey': encoded,
        'proof': base64Encode(proof.bytes),
      },
    );
    final id = (await hexHash(pub)).substring(0, 32);
    if (result['id'] != id) {
      throw const CompanionFailure(
        'VERIFICATION_FAILED',
        'The computer did not verify this phone’s key.',
      );
    }
    return (
      computer: TrustedComputer(
        id: code.id,
        name: code.name,
        pin: code.pin,
        endpoint: endpoint,
        seed: base64Encode(seed),
        publicKey: encoded,
        deviceId: id,
      ),
      ticket: result['ticket'] as String,
      verification: (await hexHash(pub)).substring(0, 12),
    );
  }

  Future<Map<String, dynamic>> status(TrustedComputer computer) async {
    final value = await authenticated(computer, 'GET', '/v1/status');
    if (value['id'] != computer.id) {
      throw const CompanionFailure(
        'IDENTITY_CHANGED',
        'The verified desktop identity changed. Review it and pair explicitly.',
      );
    }
    if (value['v'] != 1) {
      throw const CompanionFailure(
        'INCOMPATIBLE_VERSION',
        'Update Journal and the companion.',
      );
    }
    final capabilities = value['capabilities'];
    if (value['transport'] != 'connected' ||
        capabilities is! List ||
        capabilities.length > 8 ||
        capabilities.any(
          (c) =>
              c is! Map ||
              c['id'] is! String ||
              c['implemented'] is! bool ||
              c['status'] is! String ||
              c['reason'] is! String ||
              (c['id'] as String).length > 48 ||
              (c['status'] as String).length > 48 ||
              (c['reason'] as String).length > 1024,
        )) {
      throw const CompanionFailure(
        'INVALID_RESPONSE',
        'The companion sent invalid capability status. Update both apps and retry.',
      );
    }
    return value;
  }
}
