import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts_lite.dart';
import 'package:journal/common.dart';
import 'package:journal/utils/font_download_client.dart';
import 'package:journal/config/diary_typography.dart';
import 'package:journal/config/app_motion.dart';

extension JournalThemeContext on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;

  Color get borderColor1 => colors.primary.withValues(alpha: .16);

  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

extension JournalColorEffects on ColorScheme {
  /// A restrained ink shadow on paper, a luminous accent at night.
  Color glow(double opacity) => primary.withValues(
    alpha: opacity * (brightness == Brightness.dark ? 1 : .22),
  );
}

final appThemesProvider = Provider<JournalTheme>((ref) {
  final accent = ref.watch(settingsController.select((value) => value.accent));
  final themes = AppThemeConfig.themesFor(
    accent,
    fonts: ref.watch(fontThemesProvider).value,
  );
  final diary =
      ref.watch(diaryTypographyProvider).value ?? const DiaryTypography();
  ThemeData apply(ThemeData theme) => theme.copyWith(
    extensions: [
      ...theme.extensions.values.where((e) => e is! DiaryTypography),
      diary,
    ],
  );
  return (light: apply(themes.light), dark: apply(themes.dark));
});

typedef JournalTheme = ({ThemeData light, ThemeData dark});
typedef FontThemeLoader = Future<JournalTheme> Function(String fontFamily);

abstract final class AppThemeConfig {
  static const Color primaryColor = Color(0XFF161658);
  static const fontLoadTimeout = Duration(seconds: 10);

  static const lightSystemUiOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  static const darkSystemUiOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  static final lightTheme = _baseTheme(Brightness.light);
  static final darkTheme = _baseTheme(Brightness.dark);

  static final _accentThemes = <AppAccent, JournalTheme>{};
  static JournalTheme themesFor(AppAccent accent, {JournalTheme? fonts}) {
    final base = _accentThemes.putIfAbsent(
      accent,
      () => (
        light: _baseTheme(Brightness.light, accent),
        dark: _baseTheme(Brightness.dark, accent),
      ),
    );
    if (fonts == null) return base;
    ThemeData apply(ThemeData theme, ThemeData typography) => theme.copyWith(
      textTheme: typography.textTheme.apply(
        bodyColor: theme.colorScheme.onSurface,
        displayColor: theme.colorScheme.onSurface,
      ),
      primaryTextTheme: typography.primaryTextTheme.apply(
        bodyColor: theme.colorScheme.onPrimary,
        displayColor: theme.colorScheme.onPrimary,
      ),
    );
    return (
      light: apply(base.light, fonts.light),
      dark: apply(base.dark, fonts.dark),
    );
  }

  static ThemeData _baseTheme(
    Brightness brightness, [
    AppAccent accent = AppAccent.indigo,
  ]) {
    final dark = brightness == Brightness.dark;
    final generated = ColorScheme.fromSeed(
      seedColor: accent.seed,
      brightness: brightness,
    );
    final primary = dark ? accent.darkPrimary : accent.seed;
    final colors = generated.copyWith(
      primary: primary,
      primaryContainer: Color.alphaBlend(
        primary.withValues(alpha: dark ? .18 : .10),
        generated.surface,
      ),
      onPrimaryContainer: generated.onSurface,
    );
    return ThemeData(
      useMaterial3: true,
      platform: TargetPlatform.iOS,
      brightness: brightness,
      colorScheme: colors,
      pageTransitionsTheme: const AppPageTransitionsTheme(),
      appBarTheme: AppBarThemeData(
        systemOverlayStyle: brightness == Brightness.dark
            ? darkSystemUiOverlay
            : lightSystemUiOverlay,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        strokeWidth: 2.5,
      ),
    );
  }

  static final _loadedThemes = <String, JournalTheme>{};
  static Future<JournalTheme> loadFontThemes(String fontFamily) {
    GoogleFontsLite.config.httpClient ??= FontDownloadClient(
      timeout: fontLoadTimeout,
    );

    final fontTheme = () async {
      final cached = _loadedThemes[fontFamily];
      if (cached != null) return cached;

      ThemeData applyFont(ThemeData base) => base.copyWith(
        textTheme: _fontTextTheme(fontFamily, base.textTheme),
        primaryTextTheme: _fontTextTheme(fontFamily, base.primaryTextTheme),
      );

      final themes = (light: applyFont(lightTheme), dark: applyFont(darkTheme));
      await GoogleFontsLite.pendingFonts();
      _loadedThemes[fontFamily] = themes;
      return themes;
    }();

    return fontTheme;
  }

  static TextTheme _fontTextTheme(String family, TextTheme base) {
    TextStyle? apply(TextStyle? style) => style == null
        ? null
        : GoogleFontsLite.getFont(family, textStyle: style);
    return TextTheme(
      displayLarge: apply(base.displayLarge),
      displayMedium: apply(base.displayMedium),
      displaySmall: apply(base.displaySmall),
      headlineLarge: apply(base.headlineLarge),
      headlineMedium: apply(base.headlineMedium),
      headlineSmall: apply(base.headlineSmall),
      titleLarge: apply(base.titleLarge),
      titleMedium: apply(base.titleMedium),
      titleSmall: apply(base.titleSmall),
      bodyLarge: apply(base.bodyLarge),
      bodyMedium: apply(base.bodyMedium),
      bodySmall: apply(base.bodySmall),
      labelLarge: apply(base.labelLarge),
      labelMedium: apply(base.labelMedium),
      labelSmall: apply(base.labelSmall),
    );
  }
}

final fontThemeLoaderProvider = Provider<FontThemeLoader>(
  (ref) => AppThemeConfig.loadFontThemes,
);

final fontThemesProvider = FutureProvider<JournalTheme>((ref) {
  final family = ref.watch(
    settingsController.select((settings) => settings.fontFamily),
  );
  // The timed future stays failed even if the underlying load completes later.
  // Only an explicit retry or font selection can publish another theme.
  return ref
      .watch(fontThemeLoaderProvider)(family)
      .timeout(AppThemeConfig.fontLoadTimeout);
}, retry: (retryCount, error) => null);
