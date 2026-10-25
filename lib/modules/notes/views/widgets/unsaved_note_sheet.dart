import 'package:flutter/material.dart';

import 'note_paper_surface.dart';

enum UnsavedNoteAction { save, discard }

class UnsavedNoteSheet extends StatelessWidget {
  const UnsavedNoteSheet({
    super.key,
    required this.isNewNote,
    required this.title,
    required this.paperColor,
    required this.ink,
  });

  final bool isNewNote;
  final String title;
  final Color paperColor;
  final Color ink;

  static Future<UnsavedNoteAction?> show(
    BuildContext context, {
    required bool isNewNote,
    required String title,
    required Color paperColor,
    required Color ink,
  }) => showModalBottomSheet<UnsavedNoteAction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    requestFocus: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    elevation: 0,
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
    ),
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => UnsavedNoteSheet(
      isNewNote: isNewNote,
      title: title,
      paperColor: paperColor,
      ink: ink,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final accent = isNewNote ? colors.primary : colors.tertiary;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(
                isNewNote ? 'Keep this thought?' : 'Save your changes?',
                style: text.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: -.8,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isNewNote
                  ? 'Give this note a place in your journal before you go.'
                  : 'Save your latest words, or go back to the last saved version.',
              style: text.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                children: [
                  Positioned.fill(child: NotePaperSurface(color: paperColor)),
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Icon(Icons.subject_rounded, color: ink, size: 22),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title.trim().isEmpty
                                    ? 'Untitled note'
                                    : title.trim(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: text.titleSmall?.copyWith(color: ink),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isNewNote ? 'Not saved yet' : 'Unsaved changes',
                                style: text.bodySmall?.copyWith(
                                  color: ink.withValues(alpha: .7),
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
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, UnsavedNoteAction.save),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: isNewNote
                    ? colors.onPrimary
                    : colors.onTertiary,
                minimumSize: const Size.fromHeight(54),
              ),
              icon: Icon(
                isNewNote ? Icons.bookmark_add_outlined : Icons.check_rounded,
                size: 20,
              ),
              label: Text(isNewNote ? 'Save note' : 'Save changes'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () =>
                  Navigator.pop(context, UnsavedNoteAction.discard),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.error,
                side: BorderSide(color: colors.error.withValues(alpha: .25)),
                minimumSize: const Size.fromHeight(52),
              ),
              child: Text(isNewNote ? 'Discard note' : 'Discard changes'),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: colors.onSurfaceVariant,
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Keep editing'),
            ),
          ],
        ),
      ),
    );
  }
}
