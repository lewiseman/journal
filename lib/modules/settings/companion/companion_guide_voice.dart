import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:journal/modules/voice/controllers/reply_voice.dart';

/// Only speaks the setup instructions, on request. Never reads journal data.
abstract interface class CompanionGuideVoice {
  Future<void> speak(String text);
  Future<void> stop();
}

final companionGuideVoiceProvider = Provider<CompanionGuideVoice>((ref) {
  final voice = _PhoneGuideVoice();
  ref.onDispose(voice.stop);
  return voice;
});

class _PhoneGuideVoice implements CompanionGuideVoice {
  FlutterTts? _tts;
  Future<void>? _ready;
  int _generation = 0;

  Future<void> _setup(FlutterTts tts) async {
    await tts.awaitSpeakCompletion(true);
    await tts.setLanguage('en');
    await tts.setSpeechRate(.42);
    final voice = savedReplyVoice();
    if (voice != null) {
      try {
        await applyReplyVoice(tts, voice);
      } catch (_) {
        // A removed voice falls back to the phone's English voice.
      }
    }
  }

  @override
  Future<void> speak(String text) async {
    final generation = ++_generation;
    final tts = _tts ??= FlutterTts();
    try {
      await (_ready ??= _setup(tts));
    } catch (_) {
      _ready = null;
      rethrow;
    }
    if (generation != _generation) return;
    await tts.stop();
    if (generation != _generation) return;
    final result = await tts.speak(text);
    if (result == 0) throw StateError('Speech unavailable');
  }

  @override
  Future<void> stop() async {
    _generation++;
    try {
      await _tts?.stop();
    } catch (_) {
      // Closing the page should also work when speech is unavailable.
    }
  }
}
