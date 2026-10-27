import 'package:journal/common.dart';
import 'package:journal/modules/diary/questions/daily_question_contract.dart';
import 'package:journal/modules/diary/questions/daily_question_controller.dart';
import 'package:journal/modules/diary/views/widgets/diary_writing_prompt.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';

/// Today's writing invitation. With daily questions off it is exactly the
/// plain prompt. With them on, the user can ask for, skip or replace one
/// question; writing never waits for the computer.
class DailyQuestionPrompt extends ConsumerWidget {
  const DailyQuestionPrompt({
    super.key,
    required this.day,
    required this.onWrite,
  });

  /// Civil date key ("YYYY-MM-DD") of today.
  final String day;
  final VoidCallback onWrite;

  static String sourceLabel(DailyQuestion question) => !question.grounded
      ? 'A general question to help you start.'
      : switch (question.ago) {
          0 => 'Following up on something you wrote earlier today.',
          1 => 'Following up on your entry from yesterday.',
          final ago => 'Following up on your entry from $ago days ago.',
        };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Opted out: nothing AI-related is built or watched.
    if (!ref.watch(dailyQuestionEnabledProvider)) {
      return DiaryWritingPrompt(onTap: onWrite);
    }
    final state = ref.watch(dailyQuestionProvider);
    final controller = ref.read(dailyQuestionProvider.notifier);
    ref.watch(diaryDaysProvider);
    final summary = ref.watch(noteSummaryProvider);
    final view = controller.current(day);
    final asking =
        summary.handle?.isDailyQuestion == true &&
        (!summary.terminal || summary.busy);
    final occupied =
        summary.handle != null && summary.handle?.isDailyQuestion != true;
    final caption = Theme.of(context).textTheme.bodySmall!
        .copyWith(color: context.colors.onSurfaceVariant);
    final selection = view == null && !asking
        ? controller.selection(day)
        : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DiaryWritingPrompt(
          onTap: onWrite,
          text: view?.question.text ?? DiaryWritingPrompt.question,
        ),
        const SizedBox(height: 4),
        if (asking)
          Text(
            'Asking your computer for a question. You can start writing now.',
            key: const ValueKey('daily-question-asking'),
            style: caption,
          )
        else if (view != null) ...[
          Text(
            sourceLabel(view.question),
            key: const ValueKey('daily-question-source'),
            style: caption,
          ),
          if (state.message != null)
            Text(
              state.message!,
              key: const ValueKey('daily-question-message'),
              style: caption,
            ),
        ] else if (state.message != null)
          Text(
            '${state.message} The usual prompt is shown instead.',
            key: const ValueKey('daily-question-message'),
            style: caption,
          )
        else if (occupied)
          Text(
            'Another AI task is in progress. Finish it to ask a question.',
            style: caption,
          ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          children: [
            if (view != null) ...[
              TextButton(
                key: const ValueKey('daily-question-skip'),
                onPressed: () => controller.skip(view),
                child: const Text('Skip'),
              ),
              TextButton(
                key: const ValueKey('daily-question-another'),
                onPressed: occupied || asking
                    ? null
                    : () => controller.regenerate(day, view),
                child: const Text('Another question'),
              ),
            ] else if (asking)
              TextButton(
                key: const ValueKey('daily-question-cancel'),
                onPressed: summary.busy
                    ? null
                    : ref.read(noteSummaryProvider.notifier).cancel,
                child: const Text('Cancel'),
              )
            else
              TextButton(
                key: const ValueKey('daily-question-ask'),
                onPressed: occupied ? null : () => controller.request(day),
                child: const Text('Ask me a question'),
              ),
          ],
        ),
        if (selection != null)
          Text(
            selection.prior.isEmpty && selection.today.isEmpty
                ? 'No entries to draw on yet, so you’ll get a general question. Nothing else is sent.'
                : 'Sends ${_count(selection.today.length + selection.prior.length)} '
                      '(${_scope(selection)}) and your last few questions to your paired computer only.',
            key: const ValueKey('daily-question-disclosure'),
            style: caption,
            textAlign: TextAlign.center,
          ),
      ],
    );
  }

  static String _count(int n) => n == 1 ? '1 entry' : '$n entries';
  static String _scope(DailyQuestionSource s) => [
    if (s.today.isNotEmpty) 'today',
    if (s.prior.isNotEmpty)
      '${s.priorDays.length == 1 ? '1 earlier day' : '${s.priorDays.length} earlier days'} '
          'from the past week',
  ].join(' and ');
}
