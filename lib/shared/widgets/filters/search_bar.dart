import 'package:flutter/material.dart';
import 'package:rooster_trader/core/theme/app_theme.dart';

// ── AppSearchBar (shared) ─────────────────────────────────────────────────
// White bg, navy focus border, 48px height — enterprise feel
class AppSearchBar extends StatelessWidget {
  const AppSearchBar({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.onClear,
    this.autofocus   = false,
    this.height      = 48,
    this.onSubmitted,
  });

  final TextEditingController  controller;
  final String                 hint;
  final void Function(String)? onChanged;
  final VoidCallback?          onClear;
  final bool                   autofocus;
  final double                 height;
  final void Function(String)? onSubmitted;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, __) => Container(
      height: height,
      decoration: BoxDecoration(
        color:        kSurface,
        borderRadius: BorderRadius.circular(4),
        border:       Border.all(color: kBorder),
      ),
      child: TextField(
        controller:  controller,
        onChanged:   onChanged,
        onSubmitted: onSubmitted,
        autofocus:   autofocus,
        style: const TextStyle(
            fontSize: 15, color: kTextMain, fontWeight: FontWeight.w400),
        decoration: InputDecoration(
          hintText:  hint,
          hintStyle: const TextStyle(color: kTextHint, fontSize: 15),
          prefixIcon: const Icon(
              Icons.search_rounded, color: kTextHint, size: 20),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
            icon: const Icon(
                Icons.close_rounded, size: 16, color: kTextHint),
            onPressed: onClear ?? () {
              controller.clear();
              onChanged?.call('');
            },
            padding:       EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          )
              : null,
          border:         InputBorder.none,
          enabledBorder:  InputBorder.none,
          focusedBorder:  InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          isDense:        false,
        ),
      ),
    ),
  );
}

// ── ListToolbar ────────────────────────────────────────────────────────────
// 48px height inputs, navy primary button, enterprise-grade toolbar
class ListToolbar extends StatelessWidget {
  const ListToolbar({
    super.key,
    required this.searchController,
    required this.searchHint,
    this.onSearch,
    this.onClearSearch,
    this.primaryLabel,
    this.primaryIcon,
    this.onPrimary,
    this.onFilter,
    this.secondaryActions,
    this.padding,
  });

  final TextEditingController  searchController;
  final String                 searchHint;
  final void Function(String)? onSearch;
  final VoidCallback?          onClearSearch;
  final String?                primaryLabel;
  final IconData?              primaryIcon;
  final VoidCallback?          onPrimary;
  final VoidCallback?          onFilter;
  final List<Widget>?          secondaryActions;
  final EdgeInsets?            padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding ?? const EdgeInsets.fromLTRB(20, 16, 20, 12),
    child: Row(children: [
      // Search
      Expanded(
        child: AppSearchBar(
          controller: searchController,
          hint:       searchHint,
          onChanged:  onSearch,
          onClear:    onClearSearch,
        ),
      ),

      // Filter
      if (onFilter != null) ...[
        const SizedBox(width: 10),
        _ToolbarButton(
          label: 'Filter',
          icon:  Icons.tune_rounded,
          onTap: onFilter!,
        ),
      ],

      // Secondary
      if (secondaryActions != null)
        ...secondaryActions!.map((w) =>
            Padding(padding: const EdgeInsets.only(left: 10), child: w)),

      // Primary
      if (onPrimary != null) ...[
        const SizedBox(width: 10),
        _PrimaryButton(
          label: primaryLabel ?? 'New',
          icon:  primaryIcon ?? Icons.add_rounded,
          onTap: onPrimary!,
        ),
      ],
    ]),
  );
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String       label;
  final IconData     icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap:        onTap,
    borderRadius: BorderRadius.circular(4),
    child: Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color:        kSurface,
        borderRadius: BorderRadius.circular(4),
        border:       Border.all(color: kBorder),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: kTextSub),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                fontSize:   14,
                fontWeight: FontWeight.w600,
                color:      kTextSub)),
      ]),
    ),
  );
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String       label;
  final IconData     icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap:        onTap,
    borderRadius: BorderRadius.circular(4),
    child: Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color:        kNavy,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: kGoldLight),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(
                fontSize:   14,
                fontWeight: FontWeight.w700,
                color:      Colors.white)),
      ]),
    ),
  );
}