import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/dashboard_models.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

final langProvider = StateProvider<String>((ref) => 'en');

class _L {
  static String g(String lang, String k) => _t[lang]?[k] ?? _t['en']![k] ?? k;
  static const _t = {
    'en': {
      'today':'Today Overview','new_order':'New Order','orders':'Orders',
      'approve':'Approve','dispatch':'Dispatch','collect':'Collect Cash',
      'customers':'Customers','agents':'Agents','rate':'Set Rate','returns':'Returns',
      'reconcile':'Check Cash','close_day':'Close Day','alerts':'Alerts',
      'report':'Report','crates':'Crates','invoices':'Bills','shifts':'Shifts',
      'stock_in':'Purchased','delivered':'Delivered','returned':'Returns',
      'remaining':'Remaining','add_stock':'Add Stock','outstanding':'To Collect',
      'cash':'Cash','upi':'UPI',
    },
    'ta': {
      'today':'இன்றைய நிலை','new_order':'புது ஆர்டர்','orders':'ஆர்டர்',
      'approve':'அனுமதி','dispatch':'அனுப்பு','collect':'பணம் வசூல்',
      'customers':'வாடிக்கையாளர்','agents':'ஏஜெண்ட்','rate':'விலை','returns':'திருப்பம்',
      'reconcile':'கேஷ் சரிபார்','close_day':'நாள் முடி','alerts':'எச்சரிக்கை',
      'report':'அறிக்கை','crates':'கிரேட்','invoices':'பில்','shifts':'ஷிஃப்ட்',
      'stock_in':'வாங்கியது','delivered':'டெலிவரி','returned':'திருப்பம்',
      'remaining':'மீதம்','add_stock':'கோழி சேர்','outstanding':'வசூல் செய்ய',
      'cash':'கேஷ்','upi':'UPI',
    },
  };
}

// Top-level model — not nested inside a class
class _QA {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool wide;
  const _QA(this.icon, this.label, this.color, this.onTap, {this.wide = false});
}

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  DashboardData? _data;
  List<StockPosition> _stock = [];
  bool _loading = true;
  String? _error;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null || !mounted) return;
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final dashRes   = await Supabase.instance.client.rpc('dashboard_summary',   params: {'p_trader_id': tid});
      final stockRes  = await Supabase.instance.client.rpc('get_available_stock', params: {'p_trader_id': tid});
      if (!mounted) return;
      final dashMap   = dashRes  as Map<String,dynamic>?;
      final stockList = stockRes as List?;
      if (!mounted) return;
      if (mounted) setState(() {
        _data  = dashMap  != null ? DashboardData.fromMap(dashMap) : const DashboardData();
        _stock = (stockList ?? []).map((s) => StockPosition.fromMap(s as Map<String,dynamic>)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (mounted) setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(appUserProvider).valueOrNull;
    final lang = ref.watch(langProvider);
    final t    = (String k) => _L.g(lang, k);

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F0),
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(user?.companyName ?? 'Dashboard',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          Text(t('today'),
              style: const TextStyle(fontSize: 11, color: kTextHint, fontWeight: FontWeight.w400)),
        ]),
        actions: [
          GestureDetector(
            onTap: () => ref.read(langProvider.notifier).state = lang == 'en' ? 'ta' : 'en',
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: kPrimary.withValues(alpha: 0.3))),
              child: Text(lang == 'en' ? 'தமிழ்' : 'EN',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kPrimary)))),
          if ((_data?.unreadAlerts ?? 0) > 0)
            Stack(children: [
              IconButton(icon: const Icon(Icons.notifications_outlined), onPressed: () => context.go(R.alerts)),
              Positioned(right: 8, top: 8, child: Container(width: 8, height: 8,
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle))),
            ])
          else
            IconButton(icon: const Icon(Icons.notifications_outlined), onPressed: () => context.go(R.alerts)),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading ? const LoadingList()
          : _error != null ? _errorView()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(12), children: [
                ..._buildAlerts(t),
                _section('📦 Live Deliveries', [
                  Row(children: [
                    _kpi(t('orders'),   '${_data?.pendingOrders ?? 0}',   Colors.orange, () => context.go(R.orders)),
                    const SizedBox(width: 10),
                    _kpi(t('dispatch'), '${_data?.activeDeliveries ?? 0}', Colors.blue,  () => context.go(R.dispatch)),
                    const SizedBox(width: 10),
                    _kpi(t('approve'),  '${_data?.pendingApprovals ?? 0}',
                        (_data?.pendingApprovals ?? 0) == 0 ? Colors.green : Colors.red,
                        () => context.go(R.approvals)),
                  ]),
                ]),
                // ── LIVE STOCK CARD — enhanced, clean, glanceable ──────────────
                // Tap opens stock_detail_screen with full reconciliation drill-down
                _buildLiveStockCard(),
                // Today's DC is now inside the Live Stock card — removed as separate section
                // High loss alert section
                // LOSS SUMMARY — only meaningful AFTER shift approval
                // Per-delivery loss is inflated (full batch DC ÷ one delivery).
                // Real authoritative loss = approve_shift formula from batch_loss_summary.
                // We show: APPROVED loss (real) + advisory pending note.
                if ((_data?.todayDelivered ?? 0) > 0)
                  _section('⚖️ Today\'s Reconciliation', [
                    // Show stock-ledger derived today's flow — authoritative
                    Row(children: [
                      _stat2('DC Loaded', '${(_data?.todayDcWeight ?? 0).toStringAsFixed(0)} kg',   Colors.blue),
                      _stat2('Delivered', '${(_data?.todayDeliveredKgLedger ?? 0).toStringAsFixed(0)} kg', Colors.teal),
                      _stat2('Mortality', '${_data?.todayMortalityBirdsLedger ?? 0} birds',          Colors.red),
                      _stat2('Transfers Out', '${_data?.todayTransferredOutBirds ?? 0} birds',       Colors.indigo),
                    ]),
                    const SizedBox(height: 6),
                    // Show APPROVED loss (real, from batch_loss_summary)
                    if ((_data?.todayHighLossCount ?? 0) > 0 && (_data?.todayPendingShifts ?? 0) == 0) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: _alertTile(
                          '⚠️ ${_data!.todayHighLossCount} batches with loss ≥ 2% after approval',
                          Colors.red, Icons.warning_amber_rounded,
                          onTap: () => context.go(R.dailyReport))),
                    ],
                    // If shifts are pending approval — loss not yet final
                    if ((_data?.todayPendingShifts ?? 0) > 0) Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                        child: Row(children: [
                          const Icon(Icons.pending_outlined, color: Colors.orange, size: 13),
                          const SizedBox(width: 6),
                          Expanded(child: Text(
                            '${_data!.todayPendingShifts} shift(s) pending approval — final loss will be confirmed after approval.',
                            style: const TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.w600))),
                        ]))),
                    if ((_data?.todayPendingShifts ?? 0) == 0 &&
                        (_data?.todayApprovedLossKg ?? 0) > 0) Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                        child: Row(children: [
                          const Icon(Icons.verified_outlined, color: Colors.green, size: 13),
                          const SizedBox(width: 6),
                          Expanded(child: Text(
                            'Approved Loss: ${(_data!.todayApprovedLossKg).toStringAsFixed(2)} kg '
                            '(${(_data!.todayDcWeight > 0 ? (_data!.todayApprovedLossKg / _data!.todayDcWeight * 100) : 0).toStringAsFixed(1)}%)',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.green))),
                        ]))),
                  ]),
                _section('💰 Financial Overview', [
                  Row(children: [
                    _kpi(t('outstanding'), _fmt(_data?.totalOutstanding), Colors.orange, () => context.go(R.ledger)),
                    const SizedBox(width: 10),
                    _kpi('Today Collected', _fmt(_data?.todayCollected),   kPrimary,      () => context.go(R.invoices)),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _payRow(t('cash'), _data?.todayCashCollected ?? 0, Colors.green)),
                    const SizedBox(width: 10),
                    Expanded(child: _payRow(t('upi'),  _data?.todayUpiCollected  ?? 0, Colors.blue)),
                  ]),
                ]),
                _section('👤 Shifts Today', [
                  Row(children: [
                    _stat2('Open',   '${_data?.openShifts ?? 0}',  (_data?.openShifts ?? 0) == 0 ? Colors.green : Colors.orange),
                    _stat2('Agents', '${_data?.activeAgents ?? 0}', kPrimary),
                    _stat2('Batches','${_data?.activeBatches ?? 0}', Colors.blue),
                  ]),
                  if ((_data?.openShifts ?? 0) > 0) ...[
                    const SizedBox(height: 8),
                    _alertTile('${_data?.openShifts} shift(s) still open', Colors.orange,
                        Icons.schedule_outlined, onTap: () => context.go(R.shifts)),
                  ],
                ]),

                // ── AGENT RECONCILIATION STATUS (new section) ─────────────────
                // Shows per-agent: loaded today / live stock / pending deliveries
                // This is the key fraud-control view for the trader
                if ((_data?.agentStatus ?? []).isNotEmpty)
                  _buildAgentReconciliation(),
                if ((_data?.todayReturnsBirds ?? 0) > 0 || (_data?.pendingReturns ?? 0) > 0)
                  _section('↩️ Returns', [
                    if ((_data?.todayReturnsBirds ?? 0) > 0)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.purple.shade200)),
                        child: Row(children: [
                          Icon(Icons.assignment_return_outlined, color: Colors.purple.shade600, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(
                            '${_data!.todayReturnsBirds} birds (${_data!.todayReturnsKg.toStringAsFixed(1)} kg) returned to stock today ✓',
                            style: TextStyle(fontSize: 12, color: Colors.purple.shade700, fontWeight: FontWeight.w600))),
                        ])),
                    if ((_data?.pendingReturns ?? 0) > 0) ...[
                      const SizedBox(height: 6),
                      _alertTile('${_data?.pendingReturns} pending returns', Colors.orange,
                          Icons.pending_outlined, onTap: () => context.go(R.returns)),
                    ],
                  ]),
                _section('✅ Reconciliation', [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (_data?.allClear ?? false) ? Colors.green.shade50 : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: (_data?.allClear ?? false) ? Colors.green.shade200 : Colors.orange.shade200)),
                    child: Row(children: [
                      Icon((_data?.allClear ?? false) ? Icons.check_circle_outline : Icons.pending_actions_outlined,
                          color: (_data?.allClear ?? false) ? Colors.green : Colors.orange, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Text(
                        (_data?.allClear ?? false)
                            ? 'All clear — ready to close day ✓'
                            : '${_data?.pendingApprovals ?? 0} approvals · ${_data?.pendingReturns ?? 0} returns pending',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                            color: (_data?.allClear ?? false) ? Colors.green.shade700 : Colors.orange.shade800))),
                      if (_data?.allClear ?? false)
                        TextButton(onPressed: () => context.go(R.dayClosure), child: const Text('Close Day')),
                    ])),
                ]),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text('⚡ QUICK ACTIONS',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: Colors.grey.shade500, letterSpacing: 0.8))),
                _qaGrid([
                  _QA(Icons.add_circle,                          t('new_order'),  Colors.green,    () => context.go(R.orderCreate), wide: true),
                  _QA(Icons.list_alt_outlined,                   t('orders'),     Colors.blue,     () => context.go(R.orders)),
                  _QA(Icons.fact_check_rounded,                  t('approve'),    Colors.orange,   () => context.go(R.approvals)),
                  _QA(Icons.local_shipping_outlined,             t('dispatch'),   kPrimary,        () => context.go(R.dispatch)),
                  _QA(Icons.inventory_outlined,                  t('add_stock'),  Colors.teal,     () => context.go(R.stock)),
                  _QA(Icons.account_balance_wallet_outlined,     t('collect'),    Colors.purple,   () => context.go(R.ledger)),
                  _QA(Icons.receipt_long_outlined,               t('invoices'),   Colors.indigo,   () => context.go(R.invoices)),
                  _QA(Icons.price_change_outlined,               t('rate'),       Colors.cyan,     () => context.go(R.rates)),
                  _QA(Icons.store_outlined,                      t('customers'),  Colors.brown,    () => context.go(R.retailers)),
                  _QA(Icons.delivery_dining_outlined,            t('agents'),     Colors.blueGrey, () => context.go(R.agents)),
                  _QA(Icons.assignment_return_outlined,          t('returns'),    Colors.red,      () => context.go(R.returns)),
                  _QA(Icons.schedule_outlined,                   t('shifts'),     Colors.indigo,   () => context.go(R.shifts)),
                  _QA(Icons.account_balance_outlined,            t('reconcile'),  Colors.green,    () => context.go(R.cashRecon)),
                  _QA(Icons.lock_clock_outlined,                 t('close_day'),  Colors.red,      () => context.go(R.dayClosure)),
                  _QA(Icons.warning_amber_outlined,              t('alerts'),     Colors.orange,   () => context.go(R.alerts)),
                  _QA(Icons.summarize_outlined,                  t('report'),     kPrimary,        () => context.go(R.dailyReport)),
                ]),
                const SizedBox(height: 20),
              ])),
    );
  }

  List<Widget> _buildAlerts(String Function(String) t) {
    final d = _data;
    final out = <Widget>[];
    if (d == null) return out;
    void add(String msg, Color c, IconData icon, {VoidCallback? onTap}) =>
        out.add(Padding(padding: const EdgeInsets.only(bottom: 8),
            child: _alertTile(msg, c, icon, onTap: onTap)));
    if (d.isDayClosed) add('Day is closed. No new records.', Colors.grey, Icons.lock);
    if (d.remainingBirds < 0) add('CRITICAL: Negative stock! Check entries.', Colors.red, Icons.error, onTap: () => context.go(R.stock));
    if (d.remainingBirds < 50 && d.stockBirds > 0) add('Low stock: only ${d.remainingBirds} birds remaining', Colors.orange, Icons.inventory_outlined, onTap: () => context.go(R.stock));
    if (d.pendingApprovals > 0) add('${d.pendingApprovals} deliveries need approval', Colors.orange, Icons.fact_check_outlined, onTap: () => context.go(R.approvals));
    return out;
  }

  Widget _section(String title, List<Widget> children) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0,2))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kTextMain)),
      const SizedBox(height: 10),
      ...children,
    ]));

  Widget _kpi(String label, String value, Color color, VoidCallback onTap) =>
      Expanded(child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(10),
          child: Container(padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withValues(alpha: 0.2))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
                Text(label, style: const TextStyle(fontSize: 11, color: kTextSub)),
              ]))));

  // ─────────────────────────────────────────────────────────────────────────
  // LIVE STOCK CARD  (dashboard card — lightweight, glanceable, operational)
  // Tap → StockDetailScreen for full reconciliation drill-down.
  // Design rules:
  //   PRIMARY  : Available now (birds + kg)   — large, immediate
  //   SECONDARY: Loaded / Delivered / With Agents / Pending Return
  //   BADGE    : Balanced / Return Pending / Pending Approval / Low Stock / Mismatch
  //   AGENTS   : compact one-line ownership rows (who holds what)
  //   TODAY DC : tucked pill at bottom
  //   NO formulas, NO loss math, NO transfers detail — all in detail screen
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildLiveStockCard() {
    final agents = _data?.agentStatus ?? [];

    if (_stock.isEmpty && agents.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))]),
        child: _alertTile('No stock recorded. Add opening stock or create a DC.',
            Colors.orange, Icons.warning_amber_rounded, onTap: () => context.go(R.stock)));
    }

    final totalAgentBirds   = agents.fold(0,   (s, a) => s + a.liveStockBirds);
    final pendingReturnAgents = agents.where((a) => a.liveStockBirds > 0 && !a.hasOpenShift).toList();
    final pendingDelCount   = agents.fold(0,   (s, a) => s + a.pendingDeliveries);

    return GestureDetector(
      onTap: () => context.push(R.stockDetail),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10, offset: const Offset(0, 3))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── CARD HEADER ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(children: [
              const Text('🐓 Live Stock Position',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kTextMain)),
              const Spacer(),
              const Row(children: [
                Text('Details', style: TextStyle(fontSize: 11, color: kPrimary, fontWeight: FontWeight.w600)),
                Icon(Icons.chevron_right, color: kPrimary, size: 15),
              ]),
            ])),
          const SizedBox(height: 10),

          // ── PRIMARY METRIC per product ────────────────────────────────────
          ..._stock.map((s) {
            final neg = s.isNegative;
            final low = s.hasLowStock;
            final c   = neg ? Colors.red : low ? Colors.orange : const Color(0xFF1B7A3E);
            final bg  = neg ? Colors.red.shade50 : low ? Colors.orange.shade50 : Colors.green.shade50;

            return Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.withValues(alpha: 0.25))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Product name + status badge
                  Row(children: [
                    Expanded(child: Text(s.productName,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: kTextSub))),
                    _stockStatusBadge(
                        s, pendingReturnAgents.isNotEmpty, pendingDelCount),
                  ]),
                  const SizedBox(height: 6),

                  // PRIMARY: available now — the only number that matters at a glance
                  Text('${s.availableBirds} Birds  •  ${s.availableKg.toStringAsFixed(1)} kg',
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w900,
                          color: c, height: 1.0)),
                  const Text('Available now',
                      style: TextStyle(fontSize: 10, color: kTextSub)),
                  const SizedBox(height: 10),

                  // SECONDARY: 4 operational metrics
                  Row(children: [
                    _metric('Loaded Today',    '+${s.todayPurchased}', 'birds', Colors.blue),
                    _metricDivider(),
                    _metric('Delivered',        '${s.todayDelivered}', 'birds', kPrimary),
                    _metricDivider(),
                    _metric('With Agents',      '$totalAgentBirds',    'birds',
                        totalAgentBirds > 0 ? Colors.orange : Colors.green),
                    _metricDivider(),
                    _metric('Return Pending',
                        '${pendingReturnAgents.length}', 'agents',
                        pendingReturnAgents.isNotEmpty ? Colors.red : Colors.green),
                  ]),
                ])));
          }),

          // ── AGENT OWNERSHIP — one compact row per agent ───────────────────
          if (agents.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 2, 14, 6),
              child: Row(children: [
                Icon(Icons.people_alt_outlined, size: 12, color: kTextHint),
                SizedBox(width: 4),
                Text('STOCK OWNERSHIP',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
                        color: kTextHint, letterSpacing: 0.7)),
              ])),
            ...agents.map(_agentOwnershipRow),
          ],

          // ── TODAY DC pill ─────────────────────────────────────────────────
          if ((_data?.todayDcCount ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.2))),
                child: Row(children: [
                  const Icon(Icons.local_shipping_outlined, size: 13, color: Colors.blue),
                  const SizedBox(width: 6),
                  Expanded(child: Text(
                      'Today DC: ${_data!.todayDcCount} challan(s)  ·  '
                      '${_data!.todayDcBirds} birds  ·  '
                      '${_data!.todayDcWeight.toStringAsFixed(0)} kg loaded',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.blue,
                          fontWeight: FontWeight.w600))),
                ]))),

          // ── NEGATIVE STOCK ALERT ──────────────────────────────────────────
          if (_stock.any((s) => s.isNegative))
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: _alertTile('NEGATIVE STOCK — check ledger entries!',
                  Colors.red, Icons.error_outline,
                  onTap: () => context.go(R.stock))),
        ])));
  }

  // Status badge: single most important operational state
  Widget _stockStatusBadge(
      StockPosition s, bool hasPendingReturn, int pendingDel) {
    final String label;
    final Color  c;
    final IconData ic;

    if (s.isNegative) {
      label='MISMATCH';        c=Colors.red;    ic=Icons.error_outline;
    } else if (hasPendingReturn) {
      label='RETURN PENDING';  c=Colors.red;    ic=Icons.warning_amber_rounded;
    } else if (pendingDel > 0) {
      label='PENDING APPRVL';  c=Colors.orange; ic=Icons.pending_outlined;
    } else if (s.hasLowStock) {
      label='LOW STOCK';       c=Colors.orange; ic=Icons.inventory_outlined;
    } else {
      label='BALANCED';        c=Colors.green;  ic=Icons.check_circle_outline;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color:  c.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: c.withValues(alpha: 0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ic, color: c, size: 10),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
                color: c, letterSpacing: 0.3)),
      ]));
  }

  // One secondary metric cell
  Widget _metric(String label, String value, String unit, Color c) =>
      Expanded(child: Column(
          mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(value,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: c),
            textAlign: TextAlign.center),
        Text(unit,
            style: const TextStyle(fontSize: 8, color: kTextSub),
            textAlign: TextAlign.center),
        const SizedBox(height: 1),
        Text(label,
            style: const TextStyle(fontSize: 8, color: kTextHint, height: 1.2),
            textAlign: TextAlign.center, maxLines: 2),
      ]));

  Widget _metricDivider() => Container(
      width: 1, height: 32, color: kBorder,
      margin: const EdgeInsets.symmetric(horizontal: 2));

  // Compact agent ownership row
  Widget _agentOwnershipRow(AgentStockStatus a) {
    final hasStock  = a.liveStockBirds > 0;
    final shiftOpen = a.hasOpenShift;
    final Color dotColor = hasStock && !shiftOpen
        ? Colors.red
        : a.pendingDeliveries > 0
            ? Colors.orange
            : hasStock
                ? Colors.blue
                : Colors.green;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: kBorder, width: 0.5))),
      child: Row(children: [
        // Shift status dot
        Container(
            width: 7, height: 7,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: shiftOpen ? Colors.green : Colors.grey.shade400)),
        // Name
        Expanded(child: Text(a.agentName,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: kTextMain))),
        // Stock in hand
        Text(
          hasStock
              ? '${a.liveStockBirds} birds  ·  ${a.liveStockKg.toStringAsFixed(0)} kg'
              : '—',
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700,
              color: hasStock ? dotColor : Colors.green)),
        const SizedBox(width: 8),
        // Colour dot (status indicator)
        Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: dotColor)),
      ]));
  }

  // ── AGENT RECONCILIATION STATUS ─────────────────────────────────────────────
  // Shows every active agent with:
  //   - Today's DC loaded (birds picked up from farm today)
  //   - Delivered today (from stock_ledger)
  //   - Live stock in hand right now
  //   - Pending deliveries count
  //   - Shift open/closed status
  // This is the primary fraud-control view at the trader level.
  Widget _buildAgentReconciliation() {
    final agents = _data?.agentStatus ?? [];
    if (agents.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.07),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13))),
          child: Row(children: [
            const Icon(Icons.people_outline, color: kPrimary, size: 18),
            const SizedBox(width: 8),
            const Expanded(child: Text('Agent Reconciliation Status',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kPrimary))),
            GestureDetector(
              onTap: () => context.go(R.shifts),
              child: const Row(children: [
                Text('View Shifts', style: TextStyle(fontSize: 11, color: kPrimary, fontWeight: FontWeight.w600)),
                Icon(Icons.chevron_right, color: kPrimary, size: 16),
              ])),
          ])),
        // Column headers
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: Row(children: [
            const Expanded(flex: 3, child: Text('Agent', style: TextStyle(fontSize: 9, color: kTextHint, fontWeight: FontWeight.w700, letterSpacing: 0.5))),
            const Expanded(flex: 2, child: Text('DC Today', style: TextStyle(fontSize: 9, color: kTextHint, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
            const Expanded(flex: 2, child: Text('Delivered', style: TextStyle(fontSize: 9, color: kTextHint, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
            const Expanded(flex: 2, child: Text('Live Stock', style: TextStyle(fontSize: 9, color: kTextHint, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
            const Expanded(flex: 2, child: Text('Pending', style: TextStyle(fontSize: 9, color: kTextHint, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
          ])),
        const Divider(height: 1, indent: 14, endIndent: 14),
        // Agent rows
        ...agents.asMap().entries.map((e) {
          final i = e.key;
          final a = e.value;
          final hasPending  = a.pendingDeliveries > 0;
          final hasStock    = a.liveStockBirds > 0;
          final needsAttention = hasPending || (hasStock && !a.hasOpenShift);
          return Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            decoration: BoxDecoration(
                color: needsAttention ? Colors.orange.shade50 : Colors.transparent,
                border: i < agents.length - 1
                    ? const Border(bottom: BorderSide(color: kBorder, width: 0.5))
                    : null),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              // Agent name + shift status
              Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.agentName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kTextMain),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Row(children: [
                  Container(
                    width: 6, height: 6, margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: a.hasOpenShift ? Colors.green : Colors.grey)),
                  Text(a.hasOpenShift ? 'Shift Open' : 'Shift Closed',
                      style: TextStyle(fontSize: 9, color: a.hasOpenShift ? Colors.green : kTextHint)),
                ]),
              ])),
              // Today DC
              Expanded(flex: 2, child: Column(children: [
                Text('${a.todayDcBirds}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.blue), textAlign: TextAlign.center),
                Text('${a.todayDcKg.toStringAsFixed(0)} kg', style: const TextStyle(fontSize: 9, color: kTextHint), textAlign: TextAlign.center),
              ])),
              // Delivered today
              Expanded(flex: 2, child: Column(children: [
                Text('${a.todayDeliveredBirds}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.teal), textAlign: TextAlign.center),
                const Text('birds', style: TextStyle(fontSize: 9, color: kTextHint), textAlign: TextAlign.center),
              ])),
              // Live stock
              Expanded(flex: 2, child: Column(children: [
                Text('${a.liveStockBirds}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                        color: a.liveStockBirds > 0 ? Colors.orange : Colors.green),
                    textAlign: TextAlign.center),
                Text('${a.liveStockKg.toStringAsFixed(0)} kg',
                    style: const TextStyle(fontSize: 9, color: kTextHint), textAlign: TextAlign.center),
              ])),
              // Pending deliveries
              Expanded(flex: 2, child: Column(children: [
                Text('${a.pendingDeliveries}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                        color: hasPending ? Colors.orange : Colors.green),
                    textAlign: TextAlign.center),
                const Text('orders', style: TextStyle(fontSize: 9, color: kTextHint), textAlign: TextAlign.center),
              ])),
            ]));
        }),
        // Summary footer
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(13))),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _agentSummary('Total DC', '${agents.fold(0, (s, a) => s + a.todayDcBirds)} birds', Colors.blue),
            _agentSummary('Total Delivered', '${agents.fold(0, (s, a) => s + a.todayDeliveredBirds)} birds', Colors.teal),
            _agentSummary('Live in Stock', '${agents.fold(0, (s, a) => s + a.liveStockBirds)} birds',
                agents.any((a) => a.liveStockBirds > 0) ? Colors.orange : Colors.green),
            _agentSummary('Pending', '${agents.fold(0, (s, a) => s + a.pendingDeliveries)} orders',
                agents.any((a) => a.pendingDeliveries > 0) ? Colors.orange : Colors.green),
          ])),
      ]));
  }

  Widget _agentSummary(String l, String v, Color c) => Column(children: [
    Text(v, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c)),
    Text(l, style: const TextStyle(fontSize: 9, color: kTextHint)),
  ]);

  Widget _sstat(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c)),
    Text(l, style: const TextStyle(fontSize: 9, color: kTextHint), textAlign: TextAlign.center),
  ]));

  Widget _stat2(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c)),
    Text(l, style: const TextStyle(fontSize: 10, color: kTextHint)),
  ]));

  Widget _payRow(String label, double amount, Color color) => Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Row(children: [
        Icon(Icons.currency_rupee, color: color, size: 14), const SizedBox(width: 4),
        Expanded(child: Text(label, style: TextStyle(fontSize: 11, color: color))),
        Text(_fmt(amount), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
      ]));

  Widget _alertTile(String msg, Color color, IconData icon, {VoidCallback? onTap}) =>
      GestureDetector(onTap: onTap, child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.3))),
          child: Row(children: [
            Icon(icon, color: color, size: 18), const SizedBox(width: 8),
            Expanded(child: Text(msg, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600))),
            if (onTap != null) Icon(Icons.chevron_right, color: color, size: 16),
          ])));

  Widget _errorView() => Center(child: Padding(padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_outlined, size: 48, color: kTextHint),
        const SizedBox(height: 12),
        Text(_error ?? 'Error', style: const TextStyle(color: kTextSub, fontSize: 13), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: _load, child: const Text('Retry')),
      ])));

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
        final row = actions.sublist(i, i + count);
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

  Widget _qaBtn(_QA a) => InkWell(onTap: a.onTap, borderRadius: BorderRadius.circular(10),
      child: Container(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(color: a.color.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(10),
              border: Border.all(color: a.color.withValues(alpha: 0.2))),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(a.icon, size: 22, color: a.color),
            const SizedBox(height: 4),
            Text(a.label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: a.color),
                textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
          ])));

  String _fmt(double? v) {
    if (v == null) return '₹0';
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000)   return '₹${(v / 1000).toStringAsFixed(1)}K';
    return '₹${v.toStringAsFixed(0)}';
  }
}
