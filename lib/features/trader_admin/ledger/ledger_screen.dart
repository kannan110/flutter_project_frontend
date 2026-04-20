import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class LedgerScreen extends ConsumerStatefulWidget {
  const LedgerScreen({super.key});
  @override ConsumerState<LedgerScreen> createState() => _S();
}

class _S extends ConsumerState<LedgerScreen> {
  final _c = Supabase.instance.client;
  List<Map<String,dynamic>> _list = [];
  bool _loading = true;
  String _filter = 'all';

  double get _totalOutstanding =>
      _list.fold(0.0, (s, r) => s + ((r['outstanding_amount'] as num?)?.toDouble() ?? 0));

  List<Map<String,dynamic>> get _filtered {
    if (_filter == 'all') return _list;
    return _list.where((r) {
      final rs = r['risk_status'] as String? ?? 'healthy';
      if (_filter == 'over_limit') return rs == 'over_limit' || rs == 'near_limit';
      if (_filter == 'overdue')    return rs == 'overdue_15d' || rs == 'overdue_30d';
      if (_filter == 'healthy')    return rs == 'healthy';
      return true;
    }).toList();
  }

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    if (mounted) setState(() => _loading = true);
    try {
      final res = await _c.rpc('get_retailer_risk_summary', params: {'p_trader_id': tid});
      if (!mounted) return;
      setState(() {
        _list = List<Map<String,dynamic>>.from(
            (res as List? ?? []).map((e) => Map<String,dynamic>.from(e as Map)));
        _loading = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final overLimit = _list.where((r) => r['risk_status'] == 'over_limit').length;
    final nearLimit = _list.where((r) => r['risk_status'] == 'near_limit').length;
    final overdue   = _list.where((r) {
      final s = r['risk_status'] as String? ?? '';
      return s == 'overdue_15d' || s == 'overdue_30d';
    }).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ledger'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: _loading ? const LoadingList() : Column(children: [

        // Summary header
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Total Outstanding', style: TextStyle(fontSize: 11, color: kTextHint)),
                Text(Fmt.amount(_totalOutstanding),
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
                        color: _totalOutstanding > 0 ? Colors.orange : Colors.green)),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${_list.length} retailers', style: const TextStyle(fontSize: 11, color: kTextHint)),
                if (overLimit > 0) Text('$overLimit over limit',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.red)),
                if (overdue > 0) Text('$overdue overdue',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.orange)),
              ]),
            ]),
            if (overLimit > 0 || nearLimit > 0 || overdue > 0) ...[
              const SizedBox(height: 10),
              Row(children: [
                if (overLimit > 0) ...[_chip('$overLimit Over Limit', Colors.red), const SizedBox(width: 6)],
                if (nearLimit > 0) ...[_chip('$nearLimit Near Limit', Colors.orange), const SizedBox(width: 6)],
                if (overdue > 0) _chip('$overdue Overdue', Colors.deepOrange),
              ]),
            ],
          ])),
        const Divider(height: 1),

        // Filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(children: [
            for (final f in ['all', 'over_limit', 'overdue', 'healthy'])
              Padding(padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(f == 'over_limit' ? 'Over Limit' : f[0].toUpperCase() + f.substring(1),
                      style: const TextStyle(fontSize: 12)),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                  selectedColor: kPrimary.withValues(alpha: 0.12),
                  checkmarkColor: kPrimary)),
          ])),

        // List
        Expanded(child: _filtered.isEmpty
            ? const EmptyState(icon: Icons.account_balance_wallet_outlined, message: 'No retailers found')
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _Tile(
                      r: _filtered[i],
                      onTap: () => context.push(R.retailerLedgerPath(_filtered[i]['id'] as String)))))),
      ]));
  }

  Widget _chip(String label, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.3))),
    child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)));
}

class _Tile extends StatelessWidget {
  const _Tile({required this.r, required this.onTap});
  final Map<String,dynamic> r;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final outstanding = (r['outstanding_amount'] as num?)?.toDouble() ?? 0;
    final creditLimit = (r['credit_limit']        as num?)?.toDouble() ?? 0;
    final riskStatus  = r['risk_status'] as String? ?? 'healthy';
    final orders30d   = (r['orders_last_30d'] as num?)?.toInt() ?? 0;

    final Color rc = switch (riskStatus) {
      'over_limit'  => Colors.red,
      'near_limit'  => Colors.orange,
      'overdue_30d' => Colors.deepOrange,
      'overdue_15d' => Colors.orange,
      _             => outstanding > 0 ? Colors.blue : Colors.green,
    };
    final usePct = creditLimit > 0 ? (outstanding / creditLimit).clamp(0.0, 1.0) : 0.0;

    return InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: riskStatus == 'healthy' ? kBorder : rc.withValues(alpha: 0.4),
                width: riskStatus == 'healthy' ? 1 : 1.5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 40, height: 40,
                decoration: BoxDecoration(color: rc.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Center(child: Text(
                    (r['shop_name'] as String? ?? '?')[0].toUpperCase(),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: rc)))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r['shop_name'] as String? ?? '--',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              if (r['owner_name'] != null)
                Text(r['owner_name'] as String, style: const TextStyle(fontSize: 11, color: kTextSub)),
              Text('$orders30d orders (30d)', style: const TextStyle(fontSize: 10, color: kTextHint)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(Fmt.amount(outstanding),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                      color: outstanding > 0 ? Colors.orange : Colors.green)),
              const Text('outstanding', style: TextStyle(fontSize: 9, color: kTextHint)),
              if (riskStatus != 'healthy') ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: rc.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text(
                    switch(riskStatus) {
                      'over_limit'  => 'OVER LIMIT',
                      'near_limit'  => 'NEAR LIMIT',
                      'overdue_30d' => 'OVERDUE 30d',
                      'overdue_15d' => 'OVERDUE 15d',
                      _             => riskStatus.toUpperCase()
                    },
                    style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: rc))),
              ],
            ]),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: kTextHint, size: 18),
          ]),
          if (creditLimit > 0 && outstanding > 0) ...[
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Limit: ${Fmt.amount(creditLimit)}', style: const TextStyle(fontSize: 10, color: kTextSub)),
              Text('${(usePct * 100).toStringAsFixed(0)}% used',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: rc)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: usePct, minHeight: 5,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation(rc))),
          ],
        ])));
  }
}
