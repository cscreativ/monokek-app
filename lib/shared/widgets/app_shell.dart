import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_controller.dart';
import '../../features/auth/lock_overlay.dart';
import '../../features/license/license_guard.dart';
import '../../features/pos/pos_providers.dart';

/// Wraps every screen except /setup: licence gate, then the PIN lock overlay on top.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(authProvider.select((a) => a.isAuthenticated ? a.user?.role : null));
    // Pre-load the menu in the background so opening a table doesn't wait on the network.
    if (role == 'waiter' || role == 'cashier') ref.read(productsProvider);

    final locked = ref.watch(lockProvider) && ref.watch(authProvider.select((a) => a.isAuthenticated));
    return LicenseGuard(
      child: Stack(children: [
        Positioned.fill(child: child),
        if (locked) const LockOverlay(),
      ]),
    );
  }
}
