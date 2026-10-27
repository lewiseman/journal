import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/modules/settings/companion/companion_page.dart';

import 'summary_controller.dart';
import 'summary_page.dart';
import '../transform/transform_page.dart';
import '../transform/transform_contract.dart';
import '../../presentation/presentation_page.dart';
import '../../diary/suggestions/diary_details_page.dart';

String summaryPhaseLabel(String phase) => switch (phase) {
  'submitting' => 'Acceptance unknown',
  'accepted' || 'queued' => 'Accepted · waiting',
  'running' => 'Running',
  'completed' => 'Completed',
  'failed' => 'Failed',
  'interrupted' => 'Failed · desktop interrupted',
  'cancelled' => 'Cancelled',
  'expired' => 'Expired',
  _ => 'Reconnect to check',
};

class SummaryHistoryPage extends ConsumerWidget {
  const SummaryHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(noteSummaryProvider);
    final history = ref.watch(summaryHistoryProvider);
    final computers = ref.watch(companionControllerProvider).computers;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI task history'),
        actions: [
          IconButton(
            tooltip: 'Reconnect and refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await ref.read(companionControllerProvider.notifier).reconnect();
              if (!context.mounted) return;
              await ref.read(noteSummaryProvider.notifier).reconcile();
              ref.invalidate(summaryHistoryProvider);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Text AI tasks stay on this phone. Accepted work can continue on your computer while Journal is closed. Leaving a screen does not cancel it.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Results expire within 24 hours of the request. Clear preview acknowledges a result and removes its desktop text when connected. Local status receipts remain for seven days.',
          ),
          const SizedBox(height: 16),
          if (current.phase == 'storageError')
            ListTile(
              title: const Text('Saved request needs attention'),
              subtitle: Text(current.message ?? 'Unlock the phone and retry.'),
              onTap: () => _open(context),
            ),
          ...history.when(
            loading: () => [const LinearProgressIndicator()],
            error: (_, _) => [
              const Text(
                'Could not read local history. Unlock your phone and refresh.',
              ),
            ],
            data: (tasks) => tasks.isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No note AI tasks yet. Open a saved note for a summary or writing help.',
                      ),
                    ),
                  ]
                : tasks.map((task) {
                    final active = current.handle?.id == task.id;
                    final phase = task.expired && !task.acknowledged
                        ? 'expired'
                        : active &&
                              ![
                                'error',
                                'retrieving',
                                'storageError',
                              ].contains(current.phase)
                        ? current.phase
                        : task.phase;
                    final owner = computers
                        .where((c) => c.id == task.computerId)
                        .firstOrNull;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${task.isDiarySuggestion
                                  ? 'Diary details'
                                  : task.isDailyQuestion
                                  ? 'Daily question'
                                  : task.isDiaryAnswer
                                  ? 'Diary question'
                                  : task.isPresentation
                                  ? 'Presentation'
                                  : transformOperations[task.operation] ?? 'Note summary'} · ${summaryPhaseLabel(phase)}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${DateFormat.yMMMd().add_jm().format(DateTime.fromMillisecondsSinceEpoch(task.created))} · ${owner?.name ?? 'Original computer unavailable'}',
                            ),
                            Text('Task ${task.id.substring(0, 8)}'),
                            if (active && current.message != null)
                              Text(current.message!),
                            if (task.acknowledged)
                              const Text(
                                'Result acknowledged; desktop text removed.',
                              ),
                            if (task.ackPending && !task.expired) ...[
                              const Text(
                                'Desktop removal pending. Reconnect to the original computer or let retention expire.',
                              ),
                              TextButton(
                                onPressed: () => ref
                                    .read(noteSummaryProvider.notifier)
                                    .acknowledge(task),
                                child: const Text(
                                  'Retry result acknowledgment',
                                ),
                              ),
                            ],
                            if (active)
                              TextButton.icon(
                                onPressed: () => _open(
                                  context,
                                  transformation: task.isTransformation,
                                  presentation: task.isPresentation,
                                  diaryDate: task.isDiarySuggestion
                                      ? task.noteId
                                      : null,
                                ),
                                icon: const Icon(Icons.restore),
                                label: const Text('Open / recover task'),
                              ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CompanionPage()),
            ),
            child: const Text('Computer connection settings'),
          ),
        ],
      ),
    );
  }

  void _open(
    BuildContext context, {
    bool transformation = false,
    bool presentation = false,
    String? diaryDate,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => diaryDate != null
          ? DiaryDetailsPage(dateString: diaryDate)
          : presentation
          ? const PresentationPage()
          : transformation
          ? const NoteTransformPage()
          : const NoteSummaryPage(),
    ),
  );
}
