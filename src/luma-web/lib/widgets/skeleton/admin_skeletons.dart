import 'package:flutter/material.dart';

import 'shimmer.dart';
import 'skeleton_elements.dart';
import 'skeleton_table.dart';

// ── Shared header skeleton ────────────────────────────────────────────────────

class _SkeletonScreenHeader extends StatelessWidget {
  final int buttonCount;

  const _SkeletonScreenHeader({this.buttonCount = 1});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonLine(width: 120, height: 14),
                  SizedBox(height: 6),
                  SkeletonLine(width: 240, height: 10),
                ],
              ),
            ),
            for (int i = 0; i < buttonCount - 1; i++) ...[
              const SkeletonBox(width: 90, height: 32),
              const SizedBox(width: 8),
            ],
            if (buttonCount > 0) const SkeletonBox(width: 100, height: 32),
          ],
        ),
      ),
    );
  }
}

// ── Per-screen skeletons ──────────────────────────────────────────────────────

class UsersScreenSkeleton extends StatelessWidget {
  const UsersScreenSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SkeletonScreenHeader(buttonCount: 3),
        Expanded(
          child: SkeletonTable(
            columnHints: const [
              SkeletonColumnHint.avatarAndText,
              SkeletonColumnHint.text,
              SkeletonColumnHint.badge,
              SkeletonColumnHint.smallButton,
            ],
            columnWidths: const [null, null, 200, 100],
            showCheckboxes: true,
            rowCount: 10,
          ),
        ),
      ],
    );
  }
}

class GroupsScreenSkeleton extends StatelessWidget {
  const GroupsScreenSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SkeletonScreenHeader(),
        Expanded(
          child: SkeletonTable(
            columnHints: const [
              SkeletonColumnHint.text,
              SkeletonColumnHint.text,
              SkeletonColumnHint.text,
              SkeletonColumnHint.smallButton,
            ],
            columnWidths: const [null, 120, 100, 100],
            showCheckboxes: true,
            rowCount: 8,
          ),
        ),
      ],
    );
  }
}

class RolesScreenSkeleton extends StatelessWidget {
  const RolesScreenSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SkeletonScreenHeader(),
        Expanded(
          child: SkeletonTable(
            columnHints: const [
              SkeletonColumnHint.text,
              SkeletonColumnHint.badge,
              SkeletonColumnHint.text,
              SkeletonColumnHint.text,
              SkeletonColumnHint.smallButton,
            ],
            columnWidths: const [null, 110, 120, 100, 120],
            showCheckboxes: true,
            rowCount: 8,
          ),
        ),
      ],
    );
  }
}

class VaultsScreenSkeleton extends StatelessWidget {
  const VaultsScreenSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SkeletonScreenHeader(),
        Expanded(
          child: SkeletonTable(
            columnHints: const [
              SkeletonColumnHint.text,
              SkeletonColumnHint.text,
              SkeletonColumnHint.badge,
              SkeletonColumnHint.text,
              SkeletonColumnHint.smallButton,
            ],
            columnWidths: const [null, 160, 120, 120, 100],
            rowCount: 8,
          ),
        ),
      ],
    );
  }
}

class EventsScreenSkeleton extends StatelessWidget {
  const EventsScreenSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Shimmer(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Row(
              children: const [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonLine(width: 80, height: 14),
                      SizedBox(height: 6),
                      SkeletonLine(width: 220, height: 10),
                    ],
                  ),
                ),
                SkeletonBox(width: 110, height: 32),
              ],
            ),
          ),
        ),
        // Filter bar
        Shimmer(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: const [
                SkeletonBox(width: 260, height: 36),
                SkeletonBox(width: 220, height: 36),
                SkeletonBox(width: 130, height: 36),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Divider(height: 1),
        // Event rows
        Expanded(
          child: Shimmer(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: 10,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 56),
              itemBuilder: (_, __) => const _SkeletonEventRow(),
            ),
          ),
        ),
        // Pagination footer
        Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: cs.outlineVariant)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
    );
  }
}

class _SkeletonEventRow extends StatelessWidget {
  const _SkeletonEventRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      // horizontal: 24 matches the corrected _EventRow padding
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Padding(
            padding: EdgeInsets.only(top: 2, right: 12),
            child: SkeletonCircle(size: 20),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(height: 12),
                SizedBox(height: 4),
                SkeletonLine(width: 180, height: 10),
              ],
            ),
          ),
          SizedBox(width: 8),
          SkeletonLine(width: 70, height: 10),
        ],
      ),
    );
  }
}
