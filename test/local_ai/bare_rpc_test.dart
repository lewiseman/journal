import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/local_ai/engines/qvac/bare_rpc.dart';

void main() {
  test('compact uint boundary encodings round trip', () {
    for (final value in [0, 252, 253, 65535, 65536, 0xffffffff, 0x100000000]) {
      final e = Encoder()..uint(value);
      final d = Decoder(e.takeBytes());
      expect(d.uint(), value);
      expect(d.done, isTrue);
    }
  });
  test(
    'frames survive every split, including multiple frames in one chunk',
    () {
      final body = RpcRequest(
        42,
        command: 0,
        data: Uint8List.fromList([1, 2, 3]),
      ).encode();
      final bytes = frame(body);
      for (var at = 0; at <= bytes.length; at++) {
        final reader = FrameReader(), out = <Uint8List>[];
        out.addAll(reader.add(bytes.sublist(0, at)));
        out.addAll(reader.add([...bytes.sublist(at), ...bytes]));
        expect(out, [body, body]);
      }
    },
  );
  test('a worker fatal event closes all pending primitive calls', () async {
    final input = StreamController<List<int>>();
    final rpc = RpcClient(input: input.stream, send: (_) {});
    final pending = rpc.request(Uint8List(0));
    final check = expectLater(pending, throwsA(isA<RpcClosedException>()));
    input.add(frame(RpcRequest(0, command: 255, data: Uint8List(0)).encode()));
    await check;
    expect(rpc.isClosed, true);
    await rpc.close();
    await input.close();
  });
  test('oversized and short messages fail closed', () {
    final header = Uint8List(4);
    ByteData.sublistView(header)
        .setUint32(0, maxFrameLength + 1, Endian.little);
    expect(() => FrameReader().add(header), throwsFormatException);
    expect(
      () => RpcMessage.decode(Uint8List.fromList([1])),
      throwsFormatException,
    );
  });
  test(
    'client performs the bare-rpc stream-open handshake and closes waiters',
    () async {
      final input = StreamController<List<int>>(), writes = <RpcMessage>[];
      final rpc = RpcClient(
        input: input.stream,
        send: (b) => writes.add(RpcMessage.decode(b.sublist(4))),
      );
      final events = <Uint8List>[];
      final stream = rpc.requestStream(Uint8List.fromList([7]));
      final subscription = stream.listen(events.add);
      await Future<void>.delayed(Duration.zero);
      final id = writes.first.id;
      input.add(frame(RpcResponse(id, stream: StreamFlag.open).encode()));
      await Future<void>.delayed(Duration.zero);
      expect(
        (writes.last as RpcStreamFrame).flags,
        StreamFlag.open | StreamFlag.response,
      );
      input.add(
        frame(
          RpcStreamFrame(
            id,
            StreamFlag.response | StreamFlag.data,
            data: Uint8List.fromList([9]),
          ).encode(),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events.single, [9]);
      await subscription.cancel();
      expect(
        (writes.last as RpcStreamFrame).flags,
        StreamFlag.response | StreamFlag.destroy,
      );
      final pending = rpc.request(Uint8List(0));
      final check = expectLater(pending, throwsA(isA<RpcClosedException>()));
      await rpc.close();
      await check;
      await input.close();
    },
  );
}
