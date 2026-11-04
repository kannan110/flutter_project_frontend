// ─────────────────────────────────────────────────────────────────────────────
// ReportsHomeScreen — the ONLY Reports entry point (class name unchanged so
// router/nav wiring needs no further changes).
//
// Per the approved zero-learning-curve spec:
//   - No category dropdown, no separate category screen, no "All Reports"
//     page, no dashboard/pulse cards. One screen only.
//   - Search + four always-visible, collapsible sections (expanded by
//     default) with sticky headers while scrolling.
//   - Tapping a report opens it directly — Reports → Report, no
//     intermediate screen, ever.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/layouts/responsive_layout.dart';
import '../../../shared/widgets/web/web.dart';
import 'supervisor_report_screen.dart';
import 'report_inventory.dart';
import 'reports_hub_screen.dart';

class ReportsHomeScreen extends StatefulWidget {
  const ReportsHomeScreen({super.key});

  @override
  State<ReportsHomeScreen> createState() => _ReportsHomeScreenState();
}

class _ReportsHomeScreenState extends State<ReportsHomeScreen> {
  String _query = '';
  final _searchCtrl = TextEditingController();

  // All sections expanded by default, per spec.
  final Map<ReportCategory, bool> _expanded = {
    for (final c in ReportCategory.values) c: true,
  };

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _isSearching => _query.trim().isNotEmpty;

  List<ReportInventoryEntry> _filtered(ReportCategory c) {
    final inCat = reportsInCategory(c);
    if (!_isSearching) return inCat;
    final q = _query.trim().toLowerCase();
    return inCat.where((r) => r.label.toLowerCase().contains(q)).toList();
  }

  void _openReport(String key) {
    if (key == 'supervisor_report') {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const SupervisorReportScreen(),
      ));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReportsHubScreen(initialReportKey: key, showChipPicker: false),
    ));
  }

  // ═══════════════════════════════════════════════════════════════════════
  // WEB (desktop) — search + one card per category (two columns).
  // Same reports, same "click a report → it opens directly" behaviour.
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildWeb() {
    final categories = ReportCategory.values
        .where((c) => _filtered(c).isNotEmpty)
        .toList();
    final total = ReportCategory.values
        .fold<int>(0, (s, c) => s + reportsInCategory(c).length);

    return WebPage(
      header: PageBreadcrumbsHeader(
        title: 'Reports',
        subtitle: '$total reports in ${ReportCategory.values.length} categories',
        crumbs: const [Crumb('Dashboard', R.dashboard), Crumb('Reports')],
        action: WebSearchField(
          controller: _searchCtrl,
          hint: 'Search reports...',
          debounce: const Duration(milliseconds: 100),
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      children: [
        if (categories.isEmpty)
          WebCard(child: WebTableState.empty(
              text: 'No reports match "$_query"'))
        else
          WebMasonry(columns: 2, children: [
            for (final c in categories) _webCategoryCard(c),
          ]),
      ],
    );
  }

  Widget _webCategoryCard(ReportCategory c) {
    final reports = _filtered(c);
    final isOpen = _isSearching || (_expanded[c] ?? true);
    return WebListCard(children: [
      MouseRegion(
        cursor: _isSearching
            ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _isSearching ? null : () =>
              setState(() => _expanded[c] = !(_expanded[c] ?? true)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
            child: Row(children: [
              WebIconTile(icon: c.icon, color: c.color, size: 36),
              const SizedBox(width: 12),
              Expanded(child: Text(c.label, style: WebText.cardTitle)),
              WebLabel('${reports.length}', color: c.color),
              if (!_isSearching) ...[
                const SizedBox(width: 8),
                Icon(isOpen ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                    size: 22, color: WebColors.text3),
              ],
            ]),
          ),
        ),
      ),
      if (isOpen) ...[
        const Divider(height: 1, color: WebColors.border),
        for (final r in reports)
          _WebReportRow(entry: r, onTap: () => _openReport(r.key)),
        const SizedBox(height: 6),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (context.isDesktop) return _buildWeb();
    // When searching, every matching report across every category is shown,
    // sections auto-expanded — a trader should not have to expand a section
    // by hand to see a search result inside it.
    final categories = ReportCategory.values
        .where((c) => _filtered(c).isNotEmpty)
        .toList();

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kBgPage,
        elevation: 0,
        title: const Text('Reports',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kTextMain)),
      ),
      body: CustomScrollView(
        slivers: [
          // ── Search — the fastest path for anyone who knows the name ──────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search reports...',
                  prefixIcon: const Icon(Icons.search, size: 20, color: kTextHint),
                  suffixIcon: _query.isEmpty ? null : IconButton(
                    icon: const Icon(Icons.close, size: 18, color: kTextHint),
                    onPressed: () => setState(() { _query = ''; _searchCtrl.clear(); }),
                  ),
                  filled: true,
                  fillColor: kSurface,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: kBorderLight)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: kBorderLight)),
                ),
              ),
            ),
          ),

          if (categories.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text('No reports match "$_query"',
                    style: const TextStyle(fontSize: 13, color: kTextHint)),
              ),
            )
          else
            for (final c in categories) ..._buildSection(c),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  List<Widget> _buildSection(ReportCategory c) {
    final reports = _filtered(c);
    // While searching, force the section open so results are visible
    // without an extra tap.
    final isOpen = _isSearching || (_expanded[c] ?? true);

    return [
      SliverPersistentHeader(
        pinned: true,
        delegate: _SectionHeaderDelegate(
          category: c,
          count: reports.length,
          expanded: isOpen,
          onTap: _isSearching ? null : () =>
              setState(() => _expanded[c] = !(_expanded[c] ?? true)),
        ),
      ),
      if (isOpen)
        SliverList(
          delegate: SliverChildBuilderDelegate(
                (ctx, i) => _ReportRow(
              entry: reports[i],
              showCategoryTag: _isSearching,
              onTap: () => _openReport(reports[i].key),
            ),
            childCount: reports.length,
          ),
        ),
    ];
  }
}

// ── Sticky section header ───────────────────────────────────────────────────
class _SectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  _SectionHeaderDelegate({
    required this.category,
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  final ReportCategory category;
  final int count;
  final bool expanded;
  final VoidCallback? onTap;

  @override
  double get minExtent => 44;
  @override
  double get maxExtent => 44;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(
      color: kBgPage,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: kBorderLight)),
          ),
          child: Row(children: [
            Icon(category.icon, size: 16, color: category.color),
            const SizedBox(width: kSpSm),
            Text(category.label.toUpperCase(),
                style: kTypeSectionTitle.copyWith(color: category.color)),
            const SizedBox(width: kSpXs + 2),
            Text('($count)', style: kTypeCaption),
            const Spacer(),
            if (onTap != null)
              Icon(expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20, color: kTextHint),
          ]),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SectionHeaderDelegate old) =>
      old.expanded != expanded || old.count != count;
}

// ── One report row ──────────────────────────────────────────────────────────
class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.entry, required this.onTap, this.showCategoryTag = false});
  final ReportInventoryEntry entry;
  final VoidCallback onTap;
  final bool showCategoryTag;

  @override
  Widget build(BuildContext context) {
    final color = entry.category.color;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: kSpLg, vertical: kSpSm + 2),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: kBorderLight, width: 0.5)),
        ),
        child: Row(children: [
          Container(width: 6, height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: kSpMd),
          Expanded(
            child: Text(entry.label, style: kTypeBody.copyWith(fontWeight: FontWeight.w600)),
          ),
          if (showCategoryTag)
            Padding(
              padding: const EdgeInsets.only(right: kSpSm),
              child: Text(entry.category.label,
                  style: kTypeCaption.copyWith(color: color, fontWeight: FontWeight.w700)),
            ),
          const Icon(Icons.chevron_right, size: 18, color: kTextHint),
        ]),
      ),
    );
  }
}

// ── Web report row (hover highlight) ────────────────────────────────────────
class _WebReportRow extends StatefulWidget {
  const _WebReportRow({required this.entry, required this.onTap});
  final ReportInventoryEntry entry;
  final VoidCallback onTap;
  @override
  State<_WebReportRow> createState() => _WebReportRowState();
}

class _WebReportRowState extends State<_WebReportRow> {
  bool _hov = false;
  @override
  Widget build(BuildContext context) {
    final color = widget.entry.category.color;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          color: _hov ? WebColors.hover : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(children: [
            Container(width: 7, height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 14),
            Expanded(child: Text(widget.entry.label, style: TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w600,
                color: _hov ? WebColors.navy : WebColors.text1))),
            Icon(Icons.chevron_right_rounded, size: 20,
                color: _hov ? WebColors.navy : WebColors.text3),
          ]),
        ),
      ),
    );
  }
}
