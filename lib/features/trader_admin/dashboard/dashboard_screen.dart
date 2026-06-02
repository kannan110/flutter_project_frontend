import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rooster_trader/shared/layouts/trader_shell.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/dashboard_models.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/responsive_layout.dart';
import '../dashboard/trader_shell.dart';

// ── Language provider (preserved exactly) ────────────────────────────────────
final langProvider = StateProvider<String>((ref) => 'en');

class _L {
  static String g(String lang, String k) => _t[lang]?[k] ?? _t['en']![k] ?? k;
  static const _t = {
    'en': {
      'today': 'Today Overview', 'new_order': 'New Order', 'orders': 'Orders',
      'approve': 'Approve', 'dispatch': 'Dispatch', 'collect': 'Collect Cash',
      'customers': 'Customers', 'agents': 'Agents', 'rate': 'Set Rate',
      'returns': 'Returns', 'reconcile': 'Check Cash', 'close_day': 'Close Day',
      'alerts': 'Alerts', 'report': 'Report', 'crates': 'Crates',
      'invoices': 'Bills', 'shifts': 'Shifts', 'stock_in': 'Purchased',
      'delivered': 'Delivered', 'returned': 'Returns', 'remaining': 'Remaining',
      'add_stock': 'Add Stock', 'outstanding': 'To Collect', 'cash': 'Cash', 'upi': 'UPI',
    },
    'ta': {
      'today': 'இன்றைய நிலை', 'new_order': 'புது ஆர்டர்', 'orders': 'ஆர்டர்',
      'approve': 'அனுமதி', 'dispatch': 'அனுப்பு', 'collect': 'பணம் வசூல்',
      'customers': 'வாடிக்கையாளர்', 'agents': 'ஏஜெண்ட்', 'rate': 'விலை',
      'returns': 'திருப்பம்', 'reconcile': 'கேஷ் சரிபார்', 'close_day': 'நாள் முடி',
      'alerts': 'எச்சரிக்கை', 'report': 'அறிக்கை', 'crates': 'கிரேட்',
      'invoices': 'பில்', 'shifts': 'ஷிஃப்ட்', 'stock_in': 'வாங்கியது',
      'delivered': 'டெலிவரி', 'returned': 'திருப்பம்', 'remaining': 'மீதம்',
      'add_stock': 'கோழி சேர்', 'outstanding': 'வசூல் செய்ய', 'cash': 'கேஷ்', 'upi': 'UPI',
    },
  };
}

class _QA {
  final IconData     icon;
  final String       label;
  final Color        color;
  final Color        bg;
  final VoidCallback onTap;
  final bool         wide;
  const _QA(this.icon, this.label, this.color, this.bg, this.onTap,
      {this.wide = false});
}

// ── DashboardScreen ──────────────────────────────────────────────────────────
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  // ── STATE — all preserved exactly ─────────────────────────────────────────
  DashboardData?      _data;
  List<StockPosition> _stock   = [];
  bool                _loading = true;
  String?             _error;

  // ── Lifecycle — preserved exactly ─────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null || !mounted) return;
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final dashRes  = await Supabase.instance.client
          .rpc('dashboard_summary',   params: {'p_trader_id': tid});
      final stockRes = await Supabase.instance.client
          .rpc('get_available_stock', params: {'p_trader_id': tid});
      if (!mounted) return;
      final dashMap   = dashRes  as Map<String, dynamic>?;
      final stockList = stockRes as List?;
      setState(() {
        _data  = dashMap != null ? DashboardData.fromMap(dashMap)
            : const DashboardData();
        _stock = (stockList ?? [])
            .map((s) => StockPosition.fromMap(s as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
      if (mounted && _data != null) {
        ref.read(shellBadgesProvider.notifier).update((s) => s.copyWith(
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

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(appUserProvider).valueOrNull;
    final lang = ref.watch(langProvider);
    final t    = (String k) => _L.g(lang, k);

    return ResponsiveLayout(
      mobile:  (_) => _buildMobileScaffold(user, lang, t),
      desktop: (_) => _buildDesktopLayout(user, lang, t),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MOBILE SCAFFOLD — redesigned presentation, all logic preserved
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildMobileScaffold(dynamic user, String lang,
      String Function(String) t) {
    if (_loading) {
      return Scaffold(
        backgroundColor: kBgPage,
        body: const Center(
            child: CircularProgressIndicator(color: kNavy, strokeWidth: 2.5)),
      );
    }
    if (_error != null) {
      return Scaffold(backgroundColor: kBgPage, body: _errorView());
    }

    return Scaffold(
      backgroundColor: kBgPage,
      body: RefreshIndicator(
        onRefresh:   _load,
        color:       kNavy,
        strokeWidth: 2.5,
        child: CustomScrollView(
          slivers: [
            // ── App Bar — greeting style ────────────────────────────────
            SliverToBoxAdapter(child: _mobileHeader(user, lang, t)),
            // ── Alert banners ───────────────────────────────────────────
            if (_buildAlerts(t).isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                sliver: SliverList.list(
                  children: _buildAlerts(t)
                      .map((w) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child:   w))
                      .toList(),
                ),
              ),
            // ── Navy gradient summary card ──────────────────────────────
            SliverToBoxAdapter(child: _summaryCard(t)),
            // ── Live stock — gold donut ring ────────────────────────────
            SliverToBoxAdapter(child: _stockSection(t)),
            // ── Financial overview ──────────────────────────────────────
            SliverToBoxAdapter(child: _financialSection(t)),
            // ── Quick actions grid ──────────────────────────────────────
            SliverToBoxAdapter(child: _qaSection(t)),
            // ── Agent performance table ─────────────────────────────────
            if ((_data?.agentStatus ?? []).isNotEmpty)
              SliverToBoxAdapter(child: _agentSection()),
            // ── Reconciliation strip ────────────────────────────────────
            if ((_data?.todayDelivered ?? 0) > 0)
              SliverToBoxAdapter(child: _reconSection(t)),
            // ── Returns ─────────────────────────────────────────────────
            if ((_data?.todayReturnsBirds ?? 0) > 0 ||
                (_data?.pendingReturns  ?? 0) > 0)
              SliverToBoxAdapter(child: _returnsSection(t)),
            // ── Reconciliation status + close day ───────────────────────
            SliverToBoxAdapter(child: _allClearSection(t)),
            // Bottom spacer for glass nav
            const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ],
        ),
      ),
    );
  }

  // ── Greeting header ────────────────────────────────────────────────────────
  Widget _mobileHeader(dynamic user, String lang, String Function(String) t) {
    final alerts = _data?.unreadAlerts ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 52, 20, 12),
      child: Row(children: [
        // Avatar with gold ring
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            shape:  BoxShape.circle,
            border: Border.all(color: kGoldLight, width: 2),
          ),
          padding: const EdgeInsets.all(2),
          child: CircleAvatar(
            backgroundColor: kNavyMid,
            child: Text(
              _initials(user?.companyName),
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w900,
                  color: kGoldLight),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('GOOD MORNING,',
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w800,
                  color: kTextHint, letterSpacing: 0.8)),
          Text(user?.companyName ?? 'Trader',
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w900,
                  color: kNavy, letterSpacing: -0.3),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(t('today'),
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: kGold)),
        ])),
        // Language toggle
        GestureDetector(
          onTap: () => ref.read(langProvider.notifier).state =
          lang == 'en' ? 'ta' : 'en',
          child: Container(
            margin: const EdgeInsets.only(right: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color:        kSurface,
              borderRadius: BorderRadius.circular(99),
              border:       Border.all(color: kBorderLight),
              boxShadow:    kCardShadow,
            ),
            child: Text(lang == 'en' ? 'தமிழ்' : 'EN',
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800, color: kNavy)),
          ),
        ),
        // Notification bell with badge
        GestureDetector(
          onTap: () => context.go(R.alerts),
          child: Stack(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                shape:     BoxShape.circle,
                color:     kSurface,
                border:    Border.all(color: kBorderLight),
                boxShadow: kCardShadow,
              ),
              child: const Icon(Icons.notifications_outlined,
                  color: kTextSub, size: 20),
            ),
            if (alerts > 0)
              Positioned(
                right: 2, top: 2,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color:        kError,
                    borderRadius: BorderRadius.circular(99),
                    border:       Border.all(color: kSurface, width: 1.5),
                  ),
                  child: Text('$alerts',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 8, fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ),
              ),
          ]),
        ),
        const SizedBox(width: 8),
        // Profile button
        GestureDetector(
          onTap: () => context.go(R.settings),
          child: Container(
            width: 42, height: 42,
            decoration: const BoxDecoration(
                shape: BoxShape.circle, color: kNavy),
            child: const Icon(Icons.person_outline_rounded,
                color: kGoldLight, size: 22),
          ),
        ),
      ]),
    );
  }

  // ── Navy gradient summary card ────────────────────────────────────────────
  Widget _summaryCard(String Function(String) t) {
    final d = _data;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [kNavy, kNavyMid],
            begin:  Alignment.topLeft,
            end:    Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(kRadiusHero),
          boxShadow: [
            BoxShadow(
              color:      kNavy.withValues(alpha: 0.35),
              blurRadius: 24,
              offset:     const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.dashboard_rounded, color: kGoldLight, size: 16),
            const SizedBox(width: 8),
            const Text("TODAY'S SUMMARY",
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w900,
                    color: Color(0xFFB4C6F4), letterSpacing: 0.8)),
            const Spacer(),
            GestureDetector(
              onTap: _load,
              child: const Icon(Icons.refresh_rounded,
                  color: Color(0xFFB4C6F4), size: 16),
            ),
          ]),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _summaryStatItem(
                icon:  Icons.receipt_long_rounded,
                value: '${d?.pendingOrders ?? 0}',
                label: t('orders'),
                onTap: () => context.go(R.orders),
                urgent: (d?.pendingOrders ?? 0) > 0,
              ),
              _summaryStatItem(
                icon:  Icons.local_shipping_rounded,
                value: '${d?.activeDeliveries ?? 0}',
                label: t('dispatch'),
                onTap: () => context.go(R.dispatch),
              ),
              _summaryStatItem(
                icon:  Icons.verified_user_rounded,
                value: '${d?.pendingApprovals ?? 0}',
                label: t('approve'),
                onTap: () => context.go(R.approvals),
                urgent: (d?.pendingApprovals ?? 0) > 0,
              ),
              _summaryStatItem(
                icon:  Icons.support_agent_rounded,
                value: '${d?.activeAgents ?? 0}',
                label: t('agents'),
                onTap: () => context.go(R.agents),
              ),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _summaryStatItem({
    required IconData   icon,
    required String     value,
    required String     label,
    required VoidCallback onTap,
    bool urgent = false,
  }) => GestureDetector(
    onTap: onTap,
    child: Column(children: [
      Container(
        width: 46, height: 46,
        decoration: BoxDecoration(
          color:        urgent
              ? kError.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border:       Border.all(
              color: urgent
                  ? kError.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.12)),
        ),
        child: Icon(icon,
            color: urgent ? const Color(0xFFFFB4AC) : kGoldLight, size: 22),
      ),
      const SizedBox(height: 8),
      Text(value,
          style: TextStyle(
              fontSize:   26,
              fontWeight: FontWeight.w900,
              color:      urgent ? const Color(0xFFFFB4AC) : Colors.white,
              letterSpacing: -0.5)),
      Text(label,
          style: const TextStyle(
              fontSize:   9,
              fontWeight: FontWeight.w900,
              color:      Color(0xFFB4C6F4),
              letterSpacing: -0.2)),
    ]),
  );

  // ── Live Stock — gold donut ring ──────────────────────────────────────────
  Widget _stockSection(String Function(String) t) {
    final agents  = _data?.agentStatus ?? [];
    final totalBirds = _stock.isEmpty ? 0
        : _stock.fold(0, (s, p) => s + p.availableBirds);
    final inTransit  = agents.fold(0, (s, a) => s + a.liveStockBirds);
    final soldToday  = _data?.todayDelivered ?? 0;

    // donut: available vs capacity rough estimate
    final maxBirds  = (totalBirds + soldToday).clamp(1, 999999);
    final fraction  = totalBirds / maxBirds;
    const r         = 60.0;
    const circ      = 2 * 3.14159 * r;
    final dashArray = circ;
    final dashOffset= circ * (1 - fraction);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: GestureDetector(
        onTap: () => context.push(R.stockDetail),
        child: Container(
          decoration: BoxDecoration(
            color:        kSurface,
            borderRadius: BorderRadius.circular(kRadiusHero),
            border:       Border.all(color: kBorderLight.withValues(alpha: 0.5)),
            boxShadow:    kCardShadow,
          ),
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.inventory_2_rounded, color: kGold, size: 18),
              const SizedBox(width: 8),
              const Text('LIVE STOCK',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w900,
                      color: kNavy, letterSpacing: 0.6)),
              const Spacer(),
              const Text('DETAILS ›',
                  style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w900,
                      color: kGold, letterSpacing: 0.6)),
            ]),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Gold donut ring
                SizedBox(
                  width: 140, height: 140,
                  child: Stack(alignment: Alignment.center, children: [
                    Transform.rotate(
                      angle: -1.5708, // -90 degrees
                      child: CustomPaint(
                        size: const Size(140, 140),
                        painter: _DonutPainter(
                          fraction:   fraction,
                          ringColor:  kGoldLight,
                          trackColor: const Color(0xFFF3F4F6),
                          strokeWidth: 12,
                        ),
                      ),
                    ),
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                        _stock.isEmpty ? '0' : '$totalBirds',
                        style: const TextStyle(
                            fontSize: 30, fontWeight: FontWeight.w900,
                            color: kNavy, letterSpacing: -0.5),
                      ),
                      const Text('TOTAL BIRDS',
                          style: TextStyle(
                              fontSize: 8, fontWeight: FontWeight.w900,
                              color: kTextHint, letterSpacing: 0.8)),
                    ]),
                  ]),
                ),
                const SizedBox(width: 20),
                // Legend
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ..._stock.map((s) => _stockLegendRow(
                        dot:   kGoldLight,
                        label: 'IN STOCK',
                        value: '${s.availableBirds}',
                        sub:   '${s.availableKg.toStringAsFixed(0)} kg',
                      )),
                      if (inTransit > 0)
                        _stockLegendRow(
                          dot:   const Color(0xFF7687B2),
                          label: 'IN TRANSIT',
                          value: '$inTransit',
                        ),
                      _stockLegendRow(
                        dot:   kError,
                        label: 'SOLD TODAY',
                        value: '$soldToday',
                      ),
                      if ((_data?.todayMortalityBirdsLedger ?? 0) > 0)
                        _stockLegendRow(
                          dot:   const Color(0xFF7F1D1D),
                          label: 'MORTALITY',
                          value: '${_data!.todayMortalityBirdsLedger}',
                        ),
                    ],
                  ),
                ),
              ],
            ),
            // Agent rows
            if (agents.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(color: kBorderLight, height: 1),
              const SizedBox(height: 12),
              ...agents.map(_agentOwnershipRow),
            ],
            // Today DC pill
            if ((_data?.todayDcCount ?? 0) > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color:        Colors.blue.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(kRadiusInner),
                  border:       Border.all(
                      color: Colors.blue.withValues(alpha: 0.15)),
                ),
                child: Row(children: [
                  const Icon(Icons.local_shipping_outlined,
                      size: 14, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    'Today DC: ${_data!.todayDcCount} challan(s)  ·  '
                        '${_data!.todayDcBirds} birds  ·  '
                        '${_data!.todayDcWeight.toStringAsFixed(0)} kg loaded',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.blue,
                        fontWeight: FontWeight.w600),
                  )),
                ]),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _stockLegendRow({
    required Color  dot,
    required String label,
    required String value,
    String?         sub,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Container(
              width: 10, height: 10,
              decoration: BoxDecoration(shape: BoxShape.circle, color: dot)),
          const SizedBox(width: 8),
          Expanded(child: Text(label,
              style: const TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700,
                  color: kTextHint, letterSpacing: 0.3))),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w900,
                    color: kNavy)),
            if (sub != null)
              Text(sub,
                  style: const TextStyle(fontSize: 9, color: kTextHint)),
          ]),
        ]),
      );

  // ── Financial Overview ────────────────────────────────────────────────────
  Widget _financialSection(String Function(String) t) {
    final d = _data;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Icon(Icons.account_balance_wallet_rounded,
                color: kGold, size: 18),
            SizedBox(width: 8),
            Text('FINANCIAL OVERVIEW',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w900,
                    color: kNavy, letterSpacing: 0.6)),
          ]),
        ),
        // Main highlight — navy gradient
        GestureDetector(
          onTap: () => context.go(R.ledger),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [kNavy, kNavyMid],
                begin:  Alignment.topLeft,
                end:    Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: kNavyMid),
            ),
            padding: const EdgeInsets.symmetric(
                horizontal: 22, vertical: 18),
            child: Row(
              children: [
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('TOTAL TO COLLECT',
                          style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w900,
                              color: Color(0xFFB4C6F4),
                              letterSpacing: 0.7)),
                      const SizedBox(height: 6),
                      Text(_fmt(d?.totalOutstanding),
                          style: const TextStyle(
                              fontSize: 34, fontWeight: FontWeight.w900,
                              color: kGoldLight,
                              letterSpacing: -0.5)),
                    ])),
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color:        Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.payments_rounded,
                      color: kGoldLight, size: 28),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Sub cards
        Row(children: [
          Expanded(child: GestureDetector(
            onTap: () => context.go(R.invoices),
            child: _finSubCard(
              label: "TODAY'S ${t('cash')}",
              value: _fmt(d?.todayCashCollected),
              barColor: kGoldLight,
            ),
          )),
          const SizedBox(width: 10),
          Expanded(child: _finSubCard(
            label: "TODAY'S ${t('upi')}",
            value: _fmt(d?.todayUpiCollected),
            barColor: const Color(0xFF7687B2),
          )),
        ]),
      ]),
    );
  }

  Widget _finSubCard({
    required String label,
    required String value,
    required Color  barColor,
  }) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color:        kSurface,
      borderRadius: BorderRadius.circular(kRadiusCard),
      border:       Border.all(color: kBorderLight.withValues(alpha: 0.5)),
      boxShadow:    kCardShadow,
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(
              fontSize: 9, fontWeight: FontWeight.w900,
              color: kTextHint, letterSpacing: 0.6)),
      const SizedBox(height: 6),
      Text(value,
          style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.w900,
              color: kNavy, letterSpacing: -0.3)),
      const SizedBox(height: 8),
      Container(height: 3, width: 32,
          decoration: BoxDecoration(
              color: barColor, borderRadius: BorderRadius.circular(99))),
    ]),
  );

  // ── Quick Actions ─────────────────────────────────────────────────────────
  Widget _qaSection(String Function(String) t) {
    final actions = _allActions(t);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 14),
          child: Row(children: [
            Icon(Icons.bolt_rounded, color: kGold, size: 18),
            SizedBox(width: 8),
            Text('QUICK ACTIONS',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w900,
                    color: kNavy, letterSpacing: 0.6)),
          ]),
        ),
        GridView.builder(
          shrinkWrap:    true,
          physics:       const NeverScrollableScrollPhysics(),
          gridDelegate:  const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:   2,
            mainAxisSpacing:  12,
            crossAxisSpacing: 12,
            childAspectRatio: 2.6,
          ),
          itemCount: actions.length,
          itemBuilder: (_, i) => _qaBtn(actions[i]),
        ),
      ]),
    );
  }

  // ── Agent Performance table ───────────────────────────────────────────────
  Widget _agentSection() {
    final agents = _data?.agentStatus ?? [];
    if (agents.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          color:        kSurface,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border:       Border.all(color: kBorderLight.withValues(alpha: 0.5)),
          boxShadow:    kCardShadow,
        ),
        child: Column(children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(children: [
              const Icon(Icons.groups_rounded, color: kGold, size: 18),
              const SizedBox(width: 8),
              const Text('AGENT PERFORMANCE',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w900,
                      color: kNavy, letterSpacing: 0.6)),
              const Spacer(),
              GestureDetector(
                onTap: () => context.go(R.shifts),
                child: const Text('VIEW ALL',
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w900,
                        color: kGold, letterSpacing: 0.5)),
              ),
            ]),
          ),
          // Column headers
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(children: const [
              Expanded(flex: 4, child: Text('AGENT NAME',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900,
                      color: kTextHint, letterSpacing: 0.8))),
              SizedBox(width: 60, child: Text('DC',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900,
                      color: kTextHint, letterSpacing: 0.8))),
              SizedBox(width: 60, child: Text('STOCK',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900,
                      color: kTextHint, letterSpacing: 0.8))),
            ]),
          ),
          const Divider(height: 1, color: kBorderLight, indent: 20, endIndent: 20),
          // Agent rows
          ...agents.asMap().entries.map((e) {
            final i = e.key;
            final a = e.value;
            return Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              decoration: BoxDecoration(
                border: i < agents.length - 1
                    ? Border(bottom: BorderSide(
                    color: kBorderLight.withValues(alpha: 0.5)))
                    : null,
              ),
              child: Row(children: [
                Expanded(flex: 4, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.agentName,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w900,
                              color: kNavy),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Row(children: [
                        Container(
                          width: 6, height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: a.hasOpenShift
                                ? const Color(0xFF22C55E) : kTextHint,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          a.hasOpenShift ? 'SHIFT OPEN' : 'CLOSED',
                          style: TextStyle(
                              fontSize: 9, fontWeight: FontWeight.w900,
                              color: a.hasOpenShift
                                  ? const Color(0xFF16A34A) : kTextHint,
                              letterSpacing: 0.4),
                        ),
                      ]),
                    ])),
                SizedBox(
                  width: 60,
                  child: Center(child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color:        a.todayDcBirds > 0
                          ? kGoldBg : kBgGrey,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      a.todayDcBirds > 0 ? 'MAIN' : 'NONE',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 8, fontWeight: FontWeight.w900,
                          color: a.todayDcBirds > 0
                              ? kWarning : kTextHint),
                    ),
                  )),
                ),
                SizedBox(
                  width: 60,
                  child: Text(
                    '${a.liveStockBirds}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w900,
                        color: a.liveStockBirds > 0
                            ? kNavy : kTextHint),
                  ),
                ),
              ]),
            );
          }),
        ]),
      ),
    );
  }

  // ── Reconciliation section ────────────────────────────────────────────────
  Widget _reconSection(String Function(String) t) {
    final d = _data;
    if (d == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          color:        kSurface,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border:       Border.all(color: kBorderLight.withValues(alpha: 0.5)),
          boxShadow:    kCardShadow,
        ),
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.balance_rounded, color: kGold, size: 18),
            SizedBox(width: 8),
            Text("TODAY'S RECONCILIATION",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900,
                    color: kNavy, letterSpacing: 0.6)),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            _reconStat('DC Loaded',
                '${d.todayDcWeight.toStringAsFixed(0)} kg', Colors.blue),
            _reconStat('Delivered',
                '${d.todayDeliveredKgLedger.toStringAsFixed(0)} kg',
                const Color(0xFF0D9488)),
            _reconStat('Mortality',
                '${d.todayMortalityBirdsLedger} birds', kError),
            _reconStat('Transfers',
                '${d.todayTransferredOutBirds} birds', Colors.indigo),
          ]),
          if (d.todayPendingShifts > 0) ...[
            const SizedBox(height: 12),
            _alertTile(
                '${d.todayPendingShifts} shift(s) pending — loss finalises after approval.',
                Colors.orange, Icons.pending_outlined),
          ],
          if (d.todayPendingShifts == 0 && d.todayApprovedLossKg > 0) ...[
            const SizedBox(height: 12),
            _alertTile(
                'Approved Loss: ${d.todayApprovedLossKg.toStringAsFixed(2)} kg '
                    '(${(d.todayDcWeight > 0 ? d.todayApprovedLossKg / d.todayDcWeight * 100 : 0).toStringAsFixed(1)}%)',
                kSuccess, Icons.verified_outlined),
          ],
          if (d.todayHighLossCount > 0 && d.todayPendingShifts == 0) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => context.go(R.dailyReport),
              child: _alertTile(
                  '${d.todayHighLossCount} batches with loss ≥ 2%',
                  kError, Icons.warning_amber_rounded),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _reconStat(String label, String value, Color color) => Expanded(
    child: Column(children: [
      Text(value,
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w900, color: color),
          textAlign: TextAlign.center),
      Text(label,
          style: const TextStyle(fontSize: 9, color: kTextHint),
          textAlign: TextAlign.center),
    ]),
  );

  // ── Returns section ───────────────────────────────────────────────────────
  Widget _returnsSection(String Function(String) t) {
    final d = _data;
    if (d == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          color:        kSurface,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border:       Border.all(color: kBorderLight.withValues(alpha: 0.5)),
          boxShadow:    kCardShadow,
        ),
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.assignment_return_rounded, color: kGold, size: 18),
            SizedBox(width: 8),
            Text('RETURNS',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900,
                    color: kNavy, letterSpacing: 0.6)),
          ]),
          if (d.todayReturnsBirds > 0) ...[
            const SizedBox(height: 12),
            _alertTile(
                '${d.todayReturnsBirds} birds '
                    '(${d.todayReturnsKg.toStringAsFixed(1)} kg) '
                    'returned to stock today ✓',
                Colors.purple, Icons.assignment_return_outlined),
          ],
          if (d.pendingReturns > 0) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => context.go(R.returns),
              child: _alertTile('${d.pendingReturns} pending returns',
                  Colors.orange, Icons.pending_outlined),
            ),
          ],
        ]),
      ),
    );
  }

  // ── All-clear / close day section ─────────────────────────────────────────
  Widget _allClearSection(String Function(String) t) {
    final d = _data;
    if (d == null) return const SizedBox.shrink();
    final clear = d.allClear;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          color:        kSurface,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border:       Border.all(
              color: (clear ? kSuccess : kWarning).withValues(alpha: 0.3)),
          boxShadow:    kCardShadow,
        ),
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          Icon(
            clear ? Icons.check_circle_outline : Icons.pending_actions_outlined,
            color: clear ? kSuccess : kWarning,
            size:  24,
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(
            clear
                ? 'All clear — ready to close day ✓'
                : '${d.pendingApprovals} approvals · '
                '${d.pendingReturns} returns pending',
            style: TextStyle(
                fontSize:   14,
                fontWeight: FontWeight.w800,
                color:      clear ? kSuccess : kWarning),
          )),
          if (clear)
            GestureDetector(
              onTap: () => context.go(R.dayClosure),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color:        kNavy,
                  borderRadius: BorderRadius.circular(kRadiusChip),
                ),
                child: const Text('Close Day',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800,
                        color: kGoldLight)),
              ),
            ),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DESKTOP — preserved exactly from original
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildDesktopLayout(dynamic user, String lang,
      String Function(String) t) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: kBgGrey,
        body: Center(child: SizedBox(
          width: 32, height: 32,
          child: CircularProgressIndicator(color: kPrimary, strokeWidth: 2.5),
        )),
      );
    }
    if (_error != null) {
      return Scaffold(backgroundColor: kBgGrey, body: _errorView());
    }
    final alerts = _buildAlerts(t);
    return Scaffold(
      backgroundColor: kBgGrey,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _desktopKpiStrip(t),
          const SizedBox(height: 16),
          if (alerts.isNotEmpty) ...[
            ...alerts,
            const SizedBox(height: 8),
          ],
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 5, child: Column(children: [
              _buildLiveStockCard(),
              const SizedBox(height: 12),
              if ((_data?.agentStatus ?? []).isNotEmpty)
                _buildAgentReconciliation(),
            ])),
            const SizedBox(width: 16),
            Expanded(flex: 4, child: Column(children: [
              if ((_data?.todayDelivered ?? 0) > 0) ...[
                _section("⚖️ Today's Reconciliation", [
                  Row(children: [
                    _stat2('DC Loaded',
                        '${(_data?.todayDcWeight ?? 0).toStringAsFixed(0)} kg',
                        Colors.blue),
                    _stat2('Delivered',
                        '${(_data?.todayDeliveredKgLedger ?? 0).toStringAsFixed(0)} kg',
                        Colors.teal),
                    _stat2('Mortality',
                        '${_data?.todayMortalityBirdsLedger ?? 0} birds',
                        Colors.red),
                    _stat2('Transfers',
                        '${_data?.todayTransferredOutBirds ?? 0} birds',
                        Colors.indigo),
                  ]),
                  if ((_data?.todayHighLossCount ?? 0) > 0 &&
                      (_data?.todayPendingShifts ?? 0) == 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _alertTile(
                          '${_data!.todayHighLossCount} batches with loss ≥ 2%',
                          Colors.red, Icons.warning_amber_rounded,
                          onTap: () => context.go(R.dailyReport)),
                    ),
                  if ((_data?.todayPendingShifts ?? 0) > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _alertTile(
                          '${_data!.todayPendingShifts} shift(s) pending — loss finalises after approval.',
                          Colors.orange, Icons.pending_outlined),
                    ),
                  if ((_data?.todayPendingShifts ?? 0) == 0 &&
                      (_data?.todayApprovedLossKg ?? 0) > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _alertTile(
                          'Approved Loss: ${_data!.todayApprovedLossKg.toStringAsFixed(2)} kg '
                              '(${(_data!.todayDcWeight > 0 ? (_data!.todayApprovedLossKg / _data!.todayDcWeight * 100) : 0).toStringAsFixed(1)}%)',
                          Colors.green, Icons.verified_outlined),
                    ),
                ]),
                const SizedBox(height: 12),
              ],
              _section('💰 Financial Overview', [
                Row(children: [
                  _kpi(t('outstanding'), _fmt(_data?.totalOutstanding),
                      Colors.orange, () => context.go(R.ledger)),
                  const SizedBox(width: 10),
                  _kpi('Today Collected', _fmt(_data?.todayCollected),
                      kPrimary, () => context.go(R.invoices)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _payRow(t('cash'),
                      _data?.todayCashCollected ?? 0, Colors.green)),
                  const SizedBox(width: 10),
                  Expanded(child: _payRow(t('upi'),
                      _data?.todayUpiCollected  ?? 0, Colors.blue)),
                ]),
              ]),
              const SizedBox(height: 12),
              _section('👤 Shifts Today', [
                Row(children: [
                  _stat2('Open', '${_data?.openShifts ?? 0}',
                      (_data?.openShifts ?? 0) == 0
                          ? Colors.green : Colors.orange),
                  _stat2('Agents',  '${_data?.activeAgents  ?? 0}', kPrimary),
                  _stat2('Batches', '${_data?.activeBatches ?? 0}', Colors.blue),
                ]),
                if ((_data?.openShifts ?? 0) > 0) ...[
                  const SizedBox(height: 8),
                  _alertTile('${_data?.openShifts} shift(s) still open',
                      Colors.orange, Icons.schedule_outlined,
                      onTap: () => context.go(R.shifts)),
                ],
              ]),
              const SizedBox(height: 12),
              if ((_data?.todayReturnsBirds ?? 0) > 0 ||
                  (_data?.pendingReturns ?? 0) > 0) ...[
                _section('↩️ Returns', [
                  if ((_data?.todayReturnsBirds ?? 0) > 0)
                    _alertTile(
                        '${_data!.todayReturnsBirds} birds '
                            '(${_data!.todayReturnsKg.toStringAsFixed(1)} kg) returned ✓',
                        Colors.purple, Icons.assignment_return_outlined),
                  if ((_data?.pendingReturns ?? 0) > 0) ...[
                    const SizedBox(height: 6),
                    _alertTile('${_data?.pendingReturns} pending returns',
                        Colors.orange, Icons.pending_outlined,
                        onTap: () => context.go(R.returns)),
                  ],
                ]),
                const SizedBox(height: 12),
              ],
              _section('✅ Reconciliation', [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (_data?.allClear ?? false)
                        ? Colors.green.shade50 : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(kRadiusInner),
                    border: Border.all(
                        color: (_data?.allClear ?? false)
                            ? Colors.green.shade200 : Colors.orange.shade200),
                  ),
                  child: Row(children: [
                    Icon(
                      (_data?.allClear ?? false)
                          ? Icons.check_circle_outline
                          : Icons.pending_actions_outlined,
                      color: (_data?.allClear ?? false)
                          ? Colors.green : Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      (_data?.allClear ?? false)
                          ? 'All clear — ready to close day ✓'
                          : '${_data?.pendingApprovals ?? 0} approvals · '
                          '${_data?.pendingReturns ?? 0} returns pending',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600,
                          color: (_data?.allClear ?? false)
                              ? Colors.green.shade700
                              : Colors.orange.shade800),
                    )),
                    if (_data?.allClear ?? false)
                      TextButton(
                          onPressed: () => context.go(R.dayClosure),
                          child: const Text('Close Day')),
                  ]),
                ),
              ]),
            ])),
          ]),
          const SizedBox(height: 16),
          _section('⚡ QUICK ACTIONS', [_qaGrid(_allActions(t))]),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SHARED LOGIC — preserved exactly from original
  // ══════════════════════════════════════════════════════════════════════════

  List<_QA> _allActions(String Function(String) t) => [
    _QA(Icons.add_circle,                      t('new_order'),  Colors.orange,   const Color(0xFFFFF7ED), () => context.go(R.orderCreate), wide: true),
    _QA(Icons.list_alt_outlined,               t('orders'),     Colors.blue,     const Color(0xFFEFF6FF), () => context.go(R.orders)),
    _QA(Icons.fact_check_rounded,              t('approve'),    kSuccess,        const Color(0xFFF0FDF4), () => context.go(R.approvals)),
    _QA(Icons.local_shipping_outlined,         t('dispatch'),   Colors.indigo,   const Color(0xFFEEF2FF), () => context.go(R.dispatch)),
    _QA(Icons.inventory_outlined,              t('add_stock'),  Colors.blue,     const Color(0xFFEFF6FF), () => context.go(R.stock)),
    _QA(Icons.account_balance_wallet_outlined, t('collect'),    Colors.purple,   const Color(0xFFFAF5FF), () => context.go(R.ledger)),
    _QA(Icons.receipt_long_outlined,           t('invoices'),   Colors.amber.shade800, const Color(0xFFFFFBEB), () => context.go(R.invoices)),
    _QA(Icons.price_change_outlined,           t('rate'),       const Color(0xFF0D9488), const Color(0xFFECFDF5), () => context.go(R.rates)),
    _QA(Icons.store_outlined,                  t('customers'),  const Color(0xFF0284C7), const Color(0xFFF0F9FF), () => context.go(R.retailers)),
    _QA(Icons.delivery_dining_outlined,        t('agents'),     const Color(0xFF57534E), const Color(0xFFFAFAF9), () => context.go(R.agents)),
    _QA(Icons.assignment_return_outlined,      t('returns'),    kError,          const Color(0xFFFEF2F2), () => context.go(R.returns)),
    _QA(Icons.schedule_outlined,               t('shifts'),     kTextSub,        const Color(0xFFF9FAFB), () => context.go(R.shifts)),
    _QA(Icons.account_balance_outlined,        t('reconcile'),  kSuccess,        const Color(0xFFF0FDF4), () => context.go(R.cashRecon)),
    _QA(Icons.lock_clock_outlined,             t('close_day'),  kError,          const Color(0xFFFEF2F2), () => context.go(R.dayClosure)),
    _QA(Icons.warning_amber_outlined,          t('alerts'),     Colors.orange,   const Color(0xFFFFFBEB), () => context.go(R.alerts)),
    _QA(Icons.summarize_outlined,              t('report'),     kNavy,           const Color(0xFFF8FAFC), () => context.go(R.dailyReport)),
  ];

  List<Widget> _buildAlerts(String Function(String) t) {
    final d   = _data;
    final out = <Widget>[];
    if (d == null) return out;
    void add(String msg, Color c, IconData icon, {VoidCallback? onTap}) =>
        out.add(_alertTile(msg, c, icon, onTap: onTap));
    if (d.isDayClosed)
      add('Day is closed. No new records.', Colors.grey, Icons.lock);
    if (d.remainingBirds < 0)
      add('CRITICAL: Negative stock! Check entries.', kError, Icons.error,
          onTap: () => context.go(R.stock));
    if (d.remainingBirds < 50 && d.stockBirds > 0)
      add('Low stock: only ${d.remainingBirds} birds remaining',
          Colors.orange, Icons.inventory_outlined,
          onTap: () => context.go(R.stock));
    if (d.pendingApprovals > 0)
      add('${d.pendingApprovals} deliveries need approval',
          Colors.orange, Icons.fact_check_outlined,
          onTap: () => context.go(R.approvals));
    return out;
  }

  // ── Desktop-only helpers (preserved exactly) ──────────────────────────────
  Widget _desktopKpiStrip(String Function(String) t) => Row(children: [
    Expanded(child: _desktopKpiCard(label: t('orders'),
        value: '${_data?.pendingOrders ?? 0}',
        icon: Icons.shopping_bag_outlined, color: Colors.orange,
        onTap: () => context.go(R.orders))),
    const SizedBox(width: 12),
    Expanded(child: _desktopKpiCard(label: t('dispatch'),
        value: '${_data?.activeDeliveries ?? 0}',
        icon: Icons.local_shipping_outlined, color: Colors.blue,
        onTap: () => context.go(R.dispatch))),
    const SizedBox(width: 12),
    Expanded(child: _desktopKpiCard(label: t('approve'),
        value: '${_data?.pendingApprovals ?? 0}',
        icon: Icons.fact_check_outlined,
        color: (_data?.pendingApprovals ?? 0) == 0 ? Colors.green : Colors.red,
        onTap: () => context.go(R.approvals))),
    const SizedBox(width: 12),
    Expanded(child: _desktopKpiCard(label: t('outstanding'),
        value: _fmt(_data?.totalOutstanding),
        icon: Icons.account_balance_wallet_outlined, color: Colors.orange,
        onTap: () => context.go(R.ledger))),
    const SizedBox(width: 12),
    Expanded(child: _desktopKpiCard(label: 'Today Collected',
        value: _fmt(_data?.todayCollected),
        icon: Icons.trending_up_rounded, color: kPrimary,
        onTap: () => context.go(R.invoices))),
  ]);

  Widget _desktopKpiCard({
    required String label, required String value,
    required IconData icon, required Color color,
    required VoidCallback onTap,
  }) => InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(kRadiusCard),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(color: kBorder),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(kRadiusChip)),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900,
                  color: color)),
              Text(label, style: const TextStyle(fontSize: 11, color: kTextSub),
                  overflow: TextOverflow.ellipsis),
            ])),
      ]),
    ),
  );

  Widget _buildLiveStockCard() {
    final agents  = _data?.agentStatus ?? [];
    if (_stock.isEmpty && agents.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(kRadiusCard),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8, offset: const Offset(0, 2))]),
        child: _alertTile('No stock recorded. Add opening stock or create a DC.',
            Colors.orange, Icons.warning_amber_rounded,
            onTap: () => context.go(R.stock)),
      );
    }
    final totalAgentBirds     = agents.fold(0, (s, a) => s + a.liveStockBirds);
    final pendingReturnAgents = agents
        .where((a) => a.liveStockBirds > 0 && !a.hasOpenShift).toList();
    final pendingDelCount = agents.fold(0, (s, a) => s + a.pendingDeliveries);
    return GestureDetector(
      onTap: () => context.push(R.stockDetail),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(kRadiusCard),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10, offset: const Offset(0, 3))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(children: [
              const Text('🐓 Live Stock Position',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                      color: kTextMain)),
              const Spacer(),
              const Row(children: [
                Text('Details', style: TextStyle(fontSize: 11, color: kPrimary,
                    fontWeight: FontWeight.w600)),
                Icon(Icons.chevron_right, color: kPrimary, size: 15),
              ]),
            ]),
          ),
          const SizedBox(height: 10),
          ..._stock.map((s) {
            final neg = s.isNegative;
            final low = s.hasLowStock;
            final c   = neg ? Colors.red : low ? Colors.orange : const Color(0xFF1B7A3E);
            final bg  = neg ? Colors.red.shade50 : low ? Colors.orange.shade50 : Colors.green.shade50;
            return Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: bg,
                    borderRadius: BorderRadius.circular(kRadiusInner),
                    border: Border.all(color: c.withValues(alpha: 0.25))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(child: Text(s.productName,
                            style: const TextStyle(fontSize: 11,
                                fontWeight: FontWeight.w600, color: kTextSub))),
                        _stockStatusBadge(s, pendingReturnAgents.isNotEmpty,
                            pendingDelCount),
                      ]),
                      const SizedBox(height: 6),
                      Text('${s.availableBirds} Birds  •  ${s.availableKg.toStringAsFixed(1)} kg',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
                              color: c, height: 1.0)),
                      const Text('Available now',
                          style: TextStyle(fontSize: 10, color: kTextSub)),
                      const SizedBox(height: 10),
                      Row(children: [
                        _metric('In-House',    '${s.inHouseBirds}',   'birds',
                            s.inHouseBirds > 0 ? Colors.teal : Colors.grey),
                        _metricDivider(),
                        _metric('With Agents', '${s.agentBirds}',     'birds',
                            s.agentBirds > 0 ? Colors.orange : Colors.green),
                        _metricDivider(),
                        _metric('Delivered',   '${s.totalOutBirds}',  'birds', kPrimary),
                        _metricDivider(),
                        _metric('DC Today',    '+${s.todayPurchased}','birds', Colors.blue),
                      ]),
                    ]),
              ),
            );
          }),
          if (agents.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 2, 14, 6),
              child: Row(children: [
                Icon(Icons.people_alt_outlined, size: 12, color: kTextHint),
                SizedBox(width: 4),
                Text('STOCK OWNERSHIP',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
                        color: kTextHint, letterSpacing: 0.7)),
              ]),
            ),
            ...agents.map(_agentOwnershipRow),
          ],
          if ((_data?.todayDcCount ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(kRadiusInner),
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.2))),
                child: Row(children: [
                  const Icon(Icons.local_shipping_outlined, size: 13,
                      color: Colors.blue),
                  const SizedBox(width: 6),
                  Expanded(child: Text(
                    'Today DC: ${_data!.todayDcCount} challan(s)  ·  '
                        '${_data!.todayDcBirds} birds  ·  '
                        '${_data!.todayDcWeight.toStringAsFixed(0)} kg loaded',
                    style: const TextStyle(fontSize: 11, color: Colors.blue,
                        fontWeight: FontWeight.w600),
                  )),
                ]),
              ),
            ),
          if (_stock.any((s) => s.isNegative))
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: _alertTile('NEGATIVE STOCK — check ledger entries!',
                  kError, Icons.error_outline,
                  onTap: () => context.go(R.stock)),
            ),
        ]),
      ),
    );
  }

  Widget _buildAgentReconciliation() {
    final agents = _data?.agentStatus ?? [];
    if (agents.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border: Border.all(color: kBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.07),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(kRadiusCard))),
          child: Row(children: [
            const Icon(Icons.people_outline, color: kPrimary, size: 18),
            const SizedBox(width: 8),
            const Expanded(child: Text('Agent Reconciliation Status',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                    color: kPrimary))),
            GestureDetector(
              onTap: () => context.go(R.shifts),
              child: const Row(children: [
                Text('View Shifts', style: TextStyle(fontSize: 11,
                    color: kPrimary, fontWeight: FontWeight.w600)),
                Icon(Icons.chevron_right, color: kPrimary, size: 16),
              ]),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: Row(children: const [
            Expanded(flex: 3, child: Text('Agent',
                style: TextStyle(fontSize: 9, color: kTextHint,
                    fontWeight: FontWeight.w700, letterSpacing: 0.5))),
            Expanded(flex: 2, child: Text('DC Today',
                style: TextStyle(fontSize: 9, color: kTextHint,
                    fontWeight: FontWeight.w700),
                textAlign: TextAlign.center)),
            Expanded(flex: 2, child: Text('Delivered',
                style: TextStyle(fontSize: 9, color: kTextHint,
                    fontWeight: FontWeight.w700),
                textAlign: TextAlign.center)),
            Expanded(flex: 2, child: Text('Live Stock',
                style: TextStyle(fontSize: 9, color: kTextHint,
                    fontWeight: FontWeight.w700),
                textAlign: TextAlign.center)),
            Expanded(flex: 2, child: Text('Pending',
                style: TextStyle(fontSize: 9, color: kTextHint,
                    fontWeight: FontWeight.w700),
                textAlign: TextAlign.center)),
          ]),
        ),
        const Divider(height: 1, indent: 14, endIndent: 14),
        ...agents.asMap().entries.map((e) {
          final i              = e.key;
          final a              = e.value;
          final hasPending     = a.pendingDeliveries > 0;
          final hasStock       = a.liveStockBirds > 0;
          final needsAttention = hasPending || (hasStock && !a.hasOpenShift);
          return Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            decoration: BoxDecoration(
                color: needsAttention ? Colors.orange.shade50 : Colors.transparent,
                border: i < agents.length - 1
                    ? const Border(bottom: BorderSide(color: kBorder, width: 0.5))
                    : null),
            child: Row(children: [
              Expanded(flex: 3, child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.agentName, style: const TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w700, color: kTextMain),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    Row(children: [
                      Container(width: 6, height: 6,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(shape: BoxShape.circle,
                              color: a.hasOpenShift ? Colors.green : Colors.grey)),
                      Text(a.hasOpenShift ? 'Shift Open' : 'Shift Closed',
                          style: TextStyle(fontSize: 9,
                              color: a.hasOpenShift ? Colors.green : kTextHint)),
                    ]),
                  ])),
              Expanded(flex: 2, child: Column(children: [
                Text('${a.todayDcBirds}', style: const TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w800, color: Colors.blue),
                    textAlign: TextAlign.center),
                Text('${a.todayDcKg.toStringAsFixed(0)} kg',
                    style: const TextStyle(fontSize: 9, color: kTextHint),
                    textAlign: TextAlign.center),
              ])),
              Expanded(flex: 2, child: Column(children: [
                Text('${a.todayDeliveredBirds}', style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800,
                    color: Colors.teal), textAlign: TextAlign.center),
                const Text('birds', style: TextStyle(fontSize: 9, color: kTextHint),
                    textAlign: TextAlign.center),
              ])),
              Expanded(flex: 2, child: Column(children: [
                Text('${a.liveStockBirds}', style: TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: a.liveStockBirds > 0 ? Colors.orange : Colors.green),
                    textAlign: TextAlign.center),
                Text('${a.liveStockKg.toStringAsFixed(0)} kg',
                    style: const TextStyle(fontSize: 9, color: kTextHint),
                    textAlign: TextAlign.center),
              ])),
              Expanded(flex: 2, child: Column(children: [
                Text('${a.pendingDeliveries}', style: TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: hasPending ? Colors.orange : Colors.green),
                    textAlign: TextAlign.center),
                const Text('orders', style: TextStyle(fontSize: 9, color: kTextHint),
                    textAlign: TextAlign.center),
              ])),
            ]),
          );
        }),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(
              color: Color(0xFFF8F9FA),
              borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(kRadiusCard))),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _agentSummary('Total DC',
                '${agents.fold(0, (s, a) => s + a.todayDcBirds)} birds',
                Colors.blue),
            _agentSummary('Total Delivered',
                '${agents.fold(0, (s, a) => s + a.todayDeliveredBirds)} birds',
                Colors.teal),
            _agentSummary('Live in Stock',
                '${agents.fold(0, (s, a) => s + a.liveStockBirds)} birds',
                agents.any((a) => a.liveStockBirds > 0)
                    ? Colors.orange : Colors.green),
            _agentSummary('Pending',
                '${agents.fold(0, (s, a) => s + a.pendingDeliveries)} orders',
                agents.any((a) => a.pendingDeliveries > 0)
                    ? Colors.orange : Colors.green),
          ]),
        ),
      ]),
    );
  }

  // ── Widget helpers (preserved exactly) ────────────────────────────────────
  Widget _section(String title, List<Widget> children) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(kRadiusCard),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8, offset: const Offset(0, 2))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 13,
          fontWeight: FontWeight.w800, color: kTextMain)),
      const SizedBox(height: 10),
      ...children,
    ]),
  );

  Widget _kpi(String label, String value, Color color, VoidCallback onTap) =>
      Expanded(child: InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(kRadiusInner),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(kRadiusInner),
              border: Border.all(color: color.withValues(alpha: 0.2))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: TextStyle(fontSize: 22,
                fontWeight: FontWeight.w900, color: color)),
            Text(label, style: const TextStyle(fontSize: 11, color: kTextSub)),
          ]),
        ),
      ));

  Widget _stat2(String l, String v, Color c) => Expanded(child:
  Column(children: [
    Text(v, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
        color: c)),
    Text(l, style: const TextStyle(fontSize: 10, color: kTextHint)),
  ]));

  Widget _payRow(String label, double amount, Color color) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(kRadiusInner),
        border: Border.all(color: color.withValues(alpha: 0.2))),
    child: Row(children: [
      Icon(Icons.currency_rupee, color: color, size: 14),
      const SizedBox(width: 4),
      Expanded(child: Text(label,
          style: TextStyle(fontSize: 11, color: color))),
      Text(_fmt(amount),
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
              color: color)),
    ]),
  );

  Widget _alertTile(String msg, Color color, IconData icon,
      {VoidCallback? onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color:        color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(kRadiusInner),
              border:       Border.all(color: color.withValues(alpha: 0.3))),
          child: Row(children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(msg,
                style: TextStyle(fontSize: 12, color: color,
                    fontWeight: FontWeight.w600))),
            if (onTap != null)
              Icon(Icons.chevron_right, color: color, size: 16),
          ]),
        ),
      );

  Widget _errorView() => Center(child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.cloud_off_outlined, size: 48, color: kTextHint),
      const SizedBox(height: 12),
      Text(_error ?? 'Error',
          style: const TextStyle(color: kTextSub, fontSize: 13),
          textAlign: TextAlign.center),
      const SizedBox(height: 16),
      ElevatedButton(onPressed: _load, child: const Text('Retry')),
    ]),
  ));

  Widget _stockStatusBadge(StockPosition s, bool hasPendingReturn, int pendingDel) {
    final String label;
    final Color  c;
    final IconData ic;
    if (s.isNegative) {
      label = 'MISMATCH'; c = Colors.red; ic = Icons.error_outline;
    } else if (hasPendingReturn) {
      label = 'RETURN PENDING'; c = Colors.red; ic = Icons.warning_amber_rounded;
    } else if (pendingDel > 0) {
      label = 'PENDING APPRVL'; c = Colors.orange; ic = Icons.pending_outlined;
    } else if (s.hasLowStock) {
      label = 'LOW STOCK'; c = Colors.orange; ic = Icons.inventory_outlined;
    } else {
      label = 'BALANCED'; c = Colors.green; ic = Icons.check_circle_outline;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(kRadiusInner),
          border: Border.all(color: c.withValues(alpha: 0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ic, color: c, size: 10),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
            color: c, letterSpacing: 0.3)),
      ]),
    );
  }

  Widget _metric(String label, String value, String unit, Color c) =>
      Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900,
                color: c), textAlign: TextAlign.center),
            Text(unit, style: const TextStyle(fontSize: 8, color: kTextSub),
                textAlign: TextAlign.center),
            const SizedBox(height: 1),
            Text(label, style: const TextStyle(fontSize: 8, color: kTextHint,
                height: 1.2), textAlign: TextAlign.center, maxLines: 2),
          ]));

  Widget _metricDivider() => Container(
      width: 1, height: 32, color: kBorder,
      margin: const EdgeInsets.symmetric(horizontal: 2));

  Widget _agentOwnershipRow(AgentStockStatus a) {
    final hasStock  = a.liveStockBirds > 0;
    final shiftOpen = a.hasOpenShift;
    final Color dotColor = hasStock && !shiftOpen ? Colors.red
        : a.pendingDeliveries > 0 ? Colors.orange
        : hasStock ? Colors.blue : Colors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 7),
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: kBorderLight, width: 0.5))),
      child: Row(children: [
        Container(width: 7, height: 7,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(shape: BoxShape.circle,
                color: shiftOpen ? Colors.green : Colors.grey.shade400)),
        Expanded(child: Text(a.agentName,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                color: kTextMain))),
        Text(
          hasStock
              ? '${a.liveStockBirds} birds  ·  ${a.liveStockKg.toStringAsFixed(0)} kg'
              : '—',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
              color: hasStock ? dotColor : Colors.green),
        ),
        const SizedBox(width: 8),
        Container(width: 6, height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor)),
      ]),
    );
  }

  Widget _agentSummary(String l, String v, Color c) => Column(children: [
    Text(v, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c)),
    Text(l, style: const TextStyle(fontSize: 9, color: kTextHint)),
  ]);

  // Premium mobile quick action button — color-coded pill
  Widget _qaBtn(_QA a) => InkWell(
    onTap:        a.onTap,
    borderRadius: BorderRadius.circular(kRadiusCard),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color:        a.bg,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border:       Border.all(
            color: a.color.withValues(alpha: 0.15), width: 0.8),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color:        kSurface,
            borderRadius: BorderRadius.circular(kRadiusChip),
            boxShadow: [BoxShadow(
                color:      a.color.withValues(alpha: 0.15),
                blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Icon(a.icon, size: 20, color: a.color),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(a.label,
            style: TextStyle(
                fontSize:   12,
                fontWeight: FontWeight.w900,
                color:      a.color,
                letterSpacing: -0.2),
            maxLines:  1,
            overflow:  TextOverflow.ellipsis)),
      ]),
    ),
  );

  // Desktop QA grid (preserved exactly)
  Widget _qaGrid(List<_QA> actions) {
    final rows = <Widget>[];
    int i = 0;
    while (i < actions.length) {
      final a = actions[i];
      if (a.wide && i + 1 < actions.length) {
        rows.add(Row(children: [
          Expanded(flex: 2, child: _qaBtn(a)),
          const SizedBox(width: 8),
          Expanded(child: _qaBtn(actions[i + 1])),
        ]));
        i += 2;
      } else {
        final count = (i + 3 <= actions.length) ? 3 : actions.length - i;
        final row   = actions.sublist(i, i + count);
        rows.add(Row(children: [
          for (int j = 0; j < row.length; j++) ...[
            if (j > 0) const SizedBox(width: 8),
            Expanded(child: _qaBtn(row[j])),
          ],
        ]));
        i += count;
      }
      if (i < actions.length) rows.add(const SizedBox(height: 8));
    }
    return Column(children: rows);
  }

  String _initials(String? name) {
    if (name == null || name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    return parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : name[0].toUpperCase();
  }

  String _fmt(double? v) => v == null ? '₹0' : Fmt.amount(v);
}

// ── Donut ring painter ────────────────────────────────────────────────────────
class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.fraction,
    required this.ringColor,
    required this.trackColor,
    required this.strokeWidth,
  });
  final double fraction;
  final Color  ringColor;
  final Color  trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final paint  = Paint()
      ..style     = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Track
    paint.color = trackColor;
    canvas.drawCircle(center, radius, paint);

    // Fill
    paint.color = ringColor;
    final sweep = 2 * 3.14159 * fraction.clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0, sweep, false, paint,
    );
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.fraction != fraction || old.ringColor != ringColor;
}