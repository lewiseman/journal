import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';

import 'diary_conversation.dart';
import 'pcm_recorder.dart';
import 'reply_voice.dart';
import 'voice_connection.dart';
import 'voice_store.dart';

enum TalkPhase {
  connecting,
  thinking,
  speaking,
  listening,
  transcribing,
  paused,
}

/// The microphone during the person's turn only, so the companion's own
/// voice is never sent back to the computer.
abstract class TalkMic {
  Future<void> start(void Function(Uint8List pcm) onData);
  Future<void> stop();
}

class PcmTalkMic implements TalkMic {
  final _recorder = PcmRecorder();
  File? _file;

  @override
  Future<void> start(void Function(Uint8List pcm) onData) async {
    if (!Platform.isAndroid) {
      throw const CompanionFailure(
        'UNSUPPORTED',
        'Talking currently requires Android. You can still type on the conversation page.',
      );
    }
    if (await PcmRecorder.methods.invokeMethod<bool>('permission') != true) {
      throw const CompanionFailure(
        'PERMISSION_DENIED',
        'Microphone permission was denied. Allow it in Android app settings, then continue.',
      );
    }
    // The native recorder always writes a new file; this one only lives for a
    // turn. A file left by a crash would make every later start fail, so
    // earlier ones are removed and each turn gets its own name.
    final directory = await VoiceStore().directory();
    try {
      for (final old in directory.listSync()) {
        final name = old.uri.pathSegments.last;
        if (name.startsWith('talk') && name.endsWith('.pcm')) {
          await old.delete();
        }
      }
    } catch (_) {}
    _file = File(
      '${directory.path}/talk-${DateTime.now().microsecondsSinceEpoch}.pcm',
    );
    await _recorder.start(
      path: _file!.path,
      onData: onData,
      onStopped: () {},
      onError: (_) {},
    );
  }

  @override
  Future<void> stop() async {
    try {
      await _recorder.stop();
    } finally {
      try {
        if (await _file?.exists() ?? false) await _file!.delete();
      } catch (_) {}
      _file = null;
    }
  }
}

/// A live, hands-free diary conversation with the paired computer. The
/// computer decides when the person has finished speaking, transcribes the
/// turn and streams the companion's reply; this phone speaks it and then
/// hands the microphone back. Turns are kept in [conversation].
class TalkSession extends ChangeNotifier {
  TalkSession({
    required this.conversation,
    required this.voice,
    Future<WebSocket> Function(TrustedComputer computer)? connect,
    TalkMic? mic,
  }) : connect = connect ?? ((c) => connectCompanionSocket(c, '/v1/talk/live')),
       mic = mic ?? PcmTalkMic();
  final DiaryConversation conversation;
  final ReplyVoice voice;
  final Future<WebSocket> Function(TrustedComputer computer) connect;
  final TalkMic mic;

  TalkPhase phase = TalkPhase.connecting;
  String? note;

  /// The reply as it streams in, before it is checked and spoken.
  String streaming = '';

  /// This turn's words so far, updated after each short pause.
  String heard = '';
  double level = 0;
  bool disposed = false;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _events;
  final _segments = <int, String>{};
  int _frames = 0, _generation = 0;
  bool _micOn = false, _held = false;

  /// The microphone failed to open this turn; the computer's following
  /// "nothing heard" must not replace that reason.
  bool _micFailed = false;

  void _update() {
    if (!disposed) notifyListeners();
  }

  void _pause(String? message) {
    phase = TalkPhase.paused;
    note = message;
    _update();
  }

  Future<void> start() async {
    if (disposed) return;
    phase = TalkPhase.connecting;
    note = null;
    _update();
    try {
      if (conversation.saved) {
        _pause(conversation.message);
        return;
      }
      // An older typed request is finished first so turns cannot interleave.
      if (conversation.pending != null) await conversation.retrieve();
      if (conversation.pending != null) {
        _pause(conversation.message);
        return;
      }
      final c = conversation.trusted();
      conversation.computerId ??= c.id;
      conversation.deviceId ??= c.deviceId;
      await _close();
      final socket = _socket = await connect(c);
      final ready = Completer<void>();
      _events = socket.listen(
        (raw) {
          try {
            if (raw is! String || utf8.encode(raw).length > 65536) {
              throw const FormatException();
            }
            final event = jsonDecode(raw) as Map<String, dynamic>;
            if (event['type'] == 'ready' && !ready.isCompleted) {
              ready.complete();
            } else if (event['type'] == 'error' &&
                event['fatal'] == true &&
                !ready.isCompleted) {
              ready.completeError(
                CompanionFailure(
                  event['code'] as String,
                  event['message'] as String,
                ),
              );
            } else {
              unawaited(handle(event));
            }
          } catch (_) {
            unawaited(_lost('Invalid response from the computer.'));
          }
        },
        onError: (_) => unawaited(_lost(null)),
        onDone: () => unawaited(_lost(null)),
      );
      await ready.future.timeout(const Duration(seconds: 15));
      final turns = conversation.turns;
      _send({
        'type': 'start',
        'turns': turns,
        if (turns.isEmpty) 'diary': conversation.diary?.call() ?? const [],
      });
      if (turns.isNotEmpty && turns.last['speaker'] == 'assistant') {
        unawaited(_speak(turns.last['text']!));
      } else {
        phase = TalkPhase.thinking;
        _update();
      }
    } catch (e) {
      await _close();
      _pause(
        e is CompanionFailure ? e.message : 'Could not reach your computer. Check it is on and the companion is open, then continue.',
      );
    }
  }

  @visibleForTesting
  Future<void> handle(Map<String, dynamic> event) async {
    if (disposed) return;
    switch (event['type']) {
      case 'thinking':
        streaming = '';
        if (!_held) phase = TalkPhase.thinking;
      case 'token':
        streaming += event['text'] as String;
      case 'reply':
        final text = event['text'] as String;
        streaming = '';
        await conversation.append('assistant', text);
        if (_held) {
          _pause(note);
        } else {
          unawaited(_speak(text));
        }
      case 'listening':
        if (_held) {
          // The phone left the foreground while the computer opened speech.
          _send({'type': 'done'});
          return;
        }
        _segments.clear();
        heard = '';
        _micFailed = false;
        phase = TalkPhase.listening;
        await _openMic();
      case 'segment':
        final segment = event['segment'] as Map;
        _segments[segment['id'] as int] = segment['text'] as String;
        heard = _segments.values
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .join(' ');
      case 'endpoint':
        await _closeMic();
        if (_micFailed) return;
        if (!_held) phase = TalkPhase.transcribing;
      case 'turn':
        heard = '';
        await conversation.append('user', event['text'] as String);
      case 'empty':
        await _closeMic();
        heard = '';
        if (_micFailed) return;
        _pause('Nothing was heard. Continue when you are ready.');
      case 'error':
        await _closeMic();
        if (_micFailed) return;
        streaming = '';
        _pause(event['message'] as String?);
    }
    _update();
  }

  /// Whether the latest question has been spoken (or skipped) this session.
  bool _asked = false;

  Future<void> _speak(String text) async {
    final generation = ++_generation;
    _asked = false;
    phase = TalkPhase.speaking;
    _update();
    await voice.say(text);
    if (!disposed && generation == _generation && phase == TalkPhase.speaking) {
      _listen();
    }
  }

  void _listen() {
    _asked = true;
    _generation++;
    unawaited(voice.stop());
    phase = TalkPhase.listening;
    heard = '';
    _update();
    _send({'type': 'listen'});
  }

  /// Skips the rest of the spoken question.
  void answerNow() {
    if (phase == TalkPhase.speaking) _listen();
  }

  /// Ends the person's turn without waiting for a pause.
  void done() {
    if (phase == TalkPhase.listening && _micOn) _send({'type': 'done'});
  }

  /// Picks the loop back up after a pause, an error or a lost connection.
  Future<void> resume() async {
    if (phase != TalkPhase.paused || disposed) return;
    _held = false;
    note = null;
    if (_socket?.readyState != WebSocket.open) return start();
    final turns = conversation.turns;
    if (turns.isEmpty || turns.last['speaker'] == 'user') {
      phase = TalkPhase.thinking;
      _update();
      _send({'type': 'retry'});
    } else if (_asked) {
      // The question was already heard; only the answer is missing.
      _listen();
    } else {
      await _speak(turns.last['text']!);
    }
  }

  /// Leaving the foreground: stop speaking, and send what was said so far.
  Future<void> hold() async {
    if (phase == TalkPhase.paused) return;
    _held = true;
    _generation++;
    await voice.stop();
    if (_micOn) _send({'type': 'done'});
    await _closeMic();
    _pause('Paused while the app was in the background.');
  }

  /// Finishing: lets a turn being said land first, then hangs up so the
  /// computer is free to write the diary draft.
  Future<void> end() async {
    if (phase == TalkPhase.listening && _micOn && heard.isNotEmpty) {
      done();
    }
    final until = DateTime.now().add(const Duration(seconds: 15));
    while (!disposed &&
        (phase == TalkPhase.listening || phase == TalkPhase.transcribing) &&
        heard.isNotEmpty &&
        DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    _held = true;
    _generation++;
    await voice.stop();
    await _close();
    phase = TalkPhase.paused;
    note = null;
    _update();
  }

  Future<void> _openMic() async {
    _frames = 0;
    try {
      _micOn = true;
      await mic.start((pcm) {
        if (!_micOn || _socket?.readyState != WebSocket.open) return;
        final frame = Uint8List(pcm.length + 4);
        ByteData.sublistView(frame).setUint32(0, _frames++, Endian.big);
        frame.setRange(4, frame.length, pcm);
        _socket!.add(frame);
        final samples = ByteData.sublistView(pcm);
        double energy = 0;
        for (var i = 0; i + 1 < pcm.length; i += 2) {
          final v = samples.getInt16(i, Endian.little) / 32768;
          energy += v * v;
        }
        level = (math.sqrt(energy / math.max(1, pcm.length / 2)) * 8).clamp(
          0,
          1,
        );
        _update();
      });
    } catch (e) {
      _micOn = false;
      _micFailed = true;
      _send({'type': 'done'});
      _pause(
        e is CompanionFailure
            ? e.message
            : e is PlatformException
            ? e.message ?? 'Microphone unavailable.'
            : 'Microphone unavailable.',
      );
    }
  }

  Future<void> _closeMic() async {
    if (!_micOn) return;
    _micOn = false;
    level = 0;
    try {
      await mic.stop();
    } catch (_) {}
  }

  void _send(Map<String, dynamic> value) {
    if (_socket?.readyState == WebSocket.open) _socket!.add(jsonEncode(value));
  }

  Future<void> _lost(String? message) async {
    if (disposed || _socket == null) return;
    await _close();
    _pause(
      message ?? 'The connection to your computer closed. Your turns are kept; continue to reconnect.',
    );
  }

  Future<void> _close() async {
    await _closeMic();
    final socket = _socket, events = _events;
    _socket = null;
    _events = null;
    await events?.cancel();
    await socket?.close();
  }

  @override
  void dispose() {
    disposed = true;
    _generation++;
    unawaited(voice.stop());
    unawaited(_close());
    super.dispose();
  }
}
