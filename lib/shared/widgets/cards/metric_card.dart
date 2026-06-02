import 'package:flutter/material.dart';
import 'package:rooster_trader/core/theme/app_theme.dart';

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
                style: const TextStyle(
                    fontSize: 12, color: kTextSub, fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: color)),
            if (sub != null)
              Text(sub!,
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
class MetricStrip extends StatelessWidget {
  const MetricStrip({super.key, required this.metrics, this.padding});
  final List<Widget> metrics;
  final EdgeInsets?  padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding ?? EdgeInsets.zero,
    child: Row(children: [
      for (int i = 0; i < metrics.length; i++) ...[
        Expanded(child: metrics[i]),
        if (i < metrics.length - 1) const SizedBox(width: 8),
      ],
    ]),
  );
}