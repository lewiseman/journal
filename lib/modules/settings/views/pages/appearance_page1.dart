import 'package:flutter/material.dart';

/// The current values chosen on the Appearance page.
/// Use [AppearancePage1.onChanged] to save/apply them in your app.
class AppearanceValues {
  const AppearanceValues({
    required this.themeMode,
    required this.accentColor,
    required this.journalFont,
    required this.textScale,
  });

  final ThemeMode themeMode;
  final Color accentColor;
  final String journalFont;
  final double textScale;
}

class AppearancePage1 extends StatefulWidget {
  const AppearancePage1({
    super.key,
    this.lightThemeImage = 'assets/images/theme_light.png',
    this.darkThemeImage = 'assets/images/theme_dark.png',
    this.systemThemeImage = 'assets/images/theme_system.png',
    this.availableFonts = const [
      'Poppins',
      'Inter',
      'Roboto',
      'Nunito',
      'Manrope',
      'Outfit',
      'Lora',
      'Merriweather',
      'Playfair Display',
    ],
    this.initialThemeMode = ThemeMode.light,
    this.initialAccentColor = const Color(0xFF20217C),
    this.initialJournalFont = 'Poppins',
    this.initialTextSizeStep = 2,
    this.onChanged,
  });

  /// Replace these with the theme preview images already in your project.
  final String lightThemeImage;
  final String darkThemeImage;
  final String systemThemeImage;

  /// The families here should be available in your app's font configuration.
  final List<String> availableFonts;

  final ThemeMode initialThemeMode;
  final Color initialAccentColor;
  final String initialJournalFont;

  /// From 0 (smallest) to 4 (largest); 2 = Default.
  final int initialTextSizeStep;

  /// Fires immediately whenever a setting changes.
  final ValueChanged<AppearanceValues>? onChanged;

  @override
  State<AppearancePage1> createState() => _AppearancePage1State();
}

class _AppearancePage1State extends State<AppearancePage1> {
  static const _accentOptions = <_AccentOption>[
    _AccentOption('Indigo', Color(0xFF20217C)),
    _AccentOption('Teal', Color(0xFF078B82)),
    _AccentOption('Walnut', Color(0xFF946B5B)),
    _AccentOption('Olive', Color(0xFF6A7D4B)),
    _AccentOption('Clay', Color(0xFFC3644F)),
    _AccentOption('Plum', Color(0xFF865477)),
  ];

  static const _textScales = <double>[0.84, 0.92, 1.0, 1.10, 1.20];
  static const _sizeNames = <String>[
    'Smallest',
    'Smaller',
    'Default',
    'Larger',
    'Largest',
  ];

  late ThemeMode _themeMode;
  late int _accentIndex;
  late String _journalFont;
  late int _textSizeStep;

  Color get _accent => _accentOptions[_accentIndex].color;
  double get _textScale => _textScales[_textSizeStep];

  @override
  void initState() {
    super.initState();
    _themeMode = widget.initialThemeMode;
    _journalFont = widget.initialJournalFont;
    _textSizeStep = widget.initialTextSizeStep.clamp(0, 4).toInt();
    final matchingIndex = _accentOptions.indexWhere(
      (option) => option.color == widget.initialAccentColor,
    );
    _accentIndex = matchingIndex == -1 ? 0 : matchingIndex;
  }

  void _notifyChanged() {
    widget.onChanged?.call(
      AppearanceValues(
        themeMode: _themeMode,
        accentColor: _accent,
        journalFont: _journalFont,
        textScale: _textScale,
      ),
    );
  }

  void _changeTheme(ThemeMode mode) {
    setState(() => _themeMode = mode);
    _notifyChanged();
  }

  void _changeAccent(int index) {
    setState(() => _accentIndex = index);
    _notifyChanged();
  }

  void _changeSize(double step) {
    setState(() => _textSizeStep = step.round().clamp(0, 4).toInt());
    _notifyChanged();
  }

  Future<void> _openFontPicker(_AppearanceColors colors) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: 0.78,
          child: _FontPickerSheet(
            colors: colors,
            accent: _accent,
            fonts: widget.availableFonts,
            selectedFont: _journalFont,
            onSelected: (font) {
              setState(() => _journalFont = font);
              _notifyChanged();
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = switch (_themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system =>
        MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };
    final colors = _AppearanceColors(isDark);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        toolbarHeight: 74,
        backgroundColor: colors.background,
        foregroundColor: colors.ink,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        leadingWidth: 64,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 22),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        titleSpacing: 4,
        title: Text(
          'Appearance',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.7,
            color: colors.ink,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Text(
            'PREVIEW',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.6,
              color: colors.muted,
            ),
          ),
          const SizedBox(height: 10),
          _buildJournalPreview(colors),
          _sectionDivider(colors),
          _sectionTitle('Theme', colors),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildThemeOption(
                  colors: colors,
                  title: 'Light',
                  mode: ThemeMode.light,
                  image: widget.lightThemeImage,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildThemeOption(
                  colors: colors,
                  title: 'Dark',
                  mode: ThemeMode.dark,
                  image: widget.darkThemeImage,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildThemeOption(
                  colors: colors,
                  title: 'System',
                  mode: ThemeMode.system,
                  image: widget.systemThemeImage,
                ),
              ),
            ],
          ),
          _sectionDivider(colors),
          _sectionTitle('Accent color', colors),
          const SizedBox(height: 14),
          _buildAccentOptions(colors),
          const SizedBox(height: 17),
          Text(
            '${_accentOptions[_accentIndex].name}.',
            style: TextStyle(color: colors.muted, fontSize: 14),
          ),
          _sectionDivider(colors),
          _sectionTitle('Typography', colors),
          const SizedBox(height: 12),
          _buildFontButton(colors),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Text size',
                style: TextStyle(color: colors.ink, fontSize: 16),
              ),
              Text(
                _sizeNames[_textSizeStep],
                style: TextStyle(color: colors.muted, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 7),
          _buildTextSizeSlider(colors),
          const SizedBox(height: 12),
          Divider(color: colors.border, thickness: 1, height: 1),
          const SizedBox(height: 14),
          Text(
            'Changes apply instantly.',
            style: TextStyle(color: colors.muted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, _AppearanceColors colors) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.35,
        color: colors.ink,
      ),
    );
  }

  Widget _sectionDivider(_AppearanceColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Divider(color: colors.border, thickness: 1, height: 1),
    );
  }

  Widget _buildJournalPreview(_AppearanceColors colors) {
    final today = DateTime.now();
    final dateText = _formatPreviewDate(today);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: colors.dark ? 0.12 : 0.035),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            bottom: 0,
            child: Container(width: 4, color: _accent),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateText,
                  style: TextStyle(
                    color: colors.muted,
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'A little space for your thoughts.',
                  style: TextStyle(
                    fontFamily: _journalFont,
                    fontSize: 20 * _textScale,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.55,
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  'I’m enjoying a quiet morning with a cup of coffee '
                  'and a good book. Grateful for these small moments.',
                  style: TextStyle(
                    fontFamily: _journalFont,
                    fontSize: 15.5 * _textScale,
                    height: 1.58,
                    color: colors.body,
                  ),
                ),
                const SizedBox(height: 13),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: colors.dark ? 0.24 : 0.10),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.sentiment_satisfied_alt_outlined,
                        color: colors.dark ? colors.ink : _accent,
                        size: 18,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        'Calm',
                        style: TextStyle(
                          color: colors.dark ? colors.ink : _accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOption({
    required _AppearanceColors colors,
    required String title,
    required ThemeMode mode,
    required String image,
  }) {
    final selected = _themeMode == mode;

    return GestureDetector(
      onTap: () => _changeTheme(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 146,
        decoration: BoxDecoration(
          color: selected
              ? _accent.withValues(alpha: colors.dark ? 0.16 : 0.045)
              : colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _accent : colors.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                const SizedBox(height: 18),
                SizedBox(
                  height: 89,
                  width: double.infinity,
                  child: Image.asset(
                    image,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Center(
                      child: Icon(
                        Icons.image_outlined,
                        size: 42,
                        color: colors.muted.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 11),
                Text(title, style: TextStyle(color: colors.ink, fontSize: 14)),
              ],
            ),
            if (selected)
              Positioned(
                top: 7,
                right: 7,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: _accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.surface, width: 1),
                  ),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 15),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccentOptions(_AppearanceColors colors) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth >= 336
            ? constraints.maxWidth / _accentOptions.length
            : 56.0;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(_accentOptions.length, (index) {
              final option = _accentOptions[index];
              final isSelected = index == _accentIndex;

              return SizedBox(
                width: itemWidth,
                child: GestureDetector(
                  onTap: () => _changeAccent(index),
                  child: Column(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? option.color : Colors.transparent,
                            width: 1.4,
                          ),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: option.color,
                            shape: BoxShape.circle,
                          ),
                          child: isSelected
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 24,
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        option.name,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _buildFontButton(_AppearanceColors colors) {
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openFontPicker(colors),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                height: 48,
                width: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.subtleSurface,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  'Aa',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w600,
                    color: colors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Journal font',
                      style: TextStyle(color: colors.ink, fontSize: 16),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _journalFont,
                      style: TextStyle(color: colors.muted, fontSize: 14),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.muted, size: 26),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextSizeSlider(_AppearanceColors colors) {
    return Row(
      children: [
        Text('A', style: TextStyle(fontSize: 14, color: colors.ink)),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _accent,
              inactiveTrackColor: colors.sliderTrack,
              thumbColor: _accent,
              overlayColor: _accent.withValues(alpha: 0.10),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 17),
              activeTickMarkColor: _accent.withValues(alpha: 0.6),
              inactiveTickMarkColor: colors.muted.withValues(alpha: 0.4),
            ),
            child: Slider(
              value: _textSizeStep.toDouble(),
              min: 0,
              max: 4,
              divisions: 4,
              onChanged: _changeSize,
            ),
          ),
        ),
        Text('A', style: TextStyle(fontSize: 25, color: colors.ink)),
      ],
    );
  }
}

class _FontPickerSheet extends StatefulWidget {
  const _FontPickerSheet({
    required this.colors,
    required this.accent,
    required this.fonts,
    required this.selectedFont,
    required this.onSelected,
  });

  final _AppearanceColors colors;
  final Color accent;
  final List<String> fonts;
  final String selectedFont;
  final ValueChanged<String> onSelected;

  @override
  State<_FontPickerSheet> createState() => _FontPickerSheetState();
}

class _FontPickerSheetState extends State<_FontPickerSheet> {
  String _query = '';
  late String _selectedFont;

  @override
  void initState() {
    super.initState();
    _selectedFont = widget.selectedFont;
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final matches = widget.fonts
        .where((font) => font.toLowerCase().contains(_query.trim().toLowerCase()))
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 11),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: colors.border,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Journal font',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: colors.ink,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Done', style: TextStyle(color: widget.accent)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              style: TextStyle(color: colors.ink),
              decoration: InputDecoration(
                hintText: 'Search fonts',
                hintStyle: TextStyle(color: colors.muted),
                prefixIcon: Icon(Icons.search_rounded, color: colors.muted),
                filled: true,
                fillColor: colors.subtleSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Only this single sample renders in the selected font.
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PREVIEW · $_selectedFont',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1,
                    color: colors.muted,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'A little space for your thoughts.',
                  style: TextStyle(
                    fontFamily: _selectedFont,
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Every day has a story worth keeping.',
                  style: TextStyle(
                    fontFamily: _selectedFont,
                    fontSize: 15,
                    color: colors.body,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 13),
          Expanded(
            child: matches.isEmpty
                ? Center(
                    child: Text(
                      'No fonts found',
                      style: TextStyle(color: colors.muted),
                    ),
                  )
                : ListView.separated(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: matches.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      indent: 20,
                      endIndent: 20,
                      color: colors.border,
                    ),
                    itemBuilder: (context, index) {
                      final font = matches[index];
                      final selected = font == _selectedFont;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                        title: Text(
                          font,
                          style: TextStyle(fontSize: 16, color: colors.ink),
                        ),
                        trailing: selected
                            ? Icon(Icons.check_rounded, color: widget.accent)
                            : null,
                        onTap: () {
                          setState(() => _selectedFont = font);
                          widget.onSelected(font);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AccentOption {
  const _AccentOption(this.name, this.color);

  final String name;
  final Color color;
}

class _AppearanceColors {
  const _AppearanceColors(this.dark);

  final bool dark;

  Color get background => dark ? const Color(0xFF101424) : const Color(0xFFFFFEFD);
  Color get surface => dark ? const Color(0xFF191E30) : const Color(0xFFFFFEFD);
  Color get subtleSurface =>
      dark ? const Color(0xFF252A3E) : const Color(0xFFF1F2FA);
  Color get ink => dark ? const Color(0xFFF4F4FA) : const Color(0xFF12193D);
  Color get body => dark ? const Color(0xFFD6D8E6) : const Color(0xFF333C5C);
  Color get muted => dark ? const Color(0xFFA2AAC3) : const Color(0xFF707A98);
  Color get border => dark ? const Color(0xFF33384C) : const Color(0xFFE5E5EB);
  Color get sliderTrack => dark ? const Color(0xFF42475A) : const Color(0xFFD4D7E3);
}

String _formatPreviewDate(DateTime date) {
  const weekdays = [
    'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY',
    'FRIDAY', 'SATURDAY', 'SUNDAY',
  ];
  const months = [
    'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
    'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER',
  ];
  return '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]}';
}
