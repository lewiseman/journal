import 'package:journal/common.dart';
import 'package:journal/modules/notes/question/note_question_contract.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/summary/summary_history_page.dart';
import 'package:journal/modules/notes/summary/summary_page.dart';
import 'package:journal/modules/diary/history/diary_retrieval.dart'
    show civilKey;
import 'package:journal/modules/notes/views/widgets/note_ai_loading.dart';
import 'package:journal/modules/notes/views/widgets/note_ai_widgets.dart';
import 'package:journal/modules/recall/hybrid_retriever.dart';
import 'package:journal/modules/recall/recall_contract.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';

/// S02 (notes): ask a question about saved notes. The most relevant notes are
/// found on the phone and sent as bounded excerpts; the cited notes open.
/// With a note-question task in the slot it shows that task.
class NoteQuestionPage extends ConsumerStatefulWidget {
  const NoteQuestionPage({super.key, this.today});

  /// The user's current civil date; defaults to the device's local date.
  final DateTime? today;

  @override
  ConsumerState<NoteQuestionPage> createState() => _NoteQuestionPageState();
}

class _NoteQuestionPageState extends ConsumerState<NoteQuestionPage> {
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
    final notes = ref.read(notesStreamProvider).value ?? const <NoteEntity>[];
    NoteQuestionSelection selection;
    try {
      selection = NoteQuestionSelection.select(
        question: question,
        today: today,
        notes: notes,
      );
    } on FormatException catch (error) {
      setState(() => _localMessage = error.message);
      return;
    }
    setState(() {
      _searching = true;
      _localMessage = null;
    });
    final (:terms, :scope, today: t) = NoteQuestionSelection.parse(
      question,
      today,
    );
    if (terms.isNotEmpty) {
      // Keywords and meaning together; keyword ranking stays the fallback.
      final result = await ref
          .read(hybridRetrieverProvider)
          .search(
            question,
            sources: RecallSource.notes(notes),
            kinds: const {RecallKind.note},
            terms: terms,
            from: scope == null ? null : civilKey(scope.from),
            to: civilKey(scope?.to ?? t),
            limit: 24,
          );
      if (!mounted) return;
      if (result.semantic) {
        selection = NoteQuestionSelection.select(
          question: question,
          today: today,
          notes: notes,
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
            : 'No notes match this question, so nothing was sent.';
      });
      return;
    }
    await ref.read(noteSummaryProvider.notifier).startNoteQuestion(selection);
    if (mounted) setState(() => _searching = false);
  }

  void _open(NoteQuestionSource source) {
    final note = ref.read(notesRepositoryProvider).getNoteByUuid(source.uuid);
    if (note == null) return;
    context.nav.push(EditNotePage(existingNote: note));
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(accountResetProvider).blocksDataAccess) {
      return const Scaffold(
        body: Center(child: Text('Account reset in progress.')),
      );
    }
    ref.watch(notesStreamProvider);
    final state = ref.watch(noteSummaryProvider);
    final controller = ref.read(noteSummaryProvider.notifier);
    final handle = state.handle;
    final mine = handle?.isNoteQuestion == true;
    NoteQuestionSelection? selection;
    if (mine && handle?.localSource != null) {
      try {
        selection = NoteQuestionSelection.decode(handle!.localSource!);
      } on FormatException {
        selection = null;
      }
    }
    final loading =
        _searching || (mine && noteAiIsLoading(state.phase, busy: state.busy));
    final answered = mine && state.phase == 'completed' && state.text != null;
    return NoteAiScaffold(
      tool: NoteAiTool.search,
      loading: loading
          ? NoteAiLoading(
              tool: NoteAiTool.search,
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
    const Text(
      'Another AI task is in progress. Finish or clear it before asking about your notes. Keyword search on the Notes page still works.',
      key: ValueKey('note-question-occupied'),
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
        key: const ValueKey('note-question-field'),
        controller: _question,
        maxLength: noteQuestionChars,
        minLines: 1,
        maxLines: 4,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _ask(),
        decoration: const InputDecoration(
          labelText: 'Ask about your notes',
          hintText: 'For example: what did I plan for the garden?',
        ),
      ),
      Text(
        'Your question and short excerpts from the most relevant notes are sent to $name. Nothing else from your notes is sent.',
        key: const ValueKey('note-question-disclosure'),
        style: caption,
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        key: const ValueKey('note-question-ask'),
        onPressed: state.busy ? null : _ask,
        icon: const Icon(Icons.search_rounded),
        label: const Text('Ask'),
      ),
      if (message != null) ...[
        const SizedBox(height: 12),
        Text(message, key: const ValueKey('note-question-message')),
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
    NoteQuestionSelection selection,
    NoteSummaryController controller,
  ) {
    final theme = Theme.of(context);
    final caption = theme.textTheme.bodySmall!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final lookup = ref.read(notesRepositoryProvider).getNoteByUuid;
    NoteQuestionAnswer? answer;
    String? rejected;
    if (state.phase == 'completed' && state.text != null) {
      try {
        answer = NoteQuestionAnswer.parse(state.text!, selection);
      } on NoteAnswerRejected catch (error) {
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
        key: const ValueKey('note-question-coverage'),
        style: caption,
      ),
      const SizedBox(height: 16),
      if (answer == null)
        Text(
          rejected ?? summaryPhaseLabel(state.phase),
          key: const ValueKey('note-question-phase'),
        ),
      if (answer == null && state.message != null) ...[
        const SizedBox(height: 8),
        Text(state.message!),
      ],
      if (answer != null && !answer.answered)
        Text(
          'Your notes don’t have enough to answer this. Try asking another way.',
          key: const ValueKey('note-question-insufficient'),
        ),
      if (answer != null && answer.answered) ...[
        Text(
          answer.text,
          key: const ValueKey('note-question-answer'),
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 8),
        Text('Based only on these notes.', style: caption),
        const SizedBox(height: 8),
        for (final source in answer.citations)
          _SourceTile(
            source: source,
            status: noteSourceStatus(source, lookup),
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
              key: const ValueKey('note-question-clear'),
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
    required this.source,
    required this.status,
    required this.onOpen,
  });
  final NoteQuestionSource source;
  final NoteSourceStatus status;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      key: ValueKey('note-question-source-${source.uuid}'),
      title: Text(source.title.isEmpty ? 'Untitled' : source.title),
      subtitle: Text(
        [
          if (source.text.isNotEmpty) source.text,
          if (status == NoteSourceStatus.edited)
            'Edited since this answer. Open the note to check.',
          if (status == NoteSourceStatus.deleted)
            'This note is no longer in your notes.',
        ].join('\n'),
      ),
      trailing: status == NoteSourceStatus.deleted
          ? null
          : const Icon(Icons.north_east_rounded),
      onTap: status == NoteSourceStatus.deleted ? null : onOpen,
    ),
  );
}
