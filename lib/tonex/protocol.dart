import 'dart:typed_data';

/// Message layer of the ToneX One control protocol (payloads before framing).
///
/// Every message starts with `B9 03 <type> <size> <unknown>`, where the three
/// header fields use a compact integer encoding (see [_readInt]).
/// Reverse engineered by vit3k/tonex_controller and Builty/TonexOneController,
/// verified against a ToneX One (VID 0x1963, PID 0x00D1).

enum MessageType { hello, state, presetDetails, presetDetailsFull, paramChanged, unknown }

const _typeCodes = {
  0x02: MessageType.hello,
  0x0306: MessageType.state,
  0x0304: MessageType.presetDetails,
  0x0303: MessageType.presetDetailsFull,
  0x0309: MessageType.paramChanged,
};

enum Slot { a, b, c }

const int presetCount = 20;

class Message {
  Message(this.type, this.typeCode, this.body);

  final MessageType type;
  final int typeCode;

  /// Payload after the header; its length matches the header size field.
  final Uint8List body;
}

/// `0x80 nn` -> nn, `0x81/0x82 lo hi` -> 16-bit LE, otherwise the byte itself.
int _readInt(Uint8List d, List<int> pos) {
  final i = pos[0];
  final b = d[i];
  if (b == 0x81 || b == 0x82) {
    pos[0] = i + 3;
    return d[i + 1] | (d[i + 2] << 8);
  }
  if (b == 0x80) {
    pos[0] = i + 2;
    return d[i + 1];
  }
  pos[0] = i + 1;
  return b;
}

/// Parses an unframed payload; returns null when the header is malformed.
Message? parseMessage(Uint8List data) {
  if (data.length < 5 || data[0] != 0xB9 || data[1] != 0x03) return null;
  final pos = [2];
  try {
    final type = _readInt(data, pos);
    final size = _readInt(data, pos);
    _readInt(data, pos); // unknown field
    if (data.length - pos[0] != size) return null;
    return Message(_typeCodes[type] ?? MessageType.unknown, type, Uint8List.sublistView(data, pos[0]));
  } on RangeError {
    return null;
  }
}

double _f32(Uint8List d, int offset) => ByteData.sublistView(d, offset, offset + 4).getFloat32(0, Endian.little);

Uint8List _f32Bytes(double v) {
  final b = ByteData(4)..setFloat32(0, v, Endian.little);
  return b.buffer.asUint8List();
}

// ---------------------------------------------------------------- requests

Uint8List helloRequest() =>
    Uint8List.fromList([0xB9, 0x03, 0x00, 0x82, 0x04, 0x00, 0x80, 0x0B, 0x01, 0xB9, 0x02, 0x02, 0x0B]);

Uint8List stateRequest() => Uint8List.fromList([
  0xB9, 0x03, 0x00, 0x82, 0x06, 0x00, 0x80, 0x0B, 0x03, //
  0xB9, 0x02, 0x81, 0x06, 0x03, 0x0B,
]);

/// Short (~2 KB) preset summary, which carries name and all parameters.
Uint8List presetDetailsRequest(int preset) => Uint8List.fromList([
  0xB9, 0x03, 0x81, 0x00, 0x03, 0x82, 0x06, 0x00, 0x80, 0x0B, 0x03, //
  0xB9, 0x04, 0x0B, 0x01, preset, 0x00,
]);

/// Sets one parameter of the active preset (firmware with Editor support).
/// The pedal answers with a [MessageType.paramChanged] echo followed by a
/// fresh [MessageType.presetDetails] push.
Uint8List setParameterRequest(int index, double value) {
  assert(index >= 0 && index < 0x80);
  return Uint8List.fromList([
    0xB9, 0x03, 0x81, 0x09, 0x03, 0x82, 0x0A, 0x00, 0x80, 0x0B, 0x03, //
    0xB9, 0x04, 0x02, 0x00, index, 0x88, ..._f32Bytes(value),
  ]);
}

// ----------------------------------------------------------------- parsing

/// Global pedal state (message 0x0306). Offsets are relative to the body;
/// tail fields are counted from the end because the body length varies.
class PedalState {
  PedalState(this.raw);

  final Uint8List raw;

  int _tail(int n) => raw[raw.length - n];

  int get slotAPreset => _tail(18);
  int get slotBPreset => _tail(16);
  int get slotCPreset => _tail(14);
  bool get bypass => _tail(12) == 1;
  Slot get currentSlot => Slot.values[_tail(11).clamp(0, 2)];
  bool get stompMode => raw[19] == 1;
  double get inputTrim => _f32(raw, 15);
  double get bpm => _f32(raw, raw.length - 4);

  int get activePreset => switch (currentSlot) {
    Slot.a => slotAPreset,
    Slot.b => slotBPreset,
    Slot.c => slotCPreset,
  };

  static PedalState? tryParse(Uint8List body) => body.length >= 24 ? PedalState(body) : null;
}

const _nameMarker = [0xB9, 0x04, 0xB9, 0x02, 0xBC, 0x21];
const _nameLength = 32;
const _paramsMarker = [0xBA, 0x03, 0xBA];

int _indexOf(Uint8List data, List<int> pattern, [int start = 0]) {
  outer:
  for (var i = start; i <= data.length - pattern.length; i++) {
    for (var j = 0; j < pattern.length; j++) {
      if (data[i + j] != pattern[j]) continue outer;
    }
    return i;
  }
  return -1;
}

/// Preset summary (message 0x0304): name and live parameter values.
class PresetDetails {
  PresetDetails({required this.index, required this.name, required this.values});

  /// Preset number as reported in the body, or null if not recognisable.
  final int? index;
  final String name;
  final List<double> values;

  static PresetDetails? tryParse(Uint8List body) {
    final n = _indexOf(body, _nameMarker);
    if (n < 0 || n + _nameMarker.length + _nameLength > body.length) return null;
    final nameBytes = body.sublist(n + _nameMarker.length, n + _nameMarker.length + _nameLength);
    final end = nameBytes.indexOf(0);
    final name = String.fromCharCodes(end < 0 ? nameBytes : nameBytes.sublist(0, end)).trim();

    // First block is the live parameter set: `BA 03 BA <count>` then
    // `<count>` x (`0x88` + float32 LE).
    final p = _indexOf(body, _paramsMarker, n);
    if (p < 0 || p + 4 > body.length) return null;
    final count = body[p + 3];
    var i = p + 4;
    final values = <double>[];
    for (var k = 0; k < count; k++) {
      if (i + 5 > body.length || body[i] != 0x88) return null;
      values.add(_f32(body, i + 1));
      i += 5;
    }

    // Body starts with `B9 03 01 <preset>`.
    final index = body.length > 3 && body[0] == 0xB9 && body[1] == 0x03 ? body[3] : null;
    return PresetDetails(index: index, name: name, values: values);
  }
}

/// Parameter echo (message 0x0309): `B9 04 <kind> 00 <index> 88 <float32>`.
/// kind 2 = preset parameter, kind 3 = global (index 0 = master volume).
class ParamChange {
  ParamChange(this.kind, this.index, this.value);

  final int kind;
  final int index;
  final double value;

  bool get isPresetParam => kind == 0x02;

  static ParamChange? tryParse(Uint8List body) {
    final p = _indexOf(body, const [0xB9, 0x04]);
    if (p < 0 || p + 10 > body.length || body[p + 5] != 0x88) return null;
    return ParamChange(body[p + 2], body[p + 4], _f32(body, p + 6));
  }
}
