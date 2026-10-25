import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonex_tweaker/tonex/framing.dart';
import 'package:tonex_tweaker/tonex/params.dart';
import 'package:tonex_tweaker/tonex/protocol.dart';
import 'package:tonex_tweaker/tonex/tonex_controller.dart';
import 'package:tonex_tweaker/tonex/usb_link.dart';

/// Replays captured pedal answers for each request type.
class FakePedal implements UsbLink {
  final _events = StreamController<UsbEvent>.broadcast();
  final sent = <Uint8List>[];

  @override
  Stream<UsbEvent> get events => _events.stream;

  @override
  Future<bool> isAttached() async => true;

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  void push(Uint8List payload) => _events.add(UsbData(frame(payload)));

  @override
  Future<void> write(Uint8List bytes) async {
    final p = FrameDecoder().add(bytes).single;
    sent.add(p);
    // Requests are matched on their fixed prefix (their header layout differs from replies).
    if (_starts(p, helloRequest())) {
      push(Uint8List.fromList([0xB9, 0x03, 0x02, 0x01, 0x00, 0x00]));
    } else if (_starts(p, stateRequest())) {
      push(File('test/fixtures/state_payload.bin').readAsBytesSync());
    } else if (_starts(p, presetDetailsRequest(0).sublist(0, 15))) {
      push(File('test/fixtures/preset_details_payload.bin').readAsBytesSync());
    }
  }

  static bool _starts(Uint8List data, List<int> prefix) =>
      data.length >= prefix.length && List.generate(prefix.length, (i) => data[i] == prefix[i]).every((x) => x);

  /// Values of the set-parameter requests sent so far.
  List<double> get paramWrites => [
    for (final p in sent)
      if (_starts(p, setParameterRequest(0, 0).sublist(0, 14)))
        ByteData.sublistView(p, p.length - 4).getFloat32(0, Endian.little),
  ];
}

void main() {
  test('handshake loads the active preset', () {
    fakeAsync((async) {
      final pedal = FakePedal();
      final c = TonexController(link: pedal)..start();
      async.flushMicrotasks();
      expect(c.status, LinkStatus.ready);
      expect(c.presetName, 'Clean Amp');
      expect(c.presetIndex, 12);
      expect(c.value(20), 6.0);
      c.dispose();
    });
  });

  test('slider drags are coalesced and echoes do not overwrite local edits', () {
    fakeAsync((async) {
      final pedal = FakePedal();
      final c = TonexController(link: pedal)..start();
      async.flushMicrotasks();
      const treble = ParamDef(16, 'Treble', max: 10, step: 0.1);

      for (var i = 0; i <= 20; i++) {
        c.setValue(treble, 5 + i * 0.1);
      }
      async.elapse(const Duration(milliseconds: 100));
      final writes = pedal.paramWrites.toList();
      expect(writes.length, lessThanOrEqualTo(2));
      expect(writes.last, closeTo(7.0, 1e-6));

      // A stale preset push (treble = 5.0) right after the edit is ignored.
      pedal.push(File('test/fixtures/preset_details_payload.bin').readAsBytesSync());
      async.flushMicrotasks();
      expect(c.value(16), closeTo(7.0, 1e-6));

      // After the guard window the pedal is authoritative again.
      async.elapse(TonexController.echoGuard);
      pedal.push(File('test/fixtures/preset_details_payload.bin').readAsBytesSync());
      async.flushMicrotasks();
      expect(c.value(16), 5.0);
      c.dispose();
    });
  });
}
