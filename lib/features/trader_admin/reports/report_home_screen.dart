// ─────────────────────────────────────────────────────────────────────────────
// ReportsHomeScreen — NEW primary Reports entry point (category-based).
//
// Does not replace anything: "All Reports" (the existing flat chip list,
// ReportsHubScreen) remains one tap away via the button below, unchanged.
// Search / Favorites / Recently Viewed / Frequently Used are intentionally
// NOT in this phase — they depend on the report_usage_log/report_favorites
// tables from the approved migration plan, which haven't been created yet.
// This screen ships with just category navigation + the All Reports link,
// per the phased roadmap (P1 first, P2 adds the rest once schema is approved).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import 'report_inventory.dart';
import 'reports_hub_screen.dart';

class ReportsHomeScreen extends StatelessWidget {
  const ReportsHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kBgPage,
        elevation: 0,
        title: const Text('Reports',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kTextMain)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const Text('Browse by category',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kTextHint)),
          const SizedBox(height: 10),
          ...ReportCategory.values.map((cat) => _CategoryCard(category: cat)),
          const SizedBox(height: 20),
          // "All Reports" — the existing flat chip list, unchanged, always
          // reachable directly for traders who already know the report name.
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const ReportsHubScreen())),
            icon: const Icon(Icons.apps_outlined, size: 18),
            label: const Text('All Reports'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              side: const BorderSide(color: kBorderLight),
              foregroundColor: kNavy,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category});
  final ReportCategory category;

  @override
  Widget build(BuildContext context) {
    final count = reportCountInCategory(category);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(color: kBorderLight),
        boxShadow: kCardShadow,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadiusCard),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ReportListScreen(category: category))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: category.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(category.icon, color: category.color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(category.label.toUpperCase(),
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800, color: category.color, letterSpacing: 0.3)),
                const SizedBox(height: 2),
                Text(category.description,
                    style: const TextStyle(fontSize: 12, color: kTextSub), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text('$count report${count == 1 ? '' : 's'}',
                    style: const TextStyle(fontSize: 11, color: kTextHint, fontWeight: FontWeight.w600)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: kTextHint),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ReportListScreen — reports inside one category.
// ─────────────────────────────────────────────────────────────────────────────
class ReportListScreen extends StatelessWidget {
  const ReportListScreen({super.key, required this.category});
  final ReportCategory category;

  @override
  Widget build(BuildContext context) {
    final reports = reportsInCategory(category);
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kBgPage,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: kTextMain),
            onPressed: () => Navigator.of(context).pop()),
        title: Text('${category.label} Reports',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kTextMain)),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: reports.length,
        itemBuilder: (ctx, i) {
          final r = reports[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: kBorderLight),
              boxShadow: kCardShadow,
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(kRadiusCard),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ReportsHubScreen(initialReportKey: r.key))),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                child: Row(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                        color: category.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10)),
                    child: Icon(category.icon, color: category.color, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.label,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kTextMain)),
                      const SizedBox(height: 2),
                      Text(r.frequency,
                          style: const TextStyle(fontSize: 11, color: kTextHint)),
                    ]),
                  ),
                  const Icon(Icons.chevron_right, color: kTextHint),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}