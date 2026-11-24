import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 3x4 PIN pad. Emits '0'-'9', 'C' (clear) and 'del'.
class NumPad extends StatelessWidget {
  const NumPad({super.key, required this.onKey, this.enabled = true});
  final void Function(String key) onKey;
  final bool enabled;

  static const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'C', '0', 'del'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.45,
        children: [
          for (final k in keys)
            TextButton(
              onPressed: enabled ? () => onKey(k) : null,
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                foregroundColor: (k == 'C' || k == 'del') ? scheme.onSurfaceVariant : scheme.onSurface,
                textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              child: k == 'del' ? const Icon(LucideIcons.delete) : Text(k),
            ),
        ],
      ),
    );
  }
}

/// Row of 4 dots: filled as digits are typed, red + shake on error.
class PinDots extends StatelessWidget {
  const PinDots({super.key, required this.length, this.error = false, this.total = 4});
  final int length;
  final bool error;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < total; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 8),
            width: 16,
            height: 16,
            transform: Matrix4.diagonal3Values(length > i ? 1.25 : 1, length > i ? 1.25 : 1, 1),
            transformAlignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: error ? scheme.error : (length > i ? scheme.primary : Colors.transparent),
              border: error ? null : Border.all(color: length > i ? scheme.primary : scheme.onSurfaceVariant.withValues(alpha: 0.3), width: 2),
              boxShadow: error ? [BoxShadow(color: scheme.error.withValues(alpha: 0.5), blurRadius: 10)] : null,
            ),
          ),
      ],
    );
  }
}
