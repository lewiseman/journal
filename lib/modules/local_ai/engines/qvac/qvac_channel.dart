import 'package:flutter/services.dart';

import '../../core/on_device_engine.dart';

class QvacChannel {
  static const _methods = MethodChannel('journal/qvac');
  static const _events = EventChannel('journal/qvac_ipc');
  Stream<List<int>> get bytes => _events.receiveBroadcastStream().map((event) {
    if (event is Uint8List) return event;
    throw const EngineFailure(
      'INTERRUPTED',
      'On-device inference was interrupted when Journal left the foreground.',
    );
  });
  Future<String?> start() => _methods.invokeMethod<String>('start');
  Future<void> write(Uint8List bytes) =>
      _methods.invokeMethod<void>('write', bytes);
  Future<void> stop() => _methods.invokeMethod<void>('stop');
}
