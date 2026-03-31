import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class OrderDetailScreen extends ConsumerStatefulWidget {
  const OrderDetailScreen({super.key, required this.id});
  final String id;
  @override ConsumerState<OrderDetailScreen> createState() => _S();
}
class _S extends ConsumerState<OrderDetailScreen> {
  final _c = Supabase.instance.client;
  Map<String,dynamic>? _order;
  List<Map<String,dynamic>> _items = [];
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final o = await _c.from('orders')
        .select('*,retailers(shop_name,owner_name,phone,address)')
        .eq('id', widget.id).maybeSingle();
    final items = await _c.from('order_items')
        .select('*,master_products(name)').eq('order_id', widget.id);
    if (mounted) setState(() { _order = o; _items = List<Map<String,dynamic>>.from(items); _loading = false; });
  }

  Future<void> _updateStatus(String status) async {
    try {
      await _c.from('orders').update({'status': status}).eq('id', widget.id);
      _load();
      if (mounted) showSuccess(context, 'Status updated to ${status.replaceAll("_"," ")}');
    } catch (e) { if (mounted) showError(context, e.toString()); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingList());
    if (_order == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Order not found')));
    final r = _order!['retailers'] as Map<String,dynamic>?;
    final status = _order!['status'] as String? ?? 'pending';
    final date = DateTime.tryParse(_order!['created_at'] as String? ?? '');
    final birds = _order!['estimated_birds'] as int? ?? 0;
    final amt = (_order!['total_amount'] as num?)?.toDouble() ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Order Detail'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r?['shop_name'] as String? ?? '—', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          if (r?['owner_name'] != null) Text(r!['owner_name'] as String, style: const TextStyle(fontSize: 13, color: kTextSub)),
          if (r?['phone'] != null) Text(r!['phone'] as String, style: const TextStyle(fontSize: 12, color: kTextHint)),
          const SizedBox(height: 10),
          Row(children: [
            StatusBadge(status, SC.order(status)), const SizedBox(width: 8),
            if (date != null) Text(DateFormat('d MMM y').format(date), style: const TextStyle(fontSize: 12, color: kTextHint)),
          ]),
        ])),
        const SizedBox(height: 12),
        WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader('ORDER ITEMS'),
          if (_items.isEmpty) const Text('No items', style: TextStyle(color: kTextHint, fontSize: 13))
          else ..._items.map((item) {
            final p = item['master_products'] as Map<String,dynamic>?;
            return Padding(padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(child: Text(p?['name'] as String? ?? '—', style: const TextStyle(fontSize: 13))),
                if (item['bird_count'] != null) Text('${item['bird_count']} birds', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ]));
          }),
          const Divider(height: 18),
          // orders: estimated_birds (correct column name)
          InfoRow('Estimated Birds', '$birds'),
          if (amt > 0) InfoRow('Total Amount', Fmt.amount(amt)),
          if (_order!['payment_type'] != null) InfoRow('Payment Type', (_order!['payment_type'] as String).toUpperCase()),
          if (_order!['notes'] != null) InfoRow('Notes', _order!['notes'] as String),
        ])),
        const SizedBox(height: 20),
        if (status == 'pending') ...[
          ElevatedButton(onPressed: () => _updateStatus('confirmed'), child: const Text('Confirm Order')),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: () async {
            final ok = await confirmDialog(context, title: 'Cancel Order', message: 'Cancel this order?');
            if (ok) _updateStatus('cancelled');
          }, style: OutlinedButton.styleFrom(foregroundColor: kError, side: const BorderSide(color: kError)), child: const Text('Cancel Order')),
        ] else if (status == 'confirmed') ...[
          OutlinedButton(onPressed: () => context.go(R.dispatch), child: const Text('Assign to Batch → Dispatch')),
        ],
      ]),
    );
  }
}
