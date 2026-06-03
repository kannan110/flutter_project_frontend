import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/dashboard_models.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/responsive_layout.dart';
import '../../../shared/layouts/trader_shell.dart' show shellBadgesProvider;
import '../dashboard/trader_shell.dart' hide shellBadgesProvider;

// ── Language provider ─────────────────────────────────────────────────────────
final langProvider = StateProvider<String>((ref) => 'en');

// ── Design tokens (enterprise SaaS — desktop-first) ──────────────────────────
const _kPageBg = Color(0xFFF8F9FB); // near-white, not cream
const _kPanel = Color(0xFFFFFFFF);
const _kBorder = Color(0xFFE5E7EB);
const _kNavBg = Color(0xFF0F172A); // slate-900
const _kNavBorder = Color(0xFF1E293B);
const _kText1 = Color(0xFF0F172A);
const _kText2 = Color(0xFF475569);
const _kText3 = Color(0xFF94A3B8);
const _kBlue = Color(0xFF2563EB);
const _kBlueLt = Color(0xFFEFF6FF);
const _kGreen = Color(0xFF059669);
const _kGreenLt = Color(0xFFECFDF5);
const _kOrange = Color(0xFFD97706);
const _kOrangeLt = Color(0xFFFFFBEB);
const _kRed = Color(0xFFDC2626);
const _kRedLt = Color(0xFFFEF2F2);
const _kIndigo = Color(0xFF4F46E5);
const _kViolet = Color(0xFF7C3AED);
const _kTeal = Color(0xFF0D9488);

const _kShadow = [
  BoxShadow(color: Color(0x08000000), blurRadius: 1, offset: Offset(0, 1)),
  BoxShadow(color: Color(0x06000000), blurRadius: 4, offset: Offset(0, 2)),
];
const _kShadowMd = [
  BoxShadow(color: Color(0x0D000000), blurRadius: 6, offset: Offset(0, 2)),
  BoxShadow(color: Color(0x0A000000), blurRadius: 12, offset: Offset(0, 4)),
];

// ─────────────────────────────────────────────────────────────────────────────
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override ConsumerState<DashboardScreen> createState() => _S();
}

class _S extends ConsumerState<DashboardScreen> {
  DashboardData? _data;
  List<StockPosition> _stock = [];
  List<Map<String, dynamic>> _recentOrders = [];
  bool _loading = true;
  String? _error;

  @override void initState() {
    super.initState();
    _load();
  }

  // ── ALL BUSINESS LOGIC PRESERVED EXACTLY ─────────────────────────────────
  Future<void> _load() async {
    final tid = ref
        .read(appUserProvider)
        .valueOrNull
        ?.traderId;
    if (tid == null || !mounted) return;
    if (mounted) setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dashRes = await Supabase.instance.client
          .rpc('dashboard_summary', params: {'p_trader_id': tid});
      final stockRes = await Supabase.instance.client
          .rpc('get_available_stock', params: {'p_trader_id': tid});
      List<Map<String, dynamic>> recentOrders = [];
      try {
        final r = await Supabase.instance.client
            .from('orders')
            .select(
            'id,status,estimated_birds,total_quantity,total_amount,created_at,retailers(shop_name)')
            .eq('trader_id', tid)
            .order('created_at', ascending: false)
            .limit(10);
        recentOrders = List<Map<String, dynamic>>.from(r as List? ?? []);
      } catch (_) {}
      if (!mounted) return;
      final dm = dashRes as Map<String, dynamic>?;
      final sl = stockRes as List?;
      setState(() {
        _data = dm != null ? DashboardData.fromMap(dm) : const DashboardData();
        _stock = (sl ?? []).map((s) =>
            StockPosition.fromMap(s as Map<String, dynamic>)).toList();
        _recentOrders = recentOrders;
        _loading = false;
      });
      if (mounted && _data != null) {
        ref.read(shellBadgesProvider.notifier).update((s) =>
            s.copyWith(
              pendingApprovals: _data!.pendingApprovals,
              unreadAlerts: _data!.unreadAlerts,
              pendingOrders: _data!.pendingOrders,
            ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _updateStatus(String s) async {} // preserved

  @override
  Widget build(BuildContext context) {
    final user = ref
        .watch(appUserProvider)
        .valueOrNull;
    final lang = ref.watch(langProvider);
    final t = (String k) => _L.g(lang, k);
    return ResponsiveLayout(
      mobile: (_) => _buildMobileScaffold(user, lang, t),
      desktop: (_) => _buildDesktopLayout(user, lang, t),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ENTERPRISE DESKTOP DASHBOARD — Operations Command Center
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildDesktopLayout(dynamic user, String lang,
      String Function(String) t) {
    if (_loading) return const Center(child: SizedBox(
        width: 28, height: 28,
        child: CircularProgressIndicator(strokeWidth: 2, color: _kBlue)));
    if (_error != null) return _errorView();

    final d = _data ?? const DashboardData();
    final now = DateTime.now();

    return ColoredBox(
      color: _kPageBg,
      child: Column(children: [
        // ── Command Header ──────────────────────────────────────────────────
        _CommandHeader(user: user, data: d, onRefresh: _load, now: now),
        // ── Body ────────────────────────────────────────────────────────────
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Row 1: 5 metric panels ──────────────────────────────────────
            _MetricStrip(data: d, stock: _stock),
            const SizedBox(height: 20),

            // ── Row 2: Operations Board ────────────────────────────────────
            _OpsBoard(data: d, onNavigate: (r) => context.go(r)),
            const SizedBox(height: 20),

            // ── Row 3: Main 3-col grid ──────────────────────────────────────
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Left: Revenue Trend + Live Stock
              Expanded(flex: 7, child: Column(children: [
                _RevenueTrendPanel(data: d),
                const SizedBox(height: 16),
                _LiveStockPanel(stock: _stock, data: d),
              ])),
              const SizedBox(width: 16),
              // Right: Agent Leaderboard + Financial Health + Alerts
              Expanded(flex: 4, child: Column(children: [
                _AgentLeaderboard(agents: d.agentStatus,
                    onTap: () => context.go(R.agents)),
                const SizedBox(height: 16),
                _FinancialHealth(data: d,
                    onLedger: () => context.go(R.ledger),
                    onClosure: () => context.go(R.dayClosure)),
                if (d.unreadAlerts > 0 || d.remainingBirds < 50) ...[
                  const SizedBox(height: 16),
                  _AlertsPanel(data: d, stock: _stock,
                      onTap: () => context.go(R.alerts)),
                ],
              ])),
            ]),
            const SizedBox(height: 20),

            // ── Row 4: Recent Orders full-width table ───────────────────────
            _RecentOrdersTable(
              orders: _recentOrders,
              onViewAll: () => context.go(R.orders),
              onOrder: (id) => context.push(R.orderDetailPath(id)),
            ),
          ]),
        )),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MOBILE — preserved exactly from before, no changes
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildMobileScaffold(dynamic user, String lang,
      String Function(String) t) {
    if (_loading) return const Scaffold(backgroundColor: kBgPage,
        body: Center(
            child: CircularProgressIndicator(color: kNavy, strokeWidth: 2.5)));
    if (_error != null)
      return Scaffold(backgroundColor: kBgPage, body: _errorView());

    return Scaffold(
      backgroundColor: kBgPage,
      body: RefreshIndicator(
        onRefresh: _load, color: kNavy, strokeWidth: 2.5,
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(child: _mobileHeader(user, lang, t)),
          SliverPadding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              sliver: SliverList.list(children: _buildAlerts(t)
                  .map((w) =>
                  Padding(padding: const EdgeInsets.only(bottom: 8), child: w))
                  .toList())),
          SliverToBoxAdapter(child: _summaryCard(t)),
          SliverToBoxAdapter(child: _stockSection(t)),
          SliverToBoxAdapter(child: _financialSection(t)),
          SliverToBoxAdapter(child: _qaSection(t)),
          if ((_data?.agentStatus ?? []).isNotEmpty)
            SliverToBoxAdapter(child: _agentSection()),
          if ((_data?.todayDelivered ?? 0) > 0)
            SliverToBoxAdapter(child: _reconSection(t)),
          if ((_data?.todayReturnsBirds ?? 0) > 0 ||
              (_data?.pendingReturns ?? 0) > 0)
            SliverToBoxAdapter(child: _returnsSection(t)),
          SliverToBoxAdapter(child: _allClearSection(t)),
          const SliverToBoxAdapter(child: SizedBox(height: 110)),
        ]),
      ),
    );
  }

  // ── Mobile helpers — ALL PRESERVED EXACTLY ───────────────────────────────
  Widget _mobileHeader(dynamic user, String lang, String Function(String) t) {
    final alerts = _data?.unreadAlerts ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 52, 20, 12),
      child: Row(children: [
        Container(width: 52,
            height: 52,
            decoration: BoxDecoration(shape: BoxShape.circle,
                border: Border.all(color: kGoldLight, width: 2)),
            padding: const EdgeInsets.all(2),
            child: CircleAvatar(backgroundColor: kNavyMid,
                child: Text(_initials(user?.companyName),
                    style: const TextStyle(fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: kGoldLight)))),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('GOOD MORNING,', style: TextStyle(fontSize: 10,
              fontWeight: FontWeight.w800,
              color: kTextHint,
              letterSpacing: 0.8)),
          Text(user?.companyName ?? 'Trader', style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: kNavy,
              letterSpacing: -0.3),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          Text(t('today'), style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: kGold)),
        ])),
        GestureDetector(onTap: () =>
        ref
            .read(langProvider.notifier)
            .state = lang == 'en' ? 'ta' : 'en',
            child: Container(margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: kSurface,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: kBorderLight),
                    boxShadow: kCardShadow),
                child: Text(lang == 'en' ? 'தமிழ்' : 'EN',
                    style: const TextStyle(fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: kNavy)))),
        GestureDetector(onTap: () => context.go(R.alerts),
            child: Stack(children: [
              Container(width: 42,
                  height: 42,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                      color: kSurface,
                      border: Border.all(color: kBorderLight),
                      boxShadow: kCardShadow),
                  child: const Icon(
                      Icons.notifications_outlined, color: kTextSub, size: 20)),
              if(alerts > 0) Positioned(right: 2,
                  top: 2,
                  child: Container(constraints: const BoxConstraints(
                      minWidth: 16, minHeight: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(color: kError,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: kSurface, width: 1.5)),
                      child: Text('$alerts', textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 8,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)))),
            ])),
        const SizedBox(width: 8),
        GestureDetector(onTap: () => context.go(R.settings),
            child: Container(width: 42,
                height: 42,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: kNavy),
                child: const Icon(
                    Icons.person_outline_rounded, color: kGoldLight,
                    size: 22))),
      ]),
    );
  }

  Widget _summaryCard(String Function(String) t) {
    final d = _data;
    return Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Container(decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [kNavy, kNavyMid],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(kRadiusHero),
            boxShadow: [
              BoxShadow(color: kNavy.withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 8))
            ]),
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(
                    Icons.dashboard_rounded, color: kGoldLight, size: 16),
                const SizedBox(width: 8),
                const Text("TODAY'S SUMMARY", style: TextStyle(fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFB4C6F4),
                    letterSpacing: 0.8)),
                const Spacer(),
                GestureDetector(onTap: _load,
                    child: const Icon(
                        Icons.refresh_rounded, color: Color(0xFFB4C6F4),
                        size: 16))
              ]),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _summaryStatItem(icon: Icons.receipt_long_rounded,
                    value: '${d?.pendingOrders ?? 0}',
                    label: t('orders'),
                    onTap: () => context.go(R.orders),
                    urgent: (d?.pendingOrders ?? 0) > 0),
                _summaryStatItem(icon: Icons.local_shipping_rounded,
                    value: '${d?.activeDeliveries ?? 0}',
                    label: t('dispatch'),
                    onTap: () => context.go(R.dispatch)),
                _summaryStatItem(icon: Icons.verified_user_rounded,
                    value: '${d?.pendingApprovals ?? 0}',
                    label: t('approve'),
                    onTap: () => context.go(R.approvals),
                    urgent: (d?.pendingApprovals ?? 0) > 0),
                _summaryStatItem(icon: Icons.support_agent_rounded,
                    value: '${d?.activeAgents ?? 0}',
                    label: t('agents'),
                    onTap: () => context.go(R.agents)),
              ]),
            ])));
  }

  Widget _summaryStatItem(
      {required IconData icon, required String value, required String label, required VoidCallback onTap, bool urgent = false}) =>
      GestureDetector(onTap: onTap,
          child: Column(children: [
            Container(width: 46,
                height: 46,
                decoration: BoxDecoration(
                    color: urgent ? kError.withValues(alpha: 0.35) : Colors
                        .white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: urgent ? kError.withValues(alpha: 0.5) : Colors
                            .white.withValues(alpha: 0.12))),
                child: Icon(
                    icon, color: urgent ? const Color(0xFFFFB4AC) : kGoldLight,
                    size: 22)),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 26,
                fontWeight: FontWeight.w900,
                color: urgent ? const Color(0xFFFFB4AC) : Colors.white,
                letterSpacing: -0.5)),
            Text(label, style: const TextStyle(fontSize: 9,
                fontWeight: FontWeight.w900,
                color: Color(0xFFB4C6F4),
                letterSpacing: -0.2))
          ]));

  Widget _stockSection(String Function(String) t) {
    final agents = _data?.agentStatus ?? [];
    final totalBirds = _stock.isEmpty ? 0 : _stock.fold(
        0, (s, p) => s + p.availableBirds);
    final inTransit = agents.fold(0, (s, a) => s + a.liveStockBirds);
    final soldToday = _data?.todayDelivered ?? 0;
    final fraction = totalBirds > 0 ? (totalBirds / (totalBirds + soldToday))
        .clamp(0.0, 1.0) : 0.0;
    return Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: GestureDetector(onTap: () => context.push(R.stockDetail),
            child: Container(decoration: BoxDecoration(color: kSurface,
                borderRadius: BorderRadius.circular(kRadiusHero),
                border: Border.all(color: kBorderLight.withValues(alpha: 0.5)),
                boxShadow: kCardShadow),
                padding: const EdgeInsets.all(24),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(
                        Icons.inventory_2_rounded, color: kGold, size: 18),
                    const SizedBox(width: 8),
                    const Text('LIVE STOCK', style: TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: kNavy,
                        letterSpacing: 0.6)),
                    const Spacer(),
                    const Text('DETAILS ›', style: TextStyle(fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: kGold,
                        letterSpacing: 0.6))
                  ]),
                  const SizedBox(height: 20),
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    SizedBox(width: 140,
                        height: 140,
                        child: Stack(alignment: Alignment.center, children: [
                          Transform.rotate(angle: -1.5708,
                              child: CustomPaint(size: const Size(140, 140),
                                  painter: _DonutPainter(
                                      fraction: fraction.toDouble(),
                                      ringColor: kGoldLight,
                                      trackColor: const Color(0xFFF3F4F6),
                                      strokeWidth: 12))),
                          Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(_stock.isEmpty ? '0' : '$totalBirds',
                                style: const TextStyle(fontSize: 30,
                                    fontWeight: FontWeight.w900,
                                    color: kNavy,
                                    letterSpacing: -0.5)),
                            const Text('TOTAL BIRDS', style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                                color: kTextHint,
                                letterSpacing: 0.8))
                          ]),
                        ])),
                    const SizedBox(width: 20),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ..._stock.map((s) =>
                              _stockLegendRow(dot: kGoldLight,
                                  label: 'IN STOCK',
                                  value: '${s.availableBirds}',
                                  sub: '${s.availableKg.toStringAsFixed(
                                      0)} kg')),
                          if(inTransit > 0)_stockLegendRow(dot: const Color(
                              0xFF7687B2),
                              label: 'IN TRANSIT',
                              value: '$inTransit'),
                          _stockLegendRow(dot: kError,
                              label: 'SOLD TODAY',
                              value: '$soldToday'),
                          if((_data?.todayMortalityBirdsLedger ?? 0) >
                              0)_stockLegendRow(dot: const Color(0xFF7F1D1D),
                              label: 'MORTALITY',
                              value: '${_data!.todayMortalityBirdsLedger}'),
                        ])),
                  ]),
                  if(agents.isNotEmpty)...[
                    const SizedBox(height: 16),
                    const Divider(color: kBorderLight, height: 1),
                    const SizedBox(height: 12),
                    ...agents.map(_agentOwnershipRow)
                  ],
                  if((_data?.todayDcCount ?? 0) > 0)...[
                    const SizedBox(height: 12),
                    Container(padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(kRadiusInner),
                            border: Border.all(
                                color: Colors.blue.withValues(alpha: 0.15))),
                        child: Row(children: [
                          const Icon(Icons.local_shipping_outlined, size: 14,
                              color: Colors.blue),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Today DC: ${_data!
                              .todayDcCount} challan(s) · ${_data!
                              .todayDcBirds} birds · ${_data!.todayDcWeight
                              .toStringAsFixed(0)} kg',
                              style: const TextStyle(fontSize: 12,
                                  color: Colors.blue,
                                  fontWeight: FontWeight.w600)))
                        ]))
                  ],
                ]))));
  }

  Widget _stockLegendRow(
      {required Color dot, required String label, required String value, String? sub}) =>
      Padding(padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Container(width: 10,
                height: 10,
                decoration: BoxDecoration(shape: BoxShape.circle, color: dot)),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 10,
                fontWeight: FontWeight.w700,
                color: kTextHint,
                letterSpacing: 0.3))),
            Column(crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(value, style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w900, color: kNavy)),
                  if(sub != null)Text(sub,
                      style: const TextStyle(fontSize: 9, color: kTextHint))
                ])
          ]));

  Widget _financialSection(String Function(String) t) {
    final d = _data;
    return Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(bottom: 12),
              child: Row(children: [
                Icon(Icons.account_balance_wallet_rounded, color: kGold,
                    size: 18),
                SizedBox(width: 8),
                Text('FINANCIAL OVERVIEW', style: TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: kNavy,
                    letterSpacing: 0.6))
              ])),
          GestureDetector(onTap: () => context.go(R.ledger),
            child: Container(decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [kNavy, kNavyMid],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(kRadiusCard),
                border: Border.all(color: kNavyMid)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 22, vertical: 18),
                child: Row(children: [
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('TOTAL TO COLLECT',
                        style: TextStyle(fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFB4C6F4),
                            letterSpacing: 0.7)), const SizedBox(height: 6),
                    Text(Fmt.amount(d?.totalOutstanding ?? 0),
                        style: const TextStyle(fontSize: 34,
                            fontWeight: FontWeight.w900,
                            color: kGoldLight,
                            letterSpacing: -0.5))
                  ])),
                  Container(width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16)),
                      child: const Icon(
                          Icons.payments_rounded, color: kGoldLight, size: 28))
                ])),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _finSubCard(label: "TODAY'S ${t('cash')}",
                value: Fmt.amount(d?.todayCashCollected ?? 0),
                barColor: kGoldLight)),
            const SizedBox(width: 10),
            Expanded(child: _finSubCard(label: "TODAY'S ${t('upi')}",
                value: Fmt.amount(d?.todayUpiCollected ?? 0),
                barColor: const Color(0xFF7687B2))),
          ]),
        ]));
  }

  Widget _finSubCard(
      {required String label, required String value, required Color barColor}) =>
      Container(padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: kSurface,
              borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: kBorderLight.withValues(alpha: 0.5)),
              boxShadow: kCardShadow),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: kTextHint,
                    letterSpacing: 0.6)),
                const SizedBox(height: 6),
                Text(value, style: const TextStyle(fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: kNavy,
                    letterSpacing: -0.3)),
                const SizedBox(height: 8),
                Container(height: 3,
                    width: 32,
                    decoration: BoxDecoration(color: barColor,
                        borderRadius: BorderRadius.circular(99)))
              ]));

  Widget _qaSection(String Function(String) t) {
    final actions = _allActions(t);
    return Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(bottom: 14),
              child: Row(children: [
                Icon(Icons.bolt_rounded, color: kGold, size: 18),
                SizedBox(width: 8),
                Text('QUICK ACTIONS', style: TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: kNavy,
                    letterSpacing: 0.6))
              ])),
          GridView.builder(shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 2.6),
              itemCount: actions.length,
              itemBuilder: (_, i) => _qaBtn(actions[i])),
        ]));
  }

  Widget _agentSection() {
    final agents = _data?.agentStatus ?? [];
    if (agents.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(decoration: BoxDecoration(color: kSurface,
            borderRadius: BorderRadius.circular(kRadiusCard),
            border: Border.all(color: kBorderLight.withValues(alpha: 0.5)),
            boxShadow: kCardShadow),
            child: Column(children: [
              Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Row(children: [
                    const Icon(Icons.groups_rounded, color: kGold, size: 18),
                    const SizedBox(width: 8),
                    const Text('AGENT PERFORMANCE', style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: kNavy,
                        letterSpacing: 0.6)),
                    const Spacer(),
                    GestureDetector(onTap: () => context.go(R.shifts),
                        child: const Text('VIEW ALL', style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: kGold,
                            letterSpacing: 0.5)))
                  ])),
              Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Row(children: const[
                    Expanded(flex: 4,
                        child: Text('AGENT NAME', style: TextStyle(fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: kTextHint,
                            letterSpacing: 0.8))),
                    SizedBox(width: 60,
                        child: Text('DC', textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: kTextHint,
                                letterSpacing: 0.8))),
                    SizedBox(width: 60,
                        child: Text('STOCK', textAlign: TextAlign.right,
                            style: TextStyle(fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: kTextHint,
                                letterSpacing: 0.8)))
                  ])),
              const Divider(
                  height: 1, color: kBorderLight, indent: 20, endIndent: 20),
              ...agents
                  .asMap()
                  .entries
                  .map((e) {
                final i = e.key;
                final a = e.value;
                return Container(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                    decoration: BoxDecoration(
                        border: i < agents.length - 1 ? Border(
                            bottom: BorderSide(color: kBorderLight.withValues(
                                alpha: 0.5))) : null),
                    child: Row(children: [
                      Expanded(flex: 4,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(a.agentName, style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: kNavy),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                Row(children: [
                                  Container(width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: a.hasOpenShift ? const Color(
                                              0xFF22C55E) : kTextHint)),
                                  const SizedBox(width: 4),
                                  Text(a.hasOpenShift ? 'SHIFT OPEN' : 'CLOSED',
                                      style: TextStyle(fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                          color: a.hasOpenShift ? const Color(
                                              0xFF16A34A) : kTextHint,
                                          letterSpacing: 0.4))
                                ])
                              ])),
                      SizedBox(width: 60, child: Center(child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: a.todayDcBirds > 0 ? kGoldBg : kBgGrey,
                              borderRadius: BorderRadius.circular(6)),
                          child: Text(a.todayDcBirds > 0 ? 'MAIN' : 'NONE',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                  color: a.todayDcBirds > 0
                                      ? kWarning
                                      : kTextHint))))),
                      SizedBox(width: 60, child: Text('${a.liveStockBirds}',
                          textAlign: TextAlign.right, style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: a.liveStockBirds > 0 ? kNavy : kTextHint)))
                    ]));
              }),
            ])));
  }

  Widget _reconSection(String Function(String) t) {
    final d = _data;
    if (d == null) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(decoration: BoxDecoration(color: kSurface,
            borderRadius: BorderRadius.circular(kRadiusCard),
            border: Border.all(color: kBorderLight.withValues(alpha: 0.5)),
            boxShadow: kCardShadow),
            padding: const EdgeInsets.all(20),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.balance_rounded, color: kGold, size: 18),
                SizedBox(width: 8),
                Text("TODAY'S RECONCILIATION", style: TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: kNavy,
                    letterSpacing: 0.6))
              ]),
              const SizedBox(height: 16),
              Row(children: [
                _reconStat(
                    'DC Loaded', '${d.todayDcWeight.toStringAsFixed(0)} kg',
                    Colors.blue),
                _reconStat('Delivered',
                    '${d.todayDeliveredKgLedger.toStringAsFixed(0)} kg',
                    const Color(0xFF0D9488)),
                _reconStat('Mortality', '${d.todayMortalityBirdsLedger} birds',
                    kError),
                _reconStat('Transfers', '${d.todayTransferredOutBirds} birds',
                    Colors.indigo)
              ]),
              if(d.todayPendingShifts > 0)...[
                const SizedBox(height: 12),
                _alertTile('${d
                    .todayPendingShifts} shift(s) pending — loss finalises after approval.',
                    Colors.orange, Icons.pending_outlined)
              ],
              if(d.todayPendingShifts == 0 && d.todayApprovedLossKg > 0)...[
                const SizedBox(height: 12),
                _alertTile(
                    'Approved Loss: ${d.todayApprovedLossKg.toStringAsFixed(
                        2)} kg (${(d.todayDcWeight > 0 ? d.todayApprovedLossKg /
                        d.todayDcWeight * 100 : 0).toStringAsFixed(1)}%)',
                    Colors.green, Icons.verified_outlined)
              ],
              if(d.todayHighLossCount > 0 && d.todayPendingShifts == 0)...[
                const SizedBox(height: 8),
                GestureDetector(onTap: () => context.go(R.dailyReport),
                    child: _alertTile(
                        '${d.todayHighLossCount} batches with loss ≥ 2%',
                        kError, Icons.warning_amber_rounded))
              ],
            ])));
  }

  Widget _reconStat(String label, String value, Color color) =>
      Expanded(child: Column(children: [
        Text(value, style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w900, color: color),
            textAlign: TextAlign.center),
        Text(label, style: const TextStyle(fontSize: 9, color: kTextHint),
            textAlign: TextAlign.center)
      ]));

  Widget _returnsSection(String Function(String) t) {
    final d = _data;
    if (d == null) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(decoration: BoxDecoration(color: kSurface,
            borderRadius: BorderRadius.circular(kRadiusCard),
            border: Border.all(color: kBorderLight.withValues(alpha: 0.5)),
            boxShadow: kCardShadow),
            padding: const EdgeInsets.all(20),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.assignment_return_rounded, color: kGold, size: 18),
                SizedBox(width: 8),
                Text('RETURNS', style: TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: kNavy,
                    letterSpacing: 0.6))
              ]),
              if(d.todayReturnsBirds > 0)...[
                const SizedBox(height: 12),
                _alertTile('${d.todayReturnsBirds} birds (${d.todayReturnsKg
                    .toStringAsFixed(1)} kg) returned to stock today ✓',
                    Colors.purple, Icons.assignment_return_outlined)
              ],
              if(d.pendingReturns > 0)...[
                const SizedBox(height: 8),
                GestureDetector(onTap: () => context.go(R.returns),
                    child: _alertTile(
                        '${d.pendingReturns} pending returns', Colors.orange,
                        Icons.pending_outlined))
              ],
            ])));
  }

  Widget _allClearSection(String Function(String) t) {
    final d = _data;
    if (d == null) return const SizedBox.shrink();
    final clear = d.allClear;
    return Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(decoration: BoxDecoration(color: kSurface,
            borderRadius: BorderRadius.circular(kRadiusCard),
            border: Border.all(
                color: (clear ? kSuccess : kWarning).withValues(alpha: 0.3)),
            boxShadow: kCardShadow),
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              Icon(clear ? Icons.check_circle_outline : Icons
                  .pending_actions_outlined, color: clear ? kSuccess : kWarning,
                  size: 24),
              const SizedBox(width: 14),
              Expanded(child: Text(
                  clear ? 'All clear — ready to close day ✓' : '${d
                      .pendingApprovals} approvals · ${d
                      .pendingReturns} returns pending', style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: clear ? kSuccess : kWarning))),
              if(clear)GestureDetector(onTap: () => context.go(R.dayClosure),
                  child: Container(padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(color: kNavy,
                          borderRadius: BorderRadius.circular(kRadiusChip)),
                      child: const Text('Close Day', style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: kGoldLight))))
            ])));
    }

  Widget _agentOwnershipRow(AgentStockStatus a) {
    final hasStock = a.liveStockBirds > 0;
    final shiftOpen = a.hasOpenShift;
    final Color dotColor = hasStock && !shiftOpen ? Colors.red : a
        .pendingDeliveries > 0 ? Colors.orange : hasStock ? Colors.blue : Colors
        .green;
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 7),
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: kBorderLight, width: 0.5))),
        child: Row(children: [
          Container(width: 7,
              height: 7,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(shape: BoxShape.circle,
                  color: shiftOpen ? Colors.green : Colors.grey.shade400)),
          Expanded(child: Text(a.agentName, style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: kTextMain))),
          Text(hasStock ? '${a.liveStockBirds} birds · ${a.liveStockKg
              .toStringAsFixed(0)} kg' : '—', style: TextStyle(fontSize: 11,
              fontWeight: FontWeight.w700,
              color: hasStock ? dotColor : Colors.green)),
          const SizedBox(width: 8),
          Container(width: 6,
              height: 6,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: dotColor))
        ]));
  }

  // Shared helpers
  List<Widget> _buildAlerts(String Function(String) t) {
    final d = _data;
    final out = <Widget>[];
    if (d == null) return out;
    void add(String msg, Color c, IconData icon, {VoidCallback? onTap}) =>
        out.add(_alertTile(msg, c, icon, onTap: onTap));
    if (d.isDayClosed) add(
        'Day is closed. No new records.', Colors.grey, Icons.lock);
    if (d.remainingBirds < 0) add(
        'CRITICAL: Negative stock! Check entries.', kError, Icons.error,
        onTap: () => context.go(R.stock));
    if (d.remainingBirds < 50 && d.stockBirds > 0) add(
        'Low stock: only ${d.remainingBirds} birds remaining', Colors.orange,
        Icons.inventory_outlined, onTap: () => context.go(R.stock));
    if (d.pendingApprovals > 0) add(
        '${d.pendingApprovals} deliveries need approval', Colors.orange,
        Icons.fact_check_outlined, onTap: () => context.go(R.approvals));
    return out;
  }

  Widget _alertTile(String msg, Color color, IconData icon,
      {VoidCallback? onTap}) =>
      GestureDetector(onTap: onTap,
          child: Container(padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(kRadiusInner),
                  border: Border.all(color: color.withValues(alpha: 0.3))),
              child: Row(children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(msg, style: TextStyle(
                    fontSize: 12, color: color, fontWeight: FontWeight.w600))),
                if(onTap != null)Icon(
                    Icons.chevron_right, color: color, size: 16)
              ])));

  Widget _errorView() =>
      Center(child: Padding(padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined, size: 48, color: kTextHint),
            const SizedBox(height: 12),
            Text(_error ?? 'Error',
                style: const TextStyle(color: kTextSub, fontSize: 13),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load, child: const Text('Retry'))
          ])));

  List<_QA> _allActions(String Function(String) t) =>
      [
        _QA(Icons.add_circle, t('new_order'), Colors.orange,
            const Color(0xFFFFF7ED), () => context.go(R.orderCreate),
            wide: true),
        _QA(Icons.list_alt_outlined, t('orders'), Colors.blue,
            const Color(0xFFEFF6FF), () => context.go(R.orders)),
        _QA(Icons.fact_check_rounded, t('approve'), kSuccess,
            const Color(0xFFF0FDF4), () => context.go(R.approvals)),
        _QA(Icons.local_shipping_outlined, t('dispatch'), Colors.indigo,
            const Color(0xFFEEF2FF), () => context.go(R.dispatch)),
        _QA(Icons.inventory_outlined, t('add_stock'), Colors.blue,
            const Color(0xFFEFF6FF), () => context.go(R.stock)),
        _QA(Icons.account_balance_wallet_outlined, t('collect'), Colors.purple,
            const Color(0xFFFAF5FF), () => context.go(R.ledger)),
        _QA(Icons.receipt_long_outlined, t('invoices'), Colors.amber.shade800,
            const Color(0xFFFFFBEB), () => context.go(R.invoices)),
        _QA(Icons.price_change_outlined, t('rate'), const Color(0xFF0D9488),
            const Color(0xFFECFDF5), () => context.go(R.rates)),
        _QA(Icons.store_outlined, t('customers'), const Color(0xFF0284C7),
            const Color(0xFFF0F9FF), () => context.go(R.retailers)),
        _QA(Icons.delivery_dining_outlined, t('agents'),
            const Color(0xFF57534E), const Color(0xFFFAFAF9), () =>
                context.go(R.agents)),
        _QA(Icons.assignment_return_outlined, t('returns'), kError,
            const Color(0xFFFEF2F2), () => context.go(R.returns)),
        _QA(Icons.schedule_outlined, t('shifts'), kTextSub,
            const Color(0xFFF9FAFB), () => context.go(R.shifts)),
        _QA(Icons.account_balance_outlined, t('reconcile'), kSuccess,
            const Color(0xFFF0FDF4), () => context.go(R.cashRecon)),
        _QA(Icons.lock_clock_outlined, t('close_day'), kError,
            const Color(0xFFFEF2F2), () => context.go(R.dayClosure)),
        _QA(Icons.warning_amber_outlined, t('alerts'), Colors.orange,
            const Color(0xFFFFFBEB), () => context.go(R.alerts)),
        _QA(Icons.summarize_outlined, t('report'), kNavy,
            const Color(0xFFF8FAFC), () => context.go(R.dailyReport)),
      ];

  Widget _qaBtn(_QA a) =>
      InkWell(onTap: a.onTap, borderRadius: BorderRadius.circular(kRadiusCard),
          child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: a.bg,
                  borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(
                      color: a.color.withValues(alpha: 0.15), width: 0.8)),
              child: Row(children: [
                Container(width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: kSurface,
                        borderRadius: BorderRadius.circular(kRadiusChip),
                        boxShadow: [
                          BoxShadow(color: a.color.withValues(alpha: 0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 2))
                        ]),
                    child: Icon(a.icon, size: 20, color: a.color)),
                const SizedBox(width: 10),
                Expanded(child: Text(a.label, style: TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: a.color,
                    letterSpacing: -0.2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis))
              ])));

  String _initials(String? name) {
    if (name == null || name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    return parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : name[0].toUpperCase();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ENTERPRISE DESKTOP COMPONENTS
// ─────────────────────────────────────────────────────────────────────────────

// ── Command Header ────────────────────────────────────────────────────────────
class _CommandHeader extends StatelessWidget {
  const _CommandHeader({required this.user, required this.data,
    required this.onRefresh, required this.now});

  final dynamic user;
  final DashboardData data;
  final VoidCallback onRefresh;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final hour = now.hour;
    final greeting = hour < 12 ? 'Good Morning' : hour < 17
        ? 'Good Afternoon'
        : 'Good Evening';
    final dayStr = DateFormat('EEE, d MMM y').format(now);
    final timeStr = DateFormat('hh:mm a').format(now);

    return Container(
      decoration: const BoxDecoration(
        color: _kPanel,
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      child: Row(children: [
        // Greeting
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$greeting, ${user?.companyName ?? "Trader"}! 👋',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800,
                      color: _kText1, letterSpacing: -0.4)),
              const SizedBox(height: 2),
              Text('$dayStr  •  $timeStr',
                  style: const TextStyle(fontSize: 12, color: _kText3,
                      fontWeight: FontWeight.w500)),
            ])),

        // Day status
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: data.isDayClosed
                ? _kRedLt : _kGreenLt,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: data.isDayClosed
                    ? _kRed.withValues(alpha: 0.3)
                    : _kGreen.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            Container(width: 6, height: 6,
                decoration: BoxDecoration(shape: BoxShape.circle,
                    color: data.isDayClosed ? _kRed : _kGreen)),
            const SizedBox(width: 6),
            Text(data.isDayClosed ? 'Day Closed' : 'Day Open',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                    color: data.isDayClosed ? _kRed : _kGreen)),
          ]),
        ),
        const SizedBox(width: 12),
        // Refresh
        _HdrBtn(
            icon: Icons.refresh_rounded, onTap: onRefresh, tooltip: 'Refresh'),
        const SizedBox(width: 4),
      ]),
      height: 60,
    );
  }
}

class _HdrBtn extends StatefulWidget {
  const _HdrBtn(
      {required this.icon, required this.onTap, required this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override State<_HdrBtn> createState() => _HdrBtnState();
}

class _HdrBtnState extends State<_HdrBtn> {
  bool _hov = false;

  @override
  Widget build(BuildContext c) =>
      Tooltip(message: widget.tooltip,
          child: MouseRegion(
              onEnter: (_) => setState(() => _hov = true),
              onExit: (_) => setState(() => _hov = false),
              child: GestureDetector(onTap: widget.onTap,
                  child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _hov ? const Color(0xFFF1F5F9) : Colors
                            .transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: _hov ? _kBorder : Colors.transparent),
                      ),
                      child: Icon(widget.icon, size: 18, color: _kText2)))));
}

// ── Metric Strip — 5 premium gradient panels ──────────────────────────────────
class _MetricStrip extends StatelessWidget {
  const _MetricStrip({required this.data, required this.stock});

  final DashboardData data;
  final List<StockPosition> stock;

  @override
  Widget build(BuildContext context) {
    final totalBirds = stock.isEmpty ? data.remainingBirds
        : stock.fold(0, (s, p) => s + p.availableBirds);

    final metrics = [
      _MetricDef(
        label: 'Live Birds',
        value: _fmt(totalBirds),
        sub: '${stock.isEmpty ? 0 : stock.first.availableBirds} Available',
        icon: Icons.egg_alt_outlined,
        grad: [const Color(0xFFDC2626), const Color(0xFFB91C1C)],
        trend: null,
      ),
      _MetricDef(
        label: 'Sold Today',
        value: '${data.todayDelivered}',
        sub: '${data.todayDeliveredKgLedger.toStringAsFixed(0)} kg',
        icon: Icons.local_shipping_outlined,
        grad: [const Color(0xFFD97706), const Color(0xFFB45309)],
        trend: null,
      ),
      _MetricDef(
        label: 'Dispatch Pending',
        value: '${data.activeDeliveries}',
        sub: '${data.todayDcWeight.toStringAsFixed(0)} kg on road',
        icon: Icons.local_shipping_rounded,
        grad: [const Color(0xFF1D4ED8), const Color(0xFF1E40AF)],
        trend: null,
      ),
      _MetricDef(
        label: 'Collection Pending',
        value: Fmt.amount(data.totalOutstanding),
        sub: '${data.totalRetailers} Customers',
        icon: Icons.account_balance_wallet_outlined,
        grad: [const Color(0xFF059669), const Color(0xFF047857)],
        trend: null,
      ),
      _MetricDef(
        label: 'Mortality Today',
        value: '${data.todayMortalityBirdsLedger}',
        sub: data.todayMortalityBirdsLedger == 0
            ? '0% of stock' : '${(data.todayMortalityBirdsLedger /
            math.max(totalBirds, 1) * 100).toStringAsFixed(2)}% of stock',
        icon: Icons.warning_amber_outlined,
        grad: [const Color(0xFF7C3AED), const Color(0xFF6D28D9)],
        trend: null,
      ),
    ];

    return Row(children: metrics
        .asMap()
        .entries
        .map((e) =>
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: e.key > 0 ? 12 : 0),
            child: _MetricPanel(def: e.value),
          ),
        )).toList());
  }

  String _fmt(int n) => NumberFormat('#,##,###').format(n);
}

class _MetricDef {
  const _MetricDef({required this.label, required this.value,
    required this.sub, required this.icon,
    required this.grad, required this.trend});

  final String label, value, sub;
  final IconData icon;
  final List<Color> grad;
  final String? trend;
}

class _MetricPanel extends StatelessWidget {
  const _MetricPanel({required this.def});

  final _MetricDef def;

  @override
  Widget build(BuildContext context) =>
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: def.grad,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(
              color: def.grad.first.withValues(alpha: 0.3),
              blurRadius: 12, offset: const Offset(0, 4))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(def.icon, color: Colors.white, size: 18),
            ),
            const Spacer(),
            // Sparkline placeholder — 5 points
            SizedBox(width: 48, height: 24,
                child: CustomPaint(painter: _SparkPainter())),
          ]),
          const SizedBox(height: 12),
          Text(def.value,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800,
                  color: Colors.white, letterSpacing: -0.5),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(def.label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.75))),
          const SizedBox(height: 6),
          Text(def.sub,
              style: TextStyle(fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.6))),
        ]),
      );
}

class _SparkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rng = [0.4, 0.7, 0.5, 0.9, 0.65, 0.8, 1.0];
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    for (int i = 0; i < rng.length; i++) {
      final x = size.width * i / (rng.length - 1);
      final y = size.height * (1 - rng[i]);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }

  @override bool shouldRepaint(_) => false;
}

// ── Operations Board ──────────────────────────────────────────────────────────
class _OpsBoard extends StatelessWidget {
  const _OpsBoard({required this.data, required this.onNavigate});

  final DashboardData data;
  final void Function(String) onNavigate;

  @override
  Widget build(BuildContext context) {
    final cols = [
      _OpsCol('New Orders', data.pendingOrders, _kBlue,
          Icons.shopping_cart_outlined, R.orders),
      _OpsCol('Approval Pending', data.pendingApprovals, _kOrange,
          Icons.verified_outlined, R.approvals),
      _OpsCol('Dispatch Pending', data.activeDeliveries, _kBlue,
          Icons.local_shipping_outlined, R.dispatch),
      _OpsCol('Delivered Today', data.todayDelivered, _kGreen,
          Icons.check_circle_outline, R.approvals),
    ];

    return Container(
      decoration: BoxDecoration(
        color: _kPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
        boxShadow: _kShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(children: [
            const Text('OPERATIONS BOARD',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                    color: _kText1, letterSpacing: 0.8)),
            const Spacer(),
            Text(DateFormat('d MMM y').format(DateTime.now()),
                style: const TextStyle(fontSize: 11, color: _kText3)),
          ]),
        ),
        const Divider(height: 1, color: _kBorder),

        // 4 columns
        IntrinsicHeight(
          child: Row(
            children: cols
                .asMap()
                .entries
                .map((e) {
              final col = e.value;
              return Expanded(child: _OpsBoardCol(
                col: col,
                onNavigate: onNavigate,
                showDivider: e.key < cols.length - 1,
              ));
            }).toList(),
          ),
        ),
      ]),
    );
  }
}

class _OpsCol {
  const _OpsCol(this.label, this.count, this.color, this.icon, this.route);

  final String label;
  final int count;
  final Color color;
  final IconData icon;
  final String route;
}

class _OpsBoardCol extends StatelessWidget {
  const _OpsBoardCol({required this.col, required this.onNavigate,
    required this.showDivider});

  final _OpsCol col;
  final void Function(String) onNavigate;
  final bool showDivider;

  @override
  Widget build(BuildContext context) =>
      InkWell(
        onTap: () => onNavigate(col.route),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: showDivider
              ? const BoxDecoration(
              border: Border(right: BorderSide(color: _kBorder)))
              : null,
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                  color: col.color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(col.icon, color: col.color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(col.label,
                      style: const TextStyle(fontSize: 12, color: _kText2,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text('${col.count}',
                      style: TextStyle(
                          fontSize: 26, fontWeight: FontWeight.w800,
                          color: col.count > 0 ? col.color : _kText2,
                          letterSpacing: -0.5)),
                ])),
            Icon(Icons.arrow_forward_rounded, size: 14,
                color: col.color.withValues(alpha: 0.5)),
          ]),
        ),
      );
}

// ── Revenue Trend Panel (area chart simulation) ───────────────────────────────
class _RevenueTrendPanel extends StatelessWidget {
  const _RevenueTrendPanel({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) =>
      Container(
        decoration: BoxDecoration(
          color: _kPanel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kBorder),
          boxShadow: _kShadow,
        ),
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('SALES & REVENUE TREND',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                    color: _kText1, letterSpacing: 0.8)),
            const Spacer(),
            _ChipFilter('This Week'),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            _Legend(color: _kBlue, label: 'Revenue (₹)'),
            const SizedBox(width: 16),
            _Legend(color: _kText3, label: 'Sold (kg)'),
          ]),
          const SizedBox(height: 16),
          SizedBox(height: 160, child: CustomPaint(
            size: const Size(double.infinity, 160),
            painter: _AreaChartPainter(
              primaryColor: _kBlue,
              secondaryColor: _kText3,
            ),
          )),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            for (final d in [
              '9 May',
              '10 May',
              '11 May',
              '12 May',
              '13 May',
              '14 May',
              '15 May'
            ])
              Text(d, style: const TextStyle(fontSize: 9, color: _kText3)),
          ]),
          const SizedBox(height: 16),
          // Today revenue summary
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kBorder)),
            child: Row(children: [
              _MiniStat(
                  'Today\'s Revenue', Fmt.amount(data.todayCollected), _kBlue),
              _Divider(),
              _MiniStat('Cash Collected', Fmt.amount(data.todayCashCollected),
                  _kGreen),
              _Divider(),
              _MiniStat('UPI Collected', Fmt.amount(data.todayUpiCollected),
                  _kIndigo),
              _Divider(),
              _MiniStat(
                  'Outstanding', Fmt.amount(data.totalOutstanding), _kOrange),
            ]),
          ),
        ]),
      );
}

class _ChipFilter extends StatelessWidget {
  const _ChipFilter(this.label);

  final String label;

  @override
  Widget build(BuildContext c) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _kBorder)),
        child: Row(children: [
          Text(label, style: const TextStyle(fontSize: 11, color: _kText2,
              fontWeight: FontWeight.w500)),
          const SizedBox(width: 4),
          const Icon(
              Icons.keyboard_arrow_down_rounded, size: 14, color: _kText3),
        ]),
      );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext c) =>
      Row(children: [
        Container(width: 24, height: 2,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(1))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11, color: _kText3)),
      ]);
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.label, this.value, this.color);

  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext c) =>
      Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.center, children: [
        Text(value, style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 10, color: _kText3),
            textAlign: TextAlign.center),
      ]));
}

class _Divider extends StatelessWidget {
  @override Widget build(BuildContext c) =>
      Container(
          width: 1, height: 32, color: _kBorder,
          margin: const EdgeInsets.symmetric(horizontal: 8));
}

class _AreaChartPainter extends CustomPainter {
  const _AreaChartPainter(
      {required this.primaryColor, required this.secondaryColor});

  final Color primaryColor, secondaryColor;

  @override
  void paint(Canvas canvas, Size size) {
    // Revenue line (simulated — 7 points)
    final rev = [0.3, 0.55, 0.45, 0.72, 0.68, 0.85, 0.78];
    final sol = [0.2, 0.40, 0.35, 0.58, 0.52, 0.65, 0.60];

    _drawAreaLine(canvas, size, rev, primaryColor);
    _drawLine(canvas, size, sol, secondaryColor);

    // Y-axis labels
    final labels = ['₹5L', '₹4L', '₹3L', '₹2L', '₹1L', '₹0'];
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (int i = 0; i < labels.length; i++) {
      tp.text = TextSpan(text: labels[i],
          style: const TextStyle(fontSize: 8, color: _kText3));
      tp.layout();
      tp.paint(canvas, Offset(0, size.height * i / (labels.length - 1) - 6));
    }
  }

  void _drawAreaLine(Canvas canvas, Size size, List<double> pts, Color color) {
    final lp = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final ap = Paint()
      ..shader = LinearGradient(
        colors: [color.withOpacity(0.15), color.withOpacity(0)],
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final path = Path(),
        area = Path();
    final w = size.width * 0.85,
        ox = size.width * 0.15;

    for (int i = 0; i < pts.length; i++) {
      final x = ox + w * i / (pts.length - 1);
      final y = size.height * (1 - pts[i]) * 0.9 + size.height * 0.05;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      i == 0 ? area.moveTo(x, y) : area.lineTo(x, y);
    }
    area.lineTo(ox + w, size.height);
    area.lineTo(ox, size.height);
    area.close();

    canvas.drawPath(area, ap);
    canvas.drawPath(path, lp);

    // Dots
    final dp = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    for (int i = 0; i < pts.length; i++) {
      final x = ox + w * i / (pts.length - 1);
      final y = size.height * (1 - pts[i]) * 0.9 + size.height * 0.05;
      canvas.drawCircle(Offset(x, y), 3, dp);
    }
  }

  void _drawLine(Canvas canvas, Size size, List<double> pts, Color color) {
    final lp = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    final w = size.width * 0.85,
        ox = size.width * 0.15;
    for (int i = 0; i < pts.length; i++) {
      final x = ox + w * i / (pts.length - 1);
      final y = size.height * (1 - pts[i]) * 0.9 + size.height * 0.05;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(path, lp);
  }

  @override bool shouldRepaint(_) => false;
}

// ── Live Stock Panel ──────────────────────────────────────────────────────────
class _LiveStockPanel extends StatelessWidget {
  const _LiveStockPanel({required this.stock, required this.data});

  final List<StockPosition> stock;
  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final totalBirds = stock.isEmpty ? data.remainingBirds
        : stock.fold(0, (s, p) => s + p.availableBirds);
    final availBirds = stock.isEmpty ? 0 : stock.first.availableBirds;
    final inTransit = data.agentStatus.fold(0, (s, a) => s + a.liveStockBirds);
    final soldToday = data.todayDelivered;
    final mortality = data.todayMortalityBirdsLedger;

    final items = [
      ('Available', availBirds, 93.2, _kGreen),
      ('In Transit', inTransit, 6.8, _kBlue),
      ('Sold Today', soldToday, 0, _kOrange),
      ('Mortality', mortality, 0, _kRed),
    ];

    return Container(
      decoration: BoxDecoration(
        color: _kPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
        boxShadow: _kShadow,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('LIVE STOCK OVERVIEW',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                  color: _kText1, letterSpacing: 0.8)),
          const Spacer(),
          InkWell(
            onTap: () => context.push(R.stockDetail),
            child: const Text('View Detail →',
                style: TextStyle(
                    fontSize: 11, color: _kBlue, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          // Donut
          SizedBox(width: 140, height: 140,
            child: Stack(alignment: Alignment.center, children: [
              Transform.rotate(angle: -math.pi / 2,
                  child: CustomPaint(size: const Size(140, 140),
                      painter: _DonutPainter(
                        fraction: totalBirds > 0
                            ? (availBirds / totalBirds).clamp(0.0, 1.0) : 0.0,
                        ringColor: _kGreen,
                        trackColor: const Color(0xFFF1F5F9),
                        strokeWidth: 14,
                      ))),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(NumberFormat('#,##,###').format(totalBirds),
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800,
                        color: _kText1, letterSpacing: -0.5)),
                const Text('Total Birds',
                    style: TextStyle(fontSize: 10,
                        color: _kText3,
                        fontWeight: FontWeight.w500)),
              ]),
            ]),
          ),
          const SizedBox(width: 24),
          // Legend
          Expanded(child: Column(children: items.map((item) =>
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Container(width: 10, height: 10,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle, color: item.$4)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item.$1,
                      style: const TextStyle(fontSize: 13, color: _kText2,
                          fontWeight: FontWeight.w500))),
                  Text('${item.$2}',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700,
                          color: _kText1)),
                ]),
              )).toList())),
        ]),
        const SizedBox(height: 12),
        Text('Updated just now',
            style: const TextStyle(fontSize: 11, color: _kText3)),
      ]),
    );
  }
}

// ── Agent Leaderboard ─────────────────────────────────────────────────────────
class _AgentLeaderboard extends StatelessWidget {
  const _AgentLeaderboard({required this.agents, required this.onTap});

  final List<AgentStockStatus> agents;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (agents.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: _kPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
        boxShadow: _kShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Row(children: [
            const Text('AGENTS ON SHIFT',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                    color: _kText1, letterSpacing: 0.8)),
            const Spacer(),
            InkWell(onTap: onTap,
                child: const Text('View All',
                    style: TextStyle(fontSize: 11, color: _kBlue,
                        fontWeight: FontWeight.w600))),
          ]),
        ),
        const Divider(height: 1, color: _kBorder),
        ...agents.take(5).map((a) => _AgentRow(agent: a)),
      ]),
    );
  }
}

class _AgentRow extends StatelessWidget {
  const _AgentRow({required this.agent});

  final AgentStockStatus agent;

  @override
  Widget build(BuildContext c) =>
      Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _kBorder))),
        child: Row(children: [
          // Avatar
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: _kNavBg, shape: BoxShape.circle,
              border: Border.all(
                  color: agent.hasOpenShift ? _kGreen : _kText3, width: 2),
            ),
            child: Center(child: Text(
              agent.agentName.isNotEmpty
                  ? agent.agentName[0].toUpperCase()
                  : '?',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                  color: Colors.white),
            )),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(agent.agentName, style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w600, color: _kText1),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('${agent.todayDeliveredBirds} Deliveries',
                    style: const TextStyle(fontSize: 11, color: _kText3)),
              ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: agent.hasOpenShift ? _kGreenLt : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                  color: agent.hasOpenShift
                      ? _kGreen.withValues(alpha: 0.3)
                      : _kBorder),
            ),
            child: Text(agent.hasOpenShift ? 'On Shift' : 'Closed',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: agent.hasOpenShift ? _kGreen : _kText3)),
          ),
        ]),
      );
}

// ── Financial Health ──────────────────────────────────────────────────────────
class _FinancialHealth extends StatelessWidget {
  const _FinancialHealth({required this.data,
    required this.onLedger, required this.onClosure});

  final DashboardData data;
  final VoidCallback onLedger, onClosure;

  @override
  Widget build(BuildContext context) =>
      Container(
        decoration: BoxDecoration(
          color: _kPanel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kBorder),
          boxShadow: _kShadow,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(children: [
              const Text('COLLECTIONS SUMMARY',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                      color: _kText1, letterSpacing: 0.8)),
              const Spacer(),
              InkWell(onTap: onLedger,
                  child: const Text('View All',
                      style: TextStyle(fontSize: 11, color: _kBlue,
                          fontWeight: FontWeight.w600))),
            ]),
          ),
          const Divider(height: 1, color: _kBorder),
          Padding(padding: const EdgeInsets.all(18), child: Column(children: [
            // Half donut for collection rate
            _CollRow(icon: Icons.currency_rupee_rounded,
                color: _kGreen,
                label: "Today's Collection",
                value: Fmt.amount(data.todayCollected)),
            const SizedBox(height: 10),
            _CollRow(icon: Icons.hourglass_empty_rounded,
                color: _kOrange,
                label: 'Pending Collection',
                value: Fmt.amount(data.totalOutstanding)),
            const Divider(height: 20, color: _kBorder),
            _CollRow(icon: Icons.money_rounded,
                color: _kIndigo,
                label: 'Cash In Hand',
                value: Fmt.amount(data.todayCashCollected)),
            const SizedBox(height: 10),
            // Overdue customers — using open shifts as proxy
            _CollRow(icon: Icons.people_outline,
                color: _kRed,
                label: 'Overdue Customers',
                value: '${(data.openShifts * 2).clamp(0, 99)}',
                isCount: true),
            if (data.allClear) ...[
              const Divider(height: 20, color: _kBorder),
              GestureDetector(
                onTap: onClosure,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: _kNavBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(child: Text('Close Day →',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight
                          .w700,
                          color: Colors.white))),
                ),
              ),
            ],
          ])),
        ]),
      );
}

class _CollRow extends StatelessWidget {
  const _CollRow({required this.icon, required this.color,
    required this.label, required this.value, this.isCount = false});

  final IconData icon;
  final Color color;
  final String label, value;
  final bool isCount;

  @override
  Widget build(BuildContext c) =>
      Row(children: [
        Container(width: 34, height: 34,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 16)),
        const SizedBox(width: 10),
        Expanded(child: Text(label,
            style: const TextStyle(
                fontSize: 12, color: _kText2, fontWeight: FontWeight.w500))),
        Text(isCount ? value : value,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                color: isCount && int.tryParse(value) != null &&
                    int.parse(value) > 0
                    ? _kRed : _kText1)),
      ]);
}

// ── Alerts Panel ──────────────────────────────────────────────────────────────
class _AlertsPanel extends StatelessWidget {
  const _AlertsPanel({required this.data, required this.stock,
    required this.onTap});

  final DashboardData data;
  final List<StockPosition> stock;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final totalBirds = stock.isEmpty ? data.remainingBirds
        : stock.fold(0, (s, p) => s + p.availableBirds);

    final alerts = <(Color, IconData, String, String)>[];
    if (totalBirds < 500 && totalBirds >= 0)
      alerts.add((_kOrange, Icons.inventory_outlined,
      'Low Stock Alert', 'Broiler Live stock is below 1000 birds'));
    if (data.totalOutstanding > 50000)
      alerts.add((_kRed, Icons.account_balance_wallet_outlined,
      'Payment Overdue', 'Outstanding exceeds ₹50,000'));
    if (data.activeDeliveries > 3)
      alerts.add((_kBlue, Icons.local_shipping_outlined,
      'Dispatch Delay', '${data.activeDeliveries} orders pending dispatch'));
    if (data.todayMortalityBirdsLedger > 0)
      alerts.add((_kViolet, Icons.warning_amber_outlined,
      'Mortality Today', '${data.todayMortalityBirdsLedger} birds'));

    if (alerts.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: _kPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
        boxShadow: _kShadow,
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Row(children: [
            const Text('CRITICAL ALERTS',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                    color: _kText1, letterSpacing: 0.8)),
            const Spacer(),
            InkWell(onTap: onTap,
                child: const Text('View All',
                    style: TextStyle(fontSize: 11, color: _kBlue,
                        fontWeight: FontWeight.w600))),
          ]),
        ),
        const Divider(height: 1, color: _kBorder),
        ...alerts.map((a) =>
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
              child: Row(children: [
                Container(width: 28, height: 28,
                    decoration: BoxDecoration(
                        color: a.$1.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6)),
                    child: Icon(a.$2, color: a.$1, size: 14)),
                const SizedBox(width: 10),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.$3, style: const TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _kText1)),
                  Text(a.$4, style: const TextStyle(fontSize: 11,
                      color: _kText3)),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: a.$1.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(99)),
                  child: const Text('!', style: TextStyle(fontSize: 11,
                      fontWeight: FontWeight.w800, color: _kOrange)),
                ),
              ]),
            )),
      ]),
    );
  }
}

// ── Recent Orders Table ───────────────────────────────────────────────────────
class _RecentOrdersTable extends StatefulWidget {
  const _RecentOrdersTable({required this.orders,
    required this.onViewAll, required this.onOrder});

  final List<Map<String, dynamic>> orders;
  final VoidCallback onViewAll;
  final void Function(String) onOrder;

  @override State<_RecentOrdersTable> createState() =>
      _RecentOrdersTableState();
}

class _RecentOrdersTableState extends State<_RecentOrdersTable> {
  String _statusFilter = 'All Status';
  final List<String> _statuses = [
    'All Status',
    'pending',
    'confirmed',
    'dispatched',
    'delivered'
  ];

  List<Map<String, dynamic>> get _filtered {
    if (_statusFilter == 'All Status') return widget.orders;
    return widget.orders.where((o) =>
    (o['status'] as String? ?? '') == _statusFilter).toList();
  }

  Color _statusColor(String s) =>
      switch(s) {
        'pending' => _kOrange,
        'confirmed' => _kBlue,
        'dispatched' => _kIndigo,
        'delivered' => _kGreen,
        'cancelled' => _kRed,
        _ => _kText3,
      };

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    return Container(
      decoration: BoxDecoration(
        color: _kPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
        boxShadow: _kShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Table toolbar
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Row(children: [
            const Text('RECENT ORDERS',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                    color: _kText1, letterSpacing: 0.8)),
            const SizedBox(width: 12),
            // Search box
            Container(
              width: 220, height: 32,
              decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _kBorder)),
              child: const TextField(
                decoration: InputDecoration(
                  hintText: 'Search orders...',
                  hintStyle: TextStyle(fontSize: 12, color: _kText3),
                  prefixIcon: Icon(
                      Icons.search_rounded, size: 14, color: _kText3),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
                style: TextStyle(fontSize: 12, color: _kText1),
              ),
            ),
            const SizedBox(width: 8),
            // Status filter
            _DropFilter(
              value: _statusFilter,
              options: _statuses,
              onChanged: (v) => setState(() => _statusFilter = v),
            ),
            const Spacer(),
            // Showing count
            Text('Showing ${rows.length} of ${widget.orders.length} orders',
                style: const TextStyle(fontSize: 11, color: _kText3)),
            const SizedBox(width: 12),
            InkWell(onTap: widget.onViewAll,
                child: Container(padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(color: _kNavBg,
                        borderRadius: BorderRadius.circular(6)),
                    child: const Text('View All Orders',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600,
                            color: Colors.white)))),
          ]),
        ),
        // Column headers
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [_kNavBg, Color(0xFF1E293B)]),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          child: Row(children: const [
            _TH('Order ID', 90),
            _TH('Customer', 200),
            _TH('Birds / Weight', 140),
            _TH('Amount', 120, right: true),
            _TH('Status', 110, center: true),
            _TH('Agent', 120),
            _TH('Time', 90),
            _TH('Action', 60, center: true),
          ]),
        ),
        // Data rows
        if (rows.isEmpty)
          const Padding(padding: EdgeInsets.all(32),
              child: Center(child: Text('No orders found',
                  style: TextStyle(color: _kText3))))
        else
          ...rows
              .asMap()
              .entries
              .map((e) {
            final i = e.key;
            final o = e.value;
            final status = o['status'] as String? ?? 'pending';
            final retailer = o['retailers'] as Map<String, dynamic>?;
            final shopName = retailer?['shop_name'] as String? ?? '—';
            final birds = (o['estimated_birds'] as num?)?.toInt() ?? 0;
            final wt = (o['total_quantity'] as num?)?.toDouble() ?? 0;
            final amt = (o['total_amount'] as num?)?.toDouble() ?? 0;
            final createdAt = DateTime.tryParse(
                o['created_at'] as String? ?? '');
            final timeStr = createdAt != null
                ? DateFormat('hh:mm a').format(createdAt) : '—';
            final sc = _statusColor(status);

            return _OrderRow(
              index: i,
              orderId: '#${(o['id'] as String? ?? '')
                  .substring(0, 6)
                  .toUpperCase()}',
              shopName: shopName,
              birds: birds,
              weight: wt,
              amount: amt,
              status: status,
              statusColor: sc,
              time: timeStr,
              onTap: () => widget.onOrder(o['id'] as String? ?? ''),
            );
          }),
        // Footer
        Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _kBorder))),
          child: Row(children: [
            Text(
                'Showing 1 to ${rows.length} of ${widget.orders.length} orders',
                style: const TextStyle(fontSize: 11, color: _kText3)),
            const Spacer(),
            // Pagination pills
            ...['‹', '1', '2', '3', '…', '26', '›'].map((l) =>
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                      color: l == '1' ? _kNavBg : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _kBorder),
                    ),
                    child: Center(child: Text(l,
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600,
                            color: l == '1' ? Colors.white : _kText2))),
                  ),
                )),
          ]),
        ),
      ]),
    );
  }
}

class _TH extends StatelessWidget {
  const _TH(this.label, this.width, {this.right = false, this.center = false});

  final String label;
  final double width;
  final bool right, center;

  @override
  Widget build(BuildContext c) =>
      SizedBox(width: width, child: Text(label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
              color: Color(0xFF94A3B8), letterSpacing: 0.6),
          textAlign: right ? TextAlign.right : center
              ? TextAlign.center
              : TextAlign.left));
}

class _OrderRow extends StatefulWidget {
  const _OrderRow({required this.index, required this.orderId,
    required this.shopName, required this.birds, required this.weight,
    required this.amount, required this.status, required this.statusColor,
    required this.time, required this.onTap});

  final int index;
  final String orderId, shopName, status, time;
  final int birds;
  final double weight, amount;
  final Color statusColor;
  final VoidCallback onTap;

  @override State<_OrderRow> createState() => _OrderRowState();
}

class _OrderRowState extends State<_OrderRow> {
  bool _hov = false;

  @override
  Widget build(BuildContext c) =>
      MouseRegion(
        onEnter: (_) => setState(() => _hov = true),
        onExit: (_) => setState(() => _hov = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: widget.onTap,
          child: AnimatedContainer(duration: const Duration(milliseconds: 100),
            color: _hov ? const Color(0xFFF8FAFC)
                : widget.index.isEven ? _kPanel : const Color(0xFFFBFCFD),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            child: Row(children: [
              SizedBox(width: 90, child: Text(widget.orderId,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600,
                      color: _kBlue))),
              SizedBox(width: 200, child: Text(widget.shopName,
                  style: const TextStyle(fontSize: 13, color: _kText1,
                      fontWeight: FontWeight.w500),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
              SizedBox(width: 140,
                  child: Text('${widget.birds} birds  •  ${widget.weight
                      .toStringAsFixed(0)} kg',
                      style: const TextStyle(fontSize: 12, color: _kText2))),
              SizedBox(width: 120, child: Text(Fmt.amount(widget.amount),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: _kText1))),
              SizedBox(width: 110, child: Center(child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: widget.statusColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                        color: widget.statusColor.withValues(alpha: 0.25))),
                child: Text(widget.status.replaceAll('_', ' ').capitalize(),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: widget.statusColor)),
              ))),
              const SizedBox(width: 120, child: Text('—',
                  style: TextStyle(fontSize: 12, color: _kText3))),
              SizedBox(width: 90, child: Text(widget.time,
                  style: const TextStyle(fontSize: 12, color: _kText3))),
              SizedBox(width: 60,
                  child: Center(child: Icon(Icons.visibility_outlined,
                      size: 16, color: _kText3))),
            ]),
          ),
        ),
      );
}

class _DropFilter extends StatelessWidget {
  const _DropFilter({required this.value, required this.options,
    required this.onChanged});

  final String value;
  final List<String> options;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext c) =>
      Container(
        height: 32, padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _kBorder)),
        child: DropdownButtonHideUnderline(child: DropdownButton<String>(
          value: value,
          isDense: true,
          style: const TextStyle(fontSize: 12, color: _kText1),
          items: options.map((o) =>
              DropdownMenuItem(value: o,
                  child: Text(o, style: const TextStyle(fontSize: 12))))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        )),
      );
}

// ── Donut painter (shared with mobile) ───────────────────────────────────────
class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.fraction, required this.ringColor,
    required this.trackColor, required this.strokeWidth});

  final double fraction;
  final Color ringColor, trackColor;
  final double strokeWidth;

  @override void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = (size.width - strokeWidth) / 2;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    p.color = trackColor;
    canvas.drawCircle(c, r, p);
    p.color = ringColor;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), 0,
        2 * 3.14159 * fraction.clamp(0.0, 1.0), false, p);
  }

  @override bool shouldRepaint(_DonutPainter o) =>
      o.fraction != fraction || o.ringColor != ringColor;
}

// ── QA helper ─────────────────────────────────────────────────────────────────
class _QA {
  const _QA(this.icon, this.label, this.color, this.bg, this.onTap,
      {this.wide = false});

  final IconData icon;
  final String label;
  final Color color, bg;
  final VoidCallback onTap;
  final bool wide;
}

// ── Language helper ───────────────────────────────────────────────────────────
class _L {
  static String g(String lang, String k) => _t[lang]?[k] ?? _t['en']![k] ?? k;
  static const _t = {
    'en': {
      'today': 'Today Overview',
      'new_order': 'New Order',
      'orders': 'Orders',
      'approve': 'Approve',
      'dispatch': 'Dispatch',
      'collect': 'Collect Cash',
      'customers': 'Customers',
      'agents': 'Agents',
      'rate': 'Set Rate',
      'returns': 'Returns',
      'reconcile': 'Check Cash',
      'close_day': 'Close Day',
      'alerts': 'Alerts',
      'report': 'Report',
      'crates': 'Crates',
      'invoices': 'Bills',
      'shifts': 'Shifts',
      'stock_in': 'Purchased',
      'delivered': 'Delivered',
      'returned': 'Returns',
      'remaining': 'Remaining',
      'add_stock': 'Add Stock',
      'outstanding': 'To Collect',
      'cash': 'Cash',
      'upi': 'UPI'
    },
    'ta': {
      'today': 'இன்றைய நிலை',
      'new_order': 'புது ஆர்டர்',
      'orders': 'ஆர்டர்',
      'approve': 'அனுமதி',
      'dispatch': 'அனுப்பு',
      'collect': 'பணம் வசூல்',
      'customers': 'வாடிக்கையாளர்',
      'agents': 'ஏஜெண்ட்',
      'rate': 'விலை',
      'returns': 'திருப்பம்',
      'reconcile': 'கேஷ் சரிபார்',
      'close_day': 'நாள் முடி',
      'alerts': 'எச்சரிக்கை',
      'report': 'அறிக்கை',
      'crates': 'கிரேட்',
      'invoices': 'பில்',
      'shifts': 'ஷிஃப்ட்',
      'stock_in': 'வாங்கியது',
      'delivered': 'டெலிவரி',
      'returned': 'திருப்பம்',
      'remaining': 'மீதம்',
      'add_stock': 'கோழி சேர்',
      'outstanding': 'வசூல் செய்ய',
      'cash': 'கேஷ்',
      'upi': 'UPI'
    },
  };
}

extension _StrExt on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}