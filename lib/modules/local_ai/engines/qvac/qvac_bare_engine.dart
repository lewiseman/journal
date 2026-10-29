import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/on_device_engine.dart';
import 'bare_rpc.dart';
import 'qvac_channel.dart';

class QvacBareEngine implements OnDeviceEngine {
  QvacBareEngine({QvacChannel? channel}) : _channel = channel ?? QvacChannel();
  final QvacChannel _channel;
  final _state = StreamController<EngineState>.broadcast();
  RpcClient? _rpc;
  Future<void>? _starting, _stopping;
  Future<void> _writes = Future.value();
  @override
  String get id => 'qvac-bare';
  @override
  String get displayName => 'QVAC';
  @override
  Set<AiTask> get supportedTasks => const {AiTask.writing, AiTask.image};
  @override
  Set<String> get supportedModelFormats => const {'gguf'};
  @override
  Stream<EngineState> get state => _state.stream;

  void _emit(EnginePhase phase, [String? message]) =>
      _state.add(EngineState(phase, message));
  @override
  Future<void> start() async {
    await _stopping;
    if (_rpc != null && !_rpc!.isClosed) return;
    if (_rpc != null) {
      await _rpc!.close();
      _rpc = null;
    }
    await (_starting ??= _start().whenComplete(() => _starting = null));
  }

  Future<void> _start() async {
    _emit(EnginePhase.starting);
    try {
      // A hot restart can leave a previous isolate. Attach to clean it up first.
      final status = await _channel.start();
      _rpc = RpcClient(input: _channel.bytes, send: _send);
      if (status == 'running') {
        await _shutdown();
        await _channel.start();
        _rpc = RpcClient(input: _channel.bytes, send: _send);
      }
      await _request({'method': 'ping'}).timeout(const Duration(seconds: 10));
      _emit(EnginePhase.ready);
    } catch (error) {
      await _rpc?.close();
      _rpc = null;
      _emit(
        EnginePhase.failed,
        'The bundled on-device runtime could not start.',
      );
      throw EngineFailure(
        'NOT_READY',
        error is PlatformException
            ? error.message ?? 'On-device runtime unavailable.'
            : 'The bundled on-device runtime could not start.',
      );
    }
  }

  void _send(Uint8List bytes) {
    _writes = _writes.then((_) => _channel.write(bytes)).catchError((
      Object error,
    ) {
      _emit(EnginePhase.interrupted, 'The on-device runtime disconnected.');
      unawaited(_rpc?.close() ?? Future.value());
    });
  }

  Future<Map<String, dynamic>> _request(Map<String, dynamic> data) async {
    final rpc = _rpc;
    if (rpc == null) {
      throw const EngineFailure(
        'NOT_READY',
        'Start the on-device engine first.',
      );
    }
    final response = jsonDecode(
      utf8.decode(
        await rpc
            .request(Uint8List.fromList(utf8.encode(jsonEncode(data))))
            .timeout(const Duration(minutes: 2)),
      ),
    );
    return _checked(response);
  }

  Map<String, dynamic> _checked(dynamic value) {
    if (value is! Map<String, dynamic>) {
      throw const EngineFailure(
        'INVALID_OUTPUT',
        'The runtime returned an invalid primitive response.',
      );
    }
    if (value['error'] case final Map error) {
      if (kDebugMode && error['detail'] != null) {
        debugPrint('QVAC primitive error: ${error['detail']}');
      }
      throw EngineFailure(
        error['code'] as String? ?? 'RESOURCE',
        error['message'] as String? ?? 'On-device inference failed.',
      );
    }
    return value;
  }

  @override
  Future<void> load(ModelFile file, AiTask task) async {
    if (!supportedTasks.contains(task) ||
        !supportedModelFormats.contains(file.format)) {
      throw const EngineFailure(
        'NOT_READY',
        'This model format or task is unsupported.',
      );
    }
    await _request({'method': 'load', 'path': file.path, 'task': task.name});
    _emit(EnginePhase.ready);
  }

  @override
  Future<void> unload(AiTask task) async {
    if (_rpc != null) await _request({'method': 'unload', 'task': task.name});
  }

  @override
  EngineRun<CompletionEvent> complete(
    List<AiMessage> messages, {
    required Map<String, dynamic> params,
    Map<String, dynamic>? responseFormat,
  }) {
    final id = const Uuid().v4();
    final events =
        _stream({
          'method': 'complete',
          'id': id,
          'messages': messages.map((m) => m.toJson()).toList(),
          'params': params,
          'responseFormat': responseFormat,
        }).map<CompletionEvent>(
          (event) => switch (event['type']) {
            'token' => CompletionToken(event['text'] as String),
            'done' => CompletionDone(outputLimit: event['outputLimit'] == true),
            _ => throw const EngineFailure(
              'INVALID_OUTPUT',
              'Unexpected completion event.',
            ),
          },
        );
    return EngineRun(events, () => _cancel(id));
  }

  @override
  EngineRun<ImageEvent> generateImage(
    String prompt, {
    required int width,
    required int height,
    required int steps,
    required int seed,
    String negativePrompt = '',
  }) {
    final id = const Uuid().v4();
    final events =
        _stream({
          'method': 'diffusion',
          'id': id,
          'prompt': prompt,
          'width': width,
          'height': height,
          'steps': steps,
          'seed': seed,
          'negativePrompt': negativePrompt,
        }).map<ImageEvent>(
          (event) => switch (event['type']) {
            'progress' => ImageProgress(
              event['step'] as int,
              event['total'] as int,
            ),
            'image' => ImageDone(
              base64Decode(event['png'] as String),
              seed: event['seed'] as int? ?? 0,
            ),
            _ => throw const EngineFailure(
              'INVALID_OUTPUT',
              'Unexpected image event.',
            ),
          },
        );
    return EngineRun(events, () => _cancel(id));
  }

  Stream<Map<String, dynamic>> _stream(Map<String, dynamic> input) async* {
    final rpc = _rpc;
    if (rpc == null) {
      throw const EngineFailure('NOT_READY', 'Load a model before generating.');
    }
    _emit(EnginePhase.working);
    try {
      await for (final chunk in rpc.requestStream(
        Uint8List.fromList(utf8.encode(jsonEncode(input))),
      )) {
        yield _checked(jsonDecode(utf8.decode(chunk)));
      }
    } on RpcClosedException {
      _emit(EnginePhase.interrupted, 'The on-device runtime stopped.');
      throw const EngineFailure(
        'INTERRUPTED',
        'The on-device runtime stopped. Keep Journal in the foreground.',
      );
    } finally {
      if (_rpc != null && !_rpc!.isClosed && _stopping == null) {
        _emit(EnginePhase.ready);
      }
    }
  }

  Future<void> _cancel(String id) async {
    if (_rpc != null) await _request({'method': 'cancel', 'id': id});
  }

  Future<void> _shutdown() async {
    final rpc = _rpc;
    if (rpc == null) return;
    try {
      await _request({'method': '__shutdown__'})
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      /* A terminated worker has no remaining handles to clean. */
    }
    await rpc.close();
    _rpc = null;
    await _channel.stop();
  }

  @override
  Future<void> stop() => _stopping ??= (() async {
    await _starting;
    await _shutdown();
    _emit(EnginePhase.stopped);
  })().whenComplete(() => _stopping = null);
}
