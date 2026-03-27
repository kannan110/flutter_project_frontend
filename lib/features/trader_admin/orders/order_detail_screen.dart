import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';

class OrderDetailScreen extends ConsumerStatefulWidget {
  const OrderDetailScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  Map<String, dynamic>? _order;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final data = await Supabase.instance.client.from('orders')
        .select('*, retailers(*), master_products(*), order_items(*)')
        .eq('id', widget.id).maybeSingle();
    if (mounted) setState(() { _order = data; _loading = false; });
  }

  Future<void> _updateStatus(String newStatus) async {
    final confirmed = await confirmDialog(context,
      title: 'Confirm', message: 'Change order status to "${newStatus.replaceAll('_', ' ')}"?',
      confirmText: 'Yes', confirmColor: AppTheme.primary);
    if (!confirmed) return;
    try {
      await Supabase.instance.client.from('orders').update({'status': newStatus}).eq('id', widget.id);
      showSuccess(context, 'Order ${newStatus.replaceAll('_', ' ')}');
      _load();
    } catch (e) { showError(context, e.toString()); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_order == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Order not found')));

    final user     = ref.watch(appUserProvider).valueOrNull;
    final status   = _order!['status'] as String? ?? 'pending';
    final retailer = _order!['retailers'] as Map<String, dynamic>?;
    final product  = _order!['master_products'] as Map<String, dynamic>?;
    final items    = _order!['order_items'] as List? ?? [];
    final rate     = items.isNotEmpty ? (items.first['rate_per_kg'] as num?)?.toDouble() ?? 0 : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Details'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Status + ID
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: const Border.fromBorderSide(BorderSide(color: Color(0xFFEEEEEE)))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              StatusBadge(status, StatusColors.order(status)),
              const Spacer(),
              Text(DateFormat('d MMM y').format(DateTime.tryParse(_order!['order_date'] ?? '') ?? DateTime.now()),
                  style: const TextStyle(fontSize: 13, color: Color(0xFF9E9E9E))),
            ]),
            const SizedBox(height: 10),
            Text(retailer?['shop_name'] ?? 'Unknown', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            if (retailer?['owner_name'] != null)
              Text(retailer!['owner_name'] as String, style: const TextStyle(fontSize: 13, color: Color(0xFF757575))),
            if (retailer?['phone'] != null)
              Text(retailer!['phone'] as String, style: const TextStyle(fontSize: 13, color: Color(0xFF757575))),
          ]),
        ),
        const SizedBox(height: 12),

        // Order details
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: const Border.fromBorderSide(BorderSide(color: Color(0xFFEEEEEE)))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionHeader('ORDER DETAILS'),
            InfoRow('Product',     product?['name'] ?? '—'),
            InfoRow('Birds',       '${_order!['estimated_birds'] ?? '—'}'),
            InfoRow('Quantity',    '${(_order!['total_quantity'] as num?)?.toStringAsFixed(2) ?? '—'} kg'),
            InfoRow('Rate',        rate > 0 ? '₹${rate.toStringAsFixed(2)}/kg' : '—'),
            InfoRow('Amount',      _order!['final_amount'] != null ? '₹${(_order!['final_amount'] as num).toStringAsFixed(2)}' : _order!['total_amount'] != null ? '₹${(_order!['total_amount'] as num).toStringAsFixed(2)}' : '—', valueColor: AppTheme.primary),
            InfoRow('Payment',     _order!['payment_type'] as String? ?? '—'),
            InfoRow('Source',      _order!['source'] as String? ?? 'trader'),
            if (_order!['notes'] != null) InfoRow('Notes', _order!['notes'] as String),
            if ((_order!['is_after_cutoff'] as bool?) == true)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: const Row(children: [
                  Icon(Icons.schedule, size: 14, color: Colors.orange),
                  SizedBox(width: 6),
                  Text('Placed after cutoff time', style: TextStyle(fontSize: 12, color: Colors.orange)),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 12),

        // Financial summary
        if ((_order!['collected_amount'] as num? ?? 0) > 0 || (_order!['balance_amount'] as num? ?? 0) > 0)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: const Border.fromBorderSide(BorderSide(color: Color(0xFFEEEEEE)))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionHeader('FINANCIAL'),
              InfoRow('Collected', '₹${(_order!['collected_amount'] as num? ?? 0).toStringAsFixed(2)}', valueColor: Colors.green),
              InfoRow('Balance',   '₹${(_order!['balance_amount'] as num? ?? 0).toStringAsFixed(2)}', valueColor: (_order!['balance_amount'] as num? ?? 0) > 0 ? Colors.orange : Colors.green),
            ]),
          ),
        const SizedBox(height: 20),

        // Actions
        if (user?.canManageOrders == true) ...[
          if (status == 'pending') ...[
            ElevatedButton.icon(
              onPressed: () => _updateStatus('confirmed'),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Confirm Order'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _updateStatus('cancelled'),
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel Order'),
              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.errorRed, side: const BorderSide(color: AppTheme.errorRed)),
            ),
          ],
          if (status == 'confirmed')
            OutlinedButton.icon(
              onPressed: () => _updateStatus('cancelled'),
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel Order'),
              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.errorRed, side: const BorderSide(color: AppTheme.errorRed)),
            ),
        ],
      ]),
    );
  }
}
