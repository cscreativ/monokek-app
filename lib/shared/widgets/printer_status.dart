import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/printing/print_providers.dart';
import '../../core/storage/app_storage.dart';
import 'setup_pin_dialog.dart';

/// Opens the USB printer settings, after the terminal PIN when one exists.
Future<void> openUsbPrinterSettings(BuildContext context, WidgetRef ref) async {
  if (await confirmSetupPin(context, ref.read(storageProvider)) && context.mounted) context.push('/printer/usb');
}

/// Header pill for this terminal's USB printer: hidden until one is configured, green while the last job went
/// through, red after a failure (tap = open the settings).
class PrinterStatus extends ConsumerWidget {
  const PrinterStatus({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final binding = ref.watch(usbBindingProvider);
    if (binding == null) return const SizedBox.shrink();
    final last = ref.watch(lastPrintOutcomeProvider);
    final failed = last != null && !last.ok;
    final color = failed ? const Color(0xFFDC2626) : const Color(0xFF059669);
    final message = failed ? 'Dernière impression échouée : ${last.error ?? ''}' : 'Imprimante USB : ${binding.device.name}';

    return Tooltip(
      message: message,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => openUsbPrinterSettings(context, ref),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(LucideIcons.printer, size: 14, color: color),
            if (!compact) ...[
              const SizedBox(width: 6),
              Text(failed ? 'ERREUR' : 'IMPRIMANTE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1, color: color)),
            ],
          ]),
        ),
      ),
    );
  }
}
