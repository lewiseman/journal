import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:journal/modules/voice/models/voice_session.dart';

class VoiceTranscript extends StatefulWidget {
  const VoiceTranscript({
    super.key,
    required this.turns,
    required this.mode,
    required this.ink,
    required this.reducedMotion,
  });

  final List<VoiceTranscriptTurn> turns;
  final VoiceSessionMode mode;
  final Color ink;
  final bool reducedMotion;

  @override
  State<VoiceTranscript> createState() => _VoiceTranscriptState();
}

class _VoiceTranscriptState extends State<VoiceTranscript> {
  final _scroll = ScrollController();
  bool _following = true;
  bool _userScrolling = false;
  bool _scheduled = false;

  @override
  void didUpdateWidget(VoiceTranscript oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.turns.isEmpty) _following = true;
    if (oldWidget.turns != widget.turns) _followLatest();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _followLatest();
  }

  void _followLatest() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || !_scroll.hasClients || !_following || _userScrolling) {
        return;
      }
      final end = _scroll.position.maxScrollExtent;
      if ((_scroll.offset - end).abs() < .5) return;
      if (widget.reducedMotion) {
        _scroll.jumpTo(end);
      } else {
        _scroll.animateTo(
          end,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _userScrolling = true;
      _following = false;
    } else if (notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle) {
      _userScrolling = true;
      _following = false;
    } else if (notification is ScrollEndNotification && _userScrolling) {
      _following = notification.metrics.extentAfter <= 24;
      _userScrolling = false;
    }
    return false;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ShaderMask(
    key: const ValueKey('voice-transcript-fade'),
    blendMode: BlendMode.dstIn,
    shaderCallback: (bounds) => const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.transparent, Colors.white, Colors.white],
      stops: [0, .16, 1],
    ).createShader(bounds),
    child: LayoutBuilder(
      builder: (context, constraints) =>
          NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: SingleChildScrollView(
              key: const ValueKey('voice-transcript-scroll'),
              controller: _scroll,
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    28,
                    (constraints.maxHeight * .13).clamp(16.0, 42.0),
                    28,
                    18,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: widget.turns.isEmpty
                        ? [
                            Text(
                              'Take your time.\nStart wherever you like.',
                              style: TextStyle(
                                color: widget.ink.withValues(alpha: .45),
                                fontSize: 25,
                                height: 1.4,
                                letterSpacing: -.5,
                              ),
                            ),
                          ]
                        : [
                            for (var i = 0; i < widget.turns.length; i++)
                              Padding(
                                padding: EdgeInsets.only(top: i == 0 ? 0 : 22),
                                child: _turn(widget.turns[i]),
                              ),
                          ],
                  ),
                ),
              ),
            ),
          ),
    ),
  );

  Widget _turn(VoiceTranscriptTurn turn) {
    final assistant = turn.speaker == VoiceSpeaker.assistant;
    final speaker = assistant ? 'AI' : 'You';
    return Semantics(
      container: true,
      liveRegion: turn.isFinal,
      label: '$speaker: ${turn.isFinal ? turn.text : 'Speaking'}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.mode == VoiceSessionMode.conversation) ...[
              Text(
                speaker.toUpperCase(),
                style: TextStyle(
                  color: widget.ink.withValues(alpha: .52),
                  fontSize: 10,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              turn.text,
              style: TextStyle(
                color: widget.ink.withValues(alpha: assistant ? .78 : .94),
                fontSize: 23,
                height: 1.45,
                letterSpacing: -.45,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
