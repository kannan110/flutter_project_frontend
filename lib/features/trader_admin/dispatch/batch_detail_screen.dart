import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class BatchDetailScreen extends ConsumerStatefulWidget {
  const BatchDetailScreen({super.key, required this.id});
  final String id;
  @override ConsumerState<BatchDetailScreen> createState() => _S();
}
class _S extends ConsumerState<BatchDetailScreen> {
  final _c = Supabase.instance.client;
  Map<String,dynamic>? _batch;
  List<Map<String,dynamic>> _deliveries = [];
  List<Map<String,dynamic>> _confirmedOrders = [];
  bool _loading = true, _submitting = false;
  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    setState(() => _loading = true);
    final b = await _c.from('delivery_batches').select('*,delivery_agents(name,vehicle_no,phone)').eq('id', widget.id).maybeSingle();
    final d = await _c.from('deliveries').select('id,status,orders(id,estimated_birds,retailers(shop_name))').eq('batch_id', widget.id);
    // confirmed orders not yet in this batch
    final co = await _c.from('orders').select('id,estimated_birds,retailers(shop_name)').eq('trader_id', tid!).eq('status','confirmed');
    if (mounted) setState(() { _batch = b; _deliveries = List<Map<String,dynamic>>.from(d); _confirmedOrders = List<Map<String,dynamic>>.from(co); _loading = false; });
  }

  Future<void> _addOrder(String orderId) async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    try {
      // deliveries: trader_id, order_id, delivery_agent_id, batch_id, status
      await _c.from('deliveries').insert({
        'batch_id': widget.id, 'trader_id': tid,
        'order_id': orderId, 'delivery_agent_id': _batch?['delivery_agent_id'],
        'status': 'assigned',
      });
      _load();
    } catch (e) { if (mounted) showError(context, e.toString()); }
  }

  Future<void> _start() async {
    if (_deliveries.isEmpty) { showError(context, 'Add at least one order'); return; }
    final ok = await confirmDialog(context, title: 'Start Delivery', message: 'Start all ${_deliveries.length} deliveries?', confirmText: 'Start', confirmColor: kPrimary);
    if (!ok) return;
    setState(() => _submitting = true);
    try {
      await _c.rpc('start_batch_delivery', params: {'p_batch_id': widget.id});
      _load();
      if (mounted) showSuccess(context, 'Batch started ✓');
    } catch (e) { if (mounted) showError(context, e.toString()); }
    finally { if (mounted) setState(() => _submitting = false); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingList());
    if (_batch == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Not found')));
    final a = _batch!['delivery_agents'] as Map<String,dynamic>?;
    final status = _batch!['status'] as String? ?? 'assigned';

    return Scaffold(
      appBar: AppBar(title: const Text('Batch Detail'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(a?['name'] as String? ?? '—', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))), StatusBadge(status, SC.order(status))]),
          if (a?['vehicle_no'] != null) Text('Vehicle: ${a!['vehicle_no']}', style: const TextStyle(fontSize: 12, color: kTextSub)),
        ])),
        const SizedBox(height: 14),
        const SectionHeader('DELIVERIES IN BATCH'),
        if (_deliveries.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('No orders assigned yet', style: TextStyle(color: kTextHint)))),
        ..._deliveries.map((d) {
          final o = d['orders'] as Map<String,dynamic>?;
          final r = o?['retailers'] as Map<String,dynamic>?;
          return Container(margin: const EdgeInsets.only(bottom: 8), child: WhiteCard(padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(child: Text(r?['shop_name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
              Text('${o?['estimated_birds'] ?? 0} birds', style: const TextStyle(fontSize: 12, color: kTextSub)),
              const SizedBox(width: 8),
              StatusBadge(d['status'] as String? ?? '—', SC.order(d['status'] as String? ?? ''), small: true),
            ])));
        }),
        // unassigned confirmed orders
        if (status == 'assigned' && _confirmedOrders.isNotEmpty) ...[
          const SizedBox(height: 10),
          const SectionHeader('ADD FROM CONFIRMED ORDERS'),
          ..._confirmedOrders.where((o) => !_deliveries.any((d) => (d['orders'] as Map?)?['id'] == o['id'])).map((o) {
            final r = o['retailers'] as Map<String,dynamic>?;
            return ListTile(dense: true,
              title: Text(r?['shop_name'] as String? ?? '—', style: const TextStyle(fontSize: 13)),
              subtitle: Text('${o['estimated_birds'] ?? 0} birds'),
              trailing: IconButton(icon: const Icon(Icons.add_circle_outline, color: kPrimary), onPressed: () => _addOrder(o['id'])));
          }),
        ],
        const SizedBox(height: 20),
        if (status == 'assigned') ElevatedButton.icon(
          onPressed: _submitting ? null : _start,
          icon: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.play_arrow),
          label: const Text('Start Deliveries'),
        ),
      ]),
    );
  }
}
