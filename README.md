# tonex-tweaker
Control your Tonex One pedal from your phone. Directly via USB C

Android-only Flutter app that edits the parameters of the active preset on an
IK Multimedia ToneX One (VID `0x1963`, PID `0x00D1`) over its CDC "Control VCOM"
interface. Requires pedal firmware with TONEX Editor support.

## Layout
- `android/.../UsbBridge.kt` – raw USB host CDC transport (permission, bulk I/O)
- `lib/tonex/framing.dart` – HDLC-like framing, CRC-16/X-25
- `lib/tonex/protocol.dart` – requests and parsers (state, preset details, param echo)
- `lib/tonex/params.dart` – the 109 preset parameters grouped by effect block
- `lib/tonex/tonex_controller.dart` – handshake, live sync, coalesced writes
- `test/fixtures` – payloads captured from a real pedal

## Run
```sh
flutter test
flutter run   # phone connected via adb, pedal on the phone's USB-C port
```

Protocol credits: [Builty/TonexOneController](https://github.com/Builty/TonexOneController),
[vit3k/tonex_controller](https://github.com/vit3k/tonex_controller).
