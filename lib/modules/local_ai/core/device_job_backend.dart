import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/widgets.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';

import '../models/model_catalog.dart';
import '../models/model_downloader.dart';
import '../models/model_storage.dart';
import 'on_device_engine.dart';
import 'operation_runner.dart';

/// Foreground results stay in memory for 24 hours. Durable metadata receipts
/// prevent duplicate generation even when a process dies before acceptance is
/// confirmed. After restart unfinished or uncollected jobs become interrupted.
class DeviceJobBackend {
  DeviceJobBackend({
    required this.engine,
    required this.storage,
    required this.downloader,
  }) {
    _lifecycle = AppLifecycleListener(
      onStateChange: (value) {
        if (value != AppLifecycleState.resumed) unawaited(interrupt());
      },
    );
  }
  final OnDeviceEngine engine;
  final ModelStorage storage;
  final ModelDownloader downloader;
  late final AppLifecycleListener _lifecycle;
  final _jobs = <String, Map<String, dynamic>>{};
  final _images = <String, Uint8List>{};
  final _fingerprints = <String, String>{};
  Future<void>? _receiptsReady;
  Future<void> _receiptWrites = Future.value();
  Future<void>? _active;
  bool _reserved = false;
  bool get busy => _reserved || _active != null;
  String? _activeId;
  Future<void> Function()? _cancel;
  bool _disposed = false;
  final _runner = OperationRunner.loadOperations();

  Future<void> _readReceipts() async {
    final file = File('${(await storage.directory()).path}/.device_jobs.json');
    if (!await file.exists()) return;
    try {
      final decoded = jsonDecode(await file.readAsString()) as Map;
      if (decoded['version'] != 1) throw const FormatException();
      for (final row in (decoded['jobs'] as List)) {
        final j = Map<String, dynamic>.from(row as Map);
        final id = j['id'] as String;
        if (j['expires'] is! int ||
            j['operation'] is! String ||
            j['fingerprint'] is! String) {
          throw const FormatException();
        }
        _fingerprints[id] = j.remove('fingerprint') as String;
        if (['queued', 'running'].contains(j['state']) ||
            (j['state'] == 'completed' && j['acknowledged'] != true)) {
          j['state'] = 'interrupted';
          j['error'] = 'INTERRUPTED';
        }
        _jobs[id] = j;
      }
    } catch (_) {
      throw const CompanionFailure(
        'NOT_READY',
        'The local task receipts could not be read. No task was submitted again.',
      );
    }
  }

  Future<void> _persistReceipts() {
    final next = _receiptWrites.then((_) async {
      // Bound acknowledged metadata; active and unknown-acceptance tombstones
      // remain until expiry so they can never trigger duplicate generation.
      while (_jobs.length > 256) {
        final oldest = _jobs.keys
            .where((id) => _jobs[id]!['acknowledged'] == true)
            .firstOrNull;
        if (oldest == null) break;
        _jobs.remove(oldest);
        _fingerprints.remove(oldest);
      }
      final rows = [
        for (final j in _jobs.values)
          {
            for (final key in [
              'id',
              'operation',
              'device',
              'model',
              'state',
              'expires',
              'acknowledged',
              'error',
            ])
              if (j.containsKey(key)) key: j[key],
            'fingerprint': _fingerprints[j['id']],
          },
      ];
      final path = '${(await storage.directory()).path}/.device_jobs.json';
      final temporary = File('$path.tmp');
      await temporary.writeAsString(
        jsonEncode({'version': 1, 'jobs': rows}),
        flush: true,
      );
      await temporary.rename(path);
    });
    _receiptWrites = next.catchError((Object _) {});
    return next;
  }

  void _sweep() {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final id in _jobs.keys.toList()) {
      if ((_jobs[id]!['expires'] as int) <= now) {
        if (id == _activeId) unawaited(_cancel?.call() ?? Future.value());
        _jobs[id]!['state'] = 'expired';
        _jobs.remove(id);
        _images.remove(id);
        _fingerprints.remove(id);
      }
    }
  }

  Future<Map<String, dynamic>> request(
    String method,
    String route, {
    Map<String, dynamic>? body,
  }) async {
    await (_receiptsReady ??= _readReceipts());
    _sweep();
    if (_disposed) {
      throw const CompanionFailure('UNAVAILABLE', 'On-device AI has stopped.');
    }
    final parts = route.split('/');
    if (method == 'POST' && route == '/v1/jobs') return _submit(body!);
    if (parts.length < 4) {
      throw const CompanionFailure('NOT_FOUND', 'Unknown local job route.');
    }
    final id = parts[3], job = _jobs[parts[3]];
    if (job == null) {
      throw const CompanionFailure(
        'NOT_FOUND',
        'The phone no longer has this job.',
      );
    }
    if (method == 'POST' && parts.last == 'cancel') {
      if (['queued', 'running'].contains(job['state'])) {
        job['state'] = 'cancelled';
        job['error'] = 'CANCELLED';
        if (_activeId == id) await _cancel?.call();
      }
    } else if (method == 'POST' && parts.last == 'ack') {
      if (['queued', 'running'].contains(job['state'])) {
        throw const CompanionFailure('BUSY', 'This task is still running.');
      }
      job['acknowledged'] = true;
      job.remove('text');
      _images.remove(id);
    } else if (method == 'GET' && parts.last == 'result') {
      final bytes = _images[id];
      if (bytes == null || job['state'] != 'completed') {
        throw const CompanionFailure(
          'NOT_FOUND',
          'This local image is no longer available.',
        );
      }
      return {'id': id, 'image': base64Encode(bytes)};
    } else if (method != 'GET' || parts.length != 4) {
      throw const CompanionFailure('NOT_FOUND', 'Unknown local job route.');
    }
    await _persistReceipts();
    return Map.of(job);
  }

  Future<Map<String, dynamic>> _submit(Map<String, dynamic> body) async {
    final id = body['id'] as String, operation = body['operation'] as String;
    final identity = jsonEncode([
      operation,
      body['prompt'],
      body['expires'],
      body['modelId'],
    ]);
    final fingerprint = (await Sha256().hash(utf8.encode(identity))).bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    if (_jobs[id] case final job?) {
      if (_fingerprints[id] != fingerprint) {
        throw const CompanionFailure(
          'CONFLICT',
          'This job ID already belongs to different input.',
        );
      }
      return Map.of(job);
    }
    if (_jobs.values.where((j) => j['acknowledged'] != true).length >= 64) {
      throw const CompanionFailure(
        'RESOURCE',
        'Clear or acknowledge previous local tasks first.',
      );
    }
    if (busy) {
      throw const CompanionFailure(
        'BUSY',
        'Wait for the current task on this phone.',
      );
    }
    if (WidgetsBinding.instance.lifecycleState != null &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      throw const CompanionFailure(
        'NOT_READY',
        'Keep Journal in the foreground to use on-device AI.',
      );
    }
    final model = body.remove('_model') as CatalogModel;
    final expires = body['expires'] as int;
    if (expires <= DateTime.now().millisecondsSinceEpoch ||
        expires >
            DateTime.now()
                    .add(const Duration(hours: 24))
                    .millisecondsSinceEpoch +
                1000) {
      throw const CompanionFailure(
        'INVALID_INPUT',
        'This job has an invalid expiry.',
      );
    }
    final job = <String, dynamic>{
      'id': id,
      'operation': operation,
      'device': 'this-phone',
      'model': model.id,
      'state': 'queued',
      'expires': expires,
      'acknowledged': false,
    };
    _jobs[id] = job;
    _fingerprints[id] = fingerprint;
    _activeId = id;
    _reserved = true;
    // Acceptance must survive a process death even if the reply is lost. Only
    // metadata + a hash are persisted; prompts, outputs and images stay in RAM.
    try {
      await _persistReceipts();
    } catch (_) {
      _reserved = false;
      _jobs.remove(id);
      _fingerprints.remove(id);
      _activeId = null;
      throw const CompanionFailure(
        'RESOURCE',
        'The phone could not save a task receipt. Free some storage and retry.',
      );
    }
    _active =
        (() async {
          try {
            final runner = OperationRunner(engine, await _runner);
            await _run(job, body, model, runner);
          } catch (_) {
            job['state'] = 'failed';
            job['error'] = 'NOT_READY';
          }
        })().whenComplete(() {
          _reserved = false;
          _active = null;
          _activeId = null;
          _cancel = null;
        });
    return Map.of(job);
  }

  Future<void> _run(
    Map<String, dynamic> job,
    Map<String, dynamic> input,
    CatalogModel model,
    OperationRunner runner,
  ) async {
    final operation = job['operation'] as String;
    try {
      final resources = await storage.resources();
      if (resources.ramBytes < model.minRamBytes * 0.9) {
        throw const EngineFailure(
          'RESOURCE',
          'This model needs more memory. Choose a smaller model.',
        );
      }
      final file = await downloader.file(model);
      if (!await downloader.verify(file, model)) {
        throw const EngineFailure(
          'NOT_READY',
          'Download and verify the assigned model first.',
        );
      }
      if (job['state'] != 'queued') return;
      await engine.start();
      if (job['state'] != 'queued') return;
      await engine.load(
        ModelFile(id: model.id, path: file.path, format: model.format),
        model.task,
      );
      if (job['state'] != 'queued') return;
      job['state'] = 'running';
      if (model.task == AiTask.image) {
        final run = runner.image(operation, input['prompt'] as String);
        _cancel = run.cancel;
        Uint8List? image;
        var imageSeed = 0;
        await for (final event in run.events.timeout(
          const Duration(minutes: 5),
        )) {
          if (job['state'] != 'running') break;
          switch (event) {
            case ImageProgress(:final step, :final total):
              job['progress'] = {'step': step, 'total': total};
            case ImageDone(:final bytes, :final seed):
              image = bytes;
              imageSeed = seed;
          }
        }
        if (job['state'] != 'running') return;
        if (image == null ||
            image.length < 24 ||
            image.length > 4 * 1024 * 1024 ||
            base64Encode(image.sublist(0, 8)) != 'iVBORw0KGgo=') {
          throw const EngineFailure(
            'INVALID_OUTPUT',
            'The image model returned an invalid PNG.',
          );
        }
        final spec = runner.spec(operation), data = ByteData.sublistView(image);
        if (data.getUint32(16) != spec['width'] ||
            data.getUint32(20) != spec['height']) {
          throw const EngineFailure(
            'INVALID_OUTPUT',
            'The generated image has unexpected dimensions.',
          );
        }
        final digest = await Sha256().hash(image);
        final text = jsonEncode({
          'width': data.getUint32(16),
          'height': data.getUint32(20),
          'bytes': image.length,
          'sha256': digest.bytes
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join(),
          'seed': imageSeed,
        });
        runner.validate(operation, text);
        _images[job['id']] = image;
        job['text'] = text;
      } else {
        final run = runner.complete(
          operation,
          input['prompt'] as String,
          reasoningBudget: model.reasoningBudget,
        );
        _cancel = run.cancel;
        final output = StringBuffer();
        var done = false;
        final limit = runner.spec(operation)['limits']['outputBytes'] as int;
        await for (final event in run.events.timeout(
          const Duration(minutes: 3),
        )) {
          if (job['state'] != 'running') break;
          switch (event) {
            case CompletionToken(:final text):
              output.write(text);
              if (utf8.encode(output.toString()).length > limit) {
                throw const EngineFailure(
                  'INVALID_OUTPUT',
                  'The result exceeded the output limit.',
                );
              }
            case CompletionDone(:final outputLimit):
              if (outputLimit) {
                throw const EngineFailure(
                  'INVALID_OUTPUT',
                  'The model reached its output limit.',
                );
              }
              done = true;
          }
        }
        if (job['state'] != 'running') return;
        if (!done) {
          throw const EngineFailure(
            'INVALID_OUTPUT',
            'The model stream ended before completion.',
          );
        }
        final text = output.toString().trim();
        runner.validate(
          operation,
          text,
          source: input['localSource'] as String?,
        );
        job['text'] = text;
      }
      if (job['state'] == 'running') job['state'] = 'completed';
    } catch (error) {
      if (['queued', 'running'].contains(job['state'])) {
        job['state'] = error is EngineFailure && error.code == 'CANCELLED'
            ? 'cancelled'
            : error is EngineFailure && error.code == 'INTERRUPTED'
            ? 'interrupted'
            : 'failed';
        if (error is EngineFailure) job['message'] = error.message;
        job['error'] = error is EngineFailure
            ? error.code
            : error is TimeoutException
            ? 'RESOURCE'
            : 'INVALID_OUTPUT';
      }
      try {
        await _cancel?.call();
      } catch (_) {}
    } finally {
      try {
        await engine.unload(model.task);
      } catch (_) {}
      input.clear();
      try {
        await _persistReceipts();
      } catch (_) {
        /* Initial acceptance is already durable. */
      }
    }
  }

  Future<void> interrupt() async {
    for (final job in _jobs.values) {
      if (['queued', 'running'].contains(job['state'])) {
        job['state'] = 'interrupted';
        job['error'] = 'INTERRUPTED';
      }
    }
    try {
      await _cancel?.call();
    } catch (_) {}
    try {
      await engine.stop();
    } catch (_) {}
  }

  void dispose() {
    _disposed = true;
    _lifecycle.dispose();
    downloader.cancelAll();
    unawaited(interrupt());
    _images.clear();
    for (final job in _jobs.values) {
      job.remove('text');
    }
  }
}
