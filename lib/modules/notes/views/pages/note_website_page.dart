import 'package:flutter/services.dart';
import 'package:journal/common.dart';
import 'package:journal/modules/presentation/note_website_view.dart';
import 'package:journal/modules/presentation/website_contract.dart';

/// Previews a note's generated website on a page of its own. A bar in the
/// note's paper colour names the note; the site sits beneath it like a sheet.
class NoteWebsitePage extends StatelessWidget {
  const NoteWebsitePage({
    super.key,
    required this.note,
    required this.colors,
    required this.onEdit,
    this.actions,
  });

  /// The bar's button style, for [actions] to match.
  static ButtonStyle buttonStyle(NoteColors colors) => IconButton.styleFrom(
    backgroundColor: colors.foreground.withValues(alpha: .08),
    foregroundColor: colors.foreground,
  );

  final NoteEntity note;
  final NoteColors colors;

  /// Opens the note's text in the editor. Null when this device cannot edit.
  final VoidCallback? onEdit;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final paper = colors.background;
    final ink = colors.foreground;
    final theme = Theme.of(context);
    final title = note.title.trim();
    // The text was edited after the site was made from it.
    final stale = websiteContentHash(note.content) != note.websiteSourceHash;
    final quiet = ink.withValues(alpha: .65);
    final tonal = buttonStyle(colors);
    return Scaffold(
      backgroundColor: paper,
      appBar: AppBar(
        backgroundColor: paper,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle:
            (ThemeData.estimateBrightnessForColor(paper) == Brightness.dark
                    ? SystemUiOverlayStyle.light
                    : SystemUiOverlayStyle.dark)
                .copyWith(statusBarColor: Colors.transparent),
        titleSpacing: 4,
        toolbarHeight: 64,
        actionsPadding: const EdgeInsets.only(right: 8),
        leading: Center(
          child: IconButton(
            tooltip: 'Back',
            onPressed: () => context.nav.maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            style: tonal,
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title.isEmpty ? 'Untitled note' : title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                color: ink,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (stale)
              Text(
                'Text changed since',
                key: const ValueKey('note-website-page-stale'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(color: quiet),
              ),
          ],
        ),
        actions: [
          if (onEdit != null)
            Tooltip(
              message: 'Edit note',
              child: FilledButton.icon(
                onPressed: onEdit,
                style: FilledButton.styleFrom(
                  backgroundColor: ink.withValues(alpha: .08),
                  foregroundColor: ink,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
            ),
          ?actions,
        ],
      ),
      body: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: ColoredBox(
          // Sites without a background of their own draw on the app surface.
          color: context.colors.surface,
          child: NoteWebsiteView(html: note.website),
        ),
      ),
    );
  }
}
