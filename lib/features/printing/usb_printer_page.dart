import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/api/envelope.dart';
import '../../core/branch.dart';
import '../../core/printing/print_providers.dart';
import '../../core/printing/test_ticket.dart';
import '../../core/printing/usb_print_worker.dart';
import '../../core/printing/usb_printer.dart';
import '../../core/printing/usb_printer_settings.dart';
import '../../core/theme/app_theme.dart';
import '../../data/printing_api.dart';
import '../auth/auth_controller.dart';

/// Binds this terminal to a USB thermal printer (Xprinter & co): which device is plugged in, which of the
/// server's USB printers it stands for, and a local test print. The tickets themselves are rendered by the
/// server — see UsbPrintWorker.
class UsbPrinterPage extends ConsumerStatefulWidget {
  const UsbPrinterPage({super.key});
  @override
  ConsumerState<UsbPrinterPage> createState() => _UsbPrinterPageState();
}

class _UsbPrinterPageState extends ConsumerState<UsbPrinterPage> {
  List<UsbPrinterDevice> _devices = const [];
  List<ServerUsbPrinter> _serverPrinters = const [];
  UsbPrinterDevice? _device;
  final Set<int> _selected = {};
  int _paperWidth = 58;
  int? _branchId;
  bool _loading = true;
  bool _busy = false;
  String? _serverError;

  @override
  void initState() {
    super.initState();
    final b = ref.read(usbBindingProvider);
    if (b != null) {
      _device = b.device;
      _selected.addAll(b.printerIds);
      _paperWidth = b.paperWidth;
    }
    _load();
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? Theme.of(context).colorScheme.error : null));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _serverError = null;
    });
    final transport = ref.read(usbTransportProvider);
    try {
      _devices = await transport.listDevices();
    } catch (e) {
      _snack("Impossible de lister les appareils USB : $e", error: true);
    }
    try {
      final dio = ref.read(apiClientProvider);
      _branchId = await resolveBranchId(dio, ref.read(authProvider).user);
      _serverPrinters = _branchId == null ? const [] : await ref.read(printingApiProvider).usbPrinters(_branchId!);
    } catch (e) {
      _serverError = errorMessage(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  UsbPrinterDevice? get _currentDevice {
    final d = _device;
    if (d == null) return null;
    // Prefer the live entry (fresh name) when the device is plugged in right now.
    return _devices.where((x) => x.key == d.key).firstOrNull ?? d;
  }

  bool get _pluggedIn => _device != null && _devices.any((d) => d.key == _device!.key);

  Future<void> _test() async {
    final device = _currentDevice;
    if (device == null) return;
    setState(() => _busy = true);
    try {
      final transport = ref.read(usbTransportProvider);
      if (!await transport.requestPermission(device)) throw const UsbPrinterException('Accès USB refusé');
      await transport.write(device, buildTestTicket(deviceName: device.name, paperWidth: _paperWidth));
      _snack('Ticket de test envoyé à l\'imprimante');
    } catch (e) {
      _snack('Échec du test : $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final device = _currentDevice;
    if (device == null || _selected.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(usbBindingProvider.notifier).save(UsbPrinterBinding(device: device, printerIds: {..._selected}, paperWidth: _paperWidth));
      _snack('Imprimante USB enregistrée');
      // Print what was waiting while this terminal had no printer.
      final branchId = _branchId;
      if (branchId != null) await ref.read(usbPrintWorkerProvider).catchUp(branchId);
      if (mounted && context.canPop()) context.pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer l'imprimante USB ?"),
        content: const Text("Ce terminal n'imprimera plus les tickets sur cette imprimante."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(usbBindingProvider.notifier).clear();
    if (!mounted) return;
    setState(() {
      _device = null;
      _selected.clear();
    });
    _snack('Configuration supprimée');
  }

  String _locationLabel(String l) => switch (l) {
        'receipt' => 'Caisse (reçus)',
        'kitchen' => 'Cuisine',
        'bar' => 'Bar',
        _ => l,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final transport = ref.watch(usbTransportProvider);
    final last = ref.watch(lastPrintOutcomeProvider);
    final configured = ref.watch(usbBindingProvider) != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Imprimante USB'),
        actions: [IconButton(tooltip: 'Actualiser', icon: const Icon(LucideIcons.refreshCw, size: 18), onPressed: _loading ? null : _load)],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: !transport.isSupported
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    "L'impression USB directe est disponible sur Android, Windows et Linux. Sur ce poste, les tickets sont imprimés par l'application de bureau.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                )
              : _loading
                  ? const CircularProgressIndicator()
                  : ListView(padding: const EdgeInsets.all(20), children: [
                      _section('1. IMPRIMANTE BRANCHÉE', scheme),
                      _deviceList(scheme),
                      const SizedBox(height: 24),
                      _section('2. IMPRIMANTES DU SERVEUR DESSERVIES', scheme),
                      _serverList(scheme),
                      const SizedBox(height: 24),
                      _section('3. LARGEUR DU PAPIER (TICKET DE TEST)', scheme),
                      SegmentedButton<int>(
                        segments: const [ButtonSegment(value: 58, label: Text('58 mm')), ButtonSegment(value: 80, label: Text('80 mm'))],
                        selected: {_paperWidth},
                        onSelectionChanged: (s) => setState(() => _paperWidth = s.first),
                      ),
                      if (last != null) ...[
                        const SizedBox(height: 20),
                        _lastResult(last, scheme),
                      ],
                      const SizedBox(height: 24),
                      OutlinedButton.icon(
                        onPressed: _busy || _device == null || !_pluggedIn ? null : _test,
                        icon: const Icon(LucideIcons.printer, size: 18),
                        label: const Text("TESTER L'IMPRESSION"),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _busy || _device == null || _selected.isEmpty ? null : _save,
                        child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('ENREGISTRER'),
                      ),
                      if (configured) ...[
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _busy ? null : _remove,
                          style: TextButton.styleFrom(foregroundColor: scheme.error),
                          child: const Text('SUPPRIMER LA CONFIGURATION'),
                        ),
                      ],
                    ]),
        ),
      ),
    );
  }

  Widget _section(String title, ColorScheme scheme) =>
      Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(title, style: microLabelStyle.copyWith(color: scheme.onSurface)));

  Widget _hint(String text, ColorScheme scheme, {bool warning = false}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: (warning ? scheme.errorContainer : scheme.surfaceContainerHighest).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text, style: TextStyle(fontSize: 13, color: warning ? scheme.onErrorContainer : scheme.onSurfaceVariant)),
      );

  Widget _deviceList(ColorScheme scheme) {
    final known = _device;
    final missing = known != null && !_devices.any((d) => d.key == known.key);
    if (_devices.isEmpty && known == null) {
      return _hint("Aucun appareil USB détecté. Branchez l'imprimante (sur téléphone ou tablette : câble OTG), puis actualisez.", scheme);
    }
    final sorted = [..._devices]..sort((a, b) => (b.isPrinter ? 1 : 0).compareTo(a.isPrinter ? 1 : 0));
    return RadioGroup<String>(
      groupValue: _device?.key,
      onChanged: (key) => setState(() => _device = _devices.where((d) => d.key == key).firstOrNull ?? _device),
      child: Column(children: [
        for (final d in sorted)
          RadioListTile<String>(
            value: d.key,
            title: Text(d.name),
            subtitle: Text('${d.isPrinter ? 'Imprimante' : 'Appareil USB'} · ${d.vendorId.toRadixString(16)}:${d.productId.toRadixString(16)}'),
            secondary: Icon(d.isPrinter ? LucideIcons.printer : LucideIcons.usb, size: 18),
          ),
        if (missing)
          ListTile(
            leading: Icon(LucideIcons.unplug, size: 18, color: scheme.error),
            title: Text(known.name),
            subtitle: const Text('Enregistrée, mais non branchée en ce moment'),
          ),
      ]),
    );
  }

  Widget _serverList(ColorScheme scheme) {
    if (_serverError != null) return _hint("Liste des imprimantes du serveur indisponible : $_serverError", scheme, warning: true);
    if (_serverPrinters.isEmpty) {
      return _hint(
        "Aucune imprimante USB active n'est déclarée pour cette succursale. Créez-la dans l'administration "
        "(Réglages › Imprimantes, interface « USB Local ») puis actualisez.",
        scheme,
        warning: true,
      );
    }
    return Column(children: [
      for (final p in _serverPrinters)
        CheckboxListTile(
          value: _selected.contains(p.id),
          onChanged: (v) => setState(() {
            if (v == true) {
              _selected.add(p.id);
              _paperWidth = p.paperWidth == 80 ? 80 : 58;
            } else {
              _selected.remove(p.id);
            }
          }),
          title: Text(p.name),
          subtitle: Text('${_locationLabel(p.location)} · papier ${p.paperWidth} mm'),
        ),
    ]);
  }

  Widget _lastResult(PrintOutcome o, ColorScheme scheme) {
    final color = o.ok ? AppColors.success : scheme.error;
    return Row(children: [
      Icon(o.ok ? LucideIcons.circleCheck : LucideIcons.circleAlert, size: 18, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          o.ok ? 'Dernière impression : ticket #${o.jobId} imprimé' : 'Dernière impression échouée (#${o.jobId}) : ${o.error ?? ''}',
          style: TextStyle(fontSize: 13, color: color),
        ),
      ),
    ]);
  }
}
