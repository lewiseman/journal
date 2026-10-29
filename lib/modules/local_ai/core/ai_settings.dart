import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journal/utils/cache.dart';

import 'on_device_engine.dart';

enum AiMode { auto, companion, device }

enum AiProviderKind { companion, device }

class AiSettings {
  const AiSettings({
    this.mode = AiMode.companion,
    this.overrides = const {},
    this.assignments = const {},
    this.wifiOnly = true,
  });
  final AiMode mode;
  final Map<AiTask, AiMode> overrides;
  final Map<AiTask, String> assignments;
  final bool wifiOnly;
}

final aiSettingsProvider = NotifierProvider<AiSettingsController, AiSettings>(
  AiSettingsController.new,
);

class AiSettingsController extends Notifier<AiSettings> {
  CacheStorage get _cache => CacheStorage.instance;
  @override
  AiSettings build() {
    AiMode mode(Object? value, AiMode fallback) =>
        AiMode.values.where((e) => e.name == value).firstOrNull ?? fallback;
    try {
      _cache;
    } on StateError {
      return const AiSettings();
    }
    final overrides = _cache.get(aiTaskOverridesKey) ?? {};
    final assignments = _cache.get(aiModelAssignmentsKey) ?? {};
    return AiSettings(
      mode: mode(_cache.get(aiModeKey), AiMode.companion),
      overrides: {
        for (final t in AiTask.values)
          if (overrides.containsKey(t.name))
            t: mode(overrides[t.name], AiMode.auto),
      },
      assignments: {
        for (final t in AiTask.values)
          if (assignments[t.name] is String) t: assignments[t.name] as String,
      },
      wifiOnly: _cache.getOrDefault(aiWifiOnlyKey, true),
    );
  }

  Future<void> setMode(AiMode mode) async {
    await _cache.set(aiModeKey, mode.name);
    state = AiSettings(
      mode: mode,
      overrides: state.overrides,
      assignments: state.assignments,
      wifiOnly: state.wifiOnly,
    );
  }

  Future<void> setOverride(AiTask task, AiMode mode) async {
    final value = {...state.overrides, task: mode};
    await _cache.set(aiTaskOverridesKey, {
      for (final e in value.entries) e.key.name: e.value.name,
    });
    state = AiSettings(
      mode: state.mode,
      overrides: value,
      assignments: state.assignments,
      wifiOnly: state.wifiOnly,
    );
  }

  Future<void> assign(AiTask task, String? model) async {
    final value = {...state.assignments}..remove(task);
    if (model != null) value[task] = model;
    await _cache.set(aiModelAssignmentsKey, {
      for (final e in value.entries) e.key.name: e.value,
    });
    state = AiSettings(
      mode: state.mode,
      overrides: state.overrides,
      assignments: value,
      wifiOnly: state.wifiOnly,
    );
  }

  Future<void> setWifiOnly(bool value) async {
    await _cache.set(aiWifiOnlyKey, value);
    state = AiSettings(
      mode: state.mode,
      overrides: state.overrides,
      assignments: state.assignments,
      wifiOnly: value,
    );
  }
}
