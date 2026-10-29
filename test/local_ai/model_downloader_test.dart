import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/local_ai/core/on_device_engine.dart';
import 'package:journal/modules/local_ai/models/model_catalog.dart';
import 'package:journal/modules/local_ai/models/model_storage.dart';
import 'package:journal/modules/local_ai/models/model_downloader.dart';

class TestStorage extends ModelStorage {
  TestStorage(this.dir);
  final Directory dir;
  bool wifi = true;
  int freeBytes = 1000000000;
  @override
  Future<Directory> directory() async => dir;
  @override
  Future<DeviceResources> resources() async =>
      DeviceResources(freeBytes: freeBytes, ramBytes: 8000000000, wifi: wifi);
}

void main() {
  late Directory dir;
  late HttpServer server;
  late TestStorage storage;
  late ModelDownloader downloader;
  late CatalogModel model;
  final bytes = List<int>.generate(4096, (i) => i % 251);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('journal-weights-');
    storage = TestStorage(dir);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    downloader = ModelDownloader(storage: storage, allowLoopbackForTests: true);
    final hash = (await Sha256().hash(bytes)).bytes
        .map((v) => v.toRadixString(16).padLeft(2, '0'))
        .join();
    model = CatalogModel(
      id: 'test',
      name: 'Test',
      task: AiTask.writing,
      format: 'gguf',
      repository: 'public/test',
      revision: 'a' * 40,
      file: 'test.gguf',
      bytes: bytes.length,
      sha256: hash,
      minRamBytes: 1,
      license: 'Test',
    );
  });
  tearDown(() async {
    downloader.cancelAll();
    await server.close(force: true);
    await dir.delete(recursive: true);
  });
  Uri url() => Uri.parse('http://127.0.0.1:${server.port}/weights');
  test('resumes a partial file with Range and verifies SHA-256', () async {
    final target = await downloader.file(model);
    await File('${target.path}.partial').writeAsBytes(bytes.take(111).toList());
    String? range;
    server.listen((r) async {
      range = r.headers.value('range');
      r.response.statusCode = 206;
      r.response.headers.set('content-range', 'bytes 111-4095/4096');
      r.response.contentLength = 3985;
      r.response.add(bytes.sublist(111));
      await r.response.close();
    });
    final result = await downloader.download(model, testUrl: url()).done;
    expect(range, 'bytes=111-');
    expect(await result.readAsBytes(), bytes);
  });
  test('a server ignoring Range replaces the partial file', () async {
    final target = await downloader.file(model);
    await File('${target.path}.partial').writeAsBytes(bytes.take(20).toList());
    server.listen((r) async {
      r.response.contentLength = bytes.length;
      r.response.add(bytes);
      await r.response.close();
    });
    expect(
      await (await downloader.download(model, testUrl: url()).done)
          .readAsBytes(),
      bytes,
    );
  });
  test(
    'cached verification is invalidated by a changed private file',
    () async {
      final target = await downloader.file(model);
      await target.writeAsBytes(bytes);
      expect(await downloader.verify(target, model), true);
      expect(await downloader.verify(target, model), true);
      await target.writeAsBytes(List.filled(bytes.length, 0));
      await target.setLastModified(
        DateTime.now().add(const Duration(seconds: 1)),
      );
      expect(await downloader.verify(target, model), false);
    },
  );
  test('checksum mismatch discards weights and never installs them', () async {
    server.listen((r) async {
      r.response.contentLength = bytes.length;
      r.response.add(List.filled(bytes.length, 0));
      await r.response.close();
    });
    await expectLater(
      downloader.download(model, testUrl: url()).done,
      throwsA(
        isA<EngineFailure>().having((e) => e.code, 'code', 'INVALID_WEIGHTS'),
      ),
    );
    expect(await downloader.installed(model), isFalse);
    expect(
      await File('${(await downloader.file(model)).path}.partial').exists(),
      isFalse,
    );
  });
  test('Wi-Fi only and free-space guards run before any request', () async {
    storage.wifi = false;
    await expectLater(
      downloader.download(model, testUrl: url()).done,
      throwsA(
        isA<EngineFailure>().having((e) => e.code, 'code', 'WIFI_REQUIRED'),
      ),
    );
    storage.wifi = true;
    storage.freeBytes = 1;
    await expectLater(
      downloader.download(model, testUrl: url()).done,
      throwsA(isA<EngineFailure>().having((e) => e.code, 'code', 'RESOURCE')),
    );
  });
  test('cancel keeps the partial file for a later explicit resume', () async {
    server.listen((r) async {
      r.response.contentLength = bytes.length;
      r.response.bufferOutput = false;
      r.response.add(bytes.take(2048).toList());
      await r.response.flush();
    });
    final transfer = downloader.download(model, testUrl: url());
    final check = expectLater(
      transfer.done,
      throwsA(isA<EngineFailure>().having((e) => e.code, 'code', 'CANCELLED')),
    );
    await transfer.progress.first.timeout(const Duration(seconds: 5));
    transfer.cancel();
    await check;
    expect(
      await File('${(await downloader.file(model)).path}.partial').length(),
      2048,
    );
    expect(await downloader.partialBytes(model), 2048);
    await downloader.delete(model);
    expect(await downloader.partialBytes(model), 0);
  });
}
