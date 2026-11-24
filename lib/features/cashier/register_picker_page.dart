import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/envelope.dart';
import '../../core/storage/app_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../data/cashier_api.dart';
import '../../models/cashier.dart';
import '../auth/auth_controller.dart';

final _registersProvider = FutureProvider.autoDispose<List<CashRegister>>((ref) => ref.watch(cashierApiProvider).listRegisters());

/// "Assigner ce terminal": pick the physical register this device operates (port of pos/sales/page.tsx).
class RegisterPickerPage extends ConsumerWidget {
  const RegisterPickerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final registers = ref.watch(_registersProvider);
    final storage = ref.read(storageProvider);
    final user = ref.watch(authProvider).user;

    Future<void> select(CashRegister r) async {
      await storage.setRegister(r.id, r.name);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Terminal assigné à : ${r.name}')));
      context.go('/pos/sales/order');
    }

    return Scaffold(
      backgroundColor: dark ? AppColors.slate950 : const Color(0xFFFAFAF9),
      body: SafeArea(
        child: Stack(children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('ASSIGNER CE TERMINAL', textAlign: TextAlign.center, style: titleStyle.copyWith(fontSize: 38)),
                  const SizedBox(height: 12),
                  Text('Sélectionnez la caisse physique correspondant à ce poste', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 40),
                  registers.when(
                    loading: () => const Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()),
                    error: (e, _) => Column(children: [
                      Text(errorMessage(e, 'Erreur de chargement des caisses')),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: () => ref.invalidate(_registersProvider), child: const Text('Réessayer')),
                    ]),
                    data: (list) => Wrap(
                      spacing: 24,
                      runSpacing: 24,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final r in list)
                          SizedBox(
                            width: 400,
                            child: Material(
                              color: dark ? AppColors.slate900 : Colors.white,
                              borderRadius: BorderRadius.circular(40),
                              elevation: 1,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(40),
                                onTap: () => select(r),
                                child: Padding(
                                  padding: const EdgeInsets.all(28),
                                  child: Row(children: [
                                    Container(
                                      width: 64,
                                      height: 64,
                                      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
                                      child: const Icon(LucideIcons.monitor, size: 30),
                                    ),
                                    const SizedBox(width: 20),
                                    Expanded(
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                                          Text(r.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                                          if (r.isOpen)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                              decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(999)),
                                              child: Text(
                                                'OCCUPÉE${r.openedByUserName != null ? ' — ${r.openedByUserName}' : ''}',
                                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFFB45309), letterSpacing: 1),
                                              ),
                                            ),
                                          if (r.id == storage.registerId)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                              decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                                              child: const Text('CE POSTE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF059669), letterSpacing: 1)),
                                            ),
                                        ]),
                                        const SizedBox(height: 4),
                                        Text('ID: ${r.id} • Branch: ${r.branchId}', style: const TextStyle(fontSize: 13, color: AppColors.slate400)),
                                      ]),
                                    ),
                                    const Icon(LucideIcons.arrowRight, color: AppColors.slate400),
                                  ]),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Choisir une caisse "Occupée" ne l\'ouvrira pas tant que la session en cours n\'est pas fermée par son titulaire.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ]),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 12,
            child: TextButton.icon(
              onPressed: () => ref.read(authProvider.notifier).logout(),
              icon: const Icon(LucideIcons.logOut, size: 16),
              label: Text('QUITTER${user == null ? '' : ' (${user.name})'}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1)),
            ),
          ),
        ]),
      ),
    );
  }
}
