import 'package:journal/common.dart';
import 'package:journal/modules/diary/history/diary_history_contract.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/summary/summary_history_page.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';

/// S01: answers one question about the past from selected diary excerpts.
/// Shows what will be sent before sending. Opening a source pops with its
/// civil date. Without [question] it shows the recoverable task in the slot.
class DiaryAnswerPage extends ConsumerStatefulWidget {
  const DiaryAnswerPage({super.key, this.question, this.today});

  final String? question;

  /// The user's current civil date; defaults to the device's local date.
  final DateTime? today;

  @override
  ConsumerState<DiaryAnswerPage> createState() => _DiaryAnswerPageState();
}

class _DiaryAnswerPageState extends ConsumerState<DiaryAnswerPage> {
  DiaryHistorySelection? _preview;
  String? _previewError;

  @override
  void initState() {
    super.initState();
    final question = widget.question;
    if (question == null) return;
    try {
      _preview = DiaryHistorySelection.select(
        question: question,
        today: widget.today ?? DateTime.now(),
        days: ref.read(diaryRepositoryProvider).getAllDays(),
      );
    } on FormatException catch (error) {
      _previewError = error.message;
    }
  }

  void _open(DiaryHistorySource source) =>
      Navigator.of(context).pop<DateTime>(civil(source.date));

  @override
  Widget build(BuildContext context) {
    ref.watch(diaryDaysProvider);
    final state = ref.watch(noteSummaryProvider);
    final controller = ref.read(noteSummaryProvider.notifier);
    final handle = state.handle;
    final active = handle?.isDiaryAnswer == true;
    final occupied = handle != null && !active;
    DiaryHistorySelection? selection;
    final local = active ? handle?.localSource : null;
    if (local != null) {
      try {
        selection = DiaryHistorySelection.decode(local);
      } on FormatException {
        selection = null;
      }
    }
    selection ??= _preview;
    final caption = Theme.of(context).textTheme.bodySmall!
        .copyWith(color: context.colors.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: const Text('Ask your diary')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (selection != null)
            Text(
              '“${selection.question}”',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          if (_previewError != null && !active) Text(_previewError!),
          const SizedBox(height: 12),
          if (selection != null)
            Text(
              selection.coverage,
              key: const ValueKey('diary-answer-coverage'),
              style: caption,
            ),
          const SizedBox(height: 16),
          if (occupied)
            const Text(
              'Another AI task is in progress. Finish or clear it in AI task history first. Keyword search still works.',
            )
          else if (!active && selection != null)
            ..._previewBody(context, selection, controller, caption)
          else if (active && selection != null)
            ..._taskBody(context, state, selection, controller, caption)
          else if (widget.question == null)
            const Text('No diary question is being answered.'),
        ],
      ),
    );
  }

  List<Widget> _previewBody(
    BuildContext context,
    DiaryHistorySelection selection,
    NoteSummaryController controller,
    TextStyle caption,
  ) {
    if (!selection.sendable) {
      return [
        Text(
          selection.scope == null &&
                  selection.matching == 0 &&
                  diaryTerms(selection.question).isEmpty
              ? 'Add a topic or a time, such as “this time last year” or “the pottery class”.'
              : 'No entries ${selection.scope == null ? 'in your diary' : 'in this period'} match this question, so nothing was sent.',
          key: const ValueKey('diary-answer-no-match'),
        ),
      ];
    }
    final name =
        ref.watch(companionControllerProvider).selected?.name ??
        'your paired computer';
    final message = ref.watch(noteSummaryProvider).message;
    return [
      Text(
        'These excerpts would be sent to $name, and nothing else from your diary:',
        style: caption,
      ),
      const SizedBox(height: 8),
      for (final source in selection.sources)
        _SourceTile(source: source, onOpen: () => _open(source)),
      const SizedBox(height: 12),
      FilledButton(
        key: const ValueKey('diary-answer-send'),
        onPressed: () => controller.startDiaryAnswer(selection),
        child: Text(
          'Ask using ${selection.sources.length == 1 ? '1 excerpt' : '${selection.sources.length} excerpts'}',
        ),
      ),
      if (message != null) ...[
        const SizedBox(height: 12),
        Text(message, key: const ValueKey('diary-answer-message')),
      ],
    ];
  }

  List<Widget> _taskBody(
    BuildContext context,
    NoteSummaryState state,
    DiaryHistorySelection selection,
    NoteSummaryController controller,
    TextStyle caption,
  ) {
    final day = ref.read(diaryRepositoryProvider).getDay;
    DiaryHistoryAnswer? answer;
    String? rejected;
    if (state.phase == 'completed' && state.text != null) {
      try {
        answer = DiaryHistoryAnswer.parse(state.text!, selection);
      } on DiaryAnswerRejected catch (error) {
        rejected = error.message;
      } catch (_) {
        rejected =
            'Your computer returned something that was not a usable answer.';
      }
    }
    return [
      if (answer == null)
        Text(
          rejected ?? summaryPhaseLabel(state.phase),
          key: const ValueKey('diary-answer-phase'),
        ),
      if (answer == null && state.message != null) ...[
        const SizedBox(height: 8),
        Text(state.message!),
      ],
      if (answer != null && !answer.answered)
        Text(
          'Not enough in your diary to answer this. ${answer.text} Try other words or a different time.',
          key: const ValueKey('diary-answer-insufficient'),
        ),
      if (answer != null && answer.answered) ...[
        Text(
          answer.text,
          key: const ValueKey('diary-answer-text'),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Based only on the entries below. Dates show when you wrote, which may not be when something happened or began.',
          style: caption,
        ),
        const SizedBox(height: 12),
        for (final source in answer.citations)
          _SourceTile(
            source: source,
            status: sourceStatus(source, day),
            onOpen: () => _open(source),
          ),
      ],
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
              child: const Text('Cancel'),
            ),
          if (state.terminal)
            TextButton(
              key: const ValueKey('diary-answer-clear'),
              onPressed: state.busy ? null : controller.clear,
              child: const Text('Clear answer'),
            ),
        ],
      ),
    ];
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.source,
    required this.onOpen,
    this.status = DiarySourceStatus.current,
  });
  final DiaryHistorySource source;
  final DiarySourceStatus status;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => ListTile(
    key: ValueKey('diary-answer-source-${source.uuid}'),
    contentPadding: EdgeInsets.zero,
    title: Text(
      TimeHelper.format(
        civil(source.date),
        pattern: TimeFormat.localizedDate,
        locale: Localizations.localeOf(context).toString(),
        toLocal: false,
      ),
    ),
    subtitle: Text(
      [
        source.text,
        if (status == DiarySourceStatus.edited)
          'Edited since this answer. Open the day to check.',
        if (status == DiarySourceStatus.deleted)
          'This entry is no longer in your diary.',
      ].join('\n'),
    ),
    trailing: status == DiarySourceStatus.deleted
        ? null
        : const Icon(Icons.north_east_rounded),
    onTap: status == DiarySourceStatus.deleted ? null : onOpen,
  );
}
