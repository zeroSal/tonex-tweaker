import 'package:flutter/material.dart';

import '../tonex/params.dart';
import '../tonex/tonex_controller.dart';

class BlockCard extends StatelessWidget {
  const BlockCard({super.key, required this.block, required this.controller});

  final EffectBlock block;
  final TonexController controller;

  bool _on(ParamDef p) => controller.value(p.index) >= 0.5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enable = block.enable;
    final active = enable == null || _on(enable);

    final model = block.model == null || block.models.isEmpty
        ? null
        : block.models[controller.value(block.model!.index).round().clamp(0, block.models.length - 1)];

    final rows = <Widget>[
      if (block.post != null || block.model != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (block.model != null) _ChoiceField(def: block.model!, controller: controller),
              if (block.post != null)
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Pre')),
                    ButtonSegment(value: true, label: Text('Post')),
                  ],
                  selected: {_on(block.post!)},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => controller.setValue(block.post!, s.first ? 1 : 0),
                ),
            ],
          ),
        ),
      for (final p in block.params) ParamControl(def: p, controller: controller),
      if (model != null) ..._modelRows(model),
    ];

    return Card(
      margin: const EdgeInsets.only(top: 12),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          maintainState: true,
          title: Row(
            children: [
              Expanded(
                child: Text(
                  block.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: active ? null : theme.disabledColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (enable != null) Switch(value: active, onChanged: (v) => controller.setValue(enable, v ? 1 : 0)),
            ],
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            AnimatedOpacity(
              opacity: active ? 1 : 0.45,
              duration: const Duration(milliseconds: 150),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _modelRows(EffectModel model) {
    final sync = model.sync;
    final synced = sync != null && _on(sync);
    return [
      if (sync != null) ParamControl(def: sync, controller: controller),
      for (final p in model.params)
        if (synced && p.index == model.timed?.index)
          ParamControl(def: model.timeSignature!, controller: controller)
        else
          ParamControl(def: p, controller: controller),
    ];
  }
}

/// Renders the right control for a parameter kind.
class ParamControl extends StatelessWidget {
  const ParamControl({super.key, required this.def, required this.controller});

  final ParamDef def;
  final TonexController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = controller.value(def.index);
    switch (def.kind) {
      case ParamKind.toggle:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(def.label),
          value: v >= 0.5,
          onChanged: (on) => controller.setValue(def, on ? 1 : 0),
        );
      case ParamKind.choice:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(child: Text(def.label)),
              _ChoiceField(def: def, controller: controller),
            ],
          ),
        );
      case ParamKind.readOnly:
        return ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(def.label),
          trailing: Text(def.format(v), style: theme.textTheme.bodyLarge),
        );
      case ParamKind.range:
        final divisions = ((def.max - def.min) / def.step).round();
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(def.label)),
                  Text(
                    def.format(v),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              Slider(
                min: def.min,
                max: def.max,
                divisions: divisions > 0 && divisions <= 1000 ? divisions : null,
                value: def.clamp(v),
                onChanged: (x) => controller.setValue(def, x),
              ),
            ],
          ),
        );
    }
  }
}

class _ChoiceField extends StatelessWidget {
  const _ChoiceField({required this.def, required this.controller});

  final ParamDef def;
  final TonexController controller;

  @override
  Widget build(BuildContext context) {
    final current = controller.value(def.index).round();
    return DropdownButton<int>(
      value: current >= 0 && current < def.options.length ? current : null,
      hint: Text(def.format(current.toDouble())),
      items: [for (var i = 0; i < def.options.length; i++) DropdownMenuItem(value: i, child: Text(def.options[i]))],
      onChanged: (i) {
        if (i != null) controller.setValue(def, i.toDouble());
      },
    );
  }
}
