import 'package:journal/common.dart';
import 'package:journal/modules/recall/recall_contract.dart';
import 'package:journal/modules/recall/recall_indexer.dart';

/// S03b opt-ins in Settings → Local QVAC: one switch per collection, the
/// indexing progress, and pause/resume.
class RecallSettings extends ConsumerWidget {
  const RecallSettings({super.key});

  static const _labels = {
    RecallKind.diary: ('Diary entries', 'Every diary entry you have written.'),
    RecallKind.note: ('Notes', 'Note titles and text, not attachments.'),
    RecallKind.thought: ('Flow thoughts', 'Every saved thought.'),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(recallIndexerProvider);
    final indexer = ref.read(recallIndexerProvider.notifier);
    final caption = Theme.of(context).textTheme.bodySmall!
        .copyWith(color: context.colors.onSurfaceVariant);
    return Column(
      key: const ValueKey('recall-settings'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Search by meaning',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        const Text(
          'Find diary entries, notes and thoughts by what they mean, not only the words you remember. '
          'Turning a collection on sends all of its text to your paired computer, in small batches, '
          'so its embedding model can index it. The resulting vectors stay on this phone; the computer '
          'keeps none of the text once each batch is collected. Turning a collection off deletes its vectors.',
        ),
        for (final kind in RecallKind.values)
          SwitchListTile(
            key: ValueKey('recall-${kind.name}'),
            contentPadding: EdgeInsets.zero,
            title: Text(_labels[kind]!.$1),
            subtitle: Text(
              state.enabled.contains(kind)
                  ? '${_labels[kind]!.$2} ${state.indexed[kind] ?? 0} indexed.'
                  : _labels[kind]!.$2,
            ),
            value: state.enabled.contains(kind),
            onChanged: (value) => indexer.setEnabled(kind, value),
          ),
        if (state.enabled.isNotEmpty) ...[
          if (state.running) ...[
            LinearProgressIndicator(
              value: state.total == 0 ? null : state.done / state.total,
            ),
            const SizedBox(height: 6),
            Text(
              'Indexing ${state.done} of ${state.total}…',
              key: const ValueKey('recall-progress'),
              style: caption,
            ),
          ] else if (state.paused)
            Text('Indexing is paused.', style: caption)
          else if (state.message == null)
            Text(
              'Up to date.',
              key: const ValueKey('recall-progress'),
              style: caption,
            ),
          if (state.message != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(state.message!, style: caption),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('recall-pause'),
              onPressed: state.paused ? indexer.resume : indexer.pause,
              child: Text(state.paused ? 'Resume indexing' : 'Pause indexing'),
            ),
          ),
        ],
      ],
    );
  }
}
