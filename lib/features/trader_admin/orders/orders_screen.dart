import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});
  @override ConsumerState<OrdersScreen> createState() => _S();
}
class _S extends ConsumerState<OrdersScreen> {
  final _c = Supabase.instance.client;
  List<Map<String,dynamic>> _orders = [];
  bool _loading = true;
  String _filter = 'all';
  static const _statuses = ['all','pending','confirmed','assigned','out_for_delivery','delivered','invoiced','closed','cancelled'];

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    if (mounted) setState(() => _loading = true);
    try {
      // orders: estimated_birds (NOT total_birds), total_amount, status, created_at
      var q = _c.from('orders')
          .select('id,status,estimated_birds,total_amount,created_at,retailers(shop_name)')
          .eq('trader_id', tid);
      if (_filter != 'all') q = q.eq('status', _filter);
      final data = await q.order('created_at', ascending: false).limit(200);
      if (mounted) setState(() { _orders = List<Map<String,dynamic>>.from(data); _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Orders'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
    floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(R.orderCreate),
        icon: const Icon(Icons.add), label: const Text('New Order')),
    body: Column(children: [
      SizedBox(height: 48, child: ListView.separated(
          scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: _statuses.length, separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            final s = _statuses[i];
            return ChoiceChip(
              label: Text(s == 'all' ? 'All' : s.replaceAll('_', ' '), style: const TextStyle(fontSize: 11)),
              selected: _filter == s, onSelected: (_) { if (mounted) setState(() => _filter = s); _load(); });
          })),
      const Divider(height: 1),
      Expanded(child: _loading ? const LoadingList() : _orders.isEmpty
          ? EmptyState(icon: Icons.shopping_bag_outlined, message: 'No orders', onAction: () => context.push(R.orderCreate), actionLabel: 'New Order')
          : RefreshIndicator(onRefresh: _load, child: ListView.separated(
              padding: const EdgeInsets.all(16), itemCount: _orders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final o = _orders[i];
                final r = o['retailers'] as Map<String,dynamic>?;
                final status = o['status'] as String? ?? 'pending';
                final date = DateTime.tryParse(o['created_at'] as String? ?? '');
                final amt = (o['total_amount'] as num?)?.toDouble() ?? 0;
                return InkWell(
                  onTap: () => context.push(R.orderDetailPath(o['id'])),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: const Border.fromBorderSide(BorderSide(color: kBorder))),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r?['shop_name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        const SizedBox(height: 4),
                        Row(children: [
                          StatusBadge(status, SC.order(status), small: true),
                          const SizedBox(width: 8),
                          if (date != null) Text(DateFormat('d MMM').format(date), style: const TextStyle(fontSize: 11, color: kTextHint)),
                        ]),
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('${o['estimated_birds'] ?? 0} birds', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        if (amt > 0) Text(Fmt.amount(amt), style: const TextStyle(fontSize: 12, color: kTextSub)),
                      ]),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right, color: kTextHint, size: 18),
                    ])));
              }))),
    ]),
  );
}
