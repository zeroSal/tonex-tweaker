import 'package:flutter/services.dart';

sealed class UsbEvent {}

class UsbData extends UsbEvent {
  UsbData(this.bytes);
  final Uint8List bytes;
}

class UsbAttached extends UsbEvent {}

class UsbDetached extends UsbEvent {}

/// Dart side of the native CDC bridge (android/.../UsbBridge.kt).
class UsbLink {
  static const _methods = MethodChannel('tonex/usb');
  static const _events = EventChannel('tonex/usb/events');

  late final Stream<UsbEvent> events = _events.receiveBroadcastStream().map((e) {
    final m = e as Map;
    return switch (m['type']) {
      'data' => UsbData(m['bytes'] as Uint8List),
      'attached' => UsbAttached(),
      _ => UsbDetached(),
    };
  });

  Future<bool> isAttached() async => await _methods.invokeMethod<bool>('isAttached') ?? false;

  /// Requests permission if needed and opens the CDC interface.
  Future<void> connect() => _methods.invokeMethod('connect');

  Future<void> disconnect() => _methods.invokeMethod('disconnect');

  Future<void> write(Uint8List bytes) => _methods.invokeMethod('write', bytes);
}
