import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/roles.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_controller.dart';

/// Temporary landing screen for each role until its feature module (Phases 2–4) replaces it.
class RoleHomePage extends ConsumerWidget {
  const RoleHomePage({super.key, required this.title, required this.phase});
  final String title;
  final String phase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final theme = roleThemes[user?.role];
    final accent = theme?.color ?? Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        title: Text(title.toUpperCase(), style: titleStyle),
        actions: [
          IconButton(
            tooltip: 'Déconnexion',
            icon: const Icon(LucideIcons.logOut),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(999), border: Border.all(color: accent)),
            child: Text((theme?.label ?? user?.role ?? '').toUpperCase(), style: microLabelStyle.copyWith(color: accent)),
          ),
          const SizedBox(height: 16),
          Text(user?.name ?? '', style: titleStyle.copyWith(fontSize: 28)),
          const SizedBox(height: 8),
          Text('Module disponible en $phase', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

/// Admin / manager accounts: the back-office lives in the Tauri app.
class UnsupportedRolePage extends ConsumerWidget {
  const UnsupportedRolePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(LucideIcons.monitor, size: 56),
              const SizedBox(height: 16),
              Text('ESPACE ADMINISTRATION', style: titleStyle.copyWith(fontSize: 22)),
              const SizedBox(height: 8),
              const Text("L'administration se fait depuis l'application desktop MonoKek.", textAlign: TextAlign.center),
              const SizedBox(height: 24),
              SizedBox(
                width: 240,
                child: FilledButton(onPressed: () => ref.read(authProvider.notifier).logout(), child: const Text('SE DÉCONNECTER')),
              ),
            ]),
          ),
        ),
      );
}
