import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'shimmer.dart';
import 'skeleton_elements.dart';

/// Which kind of content a skeleton column should render.
enum SkeletonColumnHint {
  /// Leading circle (avatar) + text line.
  avatarAndText,

  /// Single text line.
  text,

  /// Short pill / badge.
  badge,

  /// Small button outline.
  smallButton,
}

/// A skeleton that mirrors [LumaDataTable]'s visual layout:
/// header row, N data rows, optional pagination footer.
class SkeletonTable extends StatelessWidget {
  final List<SkeletonColumnHint> columnHints;

  /// Mirrors [LumaDataTable] fixed-width columns; null = expanded.
  final List<double?> columnWidths;
  final int rowCount;
  final bool showCheckboxes;
  final bool showPagination;

  const SkeletonTable({
    super.key,
    required this.columnHints,
    this.columnWidths = const [],
    this.rowCount = 8,
    this.showCheckboxes = false,
    this.showPagination = true,
  });

  double? _width(int i) =>
      i < columnWidths.length ? columnWidths[i] : null;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Shimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row — matches LumaDataTable header padding
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              border: Border(
                bottom: BorderSide(color: cs.outlineVariant.withAlpha(128)),
              ),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                if (showCheckboxes) ...[
                  const SizedBox(width: 40),
                  const SizedBox(width: 8),
                ],
                ...List.generate(columnHints.length, (i) {
                  final w = _width(i);
                  final labelW =
                      w != null ? math.min(w * 0.5, 80.0) : 80.0;
                  final cell = SkeletonLine(width: labelW, height: 10);
                  if (w != null) return SizedBox(width: w, child: cell);
                  return Expanded(child: cell);
                }),
              ],
            ),
          ),

          // Data rows
          ...List.generate(
            rowCount,
            (i) => _SkeletonRow(
              columnHints: columnHints,
              columnWidths: columnWidths,
              showCheckboxes: showCheckboxes,
              seed: i,
            ),
          ),

          // Pagination footer — matches LumaPagination
          if (showPagination)
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: cs.outlineVariant)),
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12),
              child: const Row(
                children: [
                  SkeletonBox(width: 90, height: 32),
                  Spacer(),
                  SkeletonBox(width: 160, height: 32),
                  Spacer(),
                  SkeletonBox(width: 68, height: 32),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  final List<SkeletonColumnHint> columnHints;
  final List<double?> columnWidths;
  final bool showCheckboxes;
  final int seed;

  const _SkeletonRow({
    required this.columnHints,
    required this.columnWidths,
    required this.showCheckboxes,
    required this.seed,
  });

  double? _width(int i) =>
      i < columnWidths.length ? columnWidths[i] : null;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rng = math.Random(seed * 31 + 7);

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withAlpha(80)),
        ),
      ),
      // Matches LumaDataTable row padding
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showCheckboxes) ...[
            const SizedBox(width: 40),
            const SizedBox(width: 8),
          ],
          ...List.generate(columnHints.length, (i) {
            final hint = columnHints[i];
            final w = _width(i);
            Widget cell;
            switch (hint) {
              case SkeletonColumnHint.avatarAndText:
                cell = Row(
                  children: [
                    const SkeletonCircle(size: 28),
                    const SizedBox(width: 10),
                    SkeletonLine(
                      width: 80 + rng.nextInt(60).toDouble(),
                    ),
                  ],
                );
              case SkeletonColumnHint.text:
                cell = SkeletonLine(
                  width: 60 + rng.nextInt(80).toDouble(),
                );
              case SkeletonColumnHint.badge:
                cell = SkeletonBox(
                  width: 48 + rng.nextInt(32).toDouble(),
                  height: 20,
                );
              case SkeletonColumnHint.smallButton:
                cell = const SkeletonBox(width: 80, height: 28);
            }
            final aligned = Align(
              alignment: Alignment.centerLeft,
              child: cell,
            );
            if (w != null) return SizedBox(width: w, child: aligned);
            return Expanded(child: aligned);
          }),
        ],
      ),
    );
  }
}
