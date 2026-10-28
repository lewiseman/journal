import 'package:journal/common.dart';
import 'package:journal/modules/flow/reflection/thought_reflection_controller.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/summary/summary_history_page.dart';

/// Recovery view for a Flow reflection in the shared AI task slot. A
/// finished reflection moves to its thought, where it can be kept.
class ThoughtReflectionTaskPage extends ConsumerWidget {
  const ThoughtReflectionTaskPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Built so that a finished result is moved to its thought.
    ref.watch(thoughtReflectionProvider);
    final state = ref.watch(noteSummaryProvider);
    final controller = ref.read(noteSummaryProvider.notifier);
    final handle = state.handle;
    return Scaffold(
      appBar: AppBar(title: const Text('Flow reflection')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (handle?.isThoughtReflection != true)
            const Text(
              'No reflection is being written. Open a thought in Flow to ask for one.',
            )
          else ...[
            Text(summaryPhaseLabel(state.phase)),
            if (state.message != null) ...[
              const SizedBox(height: 12),
              Text(state.message!),
            ],
            const SizedBox(height: 12),
            const Text(
              'A finished reflection appears under its thought in Flow for you to keep or dismiss. Your thought is never changed.',
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
