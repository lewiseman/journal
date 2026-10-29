import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DeviceResources {
  const DeviceResources({
    required this.freeBytes,
    required this.ramBytes,
    required this.wifi,
  });
  final int freeBytes, ramBytes;
  final bool wifi;
}

/// Independent of the inference engine, including its native implementation.
class ModelStorage {
  static const _channel = MethodChannel('journal/local_ai_storage');
  Future<Directory> directory() async {
    final path = await _channel.invokeMethod<String>('directory');
    if (path == null) throw StateError('Model storage is unavailable');
    return Directory(path).create(recursive: true);
  }

  Future<DeviceResources> resources() async {
    final j = await _channel.invokeMapMethod<String, dynamic>('resources');
    return DeviceResources(
      freeBytes: j?['freeBytes'] ?? 0,
      ramBytes: j?['ramBytes'] ?? 0,
      wifi: j?['wifi'] == true,
    );
  }
}

final modelStorageProvider = Provider<ModelStorage>((ref) => ModelStorage());
final deviceResourcesProvider = FutureProvider<DeviceResources>(
  (ref) => ref.watch(modelStorageProvider).resources(),
);
