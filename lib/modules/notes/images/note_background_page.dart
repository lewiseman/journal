import 'package:journal/modules/notes/views/widgets/note_ai_widgets.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_wise/sync_wise.dart' show SyncDeviceRole;
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/models/note_art.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';

import '../summary/summary_controller.dart';
import '../summary/summary_history_page.dart';
import '../summary/summary_page.dart';
import 'note_background_gen.dart';

/// Generate, preview and explicitly apply (or revert) a note background.
class NoteBackgroundPage extends ConsumerStatefulWidget {
  const NoteBackgroundPage({super.key, required this.noteId});
  final String noteId;
  @override
  ConsumerState<NoteBackgroundPage> createState() => _NoteBackgroundPageState();
}

class _NoteBackgroundPageState extends ConsumerState<NoteBackgroundPage> {
  final _prompt = TextEditingController();
  String _tone = 'light';
  File? _preview;
  String? _previewFor, _message;
  bool _canRevert = false;

  @override
  void initState() {
    super.initState();
    final handle = ref.read(noteSummaryProvider).handle;
    ref
        .read(noteBackgroundStoreProvider)
        .sweepPreviews(
          keep: handle?.isNoteBackground == true ? handle!.id : null,
        )
        .catchError((Object _) {});
    _checkRevert();
  }

  Future<void> _checkRevert() async {
    final note = ref.read(notesRepositoryProvider).getNoteByUuid(widget.noteId);
    final recovery = note == null
        ? null
        : await ref
              .read(noteBackgroundStoreProvider)
              .recovery(widget.noteId, note.background);
    if (mounted) setState(() => _canRevert = recovery != null);
  }

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _discard() async {
    final handle = ref.read(noteSummaryProvider).handle;
    await ref.read(noteSummaryProvider.notifier).clear();
    if (handle != null) {
      await ref.read(noteBackgroundStoreProvider).deletePreview(handle.id);
    }
    if (mounted) setState(() => _preview = _previewFor = null);
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(accountResetProvider).blocksDataAccess) {
      return const Scaffold(
        body: Center(child: Text('Account reset in progress.')),
      );
    }
    final state = ref.watch(noteSummaryProvider);
    final controller = ref.read(noteSummaryProvider.notifier);
    final handle = state.handle;
    final mine = handle?.isNoteBackground == true;
    final readOnly =
        ref.watch(syncDeviceRoleProvider) == SyncDeviceRole.secondary;
    final request = mine && handle!.localSource != null
        ? NoteBackgroundRequest.decode(handle.localSource!)
        : null;
    if (mine && state.phase == 'completed' && _previewFor != handle!.id) {
      _previewFor = handle.id;
      controller.noteBackgroundPreview().then((file) {
        if (mounted) setState(() => _preview = file);
      });
    }
    final note = ref
        .watch(notesRepositoryProvider)
        .getNoteByUuid(widget.noteId);
    final colors = NoteArtSelection.fromBackground(note?.background ?? const {})
        .color
        .resolveColors(Theme.of(context).colorScheme);
    return NoteAiScaffold(
      tool: NoteAiTool.background,
      step: _preview != null
          ? 2
          : state.busy
          ? 1
          : 0,
      children: [
        if (readOnly)
          const Text(
            'Existing notes are read-only on this device, so their background cannot change here.',
          ),
        if (handle == null && state.phase == 'idle' && !readOnly) ...[
          NoteAiBackdropIdeas(
            value: _prompt.text,
            onChanged: state.busy
                ? null
                : (value) => setState(() => _prompt.text = value),
          ),
          TextField(
            key: const ValueKey('note-background-prompt'),
            controller: _prompt,
            maxLength: noteBackgroundPromptChars,
            decoration: const InputDecoration(
              labelText: 'Describe the background',
              hintText: 'For example: sea glass and morning fog',
            ),
            onChanged: (_) => setState(() {}),
          ),
          NoteAiChoices<String>(
            choices: noteBackgroundTones,
            selected: _tone,
            icons: const {
              'light': Icons.light_mode_outlined,
              'dark': Icons.dark_mode_outlined,
            },
            onChanged: (value) => setState(() => _tone = value),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('note-background-start'),
            onPressed: _prompt.text.trim().isEmpty
                ? null
                : () => controller.startNoteBackground(
                    widget.noteId,
                    prompt: _prompt.text,
                    tone: _tone,
                  ),
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('Generate'),
          ),

          const Text(
            'Generation takes about a minute on the computer and can be cancelled.',
          ),
        ],
        if (handle != null && !mine) ...[
          const Text('Another AI preview is open. Finish or clear it first.'),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const NoteSummaryPage()),
            ),
            child: const Text('Open the current preview'),
          ),
        ],
        if (mine) ...[
          Text(
            '“${request?.prompt ?? ''}” · ${summaryPhaseLabel(state.phase)}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (state.stale)
            const Text(
              'The note’s background changed or the note was deleted. This preview cannot be applied.',
              key: ValueKey('note-background-stale'),
            ),
          if (_preview != null) ...[
            const SizedBox(height: 12),
            // Shows the image as the note will: under 80% opaque paper.
            AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      _preview!,
                      key: const ValueKey('note-background-preview'),
                      fit: BoxFit.cover,
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      top: 72,
                      bottom: 16,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.background.withValues(alpha: .8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            note?.title.isNotEmpty == true
                                ? note!.title
                                : 'Your note',
                            style: TextStyle(
                              color: colors.foreground,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('note-background-accept'),
              onPressed: state.stale || state.busy || readOnly
                  ? null
                  : () async {
                      final accepted = await controller.acceptNoteBackground();
                      if (accepted && context.mounted) {
                        Navigator.of(context).pop(true);
                      }
                    },
              child: const Text('Use as background'),
            ),
            OutlinedButton(
              key: const ValueKey('note-background-again'),
              onPressed: state.busy || request == null
                  ? null
                  : () async {
                      await _discard();
                      await controller.startNoteBackground(
                        widget.noteId,
                        prompt: request.prompt,
                        tone: request.tone,
                      );
                    },
              child: const Text('Generate another'),
            ),
          ],
          if (state.terminal)
            TextButton(
              key: const ValueKey('note-background-discard'),
              onPressed: state.busy ? null : _discard,
              child: const Text('Discard'),
            ),
          if (!state.terminal && !state.busy)
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: controller.retry,
                  child: const Text('Retry / retrieve same task'),
                ),
                TextButton(
                  key: const ValueKey('note-background-cancel'),
                  onPressed: controller.cancel,
                  child: const Text('Cancel'),
                ),
              ],
            ),
        ],
        if (state.busy) const LinearProgressIndicator(),
        if (state.message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              state.message!,
              key: const ValueKey('note-background-message'),
            ),
          ),
        if (handle == null && state.phase != 'idle' && !state.busy)
          TextButton(
            onPressed: state.phase == 'storageError'
                ? controller.restore
                : controller.clear,
            child: const Text('Return'),
          ),
        if (_canRevert && !readOnly) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const ValueKey('note-background-revert'),
            onPressed: () async {
              try {
                await controller.revertNoteBackground(widget.noteId);
                if (context.mounted) Navigator.of(context).pop(true);
              } catch (error) {
                setState(
                  () => _message = error is StateError
                      ? error.message.toString()
                      : 'Could not restore the earlier background.',
                );
              }
            },
            icon: const Icon(Icons.undo),
            label: const Text('Restore the previous background'),
          ),
        ],
        if (_message != null) Text(_message!),
      ],
    );
  }
}
