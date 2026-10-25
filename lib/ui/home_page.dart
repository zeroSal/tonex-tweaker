import 'package:flutter/material.dart';

import '../tonex/params.dart';
import '../tonex/protocol.dart';
import '../tonex/tonex_controller.dart';
import 'block_card.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller});

  final TonexController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('ToneX Tweaker'),
          actions: [
            if (controller.isReady)
              IconButton(tooltip: 'Reload from pedal', icon: const Icon(Icons.refresh), onPressed: controller.reload),
          ],
        ),
        body: controller.isReady ? _Editor(controller: controller) : _StatusView(controller: controller),
      ),
    );
  }
}

class _StatusView extends StatelessWidget {
  const _StatusView({required this.controller});

  final TonexController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, title, detail, busy) = switch (controller.status) {
      LinkStatus.noDevice => (
        Icons.usb_off,
        'ToneX One not connected',
        'Plug the pedal into the phone\'s USB-C port (an OTG adapter may be needed).',
        false,
      ),
      LinkStatus.connecting => (Icons.usb, 'Connecting…', 'Allow USB access if Android asks.', true),
      LinkStatus.syncing || LinkStatus.ready => (Icons.sync, 'Reading preset…', '', true),
      LinkStatus.error => (Icons.error_outline, 'Connection error', controller.error ?? '', false),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(detail, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
            ],
            const SizedBox(height: 24),
            if (busy)
              const CircularProgressIndicator()
            else
              FilledButton.icon(
                onPressed: controller.connect,
                icon: const Icon(Icons.power),
                label: const Text('Connect'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Editor extends StatelessWidget {
  const _Editor({required this.controller});

  final TonexController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      children: [
        _PresetHeader(controller: controller),
        for (final block in effectBlocks) BlockCard(block: block, controller: controller),
      ],
    );
  }
}

class _PresetHeader extends StatelessWidget {
  const _PresetHeader({required this.controller});

  final TonexController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pedal = controller.pedal;
    final index = controller.presetIndex;
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              child: Text(index == null ? '?' : '${index + 1}', style: theme.textTheme.titleMedium),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    controller.presetName?.isNotEmpty == true ? controller.presetName! : 'Untitled preset',
                    style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (pedal != null)
                    Text(
                      'Slot ${pedal.currentSlot.name.toUpperCase()}'
                      '${pedal.currentSlot == Slot.c ? ' (stomp)' : ''}'
                      '${pedal.bypass ? ' · bypassed' : ''}',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
