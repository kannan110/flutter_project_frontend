import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

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
    if (agentId == null || !mounted) return;
    if (mounted) setState(() => _loading = true);
    try {
      // FIX: fetch delivery with DC birds/weight from challans for accurate stock display
      // FIX: removed broken nested delivery_batches->delivery_challans select
      // PostgREST can't traverse deliveries->delivery_batches->delivery_challans
      // DC data loaded separately only in delivery_complete_screen where needed
      var q = _c.from('deliveries')
          .select('id,status,collected_amount,payment_mode,delivered_at,'
                  'delivered_bird_count,delivered_total_weight,'
                  'dc_weight_kg,total_loss_kg,loss_percentage,is_high_loss,'
                  'is_partial_delivery,partial_birds,partial_quantity,order_id,'
                  'mortality_birds,approval_status,'
                  'orders(id,estimated_birds,total_quantity,retailers(shop_name,address,phone))')
          .eq('delivery_agent_id', agentId);

      if (_filter == 'active')
        q = q.inFilter('status', ['assigned', 'picked_up', 'out_for_delivery']);
      else if (_filter == 'done')
        q = q.eq('status', 'delivered');

      final data = await q.order('created_at', ascending: false).limit(100);
      if (!mounted) return;
      if (mounted) setState(() {
        _list    = List<Map<String,dynamic>>.from(data);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('My Deliveries'),
      actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
    body: Column(children: [
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'active', label: Text('Active')),
            ButtonSegment(value: 'done',   label: Text('Delivered')),
            ButtonSegment(value: 'all',    label: Text('All')),
          ],
          selected: {_filter},
          onSelectionChanged: (s) { if (mounted) setState(() => _filter = s.first); _load(); })),
      const Divider(height: 1),
      Expanded(
        child: _loading
            ? const LoadingList()
            : _list.isEmpty
                ? EmptyState(
                    icon: Icons.local_shipping_outlined,
                    message: _filter == 'active' ? 'No active deliveries' : 'No deliveries found',
                    sub: _filter == 'active' ? 'Admin needs to assign a batch to you' : null)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _deliveryCard(_list[i]),
                    ))),
    ]),
  );

  Widget _deliveryCard(Map<String,dynamic> d) {
    final o          = d['orders'] as Map<String,dynamic>?;
    final r          = o?['retailers'] as Map<String,dynamic>?;
    final status       = d['status'] as String? ?? '—';
    final isActive     = ['assigned', 'picked_up', 'out_for_delivery'].contains(status);
    final isDelivered  = status == 'delivered';
    final collected    = (d['collected_amount'] as num?)?.toDouble() ?? 0;
    final isHighLoss   = d['is_high_loss'] == true;
    final lossPct      = (d['loss_percentage'] as num?)?.toDouble() ?? 0;
    final approvalSt   = d['approval_status'] as String? ?? '';
    final delivBirds   = (d['delivered_bird_count'] as num?)?.toInt() ?? 0;
    final delivWeight  = (d['delivered_total_weight'] as num?)?.toDouble() ?? 0;
    final dcWt         = (d['dc_weight_kg'] as num?)?.toDouble() ?? 0;
    final orderBirds   = (o?['estimated_birds'] as num?)?.toInt() ?? 0;
    final orderWeight  = (o?['total_quantity']  as num?)?.toDouble() ?? 0;
    final showDelivered = isDelivered && delivBirds > 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isHighLoss ? Colors.orange.shade300
                : isActive ? kPrimary.withValues(alpha: 0.3) : kBorder,
            width: isActive || isHighLoss ? 1.5 : 1)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Shop name + status
        Row(children: [
          Expanded(child: Text(r?['shop_name'] as String? ?? '—',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
          StatusBadge(status, SC.order(status)),
        ]),

        // Address
        if (r?['address'] != null) Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(children: [
            const Icon(Icons.location_on_outlined, size: 13, color: kTextHint),
            const SizedBox(width: 3),
            Expanded(child: Text(r!['address'] as String,
                style: const TextStyle(fontSize: 11, color: kTextHint),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
          ])),

        // Phone
        if (r?['phone'] != null) Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(children: [
            const Icon(Icons.phone_outlined, size: 12, color: kTextHint),
            const SizedBox(width: 3),
            Text(r!['phone'] as String, style: const TextStyle(fontSize: 11, color: kTextHint)),
          ])),

        const SizedBox(height: 8),

        // Birds / weight row
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.set_meal_outlined, size: 14, color: kPrimary),
              const SizedBox(width: 4),
              Text(
                showDelivered ? '$delivBirds birds delivered' : '$orderBirds birds (est.)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: showDelivered ? kPrimary : kTextSub)),
            ]),
            Row(children: [
              const Icon(Icons.balance_outlined, size: 12, color: kTextHint),
              const SizedBox(width: 4),
              Text(
                showDelivered
                    ? '${delivWeight.toStringAsFixed(1)} kg delivered'
                    : '${orderWeight.toStringAsFixed(1)} kg (est.)',
                style: TextStyle(fontSize: 11, color: showDelivered ? kTextSub : kTextHint)),
            ]),
            if (dcWt > 0 && isDelivered)
              Text('DC: ${dcWt.toStringAsFixed(1)} kg loaded',
                  style: const TextStyle(fontSize: 10, color: kTextHint)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (collected > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.green.shade50, borderRadius: BorderRadius.circular(6)),
                child: Row(children: [
                  const Icon(Icons.currency_rupee, size: 12, color: Colors.green),
                  Text(Fmt.amount(collected),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.green)),
                ])),
            if (isHighLoss) const SizedBox(height: 4),
            if (isHighLoss) Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(6)),
                child: Text('⚠️ Loss ${lossPct.toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.deepOrange))),
            if (isDelivered && !isHighLoss && lossPct > 0) const SizedBox(height: 4),
            if (isDelivered && !isHighLoss && lossPct > 0)
              Text('Loss: ${lossPct.toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 10, color: kTextHint)),
          ]),
        ]),

        // Status-aware action row
        if (isActive) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.push(R.deliveryDonePath(d['id'])),
              style: ElevatedButton.styleFrom(minimumSize: const Size(0, 40),
                  backgroundColor: status == 'out_for_delivery' ? kPrimary : Colors.grey),
              child: Text(
                  status == 'out_for_delivery' ? 'Mark as Delivered ✓'
                  : status == 'picked_up' ? 'Waiting — out for delivery...'
                  : 'Assigned',
                  style: const TextStyle(fontWeight: FontWeight.w700)))),
        ],
        if (isDelivered) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Partial delivery indicator
            if (d['is_partial_delivery'] == true) Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade300)),
                child: Row(children: [
                  const Icon(Icons.splitscreen_outlined, size: 14, color: Colors.orange),
                  const SizedBox(width: 6),
                  Expanded(child: Text(
                    'Partial — ${(d['partial_birds'] as num?)?.toInt() ?? 0} birds · '
                    '${(d['partial_quantity'] as num?)?.toStringAsFixed(1) ?? '0'} kg remaining',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.orange))),
                ]))),
            // View history button
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: () {
                    final orderId =   (d['order_id'] ?? (d['orders'] as Map?)?['id']) as String?;
                    if (orderId != null) context.push(R.deliveryDonePath(orderId));
                  },
                  icon: const Icon(Icons.history, size: 14),
                  label: const Text('View History', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)))),
              ])),
            Row(children: [
            Icon(approvalSt == 'approved' ? Icons.verified_outlined
                : Icons.pending_outlined,
                size: 13,
                color: approvalSt == 'approved' ? Colors.green : Colors.orange),
            const SizedBox(width: 4),
            Text(approvalSt == 'approved' ? 'Approved ✓' : 'Pending approval',
                style: TextStyle(fontSize: 11,
                    color: approvalSt == 'approved' ? Colors.green : Colors.orange)),
          ]),           // close Row([Icon, Text])
          ])),          // close Column + Padding
      ]),
    );
  }
}
