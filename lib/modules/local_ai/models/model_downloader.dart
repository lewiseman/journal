import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import '../core/on_device_engine.dart';
import 'model_catalog.dart';
import 'model_storage.dart';

class DownloadProgress {
  const DownloadProgress(this.received, this.total, {this.verifying = false});
  final int received, total;
  final bool verifying;
  double get fraction => total == 0 ? 0 : received / total;
}

class ModelDownload {
  final _progress = StreamController<DownloadProgress>.broadcast();
  final _done = Completer<File>();
  final _cancelled = Completer<void>();
  HttpClientRequest? _request;
  void Function()? _abort;
  bool get cancelled => _cancelled.isCompleted;
  Stream<DownloadProgress> get progress => _progress.stream;
  Future<File> get done => _done.future;
  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
    _abort?.call();
    _request?.abort(const EngineFailure('CANCELLED', 'Download cancelled.'));
  }

  void check() {
    if (cancelled) {
      throw const EngineFailure(
        'CANCELLED',
        'Download cancelled. Partial weights kept for resuming.',
      );
    }
  }
}

/// Only pinned model weights are fetched. No executable code or shared token.
class ModelDownloader {
  ModelDownloader({
    required this.storage,
    HttpClient Function()? client,
    this.allowLoopbackForTests = false,
  }) : _client = client ?? HttpClient.new;
  final ModelStorage storage;
  final HttpClient Function() _client;
  final bool allowLoopbackForTests;
  final _running = <String, ModelDownload>{};
  // Reuse a private file's verified digest only in this process while all of
  // its filesystem metadata remains unchanged. Restarts rehash the weights.
  final _verified = <String, String>{};
  String _identity(FileStat stat, CatalogModel model) =>
      '${model.sha256}:${stat.size}:${stat.modified.microsecondsSinceEpoch}:${stat.changed.microsecondsSinceEpoch}';

  String basename(CatalogModel model) => '${model.sha256}.${model.format}';
  Future<File> file(CatalogModel model) async =>
      File('${(await storage.directory()).path}/${basename(model)}');
  Future<bool> installed(CatalogModel model) async {
    final target = await file(model);
    return await target.exists() && await target.length() == model.bytes;
  }

  Future<int> partialBytes(CatalogModel model) async {
    final partial = File('${(await file(model)).path}.partial');
    return await partial.exists() ? await partial.length() : 0;
  }

  Future<bool> verify(
    File file,
    CatalogModel model, [
    ModelDownload? transfer,
  ]) async {
    transfer?.check();
    if (!await file.exists() || await file.length() != model.bytes) {
      return false;
    }
    final before = _identity(await file.stat(), model);
    transfer?.check();
    if (_verified[file.path] == before) return true;
    final sink = Sha256().newHashSink();
    await for (final chunk in file.openRead()) {
      transfer?.check();
      sink.add(chunk);
    }
    sink.close();
    final hash = await sink.hash();
    final valid =
        hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join() ==
            model.sha256 &&
        before == _identity(await file.stat(), model);
    if (valid) _verified[file.path] = before;
    return valid;
  }

  ModelDownload download(
    CatalogModel model, {
    bool wifiOnly = true,
    Uri? testUrl,
  }) {
    if (testUrl != null && !allowLoopbackForTests) {
      throw ArgumentError('Test URL disabled');
    }
    return _running.putIfAbsent(model.id, () {
      final transfer = ModelDownload();
      // Start after returning so callers can attach progress and error listeners.
      scheduleMicrotask(() async {
        try {
          transfer._done.complete(
            await _download(model, transfer, wifiOnly, testUrl ?? model.url),
          );
        } catch (error, stack) {
          transfer._done.completeError(error, stack);
        } finally {
          _running.remove(model.id);
          await transfer._progress.close();
        }
      });
      return transfer;
    });
  }

  Future<void> delete(CatalogModel model) async {
    final active = _running[model.id];
    if (active != null) {
      active.cancel();
      try {
        await active.done;
      } catch (_) {}
    }
    final target = await file(model);
    for (final f in [target, File('${target.path}.partial')]) {
      _verified.remove(f.path);
      if (await f.exists()) await f.delete();
    }
  }

  void cancelAll() {
    for (final transfer in _running.values) {
      transfer.cancel();
    }
  }

  Future<File> _download(
    CatalogModel model,
    ModelDownload transfer,
    bool wifiOnly,
    Uri uri,
  ) async {
    final target = await file(model),
        partial = File('${(await file(model)).path}.partial');
    if (await verify(target, model, transfer)) return target;
    if (await target.exists()) await target.delete();
    var failures = 0;
    final client = _client()..autoUncompress = false;
    transfer._abort = () => client.close(force: true);
    client.connectionTimeout = const Duration(seconds: 30);
    try {
      while (true) {
        transfer.check();
        final resources = await storage.resources();
        if (wifiOnly && !resources.wifi) {
          throw const EngineFailure(
            'WIFI_REQUIRED',
            'Connect to Wi-Fi or turn off Wi-Fi only in Manage models.',
          );
        }
        var offset = await partial.exists() ? await partial.length() : 0;
        if (offset > model.bytes) {
          await partial.delete();
          offset = 0;
        }
        if (resources.freeBytes < model.bytes - offset + 100 * 1024 * 1024) {
          throw const EngineFailure(
            'RESOURCE',
            'Free more storage before downloading this model.',
          );
        }
        if (offset == model.bytes) break;
        final before = offset;
        try {
          var url = uri;
          HttpClientResponse? response;
          for (var redirects = 0; redirects <= 5; redirects++) {
            if (url.scheme != 'https' &&
                !(allowLoopbackForTests &&
                    url.scheme == 'http' &&
                    ['127.0.0.1', 'localhost'].contains(url.host))) {
              throw const EngineFailure(
                'DOWNLOAD_FAILED',
                'Model downloads require HTTPS.',
              );
            }
            final request = await client.getUrl(url);
            transfer._request = request;
            transfer.check();
            request.followRedirects = false;
            request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
            if (offset > 0) {
              request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
            }
            response = await request.close().timeout(
              const Duration(seconds: 60),
            );
            if (![301, 302, 303, 307, 308].contains(response.statusCode)) break;
            final location = response.headers.value(HttpHeaders.locationHeader);
            await response.drain<void>();
            if (location == null) {
              throw const EngineFailure(
                'DOWNLOAD_FAILED',
                'Missing model redirect.',
              );
            }
            url = url.resolve(location);
          }
          if (response == null ||
              ![200, 206].contains(response.statusCode) ||
              response.headers.value(HttpHeaders.contentEncodingHeader) !=
                  null) {
            throw const EngineFailure(
              'DOWNLOAD_FAILED',
              'The pinned public model could not be downloaded.',
            );
          }
          final range = response.headers.value(HttpHeaders.contentRangeHeader);
          if (response.statusCode == 206 &&
              range != 'bytes $offset-${model.bytes - 1}/${model.bytes}') {
            throw const EngineFailure(
              'DOWNLOAD_FAILED',
              'The server returned an invalid download range.',
            );
          }
          if (response.statusCode == 200) {
            offset = 0; // Server ignored Range: replace, never append.
          }
          if (response.contentLength != -1 &&
              response.contentLength != model.bytes - offset) {
            throw const EngineFailure(
              'DOWNLOAD_FAILED',
              'The model size differs from the pinned catalog.',
            );
          }
          final output = await partial.open(
            mode: offset == 0 ? FileMode.write : FileMode.append,
          );
          try {
            await for (final chunk in response.timeout(
              const Duration(seconds: 60),
            )) {
              transfer.check();
              if (offset + chunk.length > model.bytes) {
                throw const EngineFailure(
                  'DOWNLOAD_FAILED',
                  'Model exceeds the pinned size.',
                );
              }
              // Recheck on each chunk so Wi-Fi loss never continues on cellular.
              if (wifiOnly && !(await storage.resources()).wifi) {
                throw const EngineFailure(
                  'WIFI_REQUIRED',
                  'Wi-Fi disconnected. Download paused; retry to resume.',
                );
              }
              await output.writeFrom(chunk);
              offset += chunk.length;
              transfer._progress.add(DownloadProgress(offset, model.bytes));
            }
            await output.flush();
          } finally {
            await output.close();
          }
          if (offset == model.bytes) break;
          throw const HttpException('Incomplete model download');
        } on EngineFailure {
          rethrow;
        } catch (_) {
          transfer.check();
          final current = await partial.exists() ? await partial.length() : 0;
          failures = current > before ? 0 : failures + 1;
          if (failures >= 5) {
            throw const EngineFailure(
              'DOWNLOAD_FAILED',
              'Download paused. Check the connection and retry to resume.',
            );
          }
          await Future.any([
            Future<void>.delayed(Duration(seconds: failures + 1)),
            transfer._cancelled.future,
          ]);
        }
      }
      transfer.check();
      transfer._progress.add(
        DownloadProgress(model.bytes, model.bytes, verifying: true),
      );
      if (!await verify(partial, model, transfer)) {
        await partial.delete();
        throw const EngineFailure(
          'INVALID_WEIGHTS',
          'Checksum mismatch. These weights were discarded.',
        );
      }
      transfer.check();
      final installed = await partial.rename(target.path);
      _verified.remove(partial.path);
      _verified[installed.path] = _identity(await installed.stat(), model);
      return installed;
    } finally {
      client.close(force: true);
    }
  }
}
