enum VoiceSessionMode { transcription, conversation }

enum VoiceSessionPhase { listening, thinking, speaking, paused, completed }

enum VoiceSpeaker { user, assistant }

/// Normalized loudness and pitch, supplied by playback or a future audio source.
class VoiceAudioActivity {
  const VoiceAudioActivity({required this.level, required this.pitch})
    : assert(level >= 0 && level <= 1),
      assert(pitch >= 0 && pitch <= 1);

  static const silent = VoiceAudioActivity(level: 0, pitch: .5);

  final double level;
  final double pitch;
}

class VoiceTranscriptTurn {
  const VoiceTranscriptTurn({
    required this.speaker,
    required this.text,
    this.isFinal = true,
  });

  final VoiceSpeaker speaker;
  final String text;
  final bool isFinal;
}

class VoiceSessionState {
  VoiceSessionState({
    required this.phase,
    Iterable<VoiceTranscriptTurn> turns = const [],
    this.activity = VoiceAudioActivity.silent,
  }) : turns = List.unmodifiable(turns);

  final VoiceSessionPhase phase;
  final List<VoiceTranscriptTurn> turns;
  final VoiceAudioActivity activity;

  bool get isActive =>
      phase != VoiceSessionPhase.paused && phase != VoiceSessionPhase.completed;
}
