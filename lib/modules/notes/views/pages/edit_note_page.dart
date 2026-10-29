import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:journal/modules/voice/controllers/voice_store.dart';

import 'package:sync_wise/sync_wise.dart' show SyncDeviceRole;

import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:journal/common.dart';
import 'package:journal/modules/assistant/qvac_assistant_scope.dart';
import 'package:journal/modules/notes/controllers/note_attachment_service.dart';
import 'package:journal/modules/notes/draft/note_draft_ai.dart';
import 'package:journal/modules/notes/draft/note_draft_pages.dart';
import 'package:journal/modules/notes/images/note_scan.dart';
import 'package:journal/modules/notes/models/note_attachment.dart';
import 'package:journal/modules/notes/models/note_tag.dart';
import 'package:journal/modules/notes/views/widgets/edit_note_card_bg.dart';
import 'package:journal/modules/notes/views/widgets/edit_note_page_bg.dart';
import 'package:journal/modules/notes/views/widgets/note_art_picker.dart';
import 'package:journal/modules/notes/views/widgets/note_actions_menu.dart';
import 'package:journal/modules/notes/views/widgets/note_assistant.dart';
import 'package:journal/modules/notes/views/widgets/note_attachment_strip.dart';
import 'package:journal/modules/notes/views/widgets/note_image_provider.dart';
import 'package:journal/modules/notes/views/widgets/note_paint_timing.dart';
import 'package:journal/modules/notes/views/widgets/note_tag_picker.dart';
import 'package:journal/modules/notes/views/widgets/unsaved_note_sheet.dart';
import 'package:journal/modules/notes/metadata/note_help_pages.dart';
import 'package:journal/modules/notes/views/pages/note_website_page.dart';

class EditNotePage extends ConsumerStatefulWidget {
  const new({super.key, this.existingNote, this.starterTitle});
  final NoteEntity? existingNote;
  final String? starterTitle;

  @override
  ConsumerState<EditNotePage> createState() => _EditNotePageState();
}

class _EditNotePageState extends ConsumerState<EditNotePage> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  final _contentFocusNode = FocusNode(debugLabel: 'Note content');
  late final Duration _artworkDuration;
  late List<String> _tags;
  late List<Map<String, dynamic>> _attachmentPaths;
  late NoteEntity? _savedNote;
  late String _savedDraft;
  bool _exitSheetOpen = false;

  // Files QVAC made for this note before it was saved, and scan readings to
  // keep once it is. Unsaved, they are deleted when the editor closes.
  final _draftFiles = <String>{};
  final _pendingOriginals = <String, String>{};
  bool _pickingAttachments = false;
  late bool _isPreviewMode = widget.existingNote != null;
  // Randomize new notes while keeping saved notes repeatable across openings.
  late final _noteArtworkSeed = widget.existingNote == null
      ? DateTime.now().microsecondsSinceEpoch % 2147483646
      : widget.existingNote!.uuid.codeUnits.fold(
          0,
          (seed, unit) => (seed * 31 + unit) % 2147483646,
        );
  final _paperController = EditNoteCardController();
  late final _paperExpansion = ValueNotifier<double>(_isPreviewMode ? 0 : 1);
  late Map<String, dynamic> _background = widget.existingNote != null
      ? Map.of(widget.existingNote!.background)
      : NoteColors.randomPreset(_noteArtworkSeed).toBackground();

  // Capture values independently of the entity, which the repository can mutate.
  // Normalize artwork so applying the same background does not count as an edit.
  String get _draftSnapshot => jsonEncode({
    'title': _titleController.text,
    'content': _contentController.text,
    'tags': _tags,
    'attachments': _attachmentPaths,
    'background': {
      ..._background,
      ...NoteArtSelection.fromBackground(_background).toBackground(),
    },
  });

  bool get _hasUnsavedChanges => _draftSnapshot != _savedDraft;

  void _addCheckbox() {
    final content = _contentController.text;
    final separator = content.isEmpty || content.endsWith('\n') ? '' : '\n';
    final text = '$content$separator- [ ] ';
    _contentController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _contentFocusNode.requestFocus();
  }

  Future<void> _openVoice() async {
    if (_isPreviewMode || ModalRoute.of(context)?.isCurrent == false) return;
    if (_savedNote != null &&
        ref.read(syncDeviceRoleProvider) == SyncDeviceRole.secondary) {
      return;
    }
    FocusScope.of(context).unfocus();
    final before = _contentController.text;
    final transcript = await context.nav.push<String>(
      const VoiceSessionPage(
        mode: VoiceSessionMode.transcription,
        title: 'Voice note',
      ),
      transition: MediaQuery.disableAnimationsOf(context)
          ? NavTransition.none
          : NavTransition.fade,
    );
    if (!mounted ||
        transcript == null ||
        _isPreviewMode ||
        _contentController.text != before ||
        ref.read(accountResetProvider).blocksDataAccess) {
      return;
    }
    _contentController.text = before.isEmpty
        ? transcript
        : '$before\n$transcript';
    await VoiceStore().consumed('note');
  }

  Future<void> _pickAttachments() async {
    if (_pickingAttachments || _isPreviewMode) return;
    FocusScope.of(context).unfocus();
    final savedDraft = _savedDraft;
    setState(() => _pickingAttachments = true);
    try {
      final selection = await ref.read(noteAttachmentServiceProvider).pick();
      if (!mounted || _isPreviewMode || savedDraft != _savedDraft) return;
      final paths = {
        for (final entry in _attachmentPaths)
          if (NoteAttachment.tryFromMap(entry) case final attachment?)
            attachment.pathKey,
      };
      final added = [
        for (final attachment in selection.attachments)
          if (paths.add(attachment.pathKey)) attachment.toMap(),
      ];
      if (added.isNotEmpty) {
        setState(() => _attachmentPaths = [..._attachmentPaths, ...added]);
      }
      if (selection.skipped > 0) {
        _showActionError(
          'Some files could not be attached without a local path.',
        );
      }
    } catch (_) {
      if (!mounted || _isPreviewMode) return;
      _showActionError(
        'Could not open your files. Please try again.',
        onRetry: _pickAttachments,
      );
    } finally {
      if (mounted) setState(() => _pickingAttachments = false);
    }
  }

  void _removeAttachment(int index) {
    setState(() => _attachmentPaths = [..._attachmentPaths]..removeAt(index));
  }

  Future<void> _pickTags() async {
    final selection = await NoteTagPicker.show(context, currentTags: _tags);
    if (!mounted || selection == null) return;
    if (selection.length == _tags.length && selection.every(_tags.contains)) {
      return;
    }
    final previousTags = _tags;
    setState(() => _tags = selection);
    if (_isPreviewMode && !_save()) {
      setState(() => _tags = previousTags);
    }
  }

  Future<void> _pickBackground() async {
    final selection = await NoteArtPicker.pick(context, _background);
    if (!mounted || selection == null) return;
    final previousBackground = _background;
    setState(() => _background = {..._background, ...selection.toBackground()});
    // Apply from preview persists immediately; editing keeps the normal draft.
    if (_isPreviewMode && !_save()) {
      setState(() => _background = previousBackground);
    }
  }

  void _metadataApplied(NoteMetadataUndo undo) {
    if (!mounted) return;
    _reloadSaved(undo.noteId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Title and tags updated.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            try {
              ref
                  .read(notesRepositoryProvider)
                  .updateNoteMetadata(
                    uuid: undo.noteId,
                    expectedVersion: undo.version,
                    title: undo.title,
                    tags: undo.tags,
                  );
              _reloadSaved(undo.noteId);
            } catch (_) {
              _showActionError(
                'The note changed since then, so it was not undone.',
              );
            }
          },
        ),
      ),
    );
  }

  void _applyDraft(NoteDraftResult result) {
    if (!mounted || _savedNote != null) return;
    String append(String text) {
      final content = _contentController.text.trimRight();
      return content.isEmpty ? text : '$content\n\n$text';
    }

    setState(() {
      switch (result) {
        case DraftTemplateResult(:final template):
          if (_titleController.text.trim().isEmpty) {
            _titleController.text = template.title;
          }
          _contentController.text = append(template.body);
        case DraftScanResult(:final text, :final path, :final original):
          _contentController.text = append(text);
          _attachmentPaths = [
            ..._attachmentPaths,
            NoteAttachment.fromPath(path).toMap(),
          ];
          _pendingOriginals[path] = original;
          _draftFiles.add(path);
        case DraftBackgroundResult(:final image):
          _background = {
            ..._background,
            'image': image,
            'image_source': 'local',
          };
          _draftFiles.add(image);
      }
    });
  }

  /// Keeps each scan's unedited reading beside the page once the note exists.
  void _keepScanOriginals(NoteEntity note) {
    if (_pendingOriginals.isEmpty) return;
    final store = ref.read(noteScanStoreProvider);
    final attached = {
      for (final entry in note.attachments)
        if (NoteAttachment.tryFromMap(entry) case final attachment?)
          attachment.path,
    };
    for (final MapEntry(key: path, value: text) in _pendingOriginals.entries) {
      if (!attached.contains(path)) continue;
      unawaited(
        store.writeOriginal(path, note.uuid, text).catchError((Object _) {}),
      );
    }
    _pendingOriginals.clear();
  }

  void _reloadSaved(String uuid) {
    if (!mounted || _hasUnsavedChanges) return;
    final updated = ref.read(notesRepositoryProvider).getNoteByUuid(uuid);
    if (updated == null || updated.isDeleted || updated.isPermanentlyDeleted) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _savedNote = updated;
      _titleController.text = updated.title;
      _contentController.text = updated.content;
      _tags = List.of(updated.tags);
      _attachmentPaths = List.of(updated.attachments);
      _background = Map.of(updated.background);
      _savedDraft = _draftSnapshot;
    });
  }

  void _togglePin() {
    final note = _savedNote;
    if (note == null) return;
    final repo = ref.read(notesRepositoryProvider);
    try {
      repo.pinNote(note.uuid);
      final updated = repo.getNoteByUuid(note.uuid);
      if (updated != null) setState(() => _savedNote = updated);
    } catch (_) {
      _showActionError('Could not update your note. Please try again.');
    }
  }

  void _deleteNote() {
    final note = _savedNote;
    if (note == null) return;
    try {
      ref.read(notesRepositoryProvider).deleteNote(note.uuid);
    } catch (_) {
      _showActionError('Could not delete your note. Please try again.');
      return;
    }
    Navigator.pop(context);
  }

  void _showActionError(String message, {VoidCallback? onRetry}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: onRetry == null
            ? null
            : SnackBarAction(label: 'Retry', onPressed: onRetry),
      ),
    );
  }

  void _restorePreview() {
    FocusScope.of(context).unfocus();
    if (!_isPreviewMode) setState(() => _isPreviewMode = true);
    _paperController.collapse();
    // A website preview replaces the paper before it can report folding.
    if (_savedNote?.website.isNotEmpty == true) _paperExpansion.value = 0;
  }

  void _finishEditing() {
    if (_savedNote == null) {
      Navigator.pop(context);
    } else {
      _restorePreview();
    }
  }

  void _discardChanges() {
    final draft = jsonDecode(_savedDraft) as Map<String, dynamic>;
    _titleController.text = draft['title'] as String;
    _contentController.text = draft['content'] as String;
    _tags = List<String>.from(draft['tags'] as List);
    _attachmentPaths = (draft['attachments'] as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    setState(() {
      _background = Map<String, dynamic>.from(draft['background'] as Map);
    });
  }

  Future<void> _requestExit() async {
    if (_exitSheetOpen) return;
    if (_isPreviewMode) {
      _restorePreview();
      return;
    }
    if (!_hasUnsavedChanges) {
      _finishEditing();
      return;
    }

    _exitSheetOpen = true;
    FocusScope.of(context).unfocus();
    try {
      final colors = NoteColors.fromBackground(context.colors, _background);
      final action = await UnsavedNoteSheet.show(
        context,
        isNewNote: _savedNote == null,
        title: _titleController.text,
        paperColor: colors.background,
        ink: colors.foreground,
      );
      if (!mounted) return;
      switch (action) {
        case UnsavedNoteAction.save:
          _save();
        case UnsavedNoteAction.discard:
          if (_savedNote != null) _discardChanges();
          _finishEditing();
        case null:
          break;
      }
    } finally {
      _exitSheetOpen = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _artworkDuration = widget.existingNote == null
        ? NotePaintTiming.duration
        : NotePaintTiming.durationForContent(widget.existingNote!.content);
    _titleController = TextEditingController(
      text: widget.existingNote?.title ?? widget.starterTitle ?? '',
    );
    _contentController = TextEditingController(
      text: widget.existingNote?.content ?? '',
    );
    _tags = List.from(widget.existingNote?.tags ?? []);
    _attachmentPaths = List.from(widget.existingNote?.attachments ?? []);
    _savedNote = widget.existingNote;
    _savedDraft = _draftSnapshot;
  }

  @override
  void dispose() {
    final saved = _savedNote;
    final kept = {
      for (final entry in saved?.attachments ?? const <Map<String, dynamic>>[])
        if (NoteAttachment.tryFromMap(entry) case final attachment?)
          attachment.path,
      if (saved?.background['image'] case final String image) image,
    };
    for (final path in _draftFiles.difference(kept)) {
      try {
        File(path).deleteSync();
      } catch (_) {}
    }
    _titleController.dispose();
    _contentController.dispose();
    _contentFocusNode.dispose();
    _paperController.dispose();
    _paperExpansion.dispose();
    super.dispose();
  }

  bool _save() {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (_savedNote == null &&
        title.isEmpty &&
        content.isEmpty &&
        _attachmentPaths.isEmpty &&
        !_hasUnsavedChanges) {
      Navigator.pop(context);
      return true;
    }
    final repo = ref.read(notesRepositoryProvider);

    try {
      _savedNote = repo.saveNote(
        uuid: _savedNote?.uuid,
        expectedVersionVectorJson: _savedNote?.versionVectorJson,
        preserveLocalDraft: !_isPreviewMode && _hasUnsavedChanges,
        title: title.isEmpty ? 'Untitled Note' : title,
        content: content,
        tags: _tags,
        attachmentPaths: _attachmentPaths,
        background: {
          ..._background,
          ...NoteArtSelection.fromBackground(_background).toBackground(),
        },
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save your note. Please try again.'),
        ),
      );
      return false;
    }

    _titleController.text = _savedNote!.title;
    _contentController.text = _savedNote!.content;
    _savedDraft = _draftSnapshot;
    _keepScanOriginals(_savedNote!);

    _restorePreview();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // A new note's QVAC task lives as long as this editor, not the sheet.
    ref.listen(noteDraftAiProvider, (_, _) {});
    final canModifySaved =
        ref.watch(syncDeviceRoleProvider) != SyncDeviceRole.secondary;
    final art = NoteArtSelection.fromBackground(_background);
    final colors = art.color.resolveColors(context.colors);
    final paperColor = colors.background;
    final image = art.imageUrl == null
        ? null
        : ResizeImage(
            noteImageProvider(art.imageUrl!, art.imageSource),
            width: 2048,
            height: 2048,
            policy: ResizeImagePolicy.fit,
          );

    // A generated website is previewed on its own page; the text stays and
    // returns in the paper editor.
    final saved = _savedNote;
    if (_isPreviewMode && saved != null && saved.website.isNotEmpty) {
      return QvacAssistantPage(
        label: 'Note',
        child: _withAssistant(
          available: !_hasUnsavedChanges,
          child: NoteWebsitePage(
            note: saved,
            colors: colors,
            onEdit: canModifySaved ? _editWebsiteNote : null,
            actions: canModifySaved
                ? NoteActionsMenu(
                    isPinned: saved.isPinned,
                    onTogglePin: _togglePin,
                    onBackground: _pickBackground,
                    onTags: _pickTags,
                    onDelete: _deleteNote,
                    style: NoteWebsitePage.buttonStyle(colors),
                  )
                : null,
          ),
        ),
      );
    }

    final page = EditNotepageBg(
      seed: _noteArtworkSeed,
      animationDuration: _artworkDuration,
      color: paperColor,
      image: image,
      builder: (context, opacity, header) => ValueListenableBuilder<double>(
        valueListenable: _paperExpansion,
        builder: (context, expansion, _) {
          final canEdit = !_isPreviewMode && expansion == 1;
          final ink = colors.foreground;
          final headerColor = image == null
              ? Color.lerp(context.colors.surface, paperColor, expansion)!
              : Color.alphaBlend(
                  paperColor.withValues(alpha: expansion * opacity.value),
                  header ?? context.colors.surface,
                );
          final darkSurface = image == null
              ? ThemeData.estimateBrightnessForColor(headerColor) ==
                    Brightness.dark
              // The crossover where black has better contrast than white.
              : headerColor.computeLuminance() < .179;
          final content = PopScope(
            canPop: _isPreviewMode && expansion == 0,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _requestExit();
            },
            child: Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                systemOverlayStyle:
                    (darkSurface
                            ? SystemUiOverlayStyle.light
                            : SystemUiOverlayStyle.dark)
                        .copyWith(statusBarColor: Colors.transparent),
                flexibleSpace: Opacity(
                  opacity: expansion,
                  child: FadeTransition(
                    opacity: opacity,
                    child: NotePaperSurface(color: paperColor),
                  ),
                ),
                foregroundColor: image != null
                    ? (darkSurface ? Colors.white : Colors.black)
                    : Color.lerp(context.colors.onSurface, ink, expansion),
                elevation: 0,
                scrolledUnderElevation: 0,
                actionsPadding: const EdgeInsets.only(right: 12),
                actions: [
                  if (_isPreviewMode && expansion == 0 && canModifySaved)
                    NoteActionsMenu(
                      isPinned: _savedNote?.isPinned ?? false,
                      onTogglePin: _togglePin,
                      onBackground: _pickBackground,
                      onTags: _pickTags,
                      onDelete: _deleteNote,
                    ),

                  if (canEdit) ...[
                    IconButton.filled(
                      tooltip: 'Choose note background',
                      onPressed: _pickBackground,
                      icon: Icon(Icons.color_lens_outlined),
                      style: IconButton.styleFrom(
                        backgroundColor: context.colors.surface,
                        foregroundColor: context.colors.onSurface,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: FilledButton.icon(
                        onPressed: canEdit ? _save : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: context.colors.surface,
                          foregroundColor: context.colors.onSurface,
                        ),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Save'),
                      ),
                    ),
                  ],
                ],
                leading: IconButton.filled(
                  tooltip: expansion == 0 ? 'Back' : 'Close editor',
                  onPressed: () => context.nav.maybePop(),
                  icon: Icon(
                    expansion == 0
                        ? Icons.arrow_back_ios_new_rounded
                        : Icons.close_rounded,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: context.colors.surface,
                    foregroundColor: context.colors.onSurface,
                  ),
                ),
              ),
              body: EditNoteCardBg(
                color: paperColor,
                paperOpacity: opacity,
                controller: _paperController,
                isPreviewMode: _isPreviewMode,
                readOnly: !canModifySaved && _savedNote != null,
                onExpansionChanged: (value) => _paperExpansion.value = value,
                onEdit: () => setState(() => _isPreviewMode = false),

                children: _noteSlivers(canEdit, colors),
              ),
              floatingActionButtonLocation:
                  FloatingActionButtonLocation.startFloat,
              floatingActionButton: canEdit
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton.filled(
                          tooltip: 'Attach files',
                          onPressed: _pickingAttachments
                              ? null
                              : _pickAttachments,
                          icon: Icon(Icons.file_present_outlined),
                          style: IconButton.styleFrom(
                            backgroundColor: context.colors.surface,
                            foregroundColor: context.colors.onSurface,
                          ),
                        ),
                        IconButton.filled(
                          tooltip: 'Transcribe a voice note',
                          onPressed: canModifySaved || _savedNote == null
                              ? _openVoice
                              : null,
                          icon: Icon(Icons.mic_none_rounded),
                          style: IconButton.styleFrom(
                            backgroundColor: context.colors.surface,
                            foregroundColor: context.colors.onSurface,
                          ),
                        ),
                        IconButton.filled(
                          tooltip: 'Add checkbox',
                          onPressed: _addCheckbox,
                          icon: Icon(Icons.list_outlined),
                          style: IconButton.styleFrom(
                            backgroundColor: context.colors.surface,
                            foregroundColor: context.colors.onSurface,
                          ),
                        ),
                      ],
                    )
                  : null,
            ),
          );
          return _withAssistant(
            available: _isPreviewMode && expansion == 0 && !_hasUnsavedChanges,
            child: content,
          );
        },
      ),
    );
    return QvacAssistantPage(label: 'Note', child: page);
  }

  Widget _withAssistant({required bool available, required Widget child}) {
    final noteId = _savedNote?.uuid;
    return QvacAssistantContent(
      label: 'Note',
      builder: (context, scrollController) => NoteAssistant(
        noteId: noteId,
        available: noteId == null || available,
        draftTitle: noteId == null ? _titleController.text : null,
        onDraftResult: noteId == null ? _applyDraft : null,
        scrollController: scrollController,
        onChanged: () {
          if (noteId != null) _reloadSaved(noteId);
        },
        onMetadataApplied: _metadataApplied,
      ),
      child: child,
    );
  }

  /// The paper editor mounts already flat, so it never reports the unfold.
  void _editWebsiteNote() {
    _paperExpansion.value = 1;
    setState(() => _isPreviewMode = false);
  }

  List<Widget> _noteSlivers(bool canEdit, NoteColors colors) {
    final ink = colors.foreground;
    // Chips paint on their own Material surface, so translucent fills can reveal
    // the app's surface instead of the note's paper underneath.
    final tagFill = Color.alphaBlend(
      ink.withValues(alpha: .05),
      colors.background,
    );
    final titleStyle = TextStyle(
      color: ink,
      fontSize: 24,
      height: 1.3,
      fontWeight: FontWeight.bold,
    );
    final bodyStyle = TextStyle(color: ink, fontSize: 16, height: 1.6);
    final theme = Theme.of(context);
    final markdownStyle = MarkdownStyleSheet.fromTheme(
      theme.copyWith(
        textTheme: theme.textTheme.apply(bodyColor: ink, displayColor: ink),
      ),
    ).copyWith(p: bodyStyle, listBullet: bodyStyle);
    return [
      if (_attachmentPaths.isNotEmpty)
        SliverToBoxAdapter(
          child: NoteAttachmentStrip(
            attachments: _attachmentPaths,
            colors: colors,
            onRemove: canEdit ? _removeAttachment : null,
          ),
        ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: canEdit
              ? TextField(
                  key: const ValueKey('note-title-editor'),
                  controller: _titleController,
                  maxLines: null,
                  style: titleStyle,
                  cursorColor: ink,
                  decoration: InputDecoration(
                    hintText: 'Note Title...',
                    hintStyle: TextStyle(color: colors.secondary),
                    border: InputBorder.none,
                    isCollapsed: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                )
              : Text(
                  _titleController.text,
                  key: const ValueKey('note-title-preview'),
                  style: titleStyle,
                ),
        ),
      ),
      if (_tags.isNotEmpty || canEdit)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final value in _tags)
                    if (NoteTag.tryParse(value) case final tag?)
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth,
                        ),
                        child: Chip(
                          avatar: Text(tag.emoji),
                          label: Text(
                            tag.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                          labelStyle: TextStyle(color: ink, fontSize: 12),
                          color: WidgetStatePropertyAll(tagFill),
                          surfaceTintColor: Colors.transparent,
                          side: BorderSide(color: ink.withValues(alpha: .15)),
                          shape: const StadiumBorder(),
                        ),
                      ),
                  if (canEdit)
                    ActionChip(
                      avatar: Icon(Icons.sell_outlined, size: 16, color: ink),
                      label: Text(_tags.isEmpty ? 'Add tags' : 'Edit tags'),
                      labelStyle: TextStyle(color: ink, fontSize: 12),
                      color: WidgetStatePropertyAll(tagFill),
                      surfaceTintColor: Colors.transparent,
                      side: BorderSide(color: ink.withValues(alpha: .2)),
                      shape: const StadiumBorder(),
                      onPressed: _pickTags,
                    ),
                ],
              ),
            ),
          ),
        ),
      SliverToBoxAdapter(
        child: canEdit
            ? TextField(
                key: const ValueKey('note-content-editor'),
                controller: _contentController,
                focusNode: _contentFocusNode,
                maxLines: null,
                minLines: 5,
                style: bodyStyle,
                cursorColor: ink,
                cursorWidth: 2.5,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: 'Write in markdown (supports # headings, - lists, **bold**)...',
                  hintStyle: TextStyle(color: colors.secondary),
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.zero,
                ),
              )
            // The paper's CustomScrollView already handles scrolling.
            : MarkdownBody(
                key: const ValueKey('note-content-preview'),
                data: _contentController.text,
                styleSheet: markdownStyle,
              ),
      ),
    ];
  }
}
