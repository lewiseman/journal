import 'package:flutter/material.dart';

import 'voice_capture_page.dart';
import 'diary_talk_page.dart';

import 'package:journal/modules/voice/controllers/voice_session_controller.dart';
import 'package:journal/modules/voice/models/voice_session.dart';
import 'package:journal/modules/voice/views/widgets/voice_ambient_background.dart';
import 'package:journal/modules/voice/views/widgets/voice_session_chrome.dart';
import 'package:journal/modules/voice/views/widgets/voice_transcript.dart';

class _PreviewVoiceSessionPage extends StatefulWidget {
  const _PreviewVoiceSessionPage({
    required this.mode,
    required this.title,
    this.controller,
  });

  final VoiceSessionMode mode;
  final String title;

  /// The caller owns injected controllers; the page pauses them on exit.
  /// Without one, the page creates and disposes its own preview controller.
  final VoiceSessionController? controller;

  @override
  State<_PreviewVoiceSessionPage> createState() => _VoiceSessionPageState();
}

class _VoiceSessionPageState extends State<_PreviewVoiceSessionPage>
    with WidgetsBindingObserver {
  late VoiceSessionController _controller;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller =
        widget.controller ?? PreviewVoiceSessionController(mode: widget.mode);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configurePlayback();
  }

  void _configurePlayback() {
    assert(_controller.mode == widget.mode);
    _reduced = MediaQuery.disableAnimationsOf(context);
    _controller.setReducedMotion(_reduced);
    _controller.start();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      _controller.pause();
    }
  }

  @override
  void didUpdateWidget(_PreviewVoiceSessionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.mode != widget.mode) {
      if (oldWidget.controller == null) {
        _controller.dispose();
      } else {
        _controller.pause();
      }
      _controller =
          widget.controller ?? PreviewVoiceSessionController(mode: widget.mode);
      _configurePlayback();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _controller.pause();
  }

  void _close() {
    _controller.pause();
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller == null) {
      _controller.dispose();
    } else {
      _controller.pause();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final state = _controller.state;
      final completed = state.phase == VoiceSessionPhase.completed;
      final paused = state.phase == VoiceSessionPhase.paused;
      return VoiceSessionScaffold(
        background: VoiceAmbientBackground(
          mode: widget.mode,
          phase: state.phase,
          activity: state.activity,
          reducedMotion: _reduced,
        ),
        header: VoiceSessionHeader(
          title: widget.title,
          subtitle: 'Preview · sample text',
          closeTooltip: 'Close voice preview',
          onClose: _close,
        ),
        status: VoiceSessionStatus(
          label: switch (state.phase) {
            VoiceSessionPhase.listening => 'Listening',
            VoiceSessionPhase.thinking => 'A moment to reflect',
            VoiceSessionPhase.speaking => 'Speaking',
            VoiceSessionPhase.paused => 'Paused',
            VoiceSessionPhase.completed => 'Preview finished',
          },
          icon: switch (state.phase) {
            VoiceSessionPhase.listening => Icons.graphic_eq_rounded,
            VoiceSessionPhase.thinking => Icons.more_horiz_rounded,
            VoiceSessionPhase.speaking => Icons.graphic_eq_rounded,
            VoiceSessionPhase.paused => Icons.pause_rounded,
            VoiceSessionPhase.completed => Icons.check_rounded,
          },
        ),
        transcript: VoiceTranscript(
          turns: state.turns,
          mode: widget.mode,
          ink: VoiceColors.of(context).ink,
          reducedMotion: _reduced,
        ),
        controls: VoiceSessionControls(
          actionLabel: completed ? 'Replay' : (paused ? 'Resume' : 'Pause'),
          actionIcon: completed
              ? Icons.replay_rounded
              : (paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
          onAction: completed
              ? _controller.replay
              : (paused ? _controller.resume : _controller.pause),
          primaryLabel: 'Done',
          onPrimary: _close,
        ),
      );
    },
  );
}

/// Production routes always use real capture/conversation. Samples are available
/// only through an explicitly injected controller in visual previews/tests.
class VoiceSessionPage extends StatelessWidget {
  const VoiceSessionPage({
    super.key,
    required this.mode,
    required this.title,
    this.controller,
    this.target = 'note',
    this.date,
  });
  final VoiceSessionMode mode;
  final String title, target;
  final DateTime? date;
  final VoiceSessionController? controller;
  @override
  Widget build(BuildContext context) => controller != null
      ? _PreviewVoiceSessionPage(
          mode: mode,
          title: title,
          controller: controller,
        )
      : mode == VoiceSessionMode.conversation
      ? DiaryTalkPage(date: date ?? DateTime.now())
      : VoiceCapturePage(title: title, target: target);
}
