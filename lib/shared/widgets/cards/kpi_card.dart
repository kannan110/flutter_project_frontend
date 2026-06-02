import 'package:flutter/material.dart';
import 'package:rooster_trader/core/theme/app_theme.dart';

// ── KpiCard (shared/widgets version) ─────────────────────────────────────
// Navy icon box + large number + gold accent for prestige KPIs
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.sub,
    this.onTap,
    this.compact = false,
  });

  final String       label;
  final String       value;
  final IconData     icon;
  final Color        color;
  final String?      sub;
  final VoidCallback? onTap;
  final bool         compact;

  @override
  Widget build(BuildContext context) {
    final pad    = compact ? 14.0 : 20.0;
    final valSz  = compact ? 24.0 : 32.0;

    return InkWell(
      onTap:        onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.all(pad),
        decoration: BoxDecoration(
          color:        kSurface,
          borderRadius: BorderRadius.circular(8),
          border:       Border.all(color: kBorderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize:       MainAxisSize.min,
          children: [
            // Icon badge — Navy with Gold icon
            Container(
              width: 40, height: 40,
              decoration: const BoxDecoration(
                color: kNavy,
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
              child: Center(child: Icon(icon, color: kGoldLight, size: 20)),
            ),
            const Spacer(),
            // KPI value
            Text(
              value,
              style: TextStyle(
                fontSize:      valSz,
                fontWeight:    FontWeight.w800,
                color:         kTextMain,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                  fontSize: 14, color: kTextSub, fontWeight: FontWeight.w500),
            ),
            if (sub != null) ...[
              const SizedBox(height: 2),
              Text(sub!,
                  style: TextStyle(
                      fontSize: 13, color: color, fontWeight: FontWeight.w700)),
            ],
          ],
        ),
      ),
    );
  }
}

// ── KpiRow ────────────────────────────────────────────────────────────────
class KpiRow extends StatelessWidget {
  const KpiRow({super.key, required this.cards, this.height = 130});
  final List<Widget> cards;
  final double       height;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w >= 768) {
      return SizedBox(
        height: height,
        child: Row(children: [
          for (int i = 0; i < cards.length; i++) ...[
            Expanded(child: cards[i]),
            if (i < cards.length - 1) const SizedBox(width: 12),
          ],
        ]),
      );
    }
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection:  Axis.horizontal,
        padding:          const EdgeInsets.symmetric(horizontal: 16),
        itemCount:        cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder:      (_, i)  => SizedBox(width: 160, child: cards[i]),
      ),
    );
  }
}