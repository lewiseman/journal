import 'package:journal/common.dart';
import 'package:journal/modules/diary/questions/daily_question_contract.dart';
import 'package:journal/modules/diary/questions/daily_question_controller.dart';
import 'package:journal/modules/diary/views/widgets/diary_writing_prompt.dart';

/// Today's writing lines. With daily questions on and a current question,
/// the question is written on them; otherwise, including while one is being
/// asked, they are blank. Asking for another is in the diary helper.
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

  /// What a request for [s] sends, for disclosure before asking.
  static String disclosure(DailyQuestionSource s) =>
      s.prior.isEmpty && s.today.isEmpty
      ? 'No entries to draw on yet, so you’ll get a general question. Nothing else is sent.'
      : 'Sends ${_count(s.today.length + s.prior.length)} '
            '(${_scope(s)}) and your last few questions to your paired computer only.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Opted out: nothing AI-related is built or watched.
    if (!ref.watch(dailyQuestionEnabledProvider)) {
      return DiaryWritingPrompt(onTap: onWrite);
    }
    ref.watch(dailyQuestionProvider);
    ref.watch(diaryDaysProvider);
    final controller = ref.read(dailyQuestionProvider.notifier);
    final view = controller.current(day);
    // Also covers a new civil day starting while the app stays open.
    if (view == null) controller.ensure();
    return DiaryWritingPrompt(onTap: onWrite, text: view?.question.text);
  }

  static String _count(int n) => n == 1 ? '1 entry' : '$n entries';
  static String _scope(DailyQuestionSource s) => [
    if (s.today.isNotEmpty) 'today',
    if (s.prior.isNotEmpty)
      '${s.priorDays.length == 1 ? '1 earlier day' : '${s.priorDays.length} earlier days'} '
          'from the past week',
  ].join(' and ');
}
