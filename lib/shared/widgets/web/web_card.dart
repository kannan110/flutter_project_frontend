import 'package:flutter/material.dart';
import '../../../core/theme/web_tokens.dart';

// ═══════════════════════════════════════════════════════════════════════════
// WebCard        — plain white card (16 radius, 1px slate border, soft shadow)
// WebSectionCard — card with a title / subtitle / action header row
// WebListCard    — list-page card that stacks tabs, toolbar, filter results,
//                  table and pagination with clipped corners
// ═══════════════════════════════════════════════════════════════════════════

class WebCard extends StatelessWidget {
  const WebCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(WebSpace.xl),
    this.color,
    this.onTap,
  });

  final Widget      child;
  final EdgeInsets  padding;
  final Color?      color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: WebDecor.card(color: color),
      clipBehavior: Clip.antiAlias,
      padding: padding,
      child: child,
    );
    if (onTap == null) return card;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: card),
    );
  }
}

class WebSectionCard extends StatelessWidget {
  const WebSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.action,
    this.bodyPadding = const EdgeInsets.fromLTRB(
        WebSpace.xl, 0, WebSpace.xl, WebSpace.xl),
    this.divider = false,
  });

  final String     title;
  final String?    subtitle;
  final IconData?  icon;
  final Widget?    action;
  final Widget     child;
  final EdgeInsets bodyPadding;
  /// Draw a divider between header and body (use for tables / lists).
  final bool       divider;

  @override
  Widget build(BuildContext context) => Container(
    decoration: WebDecor.card(),
    clipBehavior: Clip.antiAlias,
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      WebCardHeader(title: title, subtitle: subtitle, icon: icon,
          action: action),
      if (divider) const Divider(height: 1, color: WebColors.border),
      Padding(padding: bodyPadding, child: child),
    ]),
  );
}

class WebCardHeader extends StatelessWidget {
  const WebCardHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.action,
    this.padding = const EdgeInsets.fromLTRB(
        WebSpace.xl, WebSpace.xl - 4, WebSpace.xl, WebSpace.lg),
  });

  final String     title;
  final String?    subtitle;
  final IconData?  icon;
  final Widget?    action;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(children: [
      if (icon != null) ...[
        WebIconTile(icon: icon!, color: WebColors.navy, size: 32),
        const SizedBox(width: WebSpace.md),
      ],
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: WebText.cardTitle),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: WebText.cardSubtitle),
          ],
        ],
      )),
      ?action,
    ]),
  );
}

class WebListCard extends StatelessWidget {
  const WebListCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: WebDecor.card(),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    ),
  );
}

// ── Rounded icon tile (tinted background) ─────────────────────────────────
class WebIconTile extends StatelessWidget {
  const WebIconTile({
    super.key,
    required this.icon,
    required this.color,
    this.size = 40,
  });
  final IconData icon;
  final Color    color;
  final double   size;

  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(size * 0.3),
    ),
    child: Icon(icon, size: size * 0.5, color: color),
  );
}

// ── KPI / summary card ────────────────────────────────────────────────────
class WebKpiCard extends StatelessWidget {
  const WebKpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.sub,
    this.onTap,
  });

  final String   label;
  final String   value;
  final String?  sub;
  final IconData icon;
  final Color    color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => WebCard(
    onTap: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    child: Stack(clipBehavior: Clip.none, children: [
      // Soft accent blob in the corner
      Positioned(right: -20, top: -20, child: Container(
        width: 64, height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.06),
        ),
      )),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Expanded(child: Text(label, style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: WebColors.text2),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 6),
            WebIconTile(icon: icon, color: color, size: 28),
          ]),
          const SizedBox(height: 4),
          Text(value, style: WebText.kpiValue,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub!, style: WebText.caption.copyWith(fontSize: 11, height: 1.15),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    ]),
  );
}

// ── Status label (soft / filled) ──────────────────────────────────────────
class WebLabel extends StatelessWidget {
  const WebLabel(this.text, {
    super.key,
    this.color = WebColors.text2,
    this.filled = false,
    this.icon,
    this.dot = false,
  });

  final String    text;
  final Color     color;
  final bool      filled;
  final IconData? icon;
  final bool      dot;

  @override
  Widget build(BuildContext context) => Container(
    height: 24,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      color: filled ? color : color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(WebRadius.label),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (dot) ...[
        Container(width: 6, height: 6, decoration: BoxDecoration(
            shape: BoxShape.circle, color: filled ? Colors.white : color)),
        const SizedBox(width: 6),
      ],
      if (icon != null) ...[
        Icon(icon, size: 13, color: filled ? Colors.white : color),
        const SizedBox(width: 4),
      ],
      Text(text, style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700,
          color: filled ? Colors.white : color)),
    ]),
  );
}

// ── Icon button used in card headers / toolbars ───────────────────────────
class WebIconButton extends StatefulWidget {
  const WebIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.color = WebColors.text2,
    this.size = 36,
    this.outlined = true,
  });
  final IconData     icon;
  final VoidCallback? onTap;
  final String?      tooltip;
  final Color        color;
  final double       size;
  final bool         outlined;

  @override
  State<WebIconButton> createState() => _WebIconButtonState();
}

class _WebIconButtonState extends State<WebIconButton> {
  bool _hov = false;
  @override
  Widget build(BuildContext context) {
    final btn = MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hov = true),
      onExit:  (_) => setState(() => _hov = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: widget.size, height: widget.size,
          decoration: BoxDecoration(
            color: _hov ? WebColors.divider : WebColors.surface,
            borderRadius: BorderRadius.circular(WebRadius.button),
            border: widget.outlined
                ? Border.all(color: WebColors.border) : null,
          ),
          child: Icon(widget.icon, size: widget.size * 0.5,
              color: widget.color),
        ),
      ),
    );
    return widget.tooltip == null
        ? btn : Tooltip(message: widget.tooltip!, child: btn);
  }
}
