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
  Map<String,dynamic>? _invoice; // Bug 5: load invoice to show real amount
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
    // Bug 5 fix: also fetch invoice so we show real billed amount
    final inv = await _c.from('invoices')
        .select('*').eq('order_id', widget.id).maybeSingle();
    if (mounted) setState(() { _order = o; _items = List<Map<String,dynamic>>.from(items); _invoice = inv; _loading = false; });
  }

  Future<void> _updateStatus(String s) async {
    try { await _c.from('orders').update({'status': s}).eq('id', widget.id); _load();
          if (mounted) showSuccess(context, 'Status updated'); }
    catch (e) { if (mounted) showError(context, e.toString()); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingList());
    if (_order == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Not found')));
    final r       = _order!['retailers'] as Map<String,dynamic>?;
    final status  = _order!['status'] as String? ?? 'pending';
    final date    = DateTime.tryParse(_order!['created_at'] as String? ?? '');
    final birds   = _order!['estimated_birds'] as int? ?? 0;
    final totalKg = (_order!['total_quantity'] as num?)?.toDouble() ?? 0;
    final hasInv  = _invoice != null;

    // Bug 5: use invoice amount if available, else order estimate
    final displayAmt = hasInv
        ? (_invoice!['total_amount'] as num?)?.toDouble() ?? 0
        : (_order!['total_amount'] as num?)?.toDouble() ?? 0;
    final balAmt = hasInv
        ? (_invoice!['balance_amount'] as num?)?.toDouble() ?? 0
        : (_order!['balance_amount'] as num?)?.toDouble() ?? 0;
    final collAmt = hasInv
        ? (_invoice!['collected_amount'] as num?)?.toDouble() ?? 0
        : (_order!['collected_amount'] as num?)?.toDouble() ?? 0;
    final rateKg  = hasInv
        ? (_invoice!['price_per_kg'] as num?)?.toDouble()
        : (_order!['final_price'] as num?)?.toDouble();
    final invKg   = hasInv ? (_invoice!['quantity_kg'] as num?)?.toDouble() : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Order Detail'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: ListView(padding: const EdgeInsets.all(16), children: [

        // Customer
        WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r?['shop_name'] as String? ?? '—', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          if (r?['owner_name'] != null) Text(r!['owner_name'] as String, style: const TextStyle(fontSize: 13, color: kTextSub)),
          if (r?['phone'] != null) Text(r!['phone'] as String, style: const TextStyle(fontSize: 12, color: kTextHint)),
          const SizedBox(height: 8),
          Row(children: [
            StatusBadge(status, SC.order(status)), const SizedBox(width: 8),
            if (date != null) Text(DateFormat('d MMM y').format(date), style: const TextStyle(fontSize: 11, color: kTextHint)),
          ]),
        ])),
        const SizedBox(height: 12),

        // Order items
        WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader('ORDER ITEMS'),
          if (_items.isEmpty) const Text('No items', style: TextStyle(color: kTextHint, fontSize: 13))
          else ..._items.map((item) {
            final p = item['master_products'] as Map<String,dynamic>?;
            final w = (item['total_weight'] as num?)?.toDouble();
            return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
              Expanded(child: Text(p?['name'] as String? ?? '—', style: const TextStyle(fontSize: 13))),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (item['bird_count'] != null) Text('${item['bird_count']} birds', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                if (w != null) Text('${w.toStringAsFixed(2)} kg', style: const TextStyle(fontSize: 11, color: kTextSub)),
              ]),
            ]));
          }),
        ])),
        const SizedBox(height: 12),

        // Amounts — Bug 5: show invoice vs estimate clearly
        WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Amount', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const Spacer(),
            if (hasInv) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.green.shade200)),
              child: const Text('Billed ✓', style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.w700))),
            if (!hasInv) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.orange.shade200)),
              child: const Text('Estimate', style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.w700))),
          ]),
          const Divider(height: 14),
          if (birds > 0)   InfoRow('Birds ordered', '$birds'),
          if (totalKg > 0) InfoRow('Weight ordered', '${totalKg.toStringAsFixed(2)} kg'),
          if (hasInv) ...[
            InfoRow('Delivered weight', '${(invKg ?? 0).toStringAsFixed(2)} kg'),
            if (rateKg != null) InfoRow('Rate', '₹${rateKg.toStringAsFixed(2)}/kg'),
          ],
          if (_order!['payment_type'] != null) InfoRow('Payment', (_order!['payment_type'] as String).toUpperCase()),
          const Divider(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(hasInv ? 'Invoice Amount' : 'Estimated Amount', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            Text(Fmt.amount(displayAmt), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: kPrimary)),
          ]),
          if (hasInv) ...[
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Collected', style: TextStyle(fontSize: 12, color: kTextSub)),
              Text(Fmt.amount(collAmt), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.green)),
            ]),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Balance', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              Text(Fmt.amount(balAmt), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: balAmt > 0 ? Colors.orange : Colors.green)),
            ]),
          ] else const Text('Actual amount set at delivery approval', style: TextStyle(fontSize: 11, color: kTextHint)),
          if (_order!['notes'] != null) ...[const Divider(height: 12), InfoRow('Notes', _order!['notes'] as String)],
        ])),

        // Invoice link
        if (hasInv) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => context.go(R.invoiceDetailPath(_invoice!['id'])),
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            label: Text('View Invoice ${_invoice!['invoice_number'] ?? ''}'),
          ),
        ],
        const SizedBox(height: 16),

        // Actions
        if (status == 'pending') ...[
          ElevatedButton(onPressed: () => _updateStatus('confirmed'), child: const Text('Confirm Order')),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: () async {
            final ok = await confirmDialog(context, title: 'Cancel Order', message: 'Cancel this order?');
            if (ok) _updateStatus('cancelled');
          }, style: OutlinedButton.styleFrom(foregroundColor: kError, side: const BorderSide(color: kError)), child: const Text('Cancel Order')),
        ] else if (status == 'confirmed') ...[
          OutlinedButton.icon(onPressed: () => context.go(R.dispatch), icon: const Icon(Icons.local_shipping_outlined, size: 18), label: const Text('Assign to Batch → Dispatch')),
        ],
      ]),
    );
  }
}
