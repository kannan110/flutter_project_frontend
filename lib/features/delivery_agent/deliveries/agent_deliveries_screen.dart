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
      var q = _c.from('deliveries')
          .select('id,status,collected_amount,payment_mode,delivered_at,'
                  'orders(id,estimated_birds,total_quantity,retailers(shop_name,address,phone)),'
                  'delivery_batches(id,delivery_challans(bird_count,net_weight))')
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
    final status     = d['status'] as String? ?? '—';
    final isActive   = ['assigned', 'picked_up', 'out_for_delivery'].contains(status);
    final collected  = (d['collected_amount'] as num?)?.toDouble() ?? 0;

    // FIX: show actual DC birds/weight if available, else fall back to order estimate
    final batch      = d['delivery_batches'] as Map<String,dynamic>?;
    final challans   = (batch?['delivery_challans'] as List? ?? []).cast<Map<String,dynamic>>();
    final dcBirds    = challans.fold(0,   (s, c) => s + ((c['bird_count']  as num?)?.toInt()    ?? 0));
    final dcWeight   = challans.fold(0.0, (s, c) => s + ((c['net_weight']  as num?)?.toDouble() ?? 0));
    final orderBirds  = (o?['estimated_birds'] as num?)?.toInt()    ?? 0;
    final orderWeight = (o?['total_quantity']  as num?)?.toDouble() ?? 0;

    final showDcBirds   = dcBirds  > 0;
    final showDcWeight  = dcWeight > 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isActive ? kPrimary.withValues(alpha: 0.3) : kBorder,
            width: isActive ? 1.5 : 1)),
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

        // Birds / weight — show DC actual vs order estimate
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // FIX: show DC stock if available, else show order estimate
            Row(children: [
              const Icon(Icons.set_meal_outlined, size: 14, color: kPrimary),
              const SizedBox(width: 4),
              Text(
                showDcBirds
                    ? '$dcBirds birds (DC actual)'
                    : '$orderBirds birds (order est.)',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: showDcBirds ? kPrimary : kTextSub)),
            ]),
            Row(children: [
              const Icon(Icons.balance_outlined, size: 12, color: kTextHint),
              const SizedBox(width: 4),
              Text(
                showDcWeight
                    ? '${dcWeight.toStringAsFixed(1)} kg (DC)'
                    : '${orderWeight.toStringAsFixed(1)} kg (est.)',
                style: TextStyle(fontSize: 11, color: showDcWeight ? kTextSub : kTextHint)),
            ]),
          ])),
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
        ]),

        // Complete button for active deliveries
        if (isActive) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.push(R.deliveryDonePath(d['id'])),
              style: ElevatedButton.styleFrom(minimumSize: const Size(0, 40)),
              child: const Text('Complete Delivery ✓',
                  style: TextStyle(fontWeight: FontWeight.w700)))),
        ],
      ]),
    );
  }
}
