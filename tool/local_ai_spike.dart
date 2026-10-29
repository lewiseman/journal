// Physical-device primitive smoke test, deliberately independent of Journal's
// database, account and note data. Run with flutter run -t tool/local_ai_spike.dart.
import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:journal/modules/notes/images/note_background_gen.dart';

import 'package:flutter/material.dart';
import 'package:journal/modules/local_ai/core/on_device_engine.dart';
import 'package:journal/modules/local_ai/core/operation_runner.dart';
import 'package:journal/modules/local_ai/core/device_job_backend.dart';
import 'package:journal/modules/local_ai/engines/qvac/qvac_bare_engine.dart';
import 'package:journal/modules/local_ai/models/model_catalog.dart';
import 'package:journal/modules/local_ai/models/model_storage.dart';
import 'package:journal/modules/local_ai/models/model_downloader.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: Spike()));
}

class Spike extends StatefulWidget {
  const Spike({super.key});
  @override
  State<Spike> createState() => _SpikeState();
}

class _SpikeState extends State<Spike> {
  String status = 'Starting QVAC smoke test…';
  final engine = QvacBareEngine();
  void report(String text) {
    debugPrint('AI_SPIKE: $text');
    if (mounted) setState(() => status = text);
  }

  @override
  void initState() {
    super.initState();
    unawaited(run());
  }

  Future<void> run() async {
    try {
      final storage = ModelStorage();
      final facts = await storage.resources();
      report(
        'Resources: RAM ${facts.ramBytes}, free ${facts.freeBytes}, Wi-Fi ${facts.wifi}',
      );
      await engine.start();
      report('Worklet ping passed');
      if (const bool.fromEnvironment('AI_SPIKE_PING_ONLY')) {
        await engine.stop();
        report('PING SPIKE COMPLETE');
        return;
      }
      final catalog = jsonDecode(
        await rootBundle.loadString('assets/ai/models.json'),
      ) as Map;
      if (const bool.fromEnvironment('AI_SPIKE_RESOURCE_ONLY')) {
        final models = (catalog['models'] as List)
            .map((m) => CatalogModel.fromJson(Map<String, dynamic>.from(m)))
            .toList();
        final large = models.firstWhere(
          (m) => m.minRamBytes > facts.ramBytes * 2,
        );
        final downloader = ModelDownloader(storage: storage);
        final backend = DeviceJobBackend(
          engine: engine,
          storage: storage,
          downloader: downloader,
        );
        final id = 'large-model-${DateTime.now().millisecondsSinceEpoch}';
        await backend.request(
          'POST',
          '/v1/jobs',
          body: {
            'id': id,
            'operation': 'summarize-note',
            'prompt': 'One short note.',
            'expires': DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch,
            'modelId': large.id,
            '_model': large,
          },
        );
        Map<String, dynamic> result = {};
        for (var i = 0; i < 100; i++) {
          result = await backend.request('GET', '/v1/jobs/$id');
          if (result['state'] == 'failed') break;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        if (result['error'] != 'RESOURCE') {
          throw StateError('Expected RESOURCE: $result');
        }
        report('PASS RESOURCE ${result['message']}');
        backend.dispose();
        await engine.stop();
        report('RESOURCE SPIKE COMPLETE');
        return;
      }
      final model = CatalogModel.fromJson(
        Map<String, dynamic>.from(
          (catalog['models'] as List).firstWhere(
            (m) =>
                m['task'] ==
                (const bool.fromEnvironment('AI_SPIKE_IMAGE_ONLY')
                    ? 'image'
                    : 'writing'),
          ),
        ),
      );
      final downloader = ModelDownloader(storage: storage);
      const offline = bool.fromEnvironment('AI_SPIKE_OFFLINE');
      final transfer = offline ? null : downloader.download(model);
      var percent = -1;
      final sub = transfer?.progress.listen((p) {
        final next = (p.fraction * 20).floor() * 5;
        if (next != percent) {
          percent = next;
          report('Weights $percent%${p.verifying ? ' · verifying' : ''}');
        }
      });
      final file = transfer == null
          ? await downloader.file(model)
          : await transfer.done;
      await sub?.cancel();
      if (!await downloader.verify(file, model)) {
        throw StateError('Pinned model is not installed');
      }
      report('SHA-256 weights verified');
      if (const bool.fromEnvironment('AI_SPIKE_IMAGE_ONLY')) {
        final imageId = 'smoke-image-${DateTime.now().millisecondsSinceEpoch}';
        final backend = DeviceJobBackend(
          engine: engine,
          storage: storage,
          downloader: downloader,
        );
        await backend.request(
          'POST',
          '/v1/jobs',
          body: {
            'id': imageId,
            'operation': 'generate-note-background',
            'prompt': jsonEncode({
              'prompt': 'pale blue watercolor wash',
              'tone': 'light',
            }),
            'expires': DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch,
            'modelId': model.id,
            '_model': model,
          },
        );
        Map<String, dynamic> job = {};
        var last = -1;
        for (var i = 0; i < 900; i++) {
          job = await backend.request('GET', '/v1/jobs/$imageId');
          final tick = job['progress'];
          if (tick is Map && tick['step'] != last) {
            last = tick['step'];
            report('IMAGE_STEP $last/${tick['total']}');
          }
          if (!['queued', 'running'].contains(job['state'])) break;
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        if (job['state'] != 'completed') throw StateError('Image failed: $job');
        final result = NoteBackgroundResult.parse(job['text']);
        final response = await backend.request(
          'GET',
          '/v1/image-jobs/$imageId/result',
        );
        final png = base64Decode(response['image']);
        final digest = (await Sha256().hash(png)).bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        if (!result.matches(png, digest)) {
          throw StateError('Image result checksum mismatch');
        }
        report(
          'PASS IMAGE ${result.width}x${result.height} ${result.bytes} bytes, seed ${result.seed}',
        );
        await backend.request('POST', '/v1/jobs/$imageId/ack', body: {});
        backend.dispose();
        await engine.stop();
        report('IMAGE SPIKE COMPLETE');
        return;
      }
      await engine.load(
        ModelFile(id: model.id, path: file.path, format: model.format),
        AiTask.writing,
      );
      report('Qwen 0.5B loaded');
      if (const bool.fromEnvironment('AI_SPIKE_BACKGROUND_ONLY')) {
        final backend = DeviceJobBackend(
          engine: engine,
          storage: storage,
          downloader: downloader,
        );
        await backend.request(
          'POST',
          '/v1/jobs',
          body: {
            'id': 'smoke-background-only',
            'operation': 'expand-note',
            'prompt': jsonEncode({
              'text': 'Meeting Friday at 10. Budget approval is pending. We need to review the full plan carefully and decide the next steps.',
              'intent': '',
            }),
            'expires': DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch,
            'modelId': model.id,
            '_model': model,
          },
        );
        for (var i = 0; i < 1000; i++) {
          final j = await backend.request(
            'GET',
            '/v1/jobs/smoke-background-only',
          );
          if (j['state'] == 'running') break;
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        report('BACKGROUND_TEST_READY');
        await Future<void>.delayed(const Duration(seconds: 45));
        final result = await backend.request(
          'GET',
          '/v1/jobs/smoke-background-only',
        );
        report('BACKGROUND_TEST_RESULT ${result['state']}');
        backend.dispose();
        return;
      }
      final run = engine.complete(
        const [AiMessage('user', 'Reply with a short greeting.')],
        params: {'predict': 32, 'temp': 0, 'seed': 42},
      );
      final text = StringBuffer();
      var done = false;
      await for (final event in run.events.timeout(
        const Duration(minutes: 2),
      )) {
        switch (event) {
          case CompletionToken(:final text):
            report('Token: $text');
          case CompletionDone():
            done = true;
        }
        if (event is CompletionToken) text.write(event.text);
      }
      if (!done || text.isEmpty) {
        throw StateError('Missing terminal completion or text');
      }
      report('PASS streaming: $text');
      final cancelRun = engine.complete(
        const [AiMessage('user', 'Count slowly from one to one hundred.')],
        params: {'predict': 200, 'temp': 0, 'seed': 42},
      );
      var cancelled = false;
      try {
        await for (final event in cancelRun.events) {
          if (event is CompletionToken && !cancelled) {
            cancelled = true;
            await cancelRun.cancel();
          }
        }
      } on EngineFailure catch (e) {
        if (e.code != 'CANCELLED') rethrow;
      }
      if (!cancelled) throw StateError('No token before cancellation');
      report('PASS native cancellation');
      final runner = OperationRunner(
        engine,
        await OperationRunner.loadOperations(),
      );
      final summary = StringBuffer();
      await for (final event
          in runner
              .complete(
                'summarize-note',
                'Team meeting is Friday at 10. Budget approval is pending.',
              )
              .events) {
        if (event is CompletionToken) summary.write(event.text);
      }
      runner.validate('summarize-note', summary.toString());
      report('PASS ${offline ? 'OFFLINE ' : ''}summary contract: $summary');
      final rewrite = StringBuffer();
      await for (final event
          in runner
              .complete(
                'rewrite-note',
                jsonEncode({
                  'text': 'Meeting Friday at 10. Budget not approved yet.',
                  'intent': '',
                }),
              )
              .events) {
        if (event is CompletionToken) rewrite.write(event.text);
      }
      runner.validate('rewrite-note', rewrite.toString());
      report('PASS ${offline ? 'OFFLINE ' : ''}rewrite contract: $rewrite');
      final backend = DeviceJobBackend(
        engine: engine,
        storage: storage,
        downloader: downloader,
      );
      final submitted = await backend.request(
        'POST',
        '/v1/jobs',
        body: {
          'id': 'smoke-background',
          'operation': 'summarize-note',
          'prompt': 'Team meeting is Friday at 10. Budget approval is pending.',
          'expires': DateTime.now()
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch,
          'modelId': model.id,
          '_model': model,
        },
      );
      report('BACKGROUND_TEST_READY ${submitted['state']}');
      await Future<void>.delayed(const Duration(seconds: 45));
      final afterBackground = await backend.request(
        'GET',
        '/v1/jobs/smoke-background',
      );
      report('BACKGROUND_TEST_RESULT ${afterBackground['state']}');
      backend.dispose();

      await engine.stop();
      report('PASS clean shutdown');
      await engine.start();
      await engine.stop();
      report('PASS restart after shutdown · SPIKE COMPLETE');
    } catch (error, stack) {
      report('FAIL $error');
      debugPrint('$stack');
      try {
        await engine.stop();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('On-device AI spike')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: SelectableText(status),
    ),
  );
}
