import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'framing.dart';
import 'params.dart';
import 'protocol.dart';
import 'usb_link.dart';

enum LinkStatus { noDevice, connecting, syncing, ready, error }

/// Owns the session with the pedal: handshake, state tracking and
/// coalesced parameter writes.
class TonexController extends ChangeNotifier {
  TonexController({UsbLink? link}) : _link = link ?? UsbLink();

  /// Minimum spacing between parameter writes while a slider is dragged.
  static const sendInterval = Duration(milliseconds: 40);

  /// Pedal pushes arriving shortly after a local edit carry stale values.
  static const echoGuard = Duration(milliseconds: 600);

  final UsbLink _link;
  final FrameDecoder _decoder = FrameDecoder();
  StreamSubscription<UsbEvent>? _sub;
  Timer? _helloRetry;

  LinkStatus status = LinkStatus.noDevice;
  String? error;
  PedalState? pedal;
  String? presetName;
  int? presetIndex;
  List<double>? values;

  final Map<int, double> _pending = {};
  final Map<int, DateTime> _lastLocalEdit = {};
  Timer? _flushTimer;
  DateTime _lastSend = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isReady => status == LinkStatus.ready && values != null;

  double value(int index) => values != null && index < values!.length ? values![index] : 0;

  Future<void> start() async {
    _sub ??= _link.events.listen(_onUsbEvent);
    if (await _link.isAttached()) await connect();
  }

  Future<void> connect() async {
    if (status == LinkStatus.connecting || status == LinkStatus.syncing) return;
    _set(LinkStatus.connecting);
    try {
      await _link.connect();
    } on PlatformException catch (e) {
      _fail(e.code == 'NOT_FOUND' ? null : (e.message ?? e.code));
      return;
    }
    _set(LinkStatus.syncing);
    await _send(helloRequest());
    // The pedal occasionally ignores the first hello right after enumeration.
    _helloRetry?.cancel();
    _helloRetry = Timer.periodic(const Duration(seconds: 2), (_) {
      if (status == LinkStatus.syncing) _send(pedal == null ? helloRequest() : stateRequest());
    });
  }

  Future<void> reload() async {
    if (status != LinkStatus.ready) return connect();
    await _send(stateRequest());
  }

  /// Updates a parameter locally and schedules its transmission.
  void setValue(ParamDef def, double v) {
    final vals = values;
    if (vals == null || def.index >= vals.length) return;
    final q = def.quantize(v);
    if (vals[def.index] == q && !_pending.containsKey(def.index)) return;
    vals[def.index] = q;
    _pending[def.index] = q;
    _lastLocalEdit[def.index] = clock.now();
    notifyListeners();
    _scheduleFlush();
  }

  void _scheduleFlush() {
    if (_flushTimer != null) return;
    final wait = sendInterval - clock.now().difference(_lastSend);
    _flushTimer = Timer(wait.isNegative ? Duration.zero : wait, _flush);
  }

  Future<void> _flush() async {
    _flushTimer = null;
    if (_pending.isEmpty) return;
    final batch = Map.of(_pending);
    _pending.clear();
    _lastSend = clock.now();
    for (final e in batch.entries) {
      await _send(setParameterRequest(e.key, e.value));
    }
    if (_pending.isNotEmpty) _scheduleFlush();
  }

  Future<void> _send(Uint8List payload) async {
    try {
      await _link.write(frame(payload));
    } on PlatformException catch (e) {
      _fail(e.message ?? e.code);
    }
  }

  void _onUsbEvent(UsbEvent e) {
    switch (e) {
      case UsbData(:final bytes):
        for (final f in _decoder.add(bytes)) {
          final m = parseMessage(f);
          if (m != null) _onMessage(m);
        }
      case UsbAttached():
        connect();
      case UsbDetached():
        _reset();
        _set(LinkStatus.noDevice);
    }
  }

  void _onMessage(Message m) {
    switch (m.type) {
      case MessageType.hello:
        _send(stateRequest());
      case MessageType.state:
        final s = PedalState.tryParse(m.body);
        if (s == null) return;
        final changed = pedal?.activePreset != s.activePreset;
        pedal = s;
        if (changed || values == null) _send(presetDetailsRequest(s.activePreset));
        notifyListeners();
      case MessageType.presetDetails:
        final d = PresetDetails.tryParse(m.body);
        if (d == null) return;
        // A preset switched on the pedal itself: resync slot info too.
        if (pedal != null && d.index != null && d.index != pedal!.activePreset) {
          _send(stateRequest());
        }
        _applyDetails(d);
      case MessageType.paramChanged:
        final c = ParamChange.tryParse(m.body);
        if (c == null || !c.isPresetParam) return;
        _applyRemoteValue(c.index, c.value);
        notifyListeners();
      case MessageType.presetDetailsFull:
      case MessageType.unknown:
        break;
    }
  }

  void _applyDetails(PresetDetails d) {
    final first = values == null || presetIndex != d.index;
    if (first || values!.length != d.values.length) {
      values = List.of(d.values);
      _pending.clear();
    } else {
      for (var i = 0; i < d.values.length; i++) {
        _applyRemoteValue(i, d.values[i]);
      }
    }
    presetName = d.name;
    presetIndex = d.index ?? pedal?.activePreset;
    _helloRetry?.cancel();
    _set(LinkStatus.ready);
  }

  void _applyRemoteValue(int index, double v) {
    final vals = values;
    if (vals == null || index >= vals.length) return;
    if (_pending.containsKey(index)) return;
    final edited = _lastLocalEdit[index];
    if (edited != null && clock.now().difference(edited) < echoGuard) return;
    vals[index] = v;
  }

  void _fail(String? message) {
    _reset();
    error = message;
    _set(message == null ? LinkStatus.noDevice : LinkStatus.error);
  }

  void _reset() {
    _helloRetry?.cancel();
    _flushTimer?.cancel();
    _flushTimer = null;
    _pending.clear();
    pedal = null;
    values = null;
    presetName = null;
    presetIndex = null;
  }

  void _set(LinkStatus s) {
    if (s != LinkStatus.error) error = null;
    status = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _reset();
    _sub?.cancel();
    _link.disconnect();
    super.dispose();
  }
}
