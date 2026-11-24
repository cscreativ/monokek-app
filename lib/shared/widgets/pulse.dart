import 'package:flutter/material.dart';

/// Tailwind `animate-pulse` equivalent (opacity 1 → 0.5 → 1).
class Pulse extends StatefulWidget {
  const Pulse({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;
  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return FadeTransition(opacity: Tween(begin: 1.0, end: 0.55).animate(_c), child: widget.child);
  }
}
