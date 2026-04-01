import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class DailyReportScreen extends ConsumerStatefulWidget {
  const DailyReportScreen({super.key});
  @override ConsumerState<DailyReportScreen> createState() => _S();
}
class _S extends ConsumerState<DailyReportScreen> {
  final _c = Supabase.instance.client;
  Map<String,dynamic>? _d;
  bool _loading = true;
  DateTime _date = DateTime.now();
  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    setState(() => _loading = true);
    try {
      final res = await _c.rpc('daily_report_summary', params: {'p_trader_id': tid, 'p_date': _date.toIso8601String().split('T')[0]});
      if (mounted) setState(() { _d = res != null ? Map<String,dynamic>.from(res as Map) : {}; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Daily Report'), actions: [
      TextButton.icon(onPressed: () async {
        final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now());
        if (d != null) { if (mounted) setState(() => _date = d); _load(); }
      }, icon: const Icon(Icons.calendar_today_outlined, size: 16), label: Text(DateFormat('d MMM').format(_date))),
      IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
    ]),
    body: _loading ? const LoadingList() : _d == null ? const EmptyState(icon: Icons.receipt_long_outlined, message: 'No data')
        : ListView(padding: const EdgeInsets.all(16), children: [
            Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                Text(DateFormat('EEEE, d MMMM y').format(_date), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 8),
                Text(Fmt.amount((_d!['total_revenue'] as num?)?.toDouble() ?? 0), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
                const Text('Total Revenue', style: TextStyle(color: Colors.white70, fontSize: 13)),
              ])),
            const SizedBox(height: 14),
            WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionHeader('VOLUME'),
              _r('Birds Sold', '${(_d!['total_birds'] ?? _d!['birds_sold'] ?? 0)}'),
              _r('Total Weight', Fmt.kg((_d!['total_weight'] as num?)?.toDouble() ?? 0)),
              _r('Deliveries', '${_d!['total_deliveries'] ?? 0}'),
              _r('Orders', '${_d!['total_orders'] ?? 0}'),
            ])),
            const SizedBox(height: 10),
            WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionHeader('CASH FLOW'),
              _r('Cash Collected', Fmt.amount((_d!['cash_collected'] as num?)?.toDouble() ?? 0), Colors.green),
              _r('UPI Collected', Fmt.amount((_d!['upi_collected'] as num?)?.toDouble() ?? 0)),
              _r('Credit Given', Fmt.amount((_d!['credit_given'] as num?)?.toDouble() ?? 0), Colors.orange),
            ])),
            if ((_d!['agent_breakdown'] as List?)?.isNotEmpty == true) ...[const SizedBox(height: 10),
              WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SectionHeader('BY AGENT'),
                ...(_d!['agent_breakdown'] as List).map((a) {
                  final row = a as Map<String,dynamic>;
                  return _r(row['agent_name'] as String? ?? '—', '${row['birds'] ?? 0} birds · ${Fmt.amount((row['revenue'] as num?)?.toDouble() ?? 0)}');
                }),
              ]))],
          ]),
  );

  Widget _r(String l, String v, [Color? color]) => Padding(padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [Expanded(child: Text(l, style: const TextStyle(fontSize: 12, color: kTextSub))), Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color ?? kTextMain))]));
}
