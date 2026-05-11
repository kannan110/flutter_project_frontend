import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// REPORTS & ANALYTICS HUB
// Unified module: Business Summary · Stock · Agent Performance ·
//                 Customer Analytics · Loss · Collection · Batch Reconciliation
// Single RPC call (get_reports_summary) + date range picker.
// ─────────────────────────────────────────────────────────────────────────────
class ReportsHubScreen extends ConsumerStatefulWidget {
  const ReportsHubScreen({super.key});
  @override ConsumerState<ReportsHubScreen> createState() => _S();
}

class _S extends ConsumerState<ReportsHubScreen>
    with SingleTickerProviderStateMixin {
  final _c = Supabase.instance.client;

  late TabController _tab;
  Map<String,dynamic>? _d;
  bool  _loading = true;

  // Date range — default: last 7 days
  DateTime _from = DateTime.now().subtract(const Duration(days: 6));
  DateTime _to   = DateTime.now();

  // Quick range presets
  final _presets = ['Today', '7 Days', '30 Days', 'Custom'];
  int _preset = 1;

  static const _tabs = [
    'Summary', 'Stock', 'Agent', 'Customer', 'Loss', 'Collection', 'Batch'
  ];

  @override void initState() {
    super.initState();
    _tab = TabController(length: _tabs.length, vsync: this);
    _load();
  }
  @override void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null || !mounted) return;
    if (mounted) setState(() => _loading = true);
    try {
      final fromStr = DateFormat('yyyy-MM-dd').format(_from);
      final toStr   = DateFormat('yyyy-MM-dd').format(_to);
      final res = await _c.rpc('get_reports_summary', params: {
        'p_trader_id':  tid,
        'p_from_date':  fromStr,
        'p_to_date':    toStr,
      }).timeout(const Duration(seconds: 15));
      if (mounted) setState(() { _d = res as Map<String,dynamic>?; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _from, end: _to),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
          data: Theme.of(ctx).copyWith(colorScheme: ColorScheme.light(primary: kPrimary)),
          child: child!));
    if (r == null || !mounted) return;
    setState(() { _from = r.start; _to = r.end; _preset = 3; });
    _load();
  }

  void _applyPreset(int idx) {
    setState(() {
      _preset = idx;
      _to   = DateTime.now();
      if (idx == 0) _from = _to;
      else if (idx == 1) _from = _to.subtract(const Duration(days: 6));
      else if (idx == 2) _from = _to.subtract(const Duration(days: 29));
    });
    _load();
  }

  String get _rangeLabel {
    if (_from == _to) return DateFormat('d MMM').format(_from);
    return '${DateFormat('d MMM').format(_from)} – ${DateFormat('d MMM').format(_to)}';
  }

  String _buildShareText() {
    if (_d == null) return '';
    final d = _d!;
    final buf = StringBuffer();
    buf.writeln('📊 *Rooster Trader Report — $_rangeLabel*\n');
    buf.writeln('🐓 *STOCK*');
    buf.writeln('DC Loaded:   ${d['dc_birds']} birds · ${(d['dc_kg'] as num?)?.toStringAsFixed(0)} kg');
    buf.writeln('Delivered:   ${d['birds_sold']} birds · ${(d['kg_delivered'] as num?)?.toStringAsFixed(0)} kg');
    buf.writeln('Mortality:   ${d['mortality_birds']} birds');
    buf.writeln('Returns:     ${d['returns_birds']} birds\n');
    buf.writeln('💰 *COLLECTION*');
    buf.writeln('Total Collected: ₹${(d['total_collected'] as num?)?.toStringAsFixed(0)}');
    buf.writeln('  Cash: ₹${((d['collection_by_mode'] as Map?)?['cash'] as num?)?.toStringAsFixed(0) ?? 0}');
    buf.writeln('  UPI:  ₹${((d['collection_by_mode'] as Map?)?['upi'] as num?)?.toStringAsFixed(0) ?? 0}');
    buf.writeln('Outstanding: ₹${(d['outstanding'] as num?)?.toStringAsFixed(0)}\n');
    final loss = d['approved_loss'] as Map?;
    if (loss != null && (loss['batch_count'] as num? ?? 0) > 0) {
      buf.writeln('⚖️ *LOSS (Approved Shifts)*');
      buf.writeln('Loss: ${(loss['loss_pct'] as num?)?.toStringAsFixed(2)}%');
      buf.writeln('Loss KG: ${(loss['total_loss_kg'] as num?)?.toStringAsFixed(2)} kg\n');
    }
    buf.writeln('_Rooster Trader v2_');
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kBgGrey,
    appBar: AppBar(
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Reports & Analytics',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        Text(_rangeLabel,
            style: const TextStyle(fontSize: 11, color: kTextHint)),
      ]),
      actions: [
        if (_d != null) IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _buildShareText()));
              if (mounted) showSuccess(context, 'Report copied — paste in WhatsApp ✓');
            }),
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ],
      bottom: PreferredSize(
          preferredSize: const Size.fromHeight(88),
          child: Column(children: [
            // ── Preset chips ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Row(children: [
                ..._presets.asMap().entries.map((e) {
                  final sel = _preset == e.key;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => e.key == 3 ? _pickRange() : _applyPreset(e.key),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                            color: sel ? kPrimary : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: sel ? kPrimary : kBorder)),
                        child: Text(e.value,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                color: sel ? Colors.white : kTextSub)))));
                }),
                const Spacer(),
                if (_preset == 3) GestureDetector(
                  onTap: _pickRange,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.calendar_today_outlined, size: 12, color: Colors.orange),
                      const SizedBox(width: 4),
                      Text(_rangeLabel, style: const TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.w600)),
                    ]))),
              ])),
            // ── Tab bar ──────────────────────────────────────────────────
            TabBar(
              controller: _tab,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
              unselectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
              tabs: _tabs.map((t) => Tab(text: t)).toList()),
          ])),
    ),
    body: _loading
        ? const LoadingList()
        : _d == null
            ? const EmptyState(icon: Icons.analytics_outlined, message: 'No data for selected range')
            : TabBarView(
                controller: _tab,
                children: [
                  _TabSummary(_d!),
                  _TabStock(_d!),
                  _TabAgent(_d!, _rangeLabel),
                  _TabCustomer(_d!),
                  _TabLoss(_d!),
                  _TabCollection(_d!),
                  _TabBatch(_d!),
                ]));
}

// ═════════════════════════════════════════════════════════════════════════════
// TAB 1: BUSINESS SUMMARY
// ═════════════════════════════════════════════════════════════════════════════
class _TabSummary extends StatelessWidget {
  const _TabSummary(this.d);
  final Map<String,dynamic> d;

  @override
  Widget build(BuildContext context) {
    final trend = (d['daily_trend'] as List?)?.cast<Map<String,dynamic>>() ?? [];
    final maxDel = trend.isEmpty ? 1.0 :
        trend.map((t) => (t['del_birds'] as num?)?.toDouble() ?? 0).reduce((a,b)=>a>b?a:b).clamp(1.0, double.infinity);

    return ListView(padding: const EdgeInsets.all(14), children: [

      // ── Hero KPIs ──────────────────────────────────────────────────────
      _kpiGrid([
        _KpiData('Birds Sold',     '${d['birds_sold'] ?? 0}',      kPrimary,           Icons.egg_alt_outlined),
        _KpiData('KG Delivered',   '${(d['kg_delivered'] as num?)?.toStringAsFixed(0) ?? 0} kg', Colors.teal, Icons.scale_outlined),
        _KpiData('DC Loaded',      '${d['dc_birds'] ?? 0} birds',  Colors.blue,        Icons.add_shopping_cart),
        _KpiData('Orders',         '${d['orders_count'] ?? 0}',    Colors.purple,      Icons.shopping_bag_outlined),
        _KpiData('Collected',      '₹${(d['total_collected'] as num?)?.toStringAsFixed(0) ?? 0}', Colors.green, Icons.payments_outlined),
        _KpiData('Outstanding',    '₹${(d['outstanding'] as num?)?.toStringAsFixed(0) ?? 0}',    Colors.orange, Icons.account_balance_wallet_outlined),
      ]),
      const SizedBox(height: 12),

      // ── 7-day delivery trend sparkline ───────────────────────────────
      if (trend.isNotEmpty) _Card(
        title: 'Daily Delivery Trend',
        subtitle: '${trend.length} days',
        child: SizedBox(
          height: 80,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: trend.map((t) {
              final del = (t['del_birds'] as num?)?.toDouble() ?? 0;
              final frac = del / maxDel;
              final dateStr = t['d'] as String? ?? '';
              final dt = DateTime.tryParse(dateStr);
              final isToday = dt != null && DateFormat('yyyy-MM-dd').format(dt) ==
                  DateFormat('yyyy-MM-dd').format(DateTime.now());
              return Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (del > 0) Text('${del.toInt()}',
                      style: TextStyle(fontSize: 7, color: isToday ? kPrimary : kTextHint)),
                  const SizedBox(height: 2),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Container(
                      height: (60 * frac).clamp(4.0, 60.0),
                      color: isToday ? kPrimary : kPrimary.withValues(alpha: 0.4))),
                  const SizedBox(height: 3),
                  Text(dt != null ? DateFormat('d').format(dt) : '',
                      style: TextStyle(fontSize: 7, color: isToday ? kPrimary : kTextHint,
                          fontWeight: isToday ? FontWeight.w800 : FontWeight.normal)),
                ])));
            }).toList())),
      ),
      const SizedBox(height: 12),

      // ── Stock movement summary ─────────────────────────────────────────
      _Card(title: 'Stock Movement', child: Column(children: [
        _row2('DC Loaded',      '${d['dc_birds']} birds · ${(d['dc_kg'] as num?)?.toStringAsFixed(0)} kg', Colors.blue),
        _row2('Delivered',      '${d['birds_sold']} birds · ${(d['kg_delivered'] as num?)?.toStringAsFixed(0)} kg', kPrimary),
        _row2('Mortality',      '${d['mortality_birds']} birds · ${(d['mortality_kg'] as num?)?.toStringAsFixed(1)} kg', Colors.red),
        _row2('Returns',        '${d['returns_birds']} birds', Colors.purple),
        _row2('Transfers Out',  '${d['transfer_out_birds']} birds', Colors.indigo),
      ])),
      const SizedBox(height: 12),

      // ── Financial summary ──────────────────────────────────────────────
      _Card(title: 'Financial Overview', child: Column(children: [
        _row2('Total Revenue',       '₹${(d['total_revenue'] as num?)?.toStringAsFixed(0) ?? 0}', kPrimary),
        _row2('Total Collected',     '₹${(d['total_collected'] as num?)?.toStringAsFixed(0) ?? 0}', Colors.green),
        _row2('Pending Collection',  '₹${(d['pending_collection'] as num?)?.toStringAsFixed(0) ?? 0}', Colors.orange),
        _row2('Outstanding (All Time)', '₹${(d['outstanding'] as num?)?.toStringAsFixed(0) ?? 0}', Colors.red),
      ])),
      const SizedBox(height: 14),

      // ── Share button ──────────────────────────────────────────────────
      ElevatedButton.icon(
        onPressed: () async {
          final t = _buildShareText(d);
          await Clipboard.setData(ClipboardData(text: t));
          if (context.mounted) showSuccess(context, 'Copied — paste in WhatsApp ✓');
        },
        icon: const Icon(Icons.share_outlined, size: 18),
        label: const Text('Copy Report for WhatsApp'),
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366))),
      const SizedBox(height: 20),
    ]);
  }

  String _buildShareText(Map<String,dynamic> d) {
    final buf = StringBuffer();
    buf.writeln('📊 *Report — ${(d['from_date'] ?? '')} to ${(d['to_date'] ?? '')}*\n');
    buf.writeln('🐓 DC: ${d['dc_birds']} birds · ${(d['dc_kg'] as num?)?.toStringAsFixed(0)} kg');
    buf.writeln('✅ Delivered: ${d['birds_sold']} birds · ${(d['kg_delivered'] as num?)?.toStringAsFixed(0)} kg');
    buf.writeln('💰 Collected: ₹${(d['total_collected'] as num?)?.toStringAsFixed(0)}');
    buf.writeln('_Rooster Trader_');
    return buf.toString();
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// TAB 2: STOCK REPORT
// ═════════════════════════════════════════════════════════════════════════════
class _TabStock extends StatelessWidget {
  const _TabStock(this.d);
  final Map<String,dynamic> d;

  @override
  Widget build(BuildContext context) {
    final positions = (d['stock_positions'] as List?)?.cast<Map<String,dynamic>>() ?? [];

    return ListView(padding: const EdgeInsets.all(14), children: [

      // ── Stock Flow (period) ────────────────────────────────────────────
      _Card(title: 'Stock Flow — Selected Period',
            subtitle: 'From stock ledger (authoritative)',
            child: Column(children: [
        _flowRow(Icons.add_shopping_cart,      Colors.blue,        'DC Loaded',       '+${d['dc_birds']} birds',    '${(d['dc_kg'] as num?)?.toStringAsFixed(1)} kg'),
        _flowRow(Icons.local_shipping_outlined, kPrimary,          'Delivered',        '−${d['birds_sold']} birds',  '${(d['kg_delivered'] as num?)?.toStringAsFixed(1)} kg'),
        _flowRow(Icons.swap_horiz,              Colors.indigo,     'Transferred Out',  '−${d['transfer_out_birds']} birds', '—'),
        _flowRow(Icons.assignment_return_outlined, Colors.purple,  'Customer Returns', '+${d['returns_birds']} birds','—'),
        _flowRow(Icons.sentiment_dissatisfied_outlined, Colors.red,'Mortality',        '−${d['mortality_birds']} birds','${(d['mortality_kg'] as num?)?.toStringAsFixed(1)} kg'),
      ])),
      const SizedBox(height: 12),

      // ── Live positions (all-time cumulative) ─────────────────────────
      const Padding(
        padding: EdgeInsets.only(bottom: 6),
        child: Text('LIVE STOCK POSITIONS',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                color: kTextHint, letterSpacing: 0.8))),
      ...positions.map((p) {
        final avail  = (p['available_birds'] as num?)?.toInt() ?? 0;
        final availKg= (p['available_kg'] as num?)?.toDouble() ?? 0;
        final totalIn= (p['total_in_birds'] as num?)?.toInt() ?? 0;
        final totalOut=(p['total_out_birds'] as num?)?.toInt() ?? 0;
        final mort   = (p['mortality_birds'] as num?)?.toInt() ?? 0;
        final ret    = (p['returned_birds'] as num?)?.toInt() ?? 0;
        final neg    = avail < 0;
        final low    = avail < 50 && totalIn > 0;
        final c      = neg ? Colors.red : low ? Colors.orange : Colors.green;
        return _Card(
          title: p['product_name'] as String? ?? '—',
          titleColor: kTextMain,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Live balance pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Text('LIVE BALANCE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
                    color: c, letterSpacing: 0.8)),
                const Spacer(),
                Text('$avail birds · ${availKg.toStringAsFixed(1)} kg',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: c)),
              ])),
            // Breakdown
            Row(children: [
              _sstat('All-Time In',  '$totalIn',   Colors.blue),
              _sstat('All-Time Out', '$totalOut',  kPrimary),
              _sstat('Returns',      '$ret',        Colors.purple),
              _sstat('Mortality',    '$mort',       mort > 0 ? Colors.red : kTextHint),
            ]),
          ]));
      }),
      const SizedBox(height: 20),
    ]);
  }

  Widget _flowRow(IconData icon, Color c, String label, String birds, String kg) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Container(width: 30, height: 30,
              decoration: BoxDecoration(color: c.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(icon, color: c, size: 14)),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(birds, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c)),
            if (kg != '—') Text(kg, style: const TextStyle(fontSize: 10, color: kTextSub)),
          ]),
        ]));

  Widget _sstat(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c), textAlign: TextAlign.center),
    Text(l, style: const TextStyle(fontSize: 9, color: kTextHint), textAlign: TextAlign.center),
  ]));
}

// ═════════════════════════════════════════════════════════════════════════════
// TAB 3: AGENT PERFORMANCE
// ═════════════════════════════════════════════════════════════════════════════
class _TabAgent extends StatelessWidget {
  const _TabAgent(this.d, this.range);
  final Map<String,dynamic> d;
  final String range;

  @override
  Widget build(BuildContext context) {
    final agents = (d['agent_performance'] as List?)?.cast<Map<String,dynamic>>() ?? [];

    if (agents.isEmpty) {
      return const EmptyState(icon: Icons.delivery_dining_outlined, message: 'No agent data');
    }

    return ListView(padding: const EdgeInsets.all(14), children: [
      Padding(padding: const EdgeInsets.only(bottom: 8),
          child: Text('AGENT PERFORMANCE — $range',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                  color: kTextHint, letterSpacing: 0.8))),
      ...agents.map((a) {
        final dcKg  = (a['dc_kg'] as num?)?.toDouble() ?? 0;
        final delKg = (a['kg_delivered'] as num?)?.toDouble() ?? 0;
        final mort  = (a['mortality_birds'] as num?)?.toInt() ?? 0;
        final dels  = (a['deliveries'] as num?)?.toInt() ?? 0;
        final high  = (a['high_loss_count'] as num?)?.toInt() ?? 0;
        final pend  = (a['pending_now'] as num?)?.toInt() ?? 0;
        final shifts= (a['shifts_completed'] as num?)?.toInt() ?? 0;
        // Loss: dc_kg from ledger (not inflated per-delivery dc_weight_kg)
        final lossPct = dcKg > 0 ? ((dcKg - delKg) / dcKg * 100).clamp(0.0, 100.0) : 0.0;
        final isHighLoss = lossPct >= 2.0;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isHighLoss ? Colors.orange.shade300 : kBorder,
                  width: isHighLoss ? 1.5 : 1),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6)]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Row(children: [
                CircleAvatar(radius: 18,
                    backgroundColor: kPrimary.withValues(alpha: 0.1),
                    child: Text((a['agent_name'] as String? ?? '?')[0].toUpperCase(),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: kPrimary))),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a['agent_name'] as String? ?? '—',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                  if (a['vehicle_no'] != null)
                    Text(a['vehicle_no'] as String, style: const TextStyle(fontSize: 10, color: kTextHint)),
                ])),
                if (isHighLoss) _badge('⚠ HIGH LOSS', Colors.orange),
                if (pend > 0)   _badge('$pend PENDING', Colors.blue),
              ])),
            const Divider(height: 1),
            // Stats grid
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                _stat('Deliveries',  '$dels',                        kPrimary),
                _stat('DC (Ledger)', '${dcKg.toStringAsFixed(0)} kg',Colors.blue),
                _stat('Delivered',   '${delKg.toStringAsFixed(0)} kg',Colors.teal),
                _stat('Mortality',   '$mort birds',                   mort > 0 ? Colors.red : kTextHint),
              ])),
            // Loss bar + shifts
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text('Loss: ${lossPct.toStringAsFixed(1)}%',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                              color: isHighLoss ? Colors.red : Colors.green)),
                      const SizedBox(width: 6),
                      Text('($shifts shifts · ${(a['cash_collected'] as num?)?.toStringAsFixed(0) ?? 0} ₹ collected)',
                          style: const TextStyle(fontSize: 10, color: kTextHint)),
                    ]),
                    const SizedBox(height: 4),
                    ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                            value: (lossPct / 10).clamp(0.0, 1.0),
                            minHeight: 5,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation(isHighLoss ? Colors.red : Colors.green))),
                  ])),
                ]),
                if (high > 0) Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('$high high-loss deliveries — review shift approvals',
                        style: const TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.w600))),
              ])),
          ]));
      }),
      const SizedBox(height: 20),
    ]);
  }

  Widget _badge(String t, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      margin: const EdgeInsets.only(left: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(t, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: c)));

  Widget _stat(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c), textAlign: TextAlign.center),
    Text(l, style: const TextStyle(fontSize: 8, color: kTextHint), textAlign: TextAlign.center),
  ]));
}

// ═════════════════════════════════════════════════════════════════════════════
// TAB 4: CUSTOMER ANALYTICS
// ═════════════════════════════════════════════════════════════════════════════
class _TabCustomer extends StatelessWidget {
  const _TabCustomer(this.d);
  final Map<String,dynamic> d;

  @override
  Widget build(BuildContext context) {
    final customers = (d['customer_analytics'] as List?)?.cast<Map<String,dynamic>>() ?? [];
    if (customers.isEmpty) {
      return const EmptyState(icon: Icons.store_outlined, message: 'No customer orders in range');
    }

    return ListView(padding: const EdgeInsets.all(14), children: [
      Padding(padding: const EdgeInsets.only(bottom: 8),
          child: Text('${customers.length} CUSTOMERS — SORTED BY KG DELIVERED',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                  color: kTextHint, letterSpacing: 0.8))),
      ...customers.map((c) {
        final kg       = (c['kg_delivered']    as num?)?.toDouble() ?? 0;
        final ordered  = (c['total_kg_ordered'] as num?)?.toDouble() ?? 0;
        final avgKg    = (c['avg_kg_per_order'] as num?)?.toDouble() ?? 0;
        final orders   = (c['order_count']     as num?)?.toInt() ?? 0;
        final collected= (c['collected']        as num?)?.toDouble() ?? 0;
        final outstanding=(c['outstanding']     as num?)?.toDouble() ?? 0;
        final risk     = c['risk_level'] as String? ?? 'low';
        final varPct   = ordered > 0 ? ((kg - ordered) / ordered * 100) : 0.0;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: outstanding > 0 ? Colors.orange.shade200 : kBorder)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c['shop_name'] as String? ?? '—',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                if (c['owner_name'] != null)
                  Text(c['owner_name'] as String,
                      style: const TextStyle(fontSize: 10, color: kTextHint)),
              ])),
              if (risk == 'high') _riskBadge('HIGH RISK', Colors.red),
              if (risk == 'medium') _riskBadge('MEDIUM', Colors.orange),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              _cstat('Orders',      '$orders',                    kPrimary),
              _cstat('Delivered',   '${kg.toStringAsFixed(0)} kg', Colors.teal),
              _cstat('Avg/Order',   '${avgKg.toStringAsFixed(0)} kg', Colors.blue),
              _cstat('Collected',   '₹${collected.toStringAsFixed(0)}', Colors.green),
            ]),
            if (outstanding > 0 || varPct.abs() > 5) Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                if (outstanding > 0) _pill('Due: ₹${outstanding.toStringAsFixed(0)}', Colors.orange),
                if (varPct.abs() > 5) ...[
                  const SizedBox(width: 6),
                  _pill('Variance: ${varPct.toStringAsFixed(0)}%',
                      varPct < -10 ? Colors.red : Colors.blue),
                ],
              ])),
          ]));
      }),
      const SizedBox(height: 20),
    ]);
  }

  Widget _riskBadge(String t, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(t, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: c)));

  Widget _cstat(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c), textAlign: TextAlign.center),
    Text(l, style: const TextStyle(fontSize: 8, color: kTextHint), textAlign: TextAlign.center),
  ]));

  Widget _pill(String t, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(t, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c)));
}

// ═════════════════════════════════════════════════════════════════════════════
// TAB 5: LOSS / SHRINKAGE REPORT
// ═════════════════════════════════════════════════════════════════════════════
class _TabLoss extends StatelessWidget {
  const _TabLoss(this.d);
  final Map<String,dynamic> d;

  @override
  Widget build(BuildContext context) {
    final loss   = d['approved_loss'] as Map<String,dynamic>? ?? {};
    final lossKg = (loss['total_loss_kg']     as num?)?.toDouble() ?? 0;
    final dcKg   = (loss['total_dc_kg']       as num?)?.toDouble() ?? 0;
    final pct    = (loss['loss_pct']           as num?)?.toDouble() ?? 0;
    final high   = (loss['high_loss_batches']  as num?)?.toInt() ?? 0;
    final batches= (loss['batch_count']        as num?)?.toInt() ?? 0;
    final mortBirds=(d['mortality_birds'] as num?)?.toInt() ?? 0;
    final mortKg = (d['mortality_kg']    as num?)?.toDouble() ?? 0;
    final pendShifts = 0; // pending shifts count not in this tab — use advisory

    final isHighLoss = pct >= 2;

    return ListView(padding: const EdgeInsets.all(14), children: [

      // ── Key loss metric ────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: batches == 0 ? Colors.grey.shade50
                : isHighLoss ? Colors.red.shade50 : Colors.green.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: batches == 0 ? kBorder
                : isHighLoss ? Colors.red.shade200 : Colors.green.shade200, width: 1.5)),
        child: batches == 0
            ? const Column(children: [
                Icon(Icons.pending_outlined, color: kTextHint, size: 36),
                SizedBox(height: 8),
                Text('No approved shifts in this range',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kTextSub)),
                SizedBox(height: 4),
                Text('Loss is final only after shift approval.\nApprove shifts in the Approvals tab.',
                    style: TextStyle(fontSize: 11, color: kTextHint), textAlign: TextAlign.center),
              ])
            : Column(children: [
                Text('${pct.toStringAsFixed(2)}%',
                    style: TextStyle(fontSize: 42, fontWeight: FontWeight.w900,
                        color: isHighLoss ? Colors.red : Colors.green)),
                Text('Transport Loss (Approved Shifts)',
                    style: TextStyle(fontSize: 12, color: isHighLoss ? Colors.red : Colors.green)),
                const SizedBox(height: 12),
                Row(children: [
                  _ls('DC Weight',   '${dcKg.toStringAsFixed(0)} kg',    Colors.blue),
                  _ls('Loss',        '${lossKg.toStringAsFixed(2)} kg',  isHighLoss ? Colors.red : Colors.orange),
                  _ls('High Batches','$high / $batches',                  high > 0 ? Colors.orange : Colors.green),
                ]),
              ])),
      const SizedBox(height: 12),

      // ── Mortality ──────────────────────────────────────────────────────
      _Card(title: 'Mortality', child: Column(children: [
        _row2('Dead Birds',     '$mortBirds birds', Colors.red),
        _row2('Mortality Weight','${mortKg.toStringAsFixed(2)} kg', Colors.red),
        if (mortBirds > 0) Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
              child: const Row(children: [
                Icon(Icons.info_outline, color: Colors.orange, size: 13),
                SizedBox(width: 6),
                Expanded(child: Text('All mortality entries require photo proof.',
                    style: TextStyle(fontSize: 10, color: Colors.orange))),
              ]))),
      ])),
      const SizedBox(height: 12),

      // ── Loss formula (educational) ─────────────────────────────────────
      _Card(title: 'Loss Formula', subtitle: 'How transport loss is calculated', child: Column(children: [
        const Text(
          'Loss = DC Loaded − Delivered − Returns − Mortality − Transfers Out − Closing Stock (agent)',
          style: TextStyle(fontSize: 11, color: kTextSub, height: 1.5)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
          child: const Row(children: [
            Icon(Icons.info_outline, color: Colors.blue, size: 13),
            SizedBox(width: 6),
            Expanded(child: Text(
              'Loss is only final after shift approval. Per-delivery loss shown during delivery is ADVISORY only.',
              style: TextStyle(fontSize: 10, color: Colors.blue))),
          ])),
      ])),
      const SizedBox(height: 20),
    ]);
  }

  Widget _ls(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c), textAlign: TextAlign.center),
    Text(l, style: const TextStyle(fontSize: 10, color: kTextHint), textAlign: TextAlign.center),
  ]));
}

// ═════════════════════════════════════════════════════════════════════════════
// TAB 6: COLLECTION REPORT
// ═════════════════════════════════════════════════════════════════════════════
class _TabCollection extends StatelessWidget {
  const _TabCollection(this.d);
  final Map<String,dynamic> d;

  @override
  Widget build(BuildContext context) {
    final mode = d['collection_by_mode'] as Map<String,dynamic>? ?? {};
    final cash = (mode['cash']   as num?)?.toDouble() ?? 0;
    final upi  = (mode['upi']    as num?)?.toDouble() ?? 0;
    final bank = (mode['bank']   as num?)?.toDouble() ?? 0;
    final cred = (mode['credit'] as num?)?.toDouble() ?? 0;
    final total= (d['total_collected'] as num?)?.toDouble() ?? 0;

    return ListView(padding: const EdgeInsets.all(14), children: [

      // ── Hero ──────────────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.green.shade200)),
        child: Column(children: [
          Text(Fmt.amount(total),
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.green)),
          const Text('Total Collected', style: TextStyle(fontSize: 12, color: Colors.green)),
          const SizedBox(height: 10),
          Row(children: [
            _cs('Cash', cash,   Icons.money),
            _cs('UPI',  upi,    Icons.qr_code_outlined),
            _cs('Bank', bank,   Icons.account_balance_outlined),
            _cs('Credit',cred,  Icons.credit_card_outlined),
          ]),
        ])),
      const SizedBox(height: 12),

      // ── Collection breakdown by mode ───────────────────────────────────
      _Card(title: 'By Payment Mode', child: Column(children: [
        if (total > 0) ...[
          _collRow('Cash',   cash,  total, Colors.green),
          _collRow('UPI',    upi,   total, Colors.blue),
          _collRow('Bank',   bank,  total, Colors.purple),
          _collRow('Credit', cred,  total, Colors.orange),
        ] else
          const Text('No collections in this range',
              style: TextStyle(fontSize: 12, color: kTextHint)),
      ])),
      const SizedBox(height: 12),

      // ── Outstanding ───────────────────────────────────────────────────
      _Card(title: 'Outstanding & Pending', child: Column(children: [
        _row2('All-Time Outstanding',  '₹${(d['outstanding']       as num?)?.toStringAsFixed(0) ?? 0}', Colors.red),
        _row2('Pending Collection',    '₹${(d['pending_collection'] as num?)?.toStringAsFixed(0) ?? 0}', Colors.orange),
      ])),
      const SizedBox(height: 20),
    ]);
  }

  Widget _cs(String l, double v, IconData ic) => Expanded(child: Column(children: [
    Icon(ic, size: 16, color: Colors.green.shade700),
    const SizedBox(height: 2),
    Text(Fmt.amount(v), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.green)),
    Text(l, style: const TextStyle(fontSize: 9, color: kTextHint)),
  ]));

  Widget _collRow(String label, double amt, double total, Color c) {
    final pct = total > 0 ? (amt / total * 100) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
          Text(Fmt.amount(amt), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c)),
          const SizedBox(width: 6),
          Text('${pct.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 10, color: kTextHint)),
        ]),
        const SizedBox(height: 3),
        ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
                value: (pct / 100).clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation(c))),
      ]));
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// TAB 7: BATCH RECONCILIATION
// ═════════════════════════════════════════════════════════════════════════════
class _TabBatch extends StatelessWidget {
  const _TabBatch(this.d);
  final Map<String,dynamic> d;

  @override
  Widget build(BuildContext context) {
    final loss   = d['approved_loss'] as Map<String,dynamic>? ?? {};
    final batches= (loss['batch_count'] as num?)?.toInt() ?? 0;

    return ListView(padding: const EdgeInsets.all(14), children: [
      _Card(title: 'Batch Reconciliation Summary',
            subtitle: 'Approved shifts only',
            child: batches == 0
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('No approved batch reconciliations in this date range.\n\n'
                        'Approve shifts in Approvals → Shift Detail → Approve.',
                        style: TextStyle(fontSize: 12, color: kTextSub, height: 1.5)))
                : Column(children: [
                    _row2('Approved Batches', '$batches',                                   kPrimary),
                    _row2('Total DC (kg)',     '${(loss['total_dc_kg'] as num?)?.toStringAsFixed(1) ?? 0} kg', Colors.blue),
                    _row2('Total Loss (kg)',   '${(loss['total_loss_kg'] as num?)?.toStringAsFixed(2) ?? 0} kg', Colors.orange),
                    _row2('Loss %',            '${(loss['loss_pct'] as num?)?.toStringAsFixed(2) ?? 0}%',
                        (loss['loss_pct'] as num? ?? 0) >= 2 ? Colors.red : Colors.green),
                    _row2('High-Loss Batches', '${loss['high_loss_batches'] ?? 0}',
                        (loss['high_loss_batches'] as num? ?? 0) > 0 ? Colors.orange : Colors.green),
                  ])),
      const SizedBox(height: 12),

      // ── Drill-down links ──────────────────────────────────────────────
      _Card(title: 'Drill Down', child: Column(children: [
        _drillRow(context, Icons.fact_check_outlined, 'View Shift Approvals', R.approvals),
        _drillRow(context, Icons.schedule_outlined,   'View Shift History',   R.shifts),
        _drillRow(context, Icons.local_shipping_outlined, 'Dispatch & Batches', R.dispatch),
      ])),
      const SizedBox(height: 12),

      // ── Reconciliation guide ──────────────────────────────────────────
      _Card(title: 'Reconciliation Flow', child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
          '1. Agent closes shift\n'
          '2. Trader reviews batch loss summary\n'
          '3. Trader approves shift\n'
          '4. batch_loss_summary is written (final loss)\n'
          '5. Loss report reflects approved data',
          style: TextStyle(fontSize: 11, color: kTextSub, height: 1.8)),
      ])),
      const SizedBox(height: 20),
    ]);
  }

  Widget _drillRow(BuildContext ctx, IconData ic, String label, String route) =>
      InkWell(
        onTap: () => ctx.go(route),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Icon(ic, color: kPrimary, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(label,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kPrimary))),
            const Icon(Icons.chevron_right, color: kTextHint, size: 18),
          ])));
}

// ═════════════════════════════════════════════════════════════════════════════
// SHARED HELPERS
// ═════════════════════════════════════════════════════════════════════════════
class _KpiData {
  final String label, value;
  final Color color;
  final IconData icon;
  const _KpiData(this.label, this.value, this.color, this.icon);
}

Widget _kpiGrid(List<_KpiData> items) => GridView.count(
    crossAxisCount: 3, shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 1.2,
    children: items.map((k) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)]),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(k.icon, color: k.color, size: 18),
          const SizedBox(height: 4),
          Text(k.value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: k.color),
              textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(k.label, style: const TextStyle(fontSize: 9, color: kTextHint),
              textAlign: TextAlign.center, maxLines: 2),
        ]))).toList());

class _Card extends StatelessWidget {
  const _Card({required this.title, this.subtitle, this.titleColor, required this.child});
  final String title;
  final String? subtitle;
  final Color? titleColor;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(children: [
              Expanded(child: Text(title,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                      color: titleColor ?? kTextMain))),
              if (subtitle != null) Text(subtitle!,
                  style: const TextStyle(fontSize: 10, color: kTextHint)),
            ])),
        const Divider(height: 1),
        Padding(padding: const EdgeInsets.all(12), child: child),
      ]));
}

Widget _row2(String l, String v, [Color? c]) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Expanded(child: Text(l, style: const TextStyle(fontSize: 12, color: kTextSub))),
      Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c ?? kTextMain)),
    ]));
