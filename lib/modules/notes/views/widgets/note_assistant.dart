import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/draft/note_draft_pages.dart';
import 'package:journal/modules/notes/images/note_background_page.dart';
import 'package:journal/modules/notes/images/note_image_page.dart';
import 'package:journal/modules/notes/images/note_scan_page.dart';
import 'package:journal/modules/notes/metadata/note_help_pages.dart';
import 'package:journal/modules/notes/models/note_attachment.dart';
import 'package:journal/modules/notes/summary/summary_page.dart';
import 'package:journal/modules/notes/transform/transform_page.dart';
import 'package:journal/modules/presentation/note_presentation_page.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/modules/settings/companion/companion_page.dart';
import 'package:sync_wise/sync_wise.dart' show SyncDeviceRole;

enum _NoteTool {
  template('Starting template', Icons.dashboard_customize_outlined),
  summary('Summarize', Icons.summarize_outlined),
  writing('Writing help', Icons.edit_note_rounded),
  metadata('Title & tag ideas', Icons.sell_outlined),
  image('Ask about an image', Icons.image_search_rounded),
  scan('Scan a page', Icons.document_scanner_outlined),
  background('Generate a background', Icons.wallpaper_outlined),
  recovery('Prior content / recovery', Icons.history_rounded),
  presentation('Presentation', Icons.auto_fix_high_outlined);

  const _NoteTool(this.label, this.icon);
  final String label;
  final IconData icon;

  /// What a new, unsaved note can use; results stay in the editor's draft.
  static const draft = [template, scan, background];
}

/// Keeps the existing tool routes and their typed results inside the sheet.
/// The menu is released while a tool is open, so its primary scrollable can
/// use the sheet's controller without a second scroll position attached.
class NoteAssistant extends StatefulWidget {
  const NoteAssistant({
    super.key,
    required this.noteId,
    required this.available,
    required this.scrollController,
    required this.onChanged,
    required this.onMetadataApplied,
    this.draftTitle,
    this.onDraftResult,
  });
  final String? noteId;
  final bool available;
  final ScrollController scrollController;
  final VoidCallback onChanged;
  final ValueChanged<NoteMetadataUndo> onMetadataApplied;

  /// Set for a new, unsaved note: its current title, and where results go.
  final String? draftTitle;
  final ValueChanged<NoteDraftResult>? onDraftResult;

  bool get draft => onDraftResult != null;

  @override
  State<NoteAssistant> createState() => _NoteAssistantState();
}

class _NoteAssistantState extends State<NoteAssistant> {
  final _navigator = GlobalKey<NavigatorState>();

  PageRoute<Object?> _route(
    WidgetBuilder builder, {
    bool maintainState = true,
  }) => PageRouteBuilder<Object?>(
    maintainState: maintainState,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (context, _, _) => PrimaryScrollController(
      controller: widget.scrollController,
      automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
      child: builder(context),
    ),
  );

  Future<void> _open(_NoteTool tool) async {
    if (widget.draft) return _openDraft(tool);
    final noteId = widget.noteId;
    if (!widget.available || noteId == null) return;
    FocusScope.of(context).unfocus();
    if (widget.scrollController.hasClients) {
      widget.scrollController.jumpTo(0);
    }
    final result = await _navigator.currentState!.push<Object?>(
      _route(
        (_) => switch (tool) {
          _NoteTool.summary => NoteSummaryPage(noteId: noteId),
          _NoteTool.writing => NoteTransformPage(noteId: noteId),
          _NoteTool.metadata => NoteMetadataPage(noteId: noteId),
          _NoteTool.image => NoteImagePage(noteId: noteId),
          _NoteTool.scan => NoteScanPage(noteId: noteId),
          _NoteTool.background => NoteBackgroundPage(noteId: noteId),
          _NoteTool.recovery => NoteRecoveryPage(noteId: noteId),
          _NoteTool.presentation => NotePresentationPage(noteId: noteId),
          _NoteTool.template => throw StateError('Only new notes use this.'),
        },
      ),
    );
    if (!mounted) return;
    if (result is NoteMetadataUndo) {
      // The editor owns Undo; reveal its snackbar after applying metadata.
      Navigator.of(context).pop();
      widget.onMetadataApplied(result);
    } else {
      widget.onChanged();
    }
  }

  Future<void> _openDraft(_NoteTool tool) async {
    if (!widget.available) return;
    FocusScope.of(context).unfocus();
    if (widget.scrollController.hasClients) {
      widget.scrollController.jumpTo(0);
    }
    final result = await _navigator.currentState!.push<Object?>(
      _route(
        (_) => switch (tool) {
          _NoteTool.template => NoteDraftTemplatePage(
            topic: widget.draftTitle ?? '',
          ),
          _NoteTool.scan => const NoteDraftScanPage(),
          _ => const NoteDraftBackgroundPage(),
        },
      ),
    );
    if (!mounted || result is! NoteDraftResult) return;
    // Close the sheet so the person sees the result land in their note.
    Navigator.of(context).pop();
    widget.onDraftResult!(result);
  }

  @override
  void dispose() {
    // Dismissing the whole sheet can bypass the active tool's return value.
    // Reload accepted edits after its route and scroll position are removed.
    final onChanged = widget.onChanged;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChanged());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NavigatorPopHandler<Object?>(
    onPopWithResult: (result) => _navigator.currentState!.pop(result),
    child: Navigator(
      key: _navigator,
      onGenerateRoute: (_) => _route(
        (_) => _NoteAssistantMenu(
          noteId: widget.noteId,
          draft: widget.draft,
          available: widget.available,
          scrollController: widget.scrollController,
          onOpen: _open,
          onClose: () => Navigator.of(context).maybePop(),
        ),
        maintainState: false,
      ),
    ),
  );
}

class _NoteAssistantMenu extends ConsumerWidget {
  const _NoteAssistantMenu({
    required this.noteId,
    required this.draft,
    required this.available,
    required this.scrollController,
    required this.onOpen,
    required this.onClose,
  });
  final String? noteId;
  final bool draft, available;
  final ScrollController scrollController;
  final ValueChanged<_NoteTool> onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final note = noteId == null
        ? null
        : ref
                  .watch(notesStreamProvider)
                  .value
                  ?.where((note) => note.uuid == noteId)
                  .firstOrNull ??
              ref.watch(notesRepositoryProvider).getNoteByUuid(noteId!);
    final canUse =
        available &&
        note != null &&
        !note.isDeleted &&
        !note.isPermanentlyDeleted;
    final canEdit =
        ref.watch(syncDeviceRoleProvider) != SyncDeviceRole.secondary;
    final hasText =
        note != null && '${note.title}${note.content}'.trim().isNotEmpty;
    final hasImage =
        note?.attachments.any(
          (entry) => NoteAttachment.tryFromMap(entry)?.isImage == true,
        ) ??
        false;
    final phase = ref.watch(
      companionControllerProvider.select((state) => state.phase),
    );
    final theme = Theme.of(context);
    final connected = phase == CompanionPhase.connected;
    final tools = draft
        ? _NoteTool.draft
        : [
            for (final tool in _NoteTool.values)
              if (tool != _NoteTool.template &&
                  (tool != _NoteTool.image || hasImage) &&
                  (canEdit ||
                      (tool != _NoteTool.scan && tool != _NoteTool.background)))
                tool,
          ];
    bool enabled(_NoteTool tool) => draft
        ? available && connected
        : canUse && (tool != _NoteTool.summary || hasText);
    return Material(
      color: theme.colorScheme.surface,
      child: ListView(
        key: const ValueKey('note-assistant-actions'),
        controller: scrollController,
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          24,
          4,
          24,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  draft ? 'New note' : 'Your note',
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          if (note != null)
            Text(
              note.title.trim().isEmpty ? 'Untitled note' : note.title,
              key: const ValueKey('note-assistant-title'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge,
            ),
          const SizedBox(height: 6),
          Text(companionPhaseLabel(phase), style: theme.textTheme.bodySmall),
          if (!canUse && !draft) ...[
            const SizedBox(height: 16),
            const Text(
              'Save your note and close the editor to use these tools.',
              key: ValueKey('note-assistant-save-first'),
            ),
          ],
          const SizedBox(height: 20),
          for (final tool in tools)
            ListTile(
              key: ValueKey('note-assistant-${tool.name}'),
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              leading: Icon(tool.icon),
              title: Text(tool.label),
              trailing: const Icon(Icons.chevron_right_rounded),
              enabled: enabled(tool),
              onTap: enabled(tool) ? () => onOpen(tool) : null,
            ),
        ],
      ),
    );
  }
}
