import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

final _ordersProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, traderId) async {
  if (traderId.isEmpty) return <Map<String, dynamic>>[];
  return List<Map<String, dynamic>>.from(
    await Supabase.instance.client
        .from('orders')
        .select('*, retailers(id,shop_name,owner_name,phone), master_products(id,name,category)')
        .eq('trader_id', traderId)
        .order('created_at', ascending: false)
        .limit(100),
  );
});

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});
  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(appUserProvider);
    if (userAsync.isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final traderId = userAsync.valueOrNull?.traderId ?? '';
    final async    = traderId.isNotEmpty ? ref.watch(_ordersProvider(traderId)) : const AsyncValue<List<Map<String,dynamic>>>.data([]);

    return Scaffold(
      backgroundColor: AppTheme.bgGrey,
      appBar: AppBar(
        title: const Text('Orders'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: () => context.go(Routes.orderCreate)),
        ],
      ),
      body: Column(children: [
        // Filter chips
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: ['all','pending','confirmed','out_for_delivery','delivered','approved','invoiced','cancelled']
                .map((s) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(s == 'all' ? 'All' : s.replaceAll('_', ' ').capitalize()),
                    selected: _filter == s,
                    onSelected: (_) => setState(() => _filter = s),
                    selectedColor: AppTheme.primary,
                    labelStyle: TextStyle(
                      color: _filter == s ? Colors.white : null,
                      fontSize: 12, fontWeight: FontWeight.w500,
                    ),
                  ),
                )).toList(),
          ),
        ),
        Expanded(child: async.when(
          loading: () => const LoadingList(),
          error:   (e, _) => Center(child: Text('Error: $e')),
          data:    (orders) {
            final filtered = _filter == 'all' ? orders : orders.where((o) => o['status'] == _filter).toList();
            if (filtered.isEmpty) return const EmptyState(icon: Icons.shopping_cart_outlined, message: 'No orders found', sub: 'Tap + to create a new order');
            return RefreshIndicator(
              onRefresh: () => ref.refresh(_ordersProvider(traderId).future),
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _OrderCard(filtered[i]),
              ),
            );
          },
        )),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go(Routes.orderCreate),
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New Order', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard(this.order);
  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final retailer = order['retailers'] as Map<String, dynamic>?;
    final product  = order['master_products'] as Map<String, dynamic>?;
    final status   = order['status'] as String? ?? 'pending';
    final amount   = (order['final_amount'] ?? order['total_amount'] as num?)?.toDouble() ?? 0;
    final date     = DateTime.tryParse(order['order_date'] as String? ?? '') ?? DateTime.now();

    return InkWell(
      onTap: () => context.go(Routes.orderDetailPath(order['id'] as String)),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12),
          border: const Border.fromBorderSide(BorderSide(color: Color(0xFFEEEEEE))),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(retailer?['shop_name'] ?? 'Unknown Retailer',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            StatusBadge(status, StatusColors.order(status)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.calendar_today_outlined, size: 13, color: Colors.grey.shade500),
            const SizedBox(width: 4),
            Text(DateFormat('d MMM y').format(date), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(width: 16),
            Icon(Icons.set_meal_outlined, size: 13, color: Colors.grey.shade500),
            const SizedBox(width: 4),
            Text(product?['name'] ?? '—', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            if ((order['total_quantity'] as num?) != null) ...[
              const SizedBox(width: 6),
              Text('${(order['total_quantity'] as num).toStringAsFixed(1)} kg',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ]),
          if (amount > 0) ...[
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.currency_rupee, size: 13, color: AppTheme.primary),
              Text(amount.toStringAsFixed(2), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primary)),
              if ((order['balance_amount'] as num?)?.toDouble() != null && (order['balance_amount'] as num).toDouble() > 0) ...[
                const SizedBox(width: 10),
                Text('Bal: ₹${(order['balance_amount'] as num).toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 12, color: Colors.orange)),
              ],
            ]),
          ],
        ]),
      ),
    );
  }
}



extension on String {
  String capitalize() => isEmpty ? this : this[0].toUpperCase() + substring(1);
}
