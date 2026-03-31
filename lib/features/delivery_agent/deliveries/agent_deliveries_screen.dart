import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

/// DELIVERY STATUS FLOW:
///   assigned → picked_up → out_for_delivery → delivered
///
/// Agent actions:
///   - "Go Out for Delivery" button: assigned/picked_up → out_for_delivery
///   - "Mark Delivered" button: out_for_delivery → delivered (with full data entry)
class AgentDeliveriesScreen extends ConsumerStatefulWidget {
  const AgentDeliveriesScreen({super.key});
  @override ConsumerState<AgentDeliveriesScreen> createState() => _S();
}

class _S extends ConsumerState<AgentDeliveriesScreen> {
  final _c = Supabase.instance.client;
  List<Map<String,dynamic>> _list = [];
  bool _loading = true;
  String _filter = 'active';

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final agentId = ref.read(appUserProvider).valueOrNull?.agentId;
    if (agentId == null) return;
    setState(() => _loading = true);
    try {
      var q = _c.from('deliveries')
          .select('id,status,expected_bird_count,expected_total_weight,collected_amount,orders(id,estimated_birds,total_quantity,retailers(shop_name,address,phone))')
          .eq('delivery_agent_id', agentId).neq('status', 'cancelled');
      if (_filter == 'active') q = q.inFilter('status', ['assigned','picked_up','out_for_delivery']);
      else if (_filter == 'done') q = q.eq('status', 'delivered');
      final data = await q.order('created_at', ascending: false).limit(100);
      if (mounted) setState(() { _list = List<Map<String,dynamic>>.from(data); _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _markOutForDelivery(String deliveryId) async {
    try {
      await _c.rpc('mark_delivery_out_for_delivery', params: {'p_delivery_id': deliveryId});
      _load();
      if (mounted) showSuccess(context, 'Marked as Out for Delivery ✓');
    } catch (e) { if (mounted) showError(context, e.toString()); }
  }

  Color _statusColor(String s) => switch(s) {
    'assigned'         => Colors.grey,
    'picked_up'        => Colors.blue,
    'out_for_delivery' => Colors.orange,
    'delivered'        => Colors.green,
    _                  => Colors.grey,
  };

  IconData _statusIcon(String s) => switch(s) {
    'assigned'         => Icons.assignment_outlined,
    'picked_up'        => Icons.inventory_2_outlined,
    'out_for_delivery' => Icons.local_shipping,
    'delivered'        => Icons.check_circle,
    _                  => Icons.circle_outlined,
  };

  String _statusLabel(String s) => switch(s) {
    'assigned'         => 'Assigned',
    'picked_up'        => 'Picked Up',
    'out_for_delivery' => 'On the Way',
    'delivered'        => 'Delivered',
    _                  => s,
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('My Deliveries'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
    body: Column(children: [
      // Status filter
      Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'active', label: Text('Active')),
            ButtonSegment(value: 'done',   label: Text('Done')),
            ButtonSegment(value: 'all',    label: Text('All')),
          ],
          selected: {_filter},
          onSelectionChanged: (s) { setState(() => _filter = s.first); _load(); },
        )),
      const SizedBox(height: 8),

      Expanded(child: _loading ? const LoadingList() : _list.isEmpty
          ? const EmptyState(icon: Icons.local_shipping_outlined, message: 'No deliveries')
          : RefreshIndicator(onRefresh: _load, child: ListView.separated(
              padding: const EdgeInsets.all(16), itemCount: _list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final d       = _list[i];
                final o       = d['orders'] as Map<String,dynamic>?;
                final r       = o?['retailers'] as Map<String,dynamic>?;
                final status  = d['status'] as String? ?? 'assigned';
                final birds   = o?['estimated_birds'] ?? 0;
                final kg      = (o?['total_quantity'] as num?)?.toStringAsFixed(1) ?? '—';
                final isActive = ['assigned','picked_up','out_for_delivery'].contains(status);

                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isActive ? _statusColor(status).withOpacity(0.4) : kBorder,
                      width: isActive ? 2 : 1)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Header
                    Padding(padding: const EdgeInsets.fromLTRB(14, 14, 14, 8), child: Row(children: [
                      Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(color: _statusColor(status).withOpacity(0.1), shape: BoxShape.circle),
                        child: Icon(_statusIcon(status), color: _statusColor(status), size: 20)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r?['shop_name'] as String? ?? '—',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        if (r?['address'] != null) Text(r!['address'] as String,
                            style: const TextStyle(fontSize: 11, color: kTextHint), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ])),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: _statusColor(status).withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                        child: Text(_statusLabel(status),
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _statusColor(status)))),
                    ])),

                    // Details
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Row(children: [
                      _chip(Icons.numbers, '$birds birds'),
                      const SizedBox(width: 8),
                      _chip(Icons.scale_outlined, '$kg kg'),
                    ])),
                    const SizedBox(height: 10),

                    // Action buttons
                    if (isActive) Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFFF8F9FA),
                        borderRadius: BorderRadius.vertical(bottom: Radius.circular(14))),
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      child: Column(children: [
                        // Status flow indicator
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          _flowStep('Assigned',  status == 'assigned'),
                          _flowArrow,
                          _flowStep('Picked up', status == 'picked_up'),
                          _flowArrow,
                          _flowStep('On the way',status == 'out_for_delivery'),
                          _flowArrow,
                          _flowStep('Delivered', false),
                        ]),
                        const SizedBox(height: 10),

                        // Go out for delivery button (assigned or picked_up)
                        if (['assigned','picked_up'].contains(status)) SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _markOutForDelivery(d['id'] as String),
                            icon: const Icon(Icons.local_shipping, size: 18),
                            label: const Text('Going Out for Delivery'),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                minimumSize: const Size(0, 42)),
                          )),

                        // Mark delivered button (out_for_delivery)
                        if (status == 'out_for_delivery') SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => context.go(R.deliveryDonePath(d['id'] as String)),
                            icon: const Icon(Icons.check_circle_outline, size: 18),
                            label: const Text('Mark as Delivered'),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                minimumSize: const Size(0, 42)),
                          )),

                        // Also show OFD for assigned (allow skipping)
                        if (status == 'assigned') ...[
                          const SizedBox(height: 6),
                          SizedBox(width: double.infinity, child: OutlinedButton.icon(
                            onPressed: () => context.go(R.deliveryDonePath(d['id'] as String)),
                            icon: const Icon(Icons.check_circle_outline, size: 16),
                            label: const Text('Mark Delivered (skip OFD)', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36), side: const BorderSide(color: Colors.green), foregroundColor: Colors.green),
                          )),
                        ],
                      ])),

                    if (!isActive && status == 'delivered') Container(
                      decoration: const BoxDecoration(color: Color(0xFFF0FFF4), borderRadius: BorderRadius.vertical(bottom: Radius.circular(14))),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: const Row(children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 16),
                        SizedBox(width: 6),
                        Text('Delivered ✓  Pending trader approval', style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600)),
                      ])),
                  ]));
              }))),
    ]),
  );

  Widget _chip(IconData icon, String text) => Row(children: [
    Icon(icon, size: 13, color: kTextSub), const SizedBox(width: 3),
    Text(text, style: const TextStyle(fontSize: 12, color: kTextSub)),
  ]);

  Widget _flowStep(String label, bool active) => Column(children: [
    Container(width: 8, height: 8, decoration: BoxDecoration(
      color: active ? Colors.orange : Colors.grey.shade300, shape: BoxShape.circle)),
    const SizedBox(height: 2),
    Text(label, style: TextStyle(fontSize: 8, color: active ? Colors.orange : Colors.grey.shade400, fontWeight: active ? FontWeight.w700 : FontWeight.normal)),
  ]);

  Widget get _flowArrow => Expanded(child: Container(height: 1, color: Colors.grey.shade300, margin: const EdgeInsets.only(bottom: 12)));
}
