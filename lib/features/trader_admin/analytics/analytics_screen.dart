import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});
  @override ConsumerState<AnalyticsScreen> createState() => _S();
}
class _S extends ConsumerState<AnalyticsScreen> {
  final _c = Supabase.instance.client;
  Map<String,dynamic>? _d;
  bool _loading = true;
  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    setState(() => _loading = true);
    try {
      final res = await _c.rpc('analytics_summary', params: {'p_trader_id': tid});
      if (mounted) setState(() { _d = res != null ? Map<String,dynamic>.from(res as Map) : {}; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Analytics'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
    body: _loading ? const LoadingList() : _d == null ? const EmptyState(icon: Icons.analytics_outlined, message: 'No analytics data')
        : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
            const SectionHeader('REVENUE'),
            GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.4,
              children: [
                KpiCard('Today', Fmt.amount((_d!['today_revenue'] as num?)?.toDouble() ?? 0), Icons.today_outlined, kPrimary),
                KpiCard('This Week', Fmt.amount((_d!['week_revenue'] as num?)?.toDouble() ?? 0), Icons.date_range_outlined, Colors.blue),
                KpiCard('This Month', Fmt.amount((_d!['month_revenue'] as num?)?.toDouble() ?? 0), Icons.calendar_month_outlined, Colors.purple),
                KpiCard('Outstanding', Fmt.amount((_d!['total_outstanding'] as num?)?.toDouble() ?? 0), Icons.account_balance_wallet_outlined, Colors.orange),
              ]),
            const SizedBox(height: 16),
            const SectionHeader('VOLUME'),
            GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.4,
              children: [
                KpiCard('Today Birds', '${_d!['today_birds'] ?? 0}', Icons.countertops_outlined, kPrimary),
                KpiCard('Month Birds', '${_d!['month_birds'] ?? 0}', Icons.calendar_month_outlined, Colors.teal),
                KpiCard('Today Weight', Fmt.kg((_d!['today_weight'] as num?)?.toDouble() ?? 0), Icons.scale_outlined, Colors.indigo),
                KpiCard('Month Weight', Fmt.kg((_d!['month_weight'] as num?)?.toDouble() ?? 0), Icons.stacked_bar_chart, Colors.cyan),
              ]),
            const SizedBox(height: 16),
            WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionHeader('OPERATIONS'),
              _r('Pending Orders', '${_d!['pending_orders'] ?? 0}', Colors.orange),
              _r('Active Deliveries', '${_d!['active_deliveries'] ?? 0}', Colors.blue),
              _r('Pending Approvals', '${_d!['pending_approvals'] ?? 0}', Colors.purple),
              _r('Open Shifts', '${_d!['open_shifts'] ?? 0}', (_d!['open_shifts'] as int? ?? 0) > 0 ? Colors.orange : null),
              _r('Active Retailers', '${_d!['active_retailers'] ?? 0}', kPrimary),
            ])),
          ])),
  );

  Widget _r(String l, String v, [Color? color]) => Padding(padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [Expanded(child: Text(l, style: const TextStyle(fontSize: 12, color: kTextSub))), Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color ?? kTextMain))]));
}
