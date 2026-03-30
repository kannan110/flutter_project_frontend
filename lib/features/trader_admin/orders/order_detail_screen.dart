import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  bool _actionLoading = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await Supabase.instance.client
          .from('orders')
          .select('*, retailers(*), master_products(*), order_items(*)')
          .eq('id', widget.id)
          .maybeSingle();
      if (mounted) setState(() { _order = data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateStatus(String newStatus, String label) async {
    final ok = await confirmDialog(context,
      title: label,
      message: 'Are you sure you want to $label this order?',
      confirmText: label,
      confirmColor: newStatus == 'cancelled' ? AppTheme.errorRed : AppTheme.primary,
    );
    if (!ok || !mounted) return;
    setState(() => _actionLoading = true);
    try {
      await Supabase.instance.client.from('orders').update({'status': newStatus}).eq('id', widget.id);
      if (mounted) { showSuccess(context, 'Order $label'); await _load(); }
    } catch (e) {
      if (mounted) {
        final raw = e.toString();
        final msg = raw.contains('Invalid order transition') ? 'Cannot change order from this status'
            : raw.contains('Credit limit') ? 'Retailer credit limit exceeded'
            : 'Update failed — please try again';
        showError(context, msg);
      }
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_order == null) return Scaffold(appBar: AppBar(title: const Text('Order')), body: const Center(child: Text('Order not found')));

    final user      = ref.watch(appUserProvider).valueOrNull;
    final status    = _order!['status'] as String? ?? 'pending';
    final retailer  = _order!['retailers']      as Map<String, dynamic>?;
    final product   = _order!['master_products'] as Map<String, dynamic>?;
    final items     = (_order!['order_items'] as List?) ?? [];
    final rate      = items.isNotEmpty ? (items.first['rate_per_kg'] as num?)?.toDouble() ?? 0 : 0.0;
    final qty       = (_order!['total_quantity']    as num?)?.toDouble() ?? 0;
    final amount    = ((_order!['final_amount'] ?? _order!['total_amount']) as num?)?.toDouble() ?? 0;
    final collected = (_order!['collected_amount']  as num?)?.toDouble() ?? 0;
    final balance   = (_order!['balance_amount']    as num?)?.toDouble() ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Order Details'),
          actions: [IconButton(icon: const Icon(Icons.refresh_outlined), onPressed: _load)]),
      body: Stack(children: [
        ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 120), children: [
          // Header
          _Box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              StatusBadge(status, StatusColors.order(status)),
              const Spacer(),
              Text(DateFormat('d MMM y').format(DateTime.tryParse(_order!['order_date'] as String? ?? '') ?? DateTime.now()),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF9E9E9E))),
            ]),
            const SizedBox(height: 10),
            Text(retailer?['shop_name'] ?? 'Unknown',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            if (retailer?['owner_name'] != null)
              Text(retailer!['owner_name'] as String, style: const TextStyle(fontSize: 13, color: Color(0xFF757575))),
            if (retailer?['phone'] != null)
              Text(retailer!['phone'] as String, style: const TextStyle(fontSize: 13, color: Color(0xFF9E9E9E))),
          ])),
          const SizedBox(height: 12),

          // Details
          _Box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionHeader('ORDER DETAILS'),
            InfoRow('Product',  product?['name'] ?? '—'),
            InfoRow('Birds',    '${_order!['estimated_birds'] ?? '—'}'),
            InfoRow('Quantity', qty > 0 ? '${qty.toStringAsFixed(2)} kg' : '—'),
            InfoRow('Rate',     rate > 0 ? '₹${rate.toStringAsFixed(2)}/kg' : '—'),
            InfoRow('Amount',   amount > 0 ? '₹${amount.toStringAsFixed(2)}' : '—', valueColor: AppTheme.primary),
            InfoRow('Payment',  (_order!['payment_type'] as String? ?? '—').toUpperCase()),
            if (_order!['notes'] != null) InfoRow('Notes', _order!['notes'] as String),
            if ((_order!['is_after_cutoff'] as bool?) == true)
              Container(margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: const Row(children: [
                  Icon(Icons.schedule, size: 14, color: Colors.orange), SizedBox(width: 6),
                  Text('Placed after cutoff time', style: TextStyle(fontSize: 12, color: Colors.orange)),
                ])),
          ])),

          // Financial
          if (collected > 0 || balance > 0) ...[
            const SizedBox(height: 12),
            _Box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionHeader('FINANCIAL'),
              InfoRow('Collected', '₹${collected.toStringAsFixed(2)}', valueColor: Colors.green),
              InfoRow('Balance',   '₹${balance.toStringAsFixed(2)}',
                  valueColor: balance > 0 ? Colors.orange : Colors.green),
            ])),
          ],
        ]),

        // Bottom action bar
        if (user?.canManageOrders == true)
          Positioned(left: 0, right: 0, bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
              decoration: BoxDecoration(color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 10, offset: const Offset(0, -3))]),
              child: _actionLoading
                  ? const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
                  : _buildActions(status),
            )),
      ]),
    );
  }

  Widget _buildActions(String status) {
    switch (status) {
      case 'pending':
        return Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: () => _updateStatus('cancelled', 'Cancel'),
            style: OutlinedButton.styleFrom(foregroundColor: AppTheme.errorRed, side: const BorderSide(color: AppTheme.errorRed), minimumSize: const Size(0, 48)),
            child: const Text('Cancel'),
          )),
          const SizedBox(width: 12),
          Expanded(child: ElevatedButton(
            onPressed: () => _updateStatus('confirmed', 'Confirm'),
            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 48)),
            child: const Text('Confirm Order'),
          )),
        ]);
      case 'confirmed':
        return Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: () => _updateStatus('cancelled', 'Cancel'),
            style: OutlinedButton.styleFrom(foregroundColor: AppTheme.errorRed, side: const BorderSide(color: AppTheme.errorRed), minimumSize: const Size(0, 48)),
            child: const Text('Cancel Order'),
          )),
          const SizedBox(width: 12),
          Expanded(child: _InfoPill('Ready for dispatch')),
        ]);
      case 'assigned': return _InfoPill('Assigned to agent');
      case 'picked_up': return _InfoPill('Picked up from farm');
      case 'out_for_delivery': return _InfoPill('Out for delivery');
      case 'delivered': return _InfoPill('Delivered — pending approval');
      case 'approved':  return _InfoPill('Approved ✓');
      case 'invoiced':  return _InfoPill('Invoiced ✓');
      case 'cancelled': return _InfoPill('Cancelled');
      default: return const SizedBox.shrink();
    }
  }
}

class _Box extends StatelessWidget {
  const _Box(this.child);
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: const Border.fromBorderSide(BorderSide(color: Color(0xFFEEEEEE)))),
    child: child,
  );
}

class _InfoPill extends StatelessWidget {
  const _InfoPill(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    height: 48, alignment: Alignment.center,
    decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(10)),
    child: Text(text, style: const TextStyle(fontSize: 13, color: Color(0xFF757575), fontWeight: FontWeight.w500)),
  );
}
