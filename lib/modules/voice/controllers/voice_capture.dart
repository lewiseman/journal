import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';

import 'voice_connection.dart';
import 'voice_store.dart';
import 'pcm_recorder.dart';

enum CapturePhase {
  idle,
  connecting,
  recording,
  stopping,
  processing,
  review,
  error,
}

class VoiceCapture extends ChangeNotifier {
  VoiceCapture({
    required this.target,
    required this.computer,
    VoiceStore? store,
    CompanionTransport Function()? transportFactory,
  }) : store = store ?? VoiceStore(),
       transportFactory = transportFactory ?? PinnedCompanionTransport.new;
  final String target;
  final TrustedComputer Function() computer;
  final VoiceStore store;
  final CompanionTransport Function() transportFactory;
  static const methods = MethodChannel('journal/pcm');
  CapturePhase phase = CapturePhase.idle;
  String? message, id, computerId, deviceId, interruption;
  bool canTranscribeAgain = false;
  bool accepted = false, disposed = false, _finishing = false;
  double level = 0;
  String text = '', prefix = '';
  List<String> previousIds = [];
  bool _discarding = false;
  int _generation = 0;
  int created = 0, bytes = 0, _frames = 0, _acked = 0;
  File? audio;
  WebSocket? _socket;
  final _mic = PcmRecorder();
  StreamSubscription<dynamic>? _network;
  Timer? _limit;
  final _segments = <int, String>{};
  Completer<void>? _ready;
  Completer<void>? _drained;
  Future<void> _saves = Future.value();
  bool get recording => phase == CapturePhase.recording;
  void update() {
    if (!disposed) notifyListeners();
  }

  Future<void> persist() {
    if (id == null || disposed || _discarding) return Future.value();
    final value = {
      'id': id,
      'computer': computerId,
      'device': deviceId,
      'created': created,
      'text': text,
      'accepted': accepted,
      'canTranscribeAgain': canTranscribeAgain,
      'interruption': interruption,
      'prefix': prefix,
      'previousIds': List<String>.from(previousIds),
    };
    _saves = _saves.catchError((_) {}).then((_) => store.save(target, value));
    return _saves;
  }

  Future<void> restore() async {
    final generation = ++_generation;
    phase = CapturePhase.connecting;
    message = 'Checking for a retained recording…';
    update();
    try {
      final data = await store.load(target);
      unawaited(store.cleanup().catchError((_) {}));
      if (disposed || generation != _generation) return;
      if (data == null) {
        phase = CapturePhase.idle;
        message = null;
        update();
        return;
      }
      id = data['id'] as String;
      computerId = data['computer'] as String?;
      deviceId = data['device'] as String?;
      created = data['created'] as int;
      text = data['text'] as String? ?? '';
      prefix = data['prefix'] as String? ?? '';
      previousIds = (data['previousIds'] as List? ?? []).cast<String>();
      accepted = data['accepted'] == true;
      canTranscribeAgain = data['canTranscribeAgain'] == true;
      interruption = data['interruption'] as String?;
      audio = File('${(await store.directory()).path}/$id.pcm');
      bytes = await audio!.exists() ? await audio!.length() : 0;
      phase = text.isNotEmpty ? CapturePhase.review : CapturePhase.error;
      message = 'Recovered recording. Retrieve accepted work, or resend retained audio explicitly. Nothing has been saved to your journal.';
      update();
    } catch (_) {
      fail(
        'Could not unlock the voice draft. Unlock the phone and reopen this screen.',
      );
    }
  }

  void fail(String value) {
    phase = CapturePhase.error;
    message = value;
    level = 0;
    update();
  }

  TrustedComputer _trusted() {
    final c = computer();
    if (!c.enabled ||
        (computerId != null &&
            (computerId != c.id || deviceId != c.deviceId))) {
      throw const CompanionFailure(
        'UNAUTHORIZED',
        'This recording belongs to another pairing. Restore that pairing or discard this recording.',
      );
    }
    return c;
  }

  Future<void> start() async {
    if (disposed || id != null || phase == CapturePhase.connecting) return;
    if (!Platform.isAndroid) {
      fail(
        'Microphone capture currently requires Android. Diary conversation also supports typing.',
      );
      return;
    }
    final generation = ++_generation;
    phase = CapturePhase.connecting;
    message = 'Checking microphone permission…';
    update();
    try {
      if (await methods.invokeMethod<bool>('permission') != true) {
        throw const CompanionFailure(
          'PERMISSION_DENIED',
          'Microphone permission was denied. Allow it in Android app settings, then retry.',
        );
      }
      if (disposed || generation != _generation) return;
      final c = _trusted();
      id = const Uuid().v4();
      computerId = c.id;
      deviceId = c.deviceId;
      created = DateTime.now().millisecondsSinceEpoch;
      audio = File('${(await store.directory()).path}/$id.pcm');
      await persist();
      if (disposed || generation != _generation) return;
      await _connect(c);
      if (disposed || generation != _generation) {
        await _close();
        return;
      }
      phase = CapturePhase.recording;
      message = 'Listening on Android · words appear after short pauses';
      update();
      await _mic.start(
        path: audio!.path,
        onData: (event) {
          if (!_finishing && !_discarding) {
            bytes += event.length;
            _send(event);
            final samples = ByteData.sublistView(event);
            double energy = 0;
            for (var i = 0; i + 1 < event.length; i += 2) {
              final v = samples.getInt16(i, Endian.little) / 32768;
              energy += v * v;
            }
            level = (math.sqrt(energy / math.max(1, event.length / 2)) * 8)
                .clamp(0, 1);
            update();
          }
        },
        onStopped: () {
          if (recording) unawaited(stop());
        },
        onError: (Object error) {
          if (recording) {
            interruption = error is PlatformException
                ? error.message
                : 'Recording was interrupted.';
            unawaited(stop());
          }
        },
      );
      if (disposed || generation != _generation) {
        await _stopMic();
        await _close();
        return;
      }
      _limit = Timer(const Duration(minutes: 10), () => unawaited(stop()));
    } catch (e) {
      await _stopMic();
      await _close();
      if (disposed || generation != _generation) return;
      await _resetUnrecordedAttempt();
      fail(
        e is CompanionFailure
            ? e.message
            : e is PlatformException
            ? e.message ?? 'Microphone unavailable.'
            : 'Could not reach speech on your computer. Load Whisper and Silero VAD, then retry.',
      );
    }
  }

  Future<void> _connect(TrustedComputer c) async {
    _frames = 0;
    _acked = 0;
    _segments.clear();
    _ready = Completer<void>();
    // Consume errors immediately even if connection setup fails before awaiting.
    _ready!.future.ignore();
    _socket = await connectVoice(c, id!);
    _network = _socket!.listen(
      (raw) {
        try {
          if (raw is! String || utf8.encode(raw).length > 65536) {
            throw const FormatException();
          }
          final event = jsonDecode(raw) as Map<String, dynamic>;
          switch (event['type']) {
            case 'ready':
              if (!(_ready?.isCompleted ?? true)) _ready!.complete();
            case 'ack':
              final next = event['next'] as int;
              if (next < _acked || next > _frames) {
                throw const FormatException();
              }
              _acked = next;
              if (_acked == _frames && !(_drained?.isCompleted ?? true)) {
                _drained!.complete();
              }
            case 'segment':
              final segment = event['segment'] as Map;
              _segments[segment['id'] as int] = segment['text'] as String;
              text = [
                prefix,
                _segments.values
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .join(' '),
              ].where((s) => s.trim().isNotEmpty).join(' ');
              update();
              unawaited(
                persist().catchError((_) {
                  fail(
                    'Could not protect the transcript. Stop recording and keep the original audio.',
                  );
                }),
              );
            case 'accepted':
              accepted = true;
              phase = CapturePhase.processing;
              message = 'Accepted on your computer. You can close this screen and retrieve the result later.';
              update();
              unawaited(
                persist().catchError((_) {
                  fail(
                    'Could not protect the transcript. Keep the original recording.',
                  );
                }),
              );
            case 'job':
              final job = Map<String, dynamic>.from(event['job'] as Map);
              unawaited(
                _consumeJob(job).catchError((_) {
                  fail(
                    'Invalid speech result or protected storage failure. Retain the audio and retry.',
                  );
                }),
              );
              if (!(_ready?.isCompleted ?? true)) _ready!.complete();
            case 'error':
              final error = CompanionFailure(
                event['code'] as String,
                event['message'] as String,
              );
              if (!(_ready?.isCompleted ?? true)) _ready!.completeError(error);
              fail(error.message);
              unawaited(_stopMic());
          }
        } catch (_) {
          fail('Invalid speech response. Keep the recording and retry.');
          unawaited(_stopMic());
        }
      },
      onError: (_) {
        _disconnected();
      },
      onDone: _disconnected,
    );
    await _ready!.future.timeout(const Duration(seconds: 15));
  }

  void _disconnected() {
    if (disposed ||
        phase == CapturePhase.review ||
        phase == CapturePhase.error) {
      return;
    }
    if (!(_ready?.isCompleted ?? true)) {
      _ready!.completeError(
        const CompanionFailure('UNAVAILABLE', 'Speech connection closed.'),
      );
    }
    if (recording) unawaited(_stopMic());
    if (phase != CapturePhase.review) {
      fail(
        accepted
            ? 'Connection closed. Your accepted task can be retrieved from the computer.'
            : 'Connection interrupted before acceptance. Retained phone audio can be resent explicitly.',
      );
    }
  }

  void _send(Uint8List pcm) {
    if (_socket?.readyState != WebSocket.open) return;
    // At most two seconds can be in flight. Stop the microphone instead of
    // building an unlimited mobile/network buffer or silently dropping speech.
    if (_frames - _acked >= 20) {
      unawaited(_stopMic());
      fail(
        'The computer fell behind. Recording stopped; resend retained audio to transcribe the complete recording.',
      );
      _socket?.close();
      return;
    }
    final frame = Uint8List(pcm.length + 4);
    ByteData.sublistView(frame).setUint32(0, _frames++, Endian.big);
    frame.setRange(4, frame.length, pcm);
    _socket!.add(frame);
  }

  Future<void> _stopMic() async {
    _limit?.cancel();
    await _mic.stop();
    level = 0;
  }

  Future<void> _waitFrames() async {
    if (_acked == _frames) return;
    _drained = Completer<void>();
    await _drained!.future.timeout(const Duration(seconds: 10));
  }

  Future<void> stop() async {
    if (!recording || _finishing) return;
    phase = CapturePhase.stopping;
    update();
    try {
      await _stopMic();
      _finishing = true;
      await _finish();
    } catch (_) {
      fail(
        'Recording stopped before acceptance. Retry sends the complete retained audio.',
      );
    } finally {
      _finishing = false;
      await persist();
    }
  }

  Future<void> _finish() async {
    final pcm = await audio!.readAsBytes();
    if (pcm.isEmpty ||
        pcm.length != bytes ||
        _socket?.readyState != WebSocket.open) {
      throw const FormatException();
    }
    await _waitFrames();
    phase = CapturePhase.processing;
    message =
        'Uploading · not accepted until the computer confirms complete audio';
    update();
    _socket!.add(
      jsonEncode({
        'type': 'finish',
        'bytes': pcm.length,
        'frames': _frames,
        'sha256': await hexHash(pcm),
      }),
    );
  }

  Future<void> retry() async {
    if (id == null ||
        recording ||
        phase == CapturePhase.connecting ||
        phase == CapturePhase.processing) {
      return;
    }
    phase = CapturePhase.connecting;
    message = 'Checking accepted work…';
    update();
    final transport = transportFactory();
    try {
      final c = _trusted();
      try {
        final job = await CompanionClient(transport)
            .authenticated(c, 'GET', '/v1/voice/$id');
        await _consumeJob(job);
        return;
      } on CompanionFailure catch (e) {
        if (e.code != 'NOT_FOUND' || accepted) rethrow;
      }
      if (audio == null ||
          !await audio!.exists() ||
          await audio!.length() == 0) {
        if (await _resetUnrecordedAttempt()) {
          phase = CapturePhase.idle;
          message = 'Recording did not start; no audio was captured. Load speech on the computer, then tap Record.';
          update();
          return;
        }
        throw const CompanionFailure(
          'NO_AUDIO',
          'Original audio is unavailable. Review recovered text or discard this session.',
        );
      }
      bytes = 0;
      await _close();
      await _connect(c);
      if (accepted || phase == CapturePhase.review) return;
      final pcm = await audio!.readAsBytes();
      for (var offset = 0; offset < pcm.length; offset += 3200) {
        final ackDeadline = DateTime.now().add(const Duration(seconds: 15));
        while (_frames - _acked >= 8) {
          if (DateTime.now().isAfter(ackDeadline)) {
            throw const CompanionFailure(
              'TIMEOUT',
              'The computer stopped acknowledging audio. Keep the recording and retry.',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
          if (_socket?.readyState != WebSocket.open) {
            throw const FormatException();
          }
        }
        final chunk = Uint8List.sublistView(
          pcm,
          offset,
          math.min(offset + 3200, pcm.length),
        );
        bytes += chunk.length;
        _send(chunk);
      }
      await _finish();
    } catch (e) {
      fail(
        e is CompanionFailure
            ? e.message
            : 'Could not retrieve or resend the recording. Keep it and retry.',
      );
    } finally {
      transport.close();
    }
  }

  Future<void> _consumeJob(Map<String, dynamic> job) async {
    if (job['id'] != id || job['device'] != deviceId) {
      throw const FormatException();
    }
    accepted = job['accepted'] == true;
    canTranscribeAgain = [
      'failed',
      'cancelled',
      'expired',
    ].contains(job['state']);
    if (job['state'] == 'completed' && job['acknowledged'] != true) {
      final segments = job['segments'] as List;
      text = [
        prefix,
        segments
            .map((s) => (s as Map)['text'] as String)
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .join(' '),
      ].where((s) => s.trim().isNotEmpty).join(' ');
      phase = CapturePhase.review;
      message = text.isEmpty
          ? 'No speech detected. Silence is never replaced with sample text.'
          : 'Correct any words before using this transcript. Language is preserved; nothing has been saved.';
    } else if (['queued', 'running'].contains(job['state'])) {
      phase = CapturePhase.error;
      message = 'Accepted work is still processing. Tap Retrieve again shortly; it continues if this app closes.';
    } else {
      phase = CapturePhase.error;
      message =
          'Recording ${job['state']}. Review any retained text or discard this session.';
    }
    if (interruption != null) message = '$interruption ${message ?? ''}';
    update();
    await persist();
  }

  /// Called only after a failed startup or a verified NOT_FOUND response.
  /// Never delete nonempty audio, reviewed text, or an accepted task receipt.
  Future<bool> _resetUnrecordedAttempt() async {
    if (accepted ||
        bytes > 0 ||
        text.trim().isNotEmpty ||
        prefix.trim().isNotEmpty ||
        previousIds.isNotEmpty) {
      return false;
    }
    final file = audio;
    if (file != null && await file.exists() && await file.length() > 0) {
      return false;
    }
    await _saves.catchError((_) {});
    await store.clear(target);
    id = null;
    computerId = null;
    deviceId = null;
    audio = null;
    canTranscribeAgain = false;
    return true;
  }

  Future<void> transcribeAgain() async {
    if (!canTranscribeAgain ||
        disposed ||
        recording ||
        audio == null ||
        id == null) {
      return;
    }
    canTranscribeAgain = false;
    phase = CapturePhase.connecting;
    update();
    try {
      final original = audio!;
      if (!await original.exists()) {
        fail(
          'The original phone audio has expired or is unavailable. Review retained text or discard this session.',
        );
        return;
      }
      await _close();
      final nextId = const Uuid().v4();
      final copy = await original.copy(
        '${(await store.directory()).path}/$nextId.pcm',
      );
      if (disposed) return;
      previousIds.add(id!);
      id = nextId;
      audio = copy;
      accepted = false;
      canTranscribeAgain = false;
      created = DateTime.now().millisecondsSinceEpoch;
      text = prefix;
      phase = CapturePhase.error;
      await persist();
      // This is an explicit new task using retained original audio. A normal
      // reconnect always retrieves the old ID and cannot rerun it accidentally.
      await retry();
    } catch (_) {
      fail(
        'Could not retry the retained audio. Keep the recording and try again.',
      );
    }
  }

  Future<void> continueRecording(String reviewed) async {
    if (phase != CapturePhase.review || id == null || disposed) return;
    interruption = null;
    prefix = reviewed.trim();
    previousIds.add(id!);
    id = null;
    accepted = false;
    bytes = 0;
    await _close();
    phase = CapturePhase.idle;
    await start();
  }

  Future<void> discard() async {
    _generation++;
    _discarding = true;
    phase = CapturePhase.stopping;
    // Taken before awaiting: a second tap or a finishing recording can clear
    // [id] meanwhile.
    final current = id, previous = [...previousIds];
    await _stopMic();
    await _close();
    if (current != null) {
      final transport = transportFactory();
      try {
        final c = _trusted();
        final client = CompanionClient(transport);
        await client.authenticated(c, 'POST', '/v1/voice/$current/cancel');
        await client.authenticated(c, 'POST', '/v1/voice/$current/ack');
      } catch (_) {
        /* Local deletion is immediate; remote work expires in 24h. */
      } finally {
        transport.close();
      }
      await store.deleteAudio(current);
    }
    for (final id in previous) {
      await store.deleteAudio(id);
    }
    await _saves.catchError((_) {});
    await store.clear(target);
    id = null;
    computerId = null;
    deviceId = null;
    text = '';
    interruption = null;
    prefix = '';
    previousIds = [];
    _discarding = false;
    accepted = false;
    canTranscribeAgain = false;
    bytes = 0;
    _segments.clear();
    phase = CapturePhase.idle;
    message = null;
    update();
  }

  Future<void> _close() async {
    await _network?.cancel();
    _network = null;
    await _socket?.close();
    _socket = null;
  }

  @override
  void dispose() {
    disposed = true;
    _limit?.cancel();
    unawaited(_stopMic());
    unawaited(_close());
    super.dispose();
  }
}
