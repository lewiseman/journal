import 'dart:async';

import 'package:journal/common.dart';
import 'package:journal/modules/voice/controllers/diary_conversation.dart';
import 'package:journal/modules/voice/controllers/reply_voice.dart';
import 'package:journal/modules/voice/controllers/talk_session.dart';
import 'package:journal/modules/voice/views/widgets/voice_ambient_background.dart';

/// Hands-free diary conversation: the companion speaks, the microphone opens,
/// and when you pause the computer takes your words and replies. The
/// [conversation] stays owned by the conversation page, where turns can still
/// be corrected and the diary draft is reviewed.
class DiaryTalkPage extends StatefulWidget {
  const DiaryTalkPage({
    super.key,
    required this.conversation,
    required this.voice,
    required this.ready,
  });
  final DiaryConversation conversation;
  final ReplyVoice voice;

  /// Completes once the conversation has been restored from protected storage.
  final Future<void> ready;
  @override
  State<DiaryTalkPage> createState() => _DiaryTalkPageState();
}

class _DiaryTalkPageState extends State<DiaryTalkPage>
    with WidgetsBindingObserver {
  late final TalkSession _talk;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _talk = TalkSession(conversation: widget.conversation, voice: widget.voice)
      ..addListener(_changed);
    unawaited(widget.ready.then((_) => _talk.start()));
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_talk.hold());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _talk.removeListener(_changed);
    _talk.dispose();
    super.dispose();
  }

  String get _title => switch (_talk.phase) {
    TalkPhase.connecting => 'Connecting to your computer…',
    TalkPhase.thinking =>
      widget.conversation.turns.isEmpty
          ? 'Getting your first question…'
          : 'Thinking…',
    TalkPhase.speaking => 'Your companion is speaking',
    TalkPhase.listening => 'Your turn · pause when you are done',
    TalkPhase.transcribing => 'Got it…',
    TalkPhase.paused => 'Paused',
  };

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? Colors.white : Colors.black87;
    final phase = _talk.phase;
    final turns = widget.conversation.turns;
    final question = _talk.streaming.isNotEmpty
        ? _talk.streaming
        : turns.lastWhere(
            (t) => t['speaker'] == 'assistant',
            orElse: () => const {'text': ''},
          )['text']!;
    final yourTurn =
        phase == TalkPhase.listening || phase == TalkPhase.transcribing;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your day, out loud'),
        actions: [
          IconButton(
            tooltip: widget.voice.enabled
                ? 'Mute spoken replies'
                : 'Speak replies',
            onPressed: () {
              setState(() => widget.voice.enabled = !widget.voice.enabled);
              if (!widget.voice.enabled) _talk.answerNow();
            },
            icon: Icon(
              widget.voice.enabled
                  ? Icons.volume_up_outlined
                  : Icons.volume_off_outlined,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: VoiceAmbientBackground(
              mode: VoiceSessionMode.conversation,
              phase: switch (phase) {
                TalkPhase.speaking => VoiceSessionPhase.speaking,
                TalkPhase.listening => VoiceSessionPhase.listening,
                TalkPhase.paused => VoiceSessionPhase.paused,
                _ => VoiceSessionPhase.thinking,
              },
              activity: VoiceAudioActivity(
                level: phase == TalkPhase.speaking ? .45 : _talk.level,
                pitch: .5,
              ),
              reducedMotion: MediaQuery.disableAnimationsOf(context),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (phase == TalkPhase.connecting ||
                          phase == TalkPhase.transcribing ||
                          (phase == TalkPhase.thinking &&
                              _talk.streaming.isEmpty))
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: LinearProgressIndicator(),
                        ),
                      if (phase == TalkPhase.listening)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: LinearProgressIndicator(
                            value: _talk.level,
                            minHeight: 5,
                          ),
                        ),
                      if (phase == TalkPhase.paused && _talk.note != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(_talk.note!),
                        ),
                      const SizedBox(height: 24),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (question.isNotEmpty)
                                SelectableText(
                                  question,
                                  style: TextStyle(
                                    fontSize: 24,
                                    height: 1.4,
                                    color: ink,
                                  ),
                                ),
                              // Words stream in after short pauses.
                              if (yourTurn || _talk.heard.isNotEmpty) ...[
                                const SizedBox(height: 24),
                                Text(
                                  _talk.heard.isEmpty
                                      ? 'Your words will appear here after short pauses.'
                                      : _talk.heard,
                                  style: TextStyle(
                                    fontSize: 19,
                                    height: 1.5,
                                    color: ink.withValues(alpha: .7),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        alignment: WrapAlignment.center,
                        children: [
                          if (phase == TalkPhase.speaking)
                            FilledButton.icon(
                              onPressed: _talk.answerNow,
                              icon: const Icon(Icons.mic),
                              label: const Text('Answer now'),
                            ),
                          if (phase == TalkPhase.listening)
                            FilledButton.icon(
                              onPressed: _talk.done,
                              icon: const Icon(Icons.check),
                              label: const Text("I'm done"),
                            ),
                          if (phase == TalkPhase.paused &&
                              !widget.conversation.saved)
                            FilledButton.icon(
                              onPressed: _talk.resume,
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Continue'),
                            ),
                          OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Finish · review'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Replies are spoken by this phone, and the microphone is off while they play. Your words go to your paired computer, which listens for a pause and replies. Review every turn and the diary draft before saving.',
                        style: TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
