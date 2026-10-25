import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tonex_tweaker/tonex/framing.dart';
import 'package:tonex_tweaker/tonex/params.dart';
import 'package:tonex_tweaker/tonex/protocol.dart';

/// Unframed payloads captured from a real ToneX One.
Uint8List fixture(String name) => File('test/fixtures/$name').readAsBytesSync();

void main() {
  group('framing', () {
    test('hello frame matches the bytes accepted by the pedal', () {
      final f = frame(helloRequest());
      expect(f.first, 0x7E);
      expect(f.last, 0x7E);
      expect(FrameDecoder().add(f).single, helloRequest());
    });

    test('stuffs flag and escape bytes', () {
      final f = frame([0x7E, 0x7D, 0x01]);
      expect(f.sublist(1, 5), [0x7D, 0x5E, 0x7D, 0x5D]);
      expect(FrameDecoder().add(f).single, [0x7E, 0x7D, 0x01]);
    });

    test('reassembles frames split across arbitrary chunks', () {
      final a = fixture('preset_details_payload.bin');
      final b = fixture('state_payload.bin');
      final stream = [...frame(a), ...frame(b)];
      final decoder = FrameDecoder();
      final out = <Uint8List>[];
      for (var i = 0; i < stream.length; i += 61) {
        out.addAll(decoder.add(stream.sublist(i, (i + 61).clamp(0, stream.length))));
      }
      expect(out, [a, b]);
    });

    test('drops frames with a bad CRC', () {
      final f = frame(stateRequest());
      f[3] ^= 0x01;
      final decoder = FrameDecoder();
      expect(decoder.add(f), isEmpty);
      expect(decoder.droppedFrames, 1);
    });
  });

  group('messages', () {
    test('state', () {
      final m = parseMessage(fixture('state_payload.bin'))!;
      expect(m.type, MessageType.state);
      final s = PedalState.tryParse(m.body)!;
      expect(s.currentSlot, Slot.b);
      expect(s.slotAPreset, 0);
      expect(s.slotBPreset, 12);
      expect(s.slotCPreset, 10);
      expect(s.activePreset, 12);
      expect(s.bypass, isFalse);
      expect(s.inputTrim, 0);
    });

    test('preset details', () {
      final m = parseMessage(fixture('preset_details_payload.bin'))!;
      expect(m.type, MessageType.presetDetails);
      final d = PresetDetails.tryParse(m.body)!;
      expect(d.index, 12);
      expect(d.name, 'Clean Amp');
      expect(d.values, hasLength(parameterCount));
      expect(d.values[16], 5.0); // EQ treble
      expect(d.values[17], 2000.0); // EQ treble freq
      expect(d.values[20], 6.0); // amp gain
      expect(d.values[38], 5.0); // reverb model = plate
      expect(d.values[62], 40.0); // plate mix
      expect(d.values[99], 350.0); // digital delay time
    });

    test('param changed echo', () {
      final m = parseMessage(fixture('param_changed_payload.bin'))!;
      expect(m.type, MessageType.paramChanged);
      final c = ParamChange.tryParse(m.body)!;
      expect(c.isPresetParam, isFalse); // master volume reply
      expect(c.value, 6.5);

      final echo = parseMessage(
        Uint8List.fromList([
          0xB9,
          0x03,
          0x81,
          0x09,
          0x03,
          0x0A,
          0x02,
          0xB9,
          0x04,
          0x02,
          0x00,
          0x10,
          0x88,
          0x00,
          0x00,
          0xE0,
          0x40,
        ]),
      )!;
      final p = ParamChange.tryParse(echo.body)!;
      expect(p.isPresetParam, isTrue);
      expect(p.index, 16);
      expect(p.value, 7.0);
    });

    test('set parameter request layout', () {
      expect(setParameterRequest(16, 7.0), [
        0xB9, 0x03, 0x81, 0x09, 0x03, 0x82, 0x0A, 0x00, 0x80, 0x0B, 0x03, //
        0xB9, 0x04, 0x02, 0x00, 0x10, 0x88, 0x00, 0x00, 0xE0, 0x40,
      ]);
    });
  });

  group('parameter table', () {
    final defs = <ParamDef>[
      for (final b in effectBlocks) ...[
        ?b.enable,
        ?b.post,
        ?b.model,
        ...b.params,
        for (final m in b.models) ...[?m.sync, ?m.timeSignature, ...m.params],
      ],
    ];

    test('indices are in range and unique', () {
      final indices = defs.map((d) => d.index).toList();
      expect(indices.every((i) => i >= 0 && i < parameterCount), isTrue);
      expect(indices.toSet().length, indices.length);
    });

    test('ranges contain the live values of the captured preset', () {
      final d = PresetDetails.tryParse(parseMessage(fixture('preset_details_payload.bin'))!.body)!;
      for (final def in defs.where((d) => d.kind == ParamKind.range)) {
        final v = d.values[def.index];
        expect(v, inInclusiveRange(def.min, def.max), reason: '${def.label} (#${def.index})');
      }
    });
  });
}
