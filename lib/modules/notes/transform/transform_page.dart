import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journal/modules/diary/history/diary_answer_page.dart';
import 'package:journal/modules/diary/questions/daily_question_task_page.dart';
import 'package:journal/modules/diary/suggestions/diary_details_page.dart';
import 'package:journal/modules/flow/reflection/thought_reflection_task_page.dart';
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/presentation/note_presentation_page.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:sync_wise/sync_wise.dart' show SyncDeviceRole;

import '../images/note_background_page.dart';
import '../images/note_image_page.dart';
import '../images/note_scan_page.dart';
import '../metadata/note_help_pages.dart';
import '../summary/summary_controller.dart';
import '../summary/summary_history_page.dart';
import '../summary/summary_page.dart';
import '../views/widgets/note_ai_widgets.dart';
import 'note_writing_voice.dart';
import 'note_writing_widgets.dart';
import 'transform_contract.dart';

class NoteTransformPage extends ConsumerStatefulWidget {
  const NoteTransformPage({super.key, this.noteId, this.voice});
  final String? noteId;
  final NoteWritingVoice? voice;

  @override
  ConsumerState<NoteTransformPage> createState() => _NoteTransformPageState();
}

class _NoteTransformPageState extends ConsumerState<NoteTransformPage> {
  late final String _body;
  late final String? _version;
  late final _voice = widget.voice ?? PhoneNoteWritingVoice();
  String _operation = 'rewrite-note', _tone = 'friendly';
  String? _speaking;
  int _speechGeneration = 0;
  bool _showBefore = false, _applying = false;

  @override
  void initState() {
    super.initState();
    final note = widget.noteId == null
        ? null
        : ref.read(notesRepositoryProvider).getNoteByUuid(widget.noteId!);
    _body = note?.content ?? '';
    _version = note?.versionVectorJson;
  }

  @override
  void dispose() {
    _speechGeneration++;
    unawaited(_voice.stop());
    super.dispose();
  }

  Future<void> _stopSpeech() async {
    _speechGeneration++;
    if (mounted && _speaking != null) setState(() => _speaking = null);
    await _voice.stop();
  }

  Future<void> _read(String id, String text) async {
    final stopping = _speaking == id;
    final generation = ++_speechGeneration;
    setState(() => _speaking = stopping ? null : id);
    try {
      await _voice.stop();
      if (!mounted || generation != _speechGeneration || stopping) return;
      await _voice.speak(text);
    } catch (_) {
      if (mounted && generation == _speechGeneration) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not read aloud. Check your phone’s speech settings.',
            ),
          ),
        );
      }
    } finally {
      if (mounted && generation == _speechGeneration) {
        setState(() => _speaking = null);
      }
    }
  }

  Widget _listen(String id, String text) => OutlinedButton.icon(
    key: ValueKey('writing-listen-$id'),
    onPressed: () => _read(id, text),
    icon: Icon(
      _speaking == id ? Icons.stop_rounded : Icons.volume_up_outlined,
      size: 21,
    ),
    label: Text(_speaking == id ? 'Stop' : 'Listen'),
  );

  Future<void> _start() async {
    await _stopSpeech();
    if (!mounted || widget.noteId == null) return;
    await ref
        .read(noteSummaryProvider.notifier)
        .start(
          widget.noteId!,
          operation: _operation,
          intent: _operation == 'tone-note' ? writingTones[_tone]!.$3 : '',
          expectedContent: _body,
          expectedVersion: _version,
        );
  }

  Future<void> _clear() async {
    await _stopSpeech();
    if (!mounted) return;
    setState(() => _showBefore = false);
    await ref.read(noteSummaryProvider.notifier).clear();
  }

  Future<void> _accept() async {
    await _stopSpeech();
    if (!mounted || _applying) return;
    setState(() => _applying = true);
    try {
      final accepted = await ref
          .read(noteSummaryProvider.notifier)
          .acceptTransformation();
      if (accepted && mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(accountResetProvider, (_, next) {
      if (next.blocksDataAccess) unawaited(_stopSpeech());
    });
    if (ref.watch(accountResetProvider).blocksDataAccess) {
      return const Scaffold(
        body: Center(child: Text('Account reset in progress.')),
      );
    }
    final state = ref.watch(noteSummaryProvider);
    if (state.handle case final handle? when handle.isNoteWebsite) {
      return NotePresentationPage(noteId: handle.noteId);
    }
    if (state.handle?.isDiaryAnswer == true) return const DiaryAnswerPage();
    if (state.handle?.isDailyQuestion == true) {
      return const DailyQuestionTaskPage();
    }
    if (state.handle?.isThoughtReflection == true) {
      return const ThoughtReflectionTaskPage();
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
    final mine = handle?.isTransformation == true;
    final readOnly =
        ref.watch(syncDeviceRoleProvider) == SyncDeviceRole.secondary;
    final source = mine && handle!.localSource != null
        ? TransformSource.decode(handle.localSource!)
        : null;
    final otherNote =
        mine && widget.noteId != null && handle!.noteId != widget.noteId;
    final before = _showBefore && source != null;
    final result = mine ? state.text : null;
    final reading = before ? source.selected : result;
    final canAccept =
        result != null &&
        state.phase == 'completed' &&
        source != null &&
        result != source.selected &&
        !state.stale &&
        !state.busy &&
        !readOnly &&
        !otherNote &&
        !_applying;
    return NoteAiScaffold(
      tool: NoteAiTool.writing,
      header: NoteWritingSteps(
        step: _applying
            ? 2
            : mine || state.busy
            ? 1
            : 0,
      ),
      children: [
        if (_applying && handle == null) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
          const Center(child: Text('Saving…')),
        ],
        if (!_applying && handle == null && state.phase == 'idle') ...[
          if (widget.noteId != null && _version != null) ...[
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: _listen(
                'choices',
                'Choose a picture. Rewrite says the same thing in new words. Fix words corrects spelling and grammar. Add detail makes the note fuller. Change tone makes it friendly, simple, or formal. Organize adds headings and lists. Then tap Preview. Your whole note is used. You choose whether to keep the result.',
              ),
            ),
            const SizedBox(height: 8),
            NoteWritingChoices(
              selected: _operation,
              onChanged: (value) {
                unawaited(_stopSpeech());
                setState(() => _operation = value);
              },
            ),
            if (_operation == 'tone-note') ...[
              NoteAiChoices<String>(
                choices: {
                  for (final tone in writingTones.entries)
                    tone.key: tone.value.$1,
                },
                icons: {
                  for (final tone in writingTones.entries)
                    tone.key: tone.value.$2,
                },
                selected: _tone,
                onChanged: (value) => setState(() => _tone = value),
              ),
            ],
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const ValueKey('transform-start'),
              onPressed: _body.trim().isEmpty ? null : _start,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Preview'),
            ),
            if (_body.trim().isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Add some words to your note first.'),
              ),
          ] else
            const Text('Open a saved note to use Writing help.'),
        ],
        if (handle != null && !mine) ...[
          const Text('Another preview is open. Finish or clear it first.'),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const NoteSummaryPage()),
            ),
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Open preview'),
          ),
        ] else if (mine) ...[
          if (otherNote) const Text('This preview belongs to another note.'),
          if (result == null) ...[
            Center(child: NoteAiArt(tool: NoteAiTool.writing, size: 72)),
            const SizedBox(height: 12),
            Text(
              summaryPhaseLabel(state.phase),
              key: const ValueKey('transform-phase'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            if (state.busy || ['queued', 'running'].contains(state.phase))
              const LinearProgressIndicator(),
          ],
          if (state.stale)
            const Text(
              'The note changed. This preview cannot replace it.',
              key: ValueKey('transform-source-changed'),
            ),
          if (result != null) ...[
            NoteAiChoices<String>(
              choices: {
                if (source != null) 'before': 'Before',
                'after': 'After',
              },
              icons: const {
                'before': Icons.description_outlined,
                'after': Icons.auto_awesome_outlined,
              },
              selected: before ? 'before' : 'after',
              onChanged: (value) {
                unawaited(_stopSpeech());
                setState(() => _showBefore = value == 'before');
              },
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  NoteAiTool.writing.ink(context).withValues(alpha: .035),
                  noteAiPaper(context),
                ),
                border: Border.all(
                  color: NoteAiTool.writing.ink(context).withValues(alpha: .2),
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: _listen('preview', reading!),
                  ),
                  const SizedBox(height: 8),
                  // Both versions are inert text, including any Markdown.
                  SelectableText(
                    reading,
                    key: ValueKey(
                      before ? 'transform-original' : 'transform-output',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (source?.selected == result)
              const Text('No changes were needed.'),
            if (readOnly)
              const Text(
                'This device can preview changes. Save them from your primary device.',
              ),
            if (source == null)
              const Text(
                'The original is unavailable. This preview cannot be used.',
              ),
            FilledButton.icon(
              key: const ValueKey('transform-accept'),
              onPressed: canAccept ? _accept : null,
              icon: Icon(
                _applying ? Icons.hourglass_top_rounded : Icons.check_rounded,
              ),
              label: Text(_applying ? 'Saving…' : 'Use this'),
            ),
          ],
          if (state.terminal)
            TextButton.icon(
              key: const ValueKey('transform-clear'),
              onPressed: state.busy || _applying ? null : _clear,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try another'),
            ),
          if (!state.terminal && !state.busy) ...[
            OutlinedButton.icon(
              onPressed: controller.retry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry preview'),
            ),
            TextButton.icon(
              onPressed: controller.cancel,
              icon: const Icon(Icons.stop_rounded),
              label: const Text('Stop'),
            ),
          ],
        ],
        if (state.busy && handle == null) const LinearProgressIndicator(),
        if (state.message != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(state.message!),
          ),
        if (handle == null && state.phase != 'idle' && !state.busy)
          OutlinedButton.icon(
            onPressed: state.phase == 'storageError'
                ? controller.restore
                : controller.clear,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
      ],
    );
  }
}
