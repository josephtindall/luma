import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// Skeleton placeholder rectangle (rounded pill).
class SkeletonLine extends StatelessWidget {
  final double? width;
  final double height;

  const SkeletonLine({super.key, this.width, this.height = 12});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: LumaRadius.radiusXs,
      ),
    );
  }
}

/// Skeleton placeholder circle.
class SkeletonCircle extends StatelessWidget {
  final double size;

  const SkeletonCircle({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Skeleton placeholder rounded rectangle.
class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;

  const SkeletonBox({super.key, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: LumaRadius.radiusMd,
      ),
    );
  }
}
