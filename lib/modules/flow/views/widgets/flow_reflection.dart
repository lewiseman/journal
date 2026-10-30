import 'package:journal/common.dart';
import 'package:journal/modules/flow/reflection/thought_reflection_controller.dart';
import 'package:journal/modules/flow/reflection/thought_reflection_entity.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';

/// L01: the optional reflection under an opened thought. It is a separate,
/// reviewable line; the thought above it is never edited.
class FlowReflection extends ConsumerWidget {
  const FlowReflection({super.key, required this.thought, required this.paper});

  final ThoughtEntity thought;
  final NoteColors paper;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(thoughtReflectionAvailableProvider)) {
      return const SizedBox.shrink();
    }
    ref.watch(thoughtReflectionProvider);
    final controller = ref.read(thoughtReflectionProvider.notifier);
    final summary = ref.watch(noteSummaryProvider);
    final view = controller.view(thought);
    final message = controller.messageFor(thought);
    final working = controller.working(thought, summary);
    final caption = TextStyle(
      color: paper.secondary,
      fontSize: 10,
      letterSpacing: 1.8,
    );
    final quiet = TextStyle(color: paper.secondary, fontSize: 12, height: 1.4);
    Widget line(ThoughtReflectionEntity row) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SelectableText(
        row.text,
        key: ValueKey('flow-reflection-${row.status}'),
        style: TextStyle(
          color: paper.foreground,
          fontSize: 16,
          height: 1.45,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
    final button = TextButton.styleFrom(
      foregroundColor: paper.foreground,
      padding: const EdgeInsets.symmetric(horizontal: 8),
    );
    final proposal = view.proposal, kept = view.kept;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: paper.secondary.withValues(alpha: .2)),
        const SizedBox(height: 8),
        if (kept != null) ...[
          Text('YOUR KEPT REFLECTION', style: caption),
          line(kept),
          if (proposal == null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                style: button,
                onPressed: () => controller.remove(kept),
                child: const Text('Remove reflection'),
              ),
            ),
          const SizedBox(height: 12),
        ],
        if (proposal != null) ...[
          Text('SUGGESTED REFLECTION · NOT KEPT YET', style: caption),
          line(proposal),
          if (kept != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Keeping it replaces your kept reflection.',
                style: quiet,
              ),
            ),
          Wrap(
            spacing: 4,
            children: [
              TextButton(
                key: const ValueKey('flow-reflection-keep'),
                style: button,
                onPressed: () => controller.keep(proposal),
                child: const Text('Keep'),
              ),
              TextButton(
                key: const ValueKey('flow-reflection-dismiss'),
                style: button,
                onPressed: () => controller.remove(proposal),
                child: const Text('Dismiss'),
              ),
            ],
          ),
        ] else if (working &&
            !summary.terminal &&
            summary.phase != 'error') ...[
          Text(
            'Your computer is reflecting on this thought. You can close this; your thought is already saved.',
            style: quiet,
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              style: button,
              onPressed: summary.busy
                  ? null
                  : ref.read(noteSummaryProvider.notifier).cancel,
              child: const Text('Cancel'),
            ),
          ),
        ] else if (working && summary.phase == 'error') ...[
          Text(
            summary.message ?? 'Could not reach your computer.',
            style: quiet,
          ),
          Wrap(
            spacing: 4,
            children: [
              TextButton(
                style: button,
                onPressed: summary.busy
                    ? null
                    : ref.read(noteSummaryProvider.notifier).retry,
                child: const Text('Retry'),
              ),
              TextButton(
                style: button,
                onPressed: summary.busy
                    ? null
                    : ref.read(noteSummaryProvider.notifier).cancel,
                child: const Text('Cancel'),
              ),
            ],
          ),
        ] else ...[
          if (message != null) ...[
            Text(
              message,
              key: const ValueKey('flow-reflection-message'),
              style: quiet,
            ),
            const SizedBox(height: 4),
          ],
          Center(
            child: TextButton(
              key: const ValueKey('flow-reflect'),
              style: button.copyWith(
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              onPressed: summary.busy && working
                  ? null
                  : () => controller.request(thought),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/flow_reflect.png',
                    width: 72,
                    height: 72,
                    filterQuality: FilterQuality.high,
                    excludeFromSemantics: true,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    kept == null ? 'Reflect on this' : 'Reflect again',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
