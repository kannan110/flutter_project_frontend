import 'package:flutter/material.dart';
import 'package:rooster_trader/core/theme/app_theme.dart';

// ── FilterBar ─────────────────────────────────────────────────────────────
// Navy selected state, gold underline treatment
class FilterBar<T> extends StatelessWidget {
  const FilterBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.labelBuilder,
    this.countBuilder,
    this.padding,
  });

  final List<T>         options;
  final T               selected;
  final ValueChanged<T> onSelected;
  final String Function(T)? labelBuilder;
  final int? Function(T)?   countBuilder;
  final EdgeInsets?         padding;

  String _label(T v) => labelBuilder != null
      ? labelBuilder!(v)
      : v.toString().replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 52,
    child: ListView.separated(
      scrollDirection:  Axis.horizontal,
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 20),
      itemCount:        options.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (_, i) {
        final opt      = options[i];
        final isActive = opt == selected;
        final count    = countBuilder?.call(opt);
        return _FilterChip(
          label:    _label(opt),
          count:    count,
          isActive: isActive,
          onTap:    () => onSelected(opt),
        );
      },
    ),
  );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isActive,
    required this.onTap,
    this.count,
  });
  final String       label;
  final int?         count;
  final bool         isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isActive ? kNavy : kSurface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isActive ? kNavy : kBorder,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(
          label,
          style: TextStyle(
            fontSize:   13,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color:      isActive ? Colors.white : kTextSub,
          ),
        ),
        if (count != null && count! > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color:        isActive ? kGold : kNavy.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize:   10,
                fontWeight: FontWeight.w800,
                color:      isActive ? kNavy : kNavy,
              ),
            ),
          ),
        ],
      ]),
    ),
  );
}

// ── ActiveFiltersBar ───────────────────────────────────────────────────────
class ActiveFiltersBar extends StatelessWidget {
  const ActiveFiltersBar({
    super.key,
    required this.filters,
    required this.onRemove,
    this.onClearAll,
  });

  final Map<String, String> filters;
  final void Function(String) onRemove;
  final VoidCallback?         onClearAll;

  @override
  Widget build(BuildContext context) {
    if (filters.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(children: [
        const Text('Filters:',
            style: TextStyle(
                fontSize: 13, color: kTextSub, fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        ...filters.entries.map((e) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Chip(
            label: Text('${e.key}: ${e.value}',
                style: const TextStyle(fontSize: 13)),
            deleteIcon:      const Icon(Icons.close, size: 14),
            onDeleted:       () => onRemove(e.key),
            backgroundColor: kNavy.withValues(alpha: 0.06),
            side:            BorderSide(color: kNavy.withValues(alpha: 0.20)),
            labelStyle: const TextStyle(
                fontSize: 13, color: kTextMain, fontWeight: FontWeight.w600),
            deleteIconColor: kTextSub,
            visualDensity:   VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 6),
          ),
        )),
        if (onClearAll != null)
          TextButton(
            onPressed: onClearAll,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Clear all',
                style: TextStyle(fontSize: 13, color: kTextSub)),
          ),
      ]),
    );
  }
}