// Adapted from SebastianKumor/qvac_flutter (Apache-2.0). See LICENSE in this directory.
import 'dart:typed_data';

/// Frames bigger than this are treated as a broken connection.
const maxFrameLength = 16 * 1024 * 1024;

/// Puts the uint32 little endian length in front of a message body.
Uint8List frame(Uint8List body) {
  final out = Uint8List(4 + body.length);
  ByteData.sublistView(out).setUint32(0, body.length, Endian.little);
  out.setRange(4, out.length, body);
  return out;
}

/// Turns chunks of bytes, cut anywhere, back into whole message bodies.
class FrameReader {
  final _pending = BytesBuilder();
  // Bytes needed before the next frame can be read. Avoids re-copying big frames.
  int _need = 4;

  List<Uint8List> add(List<int> chunk) {
    _pending.add(chunk);
    if (_pending.length < _need) return const [];
    final buffer = _pending.takeBytes();
    final bodies = <Uint8List>[];
    var at = 0;
    _need = 4;
    while (buffer.length - at >= 4) {
      final length = ByteData.sublistView(
        buffer,
        at,
      ).getUint32(0, Endian.little);
      if (length > maxFrameLength) {
        throw FormatException('bare-rpc frame of $length bytes is too big');
      }
      if (buffer.length - at - 4 < length) {
        _need = 4 + length;
        break;
      }
      bodies.add(Uint8List.sublistView(buffer, at + 4, at + 4 + length));
      at += 4 + length;
    }
    if (at < buffer.length) _pending.add(Uint8List.sublistView(buffer, at));
    return bodies;
  }
}
