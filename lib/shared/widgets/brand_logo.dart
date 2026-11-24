import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';

/// The MonoKek logo (chef-hat "M" + wordmark) with an optional subtitle underneath.
/// The artwork has dark lettering, so on the dark theme it sits on a light rounded plate.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.subtitle, this.height = 150});
  final String? subtitle;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    Widget logo = Image.asset(
      'assets/images/logo.png',
      height: height,
      fit: BoxFit.contain,
      semanticLabel: 'MonoKek',
      // Never block the sign-in screen on a missing asset.
      errorBuilder: (_, _, _) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(LucideIcons.store, size: height * 0.4, color: scheme.primary),
        const SizedBox(width: 8),
        Text('MONOKEK', style: titleStyle.copyWith(fontSize: height * 0.25)),
      ]),
    );
    if (dark) {
      logo = Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: logo,
      );
    }

    return Column(mainAxisSize: MainAxisSize.min, children: [
      logo,
      if (subtitle != null) ...[
        const SizedBox(height: 12),
        Text(subtitle!.toUpperCase(), style: microLabelStyle.copyWith(color: scheme.onSurfaceVariant, fontSize: 11)),
      ],
    ]);
  }
}
