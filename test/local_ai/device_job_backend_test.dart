import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/local_ai/core/device_job_backend.dart';
import 'package:journal/modules/local_ai/core/on_device_engine.dart';
import 'package:journal/modules/local_ai/models/model_catalog.dart';
import 'package:journal/modules/local_ai/models/model_downloader.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';

import 'fake_engine.dart';
import 'model_downloader_test.dart' show TestStorage;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late FakeOnDeviceEngine engine;
  late TestStorage storage;
  late ModelDownloader downloader;
  late DeviceJobBackend backend;
  late CatalogModel model;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('journal-device-job-');
    engine = FakeOnDeviceEngine();
    storage = TestStorage(dir);
    downloader = ModelDownloader(storage: storage);
    final bytes = [1, 2, 3, 4];
    final sha = (await Sha256().hash(bytes)).bytes
        .map((v) => v.toRadixString(16).padLeft(2, '0'))
        .join();
    model = CatalogModel(
      id: 'small',
      name: 'Small',
      task: AiTask.writing,
      format: 'gguf',
      repository: 'public/test',
      revision: 'a' * 40,
      file: 'test.gguf',
      bytes: 4,
      sha256: sha,
      minRamBytes: 1,
      license: 'Test',
    );
    await (await downloader.file(model)).writeAsBytes(bytes);
    backend = DeviceJobBackend(
      engine: engine,
      storage: storage,
      downloader: downloader,
    );
  });
  tearDown(() async {
    backend.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await dir.delete(recursive: true);
  });
  Map<String, dynamic> input(String id) => {
    'id': id,
    'operation': 'summarize-note',
    'prompt': 'The meeting is Friday.',
    'expires': DateTime.now()
        .add(const Duration(hours: 1))
        .millisecondsSinceEpoch,
    'modelId': model.id,
    '_model': model,
  };
  Future<Map<String, dynamic>> terminal(String id) async {
    for (var i = 0; i < 100; i++) {
      final job = await backend.request('GET', '/v1/jobs/$id');
      if (!['queued', 'running'].contains(job['state'])) return job;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    throw StateError('Job did not finish');
  }

  test(
    'submit, poll, validate, acknowledge; duplicate identity runs once',
    () async {
      final first = input('job-12345');
      final repeat = Map<String, dynamic>.of(first);
      await backend.request('POST', '/v1/jobs', body: first);
      await backend.request('POST', '/v1/jobs', body: repeat);
      final job = await terminal('job-12345');
      expect(job['state'], 'completed');
      expect(job['device'], 'this-phone');
      expect(engine.loads, 1);
      final ack = await backend.request(
        'POST',
        '/v1/jobs/job-12345/ack',
        body: {},
      );
      expect(ack['acknowledged'], true);
      expect(ack.containsKey('text'), false);
    },
  );
  test('invalid output fails and never becomes a completed preview', () async {
    engine.output = const [CompletionToken(''), CompletionDone()];
    await backend.request('POST', '/v1/jobs', body: input('job-12345'));
    final job = await terminal('job-12345');
    expect(job['state'], 'failed');
    expect(job['error'], 'INVALID_OUTPUT');
    expect(job.containsKey('text'), false);
  });
  test('cancel is terminal and stops native generation', () async {
    final controller = StreamController<CompletionEvent>();
    engine.completionStream = controller.stream;
    await backend.request('POST', '/v1/jobs', body: input('job-12345'));
    while (!engine.started || engine.messages == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await backend.request('POST', '/v1/jobs/job-12345/cancel', body: {});
    expect((await terminal('job-12345'))['state'], 'cancelled');
    expect(engine.cancelled, true);
    controller.add(const CompletionDone());
    await controller.close();
  });
  test('background interruption never restarts accepted work', () async {
    final controller = StreamController<CompletionEvent>();
    engine.completionStream = controller.stream;
    await backend.request('POST', '/v1/jobs', body: input('job-12345'));
    while (engine.messages == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await backend.interrupt();
    expect((await terminal('job-12345'))['state'], 'interrupted');
    expect(engine.cancelled, true);
    controller.add(const CompletionDone());
    await controller.close();
  });
  test('model checksum and memory failures happen before loading', () async {
    await (await downloader.file(model)).writeAsBytes([0, 0, 0, 0]);
    await backend.request('POST', '/v1/jobs', body: input('job-12345'));
    final job = await terminal('job-12345');
    expect(job['error'], 'NOT_READY');
    expect(engine.loads, 0);
  });
  test('a restart after a lost acceptance reply keeps a terminal receipt, without private content', () async {
    await backend.request('POST', '/v1/jobs', body: input('lost-reply'));
    await terminal('lost-reply');
    while (backend.busy) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final raw = await File('${dir.path}/.device_jobs.json').readAsString();
    expect(raw.contains('The meeting is Friday'), false);
    expect(raw.contains('A short factual summary'), false);
    backend.dispose();
    final replacement = FakeOnDeviceEngine();
    backend = DeviceJobBackend(
      engine: replacement,
      storage: storage,
      downloader: downloader,
    );
    final restored = await backend.request('GET', '/v1/jobs/lost-reply');
    expect(restored['state'], 'interrupted');
    expect(replacement.loads, 0);
  });
  test(
    'a too-large model reports RESOURCE before loading or opening weights',
    () async {
      final large = CatalogModel(
        id: 'large',
        name: 'Large',
        task: AiTask.writing,
        format: 'gguf',
        repository: model.repository,
        revision: model.revision,
        file: model.file,
        bytes: model.bytes,
        sha256: model.sha256,
        minRamBytes: 100000000000,
        license: model.license,
      );
      final body = input('large-model')
        ..['_model'] = large
        ..['modelId'] = large.id;
      await backend.request('POST', '/v1/jobs', body: body);
      final job = await terminal('large-model');
      expect(job['error'], 'RESOURCE');
      expect(engine.loads, 0);
      expect(job['message'], contains('more memory'));
    },
  );
  test('concurrent submissions cannot start two models', () async {
    engine.completionStream = const Stream.empty();
    final first = backend.request('POST', '/v1/jobs', body: input('job-12345'));
    final second = backend.request(
      'POST',
      '/v1/jobs',
      body: input('job-67890'),
    );
    final rejected = expectLater(
      second,
      throwsA(isA<CompanionFailure>().having((e) => e.code, 'code', 'BUSY')),
    );
    await first;
    await rejected;
    await terminal('job-12345');
  });
}
