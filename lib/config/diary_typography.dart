import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts_lite.dart';
import 'package:journal/config/theme.dart';
import 'package:journal/modules/settings/controllers/settings_ctrl.dart';
import 'package:journal/utils/font_download_client.dart';

enum DiaryFontRole { title, body }

void registerDiaryFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final family in ['Caveat', 'Lora']) {
      yield LicenseEntryWithLineBreaks(
        [family],
        await rootBundle.loadString(
          'assets/fonts/${family.toLowerCase()}-OFL.txt',
        ),
      );
    }
  });
}

/// Resolved fonts only: drawing a diary page never starts a font download.
@immutable
class DiaryTypography extends ThemeExtension<DiaryTypography> {
  const DiaryTypography({
    this.title = const TextStyle(
      fontFamily: 'Caveat',
      fontWeight: FontWeight.w500,
      fontSize: 35,
      height: 1.16,
    ),
    this.body = const TextStyle(
      fontFamily: 'Lora',
      fontSize: 17,
      fontWeight: FontWeight.w400,
      height: 1.75,
    ),
  });

  final TextStyle title, body;

  static DiaryTypography of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DiaryTypographyScope>()
          ?.value ??
      Theme.of(context).extension<DiaryTypography>() ??
      const DiaryTypography();

  @override
  DiaryTypography copyWith({TextStyle? title, TextStyle? body}) =>
      DiaryTypography(title: title ?? this.title, body: body ?? this.body);

  // Font metrics change atomically, rather than interpolating during a theme
  // animation and invalidating the paper's textures on every frame.
  @override
  DiaryTypography lerp(covariant DiaryTypography? other, double t) =>
      t < .5 || other == null ? this : other;

  @override
  bool operator ==(Object other) =>
      other is DiaryTypography && title == other.title && body == other.body;

  @override
  int get hashCode => Object.hash(title, body);
}

/// Holds one typography snapshot across the live page and its paper faces.
class DiaryTypographyScope extends InheritedWidget {
  const DiaryTypographyScope({
    super.key,
    required this.value,
    required super.child,
  });
  final DiaryTypography value;

  @override
  bool updateShouldNotify(DiaryTypographyScope oldWidget) =>
      value != oldWidget.value;
}

typedef DiaryFontLoader = Future<TextStyle> Function(
  String family,
  DiaryFontRole role,
);

final _loadedFonts = <(String, DiaryFontRole), TextStyle>{};
final _loadingFonts = <(String, DiaryFontRole), Future<TextStyle>>{};

Future<TextStyle> _loadFont(String family, DiaryFontRole role) async {
  final base = role == DiaryFontRole.title
      ? const DiaryTypography().title
      : const DiaryTypography().body;
  // Both bundled families can be used for either role while offline.
  if (family == 'Caveat' || family == 'Lora') {
    return base.copyWith(
      fontFamily: family,
      fontWeight: family == 'Caveat' ? FontWeight.w500 : FontWeight.w400,
    );
  }
  final key = (family, role);
  if (_loadedFonts[key] case final cached?) return cached;
  if (_loadingFonts[key] case final pending?) return pending;
  GoogleFontsLite.config.httpClient ??= FontDownloadClient(
    timeout: AppThemeConfig.fontLoadTimeout,
  );
  final future = () async {
    final style = GoogleFontsLite.getFont(family, textStyle: base);
    await GoogleFontsLite.pendingFonts().timeout(
      AppThemeConfig.fontLoadTimeout,
    );
    _loadedFonts[key] = style;
    return style;
  }();
  _loadingFonts[key] = future;
  try {
    return await future;
  } finally {
    _loadingFonts.remove(key);
  }
}

final diaryFontLoaderProvider = Provider<DiaryFontLoader>((ref) => _loadFont);

final diaryTypographyProvider = FutureProvider<DiaryTypography>((ref) async {
  final families = ref.watch(
    settingsController.select(
      (s) => (s.diaryTitleFontFamily, s.diaryBodyFontFamily),
    ),
  );
  final load = ref.watch(diaryFontLoaderProvider);
  final styles = await Future.wait([
    load(families.$1, DiaryFontRole.title),
    load(families.$2, DiaryFontRole.body),
  ]).timeout(AppThemeConfig.fontLoadTimeout);
  return DiaryTypography(title: styles[0], body: styles[1]);
}, retry: (_, _) => null);
