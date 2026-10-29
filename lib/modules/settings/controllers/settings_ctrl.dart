import 'package:journal/common.dart';
import 'package:journal/config/diary_typography.dart';

final settingsController = NotifierProvider<SettingsNotifier, LocalSettings>(
  SettingsNotifier.new,
);

class SettingsNotifier extends Notifier<LocalSettings> {
  final _diaryFontRequests = <DiaryFontRole, int>{};
  @override
  LocalSettings build() =>
      LocalSettings.fromMap(CacheStorage.instance.get(localSettingsKey));

  Future<void> setThemeMode(ThemeMode mode) =>
      _save((settings) => settings.copyWith(themeMode: mode));

  Future<void> setAccent(AppAccent accent) =>
      _save((settings) => settings.copyWith(accent: accent));

  Future<void> setAnimationsEnabled(bool enabled) =>
      _save((settings) => settings.copyWith(animationsEnabled: enabled));

  Future<void> setFontFamily(String family) async {
    if (!LocalSettings.supportsFont(family)) {
      throw ArgumentError.value(family, 'family', 'Unsupported font family');
    }

    await ref
        .read(fontThemeLoaderProvider)(family)
        .timeout(AppThemeConfig.fontLoadTimeout);
    if (!ref.mounted) return;
    await _save((settings) => settings.copyWith(fontFamily: family));
  }

  Future<void> setDiaryTitleFontFamily(String family) =>
      _setDiaryFont(family, DiaryFontRole.title);

  Future<void> setDiaryBodyFontFamily(String family) =>
      _setDiaryFont(family, DiaryFontRole.body);

  Future<void> _setDiaryFont(String family, DiaryFontRole role) async {
    if (!LocalSettings.supportsFont(family)) {
      throw ArgumentError.value(family, 'family', 'Unsupported font family');
    }
    final request = (_diaryFontRequests[role] ?? 0) + 1;
    _diaryFontRequests[role] = request;
    await ref
        .read(diaryFontLoaderProvider)(family, role)
        .timeout(AppThemeConfig.fontLoadTimeout);
    if (!ref.mounted || _diaryFontRequests[role] != request) return;
    await _save(
      (settings) => role == DiaryFontRole.title
          ? settings.copyWith(diaryTitleFontFamily: family)
          : settings.copyWith(diaryBodyFontFamily: family),
    );
  }

  Future<void> _save(LocalSettings Function(LocalSettings) update) async {
    if (!ref.mounted) return;
    final next = update(state);
    if (next.fontFamily == state.fontFamily &&
        next.diaryTitleFontFamily == state.diaryTitleFontFamily &&
        next.diaryBodyFontFamily == state.diaryBodyFontFamily &&
        next.themeMode == state.themeMode &&
        next.animationsEnabled == state.animationsEnabled &&
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
