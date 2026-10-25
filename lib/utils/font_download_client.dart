import 'dart:async';

import 'package:http/http.dart' as http;

/// Bounds Google Fonts' GET requests, including reading the response body.
class FontDownloadClient extends http.BaseClient {
  FontDownloadClient({required this.timeout, http.Client? client})
    : _client = client ?? http.Client();

  final Duration timeout;
  final http.Client _client;
  final _activeDownloads = <Completer<void>>{};

  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) async {
    final abort = Completer<void>();
    _activeDownloads.add(abort);
    final timer = Timer(timeout, () {
      if (!abort.isCompleted) abort.complete();
    });
    final request = http.AbortableRequest(
      'GET',
      url,
      abortTrigger: abort.future,
    );
    if (headers != null) request.headers.addAll(headers);

    try {
      // Keep the deadline active after headers arrive. Aborting also interrupts
      // a stalled response stream, allowing the serialized font queue to resume.
      return await http.Response.fromStream(await _client.send(request));
    } finally {
      timer.cancel();
      _activeDownloads.remove(abort);
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _client.send(request);

  @override
  void close() {
    for (final abort in _activeDownloads) {
      if (!abort.isCompleted) abort.complete();
    }
    _client.close();
  }
}
