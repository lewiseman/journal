// Adapted from SebastianKumor/qvac_flutter (Apache-2.0). See ../LICENSE.
import 'dart:convert';
import 'dart:typed_data';

/// Writes compact-encoding values, the format bare-rpc frames use.
class Encoder {
  final _bytes = BytesBuilder(copy: false);
  final _scratch = ByteData(8);

  Uint8List takeBytes() => _bytes.takeBytes();

  void uint(int n) {
    if (n < 0) throw ArgumentError.value(n, 'n', 'must not be negative');
    if (n <= 0xfc) {
      _bytes.addByte(n);
    } else if (n <= 0xffff) {
      _bytes.addByte(0xfd);
      _fixed(n, 2);
    } else if (n <= 0xffffffff) {
      _bytes.addByte(0xfe);
      _fixed(n, 4);
    } else {
      _bytes.addByte(0xff);
      _fixed(n, 8);
    }
  }

  /// Zigzag, so small negative numbers stay small.
  void int_(int n) => uint(n >= 0 ? n * 2 : -n * 2 - 1);

  void boolean(bool b) => _bytes.addByte(b ? 1 : 0);

  void buffer(List<int> data) {
    uint(data.length);
    _bytes.add(data);
  }

  void utf8String(String s) => buffer(utf8.encode(s));

  void _fixed(int n, int width) {
    switch (width) {
      case 2:
        _scratch.setUint16(0, n, Endian.little);
      case 4:
        _scratch.setUint32(0, n, Endian.little);
      default:
        _scratch.setUint64(0, n, Endian.little);
    }
    _bytes.add(Uint8List.sublistView(_scratch, 0, width));
  }
}

/// Reads what [Encoder] writes. Throws [FormatException] on short input.
class Decoder {
  Decoder(this._bytes) : _data = ByteData.sublistView(_bytes);

  final Uint8List _bytes;
  final ByteData _data;
  int _at = 0;

  bool get done => _at == _bytes.length;

  int uint() {
    final first = _byte();
    return switch (first) {
      0xfd => _fixed(2),
      0xfe => _fixed(4),
      0xff => _fixed(8),
      _ => first,
    };
  }

  int int_() {
    final n = uint();
    return n.isEven ? n ~/ 2 : -(n + 1) ~/ 2;
  }

  bool boolean() => _byte() != 0;

  Uint8List buffer() {
    final length = uint();
    _need(length);
    final out = Uint8List.sublistView(_bytes, _at, _at + length);
    _at += length;
    return out;
  }

  String utf8String() => utf8.decode(buffer());

  int _byte() {
    _need(1);
    return _bytes[_at++];
  }

  int _fixed(int width) {
    _need(width);
    final n = switch (width) {
      2 => _data.getUint16(_at, Endian.little),
      4 => _data.getUint32(_at, Endian.little),
      _ => _data.getUint64(_at, Endian.little),
    };
    _at += width;
    return n;
  }

  void _need(int n) {
    if (n < 0 || _at + n > _bytes.length) {
      throw const FormatException('bare-rpc message ended early');
    }
  }
}
