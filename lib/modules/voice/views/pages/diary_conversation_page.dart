import 'dart:async';

import 'package:journal/common.dart';
import 'package:journal/modules/diary/controllers/diary_repository.dart';
import 'package:journal/modules/diary/models/diary_ai_conversation.dart';
import 'package:journal/modules/voice/controllers/diary_conversation.dart';
import 'package:journal/modules/voice/controllers/diary_talk_sources.dart';
import 'package:journal/modules/voice/views/widgets/voice_bottom_card.dart';
import 'package:journal/modules/voice/views/widgets/voice_session_chrome.dart';
import 'package:journal/modules/voice/views/widgets/voice_transcript.dart';

/// A diary item's saved voice conversation: read the turns, have the
/// computer write a first-person draft, edit it, and make it the entry.
class DiaryConversationPage extends ConsumerStatefulWidget {
  const DiaryConversationPage({
    super.key,
    required this.dateString,
    required this.itemUuid,
    this.conversation,
  });
  final String dateString, itemUuid;

  /// Injected in tests; the caller then owns and disposes it.
  final DiaryConversation? conversation;
  @override
  ConsumerState<DiaryConversationPage> createState() =>
      _DiaryConversationPageState();
}

class _DiaryConversationPageState extends ConsumerState<DiaryConversationPage> {
  late final DiaryRepository _diary;
  late final DiaryConversation _session;
  final _draft = TextEditingController();
  DiaryAiConversation? _record;
  String _content = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _diary = ref.read(diaryRepositoryProvider);
    final item = _diary
        .getDay(widget.dateString)
        ?.items
        .where((i) => i.itemUuid == widget.itemUuid && !i.isDeleted)
        .firstOrNull;
    _record = item?.aiConversation;
    _content = item?.content ?? '';
    _session =
        widget.conversation ??
        diaryConversation(ref, dateString: widget.dateString);
    _session
      ..id = widget.itemUuid
      ..turns = [
        for (final t in _record?.turns ?? const <Map<String, String>>[])
          Map<String, String>.from(t),
      ]
      ..message = ''
      ..addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    if (_session.draft.isNotEmpty && _draft.text != _session.draft) {
      _draft.text = _session.draft;
      _session.draft = '';
    }
    setState(() {});
  }

  Future<void> _generate() async {
    if (_draft.text.trim().isNotEmpty &&
        !await _confirm(
          'Write a new draft?',
          'This replaces the draft you are editing.',
        )) {
      return;
    }
    // A request the computer already accepted is picked up, not resent.
    if (_session.pending != null) {
      await _session.retrieve();
    } else {
      await _session.request('draft');
    }
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Replace'),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _update() async {
    final text = _draft.text.trim();
    final record = _record;
    if (text.isEmpty || record == null || _saving) return;
    if (_content.trim().isNotEmpty &&
        _content.trim() != text &&
        !await _confirm(
          "Replace this entry's words?",
          'The entry will read as this draft.',
        )) {
      return;
    }
    setState(() => _saving = true);
    try {
      _diary.saveAiConversation(
        dateString: widget.dateString,
        itemUuid: widget.itemUuid,
        conversation: record.copyWith(draftedAt: DateTime.now()),
        content: text,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is StateError ? e.message : 'Could not update.'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _session.removeListener(_changed);
    if (widget.conversation == null) _session.dispose();
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = VoiceColors.of(context);
    final ink = colors.ink;
    final busy = _session.busy || _session.polling;
    final step = switch (_session.jobState) {
      'queued' => 'Waiting for your computer to start…',
      'running' => 'Your computer is writing your draft…',
      _ => 'Sending your words to your computer…',
    };
    final drafted = _draft.text.trim().isNotEmpty;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: colors.paper,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              children: [
                VoiceSessionHeader(
                  title: 'Your conversation',
                  subtitle: widget.dateString,
                  onClose: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: _record == null
                      ? Center(
                          child: Text(
                            'This conversation is no longer in your diary.',
                            style: TextStyle(color: ink.withValues(alpha: .6)),
                          ),
                        )
                      : VoiceTranscript(
                          turns: [
                            for (final t in _record!.turns)
                              VoiceTranscriptTurn(
                                speaker: t['speaker'] == 'user'
                                    ? VoiceSpeaker.user
                                    : VoiceSpeaker.assistant,
                                text: t['text'] ?? '',
                              ),
                          ],
                          mode: VoiceSessionMode.conversation,
                          ink: ink,
                          reducedMotion: reduced,
                        ),
                ),
                if (busy)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            step,
                            style: TextStyle(color: ink.withValues(alpha: .7)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(),
                      ],
                    ),
                  ),
                if (!busy && _session.message.isNotEmpty && !drafted)
                  VoiceBottomCard(
                    ink: ink,
                    icon: Icons.info_outline_rounded,
                    title: _session.message,
                  ),
                if (drafted)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: TextField(
                      key: const ValueKey('conversation-draft'),
                      controller: _draft,
                      enabled: !busy && !_saving,
                      minLines: 3,
                      maxLines: 8,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Draft',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                VoiceSessionControls(
                  actionLabel: drafted ? 'Write a new draft' : null,
                  actionIcon: drafted ? Icons.refresh_rounded : null,
                  onAction: busy || _saving ? null : () => _generate(),
                  primaryLabel: drafted ? 'Update entry' : 'Generate draft',
                  onPrimary: _record == null || busy || _saving
                      ? null
                      : drafted
                      ? () => unawaited(_update())
                      : () => unawaited(_generate()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
