import 'package:flutter/material.dart';


/// Column definition for [LumaDataTable].
class LumaColumn<T> {
  final String label;

  /// Fixed width. When null the column expands to fill remaining space.
  final double? width;

  final Widget Function(T row, int index) cellBuilder;

  const LumaColumn({
    required this.label,
    this.width,
    required this.cellBuilder,
  });
}

/// Untitled UI-style data table with optional checkbox multi-selection.
class LumaDataTable<T> extends StatelessWidget {
  final List<LumaColumn<T>> columns;
  final List<T> rows;

  /// Indices of currently selected rows.
  final Set<int> selected;

  /// Called when the selection changes. Pass null to hide checkboxes.
  final void Function(Set<int> selected)? onSelectionChanged;

  /// Called when a row is tapped (outside the checkbox area).
  final void Function(T row)? onRowTap;

  /// Widget shown above the table when at least one row is selected.
  final Widget Function(Set<int> selected)? bulkActionBar;

  /// Whether to show the checkbox column.
  final bool showCheckboxes;

  /// Optional predicate to disable selection on specific rows.
  final bool Function(T row, int index)? canSelect;

  const LumaDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.selected = const {},
    this.onSelectionChanged,
    this.onRowTap,
    this.bulkActionBar,
    this.showCheckboxes = false,
    this.canSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.labelSmall?.copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    );

    // Determine which rows are selectable.
    final selectableIndices = <int>{};
    if (showCheckboxes) {
      for (int i = 0; i < rows.length; i++) {
        if (canSelect == null || canSelect!(rows[i], i)) {
          selectableIndices.add(i);
        }
      }
    }

    final allSelected = selectableIndices.isNotEmpty &&
        selectableIndices.every(selected.contains);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Bulk action bar
        if (selected.isNotEmpty && bulkActionBar != null)
          bulkActionBar!(selected),

        // Header
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            border: Border(
              bottom: BorderSide(color: cs.outlineVariant.withAlpha(128)),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              if (showCheckboxes) ...[
                SizedBox(
                  width: 40,
                  child: Checkbox(
                    value: allSelected && selectableIndices.isNotEmpty,
                    tristate: true,
                    onChanged: onSelectionChanged == null
                        ? null
                        : (_) {
                            if (allSelected) {
                              onSelectionChanged!({});
                            } else {
                              onSelectionChanged!(Set.of(selectableIndices));
                            }
                          },
                  ),
                ),
                const SizedBox(width: 8),
              ],
              ...columns.map((col) {
                final child = Text(col.label, style: headerStyle);
                if (col.width != null) {
                  return SizedBox(width: col.width, child: child);
                }
                return Expanded(child: child);
              }),
            ],
          ),
        ),

        // Rows
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final row = rows[i];
              final isSelected = selected.contains(i);
              final selectable =
                  showCheckboxes && selectableIndices.contains(i);

              return _DataRow<T>(
                columns: columns,
                row: row,
                index: i,
                isSelected: isSelected,
                showCheckbox: showCheckboxes,
                selectable: selectable,
                onCheckChanged: onSelectionChanged == null
                    ? null
                    : (checked) {
                        final next = Set<int>.of(selected);
                        if (checked) {
                          next.add(i);
                        } else {
                          next.remove(i);
                        }
                        onSelectionChanged!(next);
                      },
                onTap: onRowTap == null ? null : () => onRowTap!(row),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DataRow<T> extends StatefulWidget {
  final List<LumaColumn<T>> columns;
  final T row;
  final int index;
  final bool isSelected;
  final bool showCheckbox;
  final bool selectable;
  final void Function(bool checked)? onCheckChanged;
  final VoidCallback? onTap;

  const _DataRow({
    required this.columns,
    required this.row,
    required this.index,
    required this.isSelected,
    required this.showCheckbox,
    required this.selectable,
    this.onCheckChanged,
    this.onTap,
  });

  @override
  State<_DataRow<T>> createState() => _DataRowState<T>();
}

class _DataRowState<T> extends State<_DataRow<T>> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Color? bg;
    if (widget.isSelected) {
      bg = cs.primaryContainer.withAlpha(40);
    } else if (_hovered) {
      bg = cs.surfaceContainerHighest.withAlpha(80);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            border: Border(
              bottom: BorderSide(
                color: cs.outlineVariant.withAlpha(80),
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              if (widget.showCheckbox) ...[
                SizedBox(
                  width: 40,
                  child: widget.selectable
                      ? Checkbox(
                          value: widget.isSelected,
                          onChanged: (v) =>
                              widget.onCheckChanged?.call(v ?? false),
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(width: 8),
              ],
              ...widget.columns.map((col) {
                final child = col.cellBuilder(widget.row, widget.index);
                if (col.width != null) {
                  return SizedBox(width: col.width, child: child);
                }
                return Expanded(child: child);
              }),
            ],
          ),
        ),
      ),
    );
  }
}
