import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:journal/utils/worklet_rpc/worklet_rpc.dart';

import 'people_models.dart';

abstract interface class PeopleTransport {
  Stream<Map<String, dynamic>> get events;
  Future<String> start(String seed, String name);
  Future<void> configure(List<String> friends, FriendInvitation? invite);
  Future<Person> pair(FriendInvitation invite);
  Future<void> confirm(String key, bool accepted);
  Future<void> send(String key, String text);
  Future<void> stop();
  Future<void> dispose();
}

class BarePeopleTransport implements PeopleTransport {
  static const _methods = MethodChannel('journal/people');
  static const _channelEvents = EventChannel('journal/people_ipc');
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  @override
  Stream<Map<String, dynamic>> get events => _events.stream;
  RpcClient? _rpc;
  StreamSubscription<Uint8List>? _subscription;
  Future<void> _writes = Future.value(), _lifecycle = Future.value();
  int _generation = 0;
  bool _disposed = false;

  Future<T> _queued<T>(Future<T> Function() action) {
    final result = _lifecycle.then((_) => action());
    _lifecycle = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<Map<String, dynamic>> _call(
    String method, [
    Map<String, dynamic> data = const {},
    Duration timeout = const Duration(seconds: 15),
  ]) async {
    final rpc = _rpc;
    if (rpc == null) throw const PeopleFailure();
    final value = jsonDecode(
      utf8.decode(
        await rpc
            .request(
              Uint8List.fromList(
                utf8.encode(jsonEncode({'method': method, ...data})),
              ),
            )
            .timeout(timeout),
      ),
    ) as Map<String, dynamic>;
    if (value.containsKey('error')) throw const PeopleFailure();
    return value;
  }

  void _attach() {
    _rpc = RpcClient(
      input: _channelEvents.receiveBroadcastStream().map((value) {
        if (value is Uint8List) return value;
        throw const PeopleFailure();
      }),
      send: (bytes) {
        _writes = _writes
            .then((_) => _methods.invokeMethod<void>('write', bytes))
            .catchError((Object _) {
              unawaited(_rpc?.close());
            });
      },
    );
  }

  @override
  Future<String> start(String seed, String name) => _queued(() async {
    await _stopInternal();
    if (_disposed) throw const PeopleFailure();
    final generation = ++_generation;
    try {
      final status = await _methods.invokeMethod<String>('start');
      _attach();
      if (status == 'running') {
        await _call('__shutdown__', {}, const Duration(seconds: 2));
        await _rpc!.close();
        await _methods.invokeMethod<void>('stop');
        await _methods.invokeMethod<String>('start');
        _attach();
      }
      await _call('ping');
      _subscription = _rpc!
          .requestStream(Uint8List.fromList(utf8.encode('{"method":"events"}')))
          .listen(
            (bytes) {
              if (generation != _generation || _disposed) return;
              try {
                _events.add(
                  jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
                );
              } catch (_) {
                _events.add({'type': 'unavailable'});
              }
            },
            onError: (Object _) {
              if (generation == _generation && !_disposed) {
                _events.add({'type': 'unavailable'});
              }
            },
          );
      final response = await _call('start', {'seed': seed, 'name': name});
      final key = response['key'];
      if (key is! String || !peopleKeyPattern.hasMatch(key)) {
        throw const PeopleFailure();
      }
      return key;
    } catch (_) {
      await _stopInternal();
      throw const PeopleFailure(
        'People networking is unavailable. Check your connection and keep Journal open.',
      );
    }
  });
  @override
  Future<void> configure(List<String> friends, FriendInvitation? invite) async {
    await _call('configure', {'friends': friends, 'invite': invite?.toJson()});
  }

  @override
  Future<Person> pair(FriendInvitation invite) async => Person.fromJson(
    await _call('pair', {
      'invite': invite.toJson(),
    }, const Duration(minutes: 2)),
  );
  @override
  Future<void> confirm(String key, bool accepted) async {
    await _call('confirm', {'key': key, 'accepted': accepted});
  }

  @override
  Future<void> send(String key, String text) async {
    await _call('send', {'key': key, 'text': text});
  }

  Future<void> _stopInternal() async {
    _generation++;
    if (_rpc != null) {
      try {
        await _call('__shutdown__', {}, const Duration(seconds: 2));
      } catch (_) {
        /* Terminate even when the worker lost connectivity. */
      }
      await _subscription?.cancel();
      _subscription = null;
      await _rpc?.close();
      _rpc = null;
      try {
        await _methods.invokeMethod<void>('stop');
      } catch (_) {
        /* No worker on unsupported platforms. */
      }
    }
    await _writes;
    _writes = Future.value();
  }

  @override
  Future<void> stop() {
    _generation++;
    return _queued(_stopInternal);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await stop();
    await _events.close();
  }
}
