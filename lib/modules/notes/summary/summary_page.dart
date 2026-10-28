import 'package:flutter/material.dart';
import 'package:journal/modules/diary/history/diary_answer_page.dart';
import 'package:journal/modules/diary/questions/daily_question_task_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journal/modules/settings/companion/companion_page.dart';

import 'summary_controller.dart';
import '../transform/transform_page.dart';
import '../metadata/note_help_pages.dart';
import '../../presentation/presentation_page.dart';
import '../../diary/suggestions/diary_details_page.dart';

class NoteSummaryPage extends ConsumerWidget {
  const NoteSummaryPage({super.key, this.noteId});
  final String? noteId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(noteSummaryProvider);
    if (state.handle?.isPresentation == true) return const PresentationPage();
    if (state.handle?.isDiaryAnswer == true) return const DiaryAnswerPage();
    if (state.handle?.isDailyQuestion == true) {
      return const DailyQuestionTaskPage();
    }
    if (state.handle?.isDiarySuggestion == true) {
      return DiaryDetailsPage(dateString: state.handle!.noteId);
    }
    if (state.handle?.isTransformation == true) {
      return NoteTransformPage(noteId: noteId);
    }
    if (state.handle?.isNoteMetadata == true) {
      return NoteMetadataPage(noteId: state.handle!.noteId);
    }
    if (state.handle?.isNoteIdeas == true) return const NoteIdeasPage();
    final controller = ref.read(noteSummaryProvider.notifier);
    final otherNote =
        state.handle != null &&
        noteId != null &&
        state.handle!.noteId != noteId;
    return Scaffold(
      appBar: AppBar(title: const Text('Note summary')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'An AI preview can miss or invent details. Check it against your note.',
            ),
            const SizedBox(height: 16),
            if (state.handle == null && state.phase == 'idle') ...[
              const Text(
                'Send only this saved note’s title and body to your trusted computer. Attachments and other notes stay here. Maximum 2,000 UTF-8 bytes; longer notes are not sent or shortened.',
              ),
              const SizedBox(height: 16),
              if (noteId != null)
                FilledButton.icon(
                  onPressed: () => controller.start(noteId!),
                  icon: const Icon(Icons.summarize_outlined),
                  label: const Text('Summarize'),
                )
              else
                const Text('Open a saved note and choose Summarize to start.'),
            ],
            if (otherNote)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  'This retained preview belongs to another note. Finish or clear it before starting a new summary.',
                ),
              ),
            if (state.stale)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  'Earlier note version: the source changed or was deleted. This summary does not describe the current note.',
                  key: ValueKey('summary-source-changed'),
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            if (state.busy) const LinearProgressIndicator(),
            if (state.phase != 'idle')
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  switch (state.phase) {
                    'submitting' => 'Submitting · acceptance not yet confirmed',
                    'restoring' => 'Reading saved request',
                    'retrieving' => 'Retrieving accepted work',
                    'queued' => 'Accepted · waiting',
                    'running' => 'Running on your computer',
                    'completed' => 'Summary preview',
                    'cancelled' => 'Cancelled',
                    'expired' => 'Preview expired',
                    'interrupted' => 'Interrupted',
                    'failed' => 'Generation failed',
                    _ => 'Needs attention',
                  },
                  key: const ValueKey('summary-phase'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            if (state.message != null) Text(state.message!),
            if (state.text != null) ...[
              const SizedBox(height: 16),
              // Model output is inert text: no Markdown, HTML, links or actions.
              SelectableText(
                state.text!,
                key: const ValueKey('summary-output'),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: state.stale
                    ? null
                    : () async {
                        await controller.refreshSource();
                        if (!context.mounted) return;
                        if (ref.read(noteSummaryProvider).stale ||
                            ref.read(noteSummaryProvider).text != state.text) {
                          return;
                        }
                        await Clipboard.setData(
                          ClipboardData(text: state.text!),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Summary copied. Your note is unchanged.',
                              ),
                            ),
                          );
                        }
                      },
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Copy summary'),
              ),
            ],
            if (!state.busy && !state.terminal && state.phase != 'idle') ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: state.phase == 'storageError'
                    ? controller.restore
                    : state.handle == null
                    ? controller.clear
                    : controller.retry,
                child: Text(
                  state.phase == 'storageError'
                      ? 'Retry saved request'
                      : state.handle == null
                      ? 'Back to summary action'
                      : 'Retry / retrieve same task',
                ),
              ),
              if (state.handle != null)
                TextButton(
                  onPressed: controller.cancel,
                  child: const Text('Cancel summary'),
                ),
            ],
            if (state.terminal)
              TextButton(
                onPressed: controller.clear,
                child: const Text('Clear preview'),
              ),
            if (state.terminal &&
                state.phase != 'completed' &&
                state.handle != null &&
                !state.stale)
              OutlinedButton(
                onPressed: state.busy ? null : controller.retryAsNew,
                child: const Text('Try again as a new task'),
              ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const CompanionPage()),
              ),
              child: const Text('Computer connection settings'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Dismiss'),
            ),
            if (state.handle != null)
              const Text(
                'Dismiss keeps the task in Settings → AI task history. Accepted work continues on the computer. Clear preview acknowledges the result and removes desktop text when connected; an offline acknowledgment is retried on reconnection. Results expire within 24 hours of the request. Local status receipts remain for seven days.',
              ),
          ],
        ),
      ),
    );
  }
}
