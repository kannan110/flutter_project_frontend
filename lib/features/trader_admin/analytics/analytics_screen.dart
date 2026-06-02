import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/dashboard_models.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});
  @override ConsumerState<AnalyticsScreen> createState() => _S();
}
class _S extends ConsumerState<AnalyticsScreen> {
  final _c = Supabase.instance.client;
  Map<String,dynamic>? _analytics;
  List<StockPosition> _stock = [];
  bool _loading = true;
  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null || !mounted) return;
    if (mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _c.rpc('analytics_summary', params: {'p_trader_id': tid}),
        _c.rpc('get_available_stock', params: {'p_trader_id': tid}),
      ]);
      if (!mounted) return;
      if (mounted) setState(() {
        _analytics = results[0] as Map<String,dynamic>?;
        _stock = ((results[1] as List?) ?? []).map((s) => StockPosition.fromMap(s as Map<String,dynamic>)).toList();
        _loading = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final d = _analytics ?? {};
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(backgroundColor: kSurface, title: const Text('Analytics'), actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)]),
      body: _loading ? const LoadingList() : ListView(padding: const EdgeInsets.fromLTRB(16,16,16,40), children: [

        const SectionHeader('REVENUE'),
        GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.4, children: [
              KpiCard('Today', Fmt.amount((d['today_revenue'] as num?)?.toDouble() ?? 0), Icons.today_outlined, kPrimary),
              KpiCard('This Week', Fmt.amount((d['week_revenue'] as num?)?.toDouble() ?? 0), Icons.date_range_outlined, Colors.blue),
              KpiCard('This Month', Fmt.amount((d['month_revenue'] as num?)?.toDouble() ?? 0), Icons.calendar_month_outlined, Colors.purple),
              KpiCard('Outstanding', Fmt.amount((d['total_outstanding'] as num?)?.toDouble() ?? 0), Icons.account_balance_wallet_outlined, Colors.orange),
            ]),
        const SizedBox(height: 16),

        const SectionHeader('STOCK (CUMULATIVE)'),
        ..._stock.map((s) => Container(margin: const EdgeInsets.only(bottom: 10), child: WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.productName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: kNavy)),
          const SizedBox(height: 8),
          Row(children: [
            _stat('Total In', '${s.totalInBirds}', Colors.blue),
            _stat('Delivered', '${s.totalOutBirds}', kPrimary),
            _stat('Returns', '${s.returnedBirds}', Colors.purple),
            _stat('Remaining', '${s.availableBirds}', s.isNegative ? Colors.red : s.hasLowStock ? Colors.orange : Colors.green),
          ]),
        ])))),
        const SizedBox(height: 8),

        WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader('OPERATIONS'),
          _r('Total Orders', '${d['total_orders'] ?? 0}'),
          _r('Delivered', '${d['total_delivered'] ?? 0}'),
          _r('Pending Approvals', '${d['pending_approvals'] ?? 0}', Colors.orange),
          _r('Active Agents', '${d['active_agents'] ?? 0}', kPrimary),
          _r('Open Shifts', '${d['open_shifts'] ?? 0}', (d['open_shifts'] as int? ?? 0) > 0 ? Colors.orange : null),
          _r('Active Retailers', '${d['active_retailers'] ?? 0}', kPrimary),
        ])),
      ]),
    );
  }

  Widget _stat(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c)),
    Text(l, style: const TextStyle(fontSize: 9, color: kTextHint), textAlign: TextAlign.center),
  ]));

  Widget _r(String l, String v, [Color? c]) => Padding(padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [Expanded(child: Text(l, style: const TextStyle(fontSize: 12, color: kTextSub))),
        Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c ?? kTextMain))]));
}