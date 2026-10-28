import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_wise/sync_wise.dart' show SyncDeviceRole;
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/models/note_attachment.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';

import '../summary/summary_controller.dart';
import '../summary/summary_history_page.dart';
import '../summary/summary_page.dart';
import 'note_image_contract.dart';

/// Ask about one image attached to a saved note, review the answer, and
/// optionally insert reviewed text into the note.
class NoteImagePage extends ConsumerStatefulWidget {
  const NoteImagePage({super.key, required this.noteId});
  final String noteId;
  @override
  ConsumerState<NoteImagePage> createState() => _NoteImagePageState();
}

class _NoteImagePageState extends ConsumerState<NoteImagePage> {
  final _question = TextEditingController();
  final _insertion = TextEditingController();
  String? _path, _shownFor;
  String _mode = 'describe';

  @override
  void dispose() {
    _question.dispose();
    _insertion.dispose();
    super.dispose();
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
    final mine = handle?.isNoteImage == true;
    final readOnly =
        ref.watch(syncDeviceRoleProvider) == SyncDeviceRole.secondary;
    final note = ref
        .watch(notesRepositoryProvider)
        .getNoteByUuid(widget.noteId);
    final images = [
      for (final entry in note?.attachments ?? const <Map<String, dynamic>>[])
        if (NoteAttachment.tryFromMap(entry) case final a? when a.isImage) a,
    ];
    final answer = mine ? controller.noteImageAnswer() : null;
    if (answer != null && _shownFor != handle!.id) {
      _shownFor = handle.id;
      _insertion.text = answer.insertion;
    }
    final theme = Theme.of(context).textTheme;
    Widget section(String title, String body, {Key? key}) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.titleSmall),
          SelectableText(body, key: key),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Ask about an image')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'An AI description can miss or misread details. It never identifies people or guesses feelings. Your note changes only if you insert reviewed text.',
            ),
            const SizedBox(height: 12),
            if (handle == null && state.phase == 'idle') ...[
              const Text(
                'Only the chosen image, re-encoded on this phone without location or camera metadata (at most 1280 px), and your question go to your trusted computer. The note text, other attachments and other notes stay here.',
              ),
              const SizedBox(height: 12),
              if (images.isEmpty)
                const Text(
                  'This saved note has no image attachments.',
                  key: ValueKey('note-image-none'),
                ),
              for (final image in images)
                _ImageChoice(
                  attachment: image,
                  selected: _path == image.path,
                  onTap: () => setState(() => _path = image.path),
                ),
              if (images.isNotEmpty) ...[
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: [
                    for (final entry in noteImageModes.entries)
                      ButtonSegment(value: entry.key, label: Text(entry.value)),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (value) =>
                      setState(() => _mode = value.single),
                ),
                if (_mode == 'question')
                  TextField(
                    key: const ValueKey('note-image-question'),
                    controller: _question,
                    maxLength: noteImageQuestionChars,
                    decoration: const InputDecoration(
                      labelText: 'Question about what is visible',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const ValueKey('note-image-start'),
                  onPressed:
                      _path == null ||
                          (_mode == 'question' && _question.text.trim().isEmpty)
                      ? null
                      : () => controller.startNoteImage(
                          widget.noteId,
                          path: _path!,
                          mode: _mode,
                          question: _mode == 'question' ? _question.text : '',
                        ),
                  icon: const Icon(Icons.image_search_outlined),
                  label: const Text('Ask'),
                ),
              ],
            ],
            if (handle != null && !mine) ...[
              const Text(
                'Another AI preview is open. Finish or clear it first.',
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const NoteSummaryPage(),
                  ),
                ),
                child: const Text('Open the current preview'),
              ),
            ],
            if (mine) ...[
              Text(
                summaryPhaseLabel(state.phase),
                key: const ValueKey('note-image-phase'),
                style: theme.titleMedium,
              ),
              if (state.stale)
                const Text(
                  'The note or its image attachment changed after you asked. This answer cannot be inserted.',
                  key: ValueKey('note-image-stale'),
                ),
              if (state.text != null && answer == null)
                const Text('The answer could not be read safely.'),
              if (answer != null) ...[
                if (answer.answer.isNotEmpty)
                  section(
                    'Answer',
                    answer.answer,
                    key: const ValueKey('note-image-answer'),
                  ),
                section(
                  'What is visible',
                  answer.observations,
                  key: const ValueKey('note-image-observations'),
                ),
                if (answer.text.isNotEmpty)
                  section(
                    'Text read from the image (content only, may contain errors)',
                    answer.text,
                    key: const ValueKey('note-image-text'),
                  ),
                if (answer.inference.isNotEmpty)
                  section(
                    'Possible interpretation (not certain)',
                    answer.inference,
                    key: const ValueKey('note-image-inference'),
                  ),
                const SizedBox(height: 16),
                Text('Insert into the note', style: theme.titleSmall),
                TextField(
                  key: const ValueKey('note-image-insertion'),
                  controller: _insertion,
                  minLines: 2,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    helperText: 'Edit before inserting. Appended to the end of the note body.',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (readOnly)
                  const Text(
                    'Existing notes are read-only on this device. You can review or copy this answer.',
                  ),
                FilledButton(
                  key: const ValueKey('note-image-insert'),
                  onPressed:
                      state.stale ||
                          state.busy ||
                          readOnly ||
                          _insertion.text.trim().isEmpty
                      ? null
                      : () async {
                          final inserted = await controller.acceptNoteImage(
                            _insertion.text,
                          );
                          if (inserted && context.mounted) {
                            Navigator.of(context).pop(true);
                          }
                        },
                  child: const Text('Insert reviewed text'),
                ),
              ],
              if (state.terminal)
                TextButton(
                  onPressed: state.busy ? null : controller.clear,
                  child: const Text('Close / clear answer'),
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
                      onPressed: controller.cancel,
                      child: const Text('Cancel task'),
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
                  key: const ValueKey('note-image-message'),
                ),
              ),
            if (handle == null && state.phase != 'idle' && !state.busy)
              TextButton(
                onPressed: state.phase == 'storageError'
                    ? controller.restore
                    : controller.clear,
                child: const Text('Return'),
              ),
            const SizedBox(height: 16),
            const Text(
              'Inserted text keeps a prior-body copy in Prior content / recovery on this phone. The image itself is never changed or uploaded to sync.',
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageChoice extends StatelessWidget {
  const _ImageChoice({
    required this.attachment,
    required this.selected,
    required this.onTap,
  });
  final NoteAttachment attachment;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final available = attachment.file.existsSync();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: available,
      selected: selected,
      leading: SizedBox.square(
        dimension: 56,
        child: available
            ? Image.file(
                File(attachment.file.path),
                cacheWidth: 112,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
              )
            : const Icon(Icons.image_not_supported_outlined),
      ),
      title: Text(attachment.filename, overflow: TextOverflow.ellipsis),
      subtitle: available
          ? null
          : const Text('Not available on this phone. Reattach it here.'),
      trailing: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
      ),
      onTap: available ? onTap : null,
    );
  }
}
