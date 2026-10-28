import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journal/modules/diary/suggestions/diary_details_page.dart';
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
