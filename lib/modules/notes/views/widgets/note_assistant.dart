import 'package:flutter/material.dart';

import 'note_ai_widgets.dart';

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
import 'package:sync_wise/sync_wise.dart' show SyncDeviceRole;

enum _NoteTool {
  template,
  summary,
  writing,
  metadata,
  image,
  scan,
  background,
  presentation;

  NoteAiTool get visual => NoteAiTool.values.byName(name);
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
    pageBuilder: (context, _, _) => builder(context),
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
  });
  final String? noteId;
  final bool draft, available;
  final ScrollController scrollController;
  final ValueChanged<_NoteTool> onOpen;

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
    final paper = noteAiPaper(context);
    final narrow =
        MediaQuery.sizeOf(context).width < 350 ||
        MediaQuery.textScalerOf(context).scale(14) > 20;
    Widget card(_NoteTool tool, {bool fullWidth = false}) => NoteAiToolCard(
      key: ValueKey('note-assistant-${tool.name}'),
      tool: tool.visual,
      horizontal: fullWidth || draft || narrow,
      onTap: enabled(tool) ? () => onOpen(tool) : null,
    );
    List<Widget> group(String label, List<_NoteTool> choices) {
      final visible = choices.where(tools.contains).toList();
      if (visible.isEmpty) return [];
      return [
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 10),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: .3,
            ),
          ),
        ),
        for (var i = 0; i < visible.length; i += draft || narrow ? 1 : 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: draft || narrow || i + 1 == visible.length
                ? card(visible[i], fullWidth: true)
                : IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: card(visible[i])),
                        const SizedBox(width: 10),
                        Expanded(
                          child: i + 1 < visible.length
                              ? card(visible[i + 1])
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
          ),
      ];
    }

    return Material(
      color: paper,
      child: ListView(
        key: const ValueKey('note-assistant-actions'),
        controller: scrollController,
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          if (!canUse && !draft) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer.withValues(
                  alpha: .5,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.save_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Save your note and close the editor to use these tools.',
                      key: const ValueKey('note-assistant-save-first'),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (draft)
            ...group('Start', _NoteTool.draft)
          else ...[
            ...group('Edit', [
              _NoteTool.writing,
              _NoteTool.summary,
              _NoteTool.metadata,
            ]),
            ...group('Add', [_NoteTool.scan, _NoteTool.image]),
            ...group('Appearance', [
              _NoteTool.presentation,
              _NoteTool.background,
            ]),
          ],
        ],
      ),
    );
  }
}
