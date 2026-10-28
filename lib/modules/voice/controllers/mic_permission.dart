import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'pcm_recorder.dart';

enum MicStatus {
  /// Not checked yet.
  unknown,
  granted,

  /// Can still be asked for in the app.
  denied,

  /// Permanently denied; only the app's system settings can turn it back on.
  blocked,

  /// This platform has no microphone capture yet.
  unsupported,
}

/// The microphone permission as the voice pages show it, without asking for
/// it until the person taps the card.
class MicPermission extends ChangeNotifier {
  MicPermission({MethodChannel? methods, bool? supported})
    : _methods = methods ?? PcmRecorder.methods,
      _supported = supported ?? Platform.isAndroid;
  final MethodChannel _methods;
  final bool _supported;
  MicStatus status = MicStatus.unknown;
  bool asking = false;
  bool _disposed = false;

  bool get granted => status == MicStatus.granted;

  void _set(MicStatus value) {
    if (_disposed) return;
    status = value;
    notifyListeners();
  }

  static MicStatus _parse(String? value) => switch (value) {
    'granted' => MicStatus.granted,
    'blocked' => MicStatus.blocked,
    _ => MicStatus.denied,
  };

  Future<MicStatus> check() async {
    if (!_supported) {
      _set(MicStatus.unsupported);
      return status;
    }
    try {
      _set(_parse(await _methods.invokeMethod<String>('micStatus')));
    } on PlatformException {
      _set(MicStatus.denied);
    } on MissingPluginException {
      _set(MicStatus.unsupported);
    }
    return status;
  }

  /// Shows the system prompt, or opens settings once that can no longer help.
  Future<MicStatus> request() async {
    if (status == MicStatus.blocked) {
      await openSettings();
      return status;
    }
    if (!_supported || asking) return status;
    asking = true;
    notifyListeners();
    try {
      _set(_parse(await _methods.invokeMethod<String>('requestMic')));
    } on PlatformException {
      await check();
    } finally {
      asking = false;
      if (!_disposed) notifyListeners();
    }
    return status;
  }

  /// The page re-checks when the app resumes from settings.
  Future<void> openSettings() async {
    try {
      await _methods.invokeMethod<bool>('openSettings');
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
