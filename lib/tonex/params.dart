/// ToneX One preset parameters, in the order the pedal sends them.
/// Ranges from Builty/TonexOneController, cross-checked with live values.
library;

enum ParamKind { toggle, range, choice, readOnly }

class ParamDef {
  const ParamDef(
    this.index,
    this.label, {
    this.kind = ParamKind.range,
    this.min = 0,
    this.max = 1,
    this.step = 1,
    this.unit = '',
    this.options = const [],
  });

  const ParamDef.toggle(this.index, this.label)
    : kind = ParamKind.toggle,
      min = 0,
      max = 1,
      step = 1,
      unit = '',
      options = const [];

  const ParamDef.choice(this.index, this.label, this.options)
    : kind = ParamKind.choice,
      min = 0,
      max = 0,
      step = 1,
      unit = '';

  const ParamDef.readOnly(this.index, this.label)
    : kind = ParamKind.readOnly,
      min = 0,
      max = 0,
      step = 1,
      unit = '',
      options = const [];

  final int index;
  final String label;
  final ParamKind kind;
  final double min;
  final double max;
  final double step;
  final String unit;
  final List<String> options;

  int get decimals => step >= 1 ? 0 : (step >= 0.1 ? 1 : 2);

  double clamp(double v) {
    if (kind == ParamKind.choice) return v.roundToDouble().clamp(0, options.length - 1).toDouble();
    if (kind == ParamKind.toggle) return v >= 0.5 ? 1 : 0;
    return v.clamp(min, max).toDouble();
  }

  double quantize(double v) => clamp(min + ((v - min) / step).round() * step);

  String format(double v) {
    switch (kind) {
      case ParamKind.toggle:
        return v >= 0.5 ? 'On' : 'Off';
      case ParamKind.choice:
        final i = v.round();
        return i >= 0 && i < options.length ? options[i] : '#$i';
      case ParamKind.range:
      case ParamKind.readOnly:
        final s = v.toStringAsFixed(decimals);
        return unit.isEmpty ? s : '$s $unit';
    }
  }
}

const parameterCount = 109;

const timeSignatures = [
  '1/32', '1/32 D', '1/32 T', '1/16', '1/16 D', '1/16 T', '1/8', '1/8 D', '1/8 T', //
  '1/4', '1/4 D', '1/4 T', '1/2', '1/2 D', '1/2 T', '1/1', '1/1 D', '1/1 T',
];

/// 0-10 "knob" parameter.
ParamDef _k(int i, String label) => ParamDef(i, label, max: 10, step: 0.1);

ParamDef _pct(int i, String label) => ParamDef(i, label, max: 100, unit: '%');

/// A model inside a multi-model effect block (e.g. Chorus inside Modulation).
class EffectModel {
  const EffectModel(this.name, this.params, {this.sync, this.timeSignature, this.timed});

  final String name;
  final List<ParamDef> params;

  /// Tempo-sync toggle; when on, [timeSignature] replaces [timed].
  final ParamDef? sync;
  final ParamDef? timeSignature;
  final ParamDef? timed;
}

class EffectBlock {
  const EffectBlock({
    required this.title,
    this.enable,
    this.post,
    this.postLabel = 'Post',
    this.model,
    this.models = const [],
    this.params = const [],
  });

  final String title;
  final ParamDef? enable;
  final ParamDef? post;
  final String postLabel;

  /// Selector for [models]; null for single-model blocks.
  final ParamDef? model;
  final List<EffectModel> models;
  final List<ParamDef> params;
}

EffectModel _reverb(String name, int base) => EffectModel(name, [
  ParamDef(base + 3, 'Mix', max: 100, unit: '%'),
  ParamDef(base, 'Time', max: 10, step: 0.1),
  ParamDef(base + 1, 'Pre-Delay', max: 500, unit: 'ms'),
  ParamDef(base + 2, 'Color', min: -10, max: 10, step: 0.1),
]);

/// Tempo-syncable model: the first param is the free-running rate/time.
EffectModel _synced(String name, int base, List<ParamDef> params) => EffectModel(
  name,
  params,
  sync: ParamDef.toggle(base, 'Sync'),
  timeSignature: ParamDef.choice(base + 1, 'Time Sig.', timeSignatures),
  timed: params.first,
);

EffectModel _delay(String name, int base) => _synced(name, base, [
  ParamDef(base + 2, 'Time', max: 1000, unit: 'ms'),
  _pct(base + 3, 'Feedback'),
  _pct(base + 5, 'Mix'),
  ParamDef.toggle(base + 4, 'Ping-Pong'),
]);

final List<EffectBlock> effectBlocks = [
  const EffectBlock(
    title: 'Noise Gate',
    post: ParamDef.toggle(0, 'Post'),
    enable: ParamDef.toggle(1, 'Enable'),
    params: [
      ParamDef(2, 'Threshold', min: -100, max: 0, unit: 'dB'),
      ParamDef(3, 'Release', min: 5, max: 500, unit: 'ms'),
      ParamDef(4, 'Depth', min: -100, max: -20, unit: 'dB'),
    ],
  ),
  const EffectBlock(
    title: 'Compressor',
    post: ParamDef.toggle(5, 'Post'),
    enable: ParamDef.toggle(6, 'Enable'),
    params: [
      ParamDef(7, 'Threshold', min: -40, max: 0, unit: 'dB'),
      ParamDef(8, 'Gain', min: -30, max: 10, unit: 'dB'),
      ParamDef(9, 'Attack', min: 1, max: 51, unit: 'ms'),
    ],
  ),
  EffectBlock(
    title: 'Amplifier',
    enable: const ParamDef.toggle(18, 'Amp Enable'),
    params: [_k(20, 'Gain'), _k(21, 'Volume'), _pct(22, 'Mix'), _k(34, 'Presence'), _k(35, 'Depth')],
  ),
  EffectBlock(
    title: 'Equalizer',
    post: const ParamDef.toggle(10, 'Post'),
    params: [
      _k(11, 'Bass'),
      const ParamDef(12, 'Bass Freq', min: 75, max: 600, unit: 'Hz'),
      _k(13, 'Mid'),
      const ParamDef(14, 'Mid Q', min: 0.2, max: 3, step: 0.1),
      const ParamDef(15, 'Mid Freq', min: 150, max: 5000, step: 10, unit: 'Hz'),
      _k(16, 'Treble'),
      const ParamDef(17, 'Treble Freq', min: 1000, max: 4000, step: 10, unit: 'Hz'),
    ],
  ),
  EffectBlock(
    title: 'Cabinet',
    model: const ParamDef.choice(24, 'Type', ['Tone Model', 'VIR', 'Disabled']),
    models: [
      const EffectModel('Tone Model', []),
      EffectModel('VIR', [
        const ParamDef.readOnly(25, 'VIR Cabinet'),
        _k(26, 'Resonance'),
        const ParamDef.choice(27, 'Mic 1', ['Condenser', 'Dynamic', 'Ribbon']),
        _k(28, 'Mic 1 X'),
        _k(29, 'Mic 1 Z'),
        const ParamDef.choice(30, 'Mic 2', ['Condenser', 'Dynamic', 'Ribbon']),
        _k(31, 'Mic 2 X'),
        _k(32, 'Mic 2 Z'),
        const ParamDef(33, 'Mic Blend', min: -100, max: 100),
      ]),
      const EffectModel('Disabled', []),
    ],
  ),
  EffectBlock(
    title: 'Modulation',
    post: const ParamDef.toggle(63, 'Post'),
    enable: const ParamDef.toggle(64, 'Enable'),
    model: const ParamDef.choice(65, 'Model', ['Chorus', 'Tremolo', 'Phaser', 'Flanger', 'Rotary']),
    models: [
      _synced('Chorus', 66, [
        const ParamDef(68, 'Rate', min: 0.1, max: 10, step: 0.1, unit: 'Hz'),
        _pct(69, 'Depth'),
        _k(70, 'Level'),
      ]),
      _synced('Tremolo', 71, [
        const ParamDef(73, 'Rate', min: 0.1, max: 10, step: 0.1, unit: 'Hz'),
        _k(74, 'Shape'),
        _pct(75, 'Spread'),
        _k(76, 'Level'),
      ]),
      _synced('Phaser', 77, [
        const ParamDef(79, 'Rate', min: 0.1, max: 10, step: 0.1, unit: 'Hz'),
        _pct(80, 'Depth'),
        _k(81, 'Level'),
      ]),
      _synced('Flanger', 82, [
        const ParamDef(84, 'Rate', min: 0.1, max: 10, step: 0.1, unit: 'Hz'),
        _pct(85, 'Depth'),
        _pct(86, 'Feedback'),
        _k(87, 'Level'),
      ]),
      _synced('Rotary', 88, [
        const ParamDef(90, 'Speed', max: 400, unit: 'rpm'),
        const ParamDef(91, 'Radius', max: 300, unit: 'mm'),
        _pct(92, 'Spread'),
        _k(93, 'Level'),
      ]),
    ],
  ),
  EffectBlock(
    title: 'Delay',
    post: const ParamDef.toggle(94, 'Post'),
    enable: const ParamDef.toggle(95, 'Enable'),
    model: const ParamDef.choice(96, 'Model', ['Digital', 'Tape']),
    models: [_delay('Digital', 97), _delay('Tape', 103)],
  ),
  EffectBlock(
    title: 'Reverb',
    post: const ParamDef.toggle(36, 'Post'),
    enable: const ParamDef.toggle(37, 'Enable'),
    model: const ParamDef.choice(38, 'Model', ['Spring 1', 'Spring 2', 'Spring 3', 'Spring 4', 'Room', 'Plate']),
    models: [
      _reverb('Spring 1', 39),
      _reverb('Spring 2', 43),
      _reverb('Spring 3', 47),
      _reverb('Spring 4', 51),
      _reverb('Room', 55),
      _reverb('Plate', 59),
    ],
  ),
];
