import 'dart:async';

import 'package:journal/common.dart';
import 'package:journal/modules/diary/controllers/diary_repository.dart';
import 'package:journal/modules/diary/questions/daily_question_contract.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';
import 'package:journal/modules/voice/controllers/diary_conversation.dart';
import 'package:journal/modules/voice/controllers/reply_voice.dart';

import 'diary_talk_page.dart';

class DiaryConversationPage extends ConsumerStatefulWidget {
  const DiaryConversationPage({
    super.key,
    required this.date,
    this.talk = false,
  });
  final DateTime date;

  /// Opens straight into the hands-free talk loop.
  final bool talk;
  @override
  ConsumerState<DiaryConversationPage> createState() =>
      _DiaryConversationPageState();
}

class _DiaryConversationPageState extends ConsumerState<DiaryConversationPage> {
  late final DiaryConversation _session;
  late final Future<void> _restored;
  final _input = TextEditingController(), _draft = TextEditingController();
  final _voice = ReplyVoice();
  String _lastDraft = '';
  bool _saving = false, _talking = false;
  @override
  void initState() {
    super.initState();
    _session = DiaryConversation(
      dateString: DiaryRepository.formatDateKey(widget.date),
      computer: () {
        if (ref.read(accountResetProvider).blocksDataAccess) {
          throw const CompanionFailure(
            'RESET',
            'Account reset is in progress.',
          );
        }
        final c = ref.read(companionControllerProvider).selected;
        if (c == null) {
          throw const CompanionFailure(
            'UNAVAILABLE',
            'Pair your computer in Settings → Local AI computer.',
          );
        }
        return c;
      },
      // The live talk session asks the first question itself.
      autoOpen: false,
      onReply: (text) {
        // While the talk page is opening it speaks the latest question itself.
        if (!_talking && mounted) unawaited(_voice.say(text));
      },
      // The same selection the daily question uses: today's latest entries,
      // then recent days, within a small budget.
      diary: () {
        final source = DailyQuestionSource.select(
          today: DiaryRepository.formatDateKey(widget.date),
          day: ref.read(diaryRepositoryProvider).getDay,
        );
        return [
          for (final e in [...source.today, ...source.prior])
            {'daysAgo': source.ago(e), 'text': e.text},
        ];
      },
    );
    _session.addListener(_changed);
    _restored = _session.restore();
    if (widget.talk) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _talk());
    }
  }

  void _changed() {
    if (!mounted) return;
    if (_lastDraft != _session.draft) {
      _lastDraft = _session.draft;
      _draft.text = _session.draft;
    }
    setState(() {});
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _session.busy || _session.saved) return;
    unawaited(_voice.stop());
    try {
      await _session.add(text);
      if (!mounted) return;
      _input.clear();
      await _session.request('question');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _talk() async {
    if (_talking || !mounted || _session.saved) return;
    _talking = true;
    await _voice.stop();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DiaryTalkPage(
          conversation: _session,
          voice: _voice,
          ready: _restored,
        ),
      ),
    );
    _talking = false;
    if (mounted) setState(() {});
  }

  Future<void> _correct(int index) async {
    final controller = TextEditingController(
      text: _session.turns[index]['text'],
    );
    final replacement = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Correct your words'),
        content: TextField(controller: controller, minLines: 3, maxLines: 8),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Keep correction'),
          ),
        ],
      ),
    );
    if (mounted && replacement != null) {
      await _session.correct(index, replacement);
    }
    // The dialog route may still animate; dispose after its transition.
    Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
  }

  Future<void> _save() async {
    if (_saving ||
        _session.saved ||
        _session.busy ||
        _draft.text.trim().isEmpty ||
        ref.read(accountResetProvider).blocksDataAccess) {
      return;
    }
    setState(() => _saving = true);
    try {
      ref
          .read(diaryRepositoryProvider)
          .addTimelineItem(
            dateString: _session.dateString,
            content: _draft.text.trim(),
            itemUuid: _session.id,
          );
      _session.saved = true;
      await _session.persist();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is StateError
                  ? e.message
                  : 'Could not save. Your reviewed draft is retained.',
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    unawaited(_voice.stop());
    _session.removeListener(_changed);
    _session.dispose();
    _input.dispose();
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _session.busy || _session.saved || _saving;
    return Scaffold(
      appBar: AppBar(
        title: const Text('A conversation about your day'),
        actions: [
          IconButton(
            tooltip: _voice.enabled ? 'Mute spoken replies' : 'Speak replies',
            onPressed: () {
              setState(() => _voice.enabled = !_voice.enabled);
              if (!_voice.enabled) unawaited(_voice.stop());
            },
            icon: Icon(
              _voice.enabled
                  ? Icons.volume_up_outlined
                  : Icons.volume_off_outlined,
            ),
          ),
          IconButton(
            tooltip: 'Discard conversation',
            onPressed: _session.busy ? null : _session.clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  _session.dateString,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Only this conversation is sent to your computer. Replies are read aloud on this phone; mute them with the speaker button.',
                ),
                const SizedBox(height: 16),
                Semantics(liveRegion: true, child: Text(_session.message)),
                if (_session.busy) const LinearProgressIndicator(),
                if (_session.pending != null && !_session.busy)
                  TextButton(
                    onPressed: _session.retrieve,
                    child: const Text('Retrieve / retry accepted request'),
                  ),
                for (var index = 0; index < _session.turns.length; index++)
                  Card(
                    child: ListTile(
                      title: Text(
                        _session.turns[index]['speaker'] == 'user'
                            ? 'You'
                            : 'Companion',
                      ),
                      subtitle: SelectableText(_session.turns[index]['text']!),
                      trailing: _session.turns[index]['speaker'] == 'user'
                          ? IconButton(
                              tooltip: 'Correct your words',
                              onPressed: disabled || _session.pending != null
                                  ? null
                                  : () => _correct(index),
                              icon: const Icon(Icons.edit_outlined),
                            )
                          : IconButton(
                              tooltip: 'Read aloud',
                              onPressed: () =>
                                  _voice.say(_session.turns[index]['text']!),
                              icon: const Icon(Icons.volume_up_outlined),
                            ),
                    ),
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _input,
                  enabled: !disabled && _session.pending == null,
                  minLines: 2,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Your words',
                    hintText: 'Type or record, then review before sending',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _session.saved || _saving ? null : _talk,
                      icon: const Icon(Icons.mic_none),
                      label: const Text('Talk'),
                    ),
                    FilledButton(
                      onPressed: disabled || _session.pending != null
                          ? null
                          : _send,
                      child: const Text('Send'),
                    ),
                    OutlinedButton(
                      onPressed:
                          disabled ||
                              _session.pending != null ||
                              _session.turns.isEmpty
                          ? null
                          : () => _session.request('draft'),
                      child: const Text('Create diary draft'),
                    ),
                  ],
                ),
                if (_session.draft.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  TextField(
                    controller: _draft,
                    enabled: !disabled,
                    minLines: 5,
                    maxLines: 16,
                    decoration: const InputDecoration(
                      labelText: 'Review diary draft',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      _session.draft = value;
                      _lastDraft = value;
                      unawaited(_session.persist());
                    },
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: disabled
                        ? null
                        : () {
                            _session.draft = '';
                            unawaited(_session.persist());
                            _changed();
                          },
                    child: const Text('Reject draft'),
                  ),
                  FilledButton(
                    onPressed: disabled ? null : _save,
                    child: const Text('Save reviewed diary entry'),
                  ),
                ],
                const SizedBox(height: 20),
                const Text(
                  'Conversation and drafts are protected locally for up to 24 hours. Closing keeps them recoverable. Discard deletes this local session; desktop requests expire within 24 hours. Saving follows this device’s normal diary date rules.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
