import 'package:flutter/material.dart';

/// Sweeping shimmer animation wrapping its [child].
///
/// Uses [AnimationController] + [ShaderMask] with [BlendMode.srcATop] so
/// it adapts to any child shape (text boxes, circles, etc.).  Colors are
/// derived from the active [ColorScheme] so it adapts to light/dark mode.
class Shimmer extends StatefulWidget {
  final Widget child;

  const Shimmer({super.key, required this.child});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final base = cs.surfaceContainerHighest;
    // Highlight is always slightly brighter than base regardless of mode.
    final highlight = Color.lerp(
      base,
      Colors.white,
      brightness == Brightness.dark ? 0.12 : 0.30,
    )!;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        final dx = _ctrl.value * 2 - 0.5;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(dx - 1, 0),
            end: Alignment(dx + 1, 0),
            colors: [base, highlight, base],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(bounds),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
