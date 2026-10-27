import 'dart:async';

import 'package:bonsoir/bonsoir.dart';

import 'companion_protocol.dart';

class DiscoveredComputer {
  const DiscoveredComputer({
    required this.name,
    required this.id,
    required this.version,
    required this.pin,
    required this.endpoints,
  });
  final String name, id, version, pin;
  final List<Uri> endpoints;
}

abstract interface class ComputerDiscovery {
  Future<void> scan(void Function(DiscoveredComputer) found);
  Future<void> stop();
}

class BonjourComputerDiscovery implements ComputerDiscovery {
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _subscription;
  Timer? _timer;
  Completer<void>? _done;
  @override
  Future<void> scan(void Function(DiscoveredComputer) found) async {
    await stop();
    final discovery = BonsoirDiscovery(
      type: '_journal-ai._tcp',
      printLogs: false,
    );
    _discovery = discovery;
    final done = Completer<void>();
    _done = done;
    try {
      await discovery.initialize().timeout(const Duration(seconds: 4));
      if (_discovery != discovery) return;
      _subscription = discovery.eventStream!.listen(
        (event) {
          if (event is BonsoirDiscoveryServiceFoundEvent) {
            event.service.resolve(discovery.serviceResolver);
          } else if (event is BonsoirDiscoveryServiceResolvedEvent ||
              event is BonsoirDiscoveryServiceUpdatedEvent) {
            final service = event.service!;
            final endpoints = <Uri>[];
            for (final address in service.hostAddresses.take(8)) {
              try {
                endpoints.add(
                  localEndpoint('https://$address:${service.port}'),
                );
              } on CompanionFailure {
                /* IPv6-only is unsupported in this preview. */
              }
            }
            if (endpoints.isNotEmpty) {
              found(
                DiscoveredComputer(
                  name: service.name,
                  id: service.attributes['id'] ?? '',
                  version: service.attributes['v'] ?? '',
                  pin: service.attributes['fp'] ?? '',
                  endpoints: endpoints,
                ),
              );
            }
          }
        },
        onError: (Object error) {
          if (!done.isCompleted) {
            done.completeError(
              const CompanionFailure(
                'DISCOVERY_FAILED',
                'Discovery failed. Allow local network access in system Settings, or scan/paste the desktop QR.',
              ),
            );
          }
        },
      );
      await discovery.start().timeout(const Duration(seconds: 4));
      _timer = Timer(const Duration(seconds: 10), () {
        if (!done.isCompleted) done.complete();
      });
      await done.future;
    } on CompanionFailure {
      rethrow;
    } catch (_) {
      throw const CompanionFailure(
        'DISCOVERY_FAILED',
        'Discovery unavailable. Allow local network access in system Settings, or scan/paste the full desktop pairing code.',
      );
    } finally {
      if (_discovery == discovery) await stop();
    }
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    if (_done case final done? when !done.isCompleted) {
      done.complete();
    }
    _done = null;
    await _subscription?.cancel();
    _subscription = null;
    final discovery = _discovery;
    _discovery = null;
    if (discovery?.isReady == true && !discovery!.isStopped) {
      try {
        await discovery.stop().timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
  }
}
