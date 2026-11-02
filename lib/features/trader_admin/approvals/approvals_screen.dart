import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/responsive_layout.dart';
import '../../../shared/widgets/common/async_state_view.dart';
import '../../../shared/widgets/filters/search_bar.dart' hide ListToolbar;
import '../../../shared/widgets/tables/app_table.dart';
import '../../../shared/widgets/web/web.dart';

class ApprovalsScreen extends ConsumerStatefulWidget {
  const ApprovalsScreen({super.key});
  @override
  ConsumerState<ApprovalsScreen> createState() => _S();
}

class _S extends ConsumerState<ApprovalsScreen> {
  final _c          = Supabase.instance.client;
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _items    = [];
  List<Map<String, dynamic>> _filtered = [];
  bool    _loading = true;
  bool    _approvingAll = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => _applySearch(_searchCtrl.text));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _applySearch(String q) {
    if (!mounted) return;
    if (q.trim().isEmpty) { setState(() => _filtered = List.from(_items)); return; }
    final lower = q.toLowerCase();
    setState(() => _filtered = _items.where((d) {
      final o = d['orders']          as Map<String, dynamic>?;
      final r = o?['retailers']      as Map<String, dynamic>?;
      final a = d['delivery_agents'] as Map<String, dynamic>?;
      return (r?['shop_name'] as String? ?? '').toLowerCase().contains(lower) ||
          (a?['name']      as String? ?? '').toLowerCase().contains(lower);
    }).toList());
  }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final data = await _c.from('deliveries')
          .select('id,delivered_total_weight,received_total_weight,collected_amount,'
          'delivered_bird_count,is_partial_delivery,delivered_at,created_at,'
          'orders(id,estimated_birds,total_quantity,fulfilled_birds,'
          'partial_count,is_partial_delivery,retailers(shop_name),'
          'order_items(master_products(name))),'
          'delivery_agents(name)')
          .eq('trader_id', tid)
          .eq('status', 'delivered')
          .eq('approval_status', 'pending')
      // ★ NEW (Undo Delivery bug fix, Issue 2): an undone delivery's
      // stock/cash effects were already reversed by Undo Delivery — it
      // must never appear here, or approving it would create a real
      // invoice against stock that no longer exists. is_undone stays
      // false for every normal delivery, so this is a no-op for them.
          .eq('is_undone', false)
          .order('delivered_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _items    = List<Map<String, dynamic>>.from(data);
        _filtered = List.from(_items);
        _loading  = false;
      });
      _applySearch(_searchCtrl.text);
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ── Approve All ───────────────────────────────────────────────────────────
  // Reuses the EXISTING single-order lifecycle: every order is approved via
  // the same `approve_delivery_and_order` RPC used by ApprovalDetailScreen,
  // called once per eligible pending delivery, sequentially. No new approval
  // logic, no new validations, no rate resolution logic — same automatic
  // rate resolution the RPC already falls back to when no manual per-item
  // rate override is supplied (i.e. exactly what happens today for any order
  // approved without editing the rate fields).
  //
  // Sequential, not a single wrapping transaction: each order commits (or
  // fails) independently, so one bad order cannot roll back others already
  // approved, and progress can be reported incrementally. See chat for the
  // full audit of why this is preferred over parallel/batched execution.
  // Single shared button — filled/primary on Desktop (the primary CTA per
  // spec), outlined elsewhere (Mobile/Tablet). Same handler everywhere;
  // only the visual weight changes with screen size.
  // Same-content button, styled for a compact inline toolbar slot rather
  // than the app's global full-width CTA default. The global
  // ElevatedButtonTheme/OutlinedButtonTheme (app_theme.dart) sets
  // minimumSize: Size.fromHeight(52) — i.e. infinite width — intended for
  // full-width buttons like "Complete Delivery". Left un-overridden here,
  // that forced an infinite-width constraint inside this Row, which Flutter
  // cannot satisfy, causing a layout exception and the button never
  // painting. Overriding minimumSize locally fixes this without touching
  // the shared theme or any other screen's buttons.
  Widget _approveAllButton({required bool primary}) {
    final label = Text('Approve All (${_items.length})');
    const icon = Icon(Icons.done_all_rounded, size: 16);
    const compactSize = Size(64, 40);
    if (primary) {
      return ElevatedButton.icon(
        onPressed: _approvingAll ? null : _approveAll,
        icon: icon,
        label: label,
        style: ElevatedButton.styleFrom(
          backgroundColor: kPrimary,
          foregroundColor: Colors.white,
          minimumSize: compactSize,
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: _approvingAll ? null : _approveAll,
      icon: icon,
      label: label,
      style: OutlinedButton.styleFrom(
        foregroundColor: kPrimary,
        side: BorderSide(color: kPrimary),
        minimumSize: compactSize,
      ),
    );
  }

  Future<void> _approveAll() async {
    if (_items.isEmpty || _approvingAll) return;

    final ok = await confirmDialog(
      context,
      title: 'Approve All Orders',
      message: 'Approve all pending orders?\n\n'
          'Pending: ${_items.length} orders\n\n'
          'This will approve all eligible pending orders using the same '
          'process as approving one at a time. Orders needing a custom rate '
          'will use automatic rate resolution.',
      confirmText: 'Approve All',
      confirmColor: kPrimary,
    );
    if (!ok || !mounted) return;

    // Snapshot the current list so the run operates on a fixed, known set —
    // re-fetching the "pending" query mid-run could otherwise pick up orders
    // that arrived after the user confirmed.
    final toApprove = List<Map<String, dynamic>>.from(_items);
    final userId = ref.read(appUserProvider).valueOrNull?.userId;

    int approved = 0;
    int failed = 0;
    final failures = <Map<String, String>>[]; // {retailer, error}
    // ROOT CAUSE FIX (Business Date audit): previously computed ONE shared
    // DateTime.now() here and applied it to every delivery in the batch,
    // regardless of each delivery's own business date — so bulk-approving
    // a mix of backdated batches collapsed them all onto today's date. Each
    // delivery's own delivered_at (already correctly business-dated by
    // complete_delivery) is now read per-delivery inside the loop below,
    // exactly like approve_delivery_and_order's own fallback already
    // prefers when no override is supplied.

    setState(() => _approvingAll = true);

    // Non-dismissible progress dialog, updated in place as each order settles.
    late StateSetter progressSetState;
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        progressSetState = setDialogState;
        final total = toApprove.length;
        final done = approved + failed;
        return AlertDialog(
          title: const Text('Approving Orders…'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: total == 0 ? 0 : done / total),
              const SizedBox(height: 12),
              Text('Approved: $approved   ·   Failed: $failed   ·   $done / $total'),
            ],
          ),
        );
      }),
    ));

    for (final delivery in toApprove) {
      final deliveryId = delivery['id'] as String;
      final order = delivery['orders'] as Map<String, dynamic>?;
      final retailer = order?['retailers'] as Map<String, dynamic>?;
      final shopName = retailer?['shop_name'] as String? ?? 'Unknown retailer';

      try {
        // Same RPC, same shape as ApprovalDetailScreen._approve(), with no
        // manual rate override — matches the RPC's own automatic-resolution
        // default path (identical to a single-/multi-product order approved
        // without touching the rate fields).
        //
        // p_invoice_date is this delivery's OWN delivered_at (already
        // correctly business-dated by complete_delivery) — not a shared
        // "today" for the whole run. If somehow missing, omit the param
        // entirely so the RPC's own COALESCE(p_invoice_date, DATE(delivered_at),
        // CURRENT_DATE) fallback resolves it instead of forcing today's date.
        final deliveredAt = delivery['delivered_at'] as String?;
        await _c.rpc('approve_delivery_and_order', params: {
          'p_delivery_id': deliveryId,
          'p_final_rate': null,
          'p_final_amount': null,
          'p_approved_by': userId,
          'p_approval_notes': 'Bulk approved via Approve All',
          if (deliveredAt != null)
            'p_invoice_date': deliveredAt.split('T')[0],
        });
        approved++;
      } catch (e) {
        failed++;
        failures.add({
          'retailer': shopName,
          'error': e
              .toString()
              .replaceAll('Exception: ', '')
              .replaceAll('PostgrestException(message: ', ''),
        });
      }
      if (mounted) progressSetState(() {});
    }

    if (mounted) Navigator.of(context, rootNavigator: true).pop(); // close progress dialog
    setState(() => _approvingAll = false);
    await _load(); // refresh the pending list

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve All — Complete'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Approved: $approved', style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('Failed: $failed',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: failed > 0 ? kError : null)),
              if (failures.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Failed orders (review individually):',
                    style: TextStyle(fontSize: 12, color: kTextHint)),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView(
                    shrinkWrap: true,
                    children: failures
                        .map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('• ${f['retailer']}: ${f['error']}',
                          style: const TextStyle(fontSize: 12)),
                    ))
                        .toList(),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = context.isDesktop;
    final isMobile  = context.isMobile;
    final hasPending = _items.isNotEmpty;
    if (isDesktop) return _buildWebPage();

    return ListScreenScaffold(
      appBar: isDesktop ? null : AppBar(
        backgroundColor: kSurface,
        title: Row(children: [
          const Text('Pending Approvals'),
          if (hasPending) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.orange, borderRadius: BorderRadius.circular(10)),
              child: Text('${_items.length}',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ],
        ]),
        // Refresh only — Approve All lives in the toolbar row below (visible
        // on every breakpoint), kept out of the AppBar to avoid a second,
        // redundant control.
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),

      // Responsive toolbar row:
      //   Mobile  — Search + "Approve All (N)" only (Refresh stays in the
      //             AppBar above, to keep this row from crowding).
      //   Tablet  — Search left, "Approve All (N)" + Refresh right.
      //   Desktop — Search left, "Approve All (N)" as a filled primary CTA
      //             + Refresh, top-right.
      toolbar: ListToolbar(
        searchController: _searchCtrl,
        searchHint:       'Search by retailer or agent…',
        onSearch:         _applySearch,
        onClearSearch:    () { _searchCtrl.clear(); _applySearch(''); },
        secondaryActions: [
          if (hasPending)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _approveAllButton(primary: isDesktop),
            ),
          if (!isMobile)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: IconButton(
                  icon: const Icon(Icons.refresh_outlined),
                  onPressed: _load,
                  tooltip: 'Refresh'),
            ),
        ],
      ),

      content: AsyncStateView(
        loading:      _loading,
        error:        _error,
        empty:        _filtered.isEmpty && !_loading,
        emptyIcon:    Icons.fact_check_outlined,
        emptyMessage: _items.isEmpty ? 'No pending approvals' : 'No results match',
        emptySub:     _items.isEmpty ? 'Delivered orders appear here for review' : null,
        onRetry:      _load,
        child: ResponsiveLayout(
          mobile:  (_) => _buildMobileList(),
        ),
      ),
    );
  }

  // ── Web page (desktop) ────────────────────────────────────────────────────

  static const _webTypes = ['all', 'full', 'partial'];
  String _webType = 'all';
  String _sortKey = 'delivered';
  bool _sortAsc = false;
  bool _dense = true;
  int _page = 0;
  int _rowsPerPage = 25;

  static const _webColumns = [
    WebColumn('Date & Time', width: 165, sortKey: 'delivered'),
    WebColumn('Retailer', flex: 3, sortKey: 'retailer'),
    WebColumn('Product', width: 120),
    WebColumn('Agent', flex: 2, sortKey: 'agent'),
    WebColumn('Weight', width: 110, sortKey: 'weight', align: TextAlign.right),
    WebColumn('Birds', width: 85, sortKey: 'birds', align: TextAlign.right),
    WebColumn('Cash', width: 115, sortKey: 'cash', align: TextAlign.right),
    WebColumn('Type', width: 110, align: TextAlign.center),
    WebColumn('Action', width: 80, align: TextAlign.center),
  ];

  bool _isPartial(Map<String, dynamic> d) => d['is_partial_delivery'] == true;
  double _wt(Map<String, dynamic> d) =>
      ((d['received_total_weight'] ?? d['delivered_total_weight']) as num?)
          ?.toDouble() ?? 0;

  Comparable<Object> _sortValue(Map<String, dynamic> d) {
    switch (_sortKey) {
      case 'retailer':
        return (((d['orders'] as Map?)?['retailers'] as Map?)?['shop_name']
                as String? ?? '').toLowerCase();
      case 'agent':
        return ((d['delivery_agents'] as Map?)?['name'] as String? ?? '')
            .toLowerCase();
      case 'weight':
        return _wt(d);
      case 'birds':
        return (d['delivered_bird_count'] as num?) ?? 0;
      case 'cash':
        return (d['collected_amount'] as num?) ?? 0;
      case 'delivered':
      default:
        return d['delivered_at'] as String? ?? '';
    }
  }

  Widget _webCell(Map<String, dynamic> d, int col) {
    switch (col) {
      case 0:
        final dt = DateTime.tryParse(d['delivered_at'] as String? ?? '');
        return Text(
          dt != null ? DateFormat('d MMM y, h:mm a').format(dt.toLocal()) : '—',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, color: WebColors.text2),
        );
      case 1:
        final o = d['orders'] as Map<String, dynamic>?;
        final name = (o?['retailers'] as Map?)?['shop_name'] as String? ?? '—';
        return Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5,
                fontWeight: FontWeight.w600, color: WebColors.text1));
      case 2:
        final lbl = _ApprovalCard._productLabel(d);
        return lbl.isEmpty
            ? const Text('—', style: WebText.caption)
            : WebLabel(lbl, color: _ApprovalCard._productColor(lbl));
      case 3:
        final a = d['delivery_agents'] as Map<String, dynamic>?;
        return Text(a?['name'] as String? ?? '—', maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5, color: WebColors.text2));
      case 4:
        final w = _wt(d);
        return Text(w > 0 ? '${w.toStringAsFixed(1)} kg' : '—',
            style: const TextStyle(fontSize: 13.5, color: WebColors.text2));
      case 5:
        final b = (d['delivered_bird_count'] as num?)?.toInt() ?? 0;
        return Text(b > 0 ? '$b' : '—',
            style: const TextStyle(fontSize: 13.5, color: WebColors.text2));
      case 6:
        final cash = (d['collected_amount'] as num?)?.toDouble() ?? 0;
        return Text(cash > 0 ? Fmt.amount(cash) : '—',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700,
                color: cash > 0 ? WebColors.success : WebColors.text3));
      case 7:
        final p = _isPartial(d);
        final attempt =
            ((d['orders'] as Map?)?['partial_count'] as num?)?.toInt() ?? 1;
        return WebLabel(p ? 'Partial #$attempt' : 'Full',
            color: p ? WebColors.warning : WebColors.success);
      default:
        return WebIconButton(
          icon: Icons.visibility_outlined,
          tooltip: 'Review',
          size: 32,
          outlined: false,
          onTap: () => context.push(R.approvalDetailPath(d['id'])),
        );
    }
  }

  Widget _buildWebPage() {
    var rows = _filtered.where((d) => _webType == 'all' ||
        (_webType == 'partial') == _isPartial(d)).toList();
    rows.sort((a, b) {
      final c = Comparable.compare(_sortValue(a), _sortValue(b));
      return _sortAsc ? c : -c;
    });
    final lastPage = rows.isEmpty ? 0 : (rows.length - 1) ~/ _rowsPerPage;
    final page = _page.clamp(0, lastPage);
    final pageRows =
        rows.skip(page * _rowsPerPage).take(_rowsPerPage).toList();

    final totalWt = _items.fold<double>(0, (s, d) => s + _wt(d));
    final totalCash = _items.fold<double>(0,
        (s, d) => s + ((d['collected_amount'] as num?)?.toDouble() ?? 0));
    final partials = _items.where(_isPartial).length;
    int countOf(String t) => t == 'all' ? _items.length
        : _items.where((d) => (t == 'partial') == _isPartial(d)).length;

    return WebPage(
      header: PageBreadcrumbsHeader(
        title: 'Pending Approvals',
        titleTrailing: _items.isEmpty ? null
            : WebLabel('${_items.length} to review',
                color: WebColors.warning, dot: true),
        subtitle: 'Delivered orders waiting for your review',
        crumbs: const [Crumb('Dashboard', R.dashboard), Crumb('Approvals')],
        action: Row(mainAxisSize: MainAxisSize.min, children: [
          WebIconButton(icon: Icons.refresh_rounded, tooltip: 'Refresh',
              onTap: _load),
          if (_items.isNotEmpty) ...[
            const SizedBox(width: 8),
            WebButton(
              label: 'Approve All (${_items.length})',
              icon: Icons.done_all_rounded,
              onPressed: _approvingAll ? null : _approveAll,
            ),
          ],
        ]),
      ),
      children: [
        WebKpiRow(children: [
          WebKpiCard(label: 'Awaiting Review', value: '${_items.length}',
              icon: Icons.fact_check_outlined, color: WebColors.warning),
          WebKpiCard(label: 'Delivered Weight',
              value: '${totalWt.toStringAsFixed(1)} kg',
              icon: Icons.scale_outlined, color: WebColors.navy),
          WebKpiCard(label: 'Cash Collected', value: Fmt.amount(totalCash),
              icon: Icons.payments_outlined, color: WebColors.success),
          WebKpiCard(label: 'Partial Deliveries', value: '$partials',
              icon: Icons.timelapse_rounded, color: WebColors.gold),
        ]),
        const SizedBox(height: WebSpace.lg),
        WebListCard(children: [
          WebListTabs(
            tabs: [
              WebTab('All', count: countOf('all')),
              WebTab('Full', count: countOf('full'),
                  color: WebColors.success),
              WebTab('Partial', count: countOf('partial'),
                  color: WebColors.warning),
            ],
            selected: _webTypes.indexOf(_webType),
            onChanged: (i) => setState(() {
              _webType = _webTypes[i];
              _page = 0;
            }),
          ),
          WebListToolbar(
            search: WebSearchField(
              controller: _searchCtrl,
              hint: 'Search by retailer or agent…',
              debounce: const Duration(milliseconds: 250),
              onChanged: (v) {
                _applySearch(v);
                setState(() => _page = 0);
              },
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(WebSpace.xl),
              child: AsyncStateView(loading: false, error: _error,
                  onRetry: _load, child: const SizedBox.shrink()),
            )
          else
            WebDataTable<Map<String, dynamic>>(
              columns: _webColumns,
              rows: pageRows,
              cellBuilder: _webCell,
              onRowTap: (d) => context.push(R.approvalDetailPath(d['id'])),
              sortKey: _sortKey,
              sortAscending: _sortAsc,
              onSort: (k) => setState(() {
                if (_sortKey == k) {
                  _sortAsc = !_sortAsc;
                } else {
                  _sortKey = k;
                  _sortAsc = true;
                }
                _page = 0;
              }),
              dense: _dense,
              loading: _loading,
              emptyText: _items.isEmpty
                  ? 'No pending approvals' : 'No results match',
            ),
          WebTablePagination(
            page: page,
            rowsPerPage: _rowsPerPage,
            total: rows.length,
            onPage: (p) => setState(() => _page = p),
            onRowsPerPage: (n) =>
                setState(() { _rowsPerPage = n; _page = 0; }),
            dense: _dense,
            onDense: (v) => setState(() => _dense = v),
          ),
        ]),
      ],
    );
  }

  // ── Mobile card list ──────────────────────────────────────────────────────

  Widget _buildMobileList() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding:          const EdgeInsets.fromLTRB(16, 16, 16, kBottomNavClearance),
        itemCount:        _filtered.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder:      (_, i)  => _ApprovalCard(item: _filtered[i]),
      ),
    );
  }
}

// ── Mobile approval card ──────────────────────────────────────────────────────

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({required this.item});
  final Map<String, dynamic> item;

  // ── Product helpers (display-only) ────────────────────────────────────────
  static String _productLabel(Map<String, dynamic> delivery) {
    final o     = delivery['orders'] as Map<String, dynamic>?;
    final items = (o?['order_items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final names = items
        .map((i) => (i['master_products'] as Map?)?['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();
    if (names.isEmpty) return '';
    return names.length == 1 ? names.first : 'Multi-product';
  }

  static Color _productColor(String label) {
    final l = label.toLowerCase();
    if (l.contains('country')) return const Color(0xFF6D4C41);
    if (l.contains('quail'))   return Colors.purple;
    if (l.contains('multi'))   return Colors.indigo;
    return const Color(0xFF00796B); // broiler
  }

  Widget _chip(String label, IconData icon, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: c),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c)),
    ]),
  );

  @override
  @override
  Widget build(BuildContext context) {
    final o           = item['orders']          as Map<String, dynamic>?;
    final r           = o?['retailers']         as Map<String, dynamic>?;
    final a           = item['delivery_agents'] as Map<String, dynamic>?;
    final w           = ((item['received_total_weight'] ?? item['delivered_total_weight']) as num?)
        ?.toDouble() ?? 0;
    final birds       = (item['delivered_bird_count'] as num?)?.toInt() ?? 0;
    final isPartial   = item['is_partial_delivery'] == true;
    final cash        = (item['collected_amount']     as num?)?.toDouble() ?? 0;
    final deliveredAt = DateTime.tryParse(item['delivered_at'] as String? ?? '');
    final totalBirds  = (o?['estimated_birds']  as num?)?.toInt() ?? 0;
    final fulfilledB  = (o?['fulfilled_birds']  as num?)?.toInt() ?? 0;
    final pct         = totalBirds > 0 ? (fulfilledB / totalBirds).clamp(0.0, 1.0) : 1.0;
    final attempt     = (o?['partial_count'] as num?)?.toInt() ?? 1;
    final shopName    = r?['shop_name'] as String? ?? '—';
    final agentName   = a?['name']     as String? ?? '—';

    return InkWell(
      onTap: () => context.push(R.approvalDetailPath(item['id'])),
      borderRadius: BorderRadius.circular(kRadiusCard),
      child: Container(
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border: Border.all(
              color: Colors.orange.withValues(alpha: 0.4), width: 1.5),
          boxShadow: kCardShadow,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.04),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(kRadiusCard)),
              border: Border(bottom: BorderSide(color: kBorderLight.withValues(alpha: 0.5))),
            ),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFFEA580C), Color(0xFFF97316)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(child: Text(
                  shopName.isNotEmpty ? shopName[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white),
                )),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(shopName, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                        color: kNavy, letterSpacing: -0.3)),
                const SizedBox(height: 2),
                // ── Product chip (display-only) ───────────────────────────
                Builder(builder: (_) {
                  final lbl = _productLabel(item);
                  if (lbl.isEmpty) return const SizedBox.shrink();
                  final c = _productColor(lbl);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: c.withValues(alpha: 0.3))),
                    child: Text(lbl,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c)),
                  );
                }),
                Text('Agent: $agentName', style: const TextStyle(
                    fontSize: 11, color: kTextHint, fontWeight: FontWeight.w600)),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(kRadiusChip),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: const Text('REVIEW', style: TextStyle(fontSize: 9,
                      fontWeight: FontWeight.w900, color: Colors.orange, letterSpacing: 0.5)),
                ),
                if (isPartial) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.deepOrange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4)),
                    child: Text('Partial #$attempt', style: const TextStyle(fontSize: 9,
                        fontWeight: FontWeight.w800, color: Colors.deepOrange)),
                  ),
                ],
              ]),
            ]),
          ),
          // Stats
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: [
              _chip('${w.toStringAsFixed(1)} kg', Icons.scale_outlined, Colors.teal),
              if (birds > 0) ...[const SizedBox(width: 8),
                _chip('$birds birds', Icons.egg_alt_outlined, kNavy)],
              if (cash > 0) ...[const SizedBox(width: 8),
                _chip(Fmt.amount(cash), Icons.payments_outlined, Colors.green)],
              const Spacer(),
              if (deliveredAt != null)
                Text(DateFormat('d MMM, h:mm a').format(deliveredAt.toLocal()),
                    style: const TextStyle(fontSize: 10, color: kTextHint)),
            ]),
          ),
          if (isPartial) Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Fulfilled: $fulfilledB / $totalBirds birds',
                    style: const TextStyle(fontSize: 11, color: kTextSub, fontWeight: FontWeight.w600)),
                Text('${(pct * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.orange)),
              ]),
              const SizedBox(height: 4),
              ClipRRect(borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: pct, minHeight: 6,
                      backgroundColor: Colors.orange.withValues(alpha: 0.15),
                      valueColor: const AlwaysStoppedAnimation(Colors.orange))),
            ]),
          ),
          const SizedBox(height: 14),
        ]),
      ),
    );
  }
}