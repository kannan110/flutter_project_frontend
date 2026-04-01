import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

final langProvider = StateProvider<String>((ref) => 'en');

class L {
  static const _t = {
    'en': {
      'new_order':'New Order','all_orders':'All Orders','add_stock':'Add Chicken Stock',
      'approve':'Approve Delivery','dispatch':'Dispatch','collect':'Collect Money',
      'customers':'Customers','agents':'Agents','rate':'Set Rate','returns':'Returns',
      'reconcile':'Check Cash','analytics':'Summary','close_day':'Close Day',
      'alerts':'Alerts','report':'Daily Report','crates':'Crates','invoices':'Bills',
      'stock':'Today Stock','finance':'Accounts','quick':'QUICK ACTIONS',
      'today_view':'Today Overview','remaining':'Remaining','purchased':'Purchased',
      'delivered':'Delivered','returned':'Returns','cash':'Cash','outstanding':'To Collect',
    },
    'ta': {
      'new_order':'புது ஆர்டர்','all_orders':'ஆர்டர்கள்','add_stock':'கோழி சேர்',
      'approve':'டெலிவரி அனுமதி','dispatch':'அனுப்பு','collect':'பணம் வசூல்',
      'customers':'வாடிக்கையாளர்','agents':'ஏஜெண்ட்','rate':'விலை நிர்ணயம்','returns':'திருப்பம்',
      'reconcile':'கேஷ் சரிபார்','analytics':'சுருக்கம்','close_day':'நாள் முடி',
      'alerts':'எச்சரிக்கை','report':'அறிக்கை','crates':'கிரேட்','invoices':'பில்',
      'stock':'இன்றைய கோழி','finance':'கணக்கு','quick':'விரைவு செயல்கள்',
      'today_view':'இன்றைய நிலை','remaining':'மீதம்','purchased':'வாங்கியது',
      'delivered':'டெலிவரி','returned':'திரும்பியது','cash':'பணம்','outstanding':'வசூல் செய்யவேண்டியது',
    },
  };
  static String g(String lang, String k) => _t[lang]?[k] ?? _t['en']![k] ?? k;
}

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
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final res = await _c.rpc('dashboard_summary', params: {'p_trader_id': tid});
      if (!mounted) return;
      if (mounted) setState(() { _d = res != null ? Map<String,dynamic>.from(res as Map) : {}; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(appUserProvider).valueOrNull;
    final lang = ref.watch(langProvider);
    final t    = (String k) => L.g(lang, k);

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(user?.companyName ?? 'Dashboard', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          Text(t('today_view'), style: const TextStyle(fontSize: 11, color: kTextHint, fontWeight: FontWeight.w400)),
        ]),
        actions: [
          GestureDetector(
            onTap: () => ref.read(langProvider.notifier).state = lang == 'en' ? 'ta' : 'en',
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: kPrimary.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: kPrimary.withOpacity(0.3))),
              child: Text(lang == 'en' ? 'தமிழ்' : 'EN', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kPrimary)),
            ),
          ),
          IconButton(icon: const Icon(Icons.notifications_outlined), onPressed: () => context.go(R.alerts)),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading ? const LoadingList()
          : RefreshIndicator(onRefresh: _load, child: _body(context, lang)),
    );
  }

  Widget _body(BuildContext ctx, String lang) {
    final t = (String k) => L.g(lang, k);
    final d = _d ?? {};

    // Use correct dashboard keys from fixed RPC
    final rev        = (d['today_revenue']        as num?)?.toDouble() ?? 0;
    final pend       = d['pending_orders']        ?? 0;
    final live       = d['active_deliveries']     ?? 0;
    final appr       = d['pending_approvals']     ?? 0;
    final stockBirds = (d['stock_birds']          as num?)?.toInt() ?? 0;
    final remaining  = (d['remaining_birds']      as num?)?.toInt() ?? 0;
    final remainKg   = (d['remaining_kg']         as num?)?.toDouble() ?? 0;
    final purchased  = (d['stock_birds']          as num?)?.toInt() ?? 0;
    final delivered  = (d['today_delivered']      as num?)?.toInt() ?? 0;
    final returns    = (d['today_returns_birds']  as num?)?.toInt() ?? 0;
    final returnsKg  = (d['today_returns_kg']     as num?)?.toDouble() ?? 0;
    final outstanding= (d['total_outstanding']    as num?)?.toDouble() ?? 0;
    final collected  = (d['today_collected']      as num?)?.toDouble() ?? 0;
    final cash       = (d['today_cash_collected'] as num?)?.toDouble() ?? 0;
    final openShifts = d['open_shifts']           ?? 0;

    return ListView(padding: const EdgeInsets.all(14), children: [

      // ── No stock warning ─────────────────────────────────────────
      if (stockBirds == 0) Container(
        margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.shade200)),
        child: Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 22), const SizedBox(width: 10),
          Expanded(child: Text(lang == 'ta' ? 'இன்று கோழி சேர்க்கவில்லை!' : 'No stock added today!',
              style: TextStyle(fontSize: 13, color: Colors.orange.shade800, fontWeight: FontWeight.w600))),
          ElevatedButton(onPressed: () => ctx.go(R.stock),
              style: ElevatedButton.styleFrom(minimumSize: const Size(0, 34), backgroundColor: Colors.orange),
              child: Text(t('add_stock'), style: const TextStyle(fontSize: 11))),
        ])),

      // ── KPI cards ─────────────────────────────────────────────────
      GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.35,
        children: [
          KpiCard(t('all_orders'), Fmt.amount(rev), Icons.currency_rupee, kPrimary, onTap: () => ctx.go(R.invoices)),
          KpiCard(t('all_orders'), '$pend', Icons.shopping_bag_outlined, Colors.orange, onTap: () => ctx.go(R.orders)),
          KpiCard(t('dispatch'), '$live', Icons.local_shipping_outlined, Colors.blue, onTap: () => ctx.go(R.dispatch)),
          KpiCard(t('approve'), '$appr', Icons.fact_check_outlined, appr > 0 ? Colors.red : Colors.green, onTap: () => ctx.go(R.approvals)),
        ]),
      const SizedBox(height: 12),

      // ── Stock panel ───────────────────────────────────────────────
      WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(t('stock'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const Spacer(),
          TextButton(onPressed: () => ctx.go(R.stock), child: Text(t('add_stock'), style: const TextStyle(fontSize: 11))),
        ]),
        const Divider(height: 10),
        Row(children: [
          _stat(t('purchased'), '$purchased', Colors.blue),
          _stat(t('delivered'), '$delivered', kPrimary),
          _stat(t('returned'), '$returns', Colors.purple),
          _stat(t('remaining'), '$remaining', remaining < 50 ? Colors.red : Colors.green),
        ]),
        if (returnsKg > 0) Padding(padding: const EdgeInsets.only(top: 6),
          child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.purple.shade200)),
            child: Row(children: [
              Icon(Icons.assignment_return_outlined, color: Colors.purple.shade600, size: 16), const SizedBox(width: 6),
              Text('${returnsKg.toStringAsFixed(1)} kg returned to stock today ✓', style: TextStyle(fontSize: 11, color: Colors.purple.shade700, fontWeight: FontWeight.w600)),
            ]))),
      ])),
      const SizedBox(height: 10),

      // ── Finance panel ─────────────────────────────────────────────
      WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(t('finance'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const Spacer(),
          TextButton(onPressed: () => ctx.go(R.ledger), child: const Text('Ledger', style: TextStyle(fontSize: 11))),
        ]),
        const Divider(height: 10),
        Row(children: [
          _stat(t('outstanding'), Fmt.amount(outstanding), outstanding > 0 ? Colors.orange : Colors.green),
          _stat(t('collect'),     Fmt.amount(collected), kPrimary),
          _stat(t('cash'),        Fmt.amount(cash), Colors.green),
          _stat('Shifts', '$openShifts', openShifts > 0 ? Colors.red : Colors.green),
        ]),
      ])),
      const SizedBox(height: 14),

      // ── Quick actions ─────────────────────────────────────────────
      Text(t('quick'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kTextHint, letterSpacing: 0.8)),
      const SizedBox(height: 8),
      Row(children: [
        _qa(Icons.add_circle,             t('new_order'),  Colors.green,    () => ctx.go(R.orderCreate), flex: 2),
        const SizedBox(width: 8),
        _qa(Icons.list_alt_outlined,      t('all_orders'), Colors.blue,     () => ctx.go(R.orders)),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        _qa(Icons.fact_check_rounded,     t('approve'),    Colors.orange,   () => ctx.go(R.approvals)),
        const SizedBox(width: 8),
        _qa(Icons.local_shipping_outlined,t('dispatch'),   kPrimary,        () => ctx.go(R.dispatch)),
        const SizedBox(width: 8),
        _qa(Icons.inventory_outlined,     t('add_stock'),  Colors.teal,     () => ctx.go(R.stock)),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        _qa(Icons.account_balance_wallet_outlined, t('collect'),  Colors.purple,  () => ctx.go(R.ledger)),
        const SizedBox(width: 8),
        _qa(Icons.receipt_long_outlined,           t('invoices'), Colors.indigo,  () => ctx.go(R.invoices)),
        const SizedBox(width: 8),
        _qa(Icons.price_change_outlined,           t('rate'),     Colors.cyan,    () => ctx.go(R.rates)),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        _qa(Icons.store_outlined,                  t('customers'),Colors.brown,   () => ctx.go(R.retailers)),
        const SizedBox(width: 8),
        _qa(Icons.delivery_dining_outlined,        t('agents'),   Colors.blueGrey,() => ctx.go(R.agents)),
        const SizedBox(width: 8),
        _qa(Icons.assignment_return_outlined,      t('returns'),  Colors.red,     () => ctx.go(R.returns)),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        _qa(Icons.schedule_outlined,               'Shifts',      Colors.indigo,  () => ctx.go(R.shifts)),
        const SizedBox(width: 8),
        _qa(Icons.account_balance_outlined,        t('reconcile'),Colors.green,   () => ctx.go(R.cashRecon)),
        const SizedBox(width: 8),
        _qa(Icons.lock_clock_outlined,             t('close_day'),Colors.red,     () => ctx.go(R.dayClosure)),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        _qa(Icons.warning_amber_outlined,          t('alerts'),   Colors.orange,  () => ctx.go(R.alerts)),
        const SizedBox(width: 8),
        _qa(Icons.bar_chart_outlined,              t('analytics'),Colors.blue,    () => ctx.go(R.analytics)),
        const SizedBox(width: 8),
        _qa(Icons.summarize_outlined,              t('report'),   kPrimary,       () => ctx.go(R.dailyReport)),
      ]),
      const SizedBox(height: 20),
    ]);
  }

  Widget _stat(String label, String value, Color color) => Expanded(child: Column(children: [
    Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
    const SizedBox(height: 2),
    Text(label, style: const TextStyle(fontSize: 10, color: kTextHint), textAlign: TextAlign.center, maxLines: 2),
  ]));

  Widget _qa(IconData icon, String label, Color color, VoidCallback onTap, {int flex = 1}) =>
      Expanded(flex: flex, child: InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withOpacity(0.2))),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color), textAlign: TextAlign.center, maxLines: 2),
          ]),
        ),
      ));
}
