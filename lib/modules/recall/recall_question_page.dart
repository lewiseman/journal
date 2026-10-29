import 'package:journal/common.dart';
import 'package:journal/modules/recall/recall_question_contract.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/summary/summary_history_page.dart';
import 'package:journal/modules/notes/summary/summary_page.dart';
import 'package:journal/modules/diary/history/diary_retrieval.dart'
    show civil, civilKey;
import 'package:journal/modules/notes/views/widgets/note_ai_loading.dart';
import 'package:journal/modules/notes/views/widgets/note_ai_widgets.dart';
import 'package:journal/modules/recall/hybrid_retriever.dart';
import 'package:journal/modules/recall/recall_contract.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';

/// S02: ask a question about saved notes or Flow thoughts. The most relevant
/// ones are found on the phone and sent as bounded excerpts. A cited note opens
/// in the editor; a cited thought pops this page with it. With a question task
/// of the same [kind] in the slot it shows that task.
class RecallQuestionPage extends ConsumerStatefulWidget {
  const RecallQuestionPage({super.key, required this.kind, this.today});

  /// [RecallKind.note] or [RecallKind.thought].
  final RecallKind kind;

  /// The user's current civil date; defaults to the device's local date.
  final DateTime? today;

  @override
  ConsumerState<RecallQuestionPage> createState() => _RecallQuestionPageState();
}

class _RecallQuestionPageState extends ConsumerState<RecallQuestionPage> {
  final _question = TextEditingController();
  bool _searching = false;
  String? _localMessage;

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    FocusScope.of(context).unfocus();
    final question = _question.text;
    final today = widget.today ?? DateTime.now();
    final kind = widget.kind;
    final (items, sources) = _collection();
    RecallQuestionSelection selection;
    try {
      selection = RecallQuestionSelection.select(
        kind: kind,
        question: question,
        today: today,
        items: items,
      );
    } on FormatException catch (error) {
      setState(() => _localMessage = error.message);
      return;
    }
    setState(() {
      _searching = true;
      _localMessage = null;
    });
    final (:terms, :scope, today: t) = RecallQuestionSelection.parse(
      question,
      today,
    );
    if (terms.isNotEmpty) {
      // Keywords and meaning together; keyword ranking stays the fallback.
      final result = await ref
          .read(hybridRetrieverProvider)
          .search(
            question,
            sources: sources,
            kinds: {kind},
            terms: terms,
            from: scope == null ? null : civilKey(scope.from),
            to: civilKey(scope?.to ?? t),
            limit: 24,
          );
      if (!mounted) return;
      if (result.semantic) {
        selection = RecallQuestionSelection.select(
          kind: kind,
          question: question,
          today: today,
          items: items,
          ranked: [for (final h in result.hits) h.source.id],
        );
      }
    }
    if (!mounted) return;
    if (!selection.sendable) {
      setState(() {
        _searching = false;
        _localMessage = terms.isEmpty && scope == null
            ? 'Add a topic or a time, such as “recipes” or “last month”.'
            : 'No ${kind.many} match this question, so nothing was sent.';
      });
      return;
    }
    await ref.read(noteSummaryProvider.notifier).startRecallQuestion(selection);
    if (mounted) setState(() => _searching = false);
  }

  /// The searchable items of [RecallQuestionPage.kind], and the same as
  /// retriever sources.
  (List<RecallItem>, Iterable<RecallSource>) _collection() {
    if (widget.kind == RecallKind.note) {
      final notes = ref.read(notesStreamProvider).value ?? const <NoteEntity>[];
      return (RecallItem.notes(notes), RecallSource.notes(notes));
    }
    final thoughts =
        ref.read(thoughtsStreamProvider).value ?? const <ThoughtEntity>[];
    return (RecallItem.thoughts(thoughts), RecallSource.thoughts(thoughts));
  }

  void _open(RecallQuestionSource source) {
    if (widget.kind == RecallKind.note) {
      final note = ref.read(notesRepositoryProvider).getNoteByUuid(source.uuid);
      if (note != null) context.nav.push(EditNotePage(existingNote: note));
      return;
    }
    final thought = ref
        .read(thoughtsRepositoryProvider)
        .getThoughtByUuid(source.uuid);
    if (thought != null) Navigator.of(context).pop(thought);
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(accountResetProvider).blocksDataAccess) {
      return const Scaffold(
        body: Center(child: Text('Account reset in progress.')),
      );
    }
    final kind = widget.kind;
    final tool = kind == RecallKind.note
        ? NoteAiTool.search
        : NoteAiTool.thoughtSearch;
    ref.watch(
      kind == RecallKind.note ? notesStreamProvider : thoughtsStreamProvider,
    );
    final state = ref.watch(noteSummaryProvider);
    final controller = ref.read(noteSummaryProvider.notifier);
    final handle = state.handle;
    final mine = handle?.operation == kind.questionOperation;
    RecallQuestionSelection? selection;
    if (mine && handle?.localSource != null) {
      try {
        selection = RecallQuestionSelection.decode(handle!.localSource!);
      } on FormatException {
        selection = null;
      }
    }
    final loading =
        _searching || (mine && noteAiIsLoading(state.phase, busy: state.busy));
    final answered = mine && state.phase == 'completed' && state.text != null;
    return NoteAiScaffold(
      tool: tool,
      loading: loading
          ? NoteAiLoading(
              tool: tool,
              phase: _searching ? 'submitting' : state.phase,
              onCancel: mine && !state.busy && !state.terminal
                  ? controller.cancel
                  : null,
            )
          : null,
      step: answered
          ? 2
          : mine
          ? 1
          : 0,
      children: [
        if (handle != null && !mine)
          ..._otherTask(context)
        else if (!mine)
          ..._askBody(context, state)
        else if (selection != null)
          ..._taskBody(context, state, selection, controller)
        else
          const Text('This question could not be read. Clear it to ask again.'),
        const SizedBox(height: 12),
      ],
    );
  }

  List<Widget> _otherTask(BuildContext context) => [
    Text(
      'Another AI task is in progress. Finish or clear it before asking about your ${widget.kind.many}.',
      key: const ValueKey('recall-question-occupied'),
    ),
    TextButton(
      onPressed: () => context.nav.push(const NoteSummaryPage()),
      child: const Text('Open the current task'),
    ),
  ];

  List<Widget> _askBody(BuildContext context, NoteSummaryState state) {
    final name =
        ref.watch(companionControllerProvider).selected?.name ??
        'your paired computer';
    final caption = Theme.of(context).textTheme.bodySmall!
        .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final message = _localMessage ?? state.message;
    return [
      TextField(
        key: const ValueKey('recall-question-field'),
        controller: _question,
        maxLength: recallQuestionChars,
        minLines: 1,
        maxLines: 4,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _ask(),
        decoration: InputDecoration(
          labelText: 'Ask about your ${widget.kind.many}',
          hintText: widget.kind == RecallKind.note
              ? 'For example: what did I plan for the garden?'
              : 'For example: what have I been worrying about?',
        ),
      ),
      Text(
        'Your question and short excerpts from the most relevant ${widget.kind.many} are sent to $name. Nothing else from your ${widget.kind.many} is sent.',
        key: const ValueKey('recall-question-disclosure'),
        style: caption,
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        key: const ValueKey('recall-question-ask'),
        onPressed: state.busy ? null : _ask,
        icon: const Icon(Icons.search_rounded),
        label: const Text('Ask'),
      ),
      if (message != null) ...[
        const SizedBox(height: 12),
        Text(message, key: const ValueKey('recall-question-message')),
      ],
      const SizedBox(height: 12),
      TextButton(
        onPressed: () => context.nav.push(const SummaryHistoryPage()),
        child: const Text('AI task history'),
      ),
    ];
  }

  List<Widget> _taskBody(
    BuildContext context,
    NoteSummaryState state,
    RecallQuestionSelection selection,
    NoteSummaryController controller,
  ) {
    final kind = widget.kind;
    final theme = Theme.of(context);
    final caption = theme.textTheme.bodySmall!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    RecallItem? lookup(String uuid) => controller.recallItem(kind, uuid);
    RecallQuestionAnswer? answer;
    String? rejected;
    if (state.phase == 'completed' && state.text != null) {
      try {
        answer = RecallQuestionAnswer.parse(state.text!, selection);
      } on RecallAnswerRejected catch (error) {
        rejected = error.message;
      } catch (_) {
        rejected =
            'Your computer returned something that was not a usable answer.';
      }
    }
    return [
      Text('“${selection.question}”', style: theme.textTheme.titleLarge),
      const SizedBox(height: 8),
      Text(
        selection.coverage,
        key: const ValueKey('recall-question-coverage'),
        style: caption,
      ),
      const SizedBox(height: 16),
      if (answer == null)
        Text(
          rejected ?? summaryPhaseLabel(state.phase),
          key: const ValueKey('recall-question-phase'),
        ),
      if (answer == null && state.message != null) ...[
        const SizedBox(height: 8),
        Text(state.message!),
      ],
      if (answer != null && !answer.answered)
        Text(
          'Your ${kind.many} don’t have enough to answer this. Try asking another way.',
          key: const ValueKey('recall-question-insufficient'),
        ),
      if (answer != null && answer.answered) ...[
        Text(
          answer.text,
          key: const ValueKey('recall-question-answer'),
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 8),
        Text(
          kind == RecallKind.note ? 'Based only on these notes.' : 'Based only on these thoughts. Links between them are the AI’s reading, not something you wrote.',
          style: caption,
        ),
        const SizedBox(height: 8),
        for (final source in answer.citations)
          _SourceTile(
            kind: kind,
            source: source,
            status: recallSourceStatus(source, lookup),
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
            FilledButton(
              key: const ValueKey('recall-question-clear'),
              onPressed: state.busy
                  ? null
                  : () async {
                      await controller.clear();
                      if (mounted) setState(() => _localMessage = null);
                    },
              child: const Text('Ask another question'),
            ),
        ],
      ),
    ];
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.kind,
    required this.source,
    required this.status,
    required this.onOpen,
  });
  final RecallKind kind;
  final RecallQuestionSource source;
  final RecallSourceStatus status;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      key: ValueKey('recall-question-source-${source.uuid}'),
      title: Text(
        kind == RecallKind.thought
            ? TimeHelper.format(
                civil(source.date),
                pattern: TimeFormat.localizedDate,
                locale: Localizations.localeOf(context).toString(),
                toLocal: false,
              )
            : source.title.isEmpty
            ? 'Untitled'
            : source.title,
      ),
      subtitle: Text(
        [
          if (source.text.isNotEmpty) source.text,
          if (status == RecallSourceStatus.edited)
            'Edited since this answer. Open the ${kind.one} to check.',
          if (status == RecallSourceStatus.deleted)
            'This ${kind.one} is no longer in your ${kind.many}.',
        ].join('\n'),
      ),
      trailing: status == RecallSourceStatus.deleted
          ? null
          : const Icon(Icons.north_east_rounded),
      onTap: status == RecallSourceStatus.deleted ? null : onOpen,
    ),
  );
}
