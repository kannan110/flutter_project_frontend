import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/dashboard_models.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/responsive_layout.dart';
import '../../../shared/widgets/cards/metric_card.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});
  @override ConsumerState<AnalyticsScreen> createState() => _S();
}

class _S extends ConsumerState<AnalyticsScreen>
    with SingleTickerProviderStateMixin {
  final _c = Supabase.instance.client;
  late TabController _tab;

  // ── State ─────────────────────────────────────────────────────────────────
  Map<String,dynamic>?       _analytics;
  List<StockPosition>        _stock          = [];
  List<Map<String,dynamic>>  _stockSurvival  = [];
  List<Map<String,dynamic>>  _aging          = [];
  List<Map<String,dynamic>>  _profitability  = [];
  List<Map<String,dynamic>>  _agentPerf      = [];

  bool    _loading = true;
  String? _error;

  static const _tabs = ['Revenue', 'Stock', 'Collections', 'Agents'];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _tabs.length, vsync: this);
    _tab.addListener(() { if (!_tab.indexIsChanging) _load(); });
    _load();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  // ── ALL BUSINESS LOGIC ────────────────────────────────────────────────────
  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null || !mounted) return;
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      // Always load core analytics + stock
      final core = await Future.wait([
        _c.rpc('analytics_summary',  params: {'p_trader_id': tid}),
        _c.rpc('get_available_stock', params: {'p_trader_id': tid}),
      ]);

      // Load intelligence data for the active tab (lazy)
      List<Map<String,dynamic>> stockSurvival = _stockSurvival;
      List<Map<String,dynamic>> aging         = _aging;
      List<Map<String,dynamic>> profitability = _profitability;
      List<Map<String,dynamic>> agentPerf     = _agentPerf;

      final tabIdx = _tab.index;
      if (tabIdx == 1 || stockSurvival.isEmpty) {
        try {
          final r = await _c.rpc('get_stock_survival', params: {'p_trader_id': tid});
          stockSurvival = List<Map<String,dynamic>>.from(r as List? ?? []);
        } catch (_) {}
      }
      if (tabIdx == 2 || aging.isEmpty) {
        try {
          final r = await _c.rpc('get_collection_aging', params: {'p_trader_id': tid});
          aging = List<Map<String,dynamic>>.from(r as List? ?? []);
        } catch (_) {}
        try {
          final r = await _c.rpc('get_retailer_profitability', params: {'p_trader_id': tid});
          profitability = List<Map<String,dynamic>>.from(r as List? ?? []);
        } catch (_) {}
      }
      if (tabIdx == 3 || agentPerf.isEmpty) {
        try {
          final r = await _c.rpc('get_agent_performance', params: {'p_trader_id': tid});
          agentPerf = List<Map<String,dynamic>>.from(r as List? ?? []);
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _analytics     = core[0] as Map<String,dynamic>?;
        _stock         = ((core[1] as List?) ?? [])
            .map((s) => StockPosition.fromMap(s as Map<String,dynamic>))
            .toList();
        _stockSurvival = stockSurvival;
        _aging         = aging;
        _profitability = profitability;
        _agentPerf     = agentPerf;
        _loading       = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error   = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  Widget _buildScaffold(BuildContext context) {
    final d        = _analytics ?? {};
    final isDesktop = context.isDesktop;

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: const Text('Analytics'),
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
        bottom: TabBar(
          controller: _tab,
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
          labelColor: kPrimary,
          unselectedLabelColor: kTextHint,
          indicatorColor: kPrimary,
          isScrollable: false,
        ),
      ),
      body: _loading
          ? const LoadingList()
          : _error != null
          ? Center(child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined, size: 48, color: kTextHint),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center,
                style: const TextStyle(color: kTextSub, fontSize: 13)),
            const SizedBox(height: 20),
            ElevatedButton.icon(onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry')),
          ])))
          : TabBarView(
        controller: _tab,
        children: [
          _buildRevenueTab(d),
          _buildStockTab(),
          _buildCollectionsTab(),
          _buildAgentsTab(),
        ],
      ),
    );
  }

  // ── TAB 1: REVENUE ────────────────────────────────────────────────────────
  Widget _buildRevenueTab(Map<String,dynamic> d) {
    final month    = d['this_month'] as Map<String,dynamic>? ?? {};
    final topRetailers = (d['top_retailers'] as List? ?? []).cast<Map<String,dynamic>>();
    final revTrend = (d['revenue_trend'] as List? ?? []).cast<Map<String,dynamic>>();

    final monthRevenue    = (month['revenue']     as num?)?.toDouble() ?? 0;
    final monthOrders     = (month['orders']      as num?)?.toInt()    ?? 0;
    final monthDelivered  = (month['delivered']   as num?)?.toInt()    ?? 0;
    final outstanding     = (month['outstanding'] as num?)?.toDouble() ?? 0;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, kBottomNavClearance), children: [
      // Summary strip
      MetricStrip(metrics: [
        MetricCard(label: 'Month Revenue', value: Fmt.amount(monthRevenue),
            color: kPrimary, icon: Icons.currency_rupee_outlined),
        MetricCard(label: 'Month Orders', value: '$monthOrders',
            icon: Icons.shopping_bag_outlined),
        MetricCard(label: 'Delivered', value: '$monthDelivered',
            color: Colors.green, icon: Icons.check_circle_outline),
        MetricCard(label: 'Outstanding', value: Fmt.amount(outstanding),
            color: outstanding > 0 ? Colors.orange : Colors.green,
            icon: Icons.account_balance_wallet_outlined),
      ]),
      const SizedBox(height: 20),

      // 30-day revenue bar chart — Phase 9: proper axes + grid + labels
      if (revTrend.isNotEmpty) ...[
        const Text('30-DAY REVENUE TREND',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                color: kNavy, letterSpacing: 0.8)),
        const SizedBox(height: 10),
        WhiteCard(child: _RevenueBarChart(data: revTrend)),
        const SizedBox(height: 20),
      ],

      // Top 5 retailers
      if (topRetailers.isNotEmpty) ...[
        const Text('TOP RETAILERS (30 DAYS)',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                color: kNavy, letterSpacing: 0.8)),
        const SizedBox(height: 10),
        WhiteCard(child: Column(children: topRetailers.asMap().entries.map((e) {
          final i   = e.key;
          final r   = e.value;
          final rev = (r['revenue'] as num?)?.toDouble() ?? 0;
          final ord = (r['orders']  as num?)?.toInt()    ?? 0;
          final maxRev = (topRetailers.first['revenue'] as num?)?.toDouble() ?? 1;
          return _RankRow(
            rank: i + 1,
            label: r['shop_name'] as String? ?? '—',
            value: Fmt.amount(rev),
            sub: '$ord orders',
            barPct: maxRev > 0 ? rev / maxRev : 0,
            color: kPrimary,
          );
        }).toList())),
      ],
    ]);
  }

  // ── TAB 2: STOCK ──────────────────────────────────────────────────────────
  Widget _buildStockTab() {
    if (_stockSurvival.isEmpty && _stock.isEmpty) {
      return const EmptyState(icon: Icons.inventory_2_outlined,
          message: 'No stock data', sub: 'Add stock via DC pickup workflow');
    }

    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, kBottomNavClearance), children: [
      // Survival days cards
      if (_stockSurvival.isNotEmpty) ...[
        const Text('STOCK SURVIVAL FORECAST',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                color: kNavy, letterSpacing: 0.8)),
        const SizedBox(height: 10),
        ..._stockSurvival.map((s) {
          final birds      = (s['available_birds']  as num?)?.toInt()    ?? 0;
          final kg         = (s['available_kg']     as num?)?.toDouble() ?? 0;
          final avgBirds   = (s['avg_daily_birds']  as num?)?.toDouble() ?? 0;
          final survDays   = (s['survival_days']    as num?)?.toDouble();
          final lastDcDate = s['last_dc_date']      as String?;
          final prodName   = s['product_name']      as String? ?? '—';

          // Colour by urgency
          final Color urgency = survDays == null
              ? Colors.green
              : survDays <= 1 ? Colors.red
              : survDays <= 3 ? Colors.orange
              : Colors.green;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: urgency.withValues(alpha: 0.3), width: 1.5),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                // Phase 9: ring showing days-remaining vs 7-day target
                SizedBox(width: 52, height: 52,
                    child: CustomPaint(
                      painter: _RingPainter(
                        value: survDays == null ? 1.0
                            : (survDays / 7.0).clamp(0.0, 1.0),
                        color: urgency,
                        trackColor: urgency.withValues(alpha: 0.12),
                      ),
                      child: Center(child: Icon(Icons.inventory_2_outlined,
                          size: 18, color: urgency)),
                    )),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(prodName,
                      style: const TextStyle(fontSize: 15,
                          fontWeight: FontWeight.w800, color: kNavy)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                        color: urgency.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: urgency.withValues(alpha: 0.3))),
                    child: Text(
                        survDays == null
                            ? 'No consumption data'
                            : survDays < 1
                            ? '< 1 day left'
                            : '${survDays.toStringAsFixed(1)} days left',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                            color: urgency)),
                  ),
                ])),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                _statCol('Available', '$birds birds', '${kg.toStringAsFixed(1)} kg', Colors.blue),
                _statCol('Daily avg', '${avgBirds.toStringAsFixed(0)} birds/day',
                    avgBirds > 0 ? '7-day avg' : 'No sales', kPrimary),
                _statCol('Last DC',
                    lastDcDate != null
                        ? DateFormat('d MMM').format(DateTime.parse(lastDcDate))
                        : '—',
                    '', Colors.teal),
              ]),
              if (survDays != null && survDays <= 3) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      color: urgency.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    Icon(Icons.warning_amber_rounded, color: urgency, size: 16),
                    const SizedBox(width: 8),
                    Text(
                        survDays <= 1
                            ? 'Urgent: Stock running out today! Place DC immediately.'
                            : 'Low stock warning: Consider ordering soon.',
                        style: TextStyle(fontSize: 12, color: urgency,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              ],
            ]),
          );
        }),
        const SizedBox(height: 20),
      ],

      // Existing stock positions
      if (_stock.isNotEmpty) ...[
        const Text('CUMULATIVE STOCK POSITIONS',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                color: kNavy, letterSpacing: 0.8)),
        const SizedBox(height: 10),
        ..._stock.map((s) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          child: WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.productName,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: kNavy)),
            const SizedBox(height: 10),
            Row(children: [
              _stat('Total In',  '${s.totalInBirds}',   Colors.blue),
              _stat('Delivered', '${s.totalOutBirds}',  kPrimary),
              _stat('Returns',   '${s.returnedBirds}',  Colors.purple),
              _stat('Remaining', '${s.availableBirds}',
                  s.isNegative ? Colors.red : s.hasLowStock ? Colors.orange : Colors.green),
            ]),
          ])),
        )),
      ],
    ]);
  }

  // ── TAB 3: COLLECTIONS ────────────────────────────────────────────────────
  Widget _buildCollectionsTab() {
    // Bucket totals
    final byBucket = <String, double>{
      'current': 0, 'due_soon': 0, 'overdue': 0, 'critical': 0
    };
    for (final r in _aging) {
      final bucket = r['aging_bucket'] as String? ?? 'current';
      byBucket[bucket] = (byBucket[bucket] ?? 0) +
          ((r['outstanding'] as num?)?.toDouble() ?? 0);
    }
    final totalOutstanding = byBucket.values.fold(0.0, (a, b) => a + b);

    if (_aging.isEmpty && _profitability.isEmpty) {
      return const EmptyState(icon: Icons.account_balance_wallet_outlined,
          message: 'No collection data',
          sub: 'Outstanding balances will appear here');
    }

    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, kBottomNavClearance), children: [

      // Aging bucket summary
      if (_aging.isNotEmpty) ...[
        const Text('COLLECTION AGING',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                color: kNavy, letterSpacing: 0.8)),
        const SizedBox(height: 10),
        MetricStrip(metrics: [
          MetricCard(label: 'Total Outstanding', value: Fmt.amount(totalOutstanding),
              color: totalOutstanding > 0 ? Colors.orange : Colors.green,
              icon: Icons.account_balance_wallet_outlined),
          MetricCard(label: 'Critical (>30d)', value: Fmt.amount(byBucket['critical']!),
              color: byBucket['critical']! > 0 ? Colors.red : Colors.green,
              icon: Icons.warning_rounded),
          MetricCard(label: 'Overdue (16-30d)', value: Fmt.amount(byBucket['overdue']!),
              color: byBucket['overdue']! > 0 ? Colors.deepOrange : Colors.green,
              icon: Icons.schedule_outlined),
          MetricCard(label: 'Due Soon (8-15d)', value: Fmt.amount(byBucket['due_soon']!),
              color: byBucket['due_soon']! > 0 ? Colors.amber.shade700 : Colors.green,
              icon: Icons.access_time_outlined),
        ]),
        const SizedBox(height: 16),

        // Phase 9: Aging donut chart
        if (totalOutstanding > 0) ...[
          WhiteCard(child: _AgingDonutChart(
            buckets: byBucket,
            total: totalOutstanding,
          )),
          const SizedBox(height: 16),
        ],

        // Aging list
        ...[
          ('critical',  Colors.red,              'CRITICAL — Over 30 days'),
          ('overdue',   Colors.deepOrange,        'OVERDUE — 16–30 days'),
          ('due_soon',  Colors.amber.shade700,    'DUE SOON — 8–15 days'),
          ('current',   Colors.green,             'CURRENT — Within 7 days'),
        ].expand((bucket) {
          final bucketName  = bucket.$1;
          final bucketColor = bucket.$2;
          final bucketLabel = bucket.$3;
          final rows = _aging.where((r) =>
          r['aging_bucket'] == bucketName).toList();
          if (rows.isEmpty) return <Widget>[];
          return <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 6),
              child: Row(children: [
                Container(width: 10, height: 10,
                    decoration: BoxDecoration(color: bucketColor, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(bucketLabel,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                        color: bucketColor, letterSpacing: 0.5)),
              ]),
            ),
            ...rows.map((r) {
              final outstanding = (r['outstanding']      as num?)?.toDouble() ?? 0;
              final daysOver    = (r['days_overdue']     as num?)?.toInt()    ?? 0;
              final utilPct     = (r['utilisation_pct']  as num?)?.toDouble() ?? 0;
              final creditLim   = (r['credit_limit']     as num?)?.toDouble() ?? 0;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: WhiteCard(padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Container(width: 4, height: 52,
                          decoration: BoxDecoration(color: bucketColor,
                              borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r['shop_name'] as String? ?? '—',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        Text('$daysOver days since last payment',
                            style: TextStyle(fontSize: 11, color: bucketColor,
                                fontWeight: FontWeight.w600)),
                        if (creditLim > 0) Text(
                            '${utilPct.toStringAsFixed(0)}% of ₹${Fmt.amount(creditLim)} limit used',
                            style: const TextStyle(fontSize: 10, color: kTextHint)),
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(Fmt.amount(outstanding),
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900,
                                color: bucketColor)),
                        if (utilPct >= 90) Container(
                          margin: const EdgeInsets.only(top: 3),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(4)),
                          child: const Text('OVER LIMIT',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
                                  color: Colors.red)),
                        ),
                      ]),
                    ])),
              );
            }),
          ];
        }),
        const SizedBox(height: 20),
      ],

      // Retailer profitability
      if (_profitability.isNotEmpty) ...[
        const Text('RETAILER PROFITABILITY (30 DAYS)',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                color: kNavy, letterSpacing: 0.8)),
        const SizedBox(height: 10),
        WhiteCard(child: Column(children: _profitability.asMap().entries.map((e) {
          final i   = e.key;
          final r   = e.value;
          final rev = (r['revenue_30d']      as num?)?.toDouble() ?? 0;
          final kg  = (r['kg_30d']           as num?)?.toDouble() ?? 0;
          final col = (r['collection_rate']  as num?)?.toDouble() ?? 0;
          final avg = (r['avg_rate_30d']     as num?)?.toDouble() ?? 0;
          final maxRev = (_profitability.first['revenue_30d'] as num?)?.toDouble() ?? 1;
          return _RankRow(
            rank: i + 1,
            label: r['shop_name'] as String? ?? '—',
            value: Fmt.amount(rev),
            sub: '${kg.toStringAsFixed(0)} kg · ₹${avg.toStringAsFixed(0)}/kg · ${col.toStringAsFixed(0)}% collected',
            barPct: maxRev > 0 ? rev / maxRev : 0,
            color: col >= 80 ? Colors.green : col >= 50 ? Colors.orange : Colors.red,
          );
        }).toList())),
      ],
    ]);
  }

  // ── TAB 4: AGENTS ─────────────────────────────────────────────────────────
  Widget _buildAgentsTab() {
    if (_agentPerf.isEmpty) {
      return const EmptyState(icon: Icons.directions_bike_outlined,
          message: 'No agent activity in last 30 days',
          sub: 'Agent delivery performance will appear here');
    }

    final totalKg      = _agentPerf.fold(0.0,
            (s, a) => s + ((a['kg_delivered_30d']   as num?)?.toDouble() ?? 0));
    final totalCash    = _agentPerf.fold(0.0,
            (s, a) => s + ((a['cash_collected_30d'] as num?)?.toDouble() ?? 0));
    final totalDel     = _agentPerf.fold(0,
            (s, a) => s + ((a['deliveries_30d']     as num?)?.toInt()    ?? 0));

    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, kBottomNavClearance), children: [
      // Summary strip
      MetricStrip(metrics: [
        MetricCard(label: 'Total Deliveries', value: '$totalDel',
            icon: Icons.local_shipping_outlined),
        MetricCard(label: 'Total KG', value: '${totalKg.toStringAsFixed(0)} kg',
            color: kPrimary, icon: Icons.scale_outlined),
        MetricCard(label: 'Cash Collected', value: Fmt.amount(totalCash),
            color: Colors.green, icon: Icons.payments_outlined),
        MetricCard(label: 'Agents', value: '${_agentPerf.length}',
            icon: Icons.people_outlined),
      ]),
      const SizedBox(height: 16),

      // Phase 9: Agent comparison chart
      if (_agentPerf.length > 1) ...[
        const Text('KG DELIVERED COMPARISON',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                color: kNavy, letterSpacing: 0.8)),
        const SizedBox(height: 10),
        WhiteCard(child: _AgentBarChart(agents: _agentPerf)),
        const SizedBox(height: 16),
      ],

      // Per-agent cards
      ..._agentPerf.map((a) {
        final name     = a['agent_name']          as String? ?? '—';
        final vehicle  = a['vehicle_no']          as String?;
        final del      = (a['deliveries_30d']     as num?)?.toInt()    ?? 0;
        final kg       = (a['kg_delivered_30d']   as num?)?.toDouble() ?? 0;
        final cash     = (a['cash_collected_30d'] as num?)?.toDouble() ?? 0;
        final loss     = (a['avg_loss_pct']       as num?)?.toDouble() ?? 0;
        final shifts   = (a['shifts_30d']         as num?)?.toInt()    ?? 0;
        final lastDate = a['last_shift_date']     as String?;

        final lossColor = loss >= 3 ? Colors.red
            : loss >= 1.5 ? Colors.orange
            : Colors.green;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(kRadiusCard),
            border: Border.all(color: kBorderLight),
          ),
          child: Column(children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(children: [
                Container(width: 42, height: 42,
                    decoration: BoxDecoration(
                        color: kNavy.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10)),
                    child: Center(child: Text(name[0].toUpperCase(),
                        style: const TextStyle(fontSize: 18,
                            fontWeight: FontWeight.w900, color: kNavy)))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w800, color: kNavy)),
                  if (vehicle != null)
                    Text(vehicle, style: const TextStyle(fontSize: 11, color: kTextHint)),
                ])),
                if (lastDate != null) Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(DateFormat('d MMM').format(DateTime.parse(lastDate)),
                      style: const TextStyle(fontSize: 11, color: kTextHint)),
                  const Text('last shift', style: TextStyle(fontSize: 9, color: kTextHint)),
                ]),
              ]),
            ),
            // Stats row
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              decoration: BoxDecoration(
                  color: kBgPage,
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(kRadiusCard))),
              child: Row(children: [
                _agentStat('Deliveries', '$del',         kPrimary),
                _agentStat('KG',         '${kg.toStringAsFixed(0)} kg', Colors.teal),
                _agentStat('Cash',       Fmt.amount(cash), Colors.green),
                _agentStat('Loss%',
                    '${loss.toStringAsFixed(1)}%',         lossColor),
                _agentStat('Shifts',     '$shifts',       Colors.indigo),
              ]),
            ),
          ]),
        );
      }),
    ]);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  Widget _stat(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c)),
    Text(l, style: const TextStyle(fontSize: 9, color: kTextHint),
        textAlign: TextAlign.center),
  ]));

  Widget _statCol(String l, String v1, String v2, Color c) =>
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Text(v1, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c)),
        if (v2.isNotEmpty)
          Text(v2, style: const TextStyle(fontSize: 10, color: kTextHint)),
        Text(l, style: const TextStyle(fontSize: 9, color: kTextHint)),
      ]));

  Widget _agentStat(String l, String v, Color c) =>
      Expanded(child: Column(children: [
        Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c)),
        Text(l, style: const TextStyle(fontSize: 9, color: kTextHint)),
      ]));

  @override
  Widget build(BuildContext context) => ResponsiveLayout(
    mobile:  (_) => _buildScaffold(context),
    desktop: (_) => _buildScaffold(context),
  );
}

// ── Phase 9: Revenue bar chart with axes, grid, labels ────────────────────
class _RevenueBarChart extends StatelessWidget {
  const _RevenueBarChart({required this.data});
  final List<Map<String,dynamic>> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();

    final values = data.map((d) =>
    (d['value'] as num?)?.toDouble() ?? 0).toList();
    final maxVal = values.reduce((a, b) => a > b ? a : b).clamp(1.0, double.infinity);

    // Pick 5 evenly-spaced date labels from the 30 days
    final labelIndices = [0, 7, 14, 21, 29]
        .where((i) => i < data.length).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Chart area
        SizedBox(
          height: 140,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            // Y-axis labels
            SizedBox(
              width: 44,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_fmtY(maxVal),
                      style: const TextStyle(fontSize: 8, color: kTextHint)),
                  Text(_fmtY(maxVal * 0.75),
                      style: const TextStyle(fontSize: 8, color: kTextHint)),
                  Text(_fmtY(maxVal * 0.5),
                      style: const TextStyle(fontSize: 8, color: kTextHint)),
                  Text(_fmtY(maxVal * 0.25),
                      style: const TextStyle(fontSize: 8, color: kTextHint)),
                  const Text('₹0',
                      style: TextStyle(fontSize: 8, color: kTextHint)),
                ],
              ),
            ),
            const SizedBox(width: 6),
            // Bars + grid
            Expanded(
              child: CustomPaint(
                painter: _BarChartPainter(
                    values: values, maxVal: maxVal,
                    barColor: kNavy, gridColor: kBorderLight),
                child: const SizedBox.expand(),
              ),
            ),
          ]),
        ),
        // X-axis date labels
        Padding(
          padding: const EdgeInsets.only(left: 50, top: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: labelIndices.map((i) {
              final d = DateTime.tryParse(
                  data[i]['date'] as String? ?? '');
              return Text(
                d != null ? DateFormat('d MMM').format(d) : '',
                style: const TextStyle(fontSize: 8, color: kTextHint),
              );
            }).toList(),
          ),
        ),
      ]),
    );
  }

  String _fmtY(double v) {
    if (v >= 100000) return '₹${(v/100000).toStringAsFixed(1)}L';
    if (v >= 1000)   return '₹${(v/1000).toStringAsFixed(0)}K';
    return '₹${v.toStringAsFixed(0)}';
  }
}

// ── Bar chart CustomPainter ────────────────────────────────────────────────
class _BarChartPainter extends CustomPainter {
  const _BarChartPainter({
    required this.values,
    required this.maxVal,
    required this.barColor,
    required this.gridColor,
  });

  final List<double> values;
  final double maxVal;
  final Color barColor, gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    // Horizontal grid lines at 25%, 50%, 75%, 100%
    for (final pct in [0.25, 0.5, 0.75, 1.0]) {
      final y = size.height * (1 - pct * 0.9);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (values.isEmpty) return;

    final barW    = (size.width / values.length) * 0.7;
    final gap     = (size.width / values.length) * 0.3;
    final today   = DateTime.now();

    for (int i = 0; i < values.length; i++) {
      final pct  = values[i] / maxVal;
      final barH = (pct * size.height * 0.9).clamp(2.0, size.height * 0.9);
      final x    = i * (barW + gap) + gap / 2;
      final y    = size.height - barH;

      // Highlight today's bar
      final date = DateTime.tryParse(
          DateTime.now().subtract(Duration(days: values.length - 1 - i))
              .toIso8601String().split('T')[0]);
      final isToday = date != null &&
          date.day == today.day && date.month == today.month;

      final paint = Paint()
        ..color = isToday ? barColor : barColor.withValues(alpha: 0.35)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x, y, barW, barH),
          topLeft: const Radius.circular(2),
          topRight: const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override bool shouldRepaint(_BarChartPainter o) =>
      o.values != values || o.maxVal != maxVal;
}


// ── Phase 9: Aging donut chart ─────────────────────────────────────────────
class _AgingDonutChart extends StatelessWidget {
  const _AgingDonutChart({required this.buckets, required this.total});
  final Map<String,double> buckets;
  final double total;

  @override
  Widget build(BuildContext context) {
    const bucketDefs = [
      ('critical',  Colors.red,            'Critical >30d'),
      ('overdue',   Colors.deepOrange,      'Overdue 16-30d'),
      ('due_soon',  Colors.amber,           'Due 8-15d'),
      ('current',   Colors.green,           'Current 0-7d'),
    ];

    final segments = bucketDefs
        .where((b) => (buckets[b.$1] ?? 0) > 0)
        .map((b) => _DonutSegment(
      value: (buckets[b.$1] ?? 0) / total,
      color: b.$2,
      label: b.$3,
    ))
        .toList();

    if (segments.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        // Donut
        SizedBox(
          width: 120, height: 120,
          child: CustomPaint(
            painter: _DonutPainter(
                segments: segments,
                centerLabel: Fmt.amount(total),
                centerSub: 'outstanding'),
          ),
        ),
        const SizedBox(width: 20),
        // Legend
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: bucketDefs.map((b) {
            final amt = buckets[b.$1] ?? 0;
            if (amt <= 0) return const SizedBox.shrink();
            final pct = total > 0 ? (amt / total * 100).toStringAsFixed(0) : '0';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Container(width: 10, height: 10,
                    decoration: BoxDecoration(color: b.$2, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(b.$3, style: const TextStyle(fontSize: 11,
                      fontWeight: FontWeight.w700)),
                  Text('${Fmt.amount(amt)}  ($pct%)',
                      style: const TextStyle(fontSize: 10, color: kTextHint)),
                ])),
              ]),
            );
          }).toList(),
        )),
      ]),
    );
  }
}

class _DonutSegment {
  const _DonutSegment({required this.value, required this.color,
    required this.label});
  final double value;
  final Color  color;
  final String label;
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.segments, required this.centerLabel,
    required this.centerSub});
  final List<_DonutSegment> segments;
  final String centerLabel, centerSub;

  @override
  void paint(Canvas canvas, Size size) {
    final cx  = size.width / 2;
    final cy  = size.height / 2;
    final r   = (size.width / 2) - 8;
    const sw  = 18.0;
    const gap = 0.03;

    double startAngle = -1.5708; // -π/2 (start at top)
    for (final seg in segments) {
      final sweep = (seg.value * (6.2832 - gap * segments.length))
          .clamp(0.001, 6.2832);
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        startAngle, sweep, false,
        Paint()
          ..color = seg.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = sw
          ..strokeCap = StrokeCap.butt,
      );
      startAngle += sweep + gap;
    }

    // Centre labels
    final tp = TextPainter(textDirection: ui.TextDirection.ltr);
    tp.text = TextSpan(text: centerLabel,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900,
            color: kNavy));
    tp.layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height - 1));

    tp.text = TextSpan(text: centerSub,
        style: const TextStyle(fontSize: 9, color: kTextHint));
    tp.layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy + 2));
  }

  @override bool shouldRepaint(_) => false;
}


// ── Phase 9: Agent comparison horizontal bar chart ─────────────────────────
class _AgentBarChart extends StatelessWidget {
  const _AgentBarChart({required this.agents});
  final List<Map<String,dynamic>> agents;

  @override
  Widget build(BuildContext context) {
    final maxKg = agents
        .map((a) => (a['kg_delivered_30d'] as num?)?.toDouble() ?? 0)
        .reduce((a, b) => a > b ? a : b)
        .clamp(1.0, double.infinity);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: agents.take(6).map((a) {
          final name = a['agent_name'] as String? ?? '—';
          final kg   = (a['kg_delivered_30d'] as num?)?.toDouble() ?? 0;
          final pct  = kg / maxKg;
          final loss = (a['avg_loss_pct']     as num?)?.toDouble() ?? 0;
          final lossColor = loss >= 3 ? Colors.red
              : loss >= 1.5 ? Colors.orange : Colors.green;

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                SizedBox(width: 90,
                    child: Text(name.split(' ').first,
                        style: const TextStyle(fontSize: 11,
                            fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis)),
                Expanded(child: Stack(children: [
                  Container(height: 18,
                      decoration: BoxDecoration(
                          color: kBorderLight,
                          borderRadius: BorderRadius.circular(3))),
                  FractionallySizedBox(
                    widthFactor: pct.clamp(0.0, 1.0),
                    child: Container(height: 18,
                        decoration: BoxDecoration(
                            color: kNavy.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(3))),
                  ),
                  Positioned.fill(child: Center(child: Text(
                      '${kg.toStringAsFixed(0)} kg',
                      style: const TextStyle(fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)))),
                ])),
                const SizedBox(width: 8),
                Text('${loss.toStringAsFixed(1)}%',
                    style: TextStyle(fontSize: 10,
                        fontWeight: FontWeight.w700, color: lossColor)),
              ]),
            ]),
          );
        }).toList(),
      ),
    );
  }
}


// ── Phase 9: Ring progress painter ────────────────────────────────────────
class _RingPainter extends CustomPainter {
  const _RingPainter({required this.value, required this.color,
    required this.trackColor});
  final double value;
  final Color  color, trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = (size.width / 2) - 4;

    // Track
    canvas.drawCircle(Offset(cx, cy), r,
        Paint()
          ..color = trackColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5);

    // Arc
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      -1.5708,
      value.clamp(0.0, 1.0) * 6.2832,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override bool shouldRepaint(_RingPainter o) => o.value != value;
}


// ── Rank row widget ────────────────────────────────────────────────────────
class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.rank,
    required this.label,
    required this.value,
    required this.sub,
    required this.barPct,
    required this.color,
  });
  final int    rank;
  final String label, value, sub;
  final double barPct;
  final Color  color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 22, height: 22,
            decoration: BoxDecoration(
                color: rank <= 3 ? kNavy : kBgPage,
                shape: BoxShape.circle),
            child: Center(child: Text('$rank',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                    color: rank <= 3 ? kGoldLight : kTextHint)))),
        const SizedBox(width: 10),
        Expanded(child: Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis)),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900,
            color: kNavy)),
      ]),
      if (sub.isNotEmpty) Padding(
        padding: const EdgeInsets.only(left: 32, top: 2),
        child: Text(sub, style: const TextStyle(fontSize: 11, color: kTextHint)),
      ),
      Padding(
        padding: const EdgeInsets.only(left: 32, top: 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: barPct.clamp(0.0, 1.0),
            minHeight: 4,
            backgroundColor: kBorderLight,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ),
    ]),
  );
}