// Adapted from SebastianKumor/qvac_flutter (Apache-2.0). See LICENSE in this directory.
import 'dart:typed_data';

import 'encoding.dart';

/// Stream flags from bare-rpc lib/constants.js.
abstract final class StreamFlag {
  static const open = 0x1;
  static const close = 0x2;
  static const pause = 0x4;
  static const resume = 0x8;
  static const data = 0x10;
  static const end = 0x20;
  static const destroy = 0x40;
  static const error = 0x80;

  /// Which side's stream a frame belongs to: the request or the response.
  static const request = 0x100;
  static const response = 0x200;
}

/// An error sent by the other side, or one we send it.
class RpcError implements Exception {
  const RpcError(this.message, {this.code = '', this.errno = 0});

  final String message;
  final String code;
  final int errno;

  @override
  String toString() =>
      code.isEmpty ? 'RpcError: $message' : 'RpcError($code): $message';
}

sealed class RpcMessage {
  const RpcMessage(this.id);

  /// 0 for events, which get no reply.
  final int id;

  static const _request = 1, _response = 2, _stream = 3;

  /// The frame body, without the 4 byte length in front.
  Uint8List encode() {
    final e = Encoder();
    switch (this) {
      case RpcRequest(:final command, :final stream, :final data):
        e
          ..uint(_request)
          ..uint(id)
          ..uint(command)
          ..uint(stream);
        if (stream == 0) e.buffer(data ?? const []);
      case RpcResponse(:final stream, :final error, :final data):
        e
          ..uint(_response)
          ..uint(id)
          ..boolean(error != null)
          ..uint(stream);
        if (error != null) {
          _encodeError(e, error);
        } else if (stream == 0) {
          e.buffer(data ?? const []);
        }
      case RpcStreamFrame(:final flags, :final error, :final data):
        e
          ..uint(_stream)
          ..uint(id)
          ..uint(flags);
        if (flags & StreamFlag.error != 0) {
          _encodeError(e, error ?? const RpcError(''));
        } else if (flags & StreamFlag.data != 0) {
          e.buffer(data ?? const []);
        }
    }
    return e.takeBytes();
  }

  static RpcMessage decode(Uint8List body) {
    final d = Decoder(body);
    final type = d.uint();
    final id = d.uint();
    switch (type) {
      case _request:
        final command = d.uint();
        final stream = d.uint();
        return RpcRequest(
          id,
          command: command,
          stream: stream,
          data: stream == 0 ? d.buffer() : null,
        );
      case _response:
        final isError = d.boolean();
        final stream = d.uint();
        if (isError) {
          return RpcResponse(id, stream: stream, error: _decodeError(d));
        }
        return RpcResponse(
          id,
          stream: stream,
          data: stream == 0 ? d.buffer() : null,
        );
      case _stream:
        final flags = d.uint();
        if (flags & StreamFlag.error != 0) {
          return RpcStreamFrame(id, flags, error: _decodeError(d));
        }
        return RpcStreamFrame(
          id,
          flags,
          data: flags & StreamFlag.data != 0 ? d.buffer() : null,
        );
      default:
        throw FormatException('Unknown bare-rpc message type $type');
    }
  }

  static void _encodeError(Encoder e, RpcError error) => e
    ..utf8String(error.message)
    ..utf8String(error.code)
    ..int_(error.errno);

  static RpcError _decodeError(Decoder d) =>
      RpcError(d.utf8String(), code: d.utf8String(), errno: d.int_());
}

class RpcRequest extends RpcMessage {
  const RpcRequest(super.id, {this.command = 0, this.stream = 0, this.data});

  final int command;

  /// [StreamFlag.open] when the request body is sent as a stream.
  final int stream;
  final Uint8List? data;
}

class RpcResponse extends RpcMessage {
  const RpcResponse(super.id, {this.stream = 0, this.error, this.data});

  /// [StreamFlag.open] when the reply comes as a stream.
  final int stream;
  final RpcError? error;
  final Uint8List? data;
}

class RpcStreamFrame extends RpcMessage {
  const RpcStreamFrame(super.id, this.flags, {this.error, this.data});

  final int flags;
  final RpcError? error;
  final Uint8List? data;
}
