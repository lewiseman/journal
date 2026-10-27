import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journal/utils/network.dart';

import 'companion_discovery.dart';
import 'companion_protocol.dart';
import 'companion_store.dart';

enum CompanionPhase {
  loading,
  idle,
  trusted,
  connecting,
  connected,
  pairing,
  unavailable,
  permissionDenied,
  incompatible,
  identityChanged,
  revoked,
}

class CompanionState {
  const CompanionState({
    this.phase = CompanionPhase.loading,
    this.computers = const [],
    this.selectedId,
    this.discovered = const [],
    this.scanning = false,
    this.busy = false,
    this.message,
    this.verification,
    this.status,
  });
  final CompanionPhase phase;
  final List<TrustedComputer> computers;
  final String? selectedId;
  final List<DiscoveredComputer> discovered;
  final bool scanning, busy;
  final String? message, verification;
  final Map<String, dynamic>? status;
  TrustedComputer? get selected =>
      computers.where((c) => c.id == selectedId).firstOrNull;
  CompanionState copyWith({
    CompanionPhase? phase,
    List<TrustedComputer>? computers,
    String? selectedId,
    bool clearSelected = false,
    List<DiscoveredComputer>? discovered,
    bool? scanning,
    bool? busy,
    String? message,
    String? verification,
    Map<String, dynamic>? status,
    bool clearStatus = false,
    bool clearMessage = false,
    bool clearVerification = false,
  }) => CompanionState(
    phase: phase ?? this.phase,
    computers: computers ?? this.computers,
    selectedId: clearSelected ? null : selectedId ?? this.selectedId,
    discovered: discovered ?? this.discovered,
    scanning: scanning ?? this.scanning,
    busy: busy ?? this.busy,
    message: clearMessage ? null : message ?? this.message,
    verification: clearVerification ? null : verification ?? this.verification,
    status: clearStatus ? null : status ?? this.status,
  );
}

final companionStoreProvider = Provider<ComputerStore>(
  (ref) => ProtectedComputerStore(),
);
final companionTransportProvider = Provider<CompanionTransport>((ref) {
  final value = PinnedCompanionTransport();
  ref.onDispose(value.close);
  return value;
});
final companionDiscoveryProvider = Provider<ComputerDiscovery>((ref) {
  final value = BonjourComputerDiscovery();
  ref.onDispose(() => unawaited(value.stop()));
  return value;
});
final companionControllerProvider =
    NotifierProvider<CompanionController, CompanionState>(
      CompanionController.new,
    );

class CompanionController extends Notifier<CompanionState> {
  late ComputerStore _store;
  late CompanionClient _client;
  late ComputerDiscovery _discovery;
  Timer? _retry;
  Timer? _networkDebounce;
  AppLifecycleListener? _lifecycle;
  StreamSubscription<NetworkType>? _network;
  int _generation = 0;
  bool _foreground = true;
  bool _probing = false;
  bool _pendingReconnect = false;
  bool _restored = false;
  Future<void>? _restoration;
  @override
  CompanionState build() {
    _store = ref.read(companionStoreProvider);
    _client = CompanionClient(ref.read(companionTransportProvider));
    _discovery = ref.read(companionDiscoveryProvider);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _lifecycle = AppLifecycleListener(
      onStateChange: (value) => foreground(value == AppLifecycleState.resumed),
    );
    _network = NetworkService().onConnectivityChanged.listen(
      (_) {
        if (!_foreground) return;
        _networkDebounce?.cancel();
        _networkDebounce = Timer(
          const Duration(seconds: 1),
          () => unawaited(reconnect()),
        );
      },
      onError: (Object _) {
        /* Interface events are only retry hints. */
      },
    );
    ref.onDispose(() {
      _generation++;
      _retry?.cancel();
      _networkDebounce?.cancel();
      _lifecycle?.dispose();
      unawaited(_network?.cancel());
      unawaited(_discovery.stop());
    });
    scheduleMicrotask(() {
      if (ref.mounted) unawaited(restore());
    });
    return const CompanionState(busy: true);
  }

  void _failure(Object error) {
    if (!ref.mounted) return;
    final e = error is CompanionFailure
        ? error
        : const CompanionFailure(
            'UNAVAILABLE',
            'The computer could not respond. Retry on the same Wi-Fi.',
          );
    final phase = switch (e.code) {
      'IDENTITY_CHANGED' ||
      'VERIFICATION_FAILED' => CompanionPhase.identityChanged,
      'UNAUTHORIZED' => CompanionPhase.revoked,
      'INCOMPATIBLE_VERSION' => CompanionPhase.incompatible,
      'PERMISSION_DENIED' => CompanionPhase.permissionDenied,
      _ => CompanionPhase.unavailable,
    };
    state = state.copyWith(
      phase: phase,
      busy: false,
      clearStatus: true,
      message: e.message,
    );
  }

  Future<void> restore() {
    final pending = _restoration;
    if (pending != null) return pending;
    final future = _restore();
    _restoration = future;
    return future.whenComplete(() => _restoration = null);
  }

  Future<void> _restore() async {
    try {
      final records = await _store.load();
      if (!ref.mounted) return;
      _restored = true;
      state = CompanionState(
        phase: records.computers.isEmpty
            ? CompanionPhase.idle
            : CompanionPhase.trusted,
        computers: records.computers,
        selectedId: records.selected,
      );
      if (_foreground) await reconnect();
    } catch (e) {
      _failure(e);
    }
  }

  Future<void> _save(List<TrustedComputer> computers, String? selected) =>
      _store.save(ComputerRecords(computers, selected));
  void foreground(bool active) {
    _foreground = active;
    _generation++;
    _retry?.cancel();
    _networkDebounce?.cancel();
    unawaited(_discovery.stop());
    if (!ref.mounted) return;
    state = state.copyWith(
      scanning: false,
      busy: state.busy && state.phase != CompanionPhase.pairing,
      clearVerification: true,
      clearStatus: true,
      phase: !_restored
          ? CompanionPhase.loading
          : state.selected == null
          ? CompanionPhase.idle
          : CompanionPhase.trusted,
    );
    if (active) unawaited(_restored ? reconnect() : restore());
  }

  Future<void> discover() async {
    if (state.scanning || !_foreground || state.busy || _probing) return;
    state = state.copyWith(scanning: true, discovered: [], clearMessage: true);
    try {
      await _discovery.scan((computer) {
        if (!ref.mounted || !_foreground) return;
        state = state.copyWith(
          discovered: [
            ...state.discovered.where((c) => c.id != computer.id),
            computer,
          ],
        );
      });
      if (ref.mounted && state.discovered.isEmpty) {
        state = state.copyWith(
          message: 'No computer found. Open Connect a phone on the companion, check local network permission, or scan/paste its full pairing code. Guest Wi-Fi and hotspots may block discovery.',
        );
      }
    } catch (e) {
      if (ref.mounted) {
        state = state.copyWith(
          message: e is CompanionFailure
              ? e.message
              : 'Discovery failed. Scan or paste the desktop code.',
        );
      }
    } finally {
      if (ref.mounted) state = state.copyWith(scanning: false);
    }
  }

  Future<void> select(String id) async {
    if (state.busy || state.selectedId == id) return;
    _generation++;
    _retry?.cancel();
    state = state.copyWith(busy: true, clearStatus: true);
    try {
      await _save(state.computers, id);
      if (!ref.mounted) return;
      state = state.copyWith(
        busy: false,
        selectedId: id,
        clearStatus: true,
        clearMessage: true,
      );
      await reconnect();
    } catch (e) {
      _failure(e);
    }
  }

  Future<void> reconnect() async {
    if (!ref.mounted || !_foreground || state.busy) return;
    if (_probing) {
      _pendingReconnect = true;
      return;
    }
    final computer = state.selected;
    if (computer == null || !computer.enabled) return;
    _retry?.cancel();
    final generation = ++_generation;
    await _probe(computer, generation, 0);
  }

  Future<void> _probe(
    TrustedComputer computer,
    int generation,
    int attempt,
  ) async {
    if (!ref.mounted || !_foreground || generation != _generation) return;
    _probing = true;
    state = state.copyWith(
      phase: CompanionPhase.connecting,
      clearStatus: true,
      clearMessage: true,
    );
    try {
      final status = await _client.status(computer);
      if (!ref.mounted || generation != _generation) return;
      state = state.copyWith(
        phase: CompanionPhase.connected,
        status: status,
        clearMessage: true,
      );
      _retry = Timer(
        const Duration(seconds: 15),
        () => unawaited(_probe(computer, generation, 0)),
      );
    } catch (e) {
      if (!ref.mounted || generation != _generation) return;
      _failure(e);
      final terminal = [
        CompanionPhase.revoked,
        CompanionPhase.identityChanged,
        CompanionPhase.incompatible,
        CompanionPhase.permissionDenied,
      ].contains(state.phase);
      if (!terminal && attempt < 2) {
        // One bounded Bonjour scan per reconnect episode; only authenticated
        // status can persist a changed endpoint. TXT identity/pins are hints.
        if (attempt == 0) {
          Uri? endpoint;
          try {
            await _discovery.scan((candidate) {
              if (candidate.id == computer.id &&
                  candidate.version == '1' &&
                  candidate.endpoints.isNotEmpty) {
                endpoint ??= candidate.endpoints.first;
              }
            });
            if (generation != _generation || !ref.mounted) return;
            if (endpoint != null) {
              final updated = computer.copyWith(endpoint: endpoint);
              final status = await _client.status(updated);
              if (generation != _generation || !ref.mounted) return;
              final computers = state.computers
                  .map((c) => c.id == updated.id ? updated : c)
                  .toList();
              state = state.copyWith(busy: true);
              await _save(computers, state.selectedId);
              if (generation != _generation || !ref.mounted) {
                if (ref.mounted) {
                  _restored = false;
                  state = state.copyWith(busy: false);
                  if (_foreground) unawaited(restore());
                }
                return;
              }
              state = state.copyWith(
                busy: false,
                computers: computers,
                phase: CompanionPhase.connected,
                status: status,
                clearMessage: true,
              );
              _retry = Timer(
                const Duration(seconds: 15),
                () => unawaited(_probe(updated, generation, 0)),
              );
              return;
            }
          } catch (rediscoveryError) {
            if (generation == _generation) _failure(rediscoveryError);
          }
        }
        if (generation == _generation &&
            ref.mounted &&
            ![
              CompanionPhase.identityChanged,
              CompanionPhase.incompatible,
              CompanionPhase.revoked,
            ].contains(state.phase)) {
          _retry = Timer(
            Duration(seconds: attempt == 0 ? 2 : 8),
            () => unawaited(_probe(computer, generation, attempt + 1)),
          );
        }
      }
    } finally {
      _probing = false;
      if (_pendingReconnect && ref.mounted && _foreground) {
        _pendingReconnect = false;
        scheduleMicrotask(() {
          if (ref.mounted) unawaited(reconnect());
        });
      }
    }
  }

  Future<void> pair(String raw, String phoneName, {String? expectedId}) async {
    if (state.busy || !_foreground) return;
    if (!_restored) {
      await restore();
      if (!_restored || !ref.mounted) return;
    }
    final generation = ++_generation;
    _retry?.cancel();
    await _discovery.stop();
    state = state.copyWith(
      busy: true,
      phase: CompanionPhase.pairing,
      clearMessage: true,
      clearStatus: true,
      clearVerification: true,
    );
    try {
      final code = PairingCode.parse(raw);
      if (expectedId != null && code.id != expectedId) {
        throw const CompanionFailure(
          'IDENTITY_CHANGED',
          'This QR belongs to a different computer than the discovered one. Verify the intended desktop.',
        );
      }
      final existing = state.computers
          .where((c) => c.id == code.id)
          .firstOrNull;
      if (existing != null && existing.pin != code.pin) {
        throw const CompanionFailure(
          'IDENTITY_CHANGED',
          'This computer has a new identity. Forget its old trust explicitly, verify the desktop, then pair again.',
        );
      }
      if (existing != null) {
        throw const CompanionFailure(
          'ALREADY_TRUSTED',
          'This computer is already remembered. Retry connection, or forget it explicitly before pairing again. Existing trust was kept.',
        );
      }
      final name = phoneName.trim();
      if (name.isEmpty ||
          name.length > 48 ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(name)) {
        throw const CompanionFailure(
          'INVALID_INPUT',
          'Enter a phone name of 1–48 characters.',
        );
      }
      Object? lastError;
      for (final endpoint in code.endpoints) {
        try {
          final pairing = await _client.beginPair(code, endpoint, name);
          if (generation != _generation || !ref.mounted) return;
          state = state.copyWith(
            verification: pairing.verification,
            message:
                'Compare this phone code on the desktop, then approve there.',
          );
          final deadline = DateTime.now().add(const Duration(minutes: 2));
          while (DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(seconds: 2));
            if (generation != _generation || !ref.mounted || !_foreground) {
              return;
            }
            final status = await _client.transport.request(
              endpoint,
              code.pin,
              'POST',
              '/v1/pair-status',
              body: {'ticket': pairing.ticket},
            );
            if (status['state'] == 'denied') {
              throw const CompanionFailure(
                'PAIRING_DENIED',
                'Pairing denied on the desktop. Create a fresh QR there when you want to try again.',
              );
            }
            if (status['state'] == 'approved') {
              final authenticated = await _client.status(pairing.computer);
              if (generation != _generation || !ref.mounted || !_foreground) {
                return;
              }
              final computers = [
                ...state.computers.where((c) => c.id != code.id),
                pairing.computer,
              ];
              if (computers.length > 20) {
                throw const CompanionFailure(
                  'DEVICE_LIMIT',
                  'Forget a computer before adding another.',
                );
              }
              await _save(computers, code.id);
              if (generation != _generation || !ref.mounted) {
                _restored = false;
                return;
              }
              state = CompanionState(
                phase: CompanionPhase.connected,
                computers: computers,
                selectedId: code.id,
                status: authenticated,
              );
              _retry = Timer(
                const Duration(seconds: 15),
                () => unawaited(_probe(pairing.computer, generation, 0)),
              );
              return;
            }
          }
          throw const CompanionFailure(
            'PAIRING_EXPIRED',
            'Approval expired. Create a fresh QR on the desktop.',
          );
        } on CompanionFailure catch (e) {
          if (e.code != 'UNAVAILABLE') rethrow;
          lastError = e;
        }
      }
      throw lastError ??
          const CompanionFailure(
            'UNAVAILABLE',
            'No desktop endpoint is reachable.',
          );
    } catch (e) {
      if (ref.mounted && generation == _generation) _failure(e);
    } finally {
      if (ref.mounted && generation == _generation) {
        state = state.copyWith(busy: false, clearVerification: true);
      }
    }
  }

  void cancelPairing() {
    _generation++;
    if (!ref.mounted) return;
    state = state.copyWith(
      busy: false,
      phase: state.selected == null
          ? CompanionPhase.idle
          : CompanionPhase.trusted,
      clearVerification: true,
      message: 'Pairing cancelled on this phone. Deny any pending request on the desktop.',
    );
  }

  Future<void> disconnect({bool resume = false}) async {
    final computer = state.selected;
    if (computer == null || state.busy) return;
    _generation++;
    _retry?.cancel();
    state = state.copyWith(busy: true, clearStatus: true);
    await _discovery.stop();
    try {
      if (!resume) {
        try {
          await _client.authenticated(
            computer,
            'POST',
            '/v1/disconnect',
            body: {},
          );
        } catch (_) {}
      }
      final computers = state.computers
          .map((c) => c.id == computer.id ? c.copyWith(enabled: resume) : c)
          .toList();
      await _save(computers, state.selectedId);
      if (!ref.mounted) return;
      state = state.copyWith(
        busy: false,
        computers: computers,
        phase: CompanionPhase.trusted,
        clearStatus: true,
        message: resume ? 'Reconnecting…' : 'Disconnected. Trust is retained; accepted desktop work continues.',
      );
      if (resume) await reconnect();
    } catch (e) {
      _failure(e);
    }
  }

  Future<void> forget(String id) async {
    final computer = state.computers.where((c) => c.id == id).firstOrNull;
    if (computer == null || state.busy) return;
    _generation++;
    _retry?.cancel();
    state = state.copyWith(busy: true, clearStatus: true);
    await _discovery.stop();
    var remoteRemoved = false;
    try {
      await _client.authenticated(computer, 'POST', '/v1/forget', body: {});
      remoteRemoved = true;
    } catch (_) {}
    final computers = state.computers.where((c) => c.id != id).toList();
    final selected = state.selectedId == id
        ? computers.firstOrNull?.id
        : state.selectedId;
    try {
      await _save(computers, selected);
      if (!ref.mounted) return;
      state = CompanionState(
        phase: CompanionPhase.idle,
        computers: computers,
        selectedId: selected,
        message: remoteRemoved
            ? 'Trust and retained work removed on both devices.'
            : 'Trust removed from this phone. The computer was unreachable: revoke this phone in its Trusted devices list to cancel and delete retained work.',
      );
    } catch (e) {
      _failure(e);
    }
  }
}
