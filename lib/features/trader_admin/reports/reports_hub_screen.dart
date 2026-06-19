import 'dart:math' show min;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';
import 'report_pdf_generator.dart';
import '../../../shared/layouts/responsive_layout.dart';

// ─────────────────────────────────────────────────────────────────────────────
// REPORTS HUB  — designed for 40+ age traders
// Large text, high contrast, easy to read
// ─────────────────────────────────────────────────────────────────────────────

enum DatePreset { today, last7, last30, thisMonth, custom }

extension DatePresetX on DatePreset {
  String get label => switch (this) {
    DatePreset.today     => 'Today',
    DatePreset.last7     => 'Last 7',
    DatePreset.last30    => 'Last 30',
    DatePreset.thisMonth => 'This Month',
    DatePreset.custom    => 'Custom',
  };
  (DateTime, DateTime) get range {
    final now = DateTime.now();
    return switch (this) {
      DatePreset.today     => (now, now),
      DatePreset.last7     => (now.subtract(const Duration(days: 6)), now),
      DatePreset.last30    => (now.subtract(const Duration(days: 29)), now),
      DatePreset.thisMonth => (DateTime(now.year, now.month, 1), now),
      DatePreset.custom    => (now.subtract(const Duration(days: 6)), now),
    };
  }
}

class _Rep {
  final String key, label;
  final IconData icon;
  final Color color;
  const _Rep(this.key, this.label, this.icon, this.color);
}

const _kR = [
  _Rep('daily_summary',        'Daily Summary',      Icons.today_outlined,             Color(0xFF1565C0)),
  _Rep('stock_reconciliation', 'Stock Recon.',        Icons.inventory_2_outlined,       Color(0xFF2E7D32)),
  _Rep('shrinkage',            'Shrinkage',           Icons.compress_outlined,          Color(0xFF6A1B9A)),
  _Rep('mortality',            'Mortality',           Icons.health_and_safety_outlined, Color(0xFFC62828)),
  _Rep('delivery_history',     'Deliveries',          Icons.local_shipping_outlined,    Color(0xFF00695C)),
  _Rep('agent_performance',    'Agent Report',        Icons.person_outlined,            Color(0xFF1565C0)),
  _Rep('shift_audit',          'Shift Audit',         Icons.assignment_outlined,        Color(0xFF37474F)),
  _Rep('expense',              'Expenses',            Icons.receipt_long_outlined,      Color(0xFFE65100)),
  _Rep('collection',           'Collection',          Icons.payments_outlined,          Color(0xFF1B5E20)),
  _Rep('retailer_purchase',    'Retailer Purchase',   Icons.store_outlined,             Color(0xFF4A148C)),
  _Rep('profitability',        'Profitability',       Icons.trending_up_outlined,       Color(0xFF004D40)),
  // ── Phase 5: Pricing Analytics ──────────────────────────────────────────
  _Rep('product_sales',        'Product Sales',       Icons.egg_alt_outlined,           Color(0xFF1A237E)),
  _Rep('zone_sales',           'Zone Sales',          Icons.map_outlined,               Color(0xFF006064)),
  _Rep('discount_leakage',     'Discount Leakage',    Icons.remove_circle_outline,      Color(0xFFBF360C)),
  _Rep('rate_source_breakdown','Rate Source',         Icons.auto_fix_high_outlined,     Color(0xFF4527A0)),
  _Rep('profitability_enhanced','Profit (Full)',      Icons.analytics_outlined,         Color(0xFF1B5E20)),
  // ── Phase 4/UI: Profitability Breakdown (by product/variant/retailer/zone/agent/batch) ──
  _Rep('profitability_breakdown','Profit by...',       Icons.pie_chart_outline,           Color(0xFF004D40)),
];

// ─────────────────────────────────────────────────────────────────────────────
class ReportsHubScreen extends ConsumerStatefulWidget {
  const ReportsHubScreen({super.key});
  @override ConsumerState<ReportsHubScreen> createState() => _RHS();
}

class _RHS extends ConsumerState<ReportsHubScreen> {
  final _c = Supabase.instance.client;
  _Rep       _sel    = _kR.first;
  DatePreset _preset = DatePreset.last7;
  DateTime   _from   = DateTime.now().subtract(const Duration(days: 6));
  DateTime   _to     = DateTime.now();
  bool       _loading = false;
  Map<String,dynamic>? _data;
  String?    _error;
  String?    _agentId;
  String?    _retailerId;
  String     _profitDimension = 'product'; // Phase 4 UI: product|variant|retailer|zone|agent|batch
  List<Map<String,dynamic>> _agents    = [];
  List<Map<String,dynamic>> _retailers = [];

  @override
  void initState() { super.initState(); _loadFilters(); _load(); }

  Future<void> _loadFilters() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    final ag = await _c.from('delivery_agents')
        .select('id,name').eq('trader_id',tid).eq('is_active',true).order('name');
    final rt = await _c.from('retailers')
        .select('id,shop_name').eq('trader_id',tid).eq('is_active',true)
        .order('shop_name').limit(50);
    if (mounted) setState(() {
      _agents    = List<Map<String,dynamic>>.from(ag as List? ?? []);
      _retailers = List<Map<String,dynamic>>.from(rt as List? ?? []);
    });
  }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    setState(() { _loading=true; _error=null; _data=null; });
    final isPricingAnalytics = const {
      'product_sales', 'zone_sales', 'discount_leakage',
      'rate_source_breakdown', 'profitability_enhanced',
    }.contains(_sel.key);
    final isProfitBreakdown = _sel.key == 'profitability_breakdown';

    try {
      final p = <String,dynamic>{
        'p_trader_id': tid,
        'p_from_date': DateFormat('yyyy-MM-dd').format(_from),
        'p_to_date':   DateFormat('yyyy-MM-dd').format(_to),
      };
      String rpcName;
      if (isProfitBreakdown) {
        // Phase 3 backend RPC — single function covering all 6 dimensions.
        // No new accounting logic here; this just picks which dimension to ask for.
        rpcName = 'get_profitability_breakdown';
        p['p_dimension'] = _profitDimension;
        if (_agentId != null)    p['p_agent_id']    = _agentId;
        if (_retailerId != null) p['p_retailer_id'] = _retailerId;
      } else if (isPricingAnalytics) {
        rpcName = 'get_pricing_analytics';
        p['p_report'] = _sel.key;
      } else {
        rpcName = 'get_report_data';
        p['p_report'] = _sel.key;
        if (_agentId != null)    p['p_agent_id']    = _agentId;
        if (_retailerId != null) p['p_retailer_id'] = _retailerId;
      }
      final res = await _c.rpc(rpcName, params: p)
          .timeout(const Duration(seconds: 20));
      if (mounted) setState(() => _data = res as Map<String,dynamic>?);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceAll('Exception:','').trim());
    } finally {
      if (mounted) setState(() => _loading=false);
    }
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final _scaffold = Scaffold(
        backgroundColor: kBgPage,
        appBar: AppBar(
            backgroundColor: kSurface, elevation: 0,
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Reports', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              Text('${DateFormat("d MMM").format(_from)} – ${DateFormat("d MMM yyyy").format(_to)}',
                  style: const TextStyle(fontSize: 12, color: kTextSub)),
            ]),
            actions: [
              IconButton(icon: const Icon(Icons.tune_outlined, size: 22), onPressed: _showFilters,
                  tooltip: 'Filter'),
              IconButton(icon: const Icon(Icons.picture_as_pdf_outlined, size: 22), onPressed: _exportPdf,
                  tooltip: 'Export PDF'),
              IconButton(icon: const Icon(Icons.share_outlined, size: 22), onPressed: _shareReport,
                  tooltip: 'Share'),
            ]),
        body: Column(children: [
          _buildReportGrid(),
          _buildDateBar(),
          if (_sel.key == 'profitability_breakdown') _buildDimensionBar(),
          Expanded(child: _loading ? const LoadingList()
              : _error != null ? _buildError()
              : _data == null  ? const EmptyState(icon: Icons.bar_chart_outlined, message: 'Loading...')
              : _buildReport()),
        ]));

    return ResponsiveLayout(mobile: (_) => _scaffold, desktop: (_) => _scaffold);
  }

  // ─── REPORT GRID (2 rows, wraps properly — no overflow) ──────────────────
  Widget _buildReportGrid() => Container(
      color: kSurface,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Wrap(
          spacing: 6, runSpacing: 6,
          children: _kR.map((r) {
            final sel = r.key == _sel.key;
            return GestureDetector(
                onTap: () { setState(() { _sel=r; _data=null; }); _load(); },
                child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                        color: sel ? r.color : r.color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: sel ? r.color : r.color.withValues(alpha: 0.3))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(r.icon, size: 14, color: sel ? Colors.white : r.color),
                      const SizedBox(width: 5),
                      Text(r.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                          color: sel ? Colors.white : r.color)),
                    ])));
          }).toList()));

  // ─── DATE BAR ─────────────────────────────────────────────────────────────
  Widget _buildDateBar() => Container(
      color: kSurface,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Row(children: [
        Expanded(child: Row(children: DatePreset.values.where((p)=>p!=DatePreset.custom).map((p) =>
            Padding(padding: const EdgeInsets.only(right: 5),
                child: GestureDetector(
                    onTap: () {
                      final (f,t)=p.range;
                      setState(() { _preset=p; _from=f; _to=t; });
                      _load();
                    },
                    child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                            color: _preset==p ? kNavy : kBgGrey,
                            borderRadius: BorderRadius.circular(kRadiusChip)),
                        child: Text(p.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                            color: _preset==p ? Colors.white : kTextSub)))))).toList())),
        GestureDetector(
            onTap: _pickCustomRange,
            child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                    color: _preset==DatePreset.custom ? kNavy : kBgGrey,
                    borderRadius: BorderRadius.circular(kRadiusChip)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.date_range_outlined, size: 12,
                      color: _preset==DatePreset.custom ? Colors.white : kTextSub),
                  const SizedBox(width: 4),
                  Text('Custom', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                      color: _preset==DatePreset.custom ? Colors.white : kTextSub)),
                ]))),
      ]));

  // ─── DIMENSION BAR (Profitability Breakdown only) ──────────────────────────
  static const _kDims = [
    ('product',  'Product',  Icons.egg_alt_outlined),
    ('variant',  'Variant',  Icons.category_outlined),
    ('retailer', 'Retailer', Icons.storefront_outlined),
    ('zone',     'Zone',     Icons.map_outlined),
    ('agent',    'Agent',    Icons.person_outlined),
    ('batch',    'Batch',    Icons.inventory_2_outlined),
  ];

  Widget _buildDimensionBar() => Container(
      color: kSurface,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Wrap(
          spacing: 6, runSpacing: 6,
          children: _kDims.map((d) {
            final (key, lbl, icon) = d;
            final sel = _profitDimension == key;
            return GestureDetector(
                onTap: () { setState(() => _profitDimension = key); _load(); },
                child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: sel ? const Color(0xFF004D40) : const Color(0xFF004D40).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: sel ? const Color(0xFF004D40) : const Color(0xFF004D40).withValues(alpha: 0.3))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(icon, size: 13, color: sel ? Colors.white : const Color(0xFF004D40)),
                      const SizedBox(width: 4),
                      Text(lbl, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: sel ? Colors.white : const Color(0xFF004D40))),
                    ])));
          }).toList()));

  // ─── ERROR ────────────────────────────────────────────────────────────────
  Widget _buildError() => Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: kErrorBg, borderRadius: BorderRadius.circular(kRadiusCard)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 12),
            Text(_error ?? 'Error loading report', textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton.icon(onPressed: _load,
                icon: const Icon(Icons.refresh), label: const Text('Retry')),
          ]))));

  // ─── REPORT ROUTER ────────────────────────────────────────────────────────
  Widget _buildReport() => switch (_data?['report'] as String? ?? _sel.key) {
    'daily_summary'        => _rDailySummary(),
    'stock_reconciliation' => _rStockRecon(),
    'shrinkage'            => _rShrinkage(),
    'mortality'            => _rMortality(),
    'delivery_history'     => _rDeliveryHistory(),
    'agent_performance'    => _rAgentPerformance(),
    'shift_audit'          => _rShiftAudit(),
    'expense'              => _rExpense(),
    'collection'           => _rCollection(),
    'retailer_purchase'    => _rRetailerPurchase(),
    'profitability'        => _rProfitability(),
  // Phase 5: Pricing Analytics
    'product_sales'        => _rProductSales(),
    'zone_sales'           => _rZoneSales(),
    'discount_leakage'     => _rDiscountLeakage(),
    'rate_source_breakdown'=> _rRateSource(),
    'profitability_enhanced'=> _rProfitabilityEnhanced(),
    'profitability_breakdown'=> _rProfitabilityBreakdown(),
    _                      => const EmptyState(icon: Icons.bar_chart_outlined, message: 'No data'),
  };

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. DAILY SUMMARY
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _rDailySummary() {
    final s = _s(); final rows = _rows('daily');
    return _scroll([
      _kpiGrid([
        _kpi('Revenue',    Fmt.amount(_d(s,'total_revenue')),   const Color(0xFF1565C0), Icons.currency_rupee),
        _kpi('Collected',  Fmt.amount(_d(s,'total_collected')), Colors.green,            Icons.check_circle_outline),
        _kpi('Pending',    Fmt.amount(_d(s,'total_pending')),   Colors.orange,           Icons.pending_outlined),
        _kpi('Outstanding',Fmt.amount(_d(s,'total_outstanding')),Colors.red,             Icons.warning_amber_outlined),
      ]),
      _kpiGrid([
        _kpi2('DC Birds',    '${_i(s,"total_birds_dc")}',                              const Color(0xFF283593), Icons.egg_outlined),
        _kpi2('Gross Wt',    '${_d(s,"total_gross_wt").toStringAsFixed(0)} kg',        Colors.blueGrey,         Icons.scale_outlined),
        _kpi2('Tare Wt',     '${_d(s,"total_tare_wt").toStringAsFixed(0)} kg',         Colors.brown,            Icons.shopping_basket_outlined),
        _kpi2('Net Del Wt',  '${_d(s,"total_net_wt").toStringAsFixed(0)} kg',          Colors.teal,             Icons.verified_outlined),
      ]),
      _banner('Net Delivery Wt = Gross Weight  -  Cage/Tare Weight', Colors.teal),
      _sec('DAILY BREAKDOWN'),
      _tbl(
          ['Date','DC Birds','Gross Wt kg','Tare Wt kg','Net Del Wt kg','Revenue','Collected','Pending'],
          rows.map((d)=>[
            _fd(d['dt']),'${_i(d,"dc_birds")}',
            _kg(d,'gross_wt'), _kg(d,'tare_wt'), _kg(d,'net_wt'),
            Fmt.amount(_d(d,'revenue')), Fmt.amount(_d(d,'collected')), Fmt.amount(_d(d,'pending')),
          ]).toList(),
          tots:['TOTAL','${_i(s,"total_birds_dc")}',
            _kg(s,'total_gross_wt'), _kg(s,'total_tare_wt'), _kg(s,'total_net_wt'),
            Fmt.amount(_d(s,'total_revenue')), Fmt.amount(_d(s,'total_collected')), Fmt.amount(_d(s,'total_pending'))],
          hi:[5,6,7]),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. STOCK RECONCILIATION
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _rStockRecon() {
    final s = _s(); final rows = _rows('daily');
    return _scroll([
      Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: kSurface,
              borderRadius: BorderRadius.circular(kRadiusCard), border: Border.all(color: kBorderLight), boxShadow: kCardShadow),
          child: Column(children: [
            _hdr('Stock Reconciliation', Icons.inventory_2_outlined, kSuccess),
            _reconR('Opening Stock',     '${_i(s,"opening")} birds',          '',                                        Colors.grey),
            _reconR('+ DC Loaded',        '${_i(s,"dc_loaded")} birds',        '${_d(s,"dc_loaded_kg").toStringAsFixed(0)} kg',   Colors.blue),
            _reconR('- Delivered',        '${_i(s,"delivered")} birds',        '${_d(s,"delivered_kg").toStringAsFixed(0)} kg',   Colors.green),
            _reconR('+ Returned',         '${_i(s,"returned")} birds',         '${_d(s,"returned_kg").toStringAsFixed(0)} kg',    Colors.teal),
            _reconR('- Mortality',        '${_i(s,"mortality")} birds',        '${_d(s,"mortality_kg").toStringAsFixed(0)} kg',   Colors.red),
            _reconR('- Transferred Out',  '${_i(s,"transferred_out")} birds',  '',                                        Colors.orange),
            _reconR('- Shrinkage',        '',                                   '${_d(s,"shrinkage_kg").toStringAsFixed(2)} kg',  const Color(0xFF6A1B9A)),
            Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFF2E7D32).withValues(alpha: 0.07),
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15))),
                child: Row(children: [
                  const Text('= Closing Stock',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF2E7D32))),
                  const Spacer(),
                  Text('${_i(s,"closing")} birds',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF2E7D32))),
                ])),
          ])),
      _sec('DAILY BREAKDOWN'),
      _tbl(['Date','DC Birds','DC kg','Del Birds','Del kg','Returned','Mortality','Transfer'],
          rows.map((d)=>[_fd(d['dt']),'${_i(d,"dc_birds")}',_kg(d,'dc_kg'),'${_i(d,"del_birds")}',
            _kg(d,'del_kg'),'${_i(d,"ret_birds")}','${_i(d,"mort_birds")}','${_i(d,"transfer_out")}']).toList(),
          hi:[3,4]),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. SHRINKAGE
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _rShrinkage() {
    final s = _s(); final rows = _rows('rows');
    return _scroll([
      _banner('Shrinkage = DC Loaded kg  -  Delivered Net kg  -  Returned kg  -  Mortality kg', const Color(0xFF6A1B9A)),
      _kpiGrid([
        _kpi2('DC Loaded',   '${_d(s,"total_dc_kg").toStringAsFixed(0)} kg',       Colors.blue,             Icons.local_shipping_outlined),
        _kpi2('Shrinkage',   '${_d(s,"total_shrinkage_kg").toStringAsFixed(1)} kg', const Color(0xFF6A1B9A),Icons.compress_outlined),
        _kpi2('Avg Loss',    '${_d(s,"avg_loss_pct").toStringAsFixed(2)}%',         _d(s,'avg_loss_pct')>2?Colors.red:Colors.green, Icons.percent_outlined),
        _kpi2('High Loss',   '${_i(s,"high_loss_shifts")} shifts',                  Colors.red,              Icons.warning_amber_outlined),
      ]),
      _sec('SHIFT-WISE SHRINKAGE'),
      _tbl(['Date','Agent','DC Birds','DC kg','Del kg','Ret kg','Mort kg','Shrink kg','Loss%'],
          rows.map((r){
            final lp=_d(r,'loss_percent');
            return [_fd(r['shift_date']),_str(r,'agent_name'),'${_i(r,"dc_total_birds")}',
              '${_d(r,"dc_total_weight_kg").toStringAsFixed(1)}','${_d(r,"delivered_weight_kg").toStringAsFixed(1)}',
              '${_d(r,"returned_weight_kg").toStringAsFixed(1)}','${_d(r,"mortality_weight_kg").toStringAsFixed(1)}',
              '${_d(r,"shrinkage_kg").toStringAsFixed(2)}','${lp.toStringAsFixed(2)}%'];
          }).toList(),
          hi:[7,8], warnC:8, warnT:2.0),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. MORTALITY
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _rMortality() {
    final s = _s(); final rows = _rows('rows');
    return _scroll([
      _kpiGrid([
        _kpi('Mort Birds', '${_i(s,"total_mortality_birds")}',                       Colors.red,   Icons.health_and_safety_outlined),
        _kpi('Mort kg',    '${_d(s,"total_mortality_kg").toStringAsFixed(1)} kg',     Colors.red.shade700, Icons.scale_outlined),
        _kpi('DC Birds',   '${_i(s,"total_dc_birds")}',                              Colors.blue,  Icons.egg_outlined),
        _kpi('Mort Rate',  '${_d(s,"mortality_rate_pct").toStringAsFixed(2)}%',
            _d(s,'mortality_rate_pct')>1?Colors.red:Colors.green, Icons.percent_outlined),
      ]),
      if (rows.isEmpty) const Padding(padding: EdgeInsets.all(40),
          child: EmptyState(icon: Icons.check_circle_outline, message: 'No mortality recorded'))
      else ...[
        _sec('MORTALITY RECORDS'),
        _tbl(['Date','Agent','Shop','DC Birds','Delivered','Dead','Mort kg','Weak','Rejected'],
            rows.map((r)=>[_fd(r['del_date']),_str(r,'agent_name'),_sh(_str(r,'shop_name'),12),
              '${_i(r,"dc_birds")}','${_i(r,"del_birds")}','${_i(r,"mortality_birds")}',
              '${_d(r,"mortality_weight_kg").toStringAsFixed(1)}','${_i(r,"weak_birds")}','${_i(r,"rejected_birds")}']).toList(),
            hi:[5,6], warnC:5, warnT:5),
      ],
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. DELIVERY HISTORY
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _rDeliveryHistory() {
    final s = _s(); final rows = _rows('rows');
    return _scroll([
      _banner('Net Delivery Weight = Gross Weight  -  Cage/Tare Weight', Colors.teal),
      _kpiGrid([
        _kpi2('Deliveries', '${_i(s,"total_deliveries")}',                         Colors.blue,     Icons.local_shipping_outlined),
        _kpi2('Gross Wt',   '${_d(s,"total_gross_wt").toStringAsFixed(0)} kg',     Colors.blueGrey, Icons.scale_outlined),
        _kpi2('Tare Wt',    '${_d(s,"total_tare_wt").toStringAsFixed(0)} kg',      Colors.brown,    Icons.shopping_basket_outlined),
        _kpi2('Net Del Wt', '${_d(s,"total_net_del_wt").toStringAsFixed(0)} kg',   Colors.teal,     Icons.verified_outlined),
      ]),
      _sec('DELIVERY RECORDS'),
      _tbl(['Date','Agent','Shop','DC#','Gross Wt','Tare Wt','Net Del Wt','DC Birds','Del Birds','Mort','Collected'],
          rows.map((r)=>[_fd(r['del_date']),_str(r,'agent_name'),_sh(_str(r,'shop_name'),10),
            _sh(_str(r,'dc_number'),8),
            '${_d(r,"gross_weight").toStringAsFixed(0)}','${_d(r,"tare_weight").toStringAsFixed(0)}',
            '${_d(r,"net_del_weight").toStringAsFixed(0)}',
            '${_i(r,"dc_birds")}','${_i(r,"del_birds")}','${_i(r,"mortality_birds")}',
            Fmt.amount(_d(r,'collected_amount'))]).toList(),
          hi:[6]),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 6. AGENT PERFORMANCE
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _rAgentPerformance() {
    final agents = _rows('agents'); final daily = _rows('daily');
    return _scroll([
      ...agents.map((a) {
        final lp = _d(a,'loss_pct');
        return Container(
            margin: const EdgeInsets.fromLTRB(12,10,12,0),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: kSurface,
                borderRadius: BorderRadius.circular(kRadiusCard), border: Border.all(color: kBorderLight), boxShadow: kCardShadow),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 44, height: 44,
                    decoration: BoxDecoration(color: kNavy, borderRadius: BorderRadius.circular(kRadiusChip)),
                    child: Center(child: Text((_str(a,'agent_name'))[0],
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: kGoldLight)))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_str(a,'agent_name'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  if (a['vehicle_no'] != null) Text(_str(a,'vehicle_no'),
                      style: const TextStyle(fontSize: 12, color: kTextSub)),
                ])),
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: lp>2?kError.withValues(alpha: 0.08):kSuccess.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(kRadiusChip)),
                    child: Text('Loss: ${lp.toStringAsFixed(2)}%',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                            color: lp>2?Colors.red:Colors.green))),
              ]),
              const SizedBox(height: 12), const Divider(height:1), const SizedBox(height: 10),
              Row(children: [
                _st('Deliveries','${_i(a,"deliveries")}'),
                _st('Birds','${_i(a,"del_birds")}'),
                _st('Net kg','${_d(a,"del_weight").toStringAsFixed(0)}'),
                _st('Mortality','${_i(a,"mortality")}'),
                _st('Shrink kg','${_d(a,"shrinkage_kg").toStringAsFixed(2)}'),
                _st('Cash',Fmt.amount(_d(a,'cash_collected'))),
              ]),
            ]));
      }),
      _sec('DAILY TREND'),
      _tbl(['Date','Del Birds','Net kg','Mortality','Shrink kg','Collected'],
          daily.map((d)=>[_fd(d['dt']),'${_i(d,"del_birds")}','${_d(d,"del_weight").toStringAsFixed(0)}',
            '${_i(d,"mortality")}','${_d(d,"shrinkage").toStringAsFixed(2)}',Fmt.amount(_d(d,'collected'))]).toList()),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 7. SHIFT AUDIT
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _rShiftAudit() {
    final shifts = _rows('shifts');
    if (shifts.isEmpty) return const EmptyState(icon: Icons.assignment_outlined, message: 'No closed shifts');
    return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16,16,16,80),
        itemCount: shifts.length,
        itemBuilder: (_, i) {
          final s = shifts[i];
          final approved = s['shift_approval_status'] == 'approved';
          final lp = _d(s,'loss_percent');
          return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: kSurface,
                  borderRadius: BorderRadius.circular(kRadiusCard), border: Border.all(color: kBorderLight), boxShadow: kCardShadow),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_str(s,'agent_name'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(_fd(s['shift_date']),
                        style: const TextStyle(fontSize: 13, color: kTextSub)),
                  ])),
                  Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                          color: approved?kSuccess.withValues(alpha: 0.08):Colors.orange.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(kRadiusChip)),
                      child: Text(approved?'APPROVED':'PENDING',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                              color: approved?Colors.green:Colors.orange))),
                ]),
                const SizedBox(height: 10), const Divider(height:1), const SizedBox(height: 10),
                _sR('DC Loaded',  '${_d(s,"dc_loaded_kg").toStringAsFixed(0)} kg', Colors.blue),
                _sR('Delivered',  '${_i(s,"delivered_birds")} birds / ${_d(s,"delivered_kg").toStringAsFixed(0)} kg', Colors.green),
                _sR('Returned',   '${_d(s,"returned_weight").toStringAsFixed(0)} kg', Colors.teal),
                _sR('Mortality',  '${_i(s,"total_mortality")} birds', Colors.red),
                _sR('Shrinkage',  '${_d(s,"shrinkage_kg").toStringAsFixed(2)} kg  (${lp.toStringAsFixed(2)}%)',
                    lp>2?Colors.red:const Color(0xFF6A1B9A)),
                const SizedBox(height: 8), const Divider(height:1), const SizedBox(height: 8),
                Row(children: [
                  _st('Cash',     Fmt.amount(_d(s,'total_cash_collected'))),
                  _st('Expenses', Fmt.amount(_d(s,'total_expenses'))),
                  _st('KM',       '${_d(s,"distance_km").toStringAsFixed(0)}'),
                  _st('Crates',   '${_i(s,"crates_taken")} → ${_i(s,"crates_returned")}'),
                  _st('Orders',   '${_i(s,"total_orders")}'),
                ]),
              ]));
        });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 8. EXPENSE
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _rExpense() {
    final s = _s(); final byA = _rows('by_agent'); final day = _rows('daily');
    return _scroll([
      _kpiGrid([
        _kpi('Total Exp', Fmt.amount(_d(s,'total_expenses')), Colors.orange,     Icons.receipt_long_outlined),
        _kpi('Diesel',    Fmt.amount(_d(s,'diesel')),         Colors.deepOrange, Icons.local_gas_station_outlined),
        _kpi('Allowance', Fmt.amount(_d(s,'allowance')),      Colors.amber.shade700, Icons.person_outline),
        _kpi('Total KM',  '${_d(s,"total_km").toStringAsFixed(0)}', Colors.blue, Icons.route_outlined),
      ]),
      _sec('BY AGENT'),
      _tbl(['Agent','Shifts','Diesel','Allowance','Total Exp','KM'],
          byA.map((a)=>[_str(a,'agent_name'),'${_i(a,"shifts")}',Fmt.amount(_d(a,'diesel')),
            Fmt.amount(_d(a,'allowance')),Fmt.amount(_d(a,'total_expenses')),'${_d(a,"km_driven").toStringAsFixed(0)}']).toList(),
          hi:[4]),
      _sec('DAILY EXPENSES'),
      _tbl(['Date','Agent','Diesel','Allowance','Total','KM'],
          day.map((d)=>[_fd(d['dt']),_str(d,'agent_name'),Fmt.amount(_d(d,'diesel_cost')),
            Fmt.amount(_d(d,'allowance')),Fmt.amount(_d(d,'total_expenses')),'${_d(d,"distance_km").toStringAsFixed(0)}']).toList(),
          hi:[4]),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 9. COLLECTION
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _rCollection() {
    final s = _s(); final ret = _rows('retailers'); final day = _rows('daily');
    final bil=_d(s,'total_billed'); final col=_d(s,'total_collected'); final pen=_d(s,'total_pending');
    return _scroll([
      _kpiGrid([
        _kpi('Billed',      Fmt.amount(bil),                                   Colors.blue,   Icons.receipt_outlined),
        _kpi('Collected',   Fmt.amount(col),                                   Colors.green,  Icons.check_circle_outline),
        _kpi('Pending',     Fmt.amount(pen),                                   Colors.orange, Icons.pending_outlined),
        _kpi('Outstanding', Fmt.amount(_d(s,'total_outstanding')),             Colors.red,    Icons.warning_amber_outlined),
      ]),
      Container(margin: const EdgeInsets.fromLTRB(12,0,12,8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard), border: Border.all(color: kBorderLight), boxShadow: kCardShadow),
          child: Row(children: [
            _st('Cash', Fmt.amount(_d(s,'cash'))), _st('UPI', Fmt.amount(_d(s,'upi'))),
            _st('Bank', Fmt.amount(_d(s,'bank'))), _st('Credit', Fmt.amount(_d(s,'credit'))),
          ])),
      if (ret.isNotEmpty) ...[
        _sec('BY RETAILER'),
        _tbl(['Shop','Orders','Billed','Collected','Outstanding'],
            ret.map((r)=>[_sh(_str(r,'shop_name'),14),'${_i(r,"orders")}',
              Fmt.amount(_d(r,'billed')),Fmt.amount(_d(r,'collected')),Fmt.amount(_d(r,'outstanding'))]).toList(),
            hi:[4]),
      ],
      _sec('DAILY COLLECTION'),
      _tbl(['Date','Billed','Collected','Pending'],
          day.map((d)=>[_fd(d['dt']),Fmt.amount(_d(d,'billed')),Fmt.amount(_d(d,'collected')),Fmt.amount(_d(d,'pending'))]).toList(),
          tots:['TOTAL',Fmt.amount(bil),Fmt.amount(col),Fmt.amount(pen)], hi:[1,2,3]),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 10. RETAILER PURCHASE
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _rRetailerPurchase() {
    final s = _s(); final ret = _rows('retailers'); final day = _rows('daily');
    return _scroll([
      _kpiGrid([
        _kpi2('Orders',    '${_i(s,"total_orders")}',                              Colors.blue,   Icons.shopping_cart_outlined),
        _kpi2('Total kg',  '${_d(s,"total_kg").toStringAsFixed(0)}',               Colors.teal,   Icons.scale_outlined),
        _kpi2('Billed',    Fmt.amount(_d(s,'total_billed')),                       Colors.indigo, Icons.receipt_outlined),
        _kpi2('Pending',   Fmt.amount(_d(s,'total_pending')),                      Colors.orange, Icons.pending_outlined),
      ]),
      if (ret.isNotEmpty) ...[
        _sec('BY RETAILER'),
        _tbl(['Shop','Phone','Orders','Total kg','Billed','Collected','Outstanding'],
            ret.map((r)=>[_sh(_str(r,'shop_name'),12),_str(r,'phone'),'${_i(r,"orders")}',
              '${_d(r,"total_kg").toStringAsFixed(0)}',Fmt.amount(_d(r,'billed')),
              Fmt.amount(_d(r,'collected')),Fmt.amount(_d(r,'outstanding'))]).toList(), hi:[6]),
      ],
      _sec('ORDER HISTORY'),
      _tbl(['Date','Shop','kg','Birds','Rate','Billed','Collected'],
          day.map((d)=>[_fd(d['order_date']),_sh(_str(d,'shop_name'),10),
            '${_d(d,"kg").toStringAsFixed(0)}','${_i(d,"birds")}',
            '${_d(d,"rate").toStringAsFixed(2)}',Fmt.amount(_d(d,'billed')),Fmt.amount(_d(d,'collected'))]).toList(),
          hi:[5]),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 11. PROFITABILITY
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _rProfitability() {
    final s = _s(); final day = _rows('daily');
    final rev = _d(s,'revenue'); final pur = _d(s,'purchase_cost');
    final exp = _d(s,'expenses'); final shL = _d(s,'shrinkage_loss'); final morL = _d(s,'mortality_loss');
    final net = rev-pur-exp-shL-morL;
    final margin = rev>0 ? net/rev*100 : 0.0;
    return _scroll([
      Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard), border: Border.all(color: kBorderLight), boxShadow: kCardShadow),
          child: Column(children: [
            _hdr('Profit & Loss', Icons.trending_up_outlined, kSuccess),
            _plR('Revenue',            rev,  Colors.green,           '+'),
            _plR('Purchase Cost',      pur,  Colors.blue,            '-'),
            _plR('Operating Expenses', exp,  Colors.orange,          '-'),
            _plR('Shrinkage Loss',     shL,  const Color(0xFF6A1B9A),'-'),
            _plR('Mortality Loss',     morL, Colors.red,             '-'),
            Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                    color: net>=0?Colors.green.shade50:Colors.red.shade50,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15))),
                child: Row(children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('= Net Profit', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900,
                        color: net>=0?Colors.green:Colors.red)),
                    Text('${margin.toStringAsFixed(1)}% margin',
                        style: TextStyle(fontSize: 13, color: net>=0?Colors.green:Colors.red)),
                  ]),
                  const Spacer(),
                  Text(Fmt.amount(net), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900,
                      color: net>=0?Colors.green:Colors.red)),
                ])),
          ])),
      _sec('DAILY P&L'),
      _tbl(['Date','Revenue','Purchase','Expenses','Gross Profit'],
          day.map((d){
            final r2=_d(d,'revenue');final p2=_d(d,'purchase_cost');final e2=_d(d,'expenses');
            return [_fd(d['dt']),Fmt.amount(r2),Fmt.amount(p2),Fmt.amount(e2),Fmt.amount(r2-p2-e2)];
          }).toList(), hi:[4]),
    ]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REUSABLE TABLE — larger text for 40+ readability
  // ─────────────────────────────────────────────────────────────────────────
  Widget _tbl(List<String> heads, List<List<String>> rows, {
    List<String>? tots, List<int> hi=const[], int? warnC, double warnT=0,
  }) => Container(
      margin: const EdgeInsets.fromLTRB(12,0,12,12),
      decoration: BoxDecoration(color: kSurface,
          borderRadius: BorderRadius.circular(kRadiusCard), border: Border.all(color: kBorderLight), boxShadow: kCardShadow),
      child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
              columnSpacing: 18,
              headingRowHeight: 40,
              dataRowMinHeight: 38, dataRowMaxHeight: 44,
              headingRowColor: WidgetStateProperty.all(kNavy),
              columns: heads.asMap().entries.map((e) => DataColumn(label: Text(e.value,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                      color: hi.contains(e.key) ? kGoldLight : const Color(0xFFB4C6F4))))).toList(),
              rows: [
                ...rows.asMap().entries.map((re) => DataRow(
                    color: WidgetStateProperty.resolveWith((s)=>re.key.isOdd?Colors.grey.shade50:Colors.white),
                    cells: re.value.asMap().entries.map((ce) {
                      final isHi   = hi.contains(ce.key);
                      final isWarn = warnC!=null && ce.key==warnC &&
                          (double.tryParse(ce.value.replaceAll('%',''))??0)>=warnT;
                      return DataCell(Text(ce.value, style: TextStyle(fontSize: 13,
                          fontWeight: isHi?FontWeight.w800:FontWeight.w500,
                          color: isWarn?Colors.red:isHi?kNavy:kTextMain)));
                    }).toList())),
                if (tots!=null) DataRow(
                    color: WidgetStateProperty.all(kNavy.withValues(alpha: 0.07)),
                    cells: tots.asMap().entries.map((e)=>DataCell(Text(e.value,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900,
                            color: hi.contains(e.key)?kNavy:kTextMain)))).toList()),
              ])));

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _exportPdf() async {
    if (_data == null) { showError(context, 'Load a report first'); return; }
    final user = ref.read(appUserProvider).valueOrNull;
    final company = user?.companyName ?? 'DSR Chicken';
    try {
      await ReportPdfGenerator.generateAndShow(
        context:     context,
        reportData:  _data!,
        reportLabel: _sel.label,
        companyName: company,
        fromDate:    _from,
        toDate:      _to,
      );
    } catch (e) {
      if (mounted) showError(context, 'PDF Error: ${e.toString().replaceAll("Exception:","").trim()}');
    }
  }

  void _showFilters() => showModalBottomSheet(
      context: context, useRootNavigator: true, isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        String? ta=_agentId; String? tr=_retailerId;
        return Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom+20,
            top: 20, left: 20, right: 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Filters', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              if (_agents.isNotEmpty) DropdownButtonFormField<String>(
                  value: ta,
                  decoration: const InputDecoration(labelText: 'Agent', isDense: false),
                  items: [const DropdownMenuItem(value: null, child: Text('All Agents')),
                    ..._agents.map((a)=>DropdownMenuItem(value: a['id'] as String,
                        child: Text(a['name'] as String? ?? '—')))],
                  onChanged: (v)=>ss(()=>ta=v)),
              const SizedBox(height: 12),
              if (_retailers.isNotEmpty) DropdownButtonFormField<String>(
                  value: tr,
                  decoration: const InputDecoration(labelText: 'Retailer', isDense: false),
                  items: [const DropdownMenuItem(value: null, child: Text('All Retailers')),
                    ..._retailers.map((r)=>DropdownMenuItem(value: r['id'] as String,
                        child: Text(r['shop_name'] as String? ?? '—')))],
                  onChanged: (v)=>ss(()=>tr=v)),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: OutlinedButton(
                    onPressed: (){setState((){_agentId=null;_retailerId=null;});Navigator.of(ctx,rootNavigator:true).pop();_load();},
                    child: const Text('Clear', style: TextStyle(fontSize: 15)))),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(
                    onPressed: (){setState((){_agentId=ta;_retailerId=tr;});Navigator.of(ctx,rootNavigator:true).pop();_load();},
                    child: const Text('Apply', style: TextStyle(fontSize: 15)))),
              ]),
              const SizedBox(height: 10),
            ]));
      }));

  Future<void> _shareReport() async {
    if (_data == null) { showError(context, 'No report to share'); return; }
    final buf = StringBuffer();
    buf.writeln('DSR Chicken - ${_sel.label}');
    buf.writeln('${DateFormat("d MMM yyyy").format(_from)} - ${DateFormat("d MMM yyyy").format(_to)}');
    buf.writeln('');
    if (_sel.key == 'profitability_breakdown') {
      final rows = List<Map<String,dynamic>>.from(_data?['rows'] as List? ?? []);
      buf.writeln('BY ${(_data?['dimension'] as String? ?? _profitDimension).toUpperCase()}');
      for (final r in rows) {
        final cost = r['total_cost'] as num?;
        buf.writeln('${_str(r,"group_label")}: ${Fmt.amount(_d(r,"total_revenue"))} revenue, '
            '${cost == null ? "cost pending" : Fmt.amount(cost.toDouble())} cost');
      }
    } else {
      final s = _s();
      s.forEach((k,v)=>buf.writeln('${k.replaceAll("_"," ").toUpperCase()}: $v'));
    }
    buf.writeln('');
    buf.writeln('Rooster Trader v2');
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) showSuccess(context, 'Report copied — paste in WhatsApp to share');
  }

  Future<void> _pickCustomRange() async {
    final r = await showDateRangePicker(context: context,
        firstDate: DateTime(2024), lastDate: DateTime.now(),
        initialDateRange: DateTimeRange(start: _from, end: _to));
    if (r != null && mounted) {
      setState((){_preset=DatePreset.custom; _from=r.start; _to=r.end;});
      _load();
    }
  }

  // ─── Micro-helpers ────────────────────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE 5 — PRICING ANALYTICS REPORTS
  // Data from get_pricing_analytics RPC
  // ═══════════════════════════════════════════════════════════════════════════

  // ── REPORT P1: Product Sales ─────────────────────────────────────────────
  Widget _rProductSales() {
    final summary  = List<Map<String,dynamic>>.from(_data?['summary'] as List? ?? []);
    final daily    = List<Map<String,dynamic>>.from(_data?['daily_trend'] as List? ?? []);
    final totalRev = summary.fold(0.0, (s, r) => s + _d(r, 'total_revenue'));
    final totalKg  = summary.fold(0.0, (s, r) => s + _d(r, 'total_kg'));

    return _scroll([
      _banner('Sales breakdown by product for the selected period.',
          const Color(0xFF1A237E)),
      const SizedBox(height: 4),
      _kpiGrid([
        _kpi('Total Revenue', Fmt.amount(totalRev), const Color(0xFF1A237E), Icons.currency_rupee),
        _kpi('Total Sold',    '${totalKg.toStringAsFixed(0)} kg', const Color(0xFF006064), Icons.scale_outlined),
      ]),
      const SizedBox(height: 12),

      if (summary.isEmpty)
        _banner('No invoiced sales in this period. Approve deliveries to see data.', Colors.orange)
      else ...[
        _sec('BY PRODUCT'),
        ...summary.map((p) {
          final rev    = _d(p, 'total_revenue');
          final kg     = _d(p, 'total_kg');
          final rate   = _d(p, 'avg_rate');
          final invCnt = _i(p, 'invoice_count');
          final pct    = totalRev > 0 ? rev / totalRev * 100 : 0.0;
          return Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: kBorderLight),
              boxShadow: kCardShadow,
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: const Color(0xFF1A237E).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(kRadiusChip)),
                  child: Text(_str(p, 'product_name'),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF1A237E))),
                ),
                const Spacer(),
                Text('${pct.toStringAsFixed(1)}% of total',
                    style: const TextStyle(fontSize: 11, color: kTextSub)),
              ]),
              const SizedBox(height: 8),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct / 100,
                  minHeight: 6,
                  backgroundColor: const Color(0xFF1A237E).withValues(alpha: 0.1),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF1A237E)),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                _st('Revenue', Fmt.amount(rev)),
                _st('Weight', '${kg.toStringAsFixed(0)} kg'),
                _st('Avg Rate', '${Fmt.amount(rate)}/kg'),
                _st('Invoices', '$invCnt'),
              ]),
            ]),
          );
        }),
      ],

      if (daily.isNotEmpty) ...[
        _sec('DAILY TREND (Revenue)'),
        _dailyBar(daily, 'revenue', const Color(0xFF1A237E)),
      ],
    ]);
  }

  // ── REPORT P2: Zone Sales ─────────────────────────────────────────────────
  Widget _rZoneSales() {
    final byZone    = List<Map<String,dynamic>>.from(_data?['by_zone'] as List? ?? []);
    final byZoneProd= List<Map<String,dynamic>>.from(_data?['by_zone_product'] as List? ?? []);
    final totalRev  = byZone.fold(0.0, (s, r) => s + _d(r, 'total_revenue'));

    return _scroll([
      _banner('Revenue breakdown by delivery zone.', const Color(0xFF006064)),
      const SizedBox(height: 4),
      _kpiGrid([
        _kpi('Total Revenue', Fmt.amount(totalRev), const Color(0xFF006064), Icons.currency_rupee),
        _kpi('Zones Active',  '${byZone.length}', const Color(0xFF00695C), Icons.map_outlined),
      ]),
      const SizedBox(height: 12),

      if (byZone.isEmpty)
        _banner('No zone data yet. Assign retailers to zones and approve deliveries.', Colors.orange)
      else ...[
        _sec('REVENUE BY ZONE'),
        ...byZone.map((z) {
          final rev  = _d(z, 'total_revenue');
          final kg   = _d(z, 'total_kg');
          final rate = _d(z, 'avg_rate');
          final pct  = totalRev > 0 ? rev / totalRev * 100 : 0.0;
          return Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: kBorderLight), boxShadow: kCardShadow,
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [kNavy, kNavyMid]),
                    borderRadius: BorderRadius.circular(kRadiusChip),
                  ),
                  child: Center(child: Text(
                    (_str(z, 'zone_code').length >= 3 ? _str(z, 'zone_code').substring(0, 3) : _str(z, 'zone_code')),
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: kGoldLight),
                  )),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(_str(z, 'zone_name'),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: kNavy))),
                Text('${pct.toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF006064))),
              ]),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct / 100, minHeight: 6,
                  backgroundColor: const Color(0xFF006064).withValues(alpha: 0.1),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF006064)),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                _st('Revenue', Fmt.amount(rev)),
                _st('Weight', '${kg.toStringAsFixed(0)} kg'),
                _st('Avg Rate', '${Fmt.amount(rate)}/kg'),
              ]),
            ]),
          );
        }),
        if (byZoneProd.isNotEmpty) ...[
          _sec('ZONE × PRODUCT BREAKDOWN'),
          ...byZoneProd.map((zp) => _sR(
            '${_str(zp, "zone_name")} · ${_str(zp, "product_name")}',
            '${Fmt.amount(_d(zp, "total_revenue"))} (${_d(zp, "total_kg").toStringAsFixed(0)} kg)',
            const Color(0xFF006064),
          )),
        ],
      ],
    ]);
  }

  // ── REPORT P3: Discount Leakage ───────────────────────────────────────────
  Widget _rDiscountLeakage() {
    final s          = (_data?['summary'] as Map<String,dynamic>?) ?? {};
    final byRetailer = List<Map<String,dynamic>>.from(_data?['by_retailer'] as List? ?? []);
    final byProduct  = List<Map<String,dynamic>>.from(_data?['by_product']  as List? ?? []);
    final total      = _d(s, 'total_discount_given');
    final totalKg    = _d(s, 'total_kg_discounted');
    final avgPerKg   = _d(s, 'avg_discount_per_kg');
    final custCount  = _i(s, 'discount_customer_count');

    return _scroll([
      _banner(
          'Shows how much revenue was discounted via Flat Discount or Percentage Discount pricing. '
              'Only available for orders approved with the Phase 3+ engine.',
          const Color(0xFFBF360C)),
      const SizedBox(height: 4),
      _kpiGrid([
        _kpi('Total Discounted', Fmt.amount(total), const Color(0xFFBF360C), Icons.remove_circle_outline),
        _kpi('Avg / kg', '${Fmt.amount(avgPerKg)}/kg', Colors.deepOrange, Icons.straighten_outlined),
      ]),
      _kpiGrid([
        _kpi2('Kg Discounted', '${totalKg.toStringAsFixed(0)} kg', Colors.orange, Icons.scale_outlined),
        _kpi2('Customers',     '$custCount', Colors.brown, Icons.person_outline),
      ]),
      const SizedBox(height: 12),

      if (total == 0)
        _banner('No discount pricing detected in this period. Either no flat/pct discounts are active, '
            'or no deliveries were approved in this range.', Colors.green)
      else ...[
        if (byRetailer.isNotEmpty) ...[
          _sec('BY CUSTOMER'),
          ...byRetailer.map((r) => Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: kBorderLight),
            ),
            child: Row(children: [
              Container(width: 4, height: 28,
                  color: const Color(0xFFBF360C).withValues(alpha: 0.6),
                  margin: const EdgeInsets.only(right: 10)),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_str(r, 'shop_name'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kNavy)),
                Text('${_d(r, "total_kg").toStringAsFixed(0)} kg · ${Fmt.amount(_d(r, "avg_per_kg"))}/kg avg',
                    style: const TextStyle(fontSize: 11, color: kTextSub)),
              ])),
              Text('−${Fmt.amount(_d(r, "discount_given"))}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFFBF360C))),
            ]),
          )),
        ],
        if (byProduct.isNotEmpty) ...[
          _sec('BY PRODUCT'),
          ...byProduct.map((p) => _sR(
            _str(p, 'product_name'),
            '−${Fmt.amount(_d(p, "discount_given"))} (${_d(p, "total_kg").toStringAsFixed(0)} kg)',
            const Color(0xFFBF360C),
          )),
        ],
      ],
    ]);
  }

  // ── REPORT P4: Rate Source Breakdown ─────────────────────────────────────
  Widget _rRateSource() {
    final bySource  = List<Map<String,dynamic>>.from(_data?['by_source'] as List? ?? []);
    final totalRev  = (_data?['total_revenue'] as num?)?.toDouble() ?? 0;

    const sourceColors = <String, Color>{
      'Customer Adjustment': Color(0xFF059669),
      'Contract':            Color(0xFF7C3AED),
      'Fixed Customer':      Color(0xFF2563EB),
      'Zone Rate':           kNavy,
      'Default Rate':        Color(0xFF374151),
    };

    return _scroll([
      _banner(
          'Shows what percentage of your revenue came from each pricing tier: '
              'Customer Adjustment, Zone Rate, or Default Rate.',
          const Color(0xFF4527A0)),
      const SizedBox(height: 4),
      _kpiGrid([
        _kpi('Total Revenue', Fmt.amount(totalRev), const Color(0xFF4527A0), Icons.currency_rupee),
        _kpi('Rate Sources',  '${bySource.length}', Colors.deepPurple, Icons.auto_fix_high_outlined),
      ]),
      const SizedBox(height: 12),

      if (bySource.isEmpty)
        _banner('No invoiced data in this period.', Colors.orange)
      else ...[
        _sec('REVENUE BY RATE SOURCE'),
        ...bySource.map((src) {
          final label  = _str(src, 'source_label');
          final rev    = _d(src, 'total_revenue');
          final kg     = _d(src, 'total_kg');
          final pct    = _d(src, 'pct_of_total');
          final color  = sourceColors[label] ?? const Color(0xFF374151);

          return Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(kRadiusChip)),
                  child: Text(label, style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800, color: color)),
                ),
                const Spacer(),
                Text('${pct.toStringAsFixed(1)}%',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color)),
              ]),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (pct / 100).clamp(0.0, 1.0), minHeight: 8,
                  backgroundColor: color.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                _st('Revenue', Fmt.amount(rev)),
                _st('Weight', '${kg.toStringAsFixed(0)} kg'),
                _st('Avg Rate', totalRev > 0 && kg > 0
                    ? '${Fmt.amount(rev / kg)}/kg' : '—'),
              ]),
            ]),
          );
        }),
      ],
    ]);
  }

  // ── REPORT P5: Enhanced Profitability ─────────────────────────────────────
  Widget _rProfitabilityEnhanced() {
    final s        = (_data?['summary'] as Map<String,dynamic>?) ?? {};
    final byProd   = List<Map<String,dynamic>>.from(_data?['by_product']  as List? ?? []);
    final daily    = List<Map<String,dynamic>>.from(_data?['daily_trend'] as List? ?? []);

    final revenue     = _d(s, 'revenue');
    final cost        = _d(s, 'purchase_cost');
    final expenses    = _d(s, 'expenses');
    final grossMargin = _d(s, 'gross_margin');
    final marginPct   = _d(s, 'gross_margin_pct');
    final netProfit   = _d(s, 'net_profit');
    final avgSell     = _d(s, 'avg_sell_rate');
    final avgBuy      = _d(s, 'avg_buy_rate');
    final discGiven   = _d(s, 'discount_given');
    final premEarned  = _d(s, 'premium_earned');
    final netPricingImpact = _d(s, 'net_pricing_impact');

    return _scroll([
      _banner('Full profitability including purchase cost, expenses, discount leakage & premium earned.',
          const Color(0xFF1B5E20)),
      const SizedBox(height: 4),

      // Revenue vs Cost KPIs
      _kpiGrid([
        _kpi('Revenue',      Fmt.amount(revenue),     const Color(0xFF1B5E20), Icons.trending_up_outlined),
        _kpi('Purchase Cost',Fmt.amount(cost),         const Color(0xFFBF360C), Icons.shopping_cart_outlined),
      ]),
      _kpiGrid([
        _kpi('Gross Margin', Fmt.amount(grossMargin),
            grossMargin >= 0 ? const Color(0xFF1B5E20) : kError, Icons.calculate_outlined),
        _kpi('Margin %',     '${marginPct.toStringAsFixed(1)}%',
            marginPct >= 10 ? kSuccess : marginPct >= 5 ? Colors.orange : kError,
            Icons.percent_outlined),
      ]),
      _kpiGrid([
        _kpi2('Expenses',   Fmt.amount(expenses),   Colors.orange,    Icons.receipt_long_outlined),
        _kpi2('Net Profit', Fmt.amount(netProfit),
            netProfit >= 0 ? kSuccess : kError, Icons.account_balance_wallet_outlined),
        _kpi2('Avg Sell', '${Fmt.amount(avgSell)}/kg', kNavy,           Icons.sell_outlined),
        _kpi2('Avg Buy',  '${Fmt.amount(avgBuy)}/kg',  Colors.brown,    Icons.shopping_bag_outlined),
      ]),

      // Pricing impact section
      if (discGiven > 0 || premEarned > 0) ...[
        _sec('PRICING ADJUSTMENTS IMPACT'),
        Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(kRadiusCard),
            border: Border.all(color: kBorderLight),
          ),
          child: Column(children: [
            if (discGiven > 0) _plR('Discount Given',    discGiven,       kError,   '−'),
            if (premEarned > 0)_plR('Premium Earned',    premEarned,      kSuccess, '+'),
            Container(height: 1, color: kBorderLight, margin: const EdgeInsets.symmetric(vertical: 6)),
            _plR('Net Pricing Impact', netPricingImpact.abs(),
                netPricingImpact >= 0 ? kSuccess : kError,
                netPricingImpact >= 0 ? '+' : '−'),
          ]),
        ),
      ],

      // Profitability note if no purchase data
      if (cost == 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: _banner('Purchase cost is ₹0 — add purchase entries to see full margin analysis.',
              Colors.orange),
        ),

      // By product
      if (byProd.isNotEmpty) ...[
        _sec('BY PRODUCT'),
        ...byProd.map((p) => Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
              color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: kBorderLight)),
          child: Row(children: [
            Container(width: 4, height: 28, color: const Color(0xFF1B5E20).withValues(alpha: 0.6),
                margin: const EdgeInsets.only(right: 10)),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_str(p, 'product_name'),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kNavy)),
              Text('${_d(p, "total_kg").toStringAsFixed(0)} kg · ${Fmt.amount(_d(p, "avg_rate"))}/kg',
                  style: const TextStyle(fontSize: 11, color: kTextSub)),
            ])),
            Text(Fmt.amount(_d(p, 'total_revenue')),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF1B5E20))),
          ]),
        )),
      ],

      // Daily trend
      if (daily.isNotEmpty) ...[
        _sec('DAILY REVENUE TREND'),
        _dailyBar(daily, 'revenue', const Color(0xFF1B5E20)),
      ],
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE 4 UI — PROFITABILITY BREAKDOWN
  // Data from get_profitability_breakdown RPC (Phase 3 backend, single
  // dimension-parameterized function). No accounting calculation lives here —
  // this only renders whatever rows the RPC returns for the selected dimension.
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _rProfitabilityBreakdown() {
    final rows = List<Map<String,dynamic>>.from(_data?['rows'] as List? ?? []);
    final dimension = _data?['dimension'] as String? ?? _profitDimension;
    final totalRevenue = rows.fold(0.0, (s,r) => s + _d(r,'total_revenue'));
    final pendingRows = rows.where((r) => _i(r,'lines_cost_pending') > 0).length;

    if (rows.isEmpty) {
      return _scroll([
        Padding(padding: const EdgeInsets.all(40),
            child: EmptyState(icon: Icons.pie_chart_outline,
                message: 'No invoiced sales for this $dimension in the selected period')),
      ]);
    }

    return _scroll([
      _banner('Revenue and cost matched per $dimension, using the same batch costing as the P&L statement.',
          const Color(0xFF004D40)),
      _kpiGrid([
        _kpi('Total Revenue', Fmt.amount(totalRevenue), const Color(0xFF004D40), Icons.currency_rupee),
        _kpi('${dimension[0].toUpperCase()}${dimension.substring(1)}s', '${rows.length}',
            const Color(0xFF00695C), Icons.list_alt_outlined),
      ]),
      if (pendingRows > 0)
        _banner('$pendingRows row${pendingRows == 1 ? '' : 's'} have batches not yet costed — '
            'their Cost/Profit/Margin show as "Pending".', Colors.orange),
      const SizedBox(height: 4),
      _sec('BY ${dimension.toUpperCase()}'),
      ...rows.map((r) {
        final rev = _d(r, 'total_revenue');
        final kg = _d(r, 'total_kg');
        final cost = r['total_cost'] as num?;
        final gp = r['gross_profit'] as num?;
        final margin = r['margin_pct'] as num?;
        final pending = _i(r, 'lines_cost_pending') > 0;
        final pct = totalRevenue > 0 ? rev / totalRevenue * 100 : 0.0;
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: kBorderLight), boxShadow: kCardShadow),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(_str(r, 'group_label'),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kNavy),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (pending)
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4)),
                    child: const Text('COST PENDING',
                        style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Colors.orange))),
              const SizedBox(width: 6),
              Text('${pct.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11, color: kTextSub)),
            ]),
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: pct/100, minHeight: 6,
                    backgroundColor: const Color(0xFF004D40).withValues(alpha: 0.1),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF004D40)))),
            const SizedBox(height: 8),
            Row(children: [
              _st('Revenue', Fmt.amount(rev)),
              _st('kg', kg.toStringAsFixed(0)),
              _st('Cost', cost == null ? (pending ? 'Pending' : '₹0') : Fmt.amount(cost.toDouble())),
              _st('Profit', gp == null ? 'Pending' : Fmt.amount(gp.toDouble())),
              _st('Margin', margin == null ? '—' : '${margin.toStringAsFixed(1)}%'),
            ]),
          ]),
        );
      }),
    ]);
  }

  // ── Shared: compact daily bar chart (pure Flutter, no charting lib) ───────
  Widget _dailyBar(List<Map<String,dynamic>> daily, String key, Color color) {
    final vals = daily.map((d) => _d(d, key)).toList();
    final maxV = vals.isEmpty ? 1.0 : vals.reduce((a, b) => a > b ? a : b);
    if (maxV == 0) return const SizedBox.shrink();

    return Container(
      height: 90,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border: Border.all(color: kBorderLight)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: daily.asMap().entries.map((e) {
          final v   = _d(e.value, key);
          final pct = maxV > 0 ? v / maxV : 0.0;
          final dateStr = _fd(e.value['dt'] ?? e.value['d']);
          final isLast  = e.key == daily.length - 1;
          return Expanded(child: Column(children: [
            Expanded(child: Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: double.infinity,
                height: (pct * 55).clamp(2.0, 55.0),
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                    color: isLast ? color : color.withValues(alpha: 0.55),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(2))),
              ),
            )),
            const SizedBox(height: 2),
            if (daily.length <= 10 || e.key % 3 == 0)
              Text(dateStr,
                  style: const TextStyle(fontSize: 7, color: kTextHint),
                  textAlign: TextAlign.center)
            else
              const SizedBox(height: 8),
          ]));
        }).toList(),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  Map<String,dynamic> _s() => (_data?['summary'] as Map<String,dynamic>?)??{};
  List<Map<String,dynamic>> _rows(String k) => List<Map<String,dynamic>>.from(_data?[k] as List? ?? []);
  double _d(Map m, String k) => (m[k] as num?)?.toDouble()??0;
  int    _i(Map m, String k) => (m[k] as num?)?.toInt()??0;
  String _str(Map m, String k) => m[k] as String? ?? '—';
  String _sh(String s, int mx) => s.length>mx?'${s.substring(0,mx)}…':s;
  String _kg(Map m, String k) => '${_d(m,k).toStringAsFixed(0)}';
  String _fd(dynamic s) {
    if (s==null) return '—';
    try { return DateFormat('d MMM').format(DateTime.parse(s.toString())); }
    catch (_) { return s.toString().substring(0, min(10,s.toString().length)); }
  }

  Widget _scroll(List<Widget> c) => SingleChildScrollView(
      child: Column(children:[...c, const SizedBox(height:80)]));

  Widget _sec(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(12,14,12,6),
      child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900,
          color: kNavy, letterSpacing: 0.6)));

  // KPI card — large text for readability
  Widget _kpiGrid(List<Widget> cards) => Padding(
      padding: const EdgeInsets.fromLTRB(12,10,12,0),
      child: Row(children: cards.expand((c)=>[c,const SizedBox(width:8)]).toList()..removeLast()));

  Widget _kpi(String label, String value, Color c, IconData icon) =>
      Expanded(child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: c.withValues(alpha: 0.25)),
              boxShadow: kCardShadow),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 16, color: c),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: c),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 10, color: kTextSub), maxLines: 1),
          ])));

  Widget _kpi2(String label, String value, Color c, IconData icon) =>
      Expanded(child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(kRadiusCard)),
          child: Column(children: [
            Icon(icon, size: 16, color: c),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: c),
                maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
            Text(label, style: const TextStyle(fontSize: 9, color: kTextSub),
                textAlign: TextAlign.center, maxLines: 1),
          ])));

  Widget _st(String label, String value) => Expanded(child: Column(children: [
    Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
    Text(label,  style: const TextStyle(fontSize: 10, color: kTextSub),
        textAlign: TextAlign.center),
  ]));

  Widget _banner(String text, Color c) => Container(
      margin: const EdgeInsets.fromLTRB(12,12,12,0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.withValues(alpha: 0.3))),
      child: Row(children: [
        Icon(Icons.info_outline, size: 14, color: c), const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600))),
      ]));

  Widget _hdr(String title, IconData icon, Color c) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.07),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(kRadiusCard))),
      child: Row(children: [
        Icon(icon, size: 16, color: c), const SizedBox(width: 8),
        Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: c)),
      ]));

  Widget _reconR(String label, String birds, String kg, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kBorder))),
      child: Row(children: [
        Container(width: 4, height: 20, color: c, margin: const EdgeInsets.only(right: 10)),
        Expanded(child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c))),
        if (birds.isNotEmpty) Text(birds, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        if (birds.isNotEmpty && kg.isNotEmpty) const SizedBox(width: 12),
        if (kg.isNotEmpty) Text(kg, style: TextStyle(fontSize: 13, color: c, fontWeight: FontWeight.w700)),
      ]));

  Widget _sR(String label, String value, Color c) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Container(width: 4, height: 18, color: c, margin: const EdgeInsets.only(right: 8)),
        Text(label, style: TextStyle(fontSize: 13, color: c, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      ]));

  Widget _plR(String label, double value, Color c, String sign) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kBorder))),
      child: Row(children: [
        Container(width: 4, height: 20, color: c, margin: const EdgeInsets.only(right: 10)),
        Expanded(child: Text(label, style: TextStyle(fontSize: 14, color: c, fontWeight: FontWeight.w600))),
        Text('$sign ${Fmt.amount(value)}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      ]));
}