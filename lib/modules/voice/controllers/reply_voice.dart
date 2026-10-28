import 'package:flutter_tts/flutter_tts.dart';

/// Reads companion replies aloud with the phone's own text-to-speech.
/// Nothing is sent anywhere; [enabled] mutes it.
class ReplyVoice {
  final _tts = FlutterTts();
  bool enabled = true;
  Future<void>? _ready;

  /// Completes when the reply has finished playing, or straight away when
  /// muted or unavailable.
  Future<void> say(String text) async {
    if (!enabled) return;
    try {
      _ready ??= _tts.awaitSpeakCompletion(true);
      await _ready;
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
