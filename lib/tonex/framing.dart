import 'dart:typed_data';

/// HDLC-like framing used by the ToneX control port:
/// `0x7E | byte-stuffed payload | CRC16 LE (stuffed) | 0x7E`.
/// Bytes 0x7E/0x7D are escaped as `0x7D, b ^ 0x20`.
const int _flag = 0x7E;
const int _escape = 0x7D;

/// CRC-16/X-25 (reflected poly 0x8408, init 0xFFFF, final xor 0xFFFF).
int crc16(List<int> data) {
  var crc = 0xFFFF;
  for (final b in data) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0x8408 : crc >> 1;
    }
  }
  return ~crc & 0xFFFF;
}

void _addStuffed(BytesBuilder out, int b) {
  if (b == _flag || b == _escape) {
    out.addByte(_escape);
    out.addByte(b ^ 0x20);
  } else {
    out.addByte(b);
  }
}

Uint8List frame(List<int> payload) {
  final out = BytesBuilder(copy: false)..addByte(_flag);
  for (final b in payload) {
    _addStuffed(out, b);
  }
  final crc = crc16(payload);
  _addStuffed(out, crc & 0xFF);
  _addStuffed(out, crc >> 8);
  out.addByte(_flag);
  return out.toBytes();
}

/// Reassembles frames from an arbitrary chunked byte stream.
/// Returns CRC-verified, unstuffed payloads; corrupt frames are dropped.
class FrameDecoder {
  final BytesBuilder _current = BytesBuilder(copy: false);
  bool _inFrame = false;
  bool _escaped = false;

  /// Count of frames dropped because of a CRC or length error.
  int droppedFrames = 0;

  List<Uint8List> add(List<int> chunk) {
    final frames = <Uint8List>[];
    for (final b in chunk) {
      if (b == _flag) {
        if (_inFrame && _current.length > 0) {
          final f = _finish();
          if (f != null) frames.add(f);
        }
        // A flag both closes the previous frame and may open the next one.
        _inFrame = true;
        _escaped = false;
        _current.clear();
        continue;
      }
      if (!_inFrame) continue;
      if (_escaped) {
        _current.addByte(b ^ 0x20);
        _escaped = false;
      } else if (b == _escape) {
        _escaped = true;
      } else {
        _current.addByte(b);
      }
    }
    return frames;
  }

  Uint8List? _finish() {
    final raw = _current.takeBytes();
    if (raw.length < 3) {
      droppedFrames++;
      return null;
    }
    final body = Uint8List.sublistView(raw, 0, raw.length - 2);
    final rx = raw[raw.length - 2] | (raw[raw.length - 1] << 8);
    if (rx != crc16(body)) {
      droppedFrames++;
      return null;
    }
    return Uint8List.fromList(body);
  }
}
