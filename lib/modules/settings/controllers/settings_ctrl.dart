import 'package:journal/common.dart';

final settingsController = NotifierProvider<SettingsNotifier, LocalSettings>(
  SettingsNotifier.new,
);

class SettingsNotifier extends Notifier<LocalSettings> {
  @override
  LocalSettings build() =>
      LocalSettings.fromMap(CacheStorage.instance.get(localSettingsKey));

  Future<void> setThemeMode(ThemeMode mode) =>
      _save((settings) => settings.copyWith(themeMode: mode));

  Future<void> setAccent(AppAccent accent) =>
      _save((settings) => settings.copyWith(accent: accent));

  Future<void> setFontFamily(String family) async {
    if (!LocalSettings.supportsFont(family)) {
      throw ArgumentError.value(family, 'family', 'Unsupported font family');
    }

    try {
      await ref
          .read(fontThemeLoaderProvider)(family)
          .timeout(AppThemeConfig.fontLoadTimeout);
      if (!ref.mounted) return;
      await _save((settings) => settings.copyWith(fontFamily: family));
    } catch (_) {}
  }

  Future<void> _save(LocalSettings Function(LocalSettings) update) async {
    if (!ref.mounted) return;
    final next = update(state);
    if (next.fontFamily == state.fontFamily &&
        next.themeMode == state.themeMode &&
        next.accent == state.accent) {
      return Future.value();
    }
    final cache = CacheStorage.instance;
    final data = {...?cache.get(localSettingsKey), ...next.toMap()};

    try {
      await cache.set(localSettingsKey, data);
    } catch (_) {
      throw 'Failed to save settings';
    }
    if (ref.mounted) state = next;
    return;
  }
}
