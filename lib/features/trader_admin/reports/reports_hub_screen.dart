import 'dart:math' show min;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';
import 'report_pdf_generator.dart';

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
    try {
      final p = <String,dynamic>{
        'p_trader_id': tid, 'p_report': _sel.key,
        'p_from_date': DateFormat('yyyy-MM-dd').format(_from),
        'p_to_date':   DateFormat('yyyy-MM-dd').format(_to),
      };
      if (_agentId != null)    p['p_agent_id']    = _agentId;
      if (_retailerId != null) p['p_retailer_id'] = _retailerId;
      final res = await _c.rpc('get_report_data', params: p)
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
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kBgGrey,
    appBar: AppBar(
      backgroundColor: Colors.white, elevation: 0,
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
      Expanded(child: _loading ? const LoadingList()
          : _error != null ? _buildError()
          : _data == null  ? const EmptyState(icon: Icons.bar_chart_outlined, message: 'Loading...')
          : _buildReport()),
    ]));

  // ─── REPORT GRID (2 rows, wraps properly — no overflow) ──────────────────
  Widget _buildReportGrid() => Container(
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
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
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
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
                  color: _preset==p ? kPrimary : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8)),
              child: Text(p.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: _preset==p ? Colors.white : kTextSub)))))).toList())),
      GestureDetector(
        onTap: _pickCustomRange,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
              color: _preset==DatePreset.custom ? kPrimary : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.date_range_outlined, size: 12,
                color: _preset==DatePreset.custom ? Colors.white : kTextSub),
            const SizedBox(width: 4),
            Text('Custom', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                color: _preset==DatePreset.custom ? Colors.white : kTextSub)),
          ]))),
    ]));

  // ─── ERROR ────────────────────────────────────────────────────────────────
  Widget _buildError() => Center(child: Padding(
    padding: const EdgeInsets.all(24),
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(16)),
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
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(16), border: Border.all(color: kBorder)),
        child: Column(children: [
          _hdr('Stock Reconciliation', Icons.inventory_2_outlined, const Color(0xFF2E7D32)),
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
          decoration: BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.circular(14), border: Border.all(color: kBorder)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(radius: 22, backgroundColor: kPrimary.withValues(alpha: 0.1),
                  child: Text((_str(a,'agent_name'))[0],
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: kPrimary))),
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
                    color: lp>2?Colors.red.shade50:Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8)),
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
      padding: const EdgeInsets.fromLTRB(12,12,12,80),
      itemCount: shifts.length,
      itemBuilder: (_, i) {
        final s = shifts[i];
        final approved = s['shift_approval_status'] == 'approved';
        final lp = _d(s,'loss_percent');
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.circular(14), border: Border.all(color: kBorder)),
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
                    color: approved?Colors.green.shade50:Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8)),
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
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
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
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: kBorder)),
        child: Column(children: [
          _hdr('Profit & Loss', Icons.trending_up_outlined, const Color(0xFF004D40)),
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
    decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 18,
        headingRowHeight: 40,
        dataRowMinHeight: 38, dataRowMaxHeight: 44,
        headingRowColor: WidgetStateProperty.all(kPrimary.withValues(alpha: 0.07)),
        columns: heads.asMap().entries.map((e) => DataColumn(label: Text(e.value,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                color: hi.contains(e.key) ? kPrimary : kTextMain)))).toList(),
        rows: [
          ...rows.asMap().entries.map((re) => DataRow(
            color: WidgetStateProperty.resolveWith((s)=>re.key.isOdd?Colors.grey.shade50:Colors.white),
            cells: re.value.asMap().entries.map((ce) {
              final isHi   = hi.contains(ce.key);
              final isWarn = warnC!=null && ce.key==warnC &&
                  (double.tryParse(ce.value.replaceAll('%',''))??0)>=warnT;
              return DataCell(Text(ce.value, style: TextStyle(fontSize: 13,
                  fontWeight: isHi?FontWeight.w800:FontWeight.w500,
                  color: isWarn?Colors.red:isHi?kPrimary:kTextMain)));
            }).toList())),
          if (tots!=null) DataRow(
            color: WidgetStateProperty.all(kPrimary.withValues(alpha: 0.09)),
            cells: tots.asMap().entries.map((e)=>DataCell(Text(e.value,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900,
                    color: hi.contains(e.key)?kPrimary:kTextMain)))).toList()),
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
    final s = _s(); final buf = StringBuffer();
    buf.writeln('DSR Chicken - ${_sel.label}');
    buf.writeln('${DateFormat("d MMM yyyy").format(_from)} - ${DateFormat("d MMM yyyy").format(_to)}');
    buf.writeln('');
    s.forEach((k,v)=>buf.writeln('${k.replaceAll("_"," ").toUpperCase()}: $v'));
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
      child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
          color: kTextSub, letterSpacing: 0.5)));

  // KPI card — large text for readability
  Widget _kpiGrid(List<Widget> cards) => Padding(
      padding: const EdgeInsets.fromLTRB(12,10,12,0),
      child: Row(children: cards.expand((c)=>[c,const SizedBox(width:8)]).toList()..removeLast()));

  Widget _kpi(String label, String value, Color c, IconData icon) =>
      Expanded(child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.withValues(alpha: 0.25))),
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
              borderRadius: BorderRadius.circular(10)),
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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(15))),
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
