import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:journal/modules/voice/models/voice_session.dart';

/// Rendering consumes this interface, independently of a future audio service.
abstract class VoiceSessionController extends ChangeNotifier {
  VoiceSessionMode get mode;
  VoiceSessionState get state;
  void start();
  void pause();
  void resume();
  void replay();

  /// Preview playback reveals complete turns when motion is reduced.
  void setReducedMotion(bool value) {}
}

/// A finite, local sample. It never opens the microphone or writes journal data.
class PreviewVoiceSessionController extends VoiceSessionController {
  PreviewVoiceSessionController({required this.mode});

  @override
  final VoiceSessionMode mode;

  late final List<_PreviewStep> _steps = _buildSteps(mode);
  VoiceSessionState _state = VoiceSessionState(
    phase: VoiceSessionPhase.listening,
  );
  VoiceSessionPhase _resumePhase = VoiceSessionPhase.listening;
  Timer? _timer;
  int _next = 0;
  bool _started = false;
  bool _disposed = false;
  bool _reduced = false;

  @override
  VoiceSessionState get state => _state;

  @override
  void start() {
    if (_disposed || _started) return;
    _started = true;
    _schedule();
  }

  @override
  void pause() {
    if (_disposed || !_state.isActive) return;
    _timer?.cancel();
    _resumePhase = _state.phase;
    _publish(VoiceSessionPhase.paused);
  }

  @override
  void resume() {
    if (_disposed || _state.phase != VoiceSessionPhase.paused) return;
    _started = true;
    _publish(_resumePhase);
    _schedule();
  }

  @override
  void replay() {
    if (_disposed) return;
    _timer?.cancel();
    _next = 0;
    _started = true;
    _state = VoiceSessionState(phase: VoiceSessionPhase.listening);
    notifyListeners();
    _schedule();
  }

  @override
  void setReducedMotion(bool value) {
    if (_disposed || value == _reduced) return;
    _reduced = value;
    if (_started && _state.isActive) {
      _timer?.cancel();
      _schedule();
    }
  }

  void _publish(VoiceSessionPhase phase) {
    _state = VoiceSessionState(
      phase: phase,
      turns: _state.turns,
      activity: _state.activity,
    );
    notifyListeners();
  }

  void _schedule() {
    if (_disposed || !_state.isActive || _next >= _steps.length) return;
    _timer?.cancel();
    final delay = _steps[_next].delay;
    var index = _next;
    if (_reduced) {
      // Skip partial words, retaining the pause before the complete turn.
      while (!_steps[index].state.turns.lastOrNullIsFinal &&
          index + 1 < _steps.length) {
        index++;
      }
    }
    _timer = Timer(delay, () {
      if (_disposed) return;
      _next = index + 1;
      _state = _steps[index].state;
      notifyListeners();
      // A listener may pause or dispose playback during notification.
      _schedule();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

extension on List<VoiceTranscriptTurn> {
  bool get lastOrNullIsFinal => isEmpty || last.isFinal;
}

class _PreviewStep {
  const _PreviewStep(this.delay, this.state);
  final Duration delay;
  final VoiceSessionState state;
}

List<_PreviewStep> _buildSteps(VoiceSessionMode mode) {
  const user = VoiceSpeaker.user;
  const ai = VoiceSpeaker.assistant;
  final script = mode == VoiceSessionMode.transcription
      ? const [
          (user, 'An idea for the weekend: take the long way to the market.'),
          (user, 'Pick up fresh flowers, and find a quiet place for coffee.'),
          (
            user,
            'I want to leave a little room in the day for something unplanned.',
          ),
          (user, 'There’s also that book I’ve been meaning to start.'),
          (
            user,
            'Maybe I’ll bring it along, turn my phone over, and read for a while.',
          ),
          (
            user,
            'Nothing complicated. Just a slower morning, and a little time to myself.',
          ),
        ]
      : const [
          (
            user,
            'Today felt a little full. I kept moving from one thing to the next.',
          ),
          (
            user,
            'But on the way home I noticed the light through the trees, and slowed down.',
          ),
          (
            ai,
            'That sounds like a small moment of calm. What made it feel different?',
          ),
          (
            user,
            'I wasn’t trying to get anywhere for a minute. I could just be there.',
          ),
          (user, 'I think I’d like to make more room for that tomorrow.'),
          (
            ai,
            'A little room to pause. That seems like a gentle thing to carry into tomorrow.',
          ),
        ];
  final steps = <_PreviewStep>[];
  final turns = <VoiceTranscriptTurn>[];
  for (final (speaker, text) in script) {
    if (speaker == ai) {
      steps.add(
        _PreviewStep(
          const Duration(milliseconds: 1100),
          VoiceSessionState(phase: VoiceSessionPhase.thinking, turns: turns),
        ),
      );
    }
    final words = text.split(' ');
    for (var count = 2; count < words.length + 2; count += 2) {
      final end = count.clamp(0, words.length);
      final turn = VoiceTranscriptTurn(
        speaker: speaker,
        text: words.take(end).join(' '),
        isFinal: end == words.length,
      );
      steps.add(
        _PreviewStep(
          Duration(milliseconds: count == 2 ? 850 : 340),
          VoiceSessionState(
            phase: speaker == ai
                ? VoiceSessionPhase.speaking
                : VoiceSessionPhase.listening,
            turns: [...turns, turn],
            activity: _sampleActivity(turn.text),
          ),
        ),
      );
    }
    turns.add(VoiceTranscriptTurn(speaker: speaker, text: text));
    // Let the glow settle between phrases instead of pulsing through silence.
    steps.add(
      _PreviewStep(
        const Duration(milliseconds: 240),
        VoiceSessionState(
          phase: speaker == ai
              ? VoiceSessionPhase.speaking
              : VoiceSessionPhase.listening,
          turns: turns,
        ),
      ),
    );
  }
  steps.add(
    _PreviewStep(
      const Duration(milliseconds: 1500),
      VoiceSessionState(phase: VoiceSessionPhase.completed, turns: turns),
    ),
  );
  return steps;
}

VoiceAudioActivity _sampleActivity(String text) {
  // Repeatable variation keeps the preview lively without reading the mic.
  final seed = text.codeUnits.fold(
    7,
    (value, unit) => (value * 31 + unit) & 0x7fffffff,
  );
  return VoiceAudioActivity(
    level: .38 + (seed % 100) / 100 * .58,
    pitch: .18 + (seed ~/ 101 % 100) / 100 * .70,
  );
}
