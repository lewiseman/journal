import 'package:journal/common.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/summary/summary_history_page.dart';

/// Recovery view for a daily-question task in the shared AI task slot. A
/// completed question is moved to today's diary page automatically.
class DailyQuestionTaskPage extends ConsumerWidget {
  const DailyQuestionTaskPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(noteSummaryProvider);
    final controller = ref.read(noteSummaryProvider.notifier);
    final handle = state.handle;
    return Scaffold(
      appBar: AppBar(title: const Text('Daily question')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (handle?.isDailyQuestion != true)
            const Text(
              'No daily question is being asked. Open today in your diary to ask one.',
            )
          else ...[
            Text(summaryPhaseLabel(state.phase)),
            if (state.message != null) ...[
              const SizedBox(height: 12),
              Text(state.message!),
            ],
            const SizedBox(height: 12),
            const Text(
              'A finished question appears on today’s diary page. Writing never waits for it.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: [
                if (!state.terminal || state.phase == 'error')
                  TextButton(
                    onPressed: state.busy ? null : controller.retry,
                    child: const Text('Retrieve / retry'),
                  ),
                if (!state.terminal)
                  TextButton(
                    onPressed: state.busy ? null : controller.cancel,
                    child: const Text('Cancel request'),
                  ),
                if (state.terminal)
                  TextButton(
                    onPressed: state.busy ? null : controller.clear,
                    child: const Text('Clear'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
