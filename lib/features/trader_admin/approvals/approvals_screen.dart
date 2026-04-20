import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class ApprovalsScreen extends ConsumerStatefulWidget {
  const ApprovalsScreen({super.key});
  @override ConsumerState<ApprovalsScreen> createState() => _S();
}
class _S extends ConsumerState<ApprovalsScreen> {
  final _c = Supabase.instance.client;
  List<Map<String,dynamic>> _items = [];
  bool _loading = true;
  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    if (mounted) setState(() => _loading = true);
    try {
      // deliveries: status=delivered, approval_status=pending
      final data = await _c.from('deliveries')
          .select('id,delivered_total_weight,received_total_weight,collected_amount,'
                  'delivered_bird_count,is_partial_delivery,delivered_at,created_at,'
                  'orders(id,estimated_birds,total_quantity,fulfilled_birds,fulfilled_quantity,'
                    'partial_count,is_partial_delivery,retailers(shop_name)),'
                  'delivery_agents(name)')
          .eq('trader_id', tid).eq('status','delivered').eq('approval_status','pending')
          .order('delivered_at', ascending: false);
      if (mounted) setState(() { _items = List<Map<String,dynamic>>.from(data); _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Widget _chip(String label, IconData icon, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: c), const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c)),
    ]));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Row(children: [
        const Text('Pending Approvals'),
        if (_items.isNotEmpty) ...[const SizedBox(width: 8),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(10)),
            child: Text('${_items.length}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)))],
      ]),
      actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
    ),
    body: _loading ? const LoadingList() : _items.isEmpty
        ? const EmptyState(icon: Icons.fact_check_outlined, message: 'No pending approvals')
        : RefreshIndicator(onRefresh: _load, child: ListView.separated(
            padding: const EdgeInsets.all(16), itemCount: _items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final d = _items[i];
              final o = d['orders'] as Map<String,dynamic>?;
              final r = o?['retailers'] as Map<String,dynamic>?;
              final a = d['delivery_agents'] as Map<String,dynamic>?;
              // weight: received_total_weight preferred, fallback to delivered_total_weight
              final w         = ((d['received_total_weight'] ?? d['delivered_total_weight']) as num?)?.toDouble() ?? 0;
              final birds      = (d['delivered_bird_count'] as num?)?.toInt() ?? 0;
              final isPartial  = d['is_partial_delivery'] == true;
              final orderMap   = d['orders'] as Map<String,dynamic>?;
              final attempt    = (orderMap?['partial_count'] as num?)?.toInt() ?? 1;
              final totalBirds = (orderMap?['estimated_birds'] as num?)?.toInt() ?? 0;
              final fulfilledB = (orderMap?['fulfilled_birds'] as num?)?.toInt() ?? 0;
              final pct        = totalBirds > 0 ? (fulfilledB / totalBirds).clamp(0.0, 1.0) : 1.0;
              final deliveredAt = DateTime.tryParse(d['delivered_at'] as String? ?? '');
              final cash       = (d['collected_amount'] as num?)?.toDouble() ?? 0;

              return InkWell(
                onTap: () => context.push(R.approvalDetailPath(d['id'])),
                borderRadius: BorderRadius.circular(12),
                child: Container(padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade200, width: 1.5)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r?['shop_name'] as String? ?? '—',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text('Agent: ${a?['name'] ?? '—'}',
                            style: const TextStyle(fontSize: 12, color: kTextSub)),
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        const StatusBadge('review', Colors.orange),
                        if (isPartial) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(4)),
                            child: Text('Partial #$attempt',
                                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.deepOrange))),
                        ],
                      ]),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right, color: kTextHint, size: 18),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      _chip('${w.toStringAsFixed(1)} kg', Icons.scale_outlined, Colors.teal),
                      if (birds > 0) ...[const SizedBox(width: 6), _chip('$birds birds', Icons.numbers, Colors.blue)],
                      if (cash > 0) ...[const SizedBox(width: 6), _chip(Fmt.amount(cash), Icons.money_outlined, Colors.green)],
                      if (deliveredAt != null) ...[
                        const Spacer(),
                        Text(DateFormat('d MMM, h:mm a').format(deliveredAt),
                            style: const TextStyle(fontSize: 10, color: kTextHint)),
                      ],
                    ]),
                    if (isPartial) ...[
                      const SizedBox(height: 8),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('Order: $fulfilledB / $totalBirds birds fulfilled',
                            style: const TextStyle(fontSize: 10, color: kTextSub)),
                        Text('${(pct * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.orange)),
                      ]),
                      const SizedBox(height: 3),
                      ClipRRect(borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                              value: pct, minHeight: 5,
                              backgroundColor: Colors.orange.shade100,
                              valueColor: const AlwaysStoppedAnimation(Colors.orange))),
                    ],
                  ])),
              );
            })),
  );
}
