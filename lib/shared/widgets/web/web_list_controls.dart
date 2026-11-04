import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/web_tokens.dart';

// ═══════════════════════════════════════════════════════════════════════════
// WebListTabs    — underlined tabs with optional count pills
// WebListToolbar — search on the left, filters / extra actions on the right
// WebSearchField — MUI-style outlined search box (debounced)
// ═══════════════════════════════════════════════════════════════════════════

class WebTab {
  const WebTab(this.label, {this.count, this.color});
  final String label;
  final int?   count;
  /// Pill colour when selected (defaults to navy).
  final Color? color;
}

class WebListTabs extends StatefulWidget {
  const WebListTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onChanged,
  });

  final List<WebTab>      tabs;
  final int               selected;
  final ValueChanged<int> onChanged;

  @override
  State<WebListTabs> createState() => _WebListTabsState();
}

class _WebListTabsState extends State<WebListTabs> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    height: 52,
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: WebColors.border)),
    ),
    // Mouse wheel scrolls the strip sideways on web
    child: Listener(
      onPointerSignal: (e) {
        if (e is PointerScrollEvent && _scroll.hasClients) {
          final max = _scroll.position.maxScrollExtent;
          _scroll.jumpTo((_scroll.offset + e.scrollDelta.dy).clamp(0.0, max));
        }
      },
      child: ListView.separated(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: WebSpace.xl),
        itemCount: widget.tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 32),
        itemBuilder: (_, i) => _TabItem(
          tab: widget.tabs[i],
          selected: i == widget.selected,
          onTap: () => widget.onChanged(i),
        ),
      ),
    ),
  );
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.tab, required this.selected,
    required this.onTap});
  final WebTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pillColor = tab.color ?? WebColors.navy;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(
              color: selected ? WebColors.navy : Colors.transparent,
              width: 2.5,
            )),
          ),
          alignment: Alignment.center,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(tab.label, style: TextStyle(
              fontSize: 13.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected ? WebColors.text1 : WebColors.text2,
            )),
            if (tab.count != null) ...[
              const SizedBox(width: 8),
              Container(
                height: 22,
                constraints: const BoxConstraints(minWidth: 24),
                padding: const EdgeInsets.symmetric(horizontal: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? pillColor : WebColors.divider,
                  borderRadius: BorderRadius.circular(WebRadius.label),
                ),
                child: Text('${tab.count}', style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : WebColors.text2,
                )),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

// ── Toolbar ───────────────────────────────────────────────────────────────
class WebListToolbar extends StatelessWidget {
  const WebListToolbar({
    super.key,
    this.search,
    this.leading = const [],
    this.trailing = const [],
    this.onFilters,
    this.filtersActive = false,
  });

  final Widget?       search;
  /// Extra controls placed after the search box (date pickers, dropdowns…).
  final List<Widget>  leading;
  /// Controls on the right, before the Filters button.
  final List<Widget>  trailing;
  final VoidCallback? onFilters;
  final bool          filtersActive;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Wrap(
      spacing: WebSpace.md,
      runSpacing: WebSpace.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Wrap(spacing: WebSpace.md, runSpacing: WebSpace.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [?search, ...leading]),
        Wrap(spacing: WebSpace.sm, runSpacing: WebSpace.sm,
            crossAxisAlignment: WrapCrossAlignment.center, children: [
              ...trailing,
              if (onFilters != null)
                WebFiltersButton(onTap: onFilters!, active: filtersActive),
            ]),
      ],
    ),
  );
}

class WebFiltersButton extends StatelessWidget {
  const WebFiltersButton({super.key, required this.onTap,
    this.active = false});
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onTap,
    style: TextButton.styleFrom(
      minimumSize: const Size(0, 44),
      foregroundColor: WebColors.text1,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WebRadius.button)),
    ),
    icon: Badge(
      isLabelVisible: active,
      smallSize: 8,
      backgroundColor: WebColors.error,
      child: const Icon(Icons.filter_list_rounded, size: 20),
    ),
    label: const Text('Filters', style: TextStyle(
        fontSize: 13.5, fontWeight: FontWeight.w700)),
  );
}

// ── Search field ──────────────────────────────────────────────────────────
class WebSearchField extends StatefulWidget {
  const WebSearchField({
    super.key,
    required this.onChanged,
    this.hint = 'Search…',
    this.width = 320,
    this.controller,
    this.debounce = const Duration(milliseconds: 500),
    this.searchOnSubmitOnly = false,
  });

  final ValueChanged<String> onChanged;
  final String  hint;
  final double  width;
  final TextEditingController? controller;
  final Duration debounce;
  final bool    searchOnSubmitOnly;

  @override
  State<WebSearchField> createState() => _WebSearchFieldState();
}

class _WebSearchFieldState extends State<WebSearchField> {
  late final TextEditingController _c =
      widget.controller ?? TextEditingController();
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _c.addListener(_rebuild);
  }

  void _rebuild() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    _t?.cancel();
    _c.removeListener(_rebuild);
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  void _changed(String v) {
    if (widget.searchOnSubmitOnly) return;
    _t?.cancel();
    _t = Timer(widget.debounce, () => widget.onChanged(v.trim()));
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.width,
    height: 48,
    child: TextField(
      controller: _c,
      onChanged: _changed,
      onSubmitted: (v) { _t?.cancel(); widget.onChanged(v.trim()); },
      style: const TextStyle(fontSize: 14, color: WebColors.text1),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: const TextStyle(fontSize: 14, color: WebColors.text3),
        prefixIcon: const Icon(Icons.search_rounded, size: 20,
            color: WebColors.text3),
        suffixIcon: _c.text.isEmpty ? null : IconButton(
          tooltip: 'Clear',
          icon: const Icon(Icons.close_rounded, size: 18,
              color: WebColors.text3),
          onPressed: () { _c.clear(); _t?.cancel(); widget.onChanged(''); },
        ),
        filled: true,
        fillColor: WebColors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WebRadius.sm),
          borderSide: const BorderSide(color: WebColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WebRadius.sm),
          borderSide: const BorderSide(color: WebColors.navy, width: 1.5),
        ),
      ),
    ),
  );
}

// ── Segmented toggle (date presets, granularity…) ─────────────────────────
class WebSegmented<T> extends StatelessWidget {
  const WebSegmented({
    super.key,
    required this.options,
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  final List<T> options;
  final T? selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: WebColors.divider,
      borderRadius: BorderRadius.circular(WebRadius.button),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      for (final o in options)
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => onChanged(o),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: o == selected ? WebColors.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(WebRadius.sm),
                boxShadow: o == selected ? WebShadow.card : null,
              ),
              child: Text(label(o), style: TextStyle(
                fontSize: 13,
                fontWeight: o == selected ? FontWeight.w700 : FontWeight.w600,
                color: o == selected ? WebColors.navy : WebColors.text2,
              )),
            ),
          ),
        ),
    ]),
  );
}
