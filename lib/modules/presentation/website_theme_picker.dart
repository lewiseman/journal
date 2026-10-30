import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/models/note_entity.dart';

import 'website_contract.dart';
import 'website_render.dart';
import 'website_themes.dart';

const _accentColors = {
  'ink': Color(0xFF3B3F5C),
  'rose': Color(0xFFC2255C),
  'ocean': Color(0xFF1864AB),
  'forest': Color(0xFF2B8A3E),
  'sun': Color(0xFFD9480F),
  'plum': Color(0xFF862E9C),
};

/// A row of theme swatches. [auto] adds "Let it choose" as `auto`.
class WebsiteThemeSwatches extends StatelessWidget {
  const WebsiteThemeSwatches({
    super.key,
    required this.selected,
    required this.onSelected,
    this.auto = false,
  });
  final String selected;
  final ValueChanged<String> onSelected;
  final bool auto;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget chip(String id, String label, Widget swatch) => Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Semantics(
        selected: id == selected,
        button: true,
        label: '$label theme',
        child: InkWell(
          key: ValueKey('website-theme-$id'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => onSelected(id),
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 64,
                height: 64,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    width: 2,
                    color: id == selected
                        ? scheme.primary
                        : scheme.outlineVariant,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: swatch,
                ),
              ),
              const SizedBox(height: 4),
              Text(label, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
    // Not a ListView: the sheet's own list is the page's one scroll view.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (auto)
            chip(
              'auto',
              'Let it choose',
              ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: Icon(Icons.auto_awesome, color: scheme.primary),
              ),
            ),
          for (final theme in websiteThemes)
            chip(
              theme.id,
              theme.name,
              ColoredBox(
                color: Color(theme.swatch.$1),
                child: Align(
                  alignment: const Alignment(-.5, .3),
                  child: Text(
                    'Aa',
                    style: TextStyle(
                      color: Color(theme.swatch.$2),
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Re-draws [note]'s themed website in another look, without the model.
/// Hidden for freehand websites and read-only devices.
class WebsiteThemeButton extends ConsumerWidget {
  const WebsiteThemeButton({super.key, required this.note, this.style});
  final NoteEntity note;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = websiteSpecOf(note.website);
    if (spec == null) return const SizedBox.shrink();
    return IconButton(
      key: const ValueKey('website-theme-button'),
      tooltip: 'Change look',
      style: style,
      icon: const Icon(Icons.palette_outlined, size: 20),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => _ThemeSheet(note: note, spec: spec),
      ),
    );
  }
}

class _ThemeSheet extends ConsumerStatefulWidget {
  const _ThemeSheet({required this.note, required this.spec});
  final NoteEntity note;
  final WebsiteSpec spec;

  @override
  ConsumerState<_ThemeSheet> createState() => _ThemeSheetState();
}

class _ThemeSheetState extends ConsumerState<_ThemeSheet> {
  late var _spec = widget.spec;
  bool _saving = false;

  Future<void> _apply(WebsiteSpec spec) async {
    if (_saving) return;
    setState(() {
      _spec = spec;
      _saving = true;
    });
    try {
      final note = widget.note;
      final page = await sanitizeWebsiteBounded(
        renderWebsite(spec, title: note.title),
      );
      final current = ref
          .read(notesRepositoryProvider)
          .getNoteByUuid(note.uuid);
      ref
          .read(notesRepositoryProvider)
          .setWebsite(
            uuid: note.uuid,
            expectedVersion: current?.versionVectorJson ?? '',
            html: page,
            sourceHash: note.websiteSourceHash,
          );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not change the look.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Look', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            WebsiteThemeSwatches(
              selected: _spec.theme,
              onSelected: (id) => _apply(_spec.withStyle(theme: id)),
            ),
            const SizedBox(height: 16),
            Text('Accent', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              children: [
                for (final MapEntry(key: id, value: color)
                    in _accentColors.entries)
                  Semantics(
                    button: true,
                    selected: id == _spec.accent,
                    label: '$id accent',
                    child: InkWell(
                      key: ValueKey('website-accent-$id'),
                      customBorder: const CircleBorder(),
                      onTap: () => _apply(_spec.withStyle(accent: id)),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            width: 3,
                            color: id == _spec.accent
                                ? scheme.onSurface
                                : Colors.transparent,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
