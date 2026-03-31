import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

// ── Language Provider ─────────────────────────────────────────────────
// Simple in-memory language toggle (no package needed)
final langProvider = StateProvider<String>((ref) => 'en');

// ── Translations ──────────────────────────────────────────────────────
class L {
  static const _t = {
    'en': {
      'today_overview': 'Today Overview',
      'add_stock': 'Add Stock',
      'no_stock': 'No stock added today',
      'today_money': "Today's Money",
      'pending': 'Pending',
      'live': 'Live Delivery',
      'approve': 'To Approve',
      'stock': 'Stock',
      'stock_birds': 'Birds in stock',
      'weight_kg': 'Weight (kg)',
      'remaining': 'Remaining',
      'finance': 'Account / Money',
      'pending_amt': 'Amount to collect',
      'collected': 'Collected today',
      'open_shifts': 'Open shifts',
      'quick_actions': 'QUICK ACTIONS',
      'new_order': 'New Order',
      'view_orders': 'All Orders',
      'add_chicken': 'Add Chicken',
      'collect_money': 'Collect Money',
      'agents': 'Agents',
      'customers': 'Customers',
      'rate': 'Set Rate',
      'approve_delivery': 'Approve Delivery',
      'alerts': 'Alerts',
      'day_close': 'Close Day',
      'reconcile': 'Check Cash',
      'returns': 'Returns',
      'report': 'Daily Report',
      'analytics': 'Summary',
      'add_expense': 'Expenses',
      'all_invoices': 'Bills',
    },
    'ta': {
      'today_overview': 'இன்றைய நிலை',
      'add_stock': 'கோழி சேர்',
      'no_stock': 'இன்று கோழி சேர்க்கவில்லை',
      'today_money': 'இன்றைய வருவாய்',
      'pending': 'நிலுவை ஆர்டர்',
      'live': 'டெலிவரி',
      'approve': 'அனுமதி',
      'stock': 'கோழி இருப்பு',
      'stock_birds': 'கோழிகள்',
      'weight_kg': 'எடை (கிலோ)',
      'remaining': 'மீதம்',
      'finance': 'கணக்கு',
      'pending_amt': 'வசூல் செய்ய வேண்டியது',
      'collected': 'இன்று வசூல்',
      'open_shifts': 'திறந்த ஷிஃப்ட்',
      'quick_actions': 'விரைவு செயல்கள்',
      'new_order': 'புது ஆர்டர்',
      'view_orders': 'ஆர்டர்கள்',
      'add_chicken': 'கோழி சேர்',
      'collect_money': 'பணம் வசூல்',
      'agents': 'ஏஜெண்டுகள்',
      'customers': 'வாடிக்கையாளர்',
      'rate': 'விலை நிர்ணயம்',
      'approve_delivery': 'டெலிவரி அனுமதி',
      'alerts': 'எச்சரிக்கை',
      'day_close': 'நாள் முடி',
      'reconcile': 'கேஷ் சரிபார்',
      'returns': 'திருப்பம்',
      'report': 'இன்றைய அறிக்கை',
      'analytics': 'சுருக்கம்',
      'add_expense': 'செலவு',
      'all_invoices': 'பில்கள்',
    },
  };

  static String get(String lang, String key) =>
      _t[lang]?[key] ?? _t['en']![key] ?? key;
}

// ── Dashboard Screen ──────────────────────────────────────────────────
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override ConsumerState<DashboardScreen> createState() => _S();
}

class _S extends ConsumerState<DashboardScreen> {
  final _c = Supabase.instance.client;
  Map<String,dynamic>? _d;
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    setState(() => _loading = true);
    try {
      final res = await _c.rpc('dashboard_summary', params: {'p_trader_id': tid});
      if (mounted) setState(() {
        _d = res != null ? Map<String,dynamic>.from(res as Map) : {};
        _loading = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(appUserProvider).valueOrNull;
    final lang = ref.watch(langProvider);
    final t    = (String k) => L.get(lang, k);

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(user?.companyName ?? 'Dashboard',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          Text(t('today_overview'),
              style: const TextStyle(fontSize: 11, color: kTextHint, fontWeight: FontWeight.w400)),
        ]),
        actions: [
          // ── Language Toggle ────────────────────────────────────────
          GestureDetector(
            onTap: () => ref.read(langProvider.notifier).state = lang == 'en' ? 'ta' : 'en',
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: kPrimary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: kPrimary.withOpacity(0.3)),
              ),
              child: Text(lang == 'en' ? 'தமிழ்' : 'EN',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kPrimary)),
            ),
          ),
          IconButton(icon: const Icon(Icons.notifications_outlined),
              onPressed: () => context.go(R.alerts)),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading ? const LoadingList()
          : RefreshIndicator(onRefresh: _load, child: _d == null
              ? const EmptyState(icon: Icons.cloud_off_outlined, message: 'No data')
              : _body(context, lang)),
    );
  }

  Widget _body(BuildContext ctx, String lang) {
    final t = (String k) => L.get(lang, k);
    final d = _d!;
    final rev       = (d['today_revenue']    as num?)?.toDouble() ?? 0;
    final pend      = d['pending_orders']    ?? 0;
    final live      = d['active_deliveries'] ?? 0;
    final appr      = d['pending_approvals'] ?? 0;
    final sBirds    = d['stock_birds']       ?? 0;
    final remaining = d['remaining_birds']   as int? ?? 0;
    final openShifts= d['open_shifts']       as int? ?? 0;
    final outstanding = (d['total_outstanding'] as num?)?.toDouble() ?? 0;
    final collected   = (d['today_collected']   as num?)?.toDouble() ?? 0;

    return ListView(padding: const EdgeInsets.all(14), children: [

      // ── No stock warning ───────────────────────────────────────────
      if (sBirds == 0) Container(
        margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.shade200)),
        child: Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Text(t('no_stock'), style: TextStyle(fontSize: 13, color: Colors.orange.shade800, fontWeight: FontWeight.w600))),
          ElevatedButton(
            onPressed: () => ctx.go(R.stock),
            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 34), backgroundColor: Colors.orange),
            child: Text(t('add_stock'), style: const TextStyle(fontSize: 12)),
          ),
        ])),

      // ── KPI Cards ─────────────────────────────────────────────────
      GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.35,
        children: [
          KpiCard(t('today_money'), Fmt.amount(rev), Icons.currency_rupee, kPrimary, onTap: () => ctx.go(R.invoices)),
          KpiCard(t('pending'), '$pend', Icons.shopping_bag_outlined, Colors.orange, onTap: () => ctx.go(R.orders)),
          KpiCard(t('live'), '$live', Icons.local_shipping_outlined, Colors.blue, onTap: () => ctx.go(R.dispatch)),
          KpiCard(t('approve'), '$appr', Icons.fact_check_outlined, Colors.red, onTap: () => ctx.go(R.approvals)),
        ]),
      const SizedBox(height: 12),

      // ── Stock ──────────────────────────────────────────────────────
      WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(t('stock'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const Spacer(),
          TextButton(onPressed: () => ctx.go(R.stock), child: Text(t('add_chicken'))),
        ]),
        const Divider(height: 12),
        Row(children: [
          _stat(t('stock_birds'), '${d['stock_birds'] ?? 0}', kPrimary),
          _stat(t('weight_kg'), '${(d['stock_kg'] as num?)?.toStringAsFixed(0) ?? 0}', Colors.blue),
          _stat(t('remaining'), '$remaining', remaining < 50 ? Colors.red : Colors.green),
        ]),
      ])),
      const SizedBox(height: 10),

      // ── Finance ────────────────────────────────────────────────────
      WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(t('finance'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const Spacer(),
          TextButton(onPressed: () => ctx.go(R.ledger), child: const Text('Ledger')),
        ]),
        const Divider(height: 12),
        Row(children: [
          _stat(t('pending_amt'), Fmt.amount(outstanding), outstanding > 0 ? Colors.orange : Colors.green),
          _stat(t('collected'), Fmt.amount(collected), kPrimary),
          _stat(t('open_shifts'), '$openShifts', openShifts > 0 ? Colors.red : Colors.green),
        ]),
      ])),
      const SizedBox(height: 14),

      // ── Quick Actions ──────────────────────────────────────────────
      Text(t('quick_actions'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kTextHint, letterSpacing: 0.8)),
      const SizedBox(height: 8),

      // Row 1 — Most used
      Row(children: [
        _qa(Icons.add_circle,              t('new_order'),        Colors.green,  () => ctx.go(R.orderCreate),    flex: 2),
        const SizedBox(width: 8),
        _qa(Icons.list_alt_outlined,       t('view_orders'),      Colors.blue,   () => ctx.go(R.orders)),
      ]),
      const SizedBox(height: 8),

      // Row 2
      Row(children: [
        _qa(Icons.fact_check_rounded,      t('approve_delivery'), Colors.orange, () => ctx.go(R.approvals)),
        const SizedBox(width: 8),
        _qa(Icons.local_shipping_outlined, t('live'),             kPrimary,      () => ctx.go(R.dispatch)),
        const SizedBox(width: 8),
        _qa(Icons.inventory_outlined,      t('add_chicken'),      Colors.teal,   () => ctx.go(R.stock)),
      ]),
      const SizedBox(height: 8),

      // Row 3
      Row(children: [
        _qa(Icons.account_balance_wallet_outlined, t('collect_money'), Colors.purple, () => ctx.go(R.ledger)),
        const SizedBox(width: 8),
        _qa(Icons.receipt_long_outlined,           t('all_invoices'),  Colors.indigo, () => ctx.go(R.invoices)),
        const SizedBox(width: 8),
        _qa(Icons.price_change_outlined,           t('rate'),          Colors.cyan,   () => ctx.go(R.rates)),
      ]),
      const SizedBox(height: 8),

      // Row 4 — Operations
      Row(children: [
        _qa(Icons.store_outlined,                 t('customers'), Colors.brown,  () => ctx.go(R.retailers)),
        const SizedBox(width: 8),
        _qa(Icons.delivery_dining_outlined,       t('agents'),    Colors.blueGrey, () => ctx.go(R.agents)),
        const SizedBox(width: 8),
        _qa(Icons.assignment_return_outlined,     t('returns'),   Colors.red,    () => ctx.go(R.returns)),
      ]),
      const SizedBox(height: 8),

      // Row 5 — Day management
      Row(children: [
        _qa(Icons.account_balance_outlined,       t('reconcile'), Colors.green,  () => ctx.go(R.cashRecon)),
        const SizedBox(width: 8),
        _qa(Icons.bar_chart_outlined,             t('analytics'), Colors.blue,   () => ctx.go(R.analytics)),
        const SizedBox(width: 8),
        _qa(Icons.lock_clock_outlined,            t('day_close'), Colors.red,    () => ctx.go(R.dayClosure)),
      ]),
      const SizedBox(height: 8),

      // Row 6
      Row(children: [
        _qa(Icons.warning_amber_outlined,         t('alerts'),    Colors.orange, () => ctx.go(R.alerts)),
        const SizedBox(width: 8),
        _qa(Icons.summarize_outlined,             t('report'),    kPrimary,      () => ctx.go(R.dailyReport)),
        const SizedBox(width: 8),
        _qa(Icons.inventory_2_outlined,           'Crates',       Colors.brown,  () => ctx.go(R.crates)),
      ]),
      const SizedBox(height: 20),
    ]);
  }

  Widget _stat(String label, String value, Color color) => Expanded(child: Column(children: [
    Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
    const SizedBox(height: 2),
    Text(label, style: const TextStyle(fontSize: 10, color: kTextHint), textAlign: TextAlign.center, maxLines: 2),
  ]));

  // Quick action tile — supports flex for wider buttons
  Widget _qa(IconData icon, String label, Color color, VoidCallback onTap, {int flex = 1}) =>
      Expanded(flex: flex, child: InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
                textAlign: TextAlign.center, maxLines: 2),
          ]),
        ),
      ));
}
