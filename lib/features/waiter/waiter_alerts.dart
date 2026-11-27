import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sound/alert_policy.dart';
import '../../core/sound/alert_sound.dart';
import '../../core/sse/notifications_service.dart';
import '../auth/auth_controller.dart';

/// Rings and flashes a message for what happens to the waiter's own orders, on EVERY waiter tab (the shell keeps it alive),
/// where it used to exist only on the Tables screen. Which event rings is decided by [alertFor]; bursts are tamed by [AlertGate].
class WaiterAlerts extends ConsumerStatefulWidget {
  const WaiterAlerts({super.key, this.gate});
  final AlertGate? gate;

  @override
  ConsumerState<WaiterAlerts> createState() => _WaiterAlertsState();
}

class _WaiterAlertsState extends ConsumerState<WaiterAlerts> {
  late final AlertGate _gate = widget.gate ?? AlertGate();

  String _message(AlertKind kind, SseEvent e) {
    final order = '#${e.map['orderId'] ?? ''}';
    return switch (kind) {
      AlertKind.ready => 'Commande $order : prête à servir',
      AlertKind.delayed =>
        'Commande $order : en attente de la cuisine depuis ${e.map['pendingMinutes'] ?? '?'} min',
      AlertKind.orderClosed =>
        'Commande $order : ${e.map['newStatus'] == 'paid' ? 'payée' : 'annulée'}',
    };
  }

  void _onEvent(SseEvent e) {
    final kind = alertFor(e, myUserId: ref.read(authProvider).user?.id);
    if (kind == null || !mounted) return;

    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(_message(kind, e)),
        backgroundColor: kind == AlertKind.delayed
            ? Theme.of(context).colorScheme.error
            : null,
      ),
    );

    final settings = ref.read(soundSettingsProvider);
    if (settings.enabled && _gate.shouldPlay(kind, e, DateTime.now())) {
      ref.read(alertSinkProvider).play(kind, settings.volume);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sseEventsProvider, (_, next) {
      final e = next.value;
      if (e != null) _onEvent(e);
    });
    return const SizedBox.shrink();
  }
}

/// Sound on/off and volume for this terminal.
Future<void> showSoundSettings(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _SoundSettingsDialog(),
  );
}

class _SoundSettingsDialog extends ConsumerWidget {
  const _SoundSettingsDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(soundSettingsProvider);
    final notifier = ref.read(soundSettingsProvider.notifier);
    final sink = ref.read(alertSinkProvider);
    return AlertDialog(
      title: const Text('Sons de notification'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Activer les sons'),
            subtitle: const Text(
              'Commande prête, retard de la cuisine, commande payée ou annulée',
            ),
            value: settings.enabled,
            onChanged: notifier.setEnabled,
          ),
          const SizedBox(height: 8),
          const Text('Volume'),
          Slider(
            value: settings.volume,
            divisions: 10,
            label: '${(settings.volume * 100).round()} %',
            onChanged: settings.enabled ? notifier.setVolume : null,
          ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: settings.enabled
                    ? () => sink.play(AlertKind.ready, settings.volume)
                    : null,
                child: const Text('Essayer « prête »'),
              ),
              OutlinedButton(
                onPressed: settings.enabled
                    ? () => sink.play(AlertKind.delayed, settings.volume)
                    : null,
                child: const Text('Essayer « retard »'),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}
