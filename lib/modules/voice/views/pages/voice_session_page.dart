import 'package:flutter/material.dart';

import 'voice_capture_page.dart';
import 'diary_conversation_page.dart';

import 'package:flutter/services.dart';
import 'package:journal/modules/voice/controllers/voice_session_controller.dart';
import 'package:journal/modules/voice/models/voice_session.dart';
import 'package:journal/modules/voice/views/widgets/voice_ambient_background.dart';
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
    _reduced =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
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
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? const Color(0xFFF5EEF5) : const Color(0xFF302A32);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
          ),
      child: Scaffold(
        backgroundColor: dark
            ? const Color(0xFF241F27)
            : const Color(0xFFFFF9EE),
        body: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            final state = _controller.state;
            return Stack(
              children: [
                Positioned.fill(
                  child: VoiceAmbientBackground(
                    mode: widget.mode,
                    phase: state.phase,
                    activity: state.activity,
                    reducedMotion: _reduced,
                  ),
                ),
                SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 700),
                      child: Column(
                        children: [
                          _header(ink),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final compact =
                                    constraints.maxHeight < 300 ||
                                    MediaQuery.textScalerOf(context).scale(1) >
                                        1.4;
                                final statusHeight = compact
                                    ? (constraints.maxHeight * .18).clamp(
                                        28.0,
                                        56.0,
                                      )
                                    : (constraints.maxHeight * .43).clamp(
                                        28.0,
                                        260.0,
                                      );
                                return Column(
                                  children: [
                                    SizedBox(
                                      height: statusHeight,
                                      child: Center(
                                        child: _SessionStatus(
                                          phase: state.phase,
                                          ink: ink,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: VoiceTranscript(
                                        turns: state.turns,
                                        mode: widget.mode,
                                        ink: ink,
                                        reducedMotion: _reduced,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                          _controls(state, ink, dark),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(Color ink) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Close voice preview',
          onPressed: _close,
          style: IconButton.styleFrom(
            minimumSize: const Size(48, 48),
            foregroundColor: ink,
          ),
          icon: const Icon(Icons.close_rounded, size: 23),
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Preview · sample text',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ink.withValues(alpha: .58),
                  fontSize: 11,
                  letterSpacing: .2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 48),
      ],
    ),
  );

  Widget _controls(VoiceSessionState state, Color ink, bool dark) {
    final completed = state.phase == VoiceSessionPhase.completed;
    final paused = state.phase == VoiceSessionPhase.paused;
    final label = completed ? 'Replay' : (paused ? 'Resume' : 'Pause');
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
      child: Row(
        children: [
          IconButton.filledTonal(
            tooltip: label,
            onPressed: completed
                ? _controller.replay
                : (paused ? _controller.resume : _controller.pause),
            style: IconButton.styleFrom(
              minimumSize: const Size(64, 64),
              foregroundColor: ink,
              backgroundColor: ink.withValues(alpha: dark ? .12 : .07),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            icon: Icon(
              completed
                  ? Icons.replay_rounded
                  : (paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: FilledButton(
              onPressed: _close,
              style: FilledButton.styleFrom(
                backgroundColor: ink,
                foregroundColor: dark
                    ? const Color(0xFF241F27)
                    : const Color(0xFFFFF9EE),
                minimumSize: const Size(0, 64),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Done',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionStatus extends StatelessWidget {
  const _SessionStatus({required this.phase, required this.ink});
  final VoiceSessionPhase phase;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final label = switch (phase) {
      VoiceSessionPhase.listening => 'Listening',
      VoiceSessionPhase.thinking => 'A moment to reflect',
      VoiceSessionPhase.speaking => 'Speaking',
      VoiceSessionPhase.paused => 'Paused',
      VoiceSessionPhase.completed => 'Preview finished',
    };
    final icon = switch (phase) {
      VoiceSessionPhase.listening => Icons.graphic_eq_rounded,
      VoiceSessionPhase.thinking => Icons.more_horiz_rounded,
      VoiceSessionPhase.speaking => Icons.graphic_eq_rounded,
      VoiceSessionPhase.paused => Icons.pause_rounded,
      VoiceSessionPhase.completed => Icons.check_rounded,
    };
    final text = Text(
      label,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: ink.withValues(alpha: .60),
        fontSize: 12,
        letterSpacing: .4,
      ),
    );
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: LayoutBuilder(
          builder: (context, constraints) => constraints.maxHeight < 80
              ? Center(child: text)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 26, color: ink.withValues(alpha: .50)),
                    const SizedBox(height: 10),
                    text,
                  ],
                ),
        ),
      ),
    );
  }
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
      ? DiaryConversationPage(date: date ?? DateTime.now(), talk: true)
      : VoiceCapturePage(title: title, target: target);
}
