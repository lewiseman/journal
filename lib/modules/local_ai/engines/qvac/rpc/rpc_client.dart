// Adapted from SebastianKumor/qvac_flutter (Apache-2.0). See ../LICENSE.
import 'dart:async';
import 'dart:typed_data';

import 'framing.dart';
import 'messages.dart';

/// Thrown to every waiting call when the connection goes away.
class RpcClosedException implements Exception {
  const RpcClosedException([this.reason]);

  final Object? reason;

  @override
  String toString() => 'RpcClosedException${reason == null ? '' : ': $reason'}';
}

/// The calling side of a bare-rpc connection. [input] is raw bytes in chunks of
/// any size; [send] writes one whole frame, length included.
class RpcClient {
  RpcClient({required Stream<List<int>> input, required this._send}) {
    _subscription = input.listen(
      _onChunk,
      onError: (Object e) => _shutdown(RpcClosedException(e)),
      onDone: () =>
          _shutdown(const RpcClosedException('the other side closed')),
    );
  }

  final void Function(Uint8List frame) _send;
  late final StreamSubscription<List<int>> _subscription;
  final _reader = FrameReader();
  final _calls = <int, _Call>{};
  // Streams cancelled before the other side opened them. Closed once it does.
  final _cancelled = <int>{};
  int _lastId = 0;
  bool _closed = false;
  bool get isClosed => _closed;

  /// Sends [data] and waits for a single reply.
  Future<Uint8List> request(Uint8List data, {int command = 0}) {
    if (_closed) return Future.error(const RpcClosedException());
    final call = _Unary();
    final id = _register(call);
    _write(RpcRequest(id, command: command, data: data));
    return call.reply.future;
  }

  /// Sends [data] and returns the reply stream. Nothing is sent until you listen.
  Stream<Uint8List> requestStream(Uint8List data, {int command = 0}) {
    late final StreamController<Uint8List> out;
    int? id;
    out = StreamController<Uint8List>(
      onListen: () {
        if (_closed) {
          out
            ..addError(const RpcClosedException())
            ..close();
          return;
        }
        id = _register(_Streamed(out));
        _write(RpcRequest(id!, command: command, data: data));
      },
      onPause: () => _flag(id, StreamFlag.pause),
      onResume: () => _flag(id, StreamFlag.resume),
      onCancel: () {
        final call = id == null ? null : _calls.remove(id);
        if (call is! _Streamed) return;
        if (call.opened) {
          _flag(id, StreamFlag.destroy, force: true);
        } else {
          _cancelled.add(id!);
        }
      },
    );
    return out.stream;
  }

  /// Stops listening and fails every call still waiting.
  Future<void> close() async {
    await _subscription.cancel();
    _shutdown(const RpcClosedException());
  }

  int _register(_Call call) {
    final id = ++_lastId;
    _calls[id] = call;
    return id;
  }

  void _write(RpcMessage m) {
    if (!_closed) _send(frame(m.encode()));
  }

  void _flag(int? id, int flag, {bool force = false}) {
    if (id != null && (force || _calls.containsKey(id))) {
      _write(RpcStreamFrame(id, StreamFlag.response | flag));
    }
  }

  void _onChunk(List<int> chunk) {
    try {
      for (final body in _reader.add(chunk)) {
        _onMessage(RpcMessage.decode(body));
      }
    } on FormatException catch (e) {
      _subscription.cancel();
      _shutdown(RpcClosedException(e));
    }
  }

  void _onMessage(RpcMessage m) {
    switch (m) {
      case RpcResponse():
        _onResponse(m);
      case RpcStreamFrame(:final flags) when flags & StreamFlag.response != 0:
        _onStreamFrame(m);
      // We don't serve requests or upload streams, so there is nothing to answer.
      case RpcRequest(id: 0):
        _shutdown(const RpcClosedException('worker reported a fatal error'));
      case RpcRequest() || RpcStreamFrame():
        break;
    }
  }

  void _onResponse(RpcResponse m) {
    final opensStream = m.stream & StreamFlag.open != 0;
    final call = _calls[m.id];
    if (call == null) {
      if (_cancelled.remove(m.id) && opensStream) {
        _write(RpcStreamFrame(m.id, StreamFlag.response | StreamFlag.open));
        _write(RpcStreamFrame(m.id, StreamFlag.response | StreamFlag.destroy));
      }
      return;
    }
    switch (call) {
      case _ when m.error != null:
        _calls.remove(m.id);
        call.fail(m.error!);
      case _Unary() when opensStream:
        _calls.remove(m.id);
        _write(RpcStreamFrame(m.id, StreamFlag.response | StreamFlag.destroy));
        call.fail(
          StateError('Expected one reply but got a stream. Use requestStream.'),
        );
      case _Unary():
        _calls.remove(m.id);
        call.reply.complete(m.data ?? Uint8List(0));
      case final _Streamed streamed when opensStream:
        // The other side holds back its data until it sees this.
        streamed.opened = true;
        _write(RpcStreamFrame(m.id, StreamFlag.response | StreamFlag.open));
      case _Streamed(:final out):
        _calls.remove(m.id);
        if (m.data case final data? when data.isNotEmpty) out.add(data);
        out.close();
    }
  }

  void _onStreamFrame(RpcStreamFrame m) {
    final call = _calls[m.id];
    if (call is! _Streamed) return;
    final out = call.out;
    if (m.flags & StreamFlag.error != 0) {
      _calls.remove(m.id);
      call.fail(m.error ?? const RpcError('stream failed'));
      return;
    }
    if (m.flags & StreamFlag.data != 0) out.add(m.data ?? Uint8List(0));
    if (m.flags & (StreamFlag.end | StreamFlag.close | StreamFlag.destroy) !=
        0) {
      _calls.remove(m.id);
      out.close();
    }
  }

  void _shutdown(RpcClosedException reason) {
    if (_closed) return;
    _closed = true;
    final calls = _calls.values.toList();
    _calls.clear();
    for (final call in calls) {
      call.fail(reason);
    }
  }
}

sealed class _Call {
  void fail(Object error);
}

class _Unary extends _Call {
  final reply = Completer<Uint8List>();

  @override
  void fail(Object error) => reply.completeError(error);
}

class _Streamed extends _Call {
  _Streamed(this.out);

  final StreamController<Uint8List> out;
  bool opened = false;

  @override
  void fail(Object error) {
    out
      ..addError(error)
      ..close();
  }
}
