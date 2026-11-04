import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/web/web.dart';
import '../../../shared/layouts/responsive_layout.dart';

// =============================================================================
// PURCHASE MANAGEMENT — 7-TAB ERP
// Overview | Purchases | Suppliers | Ledger | Costing | Reports | History
// =============================================================================
class PurchaseScreen extends ConsumerStatefulWidget {
  const PurchaseScreen({super.key});

  @override
  ConsumerState<PurchaseScreen> createState() => _S();
}

class _S extends ConsumerState<PurchaseScreen>
    with SingleTickerProviderStateMixin {
  final _c = Supabase.instance.client;
  late TabController _tab;

  // ── State ─────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _purchases = [];
  List<Map<String, dynamic>> _farms = [];
  List<Map<String, dynamic>> _companies = [];
  List<Map<String, dynamic>> _ledger = [];
  List<Map<String, dynamic>> _costing = [];
  List<Map<String, dynamic>> _auditLog = [];
  List<Map<String, dynamic>> _payHistory = [];
  List<Map<String, dynamic>> _rateHistory = [];
  Map<String, dynamic>? _overview;
  Map<String, dynamic>? _stockVal;
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _reportData;
  final Map<String, bool> _farmOverdue = {};
  bool _loading = true;

  // ── Filters ────────────────────────────────────────────────────────────────
  DateTime _from = DateTime.now().subtract(const Duration(days: 29));
  DateTime _to = DateTime.now();
  String? _filterFarm;
  String? _filterStatus;
  String? _filterPayStatus;
  String? _farmFilter; // ledger tab farm filter
  String _searchQuery = '';
  String _webSortKey = 'date';
  bool _webSortAsc = false;
  int _historySubTab = 0;

  static const _tabs = [
    'Overview',
    'Purchases',
    'Suppliers',
    'Ledger',
    'Costing',
    'Reports',
    'History'
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _tabs.length, vsync: this);
    _tab.addListener(() {
      if (mounted) setState(() {});
      if (!_tab.indexIsChanging) _load();
    });
    _load();
  }

  Future<T?> _showSheet<T>({
    required WidgetBuilder builder,
    double maxWidth = WebSize.dialogMd,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: WebColors.surface,
      constraints: BoxConstraints(maxWidth: maxWidth),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(WebRadius.card)),
      ),
      builder: builder,
    );
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  String get _fromStr => DateFormat('yyyy-MM-dd').format(_from);

  String get _toStr => DateFormat('yyyy-MM-dd').format(_to);

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (!mounted) return;
    if (tid == null) {
      setState(() => _loading = false);
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      switch (_tab.index) {
        case 0: // Overview
          final ov = await _c.rpc('get_supplier_dashboard', params: {
            'p_trader_id': tid,
            'p_from_date': _fromStr,
            'p_to_date': _toStr,
          }).timeout(const Duration(seconds: 12));
          final sm = await _c.rpc('get_purchase_summary', params: {
            'p_trader_id': tid,
            'p_from_date': _fromStr,
            'p_to_date': _toStr,
          }).timeout(const Duration(seconds: 12));
          final sv = await _c.rpc('get_stock_valuation', params: {
            'p_trader_id': tid
          }).timeout(const Duration(seconds: 10));
          if (mounted) {
            setState(() {
              _overview = ov as Map<String, dynamic>?;
              _summary = sm as Map<String, dynamic>?;
              _stockVal = sv as Map<String, dynamic>?;
            });
          }

        case 1: // Purchases
        // ROOT CAUSE FIX (Purchase Report duplicate DC audit): this used
        // to query purchase_entries directly with no awareness of the
        // batch's status, so a DC belonging to a since-rejected/cancelled
        // batch stayed visible here forever alongside its correct
        // re-entry. Now delegates to a filtered RPC (same row shape,
        // including the nested 'farms' object) instead of duplicating
        // the cancelled-batch filter logic in Dart/PostgREST syntax.
          final r = await _c.rpc('get_purchase_entries_list', params: {
            'p_trader_id': tid,
            'p_from_date': _fromStr,
            'p_to_date': _toStr,
            if (_filterFarm != null) 'p_farm_id': _filterFarm,
            if (_filterStatus != null) 'p_status': _filterStatus,
            if (_filterPayStatus != null) 'p_pay_status': _filterPayStatus,
            'p_limit': 100,
          });
          final sm2 = await _c.rpc('get_purchase_summary', params: {
            'p_trader_id': tid,
            'p_from_date': _fromStr,
            'p_to_date': _toStr,
          });
          if (mounted) {
            setState(() {
              _purchases = List<Map<String, dynamic>>.from(r as List? ?? []);
              _summary = sm2 as Map<String, dynamic>?;
            });
          }

        case 2: // Suppliers
          final r = await _c
              .from('farms')
              .select('id,farmer_name,farm_name,phone,location,credit_days,'
              'default_rate_per_kg,is_active,company_id,updated_at,'
              'poultry_companies(company_name)')
              .eq('trader_id', tid)
              .order('farmer_name');
          // ROOT CAUSE FIX (Purchase Report duplicate DC audit): same
          // cancelled-batch exclusion as the Purchases tab, via a filtered
          // RPC with the identical row shape, so this client-side
          // aggregation loop needs no changes.
          final pe = await _c.rpc('get_farm_purchase_stats', params: {
            'p_trader_id': tid,
          });
          final Map<String, Map<String, dynamic>> farmStats = {};
          for (final row
          in List<Map<String, dynamic>>.from(pe as List? ?? [])) {
            final fid = row['farm_id'] as String?;
            if (fid == null) continue;
            farmStats[fid] ??= {
              'total': 0.0,
              'paid': 0.0,
              'claim': 0.0,
              'overdue': 0
            };
            farmStats[fid]!['total'] = (farmStats[fid]!['total'] as double) +
                ((row['total_landed_cost'] as num?)?.toDouble() ?? 0);
            farmStats[fid]!['paid'] = (farmStats[fid]!['paid'] as double) +
                ((row['total_paid'] as num?)?.toDouble() ?? 0);
            farmStats[fid]!['claim'] = (farmStats[fid]!['claim'] as double) +
                ((row['claim_amount'] as num?)?.toDouble() ?? 0);
            if (row['payment_status'] == 'overdue') {
              farmStats[fid]!['overdue'] =
                  (farmStats[fid]!['overdue'] as int) + 1;
            }
          }
          final cos = await _c
              .from('poultry_companies')
              .select('id,company_name')
              .eq('trader_id', tid)
              .order('company_name');
          if (mounted) {
            setState(() {
              _farms = List<Map<String, dynamic>>.from(r as List? ?? [])
                  .map((f) => {...f, '_stats': farmStats[f['id']] ?? {}})
                  .toList();
              _companies = List<Map<String, dynamic>>.from(cos as List? ?? []);
            });
          }

        case 3: // Ledger
          var lq = _c.from('supplier_ledger').select(
              'id,entry_type,amount,reason,payment_mode,entry_date,'
                  'description,reference_number,payment_id,'
                  'farms(farmer_name),purchase_entries(dc_number,net_weight_kg)');
          lq = lq
              .eq('trader_id', tid)
              .gte('entry_date', _fromStr)
              .lte('entry_date', _toStr);
          if (_farmFilter != null) lq = lq.eq('farm_id', _farmFilter!);
          final lr = await lq.order('entry_date', ascending: false).limit(200);
          if (mounted) {
            setState(() {
              _ledger = List<Map<String, dynamic>>.from(lr as List? ?? []);
            });
          }

        case 4: // Costing
        // FIX: purchase_entries is 1-to-many per batch — join returns ARRAY not Map
        // Use a separate query to get farmer info per batch
          final r = await _c
              .from('batch_costing')
              .select('id,batch_id,dc_birds,dc_weight_kg,purchase_amount,'
              'transport_cost,loading_cost,handling_cost,operational_cost,total_cost,'
              'cost_per_kg,delivered_birds,delivered_kg,revenue,revenue_per_kg,'
              'shrinkage_kg,mortality_birds,mortality_kg,shrinkage_loss_amount,'
              'gross_profit,net_profit,profit_margin_pct,profit_per_kg,'
              'status,calculated_at,'
              'delivery_batches(farm_name,picked_up_at)')
              .eq('trader_id', tid)
              .order('created_at', ascending: false)
              .limit(50);

          // Separately fetch farmer names for each batch
          final batchIds = (r as List? ?? [])
              .map((c) => c['batch_id'] as String?)
              .where((id) => id != null)
              .toList();
          final peMap = <String, Map<String, dynamic>>{};
          if (batchIds.isNotEmpty) {
            // Defensive: batch_costing rows only ever exist for batches
            // that reached approve_shift, which a rejected/cancelled batch
            // never does — so this is currently a no-op filter, added for
            // robustness against any future cancellation path.
            final peRows = await _c.rpc('get_purchase_entries_for_batches', params: {
              'p_batch_ids': batchIds.cast<String>(),
            });
            for (final pe in (peRows as List? ?? [])) {
              final bid = pe['batch_id'] as String?;
              if (bid != null && !peMap.containsKey(bid)) {
                peMap[bid] = Map<String, dynamic>.from(pe as Map);
              }
            }
          }
          final enrichedCosting = (r as List? ?? []).map((c) {
            final bid = c['batch_id'] as String?;
            return {
              ...Map<String, dynamic>.from(c as Map),
              if (bid != null && peMap.containsKey(bid)) '_pe': peMap[bid]
            };
          }).toList();
          if (mounted) {
            setState(() {
              _costing = enrichedCosting.cast<Map<String, dynamic>>();
            });
          }

        case 5: // Reports
          final rd = await _c.rpc('get_purchase_report', params: {
            'p_trader_id': tid,
            'p_from_date': _fromStr,
            'p_to_date': _toStr,
            if (_filterFarm != null) 'p_farm_id': _filterFarm,
            if (_filterStatus != null) 'p_status': _filterStatus,
            if (_filterPayStatus != null) 'p_pay_status': _filterPayStatus,
          }).timeout(const Duration(seconds: 15));
          if (mounted) {
            setState(() {
              _reportData = rd as Map<String, dynamic>?;
            });
          }

        case 6: // History
          final hist = await _c.rpc('get_purchase_history', params: {
            'p_trader_id': tid,
            'p_from_date': _fromStr,
            'p_to_date': _toStr,
          }).timeout(const Duration(seconds: 12));
          if (hist != null) {
            final h = hist as Map<String, dynamic>;
            if (mounted) {
              setState(() {
                _auditLog = List<Map<String, dynamic>>.from(
                    h['audit_log'] as List? ?? []);
                _payHistory = List<Map<String, dynamic>>.from(
                    h['payment_history'] as List? ?? []);
                _rateHistory = List<Map<String, dynamic>>.from(
                    h['rate_history'] as List? ?? []);
              });
            }
          }
      }
    } catch (_) {
      
    }
    if (mounted) setState(() => _loading = false);
  }

  // ── Date range picker ──────────────────────────────────────────────────────
  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
        context: context,
        initialDateRange: DateTimeRange(start: _from, end: _to),
        firstDate: DateTime.now().subtract(const Duration(days: 730)),
        lastDate: DateTime.now(),
        builder: (ctx, child) => Theme(
            data: Theme.of(ctx)
                .copyWith(colorScheme: const ColorScheme.light(primary: kPrimary)),
            child: child!));
    if (r == null || !mounted) return;
    setState(() {
      _from = r.start;
      _to = r.end;
    });
    _load();
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  // ── Web (desktop): page header with actions, card with tab strip;
  // ERP-grade responsive tables and KPIs adhering strictly to the Rooster Design System.
  Widget _buildWeb(BuildContext context) => ColoredBox(
      color: WebColors.pageBg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            PageBreadcrumbsHeader(
              title: 'Purchase Management',
              subtitle: 'Procurement • Supplier Accounting • Profitability',
              crumbs: const [Crumb('Dashboard', R.dashboard),
                Crumb('Purchase')],
              padding: const EdgeInsets.only(bottom: WebSpace.lg),
              action: Wrap(spacing: 8, runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center, children: [
                WebButton(
                  label: '${DateFormat('d MMM').format(_from)} – '
                      '${DateFormat('d MMM y').format(_to)}',
                  icon: Icons.calendar_today_outlined,
                  outlined: true,
                  onPressed: _pickRange,
                ),
                if (_tab.index == 5)
                  WebButton(label: 'Export Report',
                      icon: Icons.share_outlined, outlined: true,
                      onPressed: _exportReport),
                WebButton(label: 'Add Supplier', icon: Icons.agriculture_outlined,
                    outlined: true, onPressed: _showAddFarm),
                WebButton(label: 'Add Company', icon: Icons.business_outlined,
                    outlined: true, onPressed: _showAddCompany),
                WebIconButton(icon: Icons.refresh_rounded, tooltip: 'Refresh',
                    onTap: _load),
              ]),
            ),
            Expanded(child: Container(
              decoration: WebDecor.card(),
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                WebListTabs(
                  tabs: [for (final t in _tabs) WebTab(t)],
                  selected: _tab.index,
                  onChanged: (i) => setState(() => _tab.animateTo(i)),
                ),
                Expanded(child: ColoredBox(
                  color: WebColors.pageBg,
                  child: _loading
                      ? const WebTableState.loading()
                      : TabBarView(
                          controller: _tab,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _tabOverviewWeb(),
                            _tabPurchasesWeb(),
                            _tabSuppliersWeb(),
                            _tabLedgerWeb(),
                            _tabCostingWeb(),
                            _tabReportsWeb(),
                            _tabHistoryWeb(),
                          ],
                        ),
                )),
              ]),
            )),
          ]),
      ));

  // ═══════════════════════════════════════════════════════════════════════════
  // WEB TAB IMPLEMENTATIONS (Desktop / Tablet)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _tabOverviewWeb() {
    final s = _summary;
    final o = _overview;
    if (s == null && o == null) {
      return const WebTableState.empty(text: 'No overview data for selected date range');
    }
    final total = (s?['total_purchase_amt'] as num?)?.toDouble() ?? 0;
    final paid = (s?['total_paid'] as num?)?.toDouble() ?? 0;
    final claim = (s?['total_claim'] as num?)?.toDouble() ?? 0;
    final due = (s?['total_outstanding'] as num?)?.toDouble() ?? 0;
    final avgCost = (s?['avg_cost_per_kg'] as num?)?.toDouble();
    final pending = (s?['pending_rate'] as num?)?.toInt() ?? 0;
    final overdue = (s?['overdue_count'] as num?)?.toInt() ?? 0;
    final prof = o?['profitability'] as Map<String, dynamic>?;
    final netProfit = (prof?['net_profit'] as num?)?.toDouble() ?? 0;
    final farms = (o?['farms'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final trend = (o?['monthly_trend'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final kpi1 = WebKpiCard(
      label: 'Total Purchases',
      value: Fmt.amount(total),
      icon: Icons.shopping_cart_outlined,
      color: WebColors.navy,
    );
    final kpi2 = WebKpiCard(
      label: 'Total Paid',
      value: Fmt.amount(paid),
      icon: Icons.payments_outlined,
      color: WebColors.success,
    );
    final kpi3 = WebKpiCard(
      label: 'Outstanding Due',
      value: Fmt.amount(due),
      icon: Icons.account_balance_outlined,
      color: due > 0 ? WebColors.warning : WebColors.success,
    );
    final kpi4 = WebKpiCard(
      label: 'Avg Cost / kg',
      value: avgCost != null ? 'Rs.${avgCost.toStringAsFixed(2)}' : '--',
      icon: Icons.scale_outlined,
      color: WebColors.gold,
    );
    final kpi5 = WebKpiCard(
      label: 'Total Claims',
      value: Fmt.amount(claim),
      icon: Icons.report_problem_outlined,
      color: WebColors.error,
    );
    final kpi6 = WebKpiCard(
      label: 'Net Profit',
      value: Fmt.amount(netProfit),
      icon: Icons.trending_up_rounded,
      color: netProfit >= 0 ? WebColors.success : WebColors.error,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(WebSpace.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (pending > 0 || overdue > 0) ...[
          Row(children: [
            if (pending > 0)
              Expanded(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      _tab.animateTo(1);
                      setState(() => _filterStatus = 'draft');
                      _load();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: WebColors.warningBg,
                        borderRadius: BorderRadius.circular(WebRadius.sm),
                        border: Border.all(color: WebColors.warning.withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.pending_actions_outlined, color: WebColors.warning, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '$pending DC(s) pending rate entry — click to enter rates',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: WebColors.warning,
                            ),
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: WebColors.warning, size: 20),
                      ]),
                    ),
                  ),
                ),
              ),
            if (pending > 0 && overdue > 0) const SizedBox(width: WebSpace.md),
            if (overdue > 0)
              Expanded(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      _tab.animateTo(1);
                      setState(() => _filterPayStatus = 'overdue');
                      _load();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: WebColors.errorBg,
                        borderRadius: BorderRadius.circular(WebRadius.sm),
                        border: Border.all(color: WebColors.error.withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.warning_amber_rounded, color: WebColors.error, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '$overdue payment(s) overdue — click to view',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: WebColors.error,
                            ),
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: WebColors.error, size: 20),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: WebSpace.lg),
        ],

        LayoutBuilder(builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 1100;
          return Column(children: [
            if (isNarrow) ...[
              WebKpiRow(children: [kpi1, kpi2, kpi3]),
              const SizedBox(height: WebSpace.md),
              WebKpiRow(children: [kpi4, kpi5, kpi6]),
            ] else ...[
              WebKpiRow(children: [kpi1, kpi2, kpi3, kpi4, kpi5, kpi6]),
            ],
          ]);
        }),
        const SizedBox(height: WebSpace.xl),

        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 3,
            child: WebSectionCard(
              title: 'Supplier Outstanding',
              subtitle: 'Top suppliers with pending balances',
              icon: Icons.agriculture_outlined,
              action: WebButton(
                label: 'View All Suppliers',
                icon: Icons.arrow_forward_rounded,
                outlined: true,
                onPressed: () => _tab.animateTo(2),
              ),
              child: farms.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('No suppliers with balances', style: TextStyle(color: WebColors.text3)),
                      ),
                    )
                  : Column(children: [
                      for (final f in farms.take(6)) ...[
                        Builder(builder: (_) {
                          final outstanding = (f['outstanding'] as num?)?.toDouble() ?? 0;
                          final total2 = (f['total_amount'] as num?)?.toDouble() ?? 0;
                          final name = f['farmer_name'] as String? ?? '--';
                          return InkWell(
                            onTap: () => _tab.animateTo(2),
                            borderRadius: BorderRadius.circular(WebRadius.sm),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: WebColors.surfaceAlt,
                                borderRadius: BorderRadius.circular(WebRadius.sm),
                                border: Border.all(color: WebColors.border),
                              ),
                              child: Row(children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: WebColors.navySoft,
                                  child: Text(
                                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: WebColors.navy,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: WebColors.text1)),
                                    Text(
                                      '${(f['dc_count'] as num?)?.toInt() ?? 0} DCs  •  ${Fmt.amount(total2)} total',
                                      style: const TextStyle(fontSize: 11, color: WebColors.text3),
                                    ),
                                  ]),
                                ),
                                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                  Text(
                                    Fmt.amount(outstanding),
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                      color: outstanding > 0 ? WebColors.warning : WebColors.success,
                                    ),
                                  ),
                                  Text(
                                    outstanding > 0 ? 'outstanding' : 'settled',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: outstanding > 0 ? WebColors.warning : WebColors.success,
                                    ),
                                  ),
                                ]),
                              ]),
                            ),
                          );
                        }),
                      ],
                    ]),
            ),
          ),
          const SizedBox(width: WebSpace.xl),
          Expanded(
            flex: 2,
            child: WebSectionCard(
              title: 'Monthly Purchase Trend',
              subtitle: 'Procurement volume by month',
              icon: Icons.bar_chart_rounded,
              child: trend.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('No trend data available', style: TextStyle(color: WebColors.text3)),
                      ),
                    )
                  : Container(
                      height: 240,
                      padding: const EdgeInsets.only(top: 16),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        for (final t in trend) ...[
                          Builder(builder: (_) {
                            final amt = (t['total_amount'] as num?)?.toDouble() ?? 0;
                            final maxAmt = trend
                                .map((x) => (x['total_amount'] as num?)?.toDouble() ?? 0)
                                .reduce((a, b) => a > b ? a : b)
                                .clamp(1.0, double.infinity);
                            final frac = (amt / maxAmt).clamp(0.05, 1.0);
                            final dt = DateTime.tryParse((t['month'] as String?) ?? '');
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                                  if (amt > 0)
                                    Text(
                                      Fmt.amount(amt),
                                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: WebColors.text2),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  const SizedBox(height: 4),
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    height: 160 * frac,
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                        colors: [WebColors.navy, WebColors.navyMid],
                                      ),
                                      borderRadius: BorderRadius.vertical(top: Radius.circular(WebRadius.sm)),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    dt != null ? DateFormat('MMM').format(dt) : (t['month'] ?? ''),
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: WebColors.text3),
                                  ),
                                ]),
                              ),
                            );
                          }),
                        ],
                      ]),
                    ),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _tabPurchasesWeb() {
    final s = _summary;
    final total = (s?['total_purchase_amt'] as num?)?.toDouble() ?? 0;
    final paid = (s?['total_paid'] as num?)?.toDouble() ?? 0;
    final due = (s?['total_outstanding'] as num?)?.toDouble() ?? 0;
    final avgCost = (s?['avg_cost_per_kg'] as num?)?.toDouble();
    final dcs = (s?['total_dcs'] as num?)?.toInt() ?? 0;
    final kg = (s?['total_weight_kg'] as num?)?.toDouble() ?? 0;
    final pendRate = (s?['pending_rate'] as num?)?.toInt() ?? 0;

    final query = _searchQuery.trim().toLowerCase();
    final filtered = _purchases.where((p) {
      if (query.isNotEmpty) {
        final dc = (p['dc_number'] as String? ?? '').toLowerCase();
        final farmer = (p['farms'] as Map?)?['farmer_name'] as String? ?? p['farmer_name'] as String? ?? '';
        if (!dc.contains(query) && !farmer.toLowerCase().contains(query)) {
          return false;
        }
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      Comparable<Object> val(Map<String, dynamic> row) {
        switch (_webSortKey) {
          case 'dc':
            return row['dc_number'] as String? ?? '';
          case 'farmer':
            return ((row['farms'] as Map?)?['farmer_name'] as String? ?? row['farmer_name'] as String? ?? '').toLowerCase();
          case 'rate':
            return (row['purchase_rate_per_kg'] as num?)?.toDouble() ?? -1;
          case 'total':
            return (row['total_landed_cost'] as num?)?.toDouble() ?? 0;
          case 'date':
          default:
            return row['dc_date'] as String? ?? '';
        }
      }
      final c = Comparable.compare(val(a), val(b));
      return _webSortAsc ? c : -c;
    });

    final pending = _purchases.where((p) => p['status'] == 'draft').length;

    final k1 = WebKpiCard(
      label: 'Total Purchases',
      value: Fmt.amount(total),
      icon: Icons.shopping_cart_outlined,
      color: WebColors.navy,
    );
    final k2 = WebKpiCard(
      label: 'Total Paid',
      value: Fmt.amount(paid),
      icon: Icons.payments_outlined,
      color: WebColors.success,
    );
    final k3 = WebKpiCard(
      label: 'Outstanding Due',
      value: Fmt.amount(due),
      icon: Icons.account_balance_outlined,
      color: due > 0 ? WebColors.warning : WebColors.success,
    );
    final k4 = WebKpiCard(
      label: 'Avg Cost / kg',
      value: avgCost != null ? 'Rs.${avgCost.toStringAsFixed(2)}' : '--',
      icon: Icons.scale_outlined,
      color: WebColors.gold,
    );
    final k5 = WebKpiCard(
      label: 'Total DCs',
      value: '$dcs',
      icon: Icons.receipt_long_outlined,
      color: WebColors.navyMid,
    );
    final k6 = WebKpiCard(
      label: 'Total Weight',
      value: '${kg.toStringAsFixed(0)} kg',
      icon: Icons.scale_rounded,
      color: WebColors.info,
    );
    final k7 = WebKpiCard(
      label: 'Rate Pending',
      value: '$pendRate',
      icon: Icons.pending_actions_outlined,
      color: pendRate > 0 ? WebColors.warning : WebColors.success,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(WebSpace.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (s != null) ...[
          LayoutBuilder(builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 1200;
            return Column(children: [
              if (isNarrow) ...[
                WebKpiRow(children: [k1, k2, k3, k4]),
                const SizedBox(height: WebSpace.md),
                WebKpiRow(children: [k5, k6, k7]),
              ] else ...[
                WebKpiRow(children: [k1, k2, k3, k4, k5, k6, k7]),
              ],
            ]);
          }),
          const SizedBox(height: WebSpace.lg),
        ],

        if (pending > 0) ...[
          Container(
            margin: const EdgeInsets.only(bottom: WebSpace.lg),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: WebColors.warningBg,
              borderRadius: BorderRadius.circular(WebRadius.sm),
              border: Border.all(color: WebColors.warning.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.pending_actions_outlined, color: WebColors.warning, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$pending DC(s) pending rate entry — click "Enter Rate" or tap the row to confirm',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: WebColors.warning),
                ),
              ),
              if (_filterStatus != 'draft')
                WebButton(
                  label: 'Filter Pending',
                  color: WebColors.warning,
                  onPressed: () {
                    setState(() => _filterStatus = 'draft');
                    _load();
                  },
                ),
            ]),
          ),
        ],

        WebListCard(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(WebSpace.xl, WebSpace.lg, WebSpace.xl, WebSpace.md),
            child: Row(children: [
              WebSearchField(
                hint: 'Search DC # or supplier…',
                width: 260,
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
              const SizedBox(width: WebSpace.md),
              Wrap(spacing: 8, children: [
                _webFilterChip('All Status', _filterStatus == null, () {
                  setState(() => _filterStatus = null);
                  _load();
                }),
                _webFilterChip('Draft', _filterStatus == 'draft', () {
                  setState(() => _filterStatus = 'draft');
                  _load();
                }),
                _webFilterChip('Confirmed', _filterStatus == 'confirmed', () {
                  setState(() => _filterStatus = 'confirmed');
                  _load();
                }),
                _webFilterChip('Locked', _filterStatus == 'locked', () {
                  setState(() => _filterStatus = 'locked');
                  _load();
                }),
                const SizedBox(width: 4),
                _webFilterChip('All Pay', _filterPayStatus == null, () {
                  setState(() => _filterPayStatus = null);
                  _load();
                }),
                _webFilterChip('Overdue', _filterPayStatus == 'overdue', () {
                  setState(() => _filterPayStatus = 'overdue');
                  _load();
                }),
                _webFilterChip('Paid', _filterPayStatus == 'paid', () {
                  setState(() => _filterPayStatus = 'paid');
                  _load();
                }),
                _webFilterChip('Partial', _filterPayStatus == 'partial', () {
                  setState(() => _filterPayStatus = 'partial');
                  _load();
                }),
                if (_filterStatus != null || _filterPayStatus != null || _searchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _filterStatus = null;
                        _filterPayStatus = null;
                        _searchQuery = '';
                      });
                      _load();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: WebColors.errorBg,
                        borderRadius: BorderRadius.circular(WebRadius.button),
                        border: Border.all(color: WebColors.error.withValues(alpha: 0.3)),
                      ),
                      child: const Text('Clear', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: WebColors.error)),
                    ),
                  ),
              ]),
              const Spacer(),
              Text('${filtered.length} entries', style: WebText.caption),
            ]),
          ),
          const Divider(height: 1, color: WebColors.border),

          WebDataTable<Map<String, dynamic>>(
            columns: const [
              WebColumn('DC Number', width: 140, sortKey: 'dc'),
              WebColumn('Date', width: 110, sortKey: 'date'),
              WebColumn('Supplier', flex: 2, sortKey: 'farmer'),
              WebColumn('Birds / Wt', width: 130, align: TextAlign.right),
              WebColumn('Arrival', width: 120, align: TextAlign.right),
              WebColumn('Rate / kg', width: 110, align: TextAlign.right, sortKey: 'rate'),
              WebColumn('Total Cost', width: 130, align: TextAlign.right, sortKey: 'total'),
              WebColumn('Paid / Due', width: 140, align: TextAlign.right),
              WebColumn('Status', width: 130, align: TextAlign.center),
              WebColumn('Actions', width: 170, align: TextAlign.center),
            ],
            rows: filtered,
            sortKey: _webSortKey,
            sortAscending: _webSortAsc,
            onSort: (k) => setState(() {
              if (_webSortKey == k) {
                _webSortAsc = !_webSortAsc;
              } else {
                _webSortKey = k;
                _webSortAsc = true;
              }
            }),
            paginate: true,
            rowsPerPage: 25,
            emptyText: 'No purchases found matching filters',
            onRowTap: (p) {
              if (p['status'] == 'draft') {
                _showRateEntry(p);
              } else {
                _showPurchaseDetail(p);
              }
            },
            cellBuilder: (p, col) {
              final status = p['status'] as String? ?? 'draft';
              final isDraft = status == 'draft';
              final isLocked = status == 'locked';
              final kg = (p['net_weight_kg'] as num?)?.toDouble() ?? 0;
              final arrWt = (p['arrival_weight_kg'] as num?)?.toDouble() ?? 0;
              final shortage = (p['shortage_kg'] as num?)?.toDouble() ?? 0;
              final rate = (p['purchase_rate_per_kg'] as num?)?.toDouble();
              final total = (p['total_landed_cost'] as num?)?.toDouble() ?? 0;
              final paid = (p['total_paid'] as num?)?.toDouble() ?? 0;
              final claim = (p['claim_amount'] as num?)?.toDouble() ?? 0;
              final pStatus = p['payment_status'] as String? ?? 'pending';
              final due = (total - paid - claim).clamp(0.0, double.infinity);
              final dcDate = DateTime.tryParse(p['dc_date'] as String? ?? '');
              final farmMap = p['farms'] as Map<String, dynamic>?;
              final farmName = farmMap?['farmer_name'] as String? ?? p['farmer_name'] as String? ?? '--';
              final isOverdue = pStatus == 'overdue';

              switch (col) {
                case 0:
                  return Text(
                    p['dc_number'] as String? ?? '--',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: WebColors.navy),
                  );
                case 1:
                  return Text(
                    dcDate != null ? DateFormat('d MMM y').format(dcDate) : '--',
                    style: const TextStyle(fontSize: 12.5, color: WebColors.text2),
                  );
                case 2:
                  final subFarm = farmMap?['farm_name'] as String?;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(farmName, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: WebColors.text1)),
                      if (subFarm != null && subFarm.isNotEmpty)
                        Text(subFarm, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: WebColors.text3)),
                    ],
                  );
                case 3:
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('${p['bird_count'] ?? 0} birds', style: const TextStyle(fontSize: 12.5, color: WebColors.text2)),
                      Text('${kg.toStringAsFixed(1)} kg', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: WebColors.text1)),
                    ],
                  );
                case 4:
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(arrWt > 0 ? '${arrWt.toStringAsFixed(1)} kg' : '—', style: const TextStyle(fontSize: 12.5, color: WebColors.text2)),
                      if (shortage > 0)
                        Text('Short: ${shortage.toStringAsFixed(1)} kg',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: WebColors.error)),
                    ],
                  );
                case 5:
                  return rate != null
                      ? Text('Rs.${rate.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: WebColors.text1))
                      : const WebLabel('PENDING', color: WebColors.warning);
                case 6:
                  return Text(
                    total > 0 ? Fmt.amount(total) : '—',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: WebColors.text1),
                  );
                case 7:
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(paid > 0 ? Fmt.amount(paid) : 'Rs.0',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: WebColors.success)),
                      Text(
                        due > 0 ? '${Fmt.amount(due)} due' : 'Settled',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: due > 0 ? (isOverdue ? WebColors.error : WebColors.warning) : WebColors.success,
                        ),
                      ),
                    ],
                  );
                case 8:
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      WebLabel(
                        isDraft ? 'DRAFT' : status.toUpperCase(),
                        color: isDraft
                            ? WebColors.warning
                            : (isLocked ? WebColors.text3 : WebColors.navy),
                      ),
                      if (isOverdue) ...[
                        const SizedBox(width: 4),
                        const WebLabel('OVERDUE', color: WebColors.error),
                      ],
                    ],
                  );
                default:
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isDraft)
                        WebButton(
                          label: 'Rate',
                          icon: Icons.edit_outlined,
                          color: WebColors.warning,
                          onPressed: () => _showRateEntry(p),
                        )
                      else ...[
                        if (due > 0 && !isLocked)
                          WebIconButton(
                            icon: Icons.payments_outlined,
                            tooltip: 'Pay',
                            size: 28,
                            onTap: () => _showPayment(p),
                          ),
                        if (!isLocked) ...[
                          WebIconButton(
                            icon: Icons.report_problem_outlined,
                            tooltip: 'Claim',
                            size: 28,
                            onTap: () => _showClaim(p),
                          ),
                          WebIconButton(
                            icon: Icons.lock_outline,
                            tooltip: 'Lock',
                            size: 28,
                            onTap: () => _lockEntry(p),
                          ),
                        ],
                        if (isLocked)
                          WebIconButton(
                            icon: Icons.lock_open_outlined,
                            tooltip: 'Reopen',
                            size: 28,
                            onTap: () => _unlockEntry(p),
                          ),
                        WebIconButton(
                          icon: Icons.visibility_outlined,
                          tooltip: 'View Detail',
                          size: 28,
                          onTap: () => _showPurchaseDetail(p),
                        ),
                      ],
                    ],
                  );
              }
            },
          ),
        ]),
      ]),
    );
  }

  Widget _tabSuppliersWeb() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(WebSpace.xl),
      child: WebListCard(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(WebSpace.xl, WebSpace.lg, WebSpace.xl, WebSpace.md),
          child: Row(children: [
            Text('${_farms.length} Suppliers', style: WebText.cardTitle),
            const Spacer(),
            WebButton(
              label: 'Add Supplier',
              icon: Icons.add,
              color: WebColors.navy,
              onPressed: _showAddFarm,
            ),
            const SizedBox(width: WebSpace.md),
            WebButton(
              label: 'Add Company',
              icon: Icons.business_outlined,
              outlined: true,
              onPressed: _showAddCompany,
            ),
          ]),
        ),
        const Divider(height: 1, color: WebColors.border),
        WebDataTable<Map<String, dynamic>>(
          columns: const [
            WebColumn('Farmer Name', flex: 2, sortKey: 'name'),
            WebColumn('Farm Name', flex: 2),
            WebColumn('Company', width: 160),
            WebColumn('Credit Days', width: 110, align: TextAlign.right),
            WebColumn('Default Rate', width: 120, align: TextAlign.right),
            WebColumn('Total Purchases', width: 140, align: TextAlign.right, sortKey: 'total'),
            WebColumn('Paid', width: 130, align: TextAlign.right),
            WebColumn('Outstanding', width: 140, align: TextAlign.right, sortKey: 'outstanding'),
            WebColumn('Status', width: 110, align: TextAlign.center),
            WebColumn('Actions', width: 140, align: TextAlign.center),
          ],
          rows: _farms,
          paginate: true,
          rowsPerPage: 25,
          emptyText: 'No suppliers registered',
          onRowTap: (f) => _showSupplierDashboard(f),
          cellBuilder: (f, col) {
            final st = f['_stats'] as Map<String, dynamic>? ?? {};
            final total = (st['total'] as double?) ?? 0;
            final pd = (st['paid'] as double?) ?? 0;
            final cl = (st['claim'] as double?) ?? 0;
            final outstanding = (total - pd - cl).clamp(0.0, double.infinity);
            final overdueCnt = (st['overdue'] as int?) ?? 0;
            final co = (f['poultry_companies'] as Map?)?['company_name'] as String?;
            final defRate = (f['default_rate_per_kg'] as num?)?.toDouble();

            switch (col) {
              case 0:
                final name = f['farmer_name'] as String? ?? '--';
                return Row(children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: WebColors.navySoft,
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: WebColors.navy),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: WebColors.text1),
                    ),
                  ),
                ]);
              case 1:
                return Text(
                  f['farm_name'] as String? ?? '--',
                  style: const TextStyle(fontSize: 12.5, color: WebColors.text2),
                );
              case 2:
                return co != null
                    ? WebLabel(co, color: WebColors.navy)
                    : const Text('—', style: TextStyle(color: WebColors.text3));
              case 3:
                return Text('${f['credit_days'] ?? 0} days', style: const TextStyle(fontSize: 12.5, color: WebColors.text2));
              case 4:
                return Text(
                  defRate != null ? 'Rs.${defRate.toStringAsFixed(2)}' : '—',
                  style: const TextStyle(fontSize: 12.5, color: WebColors.text2),
                );
              case 5:
                return Text(
                  Fmt.amount(total),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: WebColors.text1),
                );
              case 6:
                return Text(
                  Fmt.amount(pd),
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: WebColors.success),
                );
              case 7:
                return Text(
                  Fmt.amount(outstanding),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: outstanding > 0 ? (overdueCnt > 0 ? WebColors.error : WebColors.warning) : WebColors.success,
                  ),
                );
              case 8:
                return overdueCnt > 0
                    ? const WebLabel('OVERDUE', color: WebColors.error)
                    : (outstanding > 0 ? const WebLabel('ACTIVE', color: WebColors.warning) : const WebLabel('CLEAR', color: WebColors.success));
              default:
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    WebIconButton(
                      icon: Icons.dashboard_outlined,
                      tooltip: 'View Statement / Dashboard',
                      size: 28,
                      onTap: () => _showSupplierDashboard(f),
                    ),
                    if (outstanding > 0)
                      WebIconButton(
                        icon: Icons.payments_outlined,
                        tooltip: 'Pay Supplier',
                        size: 28,
                        onTap: () => _showPaymentForFarm(f),
                      ),
                    WebIconButton(
                      icon: Icons.edit_outlined,
                      tooltip: 'Edit Supplier',
                      size: 28,
                      onTap: () => _showEditFarm(f),
                    ),
                  ],
                );
            }
          },
        ),
      ]),
    );
  }

  Widget _tabLedgerWeb() {
    final allFarms = <String, String>{};
    for (final e in _ledger) {
      final fid = e['farm_id'] as String?;
      final fn = (e['farms'] as Map?)?['farmer_name'] as String?;
      if (fid != null && fn != null) allFarms[fid] = fn;
    }

    double balance = 0;
    final rows = _ledger.reversed.map((e) {
      final amt = (e['amount'] as num?)?.toDouble() ?? 0;
      if (e['entry_type'] == 'debit') {
        balance += amt;
      } else {
        balance -= amt;
      }
      return {...e, '_balance': balance};
    }).toList().reversed.toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(WebSpace.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: WebKpiCard(
              label: 'Outstanding Ledger Balance',
              value: Fmt.amount(balance),
              icon: Icons.account_balance_wallet_outlined,
              color: balance > 0 ? WebColors.warning : WebColors.success,
            ),
          ),
          const SizedBox(width: WebSpace.xl),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: WebColors.surface,
              borderRadius: BorderRadius.circular(WebRadius.button),
              border: Border.all(color: WebColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _farmFilter,
                hint: const Text('All Suppliers', style: TextStyle(fontSize: 13, color: WebColors.text2)),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All Suppliers', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  ...allFarms.entries.map((e) => DropdownMenuItem<String?>(
                    value: e.key,
                    child: Text(e.value, style: const TextStyle(fontSize: 13)),
                  )),
                ],
                onChanged: (v) {
                  setState(() => _farmFilter = v);
                  _load();
                },
              ),
            ),
          ),
        ]),
        const SizedBox(height: WebSpace.lg),

        WebListCard(children: [
          WebDataTable<Map<String, dynamic>>(
            columns: const [
              WebColumn('Date', width: 120),
              WebColumn('Supplier', flex: 2),
              WebColumn('DC Number', width: 130),
              WebColumn('Type', width: 130, align: TextAlign.center),
              WebColumn('Amount', width: 140, align: TextAlign.right),
              WebColumn('Balance', width: 150, align: TextAlign.right),
              WebColumn('Notes', flex: 2),
            ],
            rows: rows,
            paginate: true,
            rowsPerPage: 25,
            emptyText: 'No ledger entries for this period',
            cellBuilder: (e, col) {
              final isD = e['entry_type'] == 'debit';
              final amt = (e['amount'] as num?)?.toDouble() ?? 0;
              final bal = (e['_balance'] as double?) ?? 0;
              final dt = DateTime.tryParse(e['entry_date'] as String? ?? '');
              final farm = (e['farms'] as Map?)?['farmer_name'] as String? ?? '--';
              final dc = (e['purchase_entries'] as Map?)?['dc_number'] as String?;
              final notes = e['notes'] as String? ?? '—';

              switch (col) {
                case 0:
                  return Text(
                    dt != null ? DateFormat('d MMM y').format(dt) : '--',
                    style: const TextStyle(fontSize: 12.5, color: WebColors.text2),
                  );
                case 1:
                  return Text(farm, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: WebColors.text1));
                case 2:
                  return Text(dc ?? '—', style: const TextStyle(fontSize: 12.5, color: WebColors.navy, fontWeight: FontWeight.w600));
                case 3:
                  return isD
                      ? const WebLabel('DEBIT (PURCHASE)', color: WebColors.error)
                      : const WebLabel('CREDIT (PAYMENT)', color: WebColors.success);
                case 4:
                  return Text(
                    '${isD ? '+' : '-'}${Fmt.amount(amt)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: isD ? WebColors.error : WebColors.success,
                    ),
                  );
                case 5:
                  return Text(
                    Fmt.amount(bal),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: bal > 0 ? WebColors.warning : WebColors.success,
                    ),
                  );
                default:
                  return Text(notes, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: WebColors.text3));
              }
            },
          ),
        ]),
      ]),
    );
  }

  Widget _tabCostingWeb() {
    if (_costing.isEmpty) {
      return const WebTableState.empty(
        text: 'No costing data. Confirm purchase rates to see profitability.',
      );
    }
    final totalRevenue = _costing.fold<double>(0, (s, c) => s + ((c['revenue'] as num?)?.toDouble() ?? 0));
    final totalCost = _costing.fold<double>(0, (s, c) => s + ((c['total_cost'] as num?)?.toDouble() ?? 0));
    final totalProfit = _costing.fold<double>(0, (s, c) => s + ((c['net_profit'] as num?)?.toDouble() ?? 0));
    final margin = totalRevenue > 0 ? (totalProfit / totalRevenue * 100) : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(WebSpace.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        WebKpiRow(children: [
          WebKpiCard(
            label: 'Total Revenue',
            value: Fmt.amount(totalRevenue),
            icon: Icons.trending_up_rounded,
            color: WebColors.navy,
          ),
          WebKpiCard(
            label: 'Total Cost',
            value: Fmt.amount(totalCost),
            icon: Icons.account_balance_outlined,
            color: WebColors.navyMid,
          ),
          WebKpiCard(
            label: 'Net Profit',
            value: Fmt.amount(totalProfit),
            icon: Icons.savings_outlined,
            color: totalProfit >= 0 ? WebColors.success : WebColors.error,
          ),
          WebKpiCard(
            label: 'Profit Margin',
            value: totalRevenue > 0 ? '${margin.toStringAsFixed(1)}%' : '--',
            icon: Icons.percent_rounded,
            color: WebColors.gold,
          ),
        ]),
        const SizedBox(height: WebSpace.lg),

        WebListCard(children: [
          WebDataTable<Map<String, dynamic>>(
            columns: const [
              WebColumn('Batch / Farm', flex: 2),
              WebColumn('DC Number', width: 130),
              WebColumn('Delivered (kg)', width: 130, align: TextAlign.right),
              WebColumn('Cost / kg', width: 110, align: TextAlign.right),
              WebColumn('Revenue / kg', width: 120, align: TextAlign.right),
              WebColumn('Total Cost', width: 130, align: TextAlign.right),
              WebColumn('Revenue', width: 130, align: TextAlign.right),
              WebColumn('Net Profit', width: 130, align: TextAlign.right),
              WebColumn('Margin %', width: 110, align: TextAlign.right),
              WebColumn('Status', width: 120, align: TextAlign.center),
            ],
            rows: _costing,
            paginate: true,
            rowsPerPage: 25,
            cellBuilder: (c, col) {
              final pe = c['_pe'] as Map<String, dynamic>?;
              final peName = pe?['farmer_name'] as String?;
              final dcNum = pe?['dc_number'] as String?;
              final batch = peName ?? (c['delivery_batches'] as Map?)?['farm_name'] as String? ?? '--';
              final costKg = (c['cost_per_kg'] as num?)?.toDouble();
              final revKg = (c['revenue_per_kg'] as num?)?.toDouble();
              final profit = (c['net_profit'] as num?)?.toDouble() ?? 0;
              final revenue = (c['revenue'] as num?)?.toDouble() ?? 0;
              final cost = (c['total_cost'] as num?)?.toDouble() ?? 0;
              final m = (c['profit_margin_pct'] as num?)?.toDouble();
              final isPend = c['status'] == 'pending';
              final delKg = (c['delivered_kg'] as num?)?.toDouble() ?? 0;

              switch (col) {
                case 0:
                  return Text(batch, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: WebColors.text1));
                case 1:
                  return Text(dcNum ?? '—', style: const TextStyle(fontSize: 12.5, color: WebColors.navy, fontWeight: FontWeight.w600));
                case 2:
                  return Text('${delKg.toStringAsFixed(1)} kg', style: const TextStyle(fontSize: 12.5, color: WebColors.text2));
                case 3:
                  return Text(costKg != null ? 'Rs.${costKg.toStringAsFixed(2)}' : '--', style: const TextStyle(fontSize: 12.5, color: WebColors.text2));
                case 4:
                  return Text(revKg != null ? 'Rs.${revKg.toStringAsFixed(2)}' : '--', style: const TextStyle(fontSize: 12.5, color: WebColors.text2));
                case 5:
                  return Text(Fmt.amount(cost), style: const TextStyle(fontSize: 13, color: WebColors.text2));
                case 6:
                  return Text(Fmt.amount(revenue), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: WebColors.text1));
                case 7:
                  return Text(
                    Fmt.amount(profit),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: profit >= 0 ? WebColors.success : WebColors.error),
                  );
                case 8:
                  return Text(
                    m != null ? '${m.toStringAsFixed(1)}%' : '--',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: (m ?? 0) >= 0 ? WebColors.success : WebColors.error),
                  );
                default:
                  return WebLabel(isPend ? 'PENDING' : 'CONFIRMED', color: isPend ? WebColors.warning : WebColors.success);
              }
            },
          ),
        ]),
      ]),
    );
  }

  Widget _tabReportsWeb() {
    final rd = _reportData;
    final aggs = rd?['aggregates'] as Map<String, dynamic>?;
    final entries = List<Map<String, dynamic>>.from(rd?['entries'] as List? ?? []);

    final totalAmt = (aggs?['total_amount'] as num?)?.toDouble() ?? 0;
    final totalPd = (aggs?['total_paid'] as num?)?.toDouble() ?? 0;
    final totalDue = (aggs?['total_outstanding'] as num?)?.toDouble() ?? 0;
    final totalCl = (aggs?['total_claims'] as num?)?.toDouble() ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(WebSpace.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (aggs != null) ...[
          WebKpiRow(children: [
            WebKpiCard(
              label: 'Total Purchases',
              value: Fmt.amount(totalAmt),
              icon: Icons.shopping_cart_outlined,
              color: WebColors.navy,
            ),
            WebKpiCard(
              label: 'Total Paid',
              value: Fmt.amount(totalPd),
              icon: Icons.payments_outlined,
              color: WebColors.success,
            ),
            WebKpiCard(
              label: 'Outstanding Due',
              value: Fmt.amount(totalDue),
              icon: Icons.account_balance_outlined,
              color: totalDue > 0 ? WebColors.warning : WebColors.success,
            ),
            WebKpiCard(
              label: 'Total Claims',
              value: Fmt.amount(totalCl),
              icon: Icons.report_problem_outlined,
              color: WebColors.error,
            ),
          ]),
          const SizedBox(height: WebSpace.lg),
        ],

        WebListCard(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(WebSpace.xl, WebSpace.lg, WebSpace.xl, WebSpace.md),
            child: Row(children: [
              Text('${entries.length} Report Entries', style: WebText.cardTitle),
              const Spacer(),
              WebButton(
                label: 'Export Report',
                icon: Icons.share_outlined,
                color: WebColors.navy,
                onPressed: _exportReport,
              ),
            ]),
          ),
          const Divider(height: 1, color: WebColors.border),
          WebDataTable<Map<String, dynamic>>(
            columns: const [
              WebColumn('DC Number', width: 130),
              WebColumn('Date', width: 110),
              WebColumn('Supplier', flex: 2),
              WebColumn('Weight (kg)', width: 120, align: TextAlign.right),
              WebColumn('Rate / kg', width: 110, align: TextAlign.right),
              WebColumn('Total Cost', width: 130, align: TextAlign.right),
              WebColumn('Paid', width: 120, align: TextAlign.right),
              WebColumn('Outstanding', width: 130, align: TextAlign.right),
              WebColumn('Claims', width: 110, align: TextAlign.right),
              WebColumn('Net Profit', width: 130, align: TextAlign.right),
            ],
            rows: entries,
            paginate: true,
            rowsPerPage: 25,
            emptyText: 'No report records found for selected date range',
            cellBuilder: (e, col) {
              final total = (e['total_landed_cost'] as num?)?.toDouble() ?? 0;
              final paid = (e['total_paid'] as num?)?.toDouble() ?? 0;
              final due = (e['outstanding'] as num?)?.toDouble() ?? 0;
              final claims = (e['claim_amount'] as num?)?.toDouble() ?? 0;
              final profit = (e['net_profit'] as num?)?.toDouble();
              final dt = DateTime.tryParse(e['dc_date'] as String? ?? '');
              final wt = (e['net_weight_kg'] as num?)?.toDouble() ?? 0;
              final rate = (e['purchase_rate_per_kg'] as num?)?.toDouble();

              switch (col) {
                case 0:
                  return Text(e['dc_number'] as String? ?? '--', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: WebColors.navy));
                case 1:
                  return Text(dt != null ? DateFormat('d MMM y').format(dt) : '--', style: const TextStyle(fontSize: 12.5, color: WebColors.text2));
                case 2:
                  return Text(e['farmer_name'] as String? ?? '--', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: WebColors.text1));
                case 3:
                  return Text('${wt.toStringAsFixed(1)} kg', style: const TextStyle(fontSize: 12.5, color: WebColors.text2));
                case 4:
                  return Text(rate != null ? 'Rs.${rate.toStringAsFixed(2)}' : '--', style: const TextStyle(fontSize: 12.5, color: WebColors.text2));
                case 5:
                  return Text(Fmt.amount(total), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: WebColors.text1));
                case 6:
                  return Text(Fmt.amount(paid), style: const TextStyle(fontSize: 12.5, color: WebColors.success, fontWeight: FontWeight.w600));
                case 7:
                  return Text(
                    Fmt.amount(due),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: due > 0 ? WebColors.warning : WebColors.success),
                  );
                case 8:
                  return Text(claims > 0 ? Fmt.amount(claims) : '—', style: TextStyle(fontSize: 12.5, color: claims > 0 ? WebColors.error : WebColors.text3));
                default:
                  return profit != null
                      ? Text(Fmt.amount(profit), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: profit >= 0 ? WebColors.success : WebColors.error))
                      : const Text('—', style: TextStyle(color: WebColors.text3));
              }
            },
          ),
        ]),
      ]),
    );
  }

  Widget _tabHistoryWeb() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(WebSpace.xl),
      child: WebListCard(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(WebSpace.xl, WebSpace.lg, WebSpace.xl, WebSpace.md),
          child: Row(children: [
            WebSegmented<int>(
              options: const [0, 1, 2],
              selected: _historySubTab,
              label: (i) => switch (i) {
                0 => 'Audit Log (${_auditLog.length})',
                1 => 'Payments (${_payHistory.length})',
                _ => 'Rate Changes (${_rateHistory.length})',
              },
              onChanged: (i) => setState(() => _historySubTab = i),
            ),
          ]),
        ),
        const Divider(height: 1, color: WebColors.border),
        if (_historySubTab == 0)
          WebDataTable<Map<String, dynamic>>(
            columns: const [
              WebColumn('Time', width: 160),
              WebColumn('Action', width: 160),
              WebColumn('DC Number', width: 130),
              WebColumn('Supplier', flex: 2),
              WebColumn('Change Detail', flex: 2),
            ],
            rows: _auditLog,
            paginate: true,
            rowsPerPage: 25,
            emptyText: 'No audit log entries recorded',
            cellBuilder: (a, col) {
              final dt = DateTime.tryParse(a['changed_at'] as String? ?? '');
              final action = a['action'] as String? ?? '--';
              final color = _auditColor(action);
              switch (col) {
                case 0:
                  return Text(
                    dt != null ? DateFormat('d MMM y, h:mm a').format(dt.toLocal()) : '--',
                    style: const TextStyle(fontSize: 12.5, color: WebColors.text2),
                  );
                case 1:
                  return WebLabel(action.replaceAll('_', ' ').toUpperCase(), color: color);
                case 2:
                  return Text(a['dc_number'] as String? ?? '—', style: const TextStyle(fontSize: 12.5, color: WebColors.navy, fontWeight: FontWeight.w600));
                case 3:
                  return Text(a['farmer_name'] as String? ?? '—', style: const TextStyle(fontSize: 13, color: WebColors.text1));
                default:
                  return Text(
                    a['new_value'] != null ? '${a['new_value']}' : (a['old_value'] != null ? '${a['old_value']}' : '—'),
                    style: const TextStyle(fontSize: 12.5, color: WebColors.text2),
                  );
              }
            },
          )
        else if (_historySubTab == 1)
          WebDataTable<Map<String, dynamic>>(
            columns: const [
              WebColumn('Payment Date', width: 130),
              WebColumn('Supplier', flex: 2),
              WebColumn('DC Number', width: 130),
              WebColumn('Amount', width: 140, align: TextAlign.right),
              WebColumn('Payment Mode', width: 130, align: TextAlign.center),
              WebColumn('Reference #', width: 150),
              WebColumn('Status', width: 120, align: TextAlign.center),
            ],
            rows: _payHistory,
            paginate: true,
            rowsPerPage: 25,
            emptyText: 'No payment records found',
            cellBuilder: (p, col) {
              final dt = DateTime.tryParse(p['payment_date'] as String? ?? '');
              final amt = (p['amount'] as num?)?.toDouble() ?? 0;
              final isRev = p['is_reversed'] == true;
              switch (col) {
                case 0:
                  return Text(
                    dt != null ? DateFormat('d MMM y').format(dt) : '--',
                    style: const TextStyle(fontSize: 12.5, color: WebColors.text2),
                  );
                case 1:
                  return Text(
                    p['farmer_name'] as String? ?? p['farm_name'] as String? ?? '--',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: WebColors.text1),
                  );
                case 2:
                  return Text(p['dc_number'] as String? ?? '—', style: const TextStyle(fontSize: 12.5, color: WebColors.navy, fontWeight: FontWeight.w600));
                case 3:
                  return Text(
                    Fmt.amount(amt),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: isRev ? WebColors.error : WebColors.success,
                      decoration: isRev ? TextDecoration.lineThrough : null,
                    ),
                  );
                case 4:
                  return WebLabel((p['payment_mode'] as String? ?? 'CASH').toUpperCase(), color: WebColors.navy);
                case 5:
                  return Text(p['reference_number'] as String? ?? '—', style: const TextStyle(fontSize: 12, color: WebColors.text3));
                default:
                  return isRev
                      ? const WebLabel('REVERSED', color: WebColors.error)
                      : const WebLabel('PAID', color: WebColors.success);
              }
            },
          )
        else
          WebDataTable<Map<String, dynamic>>(
            columns: const [
              WebColumn('Date & Time', width: 160),
              WebColumn('DC Number', width: 130),
              WebColumn('Supplier', flex: 2),
              WebColumn('Old Rate', width: 120, align: TextAlign.right),
              WebColumn('New Rate', width: 120, align: TextAlign.right),
              WebColumn('Difference', width: 120, align: TextAlign.right),
              WebColumn('Reason', flex: 2),
            ],
            rows: _rateHistory,
            paginate: true,
            rowsPerPage: 25,
            emptyText: 'No rate changes recorded',
            cellBuilder: (r, col) {
              final dt = DateTime.tryParse(r['changed_at'] as String? ?? '');
              final oldR = (r['old_rate'] as num?)?.toDouble() ?? 0;
              final newR = (r['new_rate'] as num?)?.toDouble() ?? 0;
              final diff = newR - oldR;
              switch (col) {
                case 0:
                  return Text(
                    dt != null ? DateFormat('d MMM y, h:mm a').format(dt.toLocal()) : '--',
                    style: const TextStyle(fontSize: 12.5, color: WebColors.text2),
                  );
                case 1:
                  return Text(r['dc_number'] as String? ?? '—', style: const TextStyle(fontSize: 12.5, color: WebColors.navy, fontWeight: FontWeight.w600));
                case 2:
                  return Text(r['farmer_name'] as String? ?? '—', style: const TextStyle(fontSize: 13, color: WebColors.text1));
                case 3:
                  return Text('Rs.${oldR.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12.5, color: WebColors.text2));
                case 4:
                  return Text('Rs.${newR.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: WebColors.text1));
                case 5:
                  return Text(
                    '${diff >= 0 ? '+' : ''}Rs.${diff.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: diff >= 0 ? WebColors.error : WebColors.success),
                  );
                default:
                  return Text(r['change_reason'] as String? ?? '—', style: const TextStyle(fontSize: 12.5, color: WebColors.text2));
              }
            },
          ),
      ]),
    );
  }

  Widget _webFilterChip(String label, bool active, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: active ? WebColors.navySoft : WebColors.surface,
        borderRadius: BorderRadius.circular(WebRadius.button),
        border: Border.all(color: active ? WebColors.navy : WebColors.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: active ? FontWeight.w700 : FontWeight.w600,
          color: active ? WebColors.navy : WebColors.text2,
        ),
      ),
    ),
  );

  Widget _buildScaffold(BuildContext context) => Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
          backgroundColor: kSurface,
          title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Purchase Management',
                    style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                Text('Procurement + Accounting + Profitability',
                    style: TextStyle(fontSize: 9, color: kTextHint)),
              ]),
          actions: [
            IconButton(
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                onPressed: _pickRange),
            if (_tab.index == 5)
              IconButton(
                  icon: const Icon(Icons.share_outlined),
                  tooltip: 'Export Report',
                  onPressed: _exportReport),
            PopupMenuButton<String>(
                icon: const Icon(Icons.add),
                onSelected: (v) {
                  if (v == 'farm') _showAddFarm();
                  if (v == 'company') _showAddCompany();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                      value: 'farm', child: Text('Add Supplier')),
                  const PopupMenuItem(
                      value: 'company', child: Text('Add Company')),
                ]),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          ],
          bottom: TabBar(
              controller: _tab,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelStyle:
              const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
              unselectedLabelStyle:
              const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
              tabs: _tabs.map((t) => Tab(text: t)).toList())),
      body: _loading
          ? const LoadingList()
          : TabBarView(controller: _tab, children: [
        _tabOverview(),
        _tabPurchases(),
        _tabSuppliers(),
        _tabLedger(),
        _tabCosting(),
        _tabReports(),
        _tabHistory(),
      ]));

  // ==========================================================================
  // TAB 0: OVERVIEW
  // ==========================================================================
  Widget _tabOverview() {
    final s = _summary;
    final o = _overview;
    if (s == null && o == null) {
      return const EmptyState(
          icon: Icons.analytics_outlined, message: 'No data');
    }
    final total = (s?['total_purchase_amt'] as num?)?.toDouble() ?? 0;
    final paid = (s?['total_paid'] as num?)?.toDouble() ?? 0;
    final claim = (s?['total_claim'] as num?)?.toDouble() ?? 0;
    final due = (s?['total_outstanding'] as num?)?.toDouble() ?? 0;
    final avgCost = (s?['avg_cost_per_kg'] as num?)?.toDouble();
    final pending = (s?['pending_rate'] as num?)?.toInt() ?? 0;
    final overdue = (s?['overdue_count'] as num?)?.toInt() ?? 0;
    final prof = o?['profitability'] as Map<String, dynamic>?;
    final netProfit = (prof?['net_profit'] as num?)?.toDouble() ?? 0;
    final totalRevenue = (prof?['total_revenue'] as num?)?.toDouble() ?? 0;
    final farms = (o?['farms'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final trend =
        (o?['monthly_trend'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, kBottomNavClearance), children: [
          // Date range label
          Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(kRadiusInner),
                  border: Border.all(color: kBorder)),
              child: Row(children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 13, color: kTextHint),
                const SizedBox(width: 6),
                Text(
                    '${DateFormat("d MMM").format(_from)} - ${DateFormat("d MMM").format(_to)}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                const Spacer(),
                GestureDetector(
                    onTap: _pickRange,
                    child: const Text('Change',
                        style: TextStyle(fontSize: 11, color: kNavy))),
              ])),

          // Alerts row
          if (pending > 0 || overdue > 0) ...[
            if (pending > 0)
              _alertBanner(
                  Icons.pending_outlined,
                  '$pending DC(s) pending rate entry',
                  Colors.orange, onTap: () {
                _tab.animateTo(1);
                setState(() {
                  _filterStatus = 'draft';
                });
                _load();
              }),
            if (overdue > 0)
              _alertBanner(Icons.warning_amber_rounded,
                  '$overdue payment(s) overdue', Colors.red, onTap: () {
                    _tab.animateTo(1);
                    setState(() {
                      _filterPayStatus = 'overdue';
                    });
                    _load();
                  }),
            const SizedBox(height: 8),
          ],

          // Financial KPI grid (2x3)
          _sectionHeader('FINANCIAL OVERVIEW'),
          GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.25,
              children: [
                _kpiCard('Total Purchase', Fmt.amount(total), Colors.blue,
                    Icons.shopping_cart_outlined),
                _kpiCard('Total Paid', Fmt.amount(paid), Colors.green,
                    Icons.payments_outlined),
                _kpiCard(
                    'Outstanding',
                    Fmt.amount(due),
                    due > 0 ? Colors.orange : Colors.green,
                    Icons.account_balance_outlined),
                _kpiCard(
                    'Avg Cost/kg',
                    avgCost != null ? 'Rs.${avgCost.toStringAsFixed(2)}' : '--',
                    Colors.purple,
                    Icons.scale_outlined),
                _kpiCard('Claims', Fmt.amount(claim), Colors.red,
                    Icons.report_problem_outlined),
                _kpiCard(
                    'Net Profit',
                    Fmt.amount(netProfit),
                    netProfit >= 0 ? Colors.teal : Colors.red,
                    Icons.trending_up),
              ]),
          const SizedBox(height: 12),

          // Farm summary
          if (farms.isNotEmpty) ...[
            _sectionHeader('SUPPLIER OUTSTANDING',
                action: 'View All', onAction: () => _tab.animateTo(2)),
            ...farms.take(5).map((f) {
              final outstanding = (f['outstanding'] as num?)?.toDouble() ?? 0;
              final total2 = (f['total_amount'] as num?)?.toDouble() ?? 0;
              return GestureDetector(
                  onTap: () {
                    _tab.animateTo(2);
                  },
                  child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(kRadiusCard),
                          border: Border.all(color: kBorder)),
                      child: Row(children: [
                        CircleAvatar(
                            radius: 16,
                            backgroundColor: kNavy.withValues(alpha: 0.08),
                            child: Text(
                                (f['farmer_name'] as String? ?? '?')[0]
                                    .toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: kNavy))),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(f['farmer_name'] as String? ?? '--',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700)),
                                  Text(
                                      '${(f['dc_count'] as num?)?.toInt() ?? 0} DCs  |  ${Fmt.amount(total2)} total',
                                      style: const TextStyle(
                                          fontSize: 10, color: kTextHint)),
                                ])),
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(Fmt.amount(outstanding),
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: outstanding > 0
                                          ? Colors.orange
                                          : Colors.green)),
                              Text(outstanding > 0 ? 'outstanding' : 'settled',
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: outstanding > 0
                                          ? Colors.orange
                                          : Colors.green)),
                            ]),
                      ])));
            }),
          ],

          // Monthly trend mini chart
          if (trend.isNotEmpty) ...[
            const SizedBox(height: 12),
            _sectionHeader('MONTHLY TREND'),
            Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(kRadiusCard),
                    border: Border.all(color: kBorder)),
                child: Column(children: [
                  Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: trend.map((t) {
                        final amt =
                            (t['total_amount'] as num?)?.toDouble() ?? 0;
                        final maxAmt = trend
                            .map((x) =>
                        (x['total_amount'] as num?)?.toDouble() ?? 0)
                            .reduce((a, b) => a > b ? a : b)
                            .clamp(1.0, double.infinity);
                        final frac = amt / maxAmt;
                        final dt =
                        DateTime.tryParse((t['month'] as String?) ?? '');
                        return Expanded(
                            child: Padding(
                                padding:
                                const EdgeInsets.symmetric(horizontal: 2),
                                child: Column(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      if (amt > 0)
                                        Text(Fmt.amount(amt),
                                            style: const TextStyle(
                                                fontSize: 7, color: kTextHint),
                                            textAlign: TextAlign.center),
                                      const SizedBox(height: 2),
                                      ClipRRect(
                                          borderRadius:
                                          BorderRadius.circular(3),
                                          child: Container(
                                              height:
                                              (60 * frac).clamp(4.0, 60.0),
                                              color: kNavy)),
                                      const SizedBox(height: 3),
                                      Text(
                                          dt != null
                                              ? DateFormat('MMM').format(dt)
                                              : '',
                                          style: const TextStyle(
                                              fontSize: 7, color: kTextHint),
                                          textAlign: TextAlign.center),
                                    ])));
                      }).toList()),
                ])),
          ],
          const SizedBox(height: 16),

          // ── STOCK VALUATION ──────────────────────────────────────────────────
          if (_stockVal != null) ...[
            _sectionHeader('STOCK VALUATION'),
            Container(
                margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(kRadiusCard),
                    border: Border.all(color: Colors.teal.shade200)),
                child: Column(children: [
                  Row(children: [
                    _ovKpi(
                        'Available Birds',
                        '${_stockVal!['total_available_birds'] ?? 0}',
                        Colors.teal,
                        Icons.pets_outlined),
                    _ovKpi(
                        'Available Weight',
                        '${((_stockVal!['total_available_kg'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} kg',
                        Colors.blue,
                        Icons.monitor_weight_outlined),
                    _ovKpi(
                        'Stock Value',
                        Fmt.amount(
                            (_stockVal!['total_stock_value'] as num?)
                                ?.toDouble() ??
                                0),
                        Colors.purple,
                        Icons.currency_rupee),
                  ]),
                  const SizedBox(height: 8),
                  ..._buildStockProductTiles(),
                ])),
          ],

          // ── SUPPLIER DUES (outstanding per farm) ─────────────────────────────
          // Supplier dues — built separately to avoid nested spread issues
          ..._buildSupplierDuesTiles(),

          const SizedBox(height: 20),
        ]));
  }

  // Helper: supplier dues tiles for Overview tab
  // (Extracted to avoid nested spread-inside-spread, which is invalid Dart syntax)
  List<Widget> _buildSupplierDuesTiles() {
    final farms = (_overview?['farms'] as List? ?? []);
    if (farms.isEmpty) return [];
    final tiles = <Widget>[
      const SizedBox(height: 8),
      _sectionHeader('SUPPLIER DUES'),
    ];
    for (final f in farms.take(5)) {
      final farm = f as Map<String, dynamic>;
      final due = (farm['outstanding'] as num?)?.toDouble() ?? 0;
      final amt = (farm['total_amount'] as num?)?.toDouble() ?? 0;
      final dueDate = farm['earliest_due'] as String?;
      if (amt == 0) continue;
      tiles.add(Container(
          margin: const EdgeInsets.fromLTRB(14, 2, 14, 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(
                  color: due > 0 ? Colors.orange.shade200 : kBorder)),
          child: Row(children: [
            CircleAvatar(
                radius: 16,
                backgroundColor: kNavy.withValues(alpha: 0.06),
                child: Text(
                    (farm['farmer_name'] as String? ?? '?')[0].toUpperCase(),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: kNavy))),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(farm['farmer_name'] as String? ?? '—',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700)),
                      if (dueDate != null)
                        Text('Due: $dueDate',
                            style: TextStyle(
                                fontSize: 9,
                                color: due > 0 ? Colors.orange : Colors.green)),
                    ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(Fmt.amount(due),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: due > 0 ? Colors.orange : Colors.green)),
              Text('of ${Fmt.amount(amt)}',
                  style: const TextStyle(fontSize: 9, color: kTextHint)),
            ]),
          ])));
    }
    if (farms.length > 5) {
      tiles.add(Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
          child: GestureDetector(
              onTap: () => _tab.animateTo(1),
              child: const Text('View all suppliers',
                  style: TextStyle(
                      fontSize: 11,
                      color: kPrimary,
                      fontWeight: FontWeight.w700)))));
    }
    return tiles;
  }

  // Helper: stock product tiles for Overview tab stock valuation section
  List<Widget> _buildStockProductTiles() {
    final products = _stockVal?['products'] as List? ?? [];
    return products.map((p) {
      final prod = p as Map<String, dynamic>;
      final val = (prod['stock_value'] as num?)?.toDouble() ?? 0;
      final kg = (prod['available_kg'] as num?)?.toDouble() ?? 0;
      final cost = (prod['avg_cost_per_kg'] as num?)?.toDouble() ?? 0;
      return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            Expanded(
                child: Text(prod['product_name'] as String? ?? 'Product',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700))),
            Text(
                '${kg.toStringAsFixed(0)} kg  @  Rs.${cost.toStringAsFixed(2)}/kg',
                style: const TextStyle(fontSize: 10, color: kTextSub)),
            const SizedBox(width: 10),
            Text(Fmt.amount(val),
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.purple)),
          ]));
    }).toList();
  }

  // ==========================================================================
  // TAB 1: PURCHASES
  // ==========================================================================
  Widget _tabPurchases() {
    final pending = _purchases.where((p) => p['status'] == 'draft').length;
    return Column(children: [
      if (_summary != null) _buildSummaryHeader(),
      _buildFilterBar(),
      if (pending > 0)
        _alertBanner(
            Icons.pending_outlined,
            '$pending DC(s) pending rate entry -- tap to confirm',
            Colors.orange),
      Expanded(
          child: RefreshIndicator(
              onRefresh: _load,
              child: _purchases.isEmpty
                  ? const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  message: 'No purchases')
                  : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, kBottomNavClearance),
                  itemCount: _purchases.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (_, i) => _purchaseCard(_purchases[i])))),
    ]);
  }

  Widget _buildFilterBar() => Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            // Date range chip
            _filterChip(
                '${DateFormat('d MMM').format(_from)} - ${DateFormat('d MMM').format(_to)}',
                active: true,
                onTap: _pickRange),
            const SizedBox(width: 6),
            // Status filter
            _filterChip(_filterStatus ?? 'All Status',
                active: _filterStatus != null,
                onTap: () => _showFilterPicker(
                    'status',
                    ['All', 'draft', 'confirmed', 'finalized', 'locked'],
                    _filterStatus,
                        (v) => setState(() {
                      _filterStatus = v == 'All' ? null : v;
                      _load();
                    }))),
            const SizedBox(width: 6),
            _filterChip(_filterPayStatus ?? 'All Payment',
                active: _filterPayStatus != null,
                onTap: () => _showFilterPicker(
                    'payment',
                    ['All', 'pending', 'partial', 'paid', 'overdue'],
                    _filterPayStatus,
                        (v) => setState(() {
                      _filterPayStatus = v == 'All' ? null : v;
                      _load();
                    }))),
            const SizedBox(width: 6),
            if (_filterStatus != null || _filterPayStatus != null)
              GestureDetector(
                  onTap: () => setState(() {
                    _filterStatus = null;
                    _filterPayStatus = null;
                    _load();
                  }),
                  child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(kRadiusCard),
                          border: Border.all(color: Colors.red.shade200)),
                      child: const Text('Clear',
                          style: TextStyle(
                              fontSize: 10,
                              color: Colors.red,
                              fontWeight: FontWeight.w700)))),
          ])));

  Widget _filterChip(String label,
      {bool active = false, VoidCallback? onTap}) =>
      GestureDetector(
          onTap: onTap,
          child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: active ? kPrimary : Colors.white,
                  borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(color: active ? kPrimary : kBorder)),
              child: Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: active ? Colors.white : kTextSub))));

  void _showFilterPicker(String title, List<String> options, String? current,
      Function(String) onSelect) {
    _showSheet(
        maxWidth: WebSize.dialogSm,
        builder: (ctx) => ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              Text('Filter by $title',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              ...options.map((o) => ListTile(
                dense: true,
                title: Text(o, style: const TextStyle(fontSize: 13)),
                trailing: (current ?? 'All') == o
                    ? const Icon(Icons.check, color: kPrimary, size: 18)
                    : null,
                onTap: () {
                  Navigator.of(ctx, rootNavigator: true).pop();
                  onSelect(o);
                },
              )),
            ]));
  }

  Widget _buildSummaryHeader() {
    final s = _summary!;
    final total = (s['total_purchase_amt'] as num?)?.toDouble() ?? 0;
    final paid = (s['total_paid'] as num?)?.toDouble() ?? 0;
    final due = (s['total_outstanding'] as num?)?.toDouble() ?? 0;
    final avgCost = (s['avg_cost_per_kg'] as num?)?.toDouble();
    final dcs = (s['total_dcs'] as num?)?.toInt() ?? 0;
    final kg = (s['total_weight_kg'] as num?)?.toDouble() ?? 0;
    final pendRate = (s['pending_rate'] as num?)?.toInt() ?? 0;

    return Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(children: [
          Row(children: [
            _hStat('Total Purchase', Fmt.amount(total), Colors.blue),
            _hStat('Paid', Fmt.amount(paid), Colors.green),
            _hStat('Outstanding', Fmt.amount(due),
                due > 0 ? Colors.red : Colors.green),
            _hStat(
                'Avg Cost/kg',
                avgCost != null ? 'Rs.${avgCost.toStringAsFixed(2)}' : '--',
                Colors.purple),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            _hStat('Total DCs', '$dcs', kPrimary),
            _hStat('Weight', '${kg.toStringAsFixed(0)} kg', Colors.teal),
            _hStat('Pending Rate', '$pendRate',
                pendRate > 0 ? Colors.orange : Colors.green),
            _hStat('', '', Colors.transparent),
          ]),
        ]));
  }

  Widget _hStat(String l, String v, Color c) => Expanded(
      child: Column(children: [
        Text(v,
            style:
            TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c),
            textAlign: TextAlign.center),
        Text(l,
            style: const TextStyle(fontSize: 8, color: kTextHint),
            textAlign: TextAlign.center),
      ]));

  Widget _purchaseCard(Map<String, dynamic> p) {
    final status = p['status'] as String? ?? 'draft';
    final isDraft = status == 'draft';
    final isLocked = status == 'locked';
    final kg = (p['net_weight_kg'] as num?)?.toDouble() ?? 0;
    final arrWt = (p['arrival_weight_kg'] as num?)?.toDouble() ?? 0;
    final shortage = (p['shortage_kg'] as num?)?.toDouble() ?? 0;
    final rate = (p['purchase_rate_per_kg'] as num?)?.toDouble();
    final total = (p['total_landed_cost'] as num?)?.toDouble() ?? 0;
    final paid = (p['total_paid'] as num?)?.toDouble() ?? 0;
    final claim = (p['claim_amount'] as num?)?.toDouble() ?? 0;
    final pStatus = p['payment_status'] as String? ?? 'pending';
    final due = (total - paid - claim).clamp(0.0, double.infinity);
    final dcDate = DateTime.tryParse(p['dc_date'] as String? ?? '');
    final farmMap = p['farms'] as Map<String, dynamic>?;
    final farmName = farmMap?['farmer_name'] as String? ??
        p['farmer_name'] as String? ??
        '--';
    final dueDate = p['payment_due_date'] as String?;
    final isOverdue = pStatus == 'overdue';

    return GestureDetector(
        onTap: isDraft ? () => _showRateEntry(p) : () => _showPurchaseDetail(p),
        onLongPress: () => _showRateHistory(
            p['id'] as String, p['dc_number'] as String? ?? '--'),
        child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: kSurface,
                borderRadius: BorderRadius.circular(kRadiusCard),
                border: Border.all(
                    color: isDraft
                        ? Colors.orange.shade300
                        : isOverdue
                        ? Colors.red.shade300
                        : kBorder,
                    width: isDraft || isOverdue ? 1.5 : 1),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6)
                ]),
            child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p['dc_number'] as String? ?? '--',
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w800)),
                          Text(
                              '$farmName  |  ${dcDate != null ? DateFormat("d MMM").format(dcDate) : "--"}',
                              style:
                              const TextStyle(fontSize: 10, color: kTextHint)),
                        ])),
                _statusChip(
                    isDraft ? 'RATE PENDING' : status.toUpperCase(),
                    isDraft
                        ? Colors.orange
                        : isLocked
                        ? Colors.grey
                        : Colors.green),
              ]),
              if (shortage > 0)
                Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _miniAlert(
                        'Shortage: ${shortage.toStringAsFixed(1)} kg',
                        Colors.red)),
              const SizedBox(height: 8),
              Row(children: [
                _pStat('Birds', '${p['bird_count'] ?? 0}', kPrimary),
                _pStat('Farm Wt', '${kg.toStringAsFixed(1)} kg', Colors.blue),
                _pStat(
                    'Arrival',
                    arrWt > 0 ? '${arrWt.toStringAsFixed(1)} kg' : '--',
                    Colors.teal),
                _pStat(
                    'Rate',
                    rate != null ? 'Rs.${rate.toStringAsFixed(2)}/kg' : '--',
                    isDraft ? Colors.orange : Colors.teal),
              ]),
              if (total > 0) ...[
                const SizedBox(height: 6),
                Row(children: [
                  _pStat('Total', Fmt.amount(total), Colors.purple),
                  _pStat('Paid', Fmt.amount(paid), Colors.green),
                  _pStat('Due', Fmt.amount(due),
                      due > 0 ? Colors.red : Colors.green),
                  _pStat('Claim', claim > 0 ? Fmt.amount(claim) : '--',
                      claim > 0 ? Colors.orange : kTextHint),
                ]),
                const SizedBox(height: 6),
                ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                        value: total > 0 ? (paid / total).clamp(0.0, 1.0) : 0,
                        minHeight: 4,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation(pStatus == 'paid'
                            ? Colors.green
                            : isOverdue
                            ? Colors.red
                            : Colors.orange))),
                const SizedBox(height: 4),
                Row(children: [
                  Text(
                      isOverdue
                          ? 'OVERDUE'
                          : pStatus == 'paid'
                          ? 'Paid'
                          : '${Fmt.amount(due)} due',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isOverdue
                              ? Colors.red
                              : pStatus == 'paid'
                              ? Colors.green
                              : Colors.orange)),
                  const Spacer(),
                  if (dueDate != null && pStatus != 'paid')
                    Text('Due: $dueDate',
                        style: TextStyle(
                            fontSize: 9,
                            color: isOverdue ? Colors.red : kTextHint)),
                ]),
              ],
              if (isDraft)
                const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Row(children: [
                      Icon(Icons.edit_outlined,
                          size: 12, color: Colors.orange),
                      SizedBox(width: 4),
                      Text('Tap to enter purchase rate',
                          style: TextStyle(fontSize: 10, color: Colors.orange)),
                    ])),
              if (!isDraft && !isLocked)
                Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (due > 0)
                            _actionBtn(
                                'Pay', Colors.green, () => _showPayment(p)),
                          const SizedBox(width: 6),
                          _actionBtn(
                              'Claim', Colors.orange, () => _showClaim(p)),
                          const SizedBox(width: 6),
                          _actionBtn('Lock', Colors.grey, () => _lockEntry(p)),
                        ])),
              if (isLocked)
                Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(children: [
                      const Icon(Icons.lock, size: 10, color: kTextHint),
                      const SizedBox(width: 4),
                      const Text('Locked',
                          style: TextStyle(fontSize: 10, color: kTextHint)),
                      const Spacer(),
                      GestureDetector(
                          onTap: () => _unlockEntry(p),
                          child: const Text('Reopen',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: kPrimary,
                                  fontWeight: FontWeight.w700))),
                    ])),
            ])));
  }

  Widget _actionBtn(String l, Color c, VoidCallback onTap) => GestureDetector(
      onTap: onTap,
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: c.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: c.withValues(alpha: 0.3))),
          child: Text(l,
              style: TextStyle(
                  fontSize: 10, color: c, fontWeight: FontWeight.w700))));

  Widget _miniAlert(String msg, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6)),
      child: Text(msg,
          style:
          TextStyle(fontSize: 9, color: c, fontWeight: FontWeight.w700)));

  // ==========================================================================
  // TAB 2: SUPPLIERS
  // ==========================================================================
  Widget _tabSuppliers() {
    if (_farms.isEmpty) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const EmptyState(
                icon: Icons.agriculture_outlined, message: 'No suppliers added'),
            const SizedBox(height: 12),
            ElevatedButton.icon(
                onPressed: _showAddFarm,
                icon: const Icon(Icons.add),
                label: const Text('Add Supplier')),
          ]));
    }
    return ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, kBottomNavClearance),
        itemCount: _farms.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (_, i) {
          final f = _farms[i];
          final st = f['_stats'] as Map<String, dynamic>? ?? {};
          final total = (st['total'] as double?) ?? 0;
          final pd = (st['paid'] as double?) ?? 0;
          final cl = (st['claim'] as double?) ?? 0;
          final outstanding = (total - pd - cl).clamp(0.0, double.infinity);
          final overdueCnt = (st['overdue'] as int?) ?? 0;
          final co =
          (f['poultry_companies'] as Map?)?['company_name'] as String?;

          return GestureDetector(
              onTap: () => _showSupplierDashboard(f),
              child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(kRadiusCard),
                      border: Border.all(
                          color:
                          overdueCnt > 0 ? Colors.red.shade200 : kBorder)),
                  child: Column(children: [
                    Row(children: [
                      CircleAvatar(
                          radius: 20,
                          backgroundColor: kNavy.withValues(alpha: 0.08),
                          child: Text(
                              (f['farmer_name'] as String? ?? '?')[0]
                                  .toUpperCase(),
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: kNavy))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(f['farmer_name'] as String? ?? '--',
                                    style: const TextStyle(
                                        fontSize: 13, fontWeight: FontWeight.w800)),
                                if (f['farm_name'] != null)
                                  Text(f['farm_name'] as String,
                                      style: const TextStyle(
                                          fontSize: 10, color: kTextHint)),
                                if (co != null)
                                  Text(co,
                                      style: const TextStyle(
                                          fontSize: 10, color: Colors.blue)),
                              ])),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                                outstanding > 0
                                    ? Fmt.amount(outstanding)
                                    : 'Settled',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    color: outstanding > 0
                                        ? Colors.orange
                                        : Colors.green)),
                            Text(outstanding > 0 ? 'outstanding' : '',
                                style: const TextStyle(
                                    fontSize: 9, color: kTextHint)),
                          ]),
                    ]),
                    if (total > 0) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        _pStat('Purchase', Fmt.amount(total), Colors.blue),
                        _pStat('Paid', Fmt.amount(pd), Colors.green),
                        _pStat('Claims', cl > 0 ? Fmt.amount(cl) : '--',
                            cl > 0 ? Colors.orange : kTextHint),
                        _pStat('Credit', '${f['credit_days'] ?? 7}d', kTextSub),
                      ]),
                    ],
                    if (overdueCnt > 0)
                      Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: _miniAlert(
                              '$overdueCnt overdue payment(s)', Colors.red)),
                    Wrap(alignment: WrapAlignment.end, spacing: 6, runSpacing: 6, children: [
                      _actionBtn('View Ledger', Colors.blue, () {
                        setState(() => _farmFilter = f['id'] as String?);
                        _tab.animateTo(3);
                        _load();
                      }),
                      _actionBtn(
                          'Pay', Colors.green, () => _showPaymentForFarm(f)),
                      _actionBtn('Edit', kPrimary, () => _showEditFarm(f)),
                      _actionBtn('Statement', const Color(0xFF6A1B9A), () {
                        final fid = f['id'] as String?;
                        if (fid != null) {
                          context.push(R.supplierStatementPath(fid));
                        }
                      }),
                    ]),
                  ])));
        });
  }

  // ==========================================================================
  // TAB 3: LEDGER
  // ==========================================================================
  Widget _tabLedger() {
    final allFarms = <String, String>{};
    for (final e in _ledger) {
      final fid = e['farm_id'] as String?;
      final fn = (e['farms'] as Map?)?['farmer_name'] as String?;
      if (fid != null && fn != null) allFarms[fid] = fn;
    }
    if (_ledger.isEmpty && _farmFilter == null) {
      return const EmptyState(
          icon: Icons.book_outlined, message: 'No ledger entries');
    }

    double balance = 0;
    final rows = _ledger.reversed
        .map((e) {
      final amt = (e['amount'] as num?)?.toDouble() ?? 0;
      if (e['entry_type'] == 'debit') {
        balance += amt;
      } else {
        balance -= amt;
      }
      return {...e, '_balance': balance};
    })
        .toList()
        .reversed
        .toList();

    return Column(children: [
      _buildLedgerFilterBar(allFarms),
      // Balance header
      Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(children: [
            const Icon(Icons.account_balance_outlined, size: 14),
            const SizedBox(width: 8),
            const Text('OUTSTANDING',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
            const Spacer(),
            Text(Fmt.amount(balance),
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: balance > 0 ? Colors.orange : Colors.green)),
          ])),
      Expanded(
          child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final e = rows[i];
                final isD = e['entry_type'] == 'debit';
                final amt = (e['amount'] as num?)?.toDouble() ?? 0;
                final bal = (e['_balance'] as double?) ?? 0;
                final dt = DateTime.tryParse(e['entry_date'] as String? ?? '');
                final farm = (e['farms'] as Map?)?['farmer_name'] as String?;
                final dc =
                (e['purchase_entries'] as Map?)?['dc_number'] as String?;
                final c = isD ? Colors.red : Colors.green;
                return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(kRadiusCard),
                      border: Border.all(color: kBorder),
                    ),
                    child: Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e['reason'] as String? ?? '--',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: c)),
                                Text(
                                    [farm, dc, e['description'] as String?]
                                        .where((s) => s != null && s.isNotEmpty)
                                        .cast<String>()
                                        .join(' | '),
                                    style: const TextStyle(
                                        fontSize: 9, color: kTextHint),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ])),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${isD ? "+" : "-"}${Fmt.amount(amt)}',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: c)),
                            Text('Bal: ${Fmt.amount(bal)}',
                                style: const TextStyle(
                                    fontSize: 9, color: kTextHint)),
                            if (dt != null)
                              Text(DateFormat('d MMM').format(dt),
                                  style: const TextStyle(
                                      fontSize: 9, color: kTextHint)),
                          ]),
                    ]));
              })),
    ]);
  }

  Widget _buildLedgerFilterBar(Map<String, String> allFarms) {
    if (allFarms.isEmpty) return const SizedBox.shrink();
    return Container(
        color: Colors.white,
        height: 38,
        child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            children: [
              GestureDetector(
                  onTap: () => setState(() {
                    _farmFilter = null;
                    _load();
                  }),
                  child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: _farmFilter == null ? kPrimary : Colors.white,
                          borderRadius: BorderRadius.circular(kRadiusCard),
                          border: Border.all(
                              color: _farmFilter == null ? kPrimary : kBorder)),
                      child: Text('All',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _farmFilter == null
                                  ? Colors.white
                                  : kTextSub)))),
              ...allFarms.entries.map((e) {
                final sel = _farmFilter == e.key;
                return GestureDetector(
                    onTap: () => setState(() {
                      _farmFilter = sel ? null : e.key;
                      _load();
                    }),
                    child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                            color: sel ? kPrimary : Colors.white,
                            borderRadius: BorderRadius.circular(kRadiusCard),
                            border:
                            Border.all(color: sel ? kPrimary : kBorder)),
                        child: Text(e.value,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: sel ? Colors.white : kTextSub))));
              }),
            ]));
  }

  // ==========================================================================
  // TAB 4: COSTING
  // ==========================================================================
  Widget _tabCosting() {
    if (_costing.isEmpty) {
      return const EmptyState(
          icon: Icons.calculate_outlined,
          message:
          'No costing data\nConfirm purchase rates to see profitability');
    }
    final totalRevenue = _costing.fold<double>(
        0, (s, c) => s + ((c['revenue'] as num?)?.toDouble() ?? 0));
    final totalCost = _costing.fold<double>(
        0, (s, c) => s + ((c['total_cost'] as num?)?.toDouble() ?? 0));
    final totalProfit = _costing.fold<double>(
        0, (s, c) => s + ((c['net_profit'] as num?)?.toDouble() ?? 0));

    return Column(children: [
      Container(
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            _hStat('Revenue', Fmt.amount(totalRevenue), Colors.blue),
            _hStat('Cost', Fmt.amount(totalCost), kPrimary),
            _hStat('Profit', Fmt.amount(totalProfit),
                totalProfit >= 0 ? Colors.green : Colors.red),
            _hStat(
                'Margin',
                totalRevenue > 0
                    ? '${(totalProfit / totalRevenue * 100).toStringAsFixed(1)}%'
                    : '--',
                totalProfit >= 0 ? Colors.green : Colors.red),
          ])),
      Expanded(
        child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, kBottomNavClearance),
            itemCount: _costing.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (_, i) {
              final c = _costing[i];
              // FIX: use _pe (pre-fetched per batch) not purchase_entries join array
              final pe = c['_pe'] as Map<String, dynamic>?;
              final peName = pe?['farmer_name'] as String?;
              final dcNum = pe?['dc_number'] as String?;
              final dcDate = pe?['dc_date'] as String?;
              final batch = peName ??
                  (c['delivery_batches'] as Map?)?['farm_name'] as String? ??
                  '--';
              final costKg = (c['cost_per_kg'] as num?)?.toDouble();
              final revKg = (c['revenue_per_kg'] as num?)?.toDouble();
              final profit = (c['net_profit'] as num?)?.toDouble() ?? 0;
              final revenue = (c['revenue'] as num?)?.toDouble() ?? 0;
              final margin = (c['profit_margin_pct'] as num?)?.toDouble();
              final isPend = c['status'] == 'pending';
              final delKg = (c['delivered_kg'] as num?)?.toDouble() ?? 0;

              return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(kRadiusCard),
                      border: Border.all(
                          color: isPend ? Colors.orange.shade200 : kBorder)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(batch,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800)),
                                    if (dcNum != null)
                                      Text('DC: $dcNum',
                                          style: const TextStyle(
                                              fontSize: 10, color: kTextHint)),
                                  ])),
                          _statusChip(
                              isPend
                                  ? 'PENDING'
                                  : (c['status'] as String? ?? '')
                                  .toUpperCase(),
                              isPend ? Colors.orange : Colors.green),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          _pStat(
                              'DC Weight',
                              '${(c['dc_weight_kg'] as num?)?.toStringAsFixed(1) ?? 0} kg',
                              Colors.blue),
                          _pStat('Delivered', '${delKg.toStringAsFixed(1)} kg',
                              Colors.teal),
                          _pStat(
                              'Cost/kg',
                              costKg != null
                                  ? 'Rs.${costKg.toStringAsFixed(2)}'
                                  : '--',
                              kPrimary),
                          _pStat(
                              'Sale/kg',
                              revKg != null
                                  ? 'Rs.${revKg.toStringAsFixed(2)}'
                                  : '--',
                              Colors.purple),
                        ]),
                        if (!isPend) ...[
                          const SizedBox(height: 6),
                          if (revenue > 0)
                            Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                    color: profit >= 0
                                        ? Colors.green.shade50
                                        : Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(8)),
                                child: Row(children: [
                                  Icon(
                                      profit >= 0
                                          ? Icons.trending_up
                                          : Icons.trending_down,
                                      color: profit >= 0
                                          ? Colors.green
                                          : Colors.red,
                                      size: 14),
                                  const SizedBox(width: 6),
                                  Expanded(
                                      child: Text(
                                          'Net Profit: ${Fmt.amount(profit)}',
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: profit >= 0
                                                  ? Colors.green
                                                  : Colors.red))),
                                  if (margin != null)
                                    Text('${margin.toStringAsFixed(1)}%',
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: profit >= 0
                                                ? Colors.green
                                                : Colors.red)),
                                ]))
                          else
                            Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(8)),
                                child: const Row(children: [
                                  Icon(Icons.pending_outlined,
                                      size: 13, color: Colors.blue),
                                  SizedBox(width: 6),
                                  Text(
                                      'Profit pending - deliveries not completed',
                                      style: TextStyle(
                                          fontSize: 10, color: Colors.blue)),
                                ])),
                        ],
                        const SizedBox(height: 4),
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(6)),
                            child: Row(
                                mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                      child: Text(
                                          isPend
                                              ? 'Rate pending'
                                              : delKg == 0
                                              ? 'In progress - profit updates after delivery'
                                              : 'Delivery complete',
                                          style: const TextStyle(
                                              fontSize: 9, color: kTextSub))),
                                  GestureDetector(
                                      onTap: () async {
                                        try {
                                          await _c.rpc(
                                              'recalculate_batch_costing',
                                              params: {
                                                'p_batch_id': c['batch_id']
                                              });
                                          _load();
                                          if (mounted) {
                                            showSuccess(
                                                context, 'Recalculated');
                                          }
                                        } catch (e) {
                                          if (mounted) {
                                            showError(
                                                context,
                                                e.toString().replaceAll(
                                                    'Exception: ', ''));
                                          }
                                        }
                                      },
                                      child: const Row(children: [
                                        Icon(Icons.refresh,
                                            size: 11, color: kTextHint),
                                        SizedBox(width: 3),
                                        Text('Recalc',
                                            style: TextStyle(
                                                fontSize: 9, color: kTextHint)),
                                      ])),
                                ])),
                      ]));
            }),
      ),
    ]);
  }

  // ==========================================================================
  // TAB 5: REPORTS
  // ==========================================================================
  Widget _tabReports() {
    final rd = _reportData;
    final aggs = rd?['aggregates'] as Map<String, dynamic>?;
    final entries =
    List<Map<String, dynamic>>.from(rd?['entries'] as List? ?? []);

    return Column(children: [
      _buildFilterBar(),
      if (aggs != null)
        Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Row(children: [
              _hStat(
                  'Total',
                  Fmt.amount((aggs['total_amount'] as num?)?.toDouble() ?? 0),
                  Colors.blue),
              _hStat(
                  'Paid',
                  Fmt.amount((aggs['total_paid'] as num?)?.toDouble() ?? 0),
                  Colors.green),
              _hStat(
                  'Due',
                  Fmt.amount(
                      (aggs['total_outstanding'] as num?)?.toDouble() ?? 0),
                  ((aggs['total_outstanding'] as num?)?.toDouble() ?? 0) > 0
                      ? Colors.red
                      : Colors.green),
              _hStat(
                  'Claims',
                  Fmt.amount((aggs['total_claims'] as num?)?.toDouble() ?? 0),
                  Colors.orange),
            ])),
      Expanded(
          child: entries.isEmpty
              ? const EmptyState(
              icon: Icons.bar_chart_outlined,
              message: 'No data for this range')
              : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (_, i) {
                final e = entries[i];
                final total =
                    (e['total_landed_cost'] as num?)?.toDouble() ?? 0;
                final paid = (e['total_paid'] as num?)?.toDouble() ?? 0;
                final due = (e['outstanding'] as num?)?.toDouble() ?? 0;
                final profit = (e['net_profit'] as num?)?.toDouble();
                final dt = DateTime.tryParse(e['dc_date'] as String? ?? '');
                return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(kRadiusCard),
                        border: Border.all(color: kBorder)),
                    child: Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e['dc_number'] as String? ?? '--',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800)),
                                Text(
                                    '${e['farmer_name'] ?? e['farm_farmer_name'] ?? '--'}'
                                        '  |  ${dt != null ? DateFormat("d MMM").format(dt) : "--"}'
                                        '  |  ${(e['net_weight_kg'] as num?)?.toStringAsFixed(0) ?? 0} kg',
                                    style: const TextStyle(
                                        fontSize: 10, color: kTextHint)),
                              ])),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(Fmt.amount(total),
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800)),
                            if (due > 0)
                              Text('Due: ${Fmt.amount(due)}',
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.orange)),
                            if (profit != null)
                              Text(
                                  (e['revenue'] as num? ?? 0) > 0
                                      ? 'P: ${Fmt.amount(profit ?? 0)}'
                                      : 'Pending',
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: profit >= 0
                                          ? Colors.green
                                          : Colors.red)),
                          ]),
                    ]));
              })),
    ]);
  }

  // ==========================================================================
  // TAB 6: HISTORY & AUDIT
  // ==========================================================================
  Widget _tabHistory() {
    return DefaultTabController(
        length: 3,
        child: Column(children: [
          Container(
              color: Colors.white,
              child: const TabBar(
                labelColor: kPrimary,
                unselectedLabelColor: kTextSub,
                indicatorColor: kPrimary,
                tabs: [
                  Tab(text: 'Audit Log'),
                  Tab(text: 'Payments'),
                  Tab(text: 'Rates')
                ],
              )),
          Expanded(
              child: TabBarView(children: [
                // Audit log
                _auditLog.isEmpty
                    ? const EmptyState(
                    icon: Icons.history_outlined, message: 'No audit entries')
                    : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _auditLog.length,
                    itemBuilder: (_, i) {
                      final a = _auditLog[i];
                      final dt =
                      DateTime.tryParse(a['changed_at'] as String? ?? '');
                      final action = a['action'] as String? ?? '--';
                      final color = _auditColor(action);
                      return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(kRadiusCard),
                              border: const Border(
                                  left: BorderSide(color: kBorder, width: 3),
                                  right: BorderSide(color: kBorder),
                                  top: BorderSide(color: kBorder),
                                  bottom: BorderSide(color: kBorder))),
                          child: Row(children: [
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          action.replaceAll('_', ' ').toUpperCase(),
                                          style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                              color: color)),
                                      Text(
                                          'DC: ${a['dc_number'] ?? '--'}  |  ${a['farmer_name'] ?? ''}',
                                          style: const TextStyle(
                                              fontSize: 10, color: kTextHint)),
                                      if (a['new_value'] != null)
                                        Text('${a['new_value']}',
                                            style: const TextStyle(
                                                fontSize: 9, color: kTextSub),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis),
                                    ])),
                            if (dt != null)
                              Text(
                                  DateFormat('d MMM HH:mm')
                                      .format(dt.toLocal()),
                                  style: const TextStyle(
                                      fontSize: 9, color: kTextHint)),
                          ]));
                    }),
                // Payment history
                _payHistory.isEmpty
                    ? const EmptyState(
                    icon: Icons.payments_outlined,
                    message: 'No payments recorded')
                    : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _payHistory.length,
                    itemBuilder: (_, i) {
                      final p = _payHistory[i];
                      final dt =
                      DateTime.tryParse(p['payment_date'] as String? ?? '');
                      final isRev = p['status'] == 'reversed';
                      return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                              color: isRev ? Colors.red.shade50 : Colors.white,
                              borderRadius: BorderRadius.circular(kRadiusCard),
                              border: Border.all(
                                  color:
                                  isRev ? Colors.red.shade200 : kBorder)),
                          child: Row(children: [
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Text(
                                            Fmt.amount(
                                                (p['amount'] as num?)?.toDouble() ??
                                                    0),
                                            style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800,
                                                color: isRev
                                                    ? Colors.red
                                                    : Colors.green)),
                                        const SizedBox(width: 8),
                                        _statusChip(
                                            (p['payment_mode'] as String? ?? '')
                                                .toUpperCase(),
                                            Colors.blue),
                                        if (isRev) ...[
                                          const SizedBox(width: 4),
                                          _statusChip('REVERSED', Colors.red),
                                        ],
                                      ]),
                                      Text(
                                          'DC: ${p['dc_number'] ?? '--'}  |  ${p['farmer_name'] ?? p['farm_name'] ?? '--'}',
                                          style: const TextStyle(
                                              fontSize: 10, color: kTextHint)),
                                      if (p['reference_number'] != null)
                                        Text('Ref: ${p['reference_number']}',
                                            style: const TextStyle(
                                                fontSize: 9, color: kTextSub)),
                                      if (isRev && p['reversal_reason'] != null)
                                        Text('Reversed: ${p['reversal_reason']}',
                                            style: const TextStyle(
                                                fontSize: 9, color: Colors.red)),
                                    ])),
                            Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (dt != null)
                                    Text(DateFormat('d MMM').format(dt),
                                        style: const TextStyle(
                                            fontSize: 10, color: kTextHint)),
                                  if (!isRev)
                                    GestureDetector(
                                        onTap: () => _reversePayment(p),
                                        child: const Text('Reverse',
                                            style: TextStyle(
                                                fontSize: 9,
                                                color: Colors.red,
                                                fontWeight: FontWeight.w700))),
                                ]),
                          ]));
                    }),
                // Rate history
                _rateHistory.isEmpty
                    ? const EmptyState(
                    icon: Icons.price_change_outlined,
                    message: 'No rate changes')
                    : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _rateHistory.length,
                    itemBuilder: (_, i) {
                      final r = _rateHistory[i];
                      final dt =
                      DateTime.tryParse(r['changed_at'] as String? ?? '');
                      final oldR =
                          (r['old_rate_per_kg'] ?? r['old_rate_per_bird'])
                              ?.toString() ??
                              '--';
                      final newR =
                          (r['new_rate_per_kg'] ?? r['new_rate_per_bird'])
                              ?.toString() ??
                              '--';
                      return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(kRadiusCard),
                              border: Border.all(color: kBorder)),
                          child: Row(children: [
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          'DC: ${r['dc_number'] ?? '--'}  |  ${r['farmer_name'] ?? '--'}',
                                          style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700)),
                                      Text('Rs.$oldR  to  Rs.$newR',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.blue,
                                              fontWeight: FontWeight.w800)),
                                      if (r['reason'] != null)
                                        Text(
                                            (r['reason'] as String)
                                                .replaceAll('_', ' ')
                                                .split(' ')
                                                .map((w) => w.isEmpty
                                                ? w
                                                : w[0].toUpperCase() +
                                                w.substring(1))
                                                .join(' '),
                                            style: const TextStyle(
                                                fontSize: 9, color: kTextSub)),
                                    ])),
                            if (dt != null)
                              Text(
                                  DateFormat('d MMM HH:mm')
                                      .format(dt.toLocal()),
                                  style: const TextStyle(
                                      fontSize: 9, color: kTextHint)),
                          ]));
                    }),
              ])),
        ]));
  }

  Color _auditColor(String action) {
    if (action.contains('rate')) return Colors.blue;
    if (action.contains('payment')) return Colors.green;
    if (action.contains('lock') || action.contains('unlock')) {
      return Colors.grey;
    }
    if (action.contains('claim')) return Colors.orange;
    if (action.contains('shortage')) return Colors.red;
    if (action.contains('created')) return kPrimary;
    return kTextSub;
  }

  // ==========================================================================
  // DIALOGS
  // ==========================================================================

  void _showRateEntry(Map<String, dynamic> p) {
    if ((p['status'] as String?) == 'locked') {
      showError(context, 'Entry is locked. Reopen first.');
      return;
    }
    final rateCtrl = TextEditingController(
        text: (p['purchase_rate_per_kg'] as num?)?.toStringAsFixed(2) ?? '');
    final transportCtrl = TextEditingController(
        text: (p['transport_cost'] as num? ?? 0).toStringAsFixed(0));
    final loadingCtrl = TextEditingController(
        text: (p['loading_cost'] as num? ?? 0).toStringAsFixed(0));
    final handlingCtrl = TextEditingController(
        text: (p['handling_cost'] as num? ?? 0).toStringAsFixed(0));
    final otherCtrl = TextEditingController(
        text: (p['other_cost'] as num? ?? 0).toStringAsFixed(0));
    final arrWtCtrl = TextEditingController(
        text: (p['arrival_weight_kg'] as num? ?? 0) > 0
            ? (p['arrival_weight_kg'] as num).toStringAsFixed(2)
            : '');
    final arrBirdCtrl = TextEditingController(
        text: (p['arrival_birds'] as num? ?? 0) > 0
            ? (p['arrival_birds'] as num).toString()
            : '');
    final kg = (p['net_weight_kg'] as num?)?.toDouble() ?? 0;
    final birds = (p['bird_count'] as num?)?.toInt() ?? 0;
    // Suggest default rate from farm if available
    final defaultRate = (p['farms'] as Map?)?['default_rate_per_kg'] as num?;
    if (rateCtrl.text.isEmpty && defaultRate != null) {
      rateCtrl.text = defaultRate.toStringAsFixed(2);
    }

    _showSheet(
        maxWidth: WebSize.dialogLg,
        builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
          String rateMode = 'kg';
          double rate = double.tryParse(rateCtrl.text) ?? 0;
          double tran = double.tryParse(transportCtrl.text) ?? 0;
          double load = double.tryParse(loadingCtrl.text) ?? 0;
          double hand = double.tryParse(handlingCtrl.text) ?? 0;
          double other = double.tryParse(otherCtrl.text) ?? 0;
          double base = rateMode == 'bird' ? rate * birds : rate * kg;
          double landed = base + tran + load + hand + other;
          double ckg = kg > 0 ? landed / kg : 0;
          double arrWt = double.tryParse(arrWtCtrl.text) ?? 0;
          double shortage = kg > 0 && arrWt > 0 ? (kg - arrWt).abs() : 0;

          return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.start,
                                  children: [
                                    const Text('Purchase Rate Entry',
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800)),
                                    Text(
                                        'DC: ${p['dc_number']}  |  ${p['farmer_name'] ?? '--'}  |  ${kg.toStringAsFixed(1)} kg',
                                        style: const TextStyle(
                                            fontSize: 10, color: kTextHint)),
                                  ])),
                          IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  Navigator.of(ctx, rootNavigator: true)
                                      .pop()),
                        ]),
                        const SizedBox(height: 12),
                        // Rate mode toggle
                        SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                  value: 'kg', label: Text('Rate/kg')),
                              ButtonSegment(
                                  value: 'bird', label: Text('Rate/bird')),
                            ],
                            selected: {
                              rateMode
                            },
                            onSelectionChanged: (s) => ss(() {
                              rateMode = s.first;
                              rateCtrl.clear();
                            })),
                        const SizedBox(height: 10),
                        TextField(
                            controller: rateCtrl,
                            keyboardType:
                            const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (_) => ss(() {}),
                            decoration: InputDecoration(
                                labelText: rateMode == 'bird'
                                    ? 'Rate per Bird *'
                                    : 'Purchase Rate (Rs./kg) *',
                                prefixText: 'Rs.',
                                suffixText:
                                rateMode == 'bird' ? '/bird' : '/kg')),
                        const SizedBox(height: 8),
                        // Cost breakdown
                        Row(children: [
                          Expanded(
                              child: TextField(
                                  controller: transportCtrl,
                                  onChanged: (_) => ss(() {}),
                                  keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                                  decoration: const InputDecoration(
                                      labelText: 'Transport',
                                      prefixText: 'Rs.'))),
                          const SizedBox(width: 6),
                          Expanded(
                              child: TextField(
                                  controller: loadingCtrl,
                                  onChanged: (_) => ss(() {}),
                                  keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                                  decoration: const InputDecoration(
                                      labelText: 'Loading',
                                      prefixText: 'Rs.'))),
                          const SizedBox(width: 6),
                          Expanded(
                              child: TextField(
                                  controller: handlingCtrl,
                                  onChanged: (_) => ss(() {}),
                                  keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                                  decoration: const InputDecoration(
                                      labelText: 'Handling',
                                      prefixText: 'Rs.'))),
                          const SizedBox(width: 6),
                          Expanded(
                              child: TextField(
                                  controller: otherCtrl,
                                  onChanged: (_) => ss(() {}),
                                  keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                                  decoration: const InputDecoration(
                                      labelText: 'Other',
                                      prefixText: 'Rs.'))),
                        ]),
                        const SizedBox(height: 10),
                        // Weighment section
                        const Text('ARRIVAL WEIGHMENT (optional)',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: kTextHint,
                                letterSpacing: 0.5)),
                        const SizedBox(height: 6),
                        Row(children: [
                          Expanded(
                              child: TextField(
                                  controller: arrWtCtrl,
                                  onChanged: (_) => ss(() {}),
                                  keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                                  decoration: const InputDecoration(
                                      labelText: 'Arrival Weight kg',
                                      suffixText: 'kg'))),
                          const SizedBox(width: 8),
                          Expanded(
                              child: TextField(
                                  controller: arrBirdCtrl,
                                  onChanged: (_) => ss(() {}),
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                      labelText: 'Arrival Birds'))),
                        ]),
                        if (shortage > 0.1) ...[
                          const SizedBox(height: 6),
                          Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(kRadiusInner),
                                  border: Border.all(
                                      color: Colors.red.shade200)),
                              child: Row(children: [
                                const Icon(Icons.warning_amber_outlined,
                                    color: Colors.red, size: 14),
                                const SizedBox(width: 6),
                                Text(
                                    'Weighment shortage: ${shortage.toStringAsFixed(2)} kg detected',
                                    style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.red,
                                        fontWeight: FontWeight.w700)),
                              ])),
                        ],
                        // Live calculation preview
                        if (rate > 0) ...[
                          const SizedBox(height: 12),
                          Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(8)),
                              child: Column(children: [
                                _calcRow('Base Purchase',
                                    'Rs.${base.toStringAsFixed(2)}'),
                                _calcRow(
                                    'Transport + Loading + Handling + Other',
                                    'Rs.${(tran + load + hand + other).toStringAsFixed(2)}'),
                                const Divider(height: 10),
                                _calcRow('Total Landed Cost',
                                    'Rs.${landed.toStringAsFixed(2)}',
                                    bold: true),
                                _calcRow('Cost per KG',
                                    'Rs.${ckg.toStringAsFixed(4)}/kg',
                                    bold: true),
                              ])),
                        ],
                        const SizedBox(height: 16),
                        ElevatedButton(
                            onPressed: rate <= 0
                                ? null
                                : () async {
                              Navigator.of(ctx, rootNavigator: true)
                                  .pop();
                              try {
                                final uid = ref
                                    .read(appUserProvider)
                                    .valueOrNull
                                    ?.userId;
                                await _c.rpc('update_purchase_rate',
                                    params: {
                                      'p_purchase_entry_id': p['id'],
                                      'p_rate_per_kg':
                                      rateMode == 'kg'
                                          ? rate
                                          : null,
                                      'p_rate_per_bird':
                                      rateMode == 'bird'
                                          ? rate
                                          : null,
                                      'p_transport_cost': tran,
                                      'p_loading_cost': load,
                                      'p_handling_cost': hand,
                                      'p_other_cost': other,
                                      'p_confirmed_by': uid,
                                    });
                                // Save arrival weighment if provided
                                final arrWtVal =
                                    double.tryParse(arrWtCtrl.text) ??
                                        0;
                                final arrBirdVal =
                                    int.tryParse(arrBirdCtrl.text) ??
                                        0;
                                if (arrWtVal > 0 || arrBirdVal > 0) {
                                  await _c
                                      .from('purchase_entries')
                                      .update({
                                    'arrival_weight_kg': arrWtVal > 0
                                        ? arrWtVal
                                        : null,
                                    'arrival_birds': arrBirdVal > 0
                                        ? arrBirdVal
                                        : null,
                                    'shortage_kg':
                                    arrWtVal > 0 && kg > 0
                                        ? (kg - arrWtVal).abs()
                                        : 0,
                                    'shortage_birds':
                                    arrBirdVal > 0 && birds > 0
                                        ? (birds - arrBirdVal)
                                        .abs()
                                        : 0,
                                  }).eq('id', p['id'] as String);
                                }
                                _load();
                                if (mounted) {
                                  showSuccess(context,
                                      'Rate confirmed. Landed: Rs.${landed.toStringAsFixed(2)}');
                                }
                              } catch (e) {
                                if (mounted) {
                                  showError(
                                      context,
                                      e.toString().replaceAll(
                                          'Exception: ', ''));
                                }
                              }
                            },
                            style: ElevatedButton.styleFrom(
                                minimumSize:
                                const Size(double.infinity, 48)),
                            child: Text(rate > 0
                                ? 'Confirm Rate  Rs.${landed.toStringAsFixed(0)} total'
                                : 'Enter rate above')),
                      ])));
        }));
  }

  void _showPurchaseDetail(Map<String, dynamic> p) {
    _showSheet(
        maxWidth: WebSize.dialogLg,
        builder: (ctx) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            maxChildSize: 0.95,
            builder: (_, ctrl) {
              final kg = (p['net_weight_kg'] as num?)?.toDouble() ?? 0;
              final arrWt = (p['arrival_weight_kg'] as num?)?.toDouble() ?? 0;
              final total = (p['total_landed_cost'] as num?)?.toDouble() ?? 0;
              final paid = (p['total_paid'] as num?)?.toDouble() ?? 0;
              final claim = (p['claim_amount'] as num?)?.toDouble() ?? 0;
              final due = (total - paid - claim).clamp(0.0, double.infinity);
              return SingleChildScrollView(
                  controller: ctrl,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text('DC: ${p['dc_number'] ?? '--'}',
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900))),
                          _statusChip(
                              (p['status'] as String? ?? 'draft').toUpperCase(),
                              p['status'] == 'locked'
                                  ? Colors.grey
                                  : Colors.green),
                          IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  Navigator.of(ctx, rootNavigator: true).pop()),
                        ]),
                        Text(
                            '${p['farmer_name'] ?? '--'}  |  ${p['dc_date'] ?? '--'}',
                            style: const TextStyle(
                                fontSize: 12, color: kTextHint)),
                        const Divider(height: 20),
                        _detailSection('STOCK', [
                          _detailRow(
                              'Farm Birds', '${p['bird_count'] ?? 0} birds'),
                          _detailRow(
                              'Farm Weight', '${kg.toStringAsFixed(2)} kg'),
                          _detailRow(
                              'Arrival Birds', '${p['arrival_birds'] ?? '--'}'),
                          _detailRow('Arrival Weight',
                              '${arrWt > 0 ? arrWt.toStringAsFixed(2) : '--'} kg'),
                          if ((p['shortage_kg'] as num? ?? 0) > 0)
                            _detailRow('Shortage',
                                '${(p['shortage_kg'] as num).toStringAsFixed(2)} kg  (${p['shortage_birds']} birds)',
                                highlight: Colors.red),
                        ]),
                        _detailSection('COSTING', [
                          _detailRow(
                              'Rate',
                              (p['purchase_rate_per_kg'] as num?) != null
                                  ? 'Rs.${(p['purchase_rate_per_kg'] as num).toStringAsFixed(4)}/kg'
                                  : '--'),
                          _detailRow('Base Amount',
                              'Rs.${(p['base_purchase_amount'] as num? ?? 0).toStringAsFixed(2)}'),
                          _detailRow('Transport',
                              'Rs.${(p['transport_cost'] as num? ?? 0).toStringAsFixed(2)}'),
                          _detailRow('Loading',
                              'Rs.${(p['loading_cost'] as num? ?? 0).toStringAsFixed(2)}'),
                          _detailRow('Handling',
                              'Rs.${(p['handling_cost'] as num? ?? 0).toStringAsFixed(2)}'),
                          _detailRow('Other',
                              'Rs.${(p['other_cost'] as num? ?? 0).toStringAsFixed(2)}'),
                          _detailRow(
                              'Landed Cost', 'Rs.${total.toStringAsFixed(2)}',
                              bold: true),
                          _detailRow(
                              'Cost/kg',
                              (p['cost_per_kg_landed'] as num?) != null
                                  ? 'Rs.${(p['cost_per_kg_landed'] as num).toStringAsFixed(4)}/kg'
                                  : '--',
                              bold: true),
                        ]),
                        _detailSection('PAYMENT', [
                          _detailRow(
                              'Total Paid', 'Rs.${paid.toStringAsFixed(2)}'),
                          _detailRow(
                              'Claims', 'Rs.${claim.toStringAsFixed(2)}'),
                          _detailRow(
                              'Outstanding', 'Rs.${due.toStringAsFixed(2)}',
                              highlight:
                              due > 0 ? Colors.orange : Colors.green),
                          _detailRow('Due Date',
                              p['payment_due_date'] as String? ?? '--'),
                          _detailRow(
                              'Status',
                              (p['payment_status'] as String? ?? '--')
                                  .toUpperCase()),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          if (p['status'] != 'locked') ...[
                            Expanded(
                                child: OutlinedButton(
                                    onPressed: () {
                                      Navigator.of(ctx, rootNavigator: true)
                                          .pop();
                                      _showRateEntry(p);
                                    },
                                    child: const Text('Edit Rate'))),
                            const SizedBox(width: 8),
                            Expanded(
                                child: ElevatedButton(
                                    onPressed: () {
                                      Navigator.of(ctx, rootNavigator: true)
                                          .pop();
                                      _showPayment(p);
                                    },
                                    child: const Text('Record Payment'))),
                          ],
                        ]),
                      ]));
            }));
  }

  Widget _detailSection(String title, List<Widget> rows) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: kTextHint,
                letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
                color: kBgGrey, borderRadius: BorderRadius.circular(10)),
            child: Column(children: rows)),
      ]);

  Widget _detailRow(String l, String v,
      {bool bold = false, Color? highlight}) =>
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(
                child: Text(l,
                    style: const TextStyle(fontSize: 11, color: kTextSub))),
            Text(v,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                    color: highlight ?? kTextMain)),
          ]));

  void _showPayment(Map<String, dynamic> p) {
    final total = (p['total_landed_cost'] as num?)?.toDouble() ?? 0;
    final paid = (p['total_paid'] as num?)?.toDouble() ?? 0;
    final claim = (p['claim_amount'] as num?)?.toDouble() ?? 0;
    final due = (total - paid - claim).clamp(0.0, double.infinity);
    final advance = (p['advance_paid'] as num?)?.toDouble() ?? 0;
    final dueDate = p['payment_due_date'] as String?;
    final amtCtrl =
    TextEditingController(text: due > 0 ? due.toStringAsFixed(2) : '');
    final refCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String mode = 'cash';

    _showSheet(
        maxWidth: WebSize.dialogMd,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, ss) => Padding(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(ctx).viewInsets.bottom),
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Row(children: [
                        const Expanded(
                            child: Text('Record Payment',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800))),
                        IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () =>
                                Navigator.of(ctx, rootNavigator: true).pop()),
                      ]),
                      Text(
                          'DC: ${p['dc_number']}  |  Outstanding: Rs.${due.toStringAsFixed(2)}',
                          style:
                          const TextStyle(fontSize: 11, color: kTextHint)),
                      if (advance > 0 || dueDate != null)
                        Container(
                            margin: const EdgeInsets.only(top: 6),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8)),
                            child: Row(children: [
                              if (advance > 0) ...[
                                const Icon(Icons.payments_outlined,
                                    size: 12, color: Colors.blue),
                                const SizedBox(width: 4),
                                Text(
                                    'Advance: Rs.${advance.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.blue)),
                                const SizedBox(width: 12),
                              ],
                              if (dueDate != null) ...[
                                const Icon(Icons.calendar_today_outlined,
                                    size: 12, color: Colors.orange),
                                const SizedBox(width: 4),
                                Text('Due: $dueDate',
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.orange)),
                              ],
                            ])),
                      const SizedBox(height: 12),
                      // Payment mode
                      Row(
                          children: ['cash', 'upi', 'bank', 'cheque']
                              .map((m) => Expanded(
                              child: GestureDetector(
                                  onTap: () => ss(() => mode = m),
                                  child: Container(
                                      margin:
                                      const EdgeInsets.only(right: 4),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 8),
                                      decoration: BoxDecoration(
                                          color: mode == m
                                              ? kPrimary
                                              : Colors.white,
                                          borderRadius:
                                          BorderRadius.circular(8),
                                          border: Border.all(
                                              color: mode == m
                                                  ? kPrimary
                                                  : kBorder)),
                                      child: Text(m.toUpperCase(),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: mode == m ? Colors.white : kTextSub))))))
                              .toList()),
                      const SizedBox(height: 10),
                      TextField(
                          controller: amtCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                              labelText: 'Amount *', prefixText: 'Rs.')),
                      const SizedBox(height: 8),
                      if (mode != 'cash')
                        TextField(
                            controller: refCtrl,
                            decoration: const InputDecoration(
                                labelText: 'Reference / UTR / Cheque No.')),
                      if (mode != 'cash') const SizedBox(height: 8),
                      TextField(
                          controller: noteCtrl,
                          decoration: const InputDecoration(
                              labelText: 'Notes (optional)')),
                      const SizedBox(height: 16),
                      ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 48)),
                          onPressed: () async {
                            final amt =
                                double.tryParse(amtCtrl.text.trim()) ?? 0;
                            if (amt <= 0) {
                              showError(context, 'Enter valid amount');
                              return;
                            }
                            if (amt > due * 1.01 && due > 0) {
                              final ok = await confirmDialog(context,
                                  title: 'Overpayment',
                                  message:
                                  'Payment Rs.${amt.toStringAsFixed(0)} exceeds outstanding Rs.${due.toStringAsFixed(0)}. Proceed?',
                                  confirmText: 'Yes, Proceed');
                              if (!ok || !mounted) return;
                            }
                            Navigator.of(ctx, rootNavigator: true).pop();
                            try {
                              final tid = ref
                                  .read(appUserProvider)
                                  .valueOrNull
                                  ?.traderId;
                              await _c.from('purchase_payments').insert({
                                'trader_id': tid,
                                'purchase_entry_id': p['id'],
                                'farm_id': p['farm_id'],
                                'amount': amt,
                                'payment_mode': mode,
                                'reference_number': refCtrl.text.trim().isEmpty
                                    ? null
                                    : refCtrl.text.trim(),
                                'notes': noteCtrl.text.trim().isEmpty
                                    ? null
                                    : noteCtrl.text.trim(),
                              });
                              _load();
                              if (mounted) {
                                showSuccess(context, 'Payment recorded');
                              }
                            } catch (e) {
                              if (mounted) {
                                showError(context,
                                    e.toString().replaceAll('Exception: ', ''));
                              }
                            }
                          },
                          child: const Text('Record Payment')),
                    ])))));
  }

  void _showClaim(Map<String, dynamic> p) {
    final amtCtrl = TextEditingController(
        text: (p['claim_amount'] as num? ?? 0) > 0
            ? (p['claim_amount'] as num).toStringAsFixed(2)
            : '');
    final noteCtrl =
    TextEditingController(text: p['claim_notes'] as String? ?? '');

    _showSheet(
        maxWidth: WebSize.dialogMd,
        builder: (ctx) => Padding(
            padding:
            EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    const Expanded(
                        child: Text('Supplier Claim / Adjustment',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800))),
                    IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () =>
                            Navigator.of(ctx, rootNavigator: true).pop()),
                  ]),
                  Text(
                      'DC: ${p['dc_number']}  |  Use for shortage, quality issues, weight disputes',
                      style: const TextStyle(fontSize: 10, color: kTextHint)),
                  const SizedBox(height: 12),
                  TextField(
                      controller: amtCtrl,
                      keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Claim Amount Rs. *', prefixText: 'Rs.')),
                  const SizedBox(height: 8),
                  TextField(
                      controller: noteCtrl,
                      maxLines: 2,
                      decoration:
                      const InputDecoration(labelText: 'Reason / Notes *')),
                  const SizedBox(height: 14),
                  ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                          backgroundColor: Colors.orange),
                      onPressed: () async {
                        final amt = double.tryParse(amtCtrl.text.trim()) ?? 0;
                        if (amt <= 0) {
                          showError(context, 'Enter claim amount');
                          return;
                        }
                        Navigator.of(ctx, rootNavigator: true).pop();
                        try {
                          await _c.from('purchase_entries').update({
                            'claim_amount': amt,
                            'claim_notes': noteCtrl.text.trim(),
                          }).eq('id', p['id'] as String);
                          final tid =
                              ref.read(appUserProvider).valueOrNull?.traderId;
                          await _c.from('supplier_ledger').insert({
                            'trader_id': tid,
                            'farm_id': p['farm_id'],
                            'purchase_entry_id': p['id'],
                            'entry_type': 'credit',
                            'amount': amt,
                            'reason': 'claim',
                            'entry_date':
                            DateTime.now().toIso8601String().split('T')[0],
                            'description':
                            'Claim on DC ${p['dc_number']}: ${noteCtrl.text.trim()}',
                          });
                          _load();
                          if (mounted) showSuccess(context, 'Claim recorded');
                        } catch (e) {
                          if (mounted) {
                            showError(context,
                                e.toString().replaceAll('Exception: ', ''));
                          }
                        }
                      },
                      child: const Text('Save Claim')),
                ]))));
  }

  Future<void> _lockEntry(Map<String, dynamic> p) async {
    final ok = await confirmDialog(context,
        title: 'Lock Purchase Entry',
        message:
        'Lock DC ${p['dc_number']}? After locking, no edits allowed. Admin can reopen.',
        confirmText: 'Lock',
        confirmColor: Colors.grey.shade700);
    if (!ok || !mounted) return;
    try {
      await _c.from('purchase_entries').update({
        'status': 'locked',
        'locked_at': DateTime.now().toIso8601String(),
      }).eq('id', p['id'] as String);
      _load();
      if (mounted) showSuccess(context, 'Entry locked');
    } catch (e) {
      if (mounted) {
        showError(context, e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  Future<void> _unlockEntry(Map<String, dynamic> p) async {
    final ok = await confirmDialog(context,
        title: 'Reopen Entry',
        message: 'Reopen DC ${p['dc_number']} for editing?',
        confirmText: 'Reopen',
        confirmColor: kPrimary);
    if (!ok || !mounted) return;
    try {
      await _c.from('purchase_entries').update({
        'status': 'confirmed',
        'locked_at': null,
      }).eq('id', p['id'] as String);
      _load();
      if (mounted) showSuccess(context, 'Entry reopened');
    } catch (e) {
      if (mounted) {
        showError(context, e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  Future<void> _reversePayment(Map<String, dynamic> p) async {
    final ok = await confirmDialog(context,
        title: 'Reverse Payment',
        message:
        'Reverse Rs.${(p['amount'] as num?)?.toStringAsFixed(2) ?? '0'} payment?',
        confirmText: 'Reverse',
        confirmColor: Colors.red);
    if (!ok || !mounted) return;
    try {
      final uid = ref.read(appUserProvider).valueOrNull?.userId;
      await _c.rpc('reverse_payment', params: {
        'p_payment_id': p['id'],
        'p_reason': 'Reversed by trader',
        'p_reversed_by': uid,
      });
      _load();
      if (mounted) showSuccess(context, 'Payment reversed');
    } catch (e) {
      if (mounted) {
        showError(context, e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  Future<void> _showRateHistory(String entryId, String dcNum) async {
    List<Map<String, dynamic>> history = [];
    try {
      final r = await _c
          .from('purchase_rate_history')
          .select(
          'old_rate_per_kg,new_rate_per_kg,old_rate_per_bird,new_rate_per_bird,reason,changed_at')
          .eq('purchase_entry_id', entryId)
          .order('changed_at', ascending: false);
      history = List<Map<String, dynamic>>.from(r as List? ?? []);
    } catch (_) {}

    if (!mounted) return;
    _showSheet(
        maxWidth: WebSize.dialogMd,
        builder: (ctx) => ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              Text('Rate History - $dcNum',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              if (history.isEmpty)
                const Text('No rate changes recorded.',
                    style: TextStyle(color: kTextHint)),
              ...history.map((h) {
                final oldR = h['old_rate_per_kg'] ?? h['old_rate_per_bird'];
                final newR = h['new_rate_per_kg'] ?? h['new_rate_per_bird'];
                final dt =
                DateTime.tryParse(h['changed_at'] as String? ?? '');
                return ListTile(
                    dense: true,
                    title: Text(
                        'Rs.${oldR ?? '--'}  to  Rs.${newR ?? '--'}',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.blue)),
                    subtitle: Text(
                        '${h['reason'] ?? ''}  |  ${dt != null ? DateFormat('d MMM HH:mm').format(dt.toLocal()) : '--'}',
                        style: const TextStyle(
                            fontSize: 10, color: kTextHint)));
              }),
            ]));
  }

  void _showSupplierDashboard(Map<String, dynamic> farm) {
    _showSheet(
        maxWidth: WebSize.dialogLg,
        builder: (ctx) {
          final st = farm['_stats'] as Map<String, dynamic>? ?? {};
          final total = (st['total'] as double?) ?? 0;
          final pd = (st['paid'] as double?) ?? 0;
          final cl = (st['claim'] as double?) ?? 0;
          final outstanding = (total - pd - cl).clamp(0.0, double.infinity);
          return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              maxChildSize: 0.9,
              builder: (_, ctrl) => SingleChildScrollView(
                  controller: ctrl,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          CircleAvatar(
                              radius: 22,
                              backgroundColor: kNavy.withValues(alpha: 0.08),
                              child: Text(
                                  (farm['farmer_name'] as String? ?? '?')[0]
                                      .toUpperCase(),
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: kNavy))),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(farm['farmer_name'] as String? ?? '--',
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800)),
                                    if (farm['farm_name'] != null)
                                      Text(farm['farm_name'] as String,
                                          style: const TextStyle(
                                              fontSize: 11, color: kTextHint)),
                                    if (farm['phone'] != null)
                                      Text(farm['phone'] as String,
                                          style: const TextStyle(
                                              fontSize: 11, color: kTextHint)),
                                  ])),
                          IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  Navigator.of(ctx, rootNavigator: true).pop()),
                        ]),
                        const SizedBox(height: 16),
                        Row(children: [
                          _kpiCard('Purchase', Fmt.amount(total),
                              Colors.blue, Icons.shopping_cart_outlined),
                          const SizedBox(width: 8),
                          _kpiCard('Paid', Fmt.amount(pd),
                              Colors.green, Icons.payments_outlined),
                          const SizedBox(width: 8),
                          _kpiCard(
                              'Due',
                              Fmt.amount(outstanding),
                              outstanding > 0 ? Colors.orange : Colors.green,
                              Icons.account_balance_outlined),
                        ]),
                        const SizedBox(height: 12),
                        if (farm['credit_days'] != null)
                          Row(children: [
                            const Icon(Icons.schedule_outlined,
                                size: 12, color: kTextHint),
                            const SizedBox(width: 4),
                            Text('Credit: ${farm['credit_days']} days',
                                style: const TextStyle(
                                    fontSize: 11, color: kTextSub)),
                            const SizedBox(width: 16),
                            if (farm['default_rate_per_kg'] != null) ...[
                              const Icon(Icons.price_change_outlined,
                                  size: 12, color: kTextHint),
                              const SizedBox(width: 4),
                              Text(
                                  'Default rate: Rs.${(farm['default_rate_per_kg'] as num).toStringAsFixed(2)}/kg',
                                  style: const TextStyle(
                                      fontSize: 11, color: kTextSub)),
                            ],
                          ]),
                        const SizedBox(height: 16),
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.of(ctx, rootNavigator: true)
                                        .pop();
                                    _showPaymentForFarm(farm);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                  ),
                                  icon: const Icon(Icons.payments_outlined,
                                      size: 14),
                                  label: const Text('Pay')),
                              OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.of(ctx, rootNavigator: true)
                                        .pop();
                                    setState(() {
                                      _farmFilter = farm['id'] as String?;
                                    });
                                    _tab.animateTo(3);
                                    _load();
                                  },
                                  icon:
                                  const Icon(Icons.book_outlined, size: 14),
                                  label: const Text('Ledger')),
                              OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.of(ctx, rootNavigator: true)
                                        .pop();
                                    _showEditFarm(farm);
                                  },
                                  icon:
                                  const Icon(Icons.edit_outlined, size: 14),
                                  label: const Text('Edit')),
                            ]),
                      ])));
        });
  }

  void _showPaymentForFarm(Map<String, dynamic> farm) async {
    try {
      final r = await _c
          .from('purchase_entries')
          .select('id,dc_number,total_landed_cost,total_paid,claim_amount,'
          'payment_status,farm_id,farm_id,farmer_name')
          .eq('farm_id', farm['id'] as String)
          .neq('payment_status', 'paid')
          .order('dc_date', ascending: true)
          .limit(1)
          .maybeSingle();
      if (r != null && mounted) {
        _showPayment(r);
      } else if (mounted)
        showSuccess(context, 'All payments settled for this supplier');
    } catch (_) {}
  }

  void _showAddFarm() {
    final nameCtrl = TextEditingController();
    final farmCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final locCtrl = TextEditingController();
    final creditCtrl = TextEditingController(text: '7');
    final rateCtrl = TextEditingController();
    String? selectedCompanyId;

    _showSheet(
        maxWidth: WebSize.dialogMd,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, ss) => Padding(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(ctx).viewInsets.bottom),
                child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Row(children: [
                        const Expanded(
                            child: Text('Add Supplier',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800))),
                        IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () =>
                                Navigator.of(ctx, rootNavigator: true).pop()),
                      ]),
                      const SizedBox(height: 12),
                      TextField(
                          controller: nameCtrl,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                              labelText: 'Farmer Name *')),
                      const SizedBox(height: 8),
                      TextField(
                          controller: farmCtrl,
                          textCapitalization: TextCapitalization.words,
                          decoration:
                          const InputDecoration(labelText: 'Farm Name')),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                            child: TextField(
                                controller: phoneCtrl,
                                keyboardType: TextInputType.phone,
                                decoration:
                                const InputDecoration(labelText: 'Phone'))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: TextField(
                                controller: creditCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    labelText: 'Credit Days',
                                    suffixText: 'days'))),
                      ]),
                      const SizedBox(height: 8),
                      TextField(
                          controller: locCtrl,
                          decoration:
                          const InputDecoration(labelText: 'Location')),
                      const SizedBox(height: 8),
                      TextField(
                          controller: rateCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                              labelText: 'Default Rate Rs./kg (optional)',
                              prefixText: 'Rs.',
                              suffixText: '/kg')),
                      if (_companies.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                            initialValue: selectedCompanyId,
                            decoration: const InputDecoration(
                                labelText: 'Company (optional)'),
                            items: [
                              const DropdownMenuItem(
                                  value: null, child: Text('None')),
                              ..._companies.map((c) => DropdownMenuItem(
                                  value: c['id'] as String,
                                  child: Text(
                                      c['company_name'] as String? ?? '--'))),
                            ],
                            onChanged: (v) => ss(() => selectedCompanyId = v)),
                      ],
                      const SizedBox(height: 16),
                      ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 48)),
                          onPressed: () async {
                            if (nameCtrl.text.trim().isEmpty) {
                              showError(context, 'Farmer name required');
                              return;
                            }
                            Navigator.of(ctx, rootNavigator: true).pop();
                            try {
                              final tid = ref
                                  .read(appUserProvider)
                                  .valueOrNull
                                  ?.traderId;
                              await _c.from('farms').insert({
                                'trader_id': tid,
                                'farmer_name': nameCtrl.text.trim(),
                                'farm_name': farmCtrl.text.trim().isEmpty
                                    ? null
                                    : farmCtrl.text.trim(),
                                'phone': phoneCtrl.text.trim().isEmpty
                                    ? null
                                    : phoneCtrl.text.trim(),
                                'location': locCtrl.text.trim().isEmpty
                                    ? null
                                    : locCtrl.text.trim(),
                                'credit_days':
                                int.tryParse(creditCtrl.text.trim()) ?? 7,
                                'default_rate_per_kg':
                                rateCtrl.text.trim().isEmpty
                                    ? null
                                    : double.tryParse(rateCtrl.text.trim()),
                                'company_id': selectedCompanyId,
                              });
                              _load();
                              if (mounted) {
                                showSuccess(context, 'Supplier added');
                              }
                            } catch (e) {
                              if (mounted) {
                                showError(context,
                                    e.toString().replaceAll('Exception: ', ''));
                              }
                            }
                          },
                          child: const Text('Add Supplier')),
                    ])))));
  }

  void _showEditFarm(Map<String, dynamic> farm) {
    final nameCtrl =
    TextEditingController(text: farm['farmer_name'] as String? ?? '');
    final farmCtrl =
    TextEditingController(text: farm['farm_name'] as String? ?? '');
    final phoneCtrl =
    TextEditingController(text: farm['phone'] as String? ?? '');
    final locCtrl =
    TextEditingController(text: farm['location'] as String? ?? '');
    final creditCtrl =
    TextEditingController(text: (farm['credit_days'] ?? 7).toString());
    final rateCtrl = TextEditingController(
        text: farm['default_rate_per_kg'] != null
            ? (farm['default_rate_per_kg'] as num).toStringAsFixed(2)
            : '');
    final bankNameCtrl =
    TextEditingController(text: farm['bank_name'] as String? ?? '');
    final bankAcctCtrl =
    TextEditingController(text: farm['bank_account'] as String? ?? '');
    final bankIfscCtrl =
    TextEditingController(text: farm['bank_ifsc'] as String? ?? '');
    String? selectedCompanyId = farm['company_id'] as String?;

    _showSheet(
        maxWidth: WebSize.dialogMd,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, ss) => Padding(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(ctx).viewInsets.bottom),
                child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Row(children: [
                        const Expanded(
                            child: Text('Edit Supplier',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800))),
                        IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () =>
                                Navigator.of(ctx, rootNavigator: true).pop()),
                      ]),
                      const SizedBox(height: 12),
                      TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                              labelText: 'Farmer Name *')),
                      const SizedBox(height: 8),
                      TextField(
                          controller: farmCtrl,
                          decoration:
                          const InputDecoration(labelText: 'Farm Name')),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                            child: TextField(
                                controller: phoneCtrl,
                                keyboardType: TextInputType.phone,
                                decoration:
                                const InputDecoration(labelText: 'Phone'))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: TextField(
                                controller: creditCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    labelText: 'Credit Days',
                                    suffixText: 'days'))),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                            child: TextField(
                                controller: locCtrl,
                                decoration: const InputDecoration(
                                    labelText: 'Location'))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: TextField(
                                controller: rateCtrl,
                                keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                                decoration: const InputDecoration(
                                    labelText: 'Default Rate Rs./kg',
                                    prefixText: 'Rs.'))),
                      ]),
                      const SizedBox(height: 8),
                      const Text('BANK DETAILS',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: kTextHint,
                              letterSpacing: 0.5)),
                      const SizedBox(height: 6),
                      TextField(
                          controller: bankNameCtrl,
                          decoration:
                          const InputDecoration(labelText: 'Bank Name')),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                            child: TextField(
                                controller: bankAcctCtrl,
                                decoration: const InputDecoration(
                                    labelText: 'Account No.'))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: TextField(
                                controller: bankIfscCtrl,
                                decoration: const InputDecoration(
                                    labelText: 'IFSC Code'))),
                      ]),
                      if (_companies.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                            initialValue: selectedCompanyId,
                            decoration:
                            const InputDecoration(labelText: 'Company'),
                            items: [
                              const DropdownMenuItem(
                                  value: null, child: Text('None')),
                              ..._companies.map((c) => DropdownMenuItem(
                                  value: c['id'] as String,
                                  child: Text(
                                      c['company_name'] as String? ?? '--'))),
                            ],
                            onChanged: (v) => ss(() => selectedCompanyId = v)),
                      ],
                      const SizedBox(height: 16),
                      ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 48)),
                          onPressed: () async {
                            if (nameCtrl.text.trim().isEmpty) {
                              showError(context, 'Farmer name required');
                              return;
                            }
                            Navigator.of(ctx, rootNavigator: true).pop();
                            try {
                              await _c.from('farms').update({
                                'farmer_name': nameCtrl.text.trim(),
                                'farm_name': farmCtrl.text.trim().isEmpty
                                    ? null
                                    : farmCtrl.text.trim(),
                                'phone': phoneCtrl.text.trim().isEmpty
                                    ? null
                                    : phoneCtrl.text.trim(),
                                'location': locCtrl.text.trim().isEmpty
                                    ? null
                                    : locCtrl.text.trim(),
                                'credit_days':
                                int.tryParse(creditCtrl.text.trim()) ?? 7,
                                'default_rate_per_kg':
                                rateCtrl.text.trim().isEmpty
                                    ? null
                                    : double.tryParse(rateCtrl.text.trim()),
                                'bank_name': bankNameCtrl.text.trim().isEmpty
                                    ? null
                                    : bankNameCtrl.text.trim(),
                                'bank_account': bankAcctCtrl.text.trim().isEmpty
                                    ? null
                                    : bankAcctCtrl.text.trim(),
                                'bank_ifsc': bankIfscCtrl.text.trim().isEmpty
                                    ? null
                                    : bankIfscCtrl.text.trim(),
                                'company_id': selectedCompanyId,
                                'updated_at': DateTime.now().toIso8601String(),
                              }).eq('id', farm['id'] as String);
                              _load();
                              if (mounted) {
                                showSuccess(context, 'Supplier updated');
                              }
                            } catch (e) {
                              if (mounted) {
                                showError(context,
                                    e.toString().replaceAll('Exception: ', ''));
                              }
                            }
                          },
                          child: const Text('Save Changes')),
                    ])))));
  }

  // GAP 4: Export report as plain text summary (share sheet)
  Future<void> _exportReport() async {
    final rd = _reportData;
    if (rd == null) {
      showError(context, 'Load report data first');
      return;
    }
    final aggs = rd['aggregates'] as Map<String, dynamic>?;
    final entries =
    List<Map<String, dynamic>>.from(rd['entries'] as List? ?? []);

    final lines = StringBuffer();
    lines.writeln('PURCHASE REPORT');
    lines.writeln('Period: $_fromStr to $_toStr');
    lines.writeln(
        'Generated: ${DateFormat("d MMM yyyy HH:mm").format(DateTime.now())}');
    lines.writeln('');
    lines.writeln('SUMMARY');
    lines.writeln(
        'Total DCs:         ${aggs?["pending_rate"] is num ? ((aggs?["total_birds"] as num?)?.toInt() ?? 0) : 0} birds');
    lines.writeln(
        'Total Weight:      ${(aggs?["total_weight_kg"] as num?)?.toStringAsFixed(1) ?? 0} kg');
    lines.writeln(
        'Total Purchase:    ${Fmt.amount((aggs?["total_amount"] as num?)?.toDouble() ?? 0)}');
    lines.writeln(
        'Total Paid:        ${Fmt.amount((aggs?["total_paid"] as num?)?.toDouble() ?? 0)}');
    lines.writeln(
        'Outstanding:       ${Fmt.amount((aggs?["total_outstanding"] as num?)?.toDouble() ?? 0)}');
    lines.writeln(
        'Pending Rate:      ${(aggs?["pending_rate"] as num?)?.toInt() ?? 0} DCs');
    lines.writeln('');
    lines.writeln('DC DETAILS');
    lines.writeln(
        'DC No          | Date     | Farmer       | Birds | Kg     | Rate    | Total      | Status');
    lines.writeln(
        '--------------------------------------------------------------------------------------------');
    for (final e in entries) {
      lines.writeln('${(e["dc_number"] as String? ?? "—").padRight(15)}'
          '| ${(e["dc_date"] as String? ?? "").padRight(9)}'
          '| ${(e["farmer_name"] as String? ?? "—").padRight(13)}'
          '| ${(e["bird_count"] as num? ?? 0).toString().padRight(6)}'
          '| ${((e["net_weight_kg"] as num?)?.toStringAsFixed(1) ?? "0").padRight(7)}'
          '| ${((e["purchase_rate_per_kg"] as num?)?.toStringAsFixed(2) ?? "—").padRight(8)}'
          '| ${Fmt.amount((e["total_landed_cost"] as num?)?.toDouble() ?? 0).padRight(11)}'
          '| ${e["status"] ?? "—"}');
    }

    try {
      // Use share_plus to show native share sheet
      await Share.share(lines.toString(),
          subject: 'Purchase Report: $_fromStr to $_toStr');
    } catch (e) {
      // Fallback: copy to clipboard via SnackBar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Export: ${e.toString().substring(0, 60)}'),
            duration: const Duration(seconds: 3)));
      }
    }
  }

  void _showAddCompany() {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final gstCtrl = TextEditingController();

    _showSheet(
        maxWidth: WebSize.dialogMd,
        builder: (ctx) => Padding(
            padding:
            EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    const Expanded(
                        child: Text('Add Poultry Company',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800))),
                    IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () =>
                            Navigator.of(ctx, rootNavigator: true).pop()),
                  ]),
                  const SizedBox(height: 12),
                  TextField(
                      controller: nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration:
                      const InputDecoration(labelText: 'Company Name *')),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: codeCtrl,
                            decoration: const InputDecoration(
                                labelText: 'Code (optional)'))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextField(
                            controller: phoneCtrl,
                            keyboardType: TextInputType.phone,
                            decoration:
                            const InputDecoration(labelText: 'Phone'))),
                  ]),
                  const SizedBox(height: 8),
                  TextField(
                      controller: gstCtrl,
                      decoration: const InputDecoration(
                          labelText: 'GST Number (optional)')),
                  const SizedBox(height: 16),
                  ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48)),
                      onPressed: () async {
                        if (nameCtrl.text.trim().isEmpty) {
                          showError(context, 'Company name required');
                          return;
                        }
                        Navigator.of(ctx, rootNavigator: true).pop();
                        try {
                          final tid =
                              ref.read(appUserProvider).valueOrNull?.traderId;
                          await _c.from('poultry_companies').insert({
                            'trader_id': tid,
                            'company_name': nameCtrl.text.trim(),
                            'company_code': codeCtrl.text.trim().isEmpty
                                ? null
                                : codeCtrl.text.trim(),
                            'phone': phoneCtrl.text.trim().isEmpty
                                ? null
                                : phoneCtrl.text.trim(),
                            'gst_number': gstCtrl.text.trim().isEmpty
                                ? null
                                : gstCtrl.text.trim(),
                          });
                          _load();
                          if (mounted) showSuccess(context, 'Company added');
                        } catch (e) {
                          if (mounted) {
                            showError(context,
                                e.toString().replaceAll('Exception: ', ''));
                          }
                        }
                      },
                      child: const Text('Add Company')),
                ]))));
  }

  // ==========================================================================
  // SHARED WIDGETS
  // ==========================================================================

  Widget _alertBanner(IconData icon, String msg, Color c,
      {VoidCallback? onTap}) =>
      GestureDetector(
          onTap: onTap,
          child: Container(
              color: c.withValues(alpha: 0.08),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                Icon(icon, color: c, size: 14),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(msg,
                        style: TextStyle(
                            fontSize: 11,
                            color: c,
                            fontWeight: FontWeight.w600))),
                if (onTap != null)
                  Icon(Icons.arrow_forward_ios, color: c, size: 10),
              ])));

  Widget _kpiCard(String label, String value, Color color, IconData icon) =>
      Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: kBorder)),
          child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: color, size: 16),
            const Spacer(),
            Text(value,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w900, color: color)),
            Text(label,
                style: const TextStyle(fontSize: 9, color: kTextHint),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ]));

  Widget _sectionHeader(String title,
      {String? action, VoidCallback? onAction}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: kTextHint,
                    letterSpacing: 0.5)),
            const Spacer(),
            if (action != null && onAction != null)
              GestureDetector(
                  onTap: onAction,
                  child: Text(action,
                      style: const TextStyle(
                          fontSize: 10,
                          color: kPrimary,
                          fontWeight: FontWeight.w700))),
          ]));

  // Overview KPI tile — used in stock valuation section
  Widget _ovKpi(String label, String value, Color color, IconData icon) =>
      Expanded(
          child: Column(children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, color: color),
                textAlign: TextAlign.center),
            Text(label,
                style: const TextStyle(fontSize: 8, color: kTextHint),
                textAlign: TextAlign.center),
          ]));

  Widget _statusChip(String t, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6)),
      child: Text(t,
          style:
          TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: c)));

  Widget _pStat(String l, String v, Color c) => Expanded(
      child: Column(children: [
        Text(v,
            style:
            TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c),
            textAlign: TextAlign.center),
        Text(l,
            style: const TextStyle(fontSize: 8, color: kTextHint),
            textAlign: TextAlign.center),
      ]));

  Widget _calcRow(String l, String v, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(
            child: Text(l,
                style: TextStyle(
                    fontSize: 11,
                    color: kTextSub,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.normal))),
        Text(v,
            style: TextStyle(
                fontSize: 11,
                fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
                color: bold ? kPrimary : kTextMain)),
      ]));

  @override
  Widget build(BuildContext context) => ResponsiveLayout(
    mobile:  (_) => _buildScaffold(context),
    desktop: (_) => _buildWeb(context),
  );
}

// =============================================================================
// FORMATTERS — this file used to define its own local `class Fmt` here,
// which silently SHADOWED the correct, shared Fmt already imported from
// core/theme/app_theme.dart (line 9) for this entire file — every
// Fmt.amount()/Fmt.amountShort() call below was actually using this
// local, K/L-compacting duplicate instead of the canonical one, despite
// the import being present and correct. Removed entirely; the existing
// import now resolves Fmt.amount() correctly everywhere below with zero
// other changes. Fmt.amountShort() calls were updated to Fmt.amount()
// (see the three call sites) since "short" compact currency display is
// exactly what's being eliminated — the canonical Fmt has no compact
// variant to fall back to, by design.
// =============================================================================