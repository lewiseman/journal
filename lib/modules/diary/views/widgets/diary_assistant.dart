import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journal/modules/diary/controllers/diary_providers.dart';
import 'package:journal/modules/diary/controllers/diary_repository.dart';
import 'package:journal/modules/diary/questions/daily_question_controller.dart';
import 'package:journal/modules/diary/questions/daily_question_prompt.dart';
import 'package:journal/modules/diary/suggestions/diary_details_page.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/modules/settings/companion/companion_page.dart';
import 'package:journal/modules/voice/voice.dart';
import 'package:journal/utils/navigation_helper.dart';
import 'package:journal/utils/time_helper.dart';

enum _DiaryTool { details }

/// The selected reader day is captured when QVAC opens, including empty days.
/// Opening the menu itself never creates a microphone or a conversation.
class DiaryAssistant extends ConsumerStatefulWidget {
  const DiaryAssistant({
    super.key,
    required this.date,
    required this.canAddVoice,
    required this.scrollController,
  });
  final DateTime date;
  final bool canAddVoice;
  final ScrollController scrollController;

  @override
  ConsumerState<DiaryAssistant> createState() => _DiaryAssistantState();
}

class _DiaryAssistantState extends ConsumerState<DiaryAssistant> {
  _DiaryTool? _tool;

  void _open(_DiaryTool? tool) {
    if (widget.scrollController.hasClients) {
      widget.scrollController.jumpTo(0);
    }
    setState(() {
      _tool = tool;
    });
  }

  void _openVoice() {
    if (!widget.canAddVoice || ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    FocusScope.of(context).unfocus();
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    context.nav.replace<void, bool>(
      VoiceSessionPage(
        date: widget.date,
        mode: VoiceSessionMode.conversation,
        title: 'Your day, out loud',
      ),
      transition: reduced ? NavTransition.none : NavTransition.fade,
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (_tool) {
      case _DiaryTool.details:
        return DiaryDetailsPage(
          dateString: TimeHelper.dateKey(widget.date),
          scrollController: widget.scrollController,
          onBack: () => _open(null),
        );
      case null:
        break;
    }
    final theme = Theme.of(context);
    final phase = ref.watch(
      companionControllerProvider.select((state) => state.phase),
    );
    final day = DiaryRepository.formatDateKey(widget.date);
    final today =
        day ==
        DiaryRepository.formatDateKey(ref.watch(dailyQuestionClockProvider)());
    return ListView(
      key: const ValueKey('diary-assistant-actions'),
      controller: widget.scrollController,
      physics: const ClampingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        24,
        4,
        24,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Your diary', style: theme.textTheme.headlineSmall),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        Text(
          TimeHelper.format(
            widget.date,
            pattern: TimeFormat.shortWeekdayDate,
            toLocal: false,
          ),
          key: const ValueKey('diary-assistant-date'),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 6),
        Text(
          companionPhaseLabel(phase),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        if (today) ...[
          _DailyQuestionCard(day: day),
          const SizedBox(height: 12),
        ],
        _ToolTile(
          key: const ValueKey('diary-assistant-details'),
          icon: Icons.auto_awesome_outlined,
          title: 'Day details',
          subtitle: 'Reflect on your day’s title, mood and themes.',
          onTap: () => _open(_DiaryTool.details),
        ),
        const SizedBox(height: 12),
        _ToolTile(
          key: const ValueKey('diary-assistant-microphone'),
          icon: Icons.mic_none_rounded,
          title: 'Microphone',
          subtitle: widget.canAddVoice
              ? 'Talk through your day and turn it into an entry.'
              : 'Older days are read-only on this device.',
          onTap: widget.canAddVoice ? _openVoice : null,
        ),
      ],
    );
  }
}

/// Today's question: the current one with a way to ask for another, or
/// progress while one is being asked. The diary page shows only its text.
class _DailyQuestionCard extends ConsumerWidget {
  const _DailyQuestionCard({required this.day});
  final String day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final caption = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final enabled = ref.watch(dailyQuestionEnabledProvider);
    final List<Widget> children;
    if (!enabled) {
      children = [
        Text(
          'Daily questions are off. Turn them on in More → Local QVAC.',
          key: const ValueKey('daily-question-off'),
          style: caption,
        ),
      ];
    } else {
      final state = ref.watch(dailyQuestionProvider);
      ref.watch(diaryDaysProvider);
      final summary = ref.watch(noteSummaryProvider);
      final connected =
          ref.watch(companionControllerProvider.select((s) => s.phase)) ==
          CompanionPhase.connected;
      final controller = ref.read(dailyQuestionProvider.notifier);
      final view = controller.current(day);
      final asking = DailyQuestionController.asking(summary);
      final occupied = summary.handle != null && !asking;
      final status = asking
          ? 'Asking your computer for a question…'
          : occupied
          ? 'Another AI task is in progress. Finish it to ask a question.'
          : !connected
          ? 'Connect your computer to get a question.'
          : state.message;
      children = [
        if (view != null) ...[
          Text(
            view.question.text,
            key: const ValueKey('daily-question-text'),
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 4),
          Text(
            DailyQuestionPrompt.sourceLabel(view.question),
            key: const ValueKey('daily-question-source'),
            style: caption,
          ),
        ] else if (!asking)
          Text(
            'No question yet. Your diary page shows blank lines until one arrives.',
            style: caption,
          ),
        if (asking)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(
              key: ValueKey('daily-question-loading'),
            ),
          ),
        if (status != null) ...[
          const SizedBox(height: 4),
          Text(
            status,
            key: const ValueKey('daily-question-status'),
            style: caption,
          ),
        ],
        if (!asking) ...[
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.tonal(
              key: const ValueKey('daily-question-another'),
              onPressed: connected && !occupied
                  ? () => view == null
                        ? controller.request(day)
                        : controller.regenerate(day, view)
                  : null,
              child: Text(view == null ? 'Get a question' : 'Another question'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            DailyQuestionPrompt.disclosure(controller.selection(day)),
            key: const ValueKey('daily-question-disclosure'),
            style: caption,
          ),
        ],
      ];
    }
    return Container(
      key: const ValueKey('diary-assistant-question'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Today’s question', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 12,
        ),
        leading: Icon(
          icon,
          color: onTap == null ? colors.outline : colors.primary,
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        enabled: onTap != null,
        onTap: onTap,
      ),
    );
  }
}
