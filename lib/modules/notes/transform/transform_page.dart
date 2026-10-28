import 'package:flutter/material.dart';
import 'package:journal/modules/diary/history/diary_answer_page.dart';
import 'package:journal/modules/diary/questions/daily_question_task_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_wise/sync_wise.dart' show SyncDeviceRole;
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';

import '../summary/summary_controller.dart';
import '../summary/summary_page.dart';
import '../summary/summary_history_page.dart';
import 'transform_contract.dart';
import '../metadata/note_help_pages.dart';
import '../images/note_image_page.dart';
import '../images/note_scan_page.dart';
import '../images/note_background_page.dart';
import '../../presentation/presentation_page.dart';
import '../../diary/suggestions/diary_details_page.dart';

class NoteTransformPage extends ConsumerStatefulWidget {
  const NoteTransformPage({super.key, this.noteId});
  final String? noteId;
  @override
  ConsumerState<NoteTransformPage> createState() => _NoteTransformPageState();
}

class _NoteTransformPageState extends ConsumerState<NoteTransformPage> {
  final _body = TextEditingController();
  final _intent = TextEditingController();
  String _operation = 'rewrite-note';
  String? _version;
  int? _start, _end;
  String? _notice;
  @override
  void initState() {
    super.initState();
    final note = widget.noteId == null
        ? null
        : ref.read(notesRepositoryProvider).getNoteByUuid(widget.noteId!);
    _body.text = note?.content ?? '';
    _version = note?.versionVectorJson;
  }

  @override
  void dispose() {
    _body.dispose();
    _intent.dispose();
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
    if (state.handle?.isPresentation == true) return const PresentationPage();
    if (state.handle?.isDiaryAnswer == true) return const DiaryAnswerPage();
    if (state.handle?.isDailyQuestion == true) {
      return const DailyQuestionTaskPage();
    }
    if (state.handle?.isDiarySuggestion == true) {
      return DiaryDetailsPage(dateString: state.handle!.noteId);
    }
    if (state.handle?.isNoteMetadata == true) {
      return NoteMetadataPage(noteId: state.handle!.noteId);
    }
    if (state.handle?.isNoteIdeas == true) return const NoteIdeasPage();
    if (state.handle?.isNoteImage == true) {
      return NoteImagePage(noteId: state.handle!.noteId);
    }
    if (state.handle?.isNoteScan == true) {
      return NoteScanPage(noteId: state.handle!.noteId);
    }
    if (state.handle?.isNoteBackground == true) {
      return NoteBackgroundPage(noteId: state.handle!.noteId);
    }
    final controller = ref.read(noteSummaryProvider.notifier);
    final handle = state.handle;
    final readOnly =
        ref.watch(syncDeviceRoleProvider) == SyncDeviceRole.secondary;
    final source = handle?.localSource == null
        ? null
        : TransformSource.decode(handle!.localSource!);
    return Scaffold(
      appBar: AppBar(title: const Text('Writing help')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Choose one action. Review the replacement against your words before accepting. Check facts and personal voice.',
            ),
            const SizedBox(height: 16),
            if (handle == null && state.phase == 'idle') ...[
              const Text(
                'Only the chosen saved body or passage and your intent go to your trusted computer. Titles, tags, attachments and other notes stay here. Requests are limited to 2,000 UTF-8 bytes including encoding; nothing is shortened automatically.',
              ),
              if (widget.noteId != null && _version != null) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _operation,
                  decoration: const InputDecoration(labelText: 'Action'),
                  items: [
                    for (final entry in transformOperations.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (value) => setState(() => _operation = value!),
                ),
                TextField(
                  controller: _intent,
                  maxLines: 3,
                  maxLength: 240,
                  decoration: const InputDecoration(
                    labelText: 'Intent (required for tone)',
                    hintText: 'For example: make this warmer, keep my wording',
                  ),
                ),
                const Text(
                  'Select a passage below, then choose Use selected passage, or use the whole body.',
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('transform-source-selector'),
                  controller: _body,
                  readOnly: true,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Saved body',
                    border: OutlineInputBorder(),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () {
                        final selection = _body.selection;
                        setState(() {
                          if (selection.isValid && !selection.isCollapsed) {
                            _start = selection.start;
                            _end = selection.end;
                            _notice = null;
                          } else {
                            _notice = 'Select a nonempty passage first.';
                          }
                        });
                      },
                      child: const Text('Use selected passage'),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _start = _end = null;
                        _notice = null;
                      }),
                      child: const Text('Use whole body'),
                    ),
                  ],
                ),
                Text(
                  _start == null
                      ? 'Scope: whole saved body'
                      : 'Scope: selected passage',
                ),
                if (_start != null)
                  SelectableText(_body.text.substring(_start!, _end!)),
                if (_notice != null) Text(_notice!),
                FilledButton(
                  onPressed: () => controller.start(
                    widget.noteId!,
                    operation: _operation,
                    start: _start,
                    end: _end,
                    intent: _intent.text.trim(),
                    expectedContent: _body.text,
                    expectedVersion: _version,
                  ),
                  child: const Text('Generate proposal'),
                ),
              ] else
                const Text(
                  'Open a saved note and choose Writing help to start.',
                ),
            ],
            if (handle != null && !handle.isTransformation) ...[
              const Text(
                'Finish or clear the retained summary before starting writing help.',
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const NoteSummaryPage(),
                  ),
                ),
                child: const Text('Open summary'),
              ),
            ] else if (handle != null) ...[
              Text(
                '${transformOperations[handle.operation]} · ${summaryPhaseLabel(state.phase)}',
                key: const ValueKey('transform-phase'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (source != null) ...[
                const SizedBox(height: 16),
                const Text(
                  'Original selected text',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SelectableText(
                  source.selected,
                  key: const ValueKey('transform-original'),
                ),
              ],
              if (state.stale)
                const Text(
                  'The saved note changed or was deleted. This proposal cannot replace it.',
                  key: ValueKey('transform-source-changed'),
                ),
              if (state.text != null) ...[
                const SizedBox(height: 16),
                const Text(
                  'Proposed replacement',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                // Raw Markdown stays inert here; existing note preview renders after acceptance.
                SelectableText(
                  state.text!,
                  key: const ValueKey('transform-output'),
                ),
                const SizedBox(height: 12),
                if (source?.selected == state.text)
                  const Text(
                    'The model proposed no changes. Reject or try another intent.',
                  ),
                if (readOnly)
                  const Text(
                    'Existing notes are read-only on this device. You can review or reject this proposal.',
                  ),
                if (source == null)
                  const Text(
                    'The protected original is unavailable. This proposal cannot be accepted.',
                  ),
                FilledButton(
                  key: const ValueKey('transform-accept'),
                  onPressed:
                      state.stale ||
                          state.text == source?.selected ||
                          state.busy ||
                          readOnly ||
                          source == null
                      ? null
                      : () async {
                          final accepted = await controller
                              .acceptTransformation();
                          if (!context.mounted) return;
                          if (accepted) Navigator.of(context).pop();
                        },
                  child: const Text('Accept replacement'),
                ),
              ],
              if (state.terminal)
                TextButton(
                  onPressed: state.busy
                      ? null
                      : () async {
                          await controller.clear();
                          if (context.mounted) Navigator.of(context).pop();
                        },
                  child: const Text('Reject / clear proposal'),
                ),
              if (!state.terminal && !state.busy) ...[
                OutlinedButton(
                  onPressed: controller.retry,
                  child: const Text('Retry / retrieve same task'),
                ),
                TextButton(
                  onPressed: controller.cancel,
                  child: const Text('Cancel task'),
                ),
              ],
            ],
            if (state.busy) const LinearProgressIndicator(),
            if (state.message != null) Text(state.message!),
            if (handle == null && state.phase != 'idle' && !state.busy)
              TextButton(
                onPressed: state.phase == 'storageError'
                    ? controller.restore
                    : controller.clear,
                child: const Text('Retry / return to action'),
              ),
            const SizedBox(height: 16),
            const Text(
              'Dismiss keeps accepted work in Settings → AI task history for up to 24 hours. Accept saves a prior-body recovery copy on this phone. The 10 most recent copies survive restart, stay local and are removed by account reset. Accepted note content follows normal sync.',
            ),
            if (widget.noteId != null || handle?.isTransformation == true)
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => NoteRecoveryPage(
                      noteId: widget.noteId ?? handle!.noteId,
                    ),
                  ),
                ),
                child: const Text('Prior content / recovery'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Dismiss'),
            ),
          ],
        ),
      ),
    );
  }
}

class NoteRecoveryPage extends ConsumerStatefulWidget {
  const NoteRecoveryPage({super.key, required this.noteId});
  final String noteId;
  @override
  ConsumerState<NoteRecoveryPage> createState() => _NoteRecoveryPageState();
}

class _NoteRecoveryPageState extends ConsumerState<NoteRecoveryPage> {
  String? _message;
  @override
  Widget build(BuildContext context) {
    if (ref.watch(accountResetProvider).blocksDataAccess) {
      return const Scaffold(
        body: Center(child: Text('Account reset in progress.')),
      );
    }
    final repository = ref.watch(notesRepositoryProvider);
    final rows = repository.transformationHistory(widget.noteId);
    final readOnly =
        ref.watch(syncDeviceRoleProvider) == SyncDeviceRole.secondary;
    return Scaffold(
      appBar: AppBar(title: const Text('Prior note content')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Recovery copies stay on this phone. Restore works only if the note has not changed since that acceptance. Otherwise copy the prior body for manual recovery. Accepted or restored content uses normal note sync.',
          ),
          if (_message != null) Text(_message!),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No recovery copies for this note.'),
            ),
          for (final row in rows)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${transformOperations[row.operation] ?? recoveryOperationLabels[row.operation] ?? 'AI edit'} · ${DateTime.fromMillisecondsSinceEpoch(row.created).toLocal()}',
                    ),
                    if (row.restored) const Text('Restored'),
                    ExpansionTile(
                      title: const Text('Prior body'),
                      children: [SelectableText(row.beforeContent)],
                    ),
                    Wrap(
                      spacing: 12,
                      children: [
                        TextButton(
                          onPressed: readOnly || row.restored
                              ? null
                              : () {
                                  try {
                                    repository.restoreTransformation(row.id);
                                    setState(
                                      () => _message = 'Prior body restored and queued for normal sync.',
                                    );
                                  } catch (error) {
                                    setState(
                                      () => _message = error is StateError
                                          ? error.message.toString()
                                          : 'Could not restore content.',
                                    );
                                  }
                                },
                          child: const Text('Restore prior body'),
                        ),
                        TextButton(
                          onPressed: () => Clipboard.setData(
                            ClipboardData(text: row.beforeContent),
                          ),
                          child: const Text('Copy prior body'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (rows.isNotEmpty)
            TextButton(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Remove recovery copies?'),
                    content: const Text(
                      'This removes the local prior-body copies for this note.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Keep'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true &&
                    mounted &&
                    !ref.read(accountResetProvider).blocksDataAccess) {
                  repository.clearTransformationHistory(widget.noteId);
                  setState(() {});
                }
              },
              child: const Text('Remove recovery copies'),
            ),
        ],
      ),
    );
  }
}
