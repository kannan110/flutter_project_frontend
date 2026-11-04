import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../shared/widgets/web/web.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:rooster_trader/features/trader_admin/expenses/trader_expense_sheet.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/dashboard_models.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/responsive_layout.dart';
import '../dashboard/trader_shell.dart';

// ── Language provider ─────────────────────────────────────────────────────────
final langProvider = StateProvider<String>((ref) => 'en');

// ── Design tokens (enterprise SaaS — desktop-first) ──────────────────────────
const _kPageBg = WebColors.pageBg;
// Brand palette: navy = primary, gold = accent, semantic colours for status.
const _kPanel = WebColors.surface;
const _kBorder = WebColors.border;
const _kNavBg = WebColors.navy;
const _kText1 = WebColors.text1;
const _kText2 = WebColors.text2;
const _kText3 = WebColors.text3;
const _kBlue = WebColors.navy;          // primary accent
const _kGold = Color(0xFFB8913F);       // gold, darkened for text/lines on white
const _kGreen = WebColors.success;
const _kGreenLt = WebColors.successBg;
const _kOrange = WebColors.warning;
const _kRed = WebColors.error;
const _kRedLt = WebColors.errorBg;
const _kIndigo = WebColors.info;
const _kColorsViolet = _kGold;

const _kShadow = WebShadow.card;

// ─────────────────────────────────────────────────────────────────────────────
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override ConsumerState<DashboardScreen> createState() => _S();
}

class _S extends ConsumerState<DashboardScreen> {
  DashboardData? _data;
  List<StockPosition> _stock = [];
  List<Map<String, dynamic>> _recentOrders = [];
  List<Map<String, dynamic>> _dashboardAging   = [];  // from get_dashboard_aging
  List<Map<String, dynamic>> _topRetailers     = [];  // from get_top_retailers_today
  List<Map<String, dynamic>> _revenueTrend     = [];  // from get_7day_revenue_trend
  // ★ Business Health — Current Stock Value by Product. Purely rendered
  // from get_business_health_by_product_v1 — every cost/value figure comes
  // from the shared Valuation Engine (Traced → Effective Stock Point Cost
  // → Existing Average Cost → MWAC → Pending), nothing computed here.
  // Filtered to enabled AND currently-stocked products only (kg > 0) —
  // this main dashboard is a top-level summary, not the per-product deep
  // dive (that's Inventory Dashboard, which still shows every product
  // regardless of current stock level).
  List<Map<String, dynamic>> _stockValueByProduct = [];
  bool _loading = true;
  String? _error;

  @override void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tid = ref
        .read(appUserProvider)
        .valueOrNull
        ?.traderId;
    if (tid == null || !mounted) return;
    if (mounted) {
      setState(() {
      _loading = true;
      _error = null;
    });
    }
    try {
      final results = await Future.wait([
        Supabase.instance.client
            .rpc('dashboard_summary', params: {'p_trader_id': tid}),
        Supabase.instance.client
            .rpc('get_available_stock', params: {'p_trader_id': tid}),
        Supabase.instance.client
            .rpc('get_dashboard_aging', params: {'p_trader_id': tid})
            .timeout(const Duration(seconds: 8)),
        Supabase.instance.client
            .rpc('get_top_retailers_today', params: {'p_trader_id': tid})
            .timeout(const Duration(seconds: 8)),
        Supabase.instance.client
            .rpc('get_7day_revenue_trend', params: {'p_trader_id': tid})
            .timeout(const Duration(seconds: 8)),
      ]);

      List<Map<String, dynamic>> recentOrders = [];
      try {
        final r = await Supabase.instance.client
            .from('orders')
            .select(
            'id,status,estimated_birds,total_quantity,total_amount,created_at,'
                'retailers(shop_name),deliveries(delivery_agents(name))')
            .eq('trader_id', tid)
            .order('created_at', ascending: false)
            .limit(10);
        recentOrders = List<Map<String, dynamic>>.from(r as List? ?? []);
      } catch (_) {}

      // ★ Business Health — Current Stock Value by Product. Isolated in
      // its own try/catch (matching recentOrders above) so a failure here
      // never breaks the rest of the dashboard — it just shows nothing.
      List<Map<String, dynamic>> bhRows = [];
      try {
        final bh = await Supabase.instance.client
            .rpc('get_business_health_by_product_v1', params: {'p_trader_id': tid})
            .timeout(const Duration(seconds: 8));
        // ★ Presentation-only filter (which rows to show), not a
        // calculation — every value in each row already came from the
        // backend untouched.
        bhRows = List<Map<String, dynamic>>.from((bh as Map?)?['rows'] as List? ?? [])
            .where((r) => ((r['current_stock_kg'] as num?) ?? 0) > 0)
            .toList();
      } catch (_) {}

      if (!mounted) return;

      final dm  = results[0] as Map<String, dynamic>?;
      final sl  = results[1] as List?;
      final ag  = results[2] as List?;
      final tr  = results[3] as List?;
      final rt  = results[4] as List?;

      setState(() {
        _data         = dm != null ? DashboardData.fromMap(dm) : const DashboardData();
        _stock        = (sl ?? []).map((s) =>
            StockPosition.fromMap(s as Map<String, dynamic>)).toList();
        _dashboardAging = List<Map<String, dynamic>>.from(ag ?? []);
        _topRetailers   = List<Map<String, dynamic>>.from(tr ?? []);
        _revenueTrend   = List<Map<String, dynamic>>.from(rt ?? []);
        _recentOrders = recentOrders;
        _stockValueByProduct = bhRows;
        _loading      = false;
      });

      if (mounted && _data != null) {
        ref.read(shellBadgesProvider.notifier).update((s) =>
            s.copyWith(
              pendingApprovals: _data!.pendingApprovals,
              unreadAlerts:     _data!.unreadAlerts,
              pendingOrders:    _data!.pendingOrders,
            ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error   = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref
        .watch(appUserProvider)
        .valueOrNull;
    final lang = ref.watch(langProvider);
    String t(String k) => _L.g(lang, k);
    return ResponsiveLayout(
      mobile:  (_) => _buildMobileScaffold(user, lang, t),
      tablet:  (_) => _buildTabletScaffold(user, lang, t),
      desktop: (_) => _buildDesktopLayout(user, lang, t),
    );
  }

  Widget _buildDesktopLayout(dynamic user, String lang,
      String Function(String) t) {
    if (_loading) {
      return const Center(child: SizedBox(
        width: 28, height: 28,
        child: CircularProgressIndicator(strokeWidth: 2, color: _kBlue)));
    }
    if (_error != null) return _errorView();

    final d = _data ?? const DashboardData();
    final now = DateTime.now();

    return ColoredBox(
      color: _kPageBg,
      child: SingleChildScrollView(
          padding: WebSpace.page,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _CommandHeader(user: user, data: d, onRefresh: _load, now: now),
            _MetricStrip(data: d, stock: _stock),
            const SizedBox(height: _gap),
            _BusinessHealthWeb(
              data: d,
              stockValueByProduct: _stockValueByProduct,
              onPnl: () => context.push(R.pnlStatement),
              onCashFlow: () => context.push(R.cashFlowStatement),
            ),
            const SizedBox(height: _gap),
            _OpsBoard(data: d, onNavigate: (r) => context.go(r)),
            const SizedBox(height: _gap),
            // Row 1 — sales trend + collections (equal height)
            _equalRow([
              (8, _RevenueTrendPanel(data: d, trend: _revenueTrend)),
              (4, _CollectionIntelligencePanel(
                  data: d,
                  aging: _dashboardAging,
                  onLedger: () => context.go(R.ledger),
                  onClosure: () => context.go(R.dayClosure))),
            ]),
            const SizedBox(height: _gap),
            // Row 2 — stock · agents · (top retailers / alerts)
            LayoutBuilder(builder: (_, c) {
              final stockPanel = _LiveStockPanel(stock: _stock, data: d);
              final agentPanel = _NavigatorAgentShift(
                  agents: d.agentStatus, onTap: () => context.go(R.agents));
              final side = <Widget>[
                if (_topRetailers.isNotEmpty)
                  _TopRetailersToday(
                      retailers: _topRetailers,
                      onViewAll: () => context.go(R.retailers)),
                if (d.unreadAlerts > 0 || d.remainingBirds < 50)
                  _AlertsPanel(data: d, stock: _stock,
                      onTap: () => context.go(R.alerts)),
              ];
              // Stack the side panels; the last one fills leftover height
              Widget? sideCol;
              if (side.isNotEmpty) {
                sideCol = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < side.length; i++)
                      if (i == side.length - 1)
                        Expanded(child: side[i])
                      else ...[side[i], const SizedBox(height: _gap)],
                  ],
                );
              }
              final wide = c.maxWidth >= 1100;
              if (sideCol == null || wide) {
                return _equalRow([
                  (1, stockPanel),
                  (1, agentPanel),
                  if (sideCol != null) (1, sideCol),
                ]);
              }
              // Narrower screens: two per row so nothing gets squashed
              return Column(children: [
                _equalRow([(1, stockPanel), (1, agentPanel)]),
                const SizedBox(height: _gap),
                _equalRow([(1, sideCol)]),
              ]);
            }),
            const SizedBox(height: _gap),
            _RecentOrdersTable(
              orders: _recentOrders,
              onViewAll: () => context.go(R.orders),
              onOrder: (id) => context.push(R.orderDetailPath(id)),
            ),
          ]),
      ),
    );
  }

  // One gap size for the whole desktop dashboard
  static const double _gap = WebSpace.lg;

  /// Cards side by side, all stretched to the tallest one (no ragged gaps).
  Widget _equalRow(List<(int, Widget)> cells) => IntrinsicHeight(
    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < cells.length; i++) ...[
        if (i > 0) const SizedBox(width: _gap),
        Expanded(flex: cells[i].$1, child: cells[i].$2),
      ],
    ]),
  );

  Widget _buildMobileScaffold(dynamic user, String lang,
      String Function(String) t) {
    if (_loading) {
      return const Scaffold(backgroundColor: kBgPage,
        body: Center(
            child: CircularProgressIndicator(color: kNavy, strokeWidth: 2.5)));
    }
    if (_error != null) {
      return Scaffold(backgroundColor: kBgPage, body: _errorView());
    }

    final d       = _data!;
    final agents  = d.agentStatus;
    final survDays = d.stockSurvivalDays;
    final totalBirds = _stock.isEmpty ? d.remainingBirds
        : _stock.fold(0, (s, p) => s + p.availableBirds);

    final stockColor = survDays == null ? kNavy
        : survDays < 1 ? kError
        : survDays < 3 ? kWarning
        : kSuccess;

    final List<({IconData icon, String label, Color color, VoidCallback onTap})> priorityActions = [
      if (d.pendingApprovals > 0)
        (icon: Icons.verified_outlined, label: 'Approve (${d.pendingApprovals})',
        color: kWarning, onTap: () => context.go(R.approvals)),
      if (d.pendingOrders > 0)
        (icon: Icons.shopping_cart_outlined, label: 'Orders (${d.pendingOrders})',
        color: Colors.blue, onTap: () => context.go(R.orders)),
      if (d.activeDeliveries > 0)
        (icon: Icons.local_shipping_outlined, label: 'Dispatch (${d.activeDeliveries})',
        color: Colors.indigo, onTap: () => context.go(R.dispatch)),
      if (d.delayedDeliveries > 0)
        (icon: Icons.timer_off_outlined, label: 'Delayed (${d.delayedDeliveries})',
        color: kError, onTap: () => context.go(R.dispatch)),
      if (d.allClear)
        (icon: Icons.lock_clock_outlined, label: 'Close Day',
        color: kSuccess, onTap: () => context.go(R.dayClosure)),
      (icon: Icons.add_circle_outlined, label: t('new_order'),
      color: Colors.orange.shade700, onTap: () => context.go(R.orderCreate)),
    ].take(3).toList();

    final topActions = _allActions(t).take(6).toList();

    return Scaffold(
      backgroundColor: kBgPage,
      body: RefreshIndicator(
        onRefresh: _load, color: kNavy, strokeWidth: 2.5,
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(child: _mobileHeader(user, lang, t)),
          if (_buildAlerts(t).isNotEmpty)
            SliverPadding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                sliver: SliverList.list(children: _buildAlerts(t)
                    .map((w) => Padding(
                    padding: const EdgeInsets.only(bottom: 8), child: w))
                    .toList())),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [kNavy, kNavyMid],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(kRadiusHero),
                boxShadow: [BoxShadow(color: kNavy.withValues(alpha: 0.35),
                    blurRadius: 24, offset: const Offset(0, 8))],
              ),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Text("TODAY'S PULSE", style: TextStyle(fontSize: 10,
                          fontWeight: FontWeight.w900, color: Color(0xFFB4C6F4),
                          letterSpacing: 0.8)),
                      const Spacer(),
                      if (d.todayRate != null) Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(
                            (d.rateDelta ?? 0) > 0
                                ? Icons.arrow_upward_rounded
                                : (d.rateDelta ?? 0) < 0
                                ? Icons.arrow_downward_rounded
                                : Icons.remove_rounded,
                            size: 10,
                            color: (d.rateDelta ?? 0) > 0
                                ? const Color(0xFF86EFAC)
                                : (d.rateDelta ?? 0) < 0
                                ? const Color(0xFFFCA5A5)
                                : const Color(0xFFB4C6F4),
                          ),
                          const SizedBox(width: 3),
                          Text('₹${d.todayRate!.toStringAsFixed(0)}/kg',
                              style: const TextStyle(fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(onTap: _load,
                          child: const Icon(Icons.refresh_rounded,
                              color: Color(0xFFB4C6F4), size: 16)),
                    ]),
                    const SizedBox(height: 20),
                    Row(children: [
                      _pulseItem(
                        icon: Icons.currency_rupee_rounded,
                        value: Fmt.amount(d.todayRevenue > 0
                            ? d.todayRevenue : d.todayCollected),
                        label: 'Revenue',
                        onTap: () => context.go(R.ledger),
                        urgent: false,
                      ),
                      _pulseItem(
                        icon: Icons.inventory_2_rounded,
                        value: '$totalBirds',
                        label: survDays != null
                            ? '${survDays.toStringAsFixed(1)}d left'
                            : 'Birds',
                        onTap: () => context.push(R.stockDetail),
                        urgent: survDays != null && survDays < 3,
                        urgentColor: stockColor,
                      ),
                      _pulseItem(
                        icon: Icons.account_balance_wallet_outlined,
                        value: Fmt.amount(d.totalOutstanding),
                        label: 'Outstanding',
                        onTap: () => context.go(R.ledger),
                        urgent: d.overLimitCount > 0,
                      ),
                    ]),
                  ]),
            ),
          )),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _BusinessHealthCard(
              data: d,
              stockValueByProduct: _stockValueByProduct,
              onPnl: () => context.push(R.pnlStatement),
              onCashFlow: () => context.push(R.cashFlowStatement),
            ),
          )),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(padding: EdgeInsets.only(bottom: 10),
                      child: Row(children: [
                        Icon(Icons.bolt_rounded, color: kGold, size: 16),
                        SizedBox(width: 6),
                        Text('PRIORITY ACTIONS', style: TextStyle(fontSize: 11,
                            fontWeight: FontWeight.w900, color: kNavy,
                            letterSpacing: 0.6)),
                      ])),
                  Row(children: priorityActions.asMap().entries.map((e) {
                    final a = e.value;
                    return Expanded(child: Padding(
                      padding: EdgeInsets.only(left: e.key > 0 ? 8 : 0),
                      child: GestureDetector(
                        onTap: a.onTap,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 8),
                          decoration: BoxDecoration(
                            color: a.color.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(kRadiusCard),
                            border: Border.all(
                                color: a.color.withValues(alpha: 0.25)),
                          ),
                          child: Column(mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(a.icon, color: a.color, size: 22),
                                const SizedBox(height: 6),
                                Text(a.label, textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 10,
                                        fontWeight: FontWeight.w800, color: a.color),
                                    maxLines: 2, overflow: TextOverflow.ellipsis),
                              ]),
                        ),
                      ),
                    ));
                  }).toList()),
                ]),
          )),
          if (agents.isNotEmpty) SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              decoration: BoxDecoration(
                color: kSurface,
                borderRadius: BorderRadius.circular(kRadiusCard),
                border: Border.all(color: kBorderLight.withValues(alpha: 0.5)),
                boxShadow: kCardShadow,
              ),
              child: Column(children: [
                Padding(padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                    child: Row(children: [
                      const Icon(Icons.groups_rounded, color: kGold, size: 16),
                      const SizedBox(width: 8),
                      const Text('LIVE DISPATCH', style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w900,
                          color: kNavy, letterSpacing: 0.6)),
                      const Spacer(),
                      GestureDetector(onTap: () => context.go(R.dispatch),
                          child: const Text('VIEW ALL', style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w900,
                              color: kGold, letterSpacing: 0.5))),
                    ])),
                const Divider(height: 1, color: kBorderLight),
                ...agents.take(4).toList().asMap().entries.map((e) {
                  final i = e.key;
                  final a = e.value;
                  final delayed = a.pendingDeliveries > 0
                      && !a.hasOpenShift;
                  return Container(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                    decoration: i < (agents.take(4).length - 1)
                        ? BoxDecoration(border: Border(bottom: BorderSide(
                        color: kBorderLight.withValues(alpha: 0.5))))
                        : null,
                    child: Row(children: [
                      Container(width: 8, height: 8,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: a.hasOpenShift ? kSuccess
                                  : delayed ? kError : kTextHint)),
                      const SizedBox(width: 10),
                      Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.agentName, style: const TextStyle(fontSize: 13,
                                fontWeight: FontWeight.w800, color: kNavy),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text(a.hasOpenShift ? 'On Shift' : 'Closed',
                                style: TextStyle(fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: a.hasOpenShift ? kSuccess : kTextHint)),
                          ])),
                      if (a.todayDcKg > 0) Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${a.todayDcKg.toStringAsFixed(0)} kg',
                                style: const TextStyle(fontSize: 12,
                                    fontWeight: FontWeight.w800, color: kNavy)),
                            const Text('loaded', style: TextStyle(
                                fontSize: 9, color: kTextHint)),
                          ])
                      else Text('${a.liveStockBirds} birds',
                          style: const TextStyle(fontSize: 12,
                              fontWeight: FontWeight.w700, color: kTextSub)),
                    ]),
                  );
                }),
              ]),
            ),
          )),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(padding: EdgeInsets.only(bottom: 12),
                      child: Row(children: [
                        Icon(Icons.apps_rounded, color: kGold, size: 16),
                        SizedBox(width: 6),
                        Text('QUICK ACCESS', style: TextStyle(fontSize: 11,
                            fontWeight: FontWeight.w900, color: kNavy,
                            letterSpacing: 0.6)),
                      ])),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 2.4),
                    itemCount: topActions.length,
                    itemBuilder: (_, i) => _qaBtn(topActions[i]),
                  ),
                ]),
          )),
          SliverToBoxAdapter(child: _stockSection(t)),
          SliverToBoxAdapter(child: _financialSection(t)),
          if ((d.todayDelivered) > 0)
            SliverToBoxAdapter(child: _reconSection(t)),
          if (d.todayReturnsBirds > 0 || d.pendingReturns > 0)
            SliverToBoxAdapter(child: _returnsSection(t)),
          SliverToBoxAdapter(child: _allClearSection(t)),
          const SliverToBoxAdapter(child: SizedBox(height: 110)),
        ]),
      ),
    );
  }

  Widget _pulseItem({
    required IconData icon,
    required String value,
    required String label,
    required VoidCallback onTap,
    required bool urgent,
    Color? urgentColor,
  }) {
    final c = urgent ? (urgentColor ?? kError) : kGoldLight;
    return Expanded(child: GestureDetector(onTap: onTap,
        child: Column(children: [
          Container(width: 40, height: 40,
              decoration: BoxDecoration(
                  color: urgent
                      ? c.withValues(alpha: 0.25)
                      : Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.withValues(alpha: 0.35))),
              child: Icon(icon, color: c, size: 20)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 22,
              fontWeight: FontWeight.w900, color: urgent ? c : Colors.white,
              letterSpacing: -0.4)),
          Text(label, style: const TextStyle(fontSize: 9,
              fontWeight: FontWeight.w700, color: Color(0xFFB4C6F4),
              letterSpacing: -0.2), maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ])));
  }

  Widget _buildTabletScaffold(dynamic user, String lang,
      String Function(String) t) {
    if (_loading) {
      return const Scaffold(backgroundColor: kBgPage,
        body: Center(
            child: CircularProgressIndicator(color: kNavy, strokeWidth: 2.5)));
    }
    if (_error != null) {
      return Scaffold(backgroundColor: kBgPage, body: _errorView());
    }

    final d = _data!;

    return Scaffold(
      backgroundColor: kBgPage,
      body: RefreshIndicator(
        onRefresh: _load, color: kNavy, strokeWidth: 2.5,
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(child: _mobileHeader(user, lang, t)),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: IntrinsicHeight(child: Row(children: [
              _tabletMetric(
                label: 'Live Birds',
                value: '${_stock.isEmpty ? d.remainingBirds
                    : _stock.fold(0, (s, p) => s + p.availableBirds)}',
                sub: d.stockSurvivalDays != null
                    ? '${d.stockSurvivalDays!.toStringAsFixed(1)} days'
                    : 'No rate data',
                icon: Icons.inventory_2_rounded,
                color: d.stockSurvivalDays != null && d.stockSurvivalDays! < 3
                    ? kError : kSuccess,
                onTap: () => context.push(R.stockDetail),
              ),
              const SizedBox(width: 12),
              _tabletMetric(
                label: 'Revenue Today',
                value: Fmt.amount(d.todayRevenue > 0
                    ? d.todayRevenue : d.todayCollected),
                sub: d.todayRate != null
                    ? '₹${d.todayRate!.toStringAsFixed(0)}/kg'
                    : '—',
                icon: Icons.currency_rupee_rounded,
                color: Colors.blue,
                onTap: () => context.go(R.ledger),
              ),
              const SizedBox(width: 12),
              _tabletMetric(
                label: 'Outstanding',
                value: Fmt.amount(d.totalOutstanding),
                sub: d.overLimitCount > 0
                    ? '${d.overLimitCount} over limit'
                    : '${d.creditUtilisationPct.toStringAsFixed(0)}% credit used',
                icon: Icons.account_balance_wallet_outlined,
                color: d.overLimitCount > 0 ? kError : Colors.orange.shade700,
                onTap: () => context.go(R.ledger),
              ),
            ])),
          )),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _BusinessHealthCard(
              data: d,
              stockValueByProduct: _stockValueByProduct,
              onPnl: () => context.push(R.pnlStatement),
              onCashFlow: () => context.push(R.cashFlowStatement),
            ),
          )),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _OpsBoard(data: d, onNavigate: (r) => context.go(r)),
          )),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 5, child: Column(children: [
                _LiveStockPanel(stock: _stock, data: d),
                const SizedBox(height: 12),
                _NavigatorAgentShift(agents: d.agentStatus,
                    onTap: () => context.go(R.agents)),
              ])),
              const SizedBox(width: 12),
              Expanded(flex: 5, child: Column(children: [
                _CollectionIntelligencePanel(
                    data: d,
                    aging: _dashboardAging,
                    onLedger: () => context.go(R.ledger),
                    onClosure: () => context.go(R.dayClosure)),
                if (_topRetailers.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _TopRetailersToday(
                      retailers: _topRetailers,
                      onViewAll: () => context.go(R.retailers)),
                ],
                if (d.unreadAlerts > 0 || d.remainingBirds < 50) ...[
                  const SizedBox(height: 12),
                  _AlertsPanel(data: d, stock: _stock,
                      onTap: () => context.go(R.alerts)),
                ],
              ])),
            ]),
          )),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(padding: EdgeInsets.only(bottom: 12),
                      child: Row(children: [
                        Icon(Icons.bolt_rounded, color: kGold, size: 18),
                        SizedBox(width: 8),
                        Text('QUICK ACTIONS', style: TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w900, color: kNavy,
                            letterSpacing: 0.6)),
                      ])),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 2.8),
                    itemCount: _allActions(t).length,
                    itemBuilder: (_, i) => _qaBtn(_allActions(t)[i]),
                  ),
                ]),
          )),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final targetTableWidth = math.max(930.0, constraints.maxWidth);
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: targetTableWidth,
                    child: _RecentOrdersTable(
                      orders: _recentOrders,
                      onViewAll: () => context.go(R.orders),
                      onOrder: (id) => context.push(R.orderDetailPath(id)),
                    ),
                  ),
                );
              },
            ),
          )),
        ]),
      ),
    );
  }

  Widget _tabletMetric({
    required String label,
    required String value,
    required String sub,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) => Expanded(child: GestureDetector(onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 80),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border: Border.all(color: color.withValues(alpha: 0.2)),
          boxShadow: kCardShadow,
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Container(width: 48, height: 48,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 24)),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(label, style: const TextStyle(fontSize: 10,
                fontWeight: FontWeight.w700, color: kTextHint,
                letterSpacing: 0.5)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 18,
                fontWeight: FontWeight.w900, color: color,
                letterSpacing: -0.3),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(sub, style: const TextStyle(fontSize: 10, color: kTextHint)),
          ])),
        ]),
      )));

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

  Widget _stockSection(String Function(String) t) {
    final agents = _data?.agentStatus ?? [];
    final totalBirds = _stock.isEmpty ? 0 : _stock.fold(
        0, (s, p) => s + p.availableBirds);
    final inTransit = agents.fold(0, (s, a) => s + a.liveStockBirds);
    final soldToday = _data?.todayDelivered ?? 0;
    final fraction = totalBirds > 0 ? (totalBirds / (totalBirds + soldToday))
        .clamp(0.0, 1.0) : 0.0;
    final survDays = _data?.stockSurvivalDays;
    return Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: GestureDetector(onTap: () => context.push(R.stockDetail),
            child: Container(decoration: BoxDecoration(color: kSurface,
                borderRadius: BorderRadius.circular(kRadiusHero),
                border: Border.all(color: kBorderLight.withValues(alpha: 0.5)),
                boxShadow: kCardShadow),
                padding: const EdgeInsets.all(24),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Icon(
                        Icons.inventory_2_rounded, color: kGold, size: 18),
                    SizedBox(width: 8),
                    Text('LIVE STOCK', style: TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: kNavy,
                        letterSpacing: 0.6)),
                    Spacer(),
                    Text('DETAILS ›', style: TextStyle(fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: kGold,
                        letterSpacing: 0.6))
                  ]),
                  const SizedBox(height: 20),
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    Tooltip(
                      message: 'Total Stock: ${_stock.isEmpty ? 0 : totalBirds} birds\n'
                          'Weight: ${_stock.fold(0.0, (s, p) => s + p.availableKg).toStringAsFixed(2)} Kg\n'
                          'Survival: ${survDays != null ? (survDays < 1 ? "< 1 day" : "${survDays.toStringAsFixed(1)} days") : "—"}',
                      waitDuration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      textStyle: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          height: 1.5,
                          fontWeight: FontWeight.w500),
                      decoration: const BoxDecoration(
                        color: kNavy,
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                      child: SizedBox(width: 140,
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
                                  letterSpacing: 0.8)),
                              const SizedBox(height: 2),
                              Text(
                                  '${_stock.fold(0.0, (s, p) => s + p.availableKg).toStringAsFixed(2)} Kg',
                                  style: const TextStyle(fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: kTextSub)),
                            ]),
                          ])),
                    ),
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

  List<Widget> _buildAlerts(String Function(String) t) {
    final d = _data;
    final out = <Widget>[];
    if (d == null) return out;
    void add(String msg, Color c, IconData icon, {VoidCallback? onTap}) =>
        out.add(_alertTile(msg, c, icon, onTap: onTap));
    if (d.isDayClosed) {
      add(
        'Day is closed. No new records.', Colors.grey, Icons.lock);
    }
    if (d.remainingBirds < 0) {
      add(
        'CRITICAL: Negative stock! Check entries.', kError, Icons.error,
        onTap: () => context.go(R.stock));
    }
    if (d.remainingBirds < 50 && d.stockBirds > 0) {
      add(
        'Low stock: only ${d.remainingBirds} birds remaining', Colors.orange,
        Icons.inventory_outlined, onTap: () => context.go(R.stock));
    }
    if (d.pendingApprovals > 0) {
      add(
        '${d.pendingApprovals} deliveries need approval', Colors.orange,
        Icons.fact_check_outlined, onTap: () => context.go(R.approvals));
    }
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
        // ★ NEW: Stock Point Sale — direct counter/POS sale from in-house
        // stock. Distinct storefront icon (Icons.store_outlined is already
        // used by 'customers' above) and a dedicated green so it reads
        // immediately differently from the orange delivery-workflow tile
        // right beside it.
        _QA(Icons.storefront, t('stock_point_sale'), const Color(0xFF16A34A),
            const Color(0xFFF0FDF4), () => context.push(R.inHouseSale)),
        // Stock Point Management Phase 2 — separate gold accent so it
        // doesn't blend with the green Stock Point Sale tile right above it.
        _QA(Icons.dashboard_outlined, t('inventory_dashboard'), const Color(0xFF8D6E00),
            const Color(0xFFFFF8E1), () => context.push(R.inventoryDashboard)),
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
        _QA(Icons.local_offer_outlined, t('rate'), const Color(0xFF0D9488),
            const Color(0xFFECFDF5), () => context.go(R.pricingHub)),
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

    final rate      = data.todayRate;
    final delta     = data.rateDelta;
    final rateUp    = (delta ?? 0) > 0;
    final rateDown  = (delta ?? 0) < 0;

    final signal = data.tradingSignal;
    final (sigLabel, sigColor, sigIcon) = switch (signal) {
      'buy_urgent' => ('BUY NOW',   _kRed,                    Icons.arrow_upward_rounded),
      'buy_soon'   => ('BUY SOON',  _kOrange,                  Icons.trending_up_rounded),
      'sell_fast'  => ('SELL FAST', _kBlue,                    Icons.bolt_rounded),
      'hold'       => ('HOLD',      _kGreen,                   Icons.check_circle_outline),
      _            => ('NO DATA',   _kText3,                   Icons.help_outline_rounded),
    };

    return PageBreadcrumbsHeader(
      title: '$greeting, ${user?.companyName ?? "Trader"}! 👋',
      subtitle: '$dayStr  •  $timeStr',
      crumbs: const [Crumb('Home', R.dashboard), Crumb('Dashboard')],
      action: Row(mainAxisSize: MainAxisSize.min, children: [
        if (rate != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: rateUp ? _kGreenLt : rateDown ? _kRedLt : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(WebRadius.sm),
              border: Border.all(color: rateUp
                  ? _kGreen.withValues(alpha: 0.3)
                  : rateDown
                  ? _kRed.withValues(alpha: 0.3)
                  : _kBorder),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                rateUp   ? Icons.arrow_upward_rounded
                    : rateDown ? Icons.arrow_downward_rounded
                    : Icons.remove_rounded,
                size: 13,
                color: rateUp ? _kGreen : rateDown ? _kRed : _kText3,
              ),
              const SizedBox(width: 4),
              Text('₹${rate.toStringAsFixed(0)}/kg',
                  style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: rateUp ? _kGreen : rateDown ? _kRed : _kText1,
                  )),
              if (delta != null && delta != 0) ...[
                const SizedBox(width: 3),
                Text('${rateUp ? "+" : ""}${delta.toStringAsFixed(0)}',
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w600,
                        color: rateUp ? _kGreen : _kRed)),
              ],
            ]),
          ),
          const SizedBox(width: 8),
        ],

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: sigColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(WebRadius.sm),
            border: Border.all(color: sigColor.withValues(alpha: 0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(sigIcon, size: 13, color: sigColor),
            const SizedBox(width: 5),
            Text(sigLabel,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                    color: sigColor, letterSpacing: 0.4)),
          ]),
        ),
        const SizedBox(width: 12),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: data.isDayClosed ? _kRedLt : _kGreenLt,
            borderRadius: BorderRadius.circular(WebRadius.sm),
            border: Border.all(
                color: data.isDayClosed
                    ? _kRed.withValues(alpha: 0.3)
                    : _kGreen.withValues(alpha: 0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
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
        WebIconButton(
            icon: Icons.refresh_rounded, onTap: onRefresh, tooltip: 'Refresh'),
      ]),
    );
  }
}

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
        sub: '${_fmt(stock.fold(0, (s, p) => s + p.agentBirds))} with agents',
        icon: Icons.egg_alt_outlined,
        grad: [_kNavBg, _kNavBg],
        trend: null,
      ),
      _MetricDef(
        label: 'Sold Today',
        value: '${data.todayDelivered}',
        sub: '${data.todayDeliveredKgLedger.toStringAsFixed(0)} kg',
        icon: Icons.local_shipping_outlined,
        grad: [_kGold, _kGold],
        trend: null,
      ),
      _MetricDef(
        label: 'Dispatch Pending',
        value: '${data.activeDeliveries}',
        sub: '${data.todayDcWeight.toStringAsFixed(0)} kg on road',
        icon: Icons.local_shipping_rounded,
        grad: [_kIndigo, _kIndigo],
        trend: null,
      ),
      _MetricDef(
        label: 'Collection Pending',
        value: Fmt.amount(data.totalOutstanding),
        sub: '${data.totalRetailers} Customers',
        icon: Icons.account_balance_wallet_outlined,
        grad: [_kGreen, _kGreen],
        trend: null,
      ),
      _MetricDef(
        label: 'Mortality Today',
        value: '${data.todayMortalityBirdsLedger}',
        sub: data.todayMortalityBirdsLedger == 0
            ? '0% of stock' : '${(data.todayMortalityBirdsLedger /
            math.max(totalBirds, 1) * 100).toStringAsFixed(2)}% of stock',
        icon: Icons.warning_amber_outlined,
        grad: [_kRed, _kRed],
        trend: null,
      ),
    ];

    return Row(children: metrics
        .asMap()
        .entries
        .map((e) =>
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: e.key > 0 ? WebSpace.lg : 0),
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
  Widget build(BuildContext context) => WebKpiCard(
        label: def.label,
        value: def.value,
        sub:   def.sub,
        icon:  def.icon,
        color: def.grad.first,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// BUSINESS HEALTH CARD  (Phase 4 UI)
// Answers: Revenue / Purchase Cost / Expense / Mortality Loss / Shrinkage Loss /
// Gross Profit / Net Profit / Outstanding / Supplier Payable / Cash Position
// — all for TODAY. Every figure is read directly from DashboardData, which is
// itself populated from dashboard_summary's v_part3 (a thin wrapper that only
// CALLS get_pnl_statement / get_cash_flow_statement / get_payable_aging).
// No calculation happens in this widget.
// ─────────────────────────────────────────────────────────────────────────────
class _BusinessHealthCard extends StatelessWidget {
  const _BusinessHealthCard({
    required this.data,
    required this.onPnl,
    required this.onCashFlow,
    this.stockValueByProduct = const [],
  });

  final DashboardData data;
  final VoidCallback onPnl;
  final VoidCallback onCashFlow;
  // ★ Current Stock Value by Product — enabled + currently-stocked
  // products only. Every field in each row is read verbatim from
  // get_business_health_by_product_v1; nothing here computes a cost or
  // a value. Empty list (default) simply hides this sub-section — every
  // existing call site of this widget continues to work unchanged.
  final List<Map<String, dynamic>> stockValueByProduct;

  @override
  Widget build(BuildContext context) {
    final d = data;
    final costPending = d.todayLinesCostPending > 0;
    final revenue = d.todayRevenue > 0 ? d.todayRevenue : d.todayCollected;
    final hasPerKg = d.todayCostPerKg != null;

    return Container(
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(color: kBorderLight),
        boxShadow: kCardShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(children: [
            const Icon(Icons.monitor_heart_outlined, color: kGold, size: 16),
            const SizedBox(width: 8),
            const Text('BUSINESS HEALTH — TODAY',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900,
                    color: kNavy, letterSpacing: 0.6)),
            const Spacer(),
            GestureDetector(
              onTap: () async {
                final added = await showTraderExpenseSheet(context);
                if (added) onPnl(); // refresh triggers dashboard reload
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3))),
                child: const Row(children: [
                  Icon(Icons.add, size: 11, color: Colors.orange),
                  SizedBox(width: 3),
                  Text('Expense', style: TextStyle(fontSize: 10,
                      fontWeight: FontWeight.w800, color: Colors.orange)),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onPnl,
              child: const Text('FULL P&L', style: TextStyle(fontSize: 10,
                  fontWeight: FontWeight.w900, color: kGold, letterSpacing: 0.5)),
            ),
          ]),
        ),

        // ── Pending banner ───────────────────────────────────────────────────
        if (costPending)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                const Icon(Icons.info_outline, size: 13, color: Colors.orange),
                const SizedBox(width: 6),
                Expanded(child: Text(
                    '${d.todayLinesCostPending} line${d.todayLinesCostPending == 1 ? '' : 's'} '
                        'not yet costed — Gross/Net Profit pending',
                    style: const TextStyle(fontSize: 10, color: Colors.orange,
                        fontWeight: FontWeight.w600))),
              ]),
            ),
          ),

        // ── Row 1: Revenue & Purchase Cost ───────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(children: [
            Row(children: [
              Expanded(child: _healthTile('Revenue', Fmt.amount(revenue),
                  kSuccess, Icons.trending_up_outlined)),
              const SizedBox(width: 8),
              Expanded(child: _healthTile('Purchase Cost',
                  d.todayPurchaseCostActual == null ? 'Pending'
                      : Fmt.amount(d.todayPurchaseCostActual!),
                  Colors.blue, Icons.shopping_cart_outlined)),
            ]),
            const SizedBox(height: 8),

            // ── Row 2: Outstanding & Supplier Payable ─────────────────────
            Row(children: [
              Expanded(child: _healthTile('Outstanding', Fmt.amount(d.totalOutstanding),
                  Colors.deepOrange, Icons.account_balance_wallet_outlined)),
              const SizedBox(width: 8),
              Expanded(child: _healthTile('Supplier Payable',
                  Fmt.amount(d.totalSupplierPayable), Colors.brown,
                  Icons.agriculture_outlined)),
            ]),
            const SizedBox(height: 8),

            // ── Row 3: Expenses (with breakdown) & Cash ───────────────────
            Row(children: [
              Expanded(child: _expenseTile(d)),
              const SizedBox(width: 8),
              Expanded(child: GestureDetector(
                onTap: onCashFlow,
                child: _healthTile('Cash Position',
                    Fmt.amount(d.todayCashIn - d.todayCashOut),
                    (d.todayCashIn - d.todayCashOut) >= 0 ? kSuccess : kError,
                    Icons.water_drop_outlined),
              )),
            ]),
            const SizedBox(height: 8),

            // ── Row 4: Loss tiles ─────────────────────────────────────────
            Row(children: [
              Expanded(child: _healthTile('Mortality Loss',
                  Fmt.amount(d.todayMortalityLossAmount), kError,
                  Icons.health_and_safety_outlined)),
              const SizedBox(width: 8),
              Expanded(child: _healthTile('Transit Shrinkage',
                  Fmt.amount(d.todayShrinkageLossAmount),
                  const Color(0xFF6A1B9A), Icons.compress_outlined)),
            ]),
            if (d.todayUnexplainedLossAmount > 0) ...[
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _healthTile('Weight Variance',
                    Fmt.amount(d.todayUnexplainedLossAmount),
                    Colors.deepPurple, Icons.balance_outlined)),
                const SizedBox(width: 8),
                Expanded(child: _healthTile('Total Loss ₹',
                    Fmt.amount(d.todayTotalLossAmount), kError,
                    Icons.crisis_alert_outlined)),
              ]),
            ],
          ]),
        ),

        // ── Gross / Net Profit row ───────────────────────────────────────────
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: d.todayNetProfit == null
                ? Colors.orange.withValues(alpha: 0.08)
                : d.todayNetProfit! >= 0
                ? kSuccess.withValues(alpha: 0.08)
                : kError.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(kRadiusInner),
          ),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Gross Profit',
                  style: TextStyle(fontSize: 10,
                      color: d.todayGrossProfit == null ? Colors.orange.shade800 : kTextSub)),
              Text(d.todayGrossProfit == null ? 'Pending' : Fmt.amount(d.todayGrossProfit!),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
                      color: d.todayGrossProfit == null ? Colors.orange.shade800 : kTextMain)),
              if (d.todayGrossMarginPct != null)
                Text('${d.todayGrossMarginPct!.toStringAsFixed(1)}% margin',
                    style: const TextStyle(fontSize: 9, color: kTextSub)),
            ])),
            Container(width: 1, height: 40, color: kBorderLight),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Net Profit', style: TextStyle(fontSize: 10,
                  color: d.todayNetProfit == null ? Colors.orange.shade800
                      : d.todayNetProfit! >= 0 ? kSuccess : kError)),
              Text(d.todayNetProfit == null ? 'Pending' : Fmt.amount(d.todayNetProfit!),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                      color: d.todayNetProfit == null ? Colors.orange.shade800
                          : d.todayNetProfit! >= 0 ? kSuccess : kError)),
              if (d.todayNetMarginPct != null)
                Text('${d.todayNetMarginPct!.toStringAsFixed(1)}% net margin',
                    style: TextStyle(fontSize: 9,
                        color: d.todayNetMarginPct! >= 0 ? kSuccess : kError)),
            ])),
          ]),
        ),

        // ── Per-KG strip (only when batch costing is available today) ────────
        if (hasPerKg)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kNavy.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(kRadiusInner),
              border: Border.all(color: kNavy.withValues(alpha: 0.08)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.straighten_outlined, size: 11, color: kNavy),
                SizedBox(width: 4),
                Text('PER KG  —  Today\'s Averages',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900,
                        color: kNavy, letterSpacing: 0.5)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                _kgPill('Cost/kg',    d.todayCostPerKg,           Colors.blue),
                _kgPill('Sell/kg',    d.todaySellingPricePerKg,   kSuccess),
                _kgPill('Profit/kg',  d.todayNetProfitPerKg,
                    (d.todayNetProfitPerKg ?? 0) >= 0 ? kSuccess : kError),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                _kgPill('Expense/kg', d.todayExpensePerKg,        Colors.orange),
                _kgPill('Loss/kg',    d.todayLossPerKg,           kError),
                _kgPill('G.Margin',
                    d.todayGrossMarginPct != null
                        ? d.todayGrossMarginPct! / 100 : null,
                    Colors.purple, suffix: '%',
                    format: (v) => '${(v * 100).toStringAsFixed(1)}%'),
              ]),
            ]),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(kRadiusInner),
                  border: Border.all(color: Colors.grey.shade200)),
              child: const Row(children: [
                Icon(Icons.straighten_outlined, size: 12, color: kTextSub),
                SizedBox(width: 6),
                Text('Per-KG metrics available after first batch is approved today',
                    style: TextStyle(fontSize: 10, color: kTextSub)),
              ]),
            ),
          ),

        // ── Current Stock Value by Product (enabled + stocked only) ──────────
        // Purely rendered from get_business_health_by_product_v1 — no
        // calculation happens here. Hidden entirely when there's nothing
        // currently stocked, rather than showing an empty section.
        if (stockValueByProduct.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(children: [
              Icon(Icons.inventory_2_outlined, size: 11, color: kNavy),
              SizedBox(width: 4),
              Text('CURRENT STOCK VALUE  —  By Product',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900,
                      color: kNavy, letterSpacing: 0.5)),
            ]),
          ),
          ...stockValueByProduct.map((r) {
            final kg = (r['current_stock_kg'] as num?)?.toDouble() ?? 0;
            final costPerKg = (r['cost_per_kg'] as num?)?.toDouble();
            final stockValue = (r['current_stock_value'] as num?)?.toDouble();
            final marketRate = (r['market_rate_per_kg'] as num?)?.toDouble();
            final marketValue = (r['market_value'] as num?)?.toDouble();
            final isPending = r['is_pending_cost'] == true;
            return Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isPending ? Colors.orange.withValues(alpha: 0.05) : kNavy.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(kRadiusInner),
                border: Border.all(color: isPending ? Colors.orange.withValues(alpha: 0.2) : kNavy.withValues(alpha: 0.08)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(r['product_name'] as String? ?? '—',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800))),
                  Text('${kg.toStringAsFixed(0)} kg', style: const TextStyle(fontSize: 11, color: kTextSub)),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  _kgPill('Cost/kg', costPerKg, isPending ? Colors.orange : Colors.blue,
                      format: (v) => '₹${v.toStringAsFixed(0)}'),
                  _kgPill('Stock Value', stockValue, isPending ? Colors.orange : kSuccess,
                      format: (v) => Fmt.amount(v)),
                  _kgPill('Mkt Value', marketValue, kNavy,
                      format: (v) => Fmt.amount(v)),
                ]),
                if (marketRate != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text("Today's Market Rate: ₹${marketRate.toStringAsFixed(0)}/kg",
                        style: const TextStyle(fontSize: 9.5, color: kTextSub)),
                  ),
              ]),
            );
          }),
        ],
      ]),
    );
  }

  // ── Expense tile with breakdown ────────────────────────────────────────────
  Widget _expenseTile(DashboardData d) {
    final hasBreakdown = d.todayTripExpenses + d.todayTraderExpenses + d.todayFixedExpenses > 0;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(kRadiusInner)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.receipt_long_outlined, size: 14, color: Colors.orange),
        const SizedBox(height: 4),
        Text(Fmt.amount(d.todayExpenseTotal),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900,
                color: Colors.orange), maxLines: 1, overflow: TextOverflow.ellipsis),
        const Text('Total Expenses',
            style: TextStyle(fontSize: 9, color: kTextSub)),
        if (hasBreakdown) ...[
          const SizedBox(height: 4),
          if (d.todayTripExpenses > 0)
            Text('Agent: ${Fmt.amount(d.todayTripExpenses)}',
                style: const TextStyle(fontSize: 8, color: kTextSub)),
          if (d.todayTraderExpenses > 0)
            Text('Trader: ${Fmt.amount(d.todayTraderExpenses)}',
                style: const TextStyle(fontSize: 8, color: Colors.orange)),
          if (d.todayFixedExpenses > 0)
            Text('Fixed: ${Fmt.amount(d.todayFixedExpenses)}',
                style: const TextStyle(fontSize: 8, color: kTextSub)),
        ],
      ]),
    );
  }

  // ── Per-kg pill ────────────────────────────────────────────────────────────
  Widget _kgPill(String label, double? value, Color c,
      {String suffix = '/kg', String Function(double)? format}) =>
      Expanded(child: Container(
        margin: const EdgeInsets.only(right: 5),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
            color: c.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: c.withValues(alpha: 0.2))),
        child: Column(children: [
          Text(value == null ? '—'
              : format != null ? format(value)
              : '${Fmt.amount(value)}$suffix',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: c),
              textAlign: TextAlign.center),
          Text(label, style: const TextStyle(fontSize: 8, color: kTextSub),
              textAlign: TextAlign.center),
        ]),
      ));

  Widget _healthTile(String label, String value, Color c, IconData icon) => Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(kRadiusInner)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 14, color: c),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: c),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(label, style: const TextStyle(fontSize: 9, color: kTextSub),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ]));
}

// ─────────────────────────────────────────────────────────────────────────────
// BUSINESS HEALTH — desktop/web layout.
// Same figures and actions as _BusinessHealthCard (mobile keeps that one);
// only the layout and colours differ. Reads DashboardData verbatim.
// ─────────────────────────────────────────────────────────────────────────────
class _BusinessHealthWeb extends StatelessWidget {
  const _BusinessHealthWeb({
    required this.data,
    required this.onPnl,
    required this.onCashFlow,
    this.stockValueByProduct = const [],
  });

  final DashboardData data;
  final VoidCallback onPnl;
  final VoidCallback onCashFlow;
  final List<Map<String, dynamic>> stockValueByProduct;

  @override
  Widget build(BuildContext context) {
    final d = data;
    final costPending = d.todayLinesCostPending > 0;
    final revenue = d.todayRevenue > 0 ? d.todayRevenue : d.todayCollected;
    final cash = d.todayCashIn - d.todayCashOut;

    final tiles = <Widget>[
      _tile('Revenue', Fmt.amount(revenue),
          Icons.trending_up_rounded, _kGreen),
      _tile('Purchase Cost',
          d.todayPurchaseCostActual == null
              ? 'Pending' : Fmt.amount(d.todayPurchaseCostActual!),
          Icons.shopping_cart_outlined, _kBlue,
          pending: d.todayPurchaseCostActual == null),
      _tile('Outstanding', Fmt.amount(d.totalOutstanding),
          Icons.account_balance_wallet_outlined, _kOrange),
      _tile('Supplier Payable', Fmt.amount(d.totalSupplierPayable),
          Icons.agriculture_outlined, _kGold),
      _expenseTile(d),
      _tile('Cash Position', Fmt.amount(cash),
          Icons.water_drop_outlined, cash >= 0 ? _kGreen : _kRed,
          valueColor: cash >= 0 ? _kGreen : _kRed, onTap: onCashFlow),
      _tile('Mortality Loss', Fmt.amount(d.todayMortalityLossAmount),
          Icons.health_and_safety_outlined, _kRed),
      _tile('Transit Shrinkage', Fmt.amount(d.todayShrinkageLossAmount),
          Icons.compress_rounded, _kIndigo),
      if (d.todayUnexplainedLossAmount > 0) ...[
        _tile('Weight Variance', Fmt.amount(d.todayUnexplainedLossAmount),
            Icons.balance_outlined, _kIndigo),
        _tile('Total Loss ₹', Fmt.amount(d.todayTotalLossAmount),
            Icons.crisis_alert_outlined, _kRed, valueColor: _kRed),
      ],
    ];

    // 4 tiles per row, each row equal height
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 4) {
      final slice = tiles.sublist(i, (i + 4).clamp(0, tiles.length));
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 12));
      rows.add(IntrinsicHeight(child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var j = 0; j < 4; j++) ...[
            if (j > 0) const SizedBox(width: 12),
            Expanded(child: j < slice.length ? slice[j] : const SizedBox()),
          ],
        ],
      )));
    }

    return Container(
      decoration: WebDecor.card(),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ── Header ────────────────────────────────────────────────────────
        WebCardHeader(
          title: 'Business Health — Today',
          subtitle: DateFormat('EEEE, d MMM y').format(DateTime.now()),
          icon: Icons.monitor_heart_outlined,
          action: Row(mainAxisSize: MainAxisSize.min, children: [
            WebButton(
              label: 'Expense',
              icon: Icons.add_rounded,
              outlined: true,
              color: _kOrange,
              onPressed: () async {
                final added = await showTraderExpenseSheet(context);
                if (added) onPnl(); // refresh triggers dashboard reload
              },
            ),
            const SizedBox(width: 8),
            WebButton(
              label: 'Full P&L',
              icon: Icons.arrow_forward_rounded,
              onPressed: onPnl,
            ),
          ]),
        ),
        const Divider(height: 1, color: _kBorder),

        Padding(
          padding: const EdgeInsets.all(WebSpace.xl),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // ── Pending banner ────────────────────────────────────────────
            if (costPending) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: WebColors.warningBg,
                  borderRadius: BorderRadius.circular(WebRadius.sm),
                  border: Border.all(color: _kOrange.withValues(alpha: 0.25)),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 16, color: _kOrange),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                      '${d.todayLinesCostPending} line${d.todayLinesCostPending == 1 ? '' : 's'} '
                          'not yet costed — Gross/Net Profit pending',
                      style: const TextStyle(fontSize: 12.5,
                          color: _kOrange, fontWeight: FontWeight.w600))),
                ]),
              ),
              const SizedBox(height: WebSpace.lg),
            ],

            // ── Tiles (left) + profit panel (right) ───────────────────────
            IntrinsicHeight(child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 8, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: rows)),
                const SizedBox(width: WebSpace.lg),
                Expanded(flex: 4, child: _profitPanel(d)),
              ],
            )),

            // ── Per-KG strip ──────────────────────────────────────────────
            const SizedBox(height: WebSpace.lg),
            _perKg(d),

            // ── Current Stock Value by Product ────────────────────────────
            if (stockValueByProduct.isNotEmpty) ...[
              const SizedBox(height: WebSpace.lg),
              _stockValueTable(),
            ],
          ]),
        ),
      ]),
    );
  }

  // ── Metric tile ────────────────────────────────────────────────────────────
  Widget _tile(String label, String value, IconData icon, Color c,
      {Color? valueColor, bool pending = false, VoidCallback? onTap,
        Widget? extra}) {
    final tile = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          WebIconTile(icon: icon, color: c, size: 32),
          const Spacer(),
          if (onTap != null)
            const Icon(Icons.arrow_outward_rounded, size: 14, color: _kText3),
        ]),
        const SizedBox(height: 10),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: pending ? _kOrange : valueColor ?? _kText1)),
        const SizedBox(height: 2),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: _kText2,
                fontWeight: FontWeight.w500)),
        ?extra,
      ]),
    );
    if (onTap == null) return tile;
    return MouseRegion(cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: onTap, child: tile));
  }

  Widget _expenseTile(DashboardData d) {
    final parts = <(String, double)>[
      if (d.todayTripExpenses > 0) ('Agent', d.todayTripExpenses),
      if (d.todayTraderExpenses > 0) ('Trader', d.todayTraderExpenses),
      if (d.todayFixedExpenses > 0) ('Fixed', d.todayFixedExpenses),
    ];
    return _tile('Total Expenses', Fmt.amount(d.todayExpenseTotal),
        Icons.receipt_long_outlined, _kOrange,
        extra: parts.isEmpty ? null : Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(spacing: 6, runSpacing: 4, children: [
            for (final p in parts)
              Text('${p.$1}: ${Fmt.amount(p.$2)}',
                  style: const TextStyle(fontSize: 11, color: _kText3)),
          ]),
        ));
  }

  // ── Profit panel (navy brand card) ─────────────────────────────────────────
  Widget _profitPanel(DashboardData d) {
    final net = d.todayNetProfit;
    final netColor = net == null ? WebColors.goldLight
        : net >= 0 ? const Color(0xFF6EE7B7) : const Color(0xFFFCA5A5);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [WebColors.navy, WebColors.navyMid],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Net Profit', style: TextStyle(fontSize: 12.5,
              color: Colors.white70, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(net == null ? 'Pending' : Fmt.amount(net),
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800,
                  color: netColor, letterSpacing: -0.6)),
          if (d.todayNetMarginPct != null) ...[
            const SizedBox(height: 4),
            Text('${d.todayNetMarginPct!.toStringAsFixed(1)}% net margin',
                style: TextStyle(fontSize: 12, color: netColor,
                    fontWeight: FontWeight.w600)),
          ],
        ]),
        const SizedBox(height: 16),
        Container(height: 1, color: Colors.white.withValues(alpha: 0.12)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Gross Profit', style: TextStyle(fontSize: 12,
                color: WebColors.sideText, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(d.todayGrossProfit == null
                ? 'Pending' : Fmt.amount(d.todayGrossProfit!),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                    color: d.todayGrossProfit == null
                        ? WebColors.goldLight : Colors.white)),
          ])),
          if (d.todayGrossMarginPct != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: WebColors.gold.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(WebRadius.label),
              ),
              child: Text('${d.todayGrossMarginPct!.toStringAsFixed(1)}% margin',
                  style: const TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: WebColors.goldLight)),
            ),
        ]),
      ]),
    );
  }

  // ── Per-KG strip ───────────────────────────────────────────────────────────
  Widget _perKg(DashboardData d) {
    if (d.todayCostPerKg == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: WebDecor.inset(),
        child: const Row(children: [
          Icon(Icons.straighten_rounded, size: 16, color: _kText3),
          SizedBox(width: 8),
          Text('Per-KG metrics available after first batch is approved today',
              style: TextStyle(fontSize: 12.5, color: _kText2)),
        ]),
      );
    }
    final profitKg = d.todayNetProfitPerKg ?? 0;
    final items = <(String, String, Color)>[
      ('Cost/kg', _perKgFmt(d.todayCostPerKg), _kBlue),
      ('Sell/kg', _perKgFmt(d.todaySellingPricePerKg), _kGreen),
      ('Profit/kg', _perKgFmt(d.todayNetProfitPerKg),
          profitKg >= 0 ? _kGreen : _kRed),
      ('Expense/kg', _perKgFmt(d.todayExpensePerKg), _kOrange),
      ('Loss/kg', _perKgFmt(d.todayLossPerKg), _kRed),
      ('G.Margin', d.todayGrossMarginPct == null ? '—'
          : '${d.todayGrossMarginPct!.toStringAsFixed(1)}%', _kGold),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: WebDecor.inset(),
      child: Row(children: [
        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.straighten_rounded, size: 15, color: _kBlue),
            SizedBox(width: 6),
            Text('Per KG', style: TextStyle(fontSize: 13,
                fontWeight: FontWeight.w800, color: _kText1)),
          ]),
          SizedBox(height: 2),
          Text("Today's averages", style: TextStyle(fontSize: 11.5,
              color: _kText3)),
        ]),
        const SizedBox(width: 20),
        for (final it in items)
          Expanded(child: Container(
            margin: const EdgeInsets.only(left: 8),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: _kPanel,
              borderRadius: BorderRadius.circular(WebRadius.sm),
              border: Border.all(color: _kBorder),
            ),
            child: Column(children: [
              Text(it.$2, style: TextStyle(fontSize: 14,
                  fontWeight: FontWeight.w800, color: it.$3)),
              const SizedBox(height: 2),
              Text(it.$1, style: const TextStyle(fontSize: 11,
                  color: _kText3)),
            ]),
          )),
      ]),
    );
  }

  String _perKgFmt(double? v) => v == null ? '—' : '${Fmt.amount(v)}/kg';

  // ── Current stock value by product ─────────────────────────────────────────
  Widget _stockValueTable() {
    const head = TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
        color: _kText2);
    Widget cell(String t, {TextStyle? s, TextAlign a = TextAlign.right,
      int flex = 2}) => Expanded(flex: flex, child: Text(t, textAlign: a,
        maxLines: 1, overflow: TextOverflow.ellipsis,
        style: s ?? const TextStyle(fontSize: 13, color: _kText1)));

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Container(
          color: WebColors.surfaceAlt,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            const Icon(Icons.inventory_2_outlined, size: 15, color: _kBlue),
            const SizedBox(width: 8),
            const Expanded(flex: 3, child: Text(
                'Current Stock Value — By Product', style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800,
                    color: _kText1))),
            cell('Stock', s: head),
            cell('Cost/kg', s: head),
            cell('Stock Value', s: head),
            cell('Mkt Rate', s: head),
            cell('Mkt Value', s: head),
          ]),
        ),
        for (final r in stockValueByProduct) () {
          final kg = (r['current_stock_kg'] as num?)?.toDouble() ?? 0;
          final costPerKg = (r['cost_per_kg'] as num?)?.toDouble();
          final stockValue = (r['current_stock_value'] as num?)?.toDouble();
          final marketRate = (r['market_rate_per_kg'] as num?)?.toDouble();
          final marketValue = (r['market_value'] as num?)?.toDouble();
          final isPending = r['is_pending_cost'] == true;
          final pendStyle = TextStyle(fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isPending ? _kOrange : _kText1);
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: WebColors.divider))),
            child: Row(children: [
              const SizedBox(width: 23),
              Expanded(flex: 3, child: Row(children: [
                Flexible(child: Text(r['product_name'] as String? ?? '—',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w700, color: _kText1))),
                if (isPending) ...[
                  const SizedBox(width: 8),
                  const WebLabel('Cost pending', color: _kOrange),
                ],
              ])),
              cell('${kg.toStringAsFixed(0)} kg',
                  s: const TextStyle(fontSize: 13, color: _kText2)),
              cell(costPerKg == null ? '—' : '₹${costPerKg.toStringAsFixed(0)}',
                  s: pendStyle),
              cell(stockValue == null ? '—' : Fmt.amount(stockValue),
                  s: pendStyle),
              cell(marketRate == null
                  ? '—' : '₹${marketRate.toStringAsFixed(0)}/kg',
                  s: const TextStyle(fontSize: 13, color: _kText2)),
              cell(marketValue == null ? '—' : Fmt.amount(marketValue),
                  s: const TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w700, color: _kBlue)),
            ]),
          );
        }(),
      ]),
    );
  }
}

class _OpsBoard extends StatelessWidget {
  const _OpsBoard({required this.data, required this.onNavigate});

  final DashboardData data;
  final void Function(String) onNavigate;

  @override
  Widget build(BuildContext context) {
    final cols = [
      _OpsCol('New Orders', data.pendingOrders, _kBlue,
          Icons.shopping_cart_outlined, R.orders),
      _OpsCol('Approval Pending', data.pendingApprovals, _kGold,
          Icons.verified_outlined, R.approvals),
      _OpsCol('Dispatch Pending', data.activeDeliveries, _kIndigo,
          Icons.local_shipping_outlined, R.dispatch),
      _OpsCol('Delivered Today', data.todayDelivered, _kGreen,
          Icons.check_circle_outline, R.approvals),
      _OpsCol('Delayed >3h',
          data.delayedDeliveries,
          data.delayedDeliveries > 0 ? _kRed : _kText3,
          Icons.timer_off_outlined,
          R.dispatch),
    ];

    return Container(
      decoration: BoxDecoration(
        color: _kPanel,
        borderRadius: BorderRadius.circular(WebRadius.card),
        border: Border.all(color: _kBorder),
        boxShadow: _kShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(children: [
            const Text('Operations Board', style: WebText.cardTitle),
            const Spacer(),
            Text(DateFormat('d MMM y').format(DateTime.now()),
                style: const TextStyle(fontSize: 11, color: _kText3)),
          ]),
        ),
        const Divider(height: 1, color: _kBorder),

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
            WebIconTile(icon: col.icon, color: col.color, size: 44),
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
                          fontSize: 24, fontWeight: FontWeight.w800,
                          color: col.count > 0 ? _kText1 : _kText3,
                          letterSpacing: -0.5)),
                ])),
            Icon(Icons.chevron_right_rounded, size: 18,
                color: col.color.withValues(alpha: 0.6)),
          ]),
        ),
      );
}

class _HoverBadge extends StatelessWidget {
  const _HoverBadge({
    required this.date,
    required this.revenue,
    required this.kg,
  });

  final DateTime? date;
  final double revenue, kg;

  @override
  Widget build(BuildContext context) {
    final dStr = date != null ? DateFormat('d MMM: ').format(date!) : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _kBlue.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(dStr,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _kText1)),
          Text(Fmt.amount(revenue),
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _kBlue)),
          const Text('  •  ',
              style: TextStyle(fontSize: 11, color: _kText3)),
          Text('${NumberFormat('#,##,##0.00').format(kg)} kg',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _kGold)),
        ],
      ),
    );
  }
}

class _RevenueTrendPanel extends StatefulWidget {
  const _RevenueTrendPanel({required this.data, required this.trend});

  final DashboardData data;
  final List<Map<String, dynamic>> trend;

  @override
  State<_RevenueTrendPanel> createState() => _RevenueTrendPanelState();
}

class _RevenueTrendPanelState extends State<_RevenueTrendPanel> {
  int? _hoveredIndex;
  final GlobalKey _chartKey = GlobalKey();

  void _handleHover(Offset localPos, int count) {
    if (count <= 0) return;
    final box = _chartKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final width = box.size.width;
    const leftPad = 54.0;
    const rightPad = 14.0;
    final plotW = width - leftPad - rightPad;
    if (plotW <= 0) return;

    int idx;
    if (count == 1) {
      idx = 0;
    } else {
      final progress = ((localPos.dx - leftPad) / plotW).clamp(0.0, 1.0);
      idx = (progress * (count - 1)).round().clamp(0, count - 1);
    }

    if (_hoveredIndex != idx) {
      setState(() => _hoveredIndex = idx);
    }
  }

  void _clearHover() {
    if (_hoveredIndex != null) {
      setState(() => _hoveredIndex = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ── Parse live 7-day series (day_date, revenue, kg_delivered) ────────────
    final revenueList = <double>[];
    final kgList = <double>[];
    final dateList = <DateTime?>[];
    for (final row in widget.trend) {
      revenueList.add((row['revenue'] as num?)?.toDouble() ?? 0.0);
      kgList.add((row['kg_delivered'] as num?)?.toDouble() ?? 0.0);
      dateList.add(DateTime.tryParse(row['day_date'] as String? ?? ''));
    }
    final hasData = widget.trend.isNotEmpty &&
        (revenueList.any((v) => v > 0) || kgList.any((v) => v > 0));

    final maxRev = revenueList.isEmpty
        ? 0.0
        : revenueList.reduce((a, b) => a > b ? a : b);
    final maxKg = kgList.isEmpty ? 0.0 : kgList.reduce((a, b) => a > b ? a : b);
    final revFractions =
        revenueList.map((v) => maxRev > 0 ? v / maxRev : 0.0).toList();
    final kgFractions =
        kgList.map((v) => maxKg > 0 ? v / maxKg : 0.0).toList();

    // ── Y-axis labels: real amounts, plain rupee formatting (no K/L) ─────────
    const tickCount = 5;
    final yAxisLabels = List.generate(tickCount, (i) {
      final v = maxRev * (tickCount - 1 - i) / (tickCount - 1);
      return v <= 0 ? '₹0' : Fmt.amount(v);
    });

    final safeHoverIndex = (_hoveredIndex != null &&
            _hoveredIndex! < revenueList.length)
        ? _hoveredIndex
        : null;

    return Container(
      decoration: BoxDecoration(
        color: _kPanel,
        borderRadius: BorderRadius.circular(WebRadius.card),
        border: Border.all(color: _kBorder),
        boxShadow: _kShadow,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Sales & Revenue Trend', style: WebText.cardTitle),
          const Spacer(),
          if (safeHoverIndex != null) ...[
            _HoverBadge(
              date: dateList[safeHoverIndex],
              revenue: revenueList[safeHoverIndex],
              kg: kgList[safeHoverIndex],
            ),
            const SizedBox(width: 8),
          ],
          const _ChipFilter('Last 7 Days'),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          const _Legend(color: _kBlue, label: 'Revenue (₹)'),
          const SizedBox(width: 16),
          const _Legend(color: _kGold, label: 'Sold (kg)'),
          const Spacer(),
          if (hasData)
            const Text(
              'Hover over graph to view values',
              style: TextStyle(
                fontSize: 10,
                color: _kText3,
                fontStyle: FontStyle.italic,
              ),
            ),
        ]),
        const SizedBox(height: 16),
        if (!hasData)
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 160),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kBorder)),
              child: const Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.show_chart_rounded, size: 22, color: _kText3),
                SizedBox(height: 6),
                Text('No sales recorded in the last 7 days',
                    style: TextStyle(
                        fontSize: 12,
                        color: _kText3,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          )
        else
          // Grows to fill the card when its row is taller than the chart
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 160),
              child: MouseRegion(
                key: _chartKey,
                cursor: SystemMouseCursors.precise,
                onHover: (e) =>
                    _handleHover(e.localPosition, revenueList.length),
                onExit: (_) => _clearHover(),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (e) =>
                      _handleHover(e.localPosition, revenueList.length),
                  onHorizontalDragUpdate: (e) =>
                      _handleHover(e.localPosition, revenueList.length),
                  onHorizontalDragEnd: (_) => _clearHover(),
                  onTapCancel: () => _clearHover(),
                  child: CustomPaint(
                    size: const Size(double.infinity, 160),
                    painter: _AreaChartPainter(
                      primaryColor: _kBlue,
                      secondaryColor: _kGold,
                      revenueFractions: revFractions,
                      kgFractions: kgFractions,
                      revenueList: revenueList,
                      kgList: kgList,
                      dateList: dateList,
                      yAxisLabels: yAxisLabels,
                      hoveredIndex: safeHoverIndex,
                    ),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kBorder)),
          child: Row(children: [
            _MiniStat(
                'Today\'s Revenue', Fmt.amount(widget.data.todayCollected), _kBlue),
            _Divider(),
            _MiniStat('Cash Collected',
                Fmt.amount(widget.data.todayCashCollected), _kGreen),
            _Divider(),
            _MiniStat(
                'UPI Collected', Fmt.amount(widget.data.todayUpiCollected), _kIndigo),
            _Divider(),
            _MiniStat('Outstanding',
                Fmt.amount(widget.data.totalOutstanding), _kOrange),
          ]),
        ),
      ]),
    );
  }
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
        child: Text(label, style: const TextStyle(fontSize: 11, color: _kText2,
            fontWeight: FontWeight.w500)),
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
  const _AreaChartPainter({
    required this.primaryColor,
    required this.secondaryColor,
    required this.revenueFractions,
    required this.kgFractions,
    required this.revenueList,
    required this.kgList,
    required this.dateList,
    required this.yAxisLabels,
    this.hoveredIndex,
  });

  final Color primaryColor, secondaryColor;
  final List<double> revenueFractions;
  final List<double> kgFractions;
  final List<double> revenueList;
  final List<double> kgList;
  final List<DateTime?> dateList;
  final List<String> yAxisLabels;
  final int? hoveredIndex;

  static const double _kLeftPad = 54.0;
  static const double _kRightPad = 14.0;
  static const double _kTopPad = 14.0;
  static const double _kBottomPad = 26.0;

  double _getX(int i, int count, double plotW) {
    if (count <= 1) return _kLeftPad + plotW * 0.5;
    return _kLeftPad + plotW * i / (count - 1);
  }

  double _getY(double fraction, double plotH) {
    return _kTopPad + plotH * (1.0 - fraction) * 0.86 + plotH * 0.07;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plotW = math.max(0.0, size.width - _kLeftPad - _kRightPad);
    final plotH = math.max(0.0, size.height - _kTopPad - _kBottomPad);
    final count = revenueFractions.length;

    // ── 1. Horizontal grid lines & Y-axis labels ─────────────────────────
    final gridPaint = Paint()
      ..color = const Color(0xFFF1F5F9)
      ..strokeWidth = 1.0;
    final tp = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 0; i < yAxisLabels.length; i++) {
      final yTick = _kTopPad + (yAxisLabels.length > 1
          ? plotH * i / (yAxisLabels.length - 1)
          : 0.0);
      canvas.drawLine(
        Offset(_kLeftPad, yTick),
        Offset(_kLeftPad + plotW, yTick),
        gridPaint,
      );

      tp.text = TextSpan(
        text: yAxisLabels[i],
        style: const TextStyle(
          fontSize: 8.5,
          color: _kText3,
          fontWeight: FontWeight.w500,
        ),
      );
      tp.layout();
      tp.paint(canvas, Offset(_kLeftPad - 8 - tp.width, yTick - tp.height / 2));
    }

    if (count == 0) return;

    // ── 2. Revenue area gradient fill & line ─────────────────────────────
    final areaPath = Path();
    final revPath = Path();

    for (int i = 0; i < count; i++) {
      final x = _getX(i, count, plotW);
      final y = _getY(revenueFractions[i], plotH);
      if (i == 0) {
        areaPath.moveTo(x, y);
        revPath.moveTo(x, y);
      } else {
        areaPath.lineTo(x, y);
        revPath.lineTo(x, y);
      }
    }

    final lastX = _getX(count - 1, count, plotW);
    final firstX = _getX(0, count, plotW);
    areaPath.lineTo(lastX, _kTopPad + plotH);
    areaPath.lineTo(firstX, _kTopPad + plotH);
    areaPath.close();

    final areaPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          primaryColor.withValues(alpha: 0.18),
          primaryColor.withValues(alpha: 0.01),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(_kLeftPad, _kTopPad, plotW, plotH))
      ..style = PaintingStyle.fill;
    canvas.drawPath(areaPath, areaPaint);

    final revLinePaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(revPath, revLinePaint);

    // ── 3. Sold (KG) line ────────────────────────────────────────────────
    if (kgFractions.isNotEmpty) {
      final kgCount = kgFractions.length;
      final kgPath = Path();
      for (int i = 0; i < kgCount; i++) {
        final x = _getX(i, kgCount, plotW);
        final y = _getY(kgFractions[i], plotH);
        if (i == 0) {
          kgPath.moveTo(x, y);
        } else {
          kgPath.lineTo(x, y);
        }
      }
      final kgLinePaint = Paint()
        ..color = secondaryColor
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(kgPath, kgLinePaint);
    }

    // ── 4. Regular data point dots (unhovered) ───────────────────────────
    final revDotPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;
    final kgDotPaint = Paint()
      ..color = secondaryColor
      ..style = PaintingStyle.fill;

    for (int i = 0; i < count; i++) {
      if (i == hoveredIndex) continue;
      final x = _getX(i, count, plotW);
      final ry = _getY(revenueFractions[i], plotH);
      canvas.drawCircle(Offset(x, ry), 2.5, revDotPaint);

      if (i < kgFractions.length) {
        final ky = _getY(kgFractions[i], plotH);
        canvas.drawCircle(Offset(x, ky), 2.5, kgDotPaint);
      }
    }

    // ── 5. Date labels at the bottom ─────────────────────────────────────
    for (int i = 0; i < count; i++) {
      final x = _getX(i, count, plotW);
      final dt = (i < dateList.length) ? dateList[i] : null;
      final dateText = dt != null ? DateFormat('d MMM').format(dt) : '—';
      final isHovered = (i == hoveredIndex);

      tp.text = TextSpan(
        text: dateText,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: isHovered ? FontWeight.w700 : FontWeight.w500,
          color: isHovered ? _kBlue : _kText3,
        ),
      );
      tp.layout();

      final textY = size.height - _kBottomPad / 2 + 1 - tp.height / 2;

      if (isHovered) {
        final pillRect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x, size.height - _kBottomPad / 2 + 1),
            width: tp.width + 10,
            height: 17,
          ),
          const Radius.circular(4),
        );
        canvas.drawRRect(pillRect, Paint()..color = _kBlue.withValues(alpha: 0.12));
      }

      tp.paint(canvas, Offset(x - tp.width / 2, textY));
    }

    // ── 6. Hover overlay: vertical guideline, glowing rings & tooltip ────
    if (hoveredIndex != null && hoveredIndex! < count) {
      final hIdx = hoveredIndex!;
      final hx = _getX(hIdx, count, plotW);
      final ry = _getY(revenueFractions[hIdx], plotH);
      final ky = (hIdx < kgFractions.length)
          ? _getY(kgFractions[hIdx], plotH)
          : ry;

      // Dashed vertical guideline
      final guidePaint = Paint()
        ..color = const Color(0xFF64748B).withValues(alpha: 0.4)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      const dashH = 4.0;
      const dashSpace = 3.0;
      double curY = _kTopPad;
      final bottomGuideY = _kTopPad + plotH;
      while (curY < bottomGuideY) {
        canvas.drawLine(
          Offset(hx, curY),
          Offset(hx, math.min(curY + dashH, bottomGuideY)),
          guidePaint,
        );
        curY += dashH + dashSpace;
      }

      final whitePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;

      // Revenue point glow & rings
      canvas.drawCircle(
          Offset(hx, ry), 7.5, Paint()..color = primaryColor.withValues(alpha: 0.22));
      canvas.drawCircle(Offset(hx, ry), 5.0, whitePaint);
      canvas.drawCircle(Offset(hx, ry), 3.5, revDotPaint);

      // Sold KG point glow & rings
      if (hIdx < kgFractions.length) {
        canvas.drawCircle(Offset(hx, ky), 7.5,
            Paint()..color = secondaryColor.withValues(alpha: 0.22));
        canvas.drawCircle(Offset(hx, ky), 5.0, whitePaint);
        canvas.drawCircle(Offset(hx, ky), 3.5, kgDotPaint);
      }

      // Floating Tooltip Card
      final dt = (hIdx < dateList.length) ? dateList[hIdx] : null;
      final dateStr =
          dt != null ? DateFormat('EEE, d MMM yyyy').format(dt) : '—';
      final revVal = (hIdx < revenueList.length) ? revenueList[hIdx] : 0.0;
      final kgVal = (hIdx < kgList.length) ? kgList[hIdx] : 0.0;
      final revStr = Fmt.amount(revVal);
      final kgStr = '${NumberFormat('#,##,##0.00').format(kgVal)} kg';
      final avgRate = (kgVal > 0 && revVal > 0) ? revVal / kgVal : null;

      const tooltipW = 168.0;
      final tooltipH = avgRate != null ? 82.0 : 66.0;

      double tx;
      if (hx + 12.0 + tooltipW <= size.width - 6.0) {
        tx = hx + 12.0;
      } else {
        tx = hx - 12.0 - tooltipW;
      }
      tx = tx.clamp(_kLeftPad, math.max(_kLeftPad, size.width - tooltipW - 4.0));
      final ty = _kTopPad + 4.0;

      final tooltipRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(tx, ty, tooltipW, tooltipH),
        const Radius.circular(8),
      );

      // Drop shadow
      final shadowPath = Path()..addRRect(tooltipRect);
      canvas.drawShadow(shadowPath, const Color(0x24000000), 8, false);

      // Background
      canvas.drawRRect(tooltipRect, whitePaint);

      // Border
      canvas.drawRRect(
        tooltipRect,
        Paint()
          ..color = const Color(0xFFE2E8F0)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );

      // Header: Date
      tp.text = TextSpan(
        text: dateStr,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: _kText1,
        ),
      );
      tp.layout();
      tp.paint(canvas, Offset(tx + 10, ty + 7));

      // Divider
      canvas.drawLine(
        Offset(tx + 10, ty + 22),
        Offset(tx + tooltipW - 10, ty + 22),
        Paint()
          ..color = const Color(0xFFF1F5F9)
          ..strokeWidth = 1.0,
      );

      // Revenue line
      canvas.drawCircle(Offset(tx + 14, ty + 33), 3.0, revDotPaint);
      tp.text = const TextSpan(
        text: 'Revenue',
        style: TextStyle(
          fontSize: 9.5,
          color: _kText2,
          fontWeight: FontWeight.w500,
        ),
      );
      tp.layout();
      tp.paint(canvas, Offset(tx + 22, ty + 28));

      tp.text = TextSpan(
        text: revStr,
        style: const TextStyle(
          fontSize: 10,
          color: _kBlue,
          fontWeight: FontWeight.w700,
        ),
      );
      tp.layout();
      tp.paint(canvas, Offset(tx + tooltipW - 10 - tp.width, ty + 28));

      // Sold line
      canvas.drawCircle(Offset(tx + 14, ty + 49), 3.0, kgDotPaint);
      tp.text = const TextSpan(
        text: 'Sold',
        style: TextStyle(
          fontSize: 9.5,
          color: _kText2,
          fontWeight: FontWeight.w500,
        ),
      );
      tp.layout();
      tp.paint(canvas, Offset(tx + 22, ty + 44));

      tp.text = TextSpan(
        text: kgStr,
        style: const TextStyle(
          fontSize: 10,
          color: _kGold,
          fontWeight: FontWeight.w700,
        ),
      );
      tp.layout();
      tp.paint(canvas, Offset(tx + tooltipW - 10 - tp.width, ty + 44));

      // Rate line
      if (avgRate != null) {
        tp.text = TextSpan(
          text: 'Rate: ₹${avgRate.toStringAsFixed(2)}/kg',
          style: const TextStyle(
            fontSize: 9,
            color: _kText3,
            fontWeight: FontWeight.w600,
          ),
        );
        tp.layout();
        tp.paint(canvas, Offset(tx + tooltipW - 10 - tp.width, ty + 62));
      }
    }
  }

  @override
  bool shouldRepaint(_AreaChartPainter o) =>
      o.revenueFractions != revenueFractions ||
      o.kgFractions != kgFractions ||
      o.revenueList != revenueList ||
      o.kgList != kgList ||
      o.dateList != dateList ||
      o.hoveredIndex != hoveredIndex;
}

class _DonutSegmentData {
  const _DonutSegmentData({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;
}

class _LiveStockHoverBadge extends StatelessWidget {
  const _LiveStockHoverBadge({
    required this.label,
    required this.count,
    required this.color,
    required this.pct,
  });

  final String label;
  final int count;
  final Color color;
  final double pct;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            '${NumberFormat('#,##,###').format(count)} (${pct.toStringAsFixed(1)}%)',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _kText1,
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveStockPanel extends StatefulWidget {
  const _LiveStockPanel({required this.stock, required this.data});

  final List<StockPosition> stock;
  final DashboardData data;

  @override
  State<_LiveStockPanel> createState() => _LiveStockPanelState();
}

class _LiveStockPanelState extends State<_LiveStockPanel> {
  int? _hoveredIndex;

  void _onDonutHover(
      Offset localPos, double grandTotal, List<_DonutSegmentData> segments) {
    final dx = localPos.dx - 70;
    final dy = localPos.dy - 70;
    final dist = math.sqrt(dx * dx + dy * dy);

    if (dist < 28 || dist > 76) {
      if (_hoveredIndex != null) {
        setState(() => _hoveredIndex = null);
      }
      return;
    }

    double angle = math.atan2(dy, dx) + math.pi / 2;
    if (angle < 0) angle += 2 * math.pi;
    final progress = angle / (2 * math.pi);

    int? hitIndex;
    if (grandTotal > 0) {
      double accumulated = 0.0;
      for (int i = 0; i < segments.length; i++) {
        if (segments[i].value <= 0) continue;
        final segProgress = segments[i].value / grandTotal;
        if (progress >= accumulated && progress <= accumulated + segProgress) {
          hitIndex = i;
          break;
        }
        accumulated += segProgress;
      }
    }

    if (_hoveredIndex != hitIndex) {
      setState(() => _hoveredIndex = hitIndex);
    }
  }

  void _onDonutExit() {
    if (_hoveredIndex != null) {
      setState(() => _hoveredIndex = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalBirds = widget.stock.isEmpty
        ? widget.data.remainingBirds
        : widget.stock.fold(0, (s, p) => s + p.availableBirds);
    final availBirds = widget.stock.fold(0, (s, p) => s + p.availableBirds);
    final inTransit =
        widget.data.agentStatus.fold(0, (s, a) => s + a.liveStockBirds);
    final soldToday = widget.data.todayDelivered;
    final mortality = widget.data.todayMortalityBirdsLedger;
    final survival = widget.data.stockSurvivalDays;
    final totalKg = widget.stock.fold(0.0, (s, p) => s + p.availableKg);

    final ringColor = survival == null
        ? _kGreen
        : survival < 1
            ? _kRed
            : survival < 3
                ? _kOrange
                : _kGreen;

    final items = [
      ('Available', availBirds, _kGreen),
      ('In Transit', inTransit, _kBlue),
      ('Sold Today', soldToday, _kOrange),
      ('Mortality', mortality, _kRed),
    ];

    final grandTotal =
        (availBirds + inTransit + soldToday + mortality).toDouble();

    final segments = [
      _DonutSegmentData(
          label: 'Available', value: availBirds.toDouble(), color: _kGreen),
      _DonutSegmentData(
          label: 'In Transit', value: inTransit.toDouble(), color: _kBlue),
      _DonutSegmentData(
          label: 'Sold Today', value: soldToday.toDouble(), color: _kOrange),
      _DonutSegmentData(
          label: 'Mortality', value: mortality.toDouble(), color: _kRed),
    ];

    final tooltipText = 'Live Stock Breakdown:\n'
        '• Available: ${NumberFormat('#,##,###').format(availBirds)} birds (${grandTotal > 0 ? (availBirds / grandTotal * 100).toStringAsFixed(1) : 0}%)\n'
        '• In Transit: ${NumberFormat('#,##,###').format(inTransit)} birds (${grandTotal > 0 ? (inTransit / grandTotal * 100).toStringAsFixed(1) : 0}%)\n'
        '• Sold Today: ${NumberFormat('#,##,###').format(soldToday)} birds (${grandTotal > 0 ? (soldToday / grandTotal * 100).toStringAsFixed(1) : 0}%)\n'
        '• Mortality: ${NumberFormat('#,##,###').format(mortality)} birds (${grandTotal > 0 ? (mortality / grandTotal * 100).toStringAsFixed(1) : 0}%)\n'
        '• Total Weight: ${totalKg.toStringAsFixed(2)} kg\n'
        '• Stock Survival: ${survival != null ? (survival < 1 ? "< 1 day" : "${survival.toStringAsFixed(1)} days") : "—"}';

    return Container(
      decoration: BoxDecoration(
        color: _kPanel,
        borderRadius: BorderRadius.circular(WebRadius.card),
        border: Border.all(color: _kBorder),
        boxShadow: _kShadow,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Live Stock Overview', style: WebText.cardTitle),
          const Spacer(),
          if (_hoveredIndex != null &&
              _hoveredIndex! >= 0 &&
              _hoveredIndex! < items.length) ...[
            _LiveStockHoverBadge(
              label: items[_hoveredIndex!].$1,
              count: items[_hoveredIndex!].$2,
              color: items[_hoveredIndex!].$3,
              pct: grandTotal > 0
                  ? (items[_hoveredIndex!].$2 / grandTotal * 100)
                  : 0.0,
            ),
            const SizedBox(width: 8),
          ],
          InkWell(
            onTap: () => context.push(R.stockDetail),
            child: const Text('View Detail →',
                style: TextStyle(
                    fontSize: 11, color: _kBlue, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Tooltip(
            message: tooltipText,
            waitDuration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            textStyle: const TextStyle(
                fontSize: 11,
                color: _kText1,
                height: 1.5,
                fontWeight: FontWeight.w500),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1F000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onHover: (e) =>
                  _onDonutHover(e.localPosition, grandTotal, segments),
              onExit: (_) => _onDonutExit(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (e) =>
                    _onDonutHover(e.localPosition, grandTotal, segments),
                onHorizontalDragUpdate: (e) =>
                    _onDonutHover(e.localPosition, grandTotal, segments),
                onHorizontalDragEnd: (_) => _onDonutExit(),
                child: SizedBox(
                  width: 140,
                  height: 140,
                  child: Stack(alignment: Alignment.center, children: [
                    Transform.rotate(
                      angle: -math.pi / 2,
                      child: CustomPaint(
                        size: const Size(140, 140),
                        painter: _DonutPainter(
                          segments: segments,
                          hoveredIndex: _hoveredIndex,
                          trackColor: const Color(0xFFF1F5F9),
                          strokeWidth: 14,
                        ),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: (_hoveredIndex != null &&
                              _hoveredIndex! >= 0 &&
                              _hoveredIndex! < items.length)
                          ? Column(
                              key: ValueKey('hovered_$_hoveredIndex'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  items[_hoveredIndex!].$1.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: items[_hoveredIndex!].$3,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  NumberFormat('#,##,###')
                                      .format(items[_hoveredIndex!].$2),
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: _kText1,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                Text(
                                  grandTotal > 0
                                      ? '${((items[_hoveredIndex!].$2 / grandTotal) * 100).toStringAsFixed(1)}%'
                                      : 'Birds',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: items[_hoveredIndex!].$3,
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              key: const ValueKey('default_center'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  NumberFormat('#,##,###').format(totalBirds),
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: _kText1,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const Text(
                                  'Birds',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: _kText3,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${totalKg.toStringAsFixed(2)} Kg',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: _kText3,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (survival != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    survival < 1
                                        ? '< 1 day'
                                        : '${survival.toStringAsFixed(1)}d',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: ringColor,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              children: [
                for (int i = 0; i < items.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      onEnter: (_) => setState(() => _hoveredIndex = i),
                      onExit: (_) => setState(() => _hoveredIndex = null),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: (_hoveredIndex == i)
                              ? items[i].$3.withValues(alpha: 0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: (_hoveredIndex == i)
                                ? items[i].$3.withValues(alpha: 0.3)
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: items[i].$3,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                items[i].$1,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: (_hoveredIndex == i)
                                      ? _kText1
                                      : _kText2,
                                  fontWeight: (_hoveredIndex == i)
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                            Text(
                              NumberFormat('#,##,###').format(items[i].$2),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: (_hoveredIndex == i)
                                    ? items[i].$3
                                    : _kText1,
                              ),
                            ),
                            if (grandTotal > 0) ...[
                              const SizedBox(width: 6),
                              Text(
                                '(${((items[i].$2 / grandTotal) * 100).toStringAsFixed(0)}%)',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: (_hoveredIndex == i)
                                      ? items[i].$3
                                      : _kText3,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 12),
        if (widget.data.agingStockBatches > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _kRedLt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kRed.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: _kRed, size: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${widget.data.agingStockBatches} batch${widget.data.agingStockBatches > 1 ? "es" : ""} '
                  'with stock older than 2 days — quality risk',
                  style: const TextStyle(
                    fontSize: 11,
                    color: _kRed,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ]),
          )
        else
          const Text('Updated just now',
              style: TextStyle(fontSize: 11, color: _kText3)),
      ]),
    );
  }
}

class _NavigatorAgentShift extends StatelessWidget {
  const _NavigatorAgentShift({required this.agents, required this.onTap});

  final List<AgentStockStatus> agents;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (agents.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: _kPanel,
        borderRadius: BorderRadius.circular(WebRadius.card),
        border: Border.all(color: _kBorder),
        boxShadow: _kShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Row(children: [
            const Text('Agents on Shift', style: WebText.cardTitle),
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
                Text('${agent.todayDeliveredBirds} birds',
                    style: const TextStyle(fontSize: 11, color: _kText3)),
              ])),
          if (agent.todayDcKg > 0)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${agent.todayDcKg.toStringAsFixed(0)} kg',
                        style: const TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w700, color: _kText1)),
                    const Text('loaded',
                        style: TextStyle(fontSize: 9, color: _kText3)),
                  ]),
            ),
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

class _CollectionIntelligencePanel extends StatelessWidget {
  const _CollectionIntelligencePanel({
    required this.data,
    required this.aging,
    required this.onLedger,
    required this.onClosure,
  });

  final DashboardData data;
  final List<Map<String, dynamic>> aging;
  final VoidCallback onLedger, onClosure;

  @override
  Widget build(BuildContext context) {
    final bucketMap = <String, Map<String, dynamic>>{};
    for (final row in aging) {
      bucketMap[row['bucket'] as String? ?? ''] = row;
    }

    final bucketDefs = [
      ('critical', _kRed,                  'Critical  >30d'),
      ('overdue',  const Color(0xFFEA580C), 'Overdue  16–30d'),
      ('due_soon', _kOrange,               'Due Soon  8–15d'),
      ('current',  _kGreen,               'Current  0–7d'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: _kPanel,
        borderRadius: BorderRadius.circular(WebRadius.card),
        border: Border.all(color: _kBorder),
        boxShadow: _kShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Row(children: [
            const Text('Collection Intelligence', style: WebText.cardTitle),
            const Spacer(),
            InkWell(onTap: onLedger,
                child: const Text('View All',
                    style: TextStyle(fontSize: 11, color: _kBlue,
                        fontWeight: FontWeight.w600))),
          ]),
        ),
        const Divider(height: 1, color: _kBorder),
        Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [

          Row(children: [
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('Credit used: ${data.creditUtilisationPct.toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 11,
                        fontWeight: FontWeight.w700, color: _kText1)),
                if (data.overLimitCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: _kRedLt,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: _kRed.withValues(alpha: 0.3))),
                    child: Text('${data.overLimitCount} over limit',
                        style: const TextStyle(fontSize: 9,
                            fontWeight: FontWeight.w800, color: _kRed)),
                  ),
                ],
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (data.creditUtilisationPct / 100).clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: _kBorder,
                  valueColor: AlwaysStoppedAnimation(
                    data.creditUtilisationPct >= 90
                        ? _kRed
                        : data.creditUtilisationPct >= 70
                        ? _kOrange
                        : _kGreen,
                  ),
                ),
              ),
            ])),
          ]),
          const SizedBox(height: 14),
          const Divider(height: 1, color: _kBorder),
          const SizedBox(height: 12),

          ...bucketDefs.map((def) {
            final bucket = bucketMap[def.$1];
            final count  = (bucket?['retailer_count'] as num?)?.toInt()    ?? 0;
            final amount = (bucket?['total_amount']   as num?)?.toDouble() ?? 0;
            if (count == 0) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Container(width: 3, height: 32,
                    decoration: BoxDecoration(
                        color: def.$2,
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 10),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(def.$3, style: TextStyle(fontSize: 10,
                      fontWeight: FontWeight.w700, color: def.$2)),
                  Text('$count retailer${count > 1 ? "s" : ""}',
                      style: const TextStyle(
                          fontSize: 10, color: _kText3)),
                ])),
                Text(Fmt.amount(amount),
                    style: TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w800, color: def.$2)),
              ]),
            );
          }),

          const SizedBox(height: 8),
          const Divider(height: 1, color: _kBorder),
          const SizedBox(height: 10),

              () {
            final critical = bucketMap['critical'];
            final topName  = critical?['top_shop_name']   as String?;
            final topAmt   = (critical?['top_outstanding'] as num?)?.toDouble() ?? 0;
            final topDays  = (critical?['top_days']        as num?)?.toInt()    ?? 0;
            if (topName == null) {
              return Column(children: [
                _IRow(icon: Icons.currency_rupee_rounded, color: _kGreen,
                    label: "Today's Collection",
                    value: Fmt.amount(data.todayCollected)),
                const SizedBox(height: 8),
                _IRow(icon: Icons.hourglass_empty_rounded, color: _kOrange,
                    label: 'Total Outstanding',
                    value: Fmt.amount(data.totalOutstanding)),
              ]);
            }
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('CALL TODAY',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                      color: _kText3, letterSpacing: 0.6)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: _kRedLt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: _kRed.withValues(alpha: 0.2))),
                child: Row(children: [
                  Container(width: 32, height: 32,
                      decoration: BoxDecoration(
                          color: _kRed.withValues(alpha: 0.12),
                          shape: BoxShape.circle),
                      child: const Icon(Icons.phone_outlined,
                          color: _kRed, size: 16)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(topName, style: const TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w700, color: _kText1),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('$topDays days overdue',
                        style: const TextStyle(
                            fontSize: 10, color: _kRed,
                            fontWeight: FontWeight.w600)),
                  ])),
                  Text(Fmt.amount(topAmt),
                      style: const TextStyle(fontSize: 14,
                          fontWeight: FontWeight.w900, color: _kRed)),
                ]),
              ),
            ]);
          }(),

          if (data.allClear) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onClosure,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                    color: _kNavBg,
                    borderRadius: BorderRadius.circular(8)),
                child: const Center(child: Text('Close Day →',
                    style: TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w700, color: Colors.white))),
              ),
            ),
          ],
        ])),
      ]),
    );
  }
}

class _IRow extends StatelessWidget {
  const _IRow({required this.icon, required this.color,
    required this.label, required this.value});
  final IconData icon;
  final Color color;
  final String label, value;
  @override
  Widget build(BuildContext c) => Row(children: [
    Container(width: 32, height: 32,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color, size: 15)),
    const SizedBox(width: 10),
    Expanded(child: Text(label, style: const TextStyle(
        fontSize: 12, color: _kText2, fontWeight: FontWeight.w500))),
    Text(value, style: const TextStyle(
        fontSize: 13, fontWeight: FontWeight.w700, color: _kText1)),
  ]);
}

class _TopRetailersToday extends StatelessWidget {
  const _TopRetailersToday({required this.retailers, required this.onViewAll});

  final List<Map<String, dynamic>> retailers;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    if (retailers.isEmpty) return const SizedBox.shrink();
    final maxRev = (retailers.first['revenue_today'] as num?)?.toDouble() ?? 1;

    return Container(
      decoration: BoxDecoration(
        color: _kPanel,
        borderRadius: BorderRadius.circular(WebRadius.card),
        border: Border.all(color: _kBorder),
        boxShadow: _kShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Row(children: [
            const Text('Top Retailers Today', style: WebText.cardTitle),
            const Spacer(),
            InkWell(onTap: onViewAll,
                child: const Text('View All',
                    style: TextStyle(fontSize: 11, color: _kBlue,
                        fontWeight: FontWeight.w600))),
          ]),
        ),
        const Divider(height: 1, color: _kBorder),
        ...retailers.take(5).toList().asMap().entries.map((e) {
          final i   = e.key;
          final r   = e.value;
          final rev = (r['revenue_today']   as num?)?.toDouble() ?? 0;
          final ord = (r['order_count']     as num?)?.toInt()    ?? 0;
          final col = (r['collection_rate'] as num?)?.toDouble() ?? 0;
          final pct = maxRev > 0 ? (rev / maxRev).clamp(0.0, 1.0) : 0.0;

          return Container(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
            decoration: i < retailers.length - 1
                ? const BoxDecoration(
                border: Border(bottom: BorderSide(color: _kBorder)))
                : null,
            child: Column(children: [
              Row(children: [
                Container(width: 22, height: 22,
                    decoration: BoxDecoration(
                        color: i == 0 ? _kNavBg : const Color(0xFFF1F5F9),
                        shape: BoxShape.circle),
                    child: Center(child: Text('${i + 1}',
                        style: TextStyle(fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: i == 0
                                ? const Color(0xFFE9C176)
                                : _kText3)))),
                const SizedBox(width: 10),
                Expanded(child: Text(r['shop_name'] as String? ?? '—',
                    style: const TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w600, color: _kText1),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(Fmt.amount(rev),
                      style: const TextStyle(fontSize: 13,
                          fontWeight: FontWeight.w800, color: _kText1)),
                  Text('$ord order${ord != 1 ? "s" : ""} · ${col.toStringAsFixed(0)}% collected',
                      style: const TextStyle(fontSize: 10, color: _kText3)),
                ]),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 3,
                  backgroundColor: _kBorder,
                  valueColor: AlwaysStoppedAnimation(
                      i == 0 ? _kBlue : _kBlue.withValues(alpha: 0.4)),
                ),
              ),
            ]),
          );
        }),
      ]),
    );
  }
}

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
    if (totalBirds < 500 && totalBirds >= 0) {
      final lowStock = stock.isEmpty
          ? null
          : stock.reduce(
              (a, b) => a.availableBirds <= b.availableBirds ? a : b);
      final stockLabel = lowStock != null
          ? '${lowStock.productName} stock'
          : 'Live stock';
      alerts.add((_kOrange, Icons.inventory_outlined,
      'Low Stock Alert', '$stockLabel is below 500 birds'));
    }
    if (data.totalOutstanding > 50000) {
      alerts.add((_kRed, Icons.account_balance_wallet_outlined,
      'Payment Overdue', 'Outstanding exceeds ₹50,000'));
    }
    if (data.activeDeliveries > 3) {
      alerts.add((_kBlue, Icons.local_shipping_outlined,
      'Dispatch Delay', '${data.activeDeliveries} orders pending dispatch'));
    }
    if (data.todayMortalityBirdsLedger > 0) {
      alerts.add((_kColorsViolet, Icons.warning_amber_outlined,
      'Mortality Today', '${data.todayMortalityBirdsLedger} birds'));
    }

    if (alerts.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: _kPanel,
        borderRadius: BorderRadius.circular(WebRadius.card),
        border: Border.all(color: _kBorder),
        boxShadow: _kShadow,
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Row(children: [
            const Text('Critical Alerts', style: WebText.cardTitle),
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
  // Status filter — shown as tabs with counts (was a dropdown)
  static const _statuses = [
    'All Status',
    'pending',
    'confirmed',
    'dispatched',
    'delivered'
  ];
  String _statusFilter = 'All Status';
  String _searchQuery = '';

  // Table state
  String _sortKey = 'time';
  bool _sortAsc = false;
  bool _dense = true;
  int _page = 0;
  int _rowsPerPage = 10;

  static const _columns = [
    WebColumn('Order ID', width: 110, sortKey: 'id'),
    WebColumn('Customer', flex: 3, sortKey: 'customer'),
    WebColumn('Area', width: 120),
    WebColumn('Birds', width: 85, align: TextAlign.right),
    WebColumn('Weight', width: 100, sortKey: 'weight', align: TextAlign.right),
    WebColumn('Amount', width: 120, sortKey: 'amount',
        align: TextAlign.right),
    WebColumn('Status', width: 120, align: TextAlign.center),
    WebColumn('Agent', flex: 2),
    WebColumn('Time', width: 100, sortKey: 'time'),
    WebColumn('Action', width: 80, align: TextAlign.center),
  ];

  List<Map<String, dynamic>> _byStatus(String s) => s == 'All Status'
      ? widget.orders
      : widget.orders.where((o) =>
          (o['status'] as String? ?? '') == s).toList();

  List<Map<String, dynamic>> get _filtered {
    var rows = _byStatus(_statusFilter);
    if (_searchQuery.isNotEmpty) {
      rows = rows.where((o) {
        final shopName = ((o['retailers'] as Map?)?['shop_name']
        as String? ?? '').toLowerCase();
        final orderId = (o['id'] as String? ?? '').toLowerCase();
        return shopName.contains(_searchQuery) ||
            orderId.contains(_searchQuery);
      }).toList();
    }
    rows = [...rows]..sort((a, b) {
      final c = Comparable.compare(_sortValue(a), _sortValue(b));
      return _sortAsc ? c : -c;
    });
    return rows;
  }

  Comparable<Object> _sortValue(Map<String, dynamic> o) {
    switch (_sortKey) {
      case 'id':
        return o['id'] as String? ?? '';
      case 'customer':
        return ((o['retailers'] as Map?)?['shop_name'] as String? ?? '')
            .toLowerCase();
      case 'weight':
        return (o['total_quantity'] as num?) ?? 0;
      case 'amount':
        return (o['total_amount'] as num?) ?? 0;
      default:
        return o['created_at'] as String? ?? '';
    }
  }

  // ── Extract the delivery agent name for an order, if one is assigned ──────
  String? _agentFor(Map<String, dynamic> o) {
    final deliveries = o['deliveries'] as List? ?? [];
    for (final d in deliveries) {
      final agent = (d as Map?)?['delivery_agents'];
      final name = agent is Map ? agent['name'] as String? : null;
      if (name != null && name.isNotEmpty) return name;
    }
    return null;
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

  String _label(String s) => s == 'All Status'
      ? 'All' : s.replaceAll('_', ' ').capitalize();

  void _sort(String key) => setState(() {
    if (_sortKey == key) {
      _sortAsc = !_sortAsc;
    } else {
      _sortKey = key;
      _sortAsc = true;
    }
    _page = 0;
  });

  Widget _cell(Map<String, dynamic> o, int col) {
    final retailer = o['retailers'] as Map<String, dynamic>?;
    final shopName = retailer?['shop_name'] as String? ?? '—';
    final id = o['id'] as String? ?? '';
    switch (col) {
      case 0:
        return Text('#${id.length >= 6 ? id.substring(0, 6).toUpperCase() : id}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                color: _kBlue));
      case 1:
        return Text(shopName, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: _kText1));
      case 2:
        final area = retailer?['area'] as String? ?? retailer?['phone'] as String? ?? '—';
        return Text(area, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: _kText2));
      case 3:
        final birds = (o['estimated_birds'] as num?)?.toInt() ?? 0;
        return Text(birds > 0 ? '$birds' : '—', style: const TextStyle(fontSize: 13.5, color: _kText2));
      case 4:
        final wt = (o['total_quantity'] as num?)?.toDouble() ?? 0;
        return Text(wt > 0 ? '${wt.toStringAsFixed(0)} kg' : '—', style: const TextStyle(fontSize: 13.5, color: _kText2));
      case 5:
        final amt = (o['total_amount'] as num?)?.toDouble() ?? 0;
        return Text(Fmt.amount(amt), style: const TextStyle(
            fontSize: 13.5, fontWeight: FontWeight.w700, color: _kText1));
      case 6:
        final status = o['status'] as String? ?? 'pending';
        return WebLabel(_label(status), color: _statusColor(status));
      case 7:
        final agent = _agentFor(o);
        return Text(agent ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13,
                color: agent == null ? _kText3 : _kText2));
      case 8:
        final createdAt = DateTime.tryParse(o['created_at'] as String? ?? '');
        return Text(createdAt != null
            ? DateFormat('hh:mm a').format(createdAt.toLocal()) : '—',
            style: const TextStyle(fontSize: 13, color: _kText2));
      default:
        return WebIconButton(
          icon: Icons.visibility_outlined,
          tooltip: 'View order',
          size: 32,
          outlined: false,
          onTap: () => widget.onOrder(id),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    final lastPage = rows.isEmpty ? 0 : (rows.length - 1) ~/ _rowsPerPage;
    final page = _page.clamp(0, lastPage);
    final pageRows = rows.skip(page * _rowsPerPage).take(_rowsPerPage).toList();

    return WebListCard(children: [
      WebCardHeader(
        title: 'Recent Orders',
        subtitle: 'Showing ${rows.length} of ${widget.orders.length} orders',
        action: WebButton(
          label: 'View All Orders',
          icon: Icons.arrow_forward_rounded,
          onPressed: widget.onViewAll,
        ),
      ),
      WebListTabs(
        tabs: [
          for (final s in _statuses)
            WebTab(_label(s),
                count: _byStatus(s).length,
                color: s == 'All Status' ? null : _statusColor(s)),
        ],
        selected: _statuses.indexOf(_statusFilter),
        onChanged: (i) => setState(() {
          _statusFilter = _statuses[i];
          _page = 0;
        }),
      ),
      WebListToolbar(
        search: WebSearchField(
          hint: 'Search orders...',
          debounce: const Duration(milliseconds: 250),
          onChanged: (v) => setState(() {
            _searchQuery = v.toLowerCase();
            _page = 0;
          }),
        ),
      ),
      WebDataTable<Map<String, dynamic>>(
        columns: _columns,
        rows: pageRows,
        cellBuilder: _cell,
        onRowTap: (o) => widget.onOrder(o['id'] as String? ?? ''),
        sortKey: _sortKey,
        sortAscending: _sortAsc,
        onSort: _sort,
        dense: _dense,
        emptyText: 'No orders found',
      ),
      WebTablePagination(
        page: page,
        rowsPerPage: _rowsPerPage,
        total: rows.length,
        rowsPerPageOptions: const [5, 10, 25, 50],
        onPage: (p) => setState(() => _page = p),
        onRowsPerPage: (n) => setState(() { _rowsPerPage = n; _page = 0; }),
        dense: _dense,
        onDense: (v) => setState(() => _dense = v),
      ),
    ]);
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    this.fraction,
    this.ringColor,
    this.segments,
    this.hoveredIndex,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double? fraction;
  final Color? ringColor;
  final List<_DonutSegmentData>? segments;
  final int? hoveredIndex;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = (size.width - strokeWidth) / 2;
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = trackColor;

    canvas.drawCircle(c, r, trackPaint);

    if (segments != null && segments!.isNotEmpty) {
      final total = segments!.fold(0.0, (sum, s) => sum + s.value);
      if (total <= 0) return;

      double startAngle = 0.0;
      final nonZeroCount = segments!.where((s) => s.value > 0).length;
      final gap = nonZeroCount > 1 ? 0.06 : 0.0;

      for (int i = 0; i < segments!.length; i++) {
        final seg = segments![i];
        if (seg.value <= 0) continue;
        final sweep = 2 * math.pi * (seg.value / total);
        final isHovered = (hoveredIndex == i);

        // Highlight halo for hovered segment
        if (isHovered) {
          final haloPaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth + 6
            ..strokeCap = StrokeCap.round
            ..color = seg.color.withValues(alpha: 0.28);
          canvas.drawArc(
            Rect.fromCircle(center: c, radius: r),
            startAngle + gap / 2,
            math.max(0.01, sweep - gap),
            false,
            haloPaint,
          );
        }

        final segPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isHovered ? strokeWidth + 2.5 : strokeWidth
          ..strokeCap = StrokeCap.round
          ..color = (hoveredIndex != null && !isHovered)
              ? seg.color.withValues(alpha: 0.45)
              : seg.color;

        canvas.drawArc(
          Rect.fromCircle(center: c, radius: r),
          startAngle + gap / 2,
          math.max(0.01, sweep - gap),
          false,
          segPaint,
        );

        startAngle += sweep;
      }
      return;
    }

    if (ringColor != null && fraction != null && fraction! > 0) {
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = ringColor!;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        0,
        2 * math.pi * fraction!.clamp(0.0, 1.0),
        false,
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_DonutPainter o) =>
      o.fraction != fraction ||
      o.ringColor != ringColor ||
      o.hoveredIndex != hoveredIndex ||
      o.segments != segments;
}

class _QA {
  const _QA(this.icon, this.label, this.color, this.bg, this.onTap,
      {this.wide = false});

  final IconData icon;
  final String label;
  final Color color, bg;
  final VoidCallback onTap;
  final bool wide;
}

class _L {
  static String g(String lang, String k) => _t[lang]?[k] ?? _t['en']![k] ?? k;
  static const _t = {
    'en': {
      'today': 'Today Overview',
      'new_order': 'New Order',
      'stock_point_sale': 'Stock Point Sale',
      'inventory_dashboard': 'Inventory Dashboard',
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
      'stock_point_sale': 'கடை விற்பனை',
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