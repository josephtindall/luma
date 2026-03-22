import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Untitled UI-style pagination with Previous, numbered pages, and Next.
///
/// [currentPage] is 0-indexed. Always visible; buttons are disabled when
/// there is only one page.
class LumaPagination extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final void Function(int page) onPageChanged;

  const LumaPagination({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
  });

  /// Compute which page numbers to show (1-indexed for display).
  /// Returns a list of ints (page numbers) and nulls (ellipsis).
  List<int?> _visiblePages() {
    if (totalPages <= 7) {
      return List.generate(totalPages, (i) => i);
    }

    final pages = <int?>[];
    // Always show first page.
    pages.add(0);

    if (currentPage <= 3) {
      // Near start: 0,1,2,3,4,…,last
      for (int i = 1; i <= 4; i++) {
        pages.add(i);
      }
      pages.add(null); // ellipsis
      pages.add(totalPages - 1);
    } else if (currentPage >= totalPages - 4) {
      // Near end: 0,…,n-5,n-4,n-3,n-2,n-1
      pages.add(null);
      for (int i = totalPages - 5; i < totalPages; i++) {
        pages.add(i);
      }
    } else {
      // Middle: 0,…,p-1,p,p+1,…,last
      pages.add(null);
      pages.add(currentPage - 1);
      pages.add(currentPage);
      pages.add(currentPage + 1);
      pages.add(null);
      pages.add(totalPages - 1);
    }

    return pages;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canPrev = currentPage > 0;
    final canNext = currentPage < totalPages - 1;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Previous
        OutlinedButton.icon(
          onPressed: canPrev ? () => onPageChanged(currentPage - 1) : null,
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text('Previous'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape:
                const RoundedRectangleBorder(borderRadius: LumaRadius.radiusMd),
          ),
        ),

        const SizedBox(width: 4),

        // Page numbers
        ..._visiblePages().map((page) {
          if (page == null) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: SizedBox(
                width: 36,
                height: 36,
                child: Center(
                  child: Text('…',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ),
              ),
            );
          }

          final isActive = page == currentPage;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: SizedBox(
              width: 36,
              height: 36,
              child: isActive
                  ? FilledButton(
                      onPressed: null,
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: const RoundedRectangleBorder(
                            borderRadius: LumaRadius.radiusMd),
                      ),
                      child: Text('${page + 1}'),
                    )
                  : TextButton(
                      onPressed: totalPages > 1
                          ? () => onPageChanged(page)
                          : null,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: const RoundedRectangleBorder(
                            borderRadius: LumaRadius.radiusMd),
                      ),
                      child: Text('${page + 1}'),
                    ),
            ),
          );
        }),

        const SizedBox(width: 4),

        // Next
        OutlinedButton.icon(
          onPressed: canNext ? () => onPageChanged(currentPage + 1) : null,
          icon: const Icon(Icons.arrow_forward, size: 16),
          label: const Text('Next'),
          iconAlignment: IconAlignment.end,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape:
                const RoundedRectangleBorder(borderRadius: LumaRadius.radiusMd),
          ),
        ),
      ],
    );
  }
}
