import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/roles.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/num_pad.dart';
import 'auth_controller.dart';

/// Screen-lock flag (port of useUIStore.isLocked). Always cleared when the session ends.
final lockProvider = NotifierProvider<LockController, bool>(LockController.new);

class LockController extends Notifier<bool> {
  @override
  bool build() {
    ref.listen(authProvider, (_, next) {
      if (!next.isAuthenticated) state = false;
    });
    return false;
  }

  void lock() => state = true;
  void unlock() => state = false;
}

/// Full-screen PIN overlay: 4 digits verified server-side via POST /api/auth/verify-pin.
class LockOverlay extends ConsumerStatefulWidget {
  const LockOverlay({super.key});
  @override
  ConsumerState<LockOverlay> createState() => _LockOverlayState();
}

class _LockOverlayState extends ConsumerState<LockOverlay> with SingleTickerProviderStateMixin {
  String _pin = '';
  bool _error = false;
  bool _loading = false;
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  Future<void> _onKey(String key) async {
    if (_loading) return;
    setState(() => _error = false);
    if (key == 'C') return setState(() => _pin = '');
    if (key == 'del') return setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1));
    if (_pin.length >= 4) return;
    setState(() => _pin += key);
    if (_pin.length < 4) return;

    setState(() => _loading = true);
    try {
      await ref.read(apiClientProvider).post('/api/auth/verify-pin', data: {'pin': _pin});
      if (!mounted) return;
      ref.read(lockProvider.notifier).unlock();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _pin = '';
      });
      _shake.forward(from: 0);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = ref.watch(authProvider).user;
    final roleTheme = roleThemes[user?.role];

    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Material(
          color: scheme.surface.withValues(alpha: 0.95),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 96,
                    height: 96,
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [Color(0xFF171717), Color(0xFF7C3AED)], begin: Alignment.bottomLeft, end: Alignment.topRight),
                    ),
                    child: Container(
                      decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.surface),
                      alignment: Alignment.center,
                      child: _loading
                          ? const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 3))
                          : Text(
                              (user?.name.isNotEmpty ?? false) ? user!.name.characters.first.toUpperCase() : '?',
                              style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: scheme.primary),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text((user?.name ?? '').toUpperCase(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                  const SizedBox(height: 2),
                  Text(
                    (roleTheme?.label ?? user?.role ?? '').toUpperCase(),
                    style: microLabelStyle.copyWith(color: scheme.onSurfaceVariant, fontSize: 11),
                  ),
                  const SizedBox(height: 24),
                  AnimatedBuilder(
                    animation: _shake,
                    builder: (_, child) => Transform.translate(offset: Offset(_error ? (1 - _shake.value) * 10 * (_shake.value * 40 % 2 < 1 ? 1 : -1) : 0, 0), child: child),
                    child: PinDots(length: _pin.length, error: _error),
                  ),
                  const SizedBox(height: 24),
                  NumPad(onKey: _onKey, enabled: !_loading),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : () => ref.read(authProvider.notifier).logout(),
                      icon: const Icon(LucideIcons.logOut, size: 16),
                      label: const Text('CHANGER DE SESSION', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
