import 'package:flutter_tts/flutter_tts.dart';
import 'package:journal/utils/cache.dart';

/// The engine and voice chosen in Settings, or null for the phone's default.
Map<String, String>? savedReplyVoice() {
  try {
    final v = CacheStorage.instance.get(replyVoiceKey);
    if (v == null || v['name'] is! String || v['locale'] is! String) {
      return null;
    }
    return {
      if (v['engine'] is String) 'engine': v['engine'] as String,
      'name': v['name'] as String,
      'locale': v['locale'] as String,
    };
  } catch (_) {
    return null;
  }
}

/// Points [tts] at [voice]'s engine first, since switching engines resets
/// the voice.
Future<void> applyReplyVoice(FlutterTts tts, Map<String, String> voice) async {
  if (voice['engine'] != null) await tts.setEngine(voice['engine']!);
  await tts.setVoice({'name': voice['name']!, 'locale': voice['locale']!});
}

/// Reads companion replies aloud with the phone's own text-to-speech.
/// Nothing is sent anywhere; [enabled] mutes it.
class ReplyVoice {
  final _tts = FlutterTts();
  bool enabled = true;
  Future<void>? _ready;

  Future<void> _setup() async {
    await _tts.awaitSpeakCompletion(true);
    final voice = savedReplyVoice();
    if (voice == null) return;
    try {
      await applyReplyVoice(_tts, voice);
    } catch (_) {
      // An uninstalled engine or voice falls back to the phone's default.
    }
  }

  /// Completes when the reply has finished playing, or straight away when
  /// muted or unavailable.
  Future<void> say(String text) async {
    if (!enabled) return;
    try {
      _ready ??= _setup();
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
