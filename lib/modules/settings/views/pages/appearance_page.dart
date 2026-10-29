import 'package:journal/common.dart';
import 'package:journal/config/diary_typography.dart';
import 'package:journal/modules/diary/models/diary_ai_conversation.dart';
import 'package:journal/modules/diary/views/widgets/diary_notebook_entry.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_material.dart';

class AppearancePage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          DiaryTypographyScope(
            value:
                ref.watch(diaryTypographyProvider).value ??
                DiaryTypography.of(context),
            child: const _DiaryAppearancePreview(),
          ),
          SizedBox(height: 24),
          _sectionTitle('Typography'),
          const SizedBox(height: 12),
          _buildFontButton(
            context,
            localSettings.fontFamily,
            label: 'Journal font',
            onSelected: ref.read(settingsController.notifier).setFontFamily,
          ),
          const SizedBox(height: 10),
          _buildFontButton(
            context,
            localSettings.diaryTitleFontFamily,
            label: 'Diary title font',
            onSelected: ref
                .read(settingsController.notifier)
                .setDiaryTitleFontFamily,
          ),
          const SizedBox(height: 10),
          _buildFontButton(
            context,
            localSettings.diaryBodyFontFamily,
            label: 'Diary body font',
            onSelected: ref
                .read(settingsController.notifier)
                .setDiaryBodyFontFamily,
          ),
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
          _sectionDivider(),
          _sectionTitle('Motion'),
          const SizedBox(height: 12),
          const _AnimationsToggle(),
        ],
      ),
    );
  }

  Widget _buildFontButton(
    BuildContext context,
    String font, {
    required String label,
    required Future<void> Function(String) onSelected,
  }) {
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
                  onSelected: onSelected,
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
                    Text(label, style: TextStyle(fontSize: 16)),
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
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        padding: const EdgeInsets.only(bottom: 14),
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
}

class _AnimationsToggle extends ConsumerStatefulWidget {
  const _AnimationsToggle();

  @override
  ConsumerState<_AnimationsToggle> createState() => _AnimationsToggleState();
}

class _AnimationsToggleState extends ConsumerState<_AnimationsToggle> {
  bool _saving = false;
  String? _error;

  Future<void> _change(bool enabled) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(settingsController.notifier).setAnimationsEnabled(enabled);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not save animation preference. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Material(
    color: context.colors.surfaceContainer,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: context.borderColor1),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          key: const ValueKey('animations-toggle'),
          title: const Text('Animations'),
          subtitle: const Text('Turn off to reduce motion across the app.'),
          value: ref.watch(
            settingsController.select((settings) => settings.animationsEnabled),
          ),
          onChanged: _saving ? null : _change,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              _error!,
              key: const ValueKey('animations-save-error'),
              style: TextStyle(color: context.colors.error),
            ),
          ),
      ],
    ),
  );
}

class _DiaryAppearancePreview extends StatelessWidget {
  const _DiaryAppearancePreview();

  static final _date = DateTime(2026, 10, 28);
  static final _entry = DiaryItem(
    itemUuid: 'appearance-preview',
    createdAt: _date,
    updatedAt: _date,
    content: 'Coffee by the window, and nowhere to rush. I want to remember the small things.',
    aiConversation: DiaryAiConversation(
      createdAt: _date,
      turns: const [
        {'speaker': 'user', 'text': 'A quiet morning.'},
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final fonts = DiaryTypography.of(context);
    return IgnorePointer(
      child: CustomPaint(
        key: const ValueKey('diary-appearance-preview'),
        painter: DiaryPaperPainter(
          shape: DiaryPaperShape.forDate(_date),
          paper: context.colors.surface,
          ink: context.colors.onSurface,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(25, 23, 25, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A PAGE FROM YOUR DIARY',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.3,
                  height: 1.5,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'A little room to breathe.',
                style: fonts.title.copyWith(color: context.colors.onSurface),
              ),
              const SizedBox(height: 9),
              Text(
                '😌 Calm',
                style: TextStyle(
                  fontSize: 12,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 21),
              DiaryNotebookEntry(item: _entry),
            ],
          ),
        ),
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
  final Future<void> Function(String) onSelected;

  @override
  State<_FontPickerSheet> createState() => _FontPickerSheetState();
}

class _FontPickerSheetState extends State<_FontPickerSheet> {
  String _query = '';
  late String _selectedFont;
  String? _loadingFont;
  String? _fontError;

  Future<void> _select(String font) async {
    setState(() {
      _loadingFont = font;
      _fontError = null;
    });
    try {
      await widget.onSelected(font);
      if (mounted) setState(() => _selectedFont = font);
    } catch (_) {
      if (mounted) {
        setState(() => _fontError = 'This font couldn’t be loaded. Try again.');
      }
    } finally {
      if (mounted) setState(() => _loadingFont = null);
    }
  }

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

            if (_fontError != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _fontError!,
                    key: const ValueKey('font-load-error'),
                    style: TextStyle(color: colors.error),
                  ),
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
                          trailing: _loadingFont == font
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : selected
                              ? Icon(Icons.check_rounded, color: colors.primary)
                              : null,
                          onTap: _loadingFont != null
                              ? null
                              : () => _select(font),
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
