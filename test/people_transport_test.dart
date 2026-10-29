import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/local_ai/engines/qvac/qvac_bare_engine.dart';
import 'package:journal/modules/local_ai/core/on_device_engine.dart';
import 'package:journal/modules/people/people_models.dart';
import 'package:journal/modules/people/people_transport.dart';
import 'package:journal/utils/worklet_rpc/worklet_rpc.dart';

import 'support/people_fixture.dart';

class _Worker {
  _Worker(this.channel) {
    messenger.setMockMethodCallHandler(MethodChannel(channel), (call) async {
      methods.add(call.method);
      if (call.method == 'start') {
        if (reattach) {
          reattach = false;
          return 'running';
        }
        return 'started';
      }
      if (call.method == 'write') {
        for (final bytes in reader.add(call.arguments as Uint8List)) {
          final message = RpcMessage.decode(bytes);
          if (message is! RpcRequest) continue;
          final input =
              jsonDecode(utf8.decode(message.data!)) as Map<String, dynamic>;
          final method = input['method'] as String;
          requests.add(method);
          if (method == 'events') {
            eventId = message.id;
            emit(RpcResponse(message.id, stream: StreamFlag.open));
          } else {
            final output = fail && method == 'send'
                ? {'error': 'PEOPLE_UNAVAILABLE'}
                : switch (method) {
                    'start' => {'key': peopleAliceKey},
                    'pair' => {'key': peopleBobKey, 'name': 'Bob'},
                    _ => {'ok': true},
                  };
            if (method == '__shutdown__' && eventId != null) {
              emit(
                RpcStreamFrame(eventId!, StreamFlag.response | StreamFlag.end),
              );
              eventId = null;
            }
            emit(
              RpcResponse(
                message.id,
                data: Uint8List.fromList(utf8.encode(jsonEncode(output))),
              ),
            );
          }
        }
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
      MethodChannel('${channel}_ipc'),
      (_) async => null,
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(MethodChannel(channel), null);
      messenger.setMockMethodCallHandler(MethodChannel('${channel}_ipc'), null);
    });
  }
  final String channel;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final reader = FrameReader();
  final methods = <String>[], requests = <String>[];
  int? eventId;
  bool reattach = false, fail = false;
  void emit(RpcMessage message) {
    final packet = frame(message.encode());
    // Split a frame across platform callbacks to exercise real IPC buffering.
    for (final part in [packet.sublist(0, 2), packet.sublist(2)]) {
      unawaited(
        messenger.handlePlatformMessage(
          '${channel}_ipc',
          const StandardMethodCodec().encodeSuccessEnvelope(
            Uint8List.fromList(part),
          ),
          (_) {},
        ),
      );
    }
  }

  void note() => emit(
    RpcStreamFrame(
      eventId!,
      StreamFlag.response | StreamFlag.data,
      data: Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'type': 'note',
            'key': peopleBobKey,
            'text': 'temporary',
          }),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'People and QVAC use independent channels and independently shut down',
    () async {
      final peopleWorker = _Worker('journal/people'),
          aiWorker = _Worker('journal/qvac');
      final people = BarePeopleTransport(), ai = QvacBareEngine();
      await ai.start();
      expect(await people.start(peopleSeed, 'Alice'), peopleAliceKey);
      await people.configure([peopleBobKey], null);
      final incoming = people.events.first;
      peopleWorker.note();
      expect((await incoming)['text'], 'temporary');
      await ai.stop();
      await people.send(peopleBobKey, 'one attempt');
      expect(peopleWorker.requests.where((m) => m == '__shutdown__'), isEmpty);
      expect(aiWorker.methods.where((m) => m == 'stop').length, 1);
      await ai.start();
      await people.stop();
      await ai.unload(AiTask.writing);
      expect(aiWorker.requests.last, 'unload');
      await ai.stop();
      await people.dispose();
    },
  );
  test(
    'reattachment shuts down the old worker and RPC failures expose no payload',
    () async {
      final worker = _Worker('journal/people')..reattach = true;
      final people = BarePeopleTransport();
      await people.start(peopleSeed, 'Alice');
      expect(worker.methods.where((m) => m == 'start').length, 2);
      expect(worker.requests.where((m) => m == '__shutdown__').length, 1);
      worker.fail = true;
      await expectLater(
        people.send(peopleBobKey, 'secret'),
        throwsA(isA<PeopleFailure>()),
      );
      await people.dispose();
    },
  );
}
