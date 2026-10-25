import 'package:journal/common.dart';
import 'package:google_fonts/google_fonts_lite.dart';

class LocalSettings {
  const LocalSettings({
    this.fontFamily = defaultFontFamily,
    this.themeMode = ThemeMode.system,
    this.accent = AppAccent.indigo,
  });

  final String fontFamily;
  final ThemeMode themeMode;
  final AppAccent accent;

  static const defaultFontFamily = 'Poppins';
  static final fontFamilies = List<String>.unmodifiable(
    GoogleFontsLite.fontsMap.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
  );

  static bool supportsFont(String family) =>
      GoogleFontsLite.fontsMap.containsKey(family);

  factory LocalSettings.fromMap(Map<String, dynamic>? data) {
    final family = data?['font_family'];
    return LocalSettings(
      fontFamily: family is String && supportsFont(family)
          ? family
          : defaultFontFamily,
      themeMode: ThemeMode.values.firstWhere(
        (mode) => mode.name == data?['theme_mode'],
        orElse: () => ThemeMode.system,
      ),
      accent: AppAccent.fromName(data?['accent_color']),
    );
  }

  Map<String, dynamic> toMap() => {
    'font_family': fontFamily,
    'theme_mode': themeMode.name,
    'accent_color': accent.name,
  };

  LocalSettings copyWith({
    String? fontFamily,
    ThemeMode? themeMode,
    AppAccent? accent,
  }) => LocalSettings(
    fontFamily: fontFamily ?? this.fontFamily,
    themeMode: themeMode ?? this.themeMode,
    accent: accent ?? this.accent,
  );
}

enum AppAccent {
  indigo(
    'Indigo',
    'The original journal ink',
    Color(0xFF161658),
    Color(0xFFB9B7FF),
  ),
  teal('Teal', 'Calm coastal greens', Color(0xFF176B65), Color(0xFF80D5CC)),
  walnut(
    'Walnut',
    'Warm leather and coffee',
    Color(0xFF795548),
    Color(0xFFD8B798),
  ),
  olive('Olive', 'Soft, earthy greens', Color(0xFF59633B), Color(0xFFC0CB8F)),
  terracotta(
    'Terracotta',
    'Sun-warmed clay',
    Color(0xFFA04F38),
    Color(0xFFF2B09C),
  ),
  plum('Plum', 'A mellow, dusky purple', Color(0xFF754B70), Color(0xFFDCB0D2));

  const AppAccent(this.label, this.description, this.seed, this.darkPrimary);

  final String label;
  final String description;
  final Color seed;
  final Color darkPrimary;

  static AppAccent fromName(Object? name) =>
      values.firstWhere((accent) => accent.name == name, orElse: () => indigo);
}
