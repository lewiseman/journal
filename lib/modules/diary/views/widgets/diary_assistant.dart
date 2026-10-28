import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journal/modules/diary/controllers/diary_providers.dart';
import 'package:journal/modules/diary/suggestions/diary_details_page.dart';
import 'package:journal/modules/presentation/presentation_contract.dart';
import 'package:journal/modules/presentation/presentation_page.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/modules/settings/companion/companion_page.dart';
import 'package:journal/modules/voice/views/pages/diary_talk_page.dart';
import 'package:journal/utils/time_helper.dart';

enum _DiaryTool { details, microphone, presentation }

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
  PresentationSourceRef? _presentationSource;

  void _open(_DiaryTool? tool) {
    if (widget.scrollController.hasClients) {
      widget.scrollController.jumpTo(0);
    }
    setState(() {
      _tool = tool;
      _presentationSource = null;
    });
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
      case _DiaryTool.microphone:
        return DiaryTalkPage(
          date: widget.date,
          scrollController: widget.scrollController,
        );
      case _DiaryTool.presentation:
        final source = _presentationSource;
        if (source != null) {
          return PresentationPage(
            key: ValueKey(source.key),
            source: source,
            scrollController: widget.scrollController,
            onBack: () => _open(_DiaryTool.presentation),
          );
        }
        break;
      case null:
        break;
    }
    final dateString = TimeHelper.dateKey(widget.date);
    final day =
        ref
            .watch(diaryDaysProvider)
            .value
            ?.where((day) => day.dateString == dateString)
            .firstOrNull ??
        ref.read(diaryRepositoryProvider).getDay(dateString);
    final items = day?.visibleItems.toList() ?? [];
    if (_tool == _DiaryTool.presentation) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Presentation'),
          leading: BackButton(onPressed: () => _open(null)),
        ),
        body: ListView(
          key: const ValueKey('diary-presentation-entries'),
          controller: widget.scrollController,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const Text('Choose a saved entry'),
            const SizedBox(height: 12),
            if (items.isEmpty)
              const Text('Save an entry for this day to style its words.'),
            for (final item in items)
              ListTile(
                key: ValueKey('diary-presentation-entry-${item.itemUuid}'),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  item.content,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  widget.scrollController.jumpTo(0);
                  setState(() {
                    _presentationSource = PresentationSourceRef.diary(
                      dateString,
                      item.itemUuid,
                    );
                  });
                },
              ),
          ],
        ),
      );
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
          onTap: widget.canAddVoice ? () => _open(_DiaryTool.microphone) : null,
        ),
        const SizedBox(height: 12),
        _ToolTile(
          key: const ValueKey('diary-assistant-presentation'),
          icon: Icons.auto_fix_high_outlined,
          title: 'Presentation',
          subtitle: items.isEmpty
              ? 'Save an entry for this day to style its words.'
              : 'Style a saved entry while keeping your words.',
          onTap: items.isEmpty ? null : () => _open(_DiaryTool.presentation),
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
