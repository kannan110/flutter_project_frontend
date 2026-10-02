import 'package:flutter/material.dart';
import 'package:rooster_trader/core/theme/app_theme.dart';
import 'package:rooster_trader/shared/layouts/responsive_layout.dart';

// ── MetricCard ─────────────────────────────────────────────────────────────
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    this.color   = kTextMain,
    this.icon,
    this.sub,
    this.onTap,
  });

  final String       label;
  final String       value;
  final Color        color;
  final IconData?    icon;
  final String?      sub;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap:        onTap,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color:        kSurface,
        borderRadius: BorderRadius.circular(8),
        border:       Border.all(color: kBorderLight),
      ),
      child: Row(children: [
        if (icon != null) ...[
          Container(
            width:  32, height: 32,
            decoration: const BoxDecoration(
              color: kNavy,
              borderRadius: BorderRadius.all(Radius.circular(4)),
            ),
            child: Center(child: Icon(icon, size: 16, color: kGoldLight)),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize:       MainAxisSize.min,
          children: [
            Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, color: kTextSub, fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            // FittedBox lets large rupee values (e.g. ₹12,34,567) shrink to
            // fit the available width on one line instead of wrapping
            // character-by-character on narrow mobile cards.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  maxLines: 1,
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800, color: color)),
            ),
            if (sub != null)
              Text(sub!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: kTextHint)),
          ],
        )),
        if (onTap != null)
          const Icon(Icons.chevron_right_rounded, size: 16, color: kTextHint),
      ]),
    ),
  );
}

// ── MetricStrip ────────────────────────────────────────────────────────────
//
// Desktop/tablet: cards share the row equally via Expanded (plenty of width).
// Mobile: forcing 3-4 cards into equal Expanded columns leaves too little
// width for icon + label + value, causing character-by-character text
// wrapping. Instead, give each card a comfortable fixed width and let the
// strip scroll horizontally — same information, fully readable, no data lost.
class MetricStrip extends StatelessWidget {
  const MetricStrip({super.key, required this.metrics, this.padding});
  final List<Widget> metrics;
  final EdgeInsets?  padding;

  static const double _mobileCardWidth = 172;

  @override
  Widget build(BuildContext context) {
    final isDesktop = context.isDesktop;

    final Widget row = isDesktop
        ? Row(children: [
      for (int i = 0; i < metrics.length; i++) ...[
        Expanded(child: metrics[i]),
        if (i < metrics.length - 1) const SizedBox(width: 8),
      ],
    ])
        : Row(children: [
      for (int i = 0; i < metrics.length; i++) ...[
        SizedBox(width: _mobileCardWidth, child: metrics[i]),
        if (i < metrics.length - 1) const SizedBox(width: 8),
      ],
    ]);

    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: isDesktop
          ? row
          : SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: row,
      ),
    );
  }
}