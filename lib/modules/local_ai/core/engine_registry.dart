import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'on_device_engine.dart';
import '../engines/qvac/qvac_bare_engine.dart';

/// The only registration point. Replace the factory with `null` and remove the
/// import above to remove this engine. All callers accept an empty registry.
final onDeviceEngineProvider = Provider<OnDeviceEngine?>((ref) {
  final OnDeviceEngine? engine = Platform.isAndroid || Platform.isIOS
      ? QvacBareEngine()
      : null;
  ref.onDispose(() {
    engine?.stop();
  });
  return engine;
});
