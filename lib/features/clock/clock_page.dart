import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/api/envelope.dart';
import '../../core/branch.dart';
import '../../core/theme/app_theme.dart';
import '../../data/staffing_api.dart';
import '../auth/auth_controller.dart';

/// Kiosk clock-in/out (port of pos/clock/page.tsx): a colleague types their own 4-digit PIN,
/// the server identifies them and the screen toggles between entry and exit.
class ClockPage extends ConsumerStatefulWidget {
  const ClockPage({super.key});
  @override
  ConsumerState<ClockPage> createState() => _ClockPageState();
}

class _ClockPageState extends ConsumerState<ClockPage> {
  String _pin = '';
  bool _busy = false;
  bool _loading = true;
  int? _branchId;
  List<TimeClockEntry> _present = const [];
  ({String name, bool entry})? _last;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final branch = await resolveBranchId(ref.read(apiClientProvider), ref.read(authProvider).user);
    if (!mounted) return;
    setState(() => _branchId = branch);
    if (branch != null) await _refresh(branch);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refresh(int branch) async {
    try {
      final list = await ref.read(staffingApiProvider).currentlyPresent(branch);
      if (mounted) setState(() => _present = list);
    } catch (_) {
      // The list is informational; a failed refresh must not block clocking.
    }
  }

  void _toast(String m, {bool error = false}) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? Theme.of(context).colorScheme.error : null));

  Future<void> _submit(String pin) async {
    final branch = _branchId;
    if (branch == null) {
      _toast('Succursale introuvable — vérifiez la configuration du poste.', error: true);
      setState(() => _pin = '');
      return;
    }
    setState(() => _busy = true);
    final api = ref.read(staffingApiProvider);
    try {
      final user = await api.lookupPin(branch, pin);
      if (_present.any((e) => e.userId == user.id)) {
        await api.clockOut(user.id, pin);
        if (mounted) {
          _toast('${user.name} : sortie enregistrée');
          setState(() => _last = (name: user.name, entry: false));
        }
      } else {
        await api.clockIn(user.id, branch, pin);
        if (mounted) {
          _toast('${user.name} : entrée enregistrée');
          setState(() => _last = (name: user.name, entry: true));
        }
      }
      await _refresh(branch);
    } catch (e) {
      if (mounted) _toast(errorMessage(e, 'Code PIN invalide'), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _pin = '';
          _busy = false;
        });
      }
    }
  }

  void _digit(String d) {
    if (_busy || _pin.length >= 4) return;
    final next = _pin + d;
    setState(() => _pin = next);
    if (next.length == 4) _submit(next);
  }

  void _delete() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final wide = MediaQuery.sizeOf(context).width >= 760;

    final pad = Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < 4; i++)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: i < _pin.length ? scheme.primary.withValues(alpha: 0.1) : null,
              border: Border.all(color: i < _pin.length ? scheme.primary : scheme.outline, width: 2),
            ),
            child: Text(i < _pin.length ? '•' : '', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: scheme.primary)),
          ),
        if (_busy) const Padding(padding: EdgeInsets.only(left: 8), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))),
      ]),
      const SizedBox(height: 28),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 1.5,
          children: [
            for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9'])
              OutlinedButton(
                onPressed: _busy ? null : () => _digit(d),
                style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), side: BorderSide(color: scheme.outline)),
                child: Text(d, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              ),
            const SizedBox.shrink(),
            OutlinedButton(
              onPressed: _busy ? null : () => _digit('0'),
              style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), side: BorderSide(color: scheme.outline)),
              child: const Text('0', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            ),
            OutlinedButton(
              onPressed: (_busy || _pin.isEmpty) ? null : _delete,
              style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), side: BorderSide(color: scheme.outline)),
              child: const Icon(LucideIcons.delete, size: 20),
            ),
          ],
        ),
      ),
      if (_last != null) ...[
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: _last!.entry ? const Color(0xFFD1FAE5) : const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_last!.entry ? LucideIcons.logIn : LucideIcons.logOut, size: 16, color: _last!.entry ? const Color(0xFF065F46) : const Color(0xFF92400E)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '${_last!.name} ${_last!.entry ? 'a pointé son entrée' : 'a pointé sa sortie'}'.toUpperCase(),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: _last!.entry ? const Color(0xFF065F46) : const Color(0xFF92400E)),
              ),
            ),
          ]),
        ),
      ],
    ]);

    final presentList = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        '${_present.length} EMPLOYÉ${_present.length > 1 ? 'S' : ''} PRÉSENT${_present.length > 1 ? 'S' : ''}',
        style: microLabelStyle.copyWith(color: AppColors.slate400, letterSpacing: 1.5),
      ),
      const SizedBox(height: 16),
      if (_present.isEmpty && !_loading)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 40),
          decoration: BoxDecoration(border: Border.all(color: scheme.outline, width: 2), borderRadius: BorderRadius.circular(16)),
          child: const Text("Aucun employé n'est actuellement pointé", textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.slate400)),
        )
      else
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (final e in _present)
            Container(
              width: 220,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: dark ? AppColors.slate900 : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outline),
              ),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(LucideIcons.circleUser, size: 22, color: Color(0xFF059669)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.userName ?? '#${e.userId}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    Text(
                      'depuis ${e.clockInAt == null ? '--:--' : DateFormat('HH:mm').format(e.clockInAt!)}',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppColors.slate400),
                    ),
                  ]),
                ),
              ]),
            ),
        ]),
    ]);

    return Scaffold(
      backgroundColor: dark ? AppColors.slate950 : AppColors.slate50,
      body: SafeArea(
        // Physical / on-screen keyboards can type the PIN too.
        child: KeyboardListener(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: (e) {
            if (e is! KeyDownEvent) return;
            final ch = e.character;
            if (ch != null && RegExp(r'^[0-9]$').hasMatch(ch)) {
              _digit(ch);
            } else if (e.logicalKey == LogicalKeyboardKey.backspace) {
              _delete();
            }
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    IconButton.filled(
                      onPressed: () => context.canPop() ? context.pop() : context.go('/'),
                      icon: const Icon(LucideIcons.arrowLeft, size: 20),
                      style: IconButton.styleFrom(backgroundColor: dark ? AppColors.slate900 : Colors.white, foregroundColor: scheme.onSurface),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('POINTAGE', style: titleStyle.copyWith(fontSize: 24)),
                        Text('ENTREZ VOTRE CODE PIN À 4 CHIFFRES', style: microLabelStyle.copyWith(color: AppColors.slate400, fontSize: 10, letterSpacing: 1.5)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 32),
                  if (wide)
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: Center(child: pad)),
                      const SizedBox(width: 40),
                      Expanded(child: presentList),
                    ])
                  else ...[
                    Center(child: pad),
                    const SizedBox(height: 32),
                    presentList,
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
