import 'package:journal/common.dart';

class AppearancePage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final localSettings = ref.watch(settingsController);
    final selectedTheme = localSettings.themeMode;
    return Scaffold(
      appBar: AppBar(
        title: Text('Appearance'),
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          _buildJournalPreview(context, colors),
          SizedBox(height: 24),
          _sectionTitle('Typography'),
          const SizedBox(height: 12),
          _buildFontButton(context, localSettings.fontFamily, ref),
          _sectionDivider(),
          _sectionTitle('Theme'),
          const SizedBox(height: 12),
          Row(
            spacing: 10,
            children: [
              for (final theme in ThemeMode.values)
                Expanded(
                  child: _buildThemeOption(
                    onTap: () => ref
                        .read(settingsController.notifier)
                        .setThemeMode(theme),
                    selected: selectedTheme == theme,
                    context: context,
                    title:
                        theme.name[0].toUpperCase() + theme.name.substring(1),
                    image: switch (theme) {
                      ThemeMode.light => 'assets/images/theme_light.png',
                      ThemeMode.dark => 'assets/images/theme_dark.png',
                      ThemeMode.system => 'assets/images/theme_system.png',
                    },
                  ),
                ),
            ],
          ),
          _sectionDivider(),
          _sectionTitle('Accent color'),
          const SizedBox(height: 14),
          _buildAccentOptions(context, localSettings.accent, ref),
        ],
      ),
    );
  }

  Widget _buildFontButton(BuildContext context, String font, WidgetRef ref) {
    return Material(
      color: context.colors.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.borderColor1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
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
                  fonts: LocalSettings.fontFamilies,
                  selectedFont: font,
                  onSelected: (font) {
                    ref.read(settingsController.notifier).setFontFamily(font);
                  },
                ),
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                height: 48,
                width: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  'Aa',
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Journal font', style: TextStyle(fontSize: 16)),
                    const SizedBox(height: 3),
                    Text(
                      font,
                      style: TextStyle(
                        color: context.colors.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: context.colors.onSurfaceVariant,
                size: 26,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccentOptions(
    BuildContext context,
    AppAccent selectedAccent,
    WidgetRef ref,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth >= 336
            ? constraints.maxWidth / AppAccent.values.length
            : 56.0;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(AppAccent.values.length, (index) {
              final option = AppAccent.values[index];
              final isSelected = option.label == selectedAccent.label;
              return SizedBox(
                width: itemWidth,
                child: GestureDetector(
                  onTap: () =>
                      ref.read(settingsController.notifier).setAccent(option),
                  child: Column(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? option.darkPrimary
                                : Colors.transparent,
                            width: 1.4,
                          ),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: option.seed,
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
                        option.name[0].toUpperCase() + option.name.substring(1),
                        maxLines: 1,
                        style: TextStyle(fontSize: 12),
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

  Widget _buildThemeOption({
    required String title,
    required bool selected,
    required BuildContext context,
    required String image,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 146,
        decoration: BoxDecoration(
          color: selected
              ? context.colors.surfaceContainerHighest
              : context.colors.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? context.colors.primary : context.borderColor1,
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
                    excludeFromSemantics: true,
                    errorBuilder: (context, error, stackTrace) => Center(
                      child: Icon(
                        Icons.image_outlined,
                        size: 42,
                        color: context.colors.onSurfaceVariant.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 11),
                Text(title, style: TextStyle(fontSize: 14)),
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
                    color: context.colors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: context.colors.surface, width: 1),
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 15,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectionDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Divider(thickness: 1, height: 1),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.35,
      ),
    );
  }

  Widget _buildJournalPreview(BuildContext context, ColorScheme colors) {
    final today = DateTime.now();

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: context.borderColor1),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: context.isDark ? 0.12 : 0.035,
            ),
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
            child: Container(width: 4, color: context.colors.primary),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 12, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  TimeHelper.format(
                    today,
                    pattern: TimeFormat.fullDate,
                  ).toUpperCase(),
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'A little space for your thoughts.',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                Text(
                  'I\'m enjoying a quiet morning with a cup of coffee '
                  'and a good book. Grateful for these small moments.',
                  style: TextStyle(),
                ),
                const SizedBox(height: 13),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.primary.withValues(
                      alpha: context.isDark ? 0.24 : 0.10,
                    ),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.sentiment_satisfied_alt_outlined,
                        color: context.isDark
                            ? context.colors.onSurface
                            : context.colors.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        'Calm',
                        style: TextStyle(
                          color: context.isDark
                              ? context.colors.onSurface
                              : context.colors.primary,
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
}

class _FontPickerSheet extends StatefulWidget {
  const _FontPickerSheet({
    required this.fonts,
    required this.selectedFont,
    required this.onSelected,
  });

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
    final colors = context.colors;
    final matches = widget.fonts
        .where(
          (font) => font.toLowerCase().contains(_query.trim().toLowerCase()),
        )
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            const SizedBox(height: 11),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: context.borderColor1,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        onChanged: (value) => setState(() => _query = value),
                        decoration: InputDecoration(
                          hintText: 'Search fonts',
                          hintStyle: TextStyle(color: colors.onSurfaceVariant),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: colors.onSurfaceVariant,
                          ),
                          filled: true,
                          fillColor: colors.surfaceContainerHighest,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Done',
                      style: TextStyle(color: colors.primary),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            Expanded(
              child: matches.isEmpty
                  ? Center(
                      child: Text(
                        'No fonts found',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    )
                  : ListView.separated(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: matches.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        indent: 20,
                        endIndent: 20,
                        color: context.borderColor1,
                      ),
                      itemBuilder: (context, index) {
                        final font = matches[index];
                        final selected = font == _selectedFont;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 24,
                          ),
                          title: Text(font, style: TextStyle(fontSize: 16)),
                          trailing: selected
                              ? Icon(Icons.check_rounded, color: colors.primary)
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
      ),
    );
  }
}
