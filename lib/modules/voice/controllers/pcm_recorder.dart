import 'dart:async';

import 'package:flutter/services.dart';

/// Owns one native microphone subscription, including its final audio frames.
class PcmRecorder {
  static const methods = MethodChannel('journal/pcm');
  static const events = EventChannel('journal/pcm_events');
  StreamSubscription<dynamic>? _subscription;
  Completer<void>? _stopped;
  Future<void>? _starting, _stopping;
  bool _started = false;

  Future<void> start({
    required String path,
    required void Function(Uint8List) onData,
    required void Function() onStopped,
    required void Function(Object) onError,
  }) async {
    if (_subscription != null) throw StateError('Microphone already active');
    final stopped = _stopped = Completer<void>();
    _subscription = events.receiveBroadcastStream().listen((event) {
      if (event is Uint8List) {
        onData(event);
      } else if (event is Map && event['stopped'] == true) {
        // Native posts this after closing the file and posting every PCM frame.
        if (!stopped.isCompleted) stopped.complete();
        onStopped();
      }
    }, onError: onError);
    final starting = _starting = methods.invokeMethod<void>('start', {
      'path': path,
    });
    try {
      await starting;
      _started = true;
    } finally {
      _starting = null;
    }
  }

  Future<void> stop() {
    // A disposed controller with no subscription must never stop a newer one.
    if (_stopping != null) return _stopping!;
    if (_subscription == null) return Future.value();
    final stopping = _stop();
    _stopping = stopping;
    return stopping.whenComplete(() => _stopping = null);
  }

  Future<void> _stop() async {
    final subscription = _subscription!;
    try {
      try {
        await _starting;
      } catch (_) {
        /* Native cleans up failed starts. */
      }
      if (_started) {
        await methods.invokeMethod<void>('stop');
        // The method reply and EventChannel use different platform messages.
        // A zero-duration delay cannot guarantee the final frames arrived.
        await _stopped!.future.timeout(const Duration(seconds: 3));
      }
    } finally {
      await subscription.cancel();
      _subscription = null;
      _started = false;
      _stopped = null;
    }
  }
}
