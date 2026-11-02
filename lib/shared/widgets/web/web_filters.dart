import 'package:flutter/material.dart';
import '../../../core/theme/web_tokens.dart';

// ═══════════════════════════════════════════════════════════════════════════
// showWebFiltersDrawer — right-side panel; values apply only on "Filter".
// WebFilterSection     — bold title above a field.
// WebFiltersResult     — "N results found" + removable chips + Clear.
// ═══════════════════════════════════════════════════════════════════════════

Future<void> showWebFiltersDrawer(
  BuildContext context, {
  String title = 'Filters',
  required WidgetBuilder builder,
  required VoidCallback onApply,
  VoidCallback? onReset,
  bool hasActive = false,
  bool Function()? canApply,
}) => showGeneralDialog(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Filters',
  barrierColor: Colors.transparent,
  transitionDuration: const Duration(milliseconds: 250),
  pageBuilder: (ctx, _, __) => Align(
    alignment: Alignment.centerRight,
    child: _FiltersPanel(
      title: title, builder: builder, onApply: onApply,
      onReset: onReset, hasActive: hasActive, canApply: canApply,
    ),
  ),
  transitionBuilder: (_, anim, __, child) => SlideTransition(
    position: Tween(begin: const Offset(1, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
    child: child,
  ),
);

class _FiltersPanel extends StatefulWidget {
  const _FiltersPanel({required this.title, required this.builder,
    required this.onApply, this.onReset, required this.hasActive,
    this.canApply});
  final String title;
  final WidgetBuilder builder;
  final VoidCallback onApply;
  final VoidCallback? onReset;
  final bool hasActive;
  final bool Function()? canApply;

  @override
  State<_FiltersPanel> createState() => _FiltersPanelState();
}

class _FiltersPanelState extends State<_FiltersPanel> {
  @override
  Widget build(BuildContext context) {
    final enabled = widget.canApply?.call() ?? true;
    return Material(
      color: WebColors.surface,
      elevation: 0,
      child: Container(
        width: WebSize.filtersDrawer,
        height: double.infinity,
        decoration: const BoxDecoration(boxShadow: WebShadow.drawer),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
            child: Row(children: [
              Expanded(child: Text(widget.title, style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800,
                  color: WebColors.text1))),
              if (widget.onReset != null)
                IconButton(
                  tooltip: 'Reset',
                  onPressed: () { widget.onReset!(); setState(() {}); },
                  icon: Badge(
                    isLabelVisible: widget.hasActive,
                    smallSize: 8,
                    backgroundColor: WebColors.error,
                    child: const Icon(Icons.restart_alt_rounded, size: 20),
                  ),
                ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ]),
          ),
          const Divider(height: 1, color: WebColors.border),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: StatefulBuilder(builder: (ctx, _) => widget.builder(ctx)),
          )),
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(height: 48, child: FilledButton(
              onPressed: enabled ? () {
                widget.onApply();
                Navigator.of(context).pop();
              } : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
                backgroundColor: WebColors.navy,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(WebRadius.button)),
              ),
              child: const Text('Filter', style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700)),
            )),
          ),
        ]),
      ),
    );
  }
}

class WebFilterSection extends StatelessWidget {
  const WebFilterSection({super.key, required this.title,
    required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: WebSpace.xl),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 13.5,
          fontWeight: FontWeight.w700, color: WebColors.text1)),
      const SizedBox(height: WebSpace.sm),
      child,
    ]),
  );
}

// ── Results row ───────────────────────────────────────────────────────────
class WebFilterChipGroup {
  const WebFilterChipGroup(this.label, this.values);
  final String label;
  /// value label → remove callback
  final Map<String, VoidCallback> values;
}

class WebFiltersResult extends StatelessWidget {
  const WebFiltersResult({
    super.key,
    required this.total,
    required this.groups,
    required this.onClearAll,
  });
  final int total;
  final List<WebFilterChipGroup> groups;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text.rich(TextSpan(children: [
        TextSpan(text: '$total', style: const TextStyle(
            fontWeight: FontWeight.w800, color: WebColors.text1)),
        const TextSpan(text: ' results found',
            style: TextStyle(color: WebColors.text2)),
      ]), style: const TextStyle(fontSize: 13.5)),
      const SizedBox(height: WebSpace.md),
      Wrap(spacing: WebSpace.sm, runSpacing: WebSpace.sm,
          crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final g in groups)
          Container(
            padding: const EdgeInsets.all(WebSpace.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(WebRadius.sm),
              border: Border.all(color: WebColors.border),
            ),
            child: Wrap(spacing: 6, runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('${g.label}:', style: const TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w700, color: WebColors.text1)),
              for (final e in g.values.entries)
                _RemovableChip(label: e.key, onRemove: e.value),
            ]),
          ),
        TextButton.icon(
          onPressed: onClearAll,
          style: TextButton.styleFrom(foregroundColor: WebColors.error),
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          label: const Text('Clear', style: TextStyle(
              fontWeight: FontWeight.w700)),
        ),
      ]),
    ]),
  );
}

class _RemovableChip extends StatefulWidget {
  const _RemovableChip({required this.label, required this.onRemove});
  final String label;
  final VoidCallback onRemove;
  @override
  State<_RemovableChip> createState() => _RemovableChipState();
}

class _RemovableChipState extends State<_RemovableChip> {
  bool _hov = false;
  @override
  Widget build(BuildContext context) => Container(
    height: 24,
    padding: const EdgeInsets.only(left: 8, right: 4),
    decoration: BoxDecoration(
      color: WebColors.navy,
      borderRadius: BorderRadius.circular(WebRadius.label),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(widget.label, style: const TextStyle(fontSize: 12,
          fontWeight: FontWeight.w600, color: Colors.white)),
      const SizedBox(width: 4),
      MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hov = true),
        onExit:  (_) => setState(() => _hov = false),
        child: GestureDetector(
          onTap: widget.onRemove,
          child: Icon(Icons.cancel_rounded, size: 16,
              color: Colors.white.withValues(alpha: _hov ? 1 : 0.6)),
        ),
      ),
    ]),
  );
}
