import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

final _batchesProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, traderId) async {
  return List<Map<String, dynamic>>.from(
    await Supabase.instance.client.from('delivery_batches')
        .select('*, delivery_agents(id,name,phone,vehicle_no,is_online)')
        .eq('trader_id', traderId)
        .inFilter('status', ['assigned', 'picked_up', 'out_for_delivery'])
        .order('created_at', ascending: false),
  );
});

final _confirmedOrdersProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, traderId) async {
  return List<Map<String, dynamic>>.from(
    await Supabase.instance.client.from('orders')
        .select('*, retailers(id,shop_name), master_products(id,name)')
        .eq('trader_id', traderId).eq('status', 'confirmed')
        .order('order_date', ascending: false),
  );
});

class DispatchScreen extends ConsumerWidget {
  const DispatchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final traderId = ref.watch(appUserProvider).valueOrNull?.traderId ?? '';
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Dispatch'),
          bottom: const TabBar(tabs: [Tab(text: 'Active Batches'), Tab(text: 'Assign Orders')]),
        ),
        body: TabBarView(children: [
          _ActiveBatchesTab(traderId: traderId, ref: ref),
          _AssignOrdersTab(traderId: traderId, ref: ref),
        ]),
      ),
    );
  }
}

class _ActiveBatchesTab extends StatelessWidget {
  const _ActiveBatchesTab({required this.traderId, required this.ref});
  final String traderId;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final async = traderId.isNotEmpty ? ref.watch(_batchesProvider(traderId)) : const AsyncValue<List<Map<String, dynamic>>>.data([]);
    return async.when(
      loading: () => const LoadingList(),
      error:   (e, _) => Center(child: Text('Error: $e')),
      data:    (batches) {
        if (batches.isEmpty) return const EmptyState(icon: Icons.local_shipping_outlined, message: 'No active batches', sub: 'Assign confirmed orders to create a batch');
        return RefreshIndicator(
          onRefresh: () => ref.refresh(_batchesProvider(traderId).future),
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: batches.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final b = batches[i];
              final agent  = b['delivery_agents'] as Map<String, dynamic>?;
              final status = b['status'] as String? ?? 'assigned';
              return InkWell(
                onTap: () => context.go('/dispatch/batch/${b['id']}'),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                      border: const Border.fromBorderSide(BorderSide(color: Color(0xFFEEEEEE)))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      StatusBadge(status.replaceAll('_', ' '), StatusColors.order(status)),
                      const Spacer(),
                      Text(DateFormat('d MMM HH:mm').format(DateTime.tryParse(b['created_at'] as String? ?? '') ?? DateTime.now()),
                          style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E))),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Icon(Icons.person_outline, size: 14, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Text(agent?['name'] ?? '—', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(width: 4),
                      if (agent?['is_online'] == true) Container(width: 8, height: 8,
                          decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: [
                      Icon(Icons.inventory_2_outlined, size: 14, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Text('${b['total_orders']} orders · ${(b['total_weight'] as num?)?.toStringAsFixed(1) ?? 0} kg · ₹${(b['total_amount'] as num?)?.toStringAsFixed(0) ?? 0}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF757575))),
                    ]),
                    if (b['farm_name'] != null) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        Icon(Icons.agriculture_outlined, size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(b['farm_name'] as String, style: const TextStyle(fontSize: 12, color: Color(0xFF757575))),
                      ]),
                    ],
                  ]),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _AssignOrdersTab extends StatefulWidget {
  const _AssignOrdersTab({required this.traderId, required this.ref});
  final String traderId;
  final WidgetRef ref;

  @override
  State<_AssignOrdersTab> createState() => _AssignOrdersTabState();
}

class _AssignOrdersTabState extends State<_AssignOrdersTab> {
  final Set<String> _selected = {};
  String? _selectedAgent;
  bool _submitting = false;

  Future<List<Map<String, dynamic>>> _loadAgents() async {
    return List<Map<String, dynamic>>.from(
      await Supabase.instance.client.from('delivery_agents')
          .select('id,name,vehicle_no,is_online')
          .eq('trader_id', widget.traderId).eq('is_active', true).order('name'));
  }

  Future<void> _dispatch(List<Map<String, dynamic>> orders) async {
    if (_selected.isEmpty) { showError(context, 'Select at least one order'); return; }
    if (_selectedAgent == null) { showError(context, 'Select a delivery agent'); return; }
    setState(() => _submitting = true);
    try {
      final selectedOrders = orders.where((o) => _selected.contains(o['id'] as String)).toList();
      final totalBirds  = selectedOrders.fold<int>(0, (s, o) => s + ((o['estimated_birds'] as int?) ?? 0));
      final totalWeight = selectedOrders.fold<double>(0, (s, o) => s + ((o['total_quantity'] as num?)?.toDouble() ?? 0));
      final totalAmount = selectedOrders.fold<double>(0, (s, o) => s + ((o['total_amount'] as num?)?.toDouble() ?? 0));

      final batch = await Supabase.instance.client.from('delivery_batches').insert({
        'trader_id': widget.traderId, 'delivery_agent_id': _selectedAgent,
        'status': 'assigned', 'total_orders': _selected.length,
        'total_birds': totalBirds, 'total_weight': totalWeight, 'total_amount': totalAmount,
      }).select().single();
      final batchId = batch['id'] as String;

      for (final orderId in _selected) {
        final order = orders.firstWhere((o) => o['id'] == orderId);
        await Supabase.instance.client.from('deliveries').insert({
          'trader_id': widget.traderId, 'order_id': orderId,
          'delivery_agent_id': _selectedAgent, 'batch_id': batchId,
          'status': 'assigned', 'expected_bird_count': order['estimated_birds'],
          'expected_total_weight': order['total_quantity'],
        });
        await Supabase.instance.client.from('orders').update({'status': 'assigned', 'batch_id': batchId}).eq('id', orderId);
      }

      if (mounted) {
        showSuccess(context, 'Batch created with ${_selected.length} orders');
        setState(() { _selected.clear(); _selectedAgent = null; });
        widget.ref.refresh(_batchesProvider(widget.traderId));
        widget.ref.refresh(_confirmedOrdersProvider(widget.traderId));
      }
    } catch (e) {
      if (mounted) showError(context, e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = widget.traderId.isNotEmpty
        ? widget.ref.watch(_confirmedOrdersProvider(widget.traderId))
        : const AsyncValue<List<Map<String, dynamic>>>.data([]);

    return ordersAsync.when(
      loading: () => const LoadingList(),
      error:   (e, _) => Center(child: Text('Error: $e')),
      data:    (orders) {
        if (orders.isEmpty) return const EmptyState(icon: Icons.check_circle_outline, message: 'No confirmed orders', sub: 'Confirm orders first, then assign them here');
        return Column(children: [
          // Agent selector
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _loadAgents(),
            builder: (_, snap) {
              final agents = snap.data ?? [];
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: DropdownButtonFormField<String>(
                  value: _selectedAgent,
                  hint: const Text('Select delivery agent'),
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.person_outline, size: 20)),
                  items: agents.map((a) => DropdownMenuItem(
                    value: a['id'] as String,
                    child: Row(children: [
                      Text(a['name'] as String),
                      if (a['is_online'] == true) ...[
                        const SizedBox(width: 6),
                        Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                      ],
                      if (a['vehicle_no'] != null) ...[
                        const SizedBox(width: 6),
                        Text('· ${a['vehicle_no']}', style: const TextStyle(fontSize: 12, color: Color(0xFF9E9E9E))),
                      ],
                    ]),
                  )).toList(),
                  onChanged: (v) => setState(() => _selectedAgent = v),
                ),
              );
            },
          ),
          // Orders list
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: orders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) {
                final o = orders[i];
                final id = o['id'] as String;
                final retailer = o['retailers'] as Map<String, dynamic>?;
                final product  = o['master_products'] as Map<String, dynamic>?;
                final selected = _selected.contains(id);
                return InkWell(
                  onTap: () => setState(() => selected ? _selected.remove(id) : _selected.add(id)),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.primary.withOpacity(0.07) : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: selected ? AppTheme.primary : const Color(0xFFEEEEEE), width: selected ? 1.5 : 1),
                    ),
                    child: Row(children: [
                      Checkbox(value: selected, onChanged: (_) => setState(() => selected ? _selected.remove(id) : _selected.add(id)),
                          activeColor: AppTheme.primary, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      const SizedBox(width: 8),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(retailer?['shop_name'] ?? '—', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        Text('${product?['name'] ?? '—'} · ${(o['total_quantity'] as num?)?.toStringAsFixed(1) ?? '?'} kg',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E))),
                      ])),
                      Text('₹${(o['total_amount'] as num?)?.toStringAsFixed(0) ?? '0'}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                    ]),
                  ),
                );
              },
            ),
          ),
          if (_selected.isNotEmpty)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ElevatedButton(
                  onPressed: _submitting ? null : () => _dispatch(orders),
                  child: _submitting
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('Dispatch ${_selected.length} Order${_selected.length > 1 ? 's' : ''}'),
                ),
              ),
            ),
        ]);
      },
    );
  }
}
