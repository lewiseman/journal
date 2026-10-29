import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journal/modules/diary/controllers/diary_providers.dart';
import 'package:journal/modules/diary/models/diary_calendar_day.dart';
import 'package:journal/modules/diary/models/diary_day_entity.dart';
import 'package:journal/modules/local_ai/core/ai_router.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/summary/summary_history_page.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:sync_wise/sync_wise.dart';

import 'diary_suggestion_contract.dart';

enum _Decision { pending, accepted, rejected }

class _Field<T> {
  _Field(this.value);
  T value;
  _Decision decision = _Decision.pending;
  bool edited = false;
}

/// Day title, mood and themes: manual editing plus optional local-AI
/// suggestions that are reviewed field by field and never saved automatically.
class DiaryDetailsPage extends ConsumerStatefulWidget {
  const DiaryDetailsPage({
    super.key,
    required this.dateString,
    this.scrollController,
    this.onBack,
  });
  final String dateString;
  final ScrollController? scrollController;
  final VoidCallback? onBack;
  @override
  ConsumerState<DiaryDetailsPage> createState() => _DiaryDetailsPageState();
}

class _DiaryDetailsPageState extends ConsumerState<DiaryDetailsPage> {
  String? _seeded;
  _Field<String>? _title;
  _Field<DiaryCalendarMood>? _mood;
  _Field<List<String>>? _themes;

  /// Seeds per-field decisions once per completed result.
  void _seed(String? taskId, DiarySuggestions? suggestions) {
    final key = suggestions == null ? null : taskId;
    if (key == _seeded) return;
    _seeded = key;
    _title = suggestions?.title == null ? null : _Field(suggestions!.title!);
    _mood = suggestions?.mood.mood == null
        ? null
        : _Field(suggestions!.mood.mood!);
    _themes = suggestions == null || suggestions.themes.isEmpty
        ? null
        : _Field([for (final t in suggestions.themes) t.label]);
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _editManually(DiaryDayEntity day) async {
    final result = await showDialog<_ManualDetails>(
      context: context,
      builder: (_) => _ManualDetailsDialog(
        title: day.dayTitle?.trim() ?? '',
        mood: decodeDayMood(day.dayMood),
        themes: day.themes,
      ),
    );
    if (result == null || !mounted) return;
    try {
      ref
          .read(diaryRepositoryProvider)
          .updateDayMetadata(
            dateString: widget.dateString,
            dayTitle: normalizeDayTitle(result.title),
            dayMood: result.mood == null ? '' : encodeDayMood(result.mood!),
            dayThemes: encodeDayThemes(result.themes),
          );
    } on StateError catch (e) {
      _message(e.message);
    } on ArgumentError catch (e) {
      _message(e.message.toString());
    }
  }

  Future<String?> _editText(String label, String initial, int max) =>
      showDialog<String>(
        context: context,
        builder: (context) {
          final controller = TextEditingController(text: initial);
          return AlertDialog(
            title: Text('Edit $label'),
            content: TextField(
              key: ValueKey('diary-edit-$label'),
              controller: controller,
              maxLength: max,
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: const Text('Use'),
              ),
            ],
          );
        },
      );

  Future<void> _save() async {
    String? title, mood, themes;
    try {
      if (_title?.decision == _Decision.accepted) {
        title = normalizeDayTitle(_title!.value);
      }
      if (_mood?.decision == _Decision.accepted) {
        mood = encodeDayMood(_mood!.value);
      }
      if (_themes?.decision == _Decision.accepted) {
        themes = encodeDayThemes(_themes!.value);
      }
    } on ArgumentError catch (e) {
      _message(e.message.toString());
      return;
    }
    final saved = await ref
        .read(noteSummaryProvider.notifier)
        .acceptDiarySuggestion(title: title, mood: mood, themes: themes);
    if (saved && mounted) {
      setState(() => _seeded = null);
      _message('Saved the details you accepted.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(accountResetProvider).blocksDataAccess) {
      return const Scaffold(
        body: Center(child: Text('Account reset in progress.')),
      );
    }
    final days = ref.watch(diaryDaysProvider).value;
    final day =
        days?.where((d) => d.dateString == widget.dateString).firstOrNull ??
        ref.read(diaryRepositoryProvider).getDay(widget.dateString) ??
        DiaryDayEntity(dateString: widget.dateString);
    final canEdit =
        ref.watch(syncDeviceRoleProvider) != SyncDeviceRole.secondary;
    final suggestionsReady = ref.watch(
      aiOperationAvailableProvider('suggest-diary-day'),
    );
    final state = ref.watch(noteSummaryProvider);
    final controller = ref.read(noteSummaryProvider.notifier);
    final handle = state.handle;
    final thisTask =
        handle?.isDiarySuggestion == true &&
        handle?.noteId == widget.dateString;
    final suggestions = thisTask ? controller.diarySuggestions() : null;
    _seed(thisTask ? handle!.id : null, suggestions);
    final hasEntries = DiarySuggestionSource.fromDay(day) != null;
    final mood = decodeDayMood(day.dayMood);
    final anyAccepted = [
      _title?.decision,
      _mood?.decision,
      _themes?.decision,
    ].contains(_Decision.accepted);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Day details'),
        leading: widget.onBack == null
            ? null
            : BackButton(onPressed: widget.onBack),
      ),
      body: ListView(
        controller: widget.scrollController,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            widget.dateString,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 12),
          _Current(
            title: day.dayTitle?.trim() ?? '',
            mood: mood,
            themes: day.themes,
          ),
          if (canEdit)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('diary-details-edit'),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit details yourself'),
                onPressed: () => _editManually(day),
              ),
            )
          else
            const Text(
              'This device can read these details. Changing them requires the primary device.',
              key: ValueKey('diary-details-read-only'),
            ),
          const Divider(height: 32),
          Text(
            'Optional AI suggestions',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Only this day’s saved entry text is used for suggestions: no date, other days, photos or existing details. Suggestions are optional, can be wrong, and nothing is saved unless you accept it.',
          ),
          const SizedBox(height: 12),
          if (handle == null) ...[
            if (!hasEntries)
              const Text('Write an entry for this day to get suggestions.'),
            if (!suggestionsReady)
              const Text(
                'Connect your computer or set up a model on this phone to get suggestions.',
                key: ValueKey('diary-suggest-unavailable'),
              ),
            FilledButton.icon(
              key: const ValueKey('diary-suggest'),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Suggest title, mood and themes'),
              onPressed:
                  canEdit && hasEntries && suggestionsReady && !state.busy
                  ? () => controller.startDiarySuggestion(widget.dateString)
                  : null,
            ),
            if (state.message != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  state.message!,
                  key: const ValueKey('diary-suggest-message'),
                ),
              ),
          ] else if (!thisTask) ...[
            const Text(
              'Another AI task occupies the recoverable preview. Finish or clear it in AI task history first.',
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SummaryHistoryPage(),
                ),
              ),
              child: const Text('AI task history'),
            ),
          ] else ...[
            Text(
              summaryPhaseLabel(state.phase),
              key: const ValueKey('diary-suggest-phase'),
            ),
            if (state.stale)
              const Text(
                'This day’s entries changed after the request. These suggestions are out of date and cannot be saved; clear them and ask again.',
                key: ValueKey('diary-suggest-stale'),
              ),
            if (state.message != null) Text(state.message!),
            if (state.busy) const LinearProgressIndicator(),
            if (state.phase == 'completed' && suggestions != null) ...[
              const SizedBox(height: 12),
              if (suggestions.empty)
                const Text(
                  'There was not enough in this day’s entries for a grounded suggestion. That is a normal result; you can edit details yourself.',
                  key: ValueKey('diary-suggest-empty'),
                ),
              if (suggestions.dropped > 0)
                Text(
                  '${suggestions.dropped} suggestion${suggestions.dropped == 1 ? ' was' : 's were'} left out because ${suggestions.dropped == 1 ? 'it was' : 'they were'} not supported by your words or used sensitive labels.',
                  key: const ValueKey('diary-suggest-dropped'),
                ),
              if (_title case final field?)
                _Review(
                  key: const ValueKey('diary-review-title'),
                  label: 'Title',
                  current: day.dayTitle?.trim().isNotEmpty == true
                      ? day.dayTitle!.trim()
                      : 'None',
                  suggested: field.value,
                  edited: field.edited,
                  decision: field.decision,
                  onAccept: () =>
                      setState(() => field.decision = _Decision.accepted),
                  onReject: () =>
                      setState(() => field.decision = _Decision.rejected),
                  onEdit: () async {
                    final value = await _editText(
                      'title',
                      field.value,
                      diaryTitleChars,
                    );
                    if (value != null && value.trim().isNotEmpty) {
                      setState(() {
                        field
                          ..value = value
                          ..edited = true
                          ..decision = _Decision.accepted;
                      });
                    }
                  },
                ),
              _moodReview(day, mood, suggestions),
              if (_themes case final field?)
                _Review(
                  key: const ValueKey('diary-review-themes'),
                  label: 'Themes',
                  current: day.themes.isEmpty ? 'None' : day.themes.join(', '),
                  suggested: field.value.join(', '),
                  evidence: field.edited
                      ? null
                      : suggestions.themes
                            .map((t) => '“${t.evidence}”')
                            .join('  '),
                  edited: field.edited,
                  decision: field.decision,
                  onAccept: () =>
                      setState(() => field.decision = _Decision.accepted),
                  onReject: () =>
                      setState(() => field.decision = _Decision.rejected),
                  onEdit: () async {
                    final value = await _editText(
                      'themes (comma separated)',
                      field.value.join(', '),
                      3 * diaryThemeChars + 4,
                    );
                    if (value != null) {
                      setState(() {
                        field
                          ..value = value
                              .split(',')
                              .map((t) => t.trim())
                              .where((t) => t.isNotEmpty)
                              .toList()
                          ..edited = true
                          ..decision = _Decision.accepted;
                      });
                    }
                  },
                ),
              const SizedBox(height: 12),
              FilledButton(
                key: const ValueKey('diary-suggest-save'),
                onPressed: canEdit && anyAccepted && !state.stale && !state.busy
                    ? _save
                    : null,
                child: const Text('Save accepted details'),
              ),
              if (!canEdit)
                const Text(
                  'Saving requires the primary device. Nothing was changed.',
                ),
            ],
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
                    child: const Text('Cancel request'),
                  ),
                if (state.terminal)
                  TextButton(
                    key: const ValueKey('diary-suggest-clear'),
                    onPressed: state.busy ? null : controller.clear,
                    child: Text(
                      state.phase == 'completed'
                          ? 'Reject all and clear'
                          : 'Clear',
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _moodReview(
    DiaryDayEntity day,
    DiaryCalendarMood? current,
    DiarySuggestions suggestions,
  ) {
    const note = Text(
      'Mood is a tentative suggestion from your words, not a judgment of how you felt. Your own choice always wins.',
      key: ValueKey('diary-mood-disclaimer'),
    );
    final field = _mood;
    if (field == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              suggestions.mood.value == 'mixed'
                  ? 'Mood: your entries describe mixed feelings, so no single mood is suggested.'
                  : 'Mood: no mood suggested; the entries do not clearly say how you felt.',
              key: const ValueKey('diary-review-mood-none'),
            ),
            note,
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Review(
          key: const ValueKey('diary-review-mood'),
          label: 'Tentative mood',
          current: current == null
              ? 'None'
              : '${current.emoji} ${current.label}',
          suggested: '${field.value.emoji} ${field.value.label}',
          evidence: field.edited ? null : '“${suggestions.mood.evidence}”',
          edited: field.edited,
          decision: field.decision,
          onAccept: () => setState(() => field.decision = _Decision.accepted),
          onReject: () => setState(() => field.decision = _Decision.rejected),
          onEdit: () async {
            final value = await showDialog<DiaryCalendarMood>(
              context: context,
              builder: (context) => SimpleDialog(
                title: const Text('Choose a mood'),
                children: [
                  for (final m in DiaryCalendarMood.values)
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, m),
                      child: Text('${m.emoji} ${m.label}'),
                    ),
                ],
              ),
            );
            if (value != null) {
              setState(() {
                field
                  ..value = value
                  ..edited = true
                  ..decision = _Decision.accepted;
              });
            }
          },
        ),
        note,
      ],
    );
  }
}

class _Current extends StatelessWidget {
  const _Current({
    required this.title,
    required this.mood,
    required this.themes,
  });
  final String title;
  final DiaryCalendarMood? mood;
  final List<String> themes;
  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('diary-details-current'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Title: ${title.isEmpty ? 'None' : title}'),
      Text('Mood: ${mood == null ? 'None' : '${mood!.emoji} ${mood!.label}'}'),
      Text('Themes: ${themes.isEmpty ? 'None' : themes.join(', ')}'),
    ],
  );
}

class _Review extends StatelessWidget {
  const _Review({
    super.key,
    required this.label,
    required this.current,
    required this.suggested,
    required this.decision,
    required this.edited,
    required this.onAccept,
    required this.onReject,
    required this.onEdit,
    this.evidence,
  });
  final String label, current, suggested;
  final String? evidence;
  final _Decision decision;
  final bool edited;
  final VoidCallback onAccept, onReject, onEdit;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(vertical: 8),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          Text('Current: $current'),
          SelectableText('${edited ? 'Your edit' : 'Suggested'}: $suggested'),
          if (evidence != null && evidence!.trim().isNotEmpty)
            Text(
              'From your words: $evidence',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          Text(switch (decision) {
            _Decision.pending => 'Not chosen yet',
            _Decision.accepted => 'Will be saved',
            _Decision.rejected => 'Rejected; current value kept',
          }),
          Wrap(
            spacing: 8,
            children: [
              TextButton(onPressed: onAccept, child: const Text('Accept')),
              TextButton(onPressed: onEdit, child: const Text('Edit')),
              TextButton(onPressed: onReject, child: const Text('Reject')),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ManualDetails {
  const _ManualDetails(this.title, this.mood, this.themes);
  final String title;
  final DiaryCalendarMood? mood;
  final List<String> themes;
}

class _ManualDetailsDialog extends StatefulWidget {
  const _ManualDetailsDialog({
    required this.title,
    required this.mood,
    required this.themes,
  });
  final String title;
  final DiaryCalendarMood? mood;
  final List<String> themes;
  @override
  State<_ManualDetailsDialog> createState() => _ManualDetailsDialogState();
}

class _ManualDetailsDialogState extends State<_ManualDetailsDialog> {
  late final _title = TextEditingController(text: widget.title);
  late final _themes = TextEditingController(text: widget.themes.join(', '));
  late DiaryCalendarMood? _mood = widget.mood;
  @override
  void dispose() {
    _title.dispose();
    _themes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Day details'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('diary-manual-title'),
            controller: _title,
            maxLength: diaryTitleChars,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const Text('Mood'),
          Wrap(
            spacing: 6,
            children: [
              ChoiceChip(
                label: const Text('None'),
                selected: _mood == null,
                onSelected: (_) => setState(() => _mood = null),
              ),
              for (final m in DiaryCalendarMood.values)
                ChoiceChip(
                  key: ValueKey('diary-manual-mood-${m.name}'),
                  label: Text('${m.emoji} ${m.label}'),
                  selected: _mood == m,
                  onSelected: (_) => setState(() => _mood = m),
                ),
            ],
          ),
          TextField(
            key: const ValueKey('diary-manual-themes'),
            controller: _themes,
            decoration: const InputDecoration(
              labelText: 'Themes (up to three, comma separated)',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        key: const ValueKey('diary-manual-save'),
        onPressed: () => Navigator.pop(
          context,
          _ManualDetails(
            _title.text,
            _mood,
            _themes.text
                .split(',')
                .map((t) => t.trim())
                .where((t) => t.isNotEmpty)
                .toList(),
          ),
        ),
        child: const Text('Save'),
      ),
    ],
  );
}
