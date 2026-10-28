import 'dart:async';

import 'package:journal/common.dart';
import 'package:journal/modules/diary/controllers/diary_repository.dart';
import 'package:journal/modules/diary/models/diary_ai_conversation.dart';
import 'package:journal/modules/voice/controllers/diary_conversation.dart';
import 'package:journal/modules/voice/controllers/diary_talk_sources.dart';
import 'package:journal/modules/voice/controllers/mic_permission.dart';
import 'package:journal/modules/voice/controllers/reply_voice.dart';
import 'package:journal/modules/voice/controllers/talk_session.dart';
import 'package:journal/modules/voice/views/widgets/voice_ambient_background.dart';
import 'package:journal/modules/voice/views/widgets/voice_bottom_card.dart';
import 'package:journal/modules/voice/views/widgets/voice_session_chrome.dart';
import 'package:journal/modules/voice/views/widgets/voice_transcript.dart';

/// Hands-free diary conversation: the companion speaks, the microphone opens,
/// and when you pause the computer takes your words and replies.
///
/// Every open starts a fresh conversation. Once you have said something it is
/// kept on its own diary item, updated after each turn, so leaving keeps it.
/// Finish asks the computer for a first-person draft and writes it in as the
/// entry's words; the diary's conversation chip reopens it later.
///
/// Nothing connects until the microphone is allowed, so the companion never
/// asks a question that cannot be answered.
class DiaryTalkPage extends ConsumerStatefulWidget {
  const DiaryTalkPage({
    super.key,
    required this.date,
    this.conversation,
    this.voice,
    this.talk,
    this.permission,
    this.scrollController,
  });
  final DateTime date;
  final ScrollController? scrollController;

  /// Injected in tests; the caller then owns and disposes them.
  final DiaryConversation? conversation;
  final ReplyVoice? voice;
  final TalkSession? talk;
  final MicPermission? permission;
  @override
  ConsumerState<DiaryTalkPage> createState() => _DiaryTalkPageState();
}

class _DiaryTalkPageState extends ConsumerState<DiaryTalkPage>
    with WidgetsBindingObserver {
  late final DiaryRepository _diary;
  late final DiaryConversation _conversation;
  late final ReplyVoice _voice;
  late final TalkSession _talk;
  late final MicPermission _mic;
  late final Future<void> _ready;
  late final DateTime _created;
  bool _started = false, _granted = false;
  int _savedTurns = 0;

  /// Why Finish could not write the entry; the conversation is still kept.
  String? _writeFailure;
  TalkPhase? _lastPhase;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _diary = ref.read(diaryRepositoryProvider);
    _created = DateTime.now();
    _conversation =
        widget.conversation ??
        diaryConversation(
          ref,
          dateString: DiaryRepository.formatDateKey(widget.date),
        );
    _conversation.addListener(_conversationChanged);
    _voice = widget.voice ?? ReplyVoice();
    _ready = widget.conversation != null
        ? Future.value()
        : adoptLeftoverDiaryTalk(_diary);
    _talk =
        widget.talk ?? TalkSession(conversation: _conversation, voice: _voice);
    _talk.addListener(_changed);
    _mic = widget.permission ?? MicPermission();
    _mic.addListener(_permissionChanged);
    unawaited(_mic.check());
  }

  DiaryAiConversation get _record => DiaryAiConversation(
    turns: [for (final t in _conversation.turns) Map<String, String>.from(t)],
    createdAt: _created,
  );

  /// Read-only devices may add one item for today but not edit it, so they
  /// keep the turns until the page closes.
  bool get _savesEachTurn => _diary.sync.canEdit;

  bool _save({String? content}) {
    final record = _record;
    if (!record.hasUserTurn) return false;
    try {
      _diary.saveAiConversation(
        dateString: _conversation.dateString,
        itemUuid: _conversation.id,
        conversation: content == null
            ? record
            : record.copyWith(draftedAt: DateTime.now()),
        content: content,
      );
      _savedTurns = record.turns.length;
      return true;
    } catch (_) {
      return false;
    }
  }

  void _conversationChanged() {
    if (_savesEachTurn && _conversation.turns.length != _savedTurns) _save();
    // Finish shows the computer's progress as the request moves along.
    if (mounted && _writing) setState(() {});
  }

  void _changed() {
    if (!mounted) return;
    // A microphone revoked mid-session pauses the loop; show the card again.
    if (_talk.phase == TalkPhase.paused &&
        _lastPhase != TalkPhase.paused &&
        !_writing) {
      unawaited(_mic.check());
    }
    _lastPhase = _talk.phase;
    setState(() {});
  }

  void _permissionChanged() {
    if (!mounted) return;
    final regained = _mic.granted && !_granted;
    _granted = _mic.granted;
    if (regained && !_started) {
      _started = true;
      unawaited(_ready.then((_) => mounted ? _talk.start() : null));
    } else if (regained && _talk.phase == TalkPhase.paused && !_writing) {
      // Allowed again after it was revoked mid-session.
      unawaited(_talk.resume());
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Back from Settings, or a one-time permission that has now expired.
      unawaited(_mic.check());
    } else if (_started &&
        !_writing &&
        (state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden)) {
      // Dialogs and the notification shade only make the app inactive.
      unawaited(_talk.hold());
    }
  }

  /// The step Finish is on, shown as it happens; null when not finishing.
  _FinishStep? _step;
  bool get _writing => _step != null;

  /// What the computer is doing with the draft right now.
  _FinishStep? get _shownStep => _step == _FinishStep.sending
      ? switch (_conversation.jobState) {
          'queued' => _FinishStep.waiting,
          'running' => _FinishStep.writing,
          _ => _FinishStep.sending,
        }
      : _step;

  /// Hangs up, has the computer write the entry from your words, saves it
  /// and closes. Accepted work is waited for however long it takes; closing
  /// keeps the conversation without the entry.
  Future<void> _finish() async {
    if (_writing) return;
    if (!_record.hasUserTurn) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _step = _FinishStep.ending;
      _writeFailure = null;
    });
    await _talk.end();
    _save();
    if (!mounted || !_writing) return;
    setState(() => _step = _FinishStep.sending);
    // A retry picks up a request the computer may already have accepted.
    if (_conversation.pending != null) {
      await _conversation.retrieve();
    } else {
      await _conversation.request('draft');
    }
    final settled = Completer<void>();
    void check() {
      if (!_conversation.busy &&
          !_conversation.polling &&
          !settled.isCompleted) {
        settled.complete();
      }
    }

    _conversation.addListener(check);
    check();
    await settled.future;
    _conversation.removeListener(check);
    if (!mounted || !_writing) return;
    final draft = _conversation.draft.trim();
    if (draft.isNotEmpty) {
      setState(() => _step = _FinishStep.saving);
      if (_save(content: draft)) {
        Navigator.of(context).pop();
        return;
      }
    }
    setState(() {
      _step = null;
      _writeFailure = draft.isNotEmpty
          ? 'The entry was written but could not be saved to your diary.'
          : _conversation.message;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _talk.removeListener(_changed);
    _mic.removeListener(_permissionChanged);
    _conversation.removeListener(_conversationChanged);
    if (_conversation.turns.length != _savedTurns && !_writing) _save();
    if (widget.talk == null) _talk.dispose();
    if (widget.permission == null) _mic.dispose();
    if (widget.conversation == null) _conversation.dispose();
    if (widget.voice == null) unawaited(_voice.stop());
    super.dispose();
  }

  /// Before the microphone is allowed the page rests rather than loads.
  bool get _waiting => !_started;

  (String, IconData) get _status {
    if (_writing) {
      return switch (_shownStep!) {
        _FinishStep.ending => (
          'Ending the conversation…',
          Icons.call_end_rounded,
        ),
        _FinishStep.sending => (
          'Sending your words to your computer…',
          Icons.upload_rounded,
        ),
        _FinishStep.waiting => (
          'Waiting for your computer to start…',
          Icons.hourglass_top_rounded,
        ),
        _FinishStep.writing => (
          'Your computer is writing your entry…',
          Icons.edit_note_rounded,
        ),
        _FinishStep.saving => ('Saving to your diary…', Icons.save_rounded),
      };
    }
    if (_writeFailure != null) {
      return ('Conversation saved', Icons.check_rounded);
    }
    if (_waiting) {
      return _mic.status == MicStatus.unknown
          ? ('Getting ready…', Icons.more_horiz_rounded)
          : ('Waiting for your microphone', Icons.mic_off_rounded);
    }
    return switch (_talk.phase) {
      TalkPhase.connecting => ('Getting ready…', Icons.more_horiz_rounded),
      TalkPhase.thinking => (
        _conversation.turns.isEmpty
            ? 'Finding your first question…'
            : 'Thinking…',
        Icons.more_horiz_rounded,
      ),
      TalkPhase.speaking => ('Speaking', Icons.graphic_eq_rounded),
      TalkPhase.listening => (
        'Your turn · pause when you are done',
        Icons.mic_rounded,
      ),
      TalkPhase.transcribing => ('Got it…', Icons.more_horiz_rounded),
      TalkPhase.paused => ('Paused', Icons.pause_rounded),
    };
  }

  VoiceSessionPhase get _backgroundPhase {
    if (_writing) return VoiceSessionPhase.thinking;
    if (_writeFailure != null) return VoiceSessionPhase.paused;
    if (_waiting) {
      return _mic.status == MicStatus.unknown
          ? VoiceSessionPhase.thinking
          : VoiceSessionPhase.paused;
    }
    return switch (_talk.phase) {
      TalkPhase.speaking => VoiceSessionPhase.speaking,
      TalkPhase.listening => VoiceSessionPhase.listening,
      TalkPhase.paused => VoiceSessionPhase.paused,
      TalkPhase.connecting ||
      TalkPhase.thinking ||
      TalkPhase.transcribing => VoiceSessionPhase.thinking,
    };
  }

  List<VoiceTranscriptTurn> get _turns => [
    for (final turn in _conversation.turns)
      VoiceTranscriptTurn(
        speaker: turn['speaker'] == 'user'
            ? VoiceSpeaker.user
            : VoiceSpeaker.assistant,
        text: turn['text'] ?? '',
      ),
    if (_talk.streaming.isNotEmpty)
      VoiceTranscriptTurn(
        speaker: VoiceSpeaker.assistant,
        text: _talk.streaming,
        isFinal: false,
      ),
    if (_talk.heard.isNotEmpty)
      VoiceTranscriptTurn(
        speaker: VoiceSpeaker.user,
        text: _talk.heard,
        isFinal: false,
      ),
  ];

  Widget? _card(Color ink) {
    if (_writing) return null;
    if (_writeFailure != null) {
      return VoiceBottomCard(
        key: const ValueKey('voice-write-failed-card'),
        ink: ink,
        icon: Icons.info_outline_rounded,
        title: "Couldn't write your entry",
        body: '$_writeFailure Your conversation is saved in your diary.',
        action: 'Try again',
        onAction: () => unawaited(_finish()),
      );
    }
    final mic = VoiceBottomCard.microphone(permission: _mic, ink: ink);
    if (mic != null) return mic;
    if (_started && _talk.phase == TalkPhase.paused && _talk.note != null) {
      return VoiceBottomCard(
        key: const ValueKey('voice-note-card'),
        ink: ink,
        icon: Icons.info_outline_rounded,
        title: _talk.note!,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ink = VoiceColors.of(context).ink;
    final phase = _talk.phase;
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    final (label, icon) = _status;
    final (
      actionLabel,
      actionIcon,
      onAction,
    ) = _waiting || _writing || _writeFailure != null
        ? (null, null, null)
        : switch (phase) {
            TalkPhase.speaking => (
              'Answer now',
              Icons.mic_rounded,
              _talk.answerNow,
            ),
            TalkPhase.listening => (
              "I'm done",
              Icons.check_rounded,
              _talk.done,
            ),
            TalkPhase.paused when !_conversation.saved => (
              'Continue',
              Icons.play_arrow_rounded,
              _mic.granted ? () => unawaited(_talk.resume()) : null,
            ),
            _ => (null, null, null),
          };
    final finished = _writeFailure != null;
    return PopScope(
      canPop: !_writing,
      child: VoiceSessionScaffold(
        scrollController: widget.scrollController,
        background: VoiceAmbientBackground(
          mode: VoiceSessionMode.conversation,
          phase: _backgroundPhase,
          activity: VoiceAudioActivity(
            level: phase == TalkPhase.speaking ? .45 : _talk.level,
            pitch: .5,
          ),
          reducedMotion: reduced,
        ),
        header: VoiceSessionHeader(
          title: 'Your day, out loud',
          subtitle: _writing ? 'Your conversation is already saved' : null,
          closeTooltip: _writing ? 'Close without the entry' : 'Close',
          // Every turn is already in the diary; closing only skips the draft.
          onClose: () {
            _step = null;
            Navigator.of(context).pop();
          },
          trailing: IconButton(
            tooltip: _voice.enabled ? 'Mute spoken replies' : 'Speak replies',
            onPressed: () {
              setState(() => _voice.enabled = !_voice.enabled);
              if (!_voice.enabled) _talk.answerNow();
            },
            style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
            icon: Icon(
              _voice.enabled
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded,
              size: 22,
            ),
          ),
        ),
        status: VoiceSessionStatus(label: label, icon: icon),
        transcript: VoiceTranscript(
          embedded: widget.scrollController != null,
          scrollController: widget.scrollController,
          turns: _turns,
          mode: VoiceSessionMode.conversation,
          ink: ink,
          reducedMotion: reduced,
        ),
        card: _card(ink),
        controls: VoiceSessionControls(
          actionLabel: actionLabel,
          actionIcon: actionIcon,
          onAction: onAction,
          primaryLabel: _writing
              ? (_shownStep == _FinishStep.saving ? 'Saving…' : 'Writing…')
              : finished
              ? 'Close'
              : 'Finish',
          onPrimary: _writing
              ? null
              : finished
              ? () => Navigator.of(context).pop()
              : () => unawaited(_finish()),
        ),
      ),
    );
  }
}

enum _FinishStep { ending, sending, waiting, writing, saving }
