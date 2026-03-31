import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
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
    if (agentId == null) return;
    setState(() => _loading = true);
    try {
      // deliveries: status options: assigned, picked_up, out_for_delivery, delivered, cancelled
      var q = _c.from('deliveries').select('id,status,collected_amount,orders(estimated_birds,retailers(shop_name,address,phone))').eq('delivery_agent_id', agentId);
      if (_filter == 'active') q = q.inFilter('status', ['assigned','picked_up','out_for_delivery']);
      else if (_filter == 'done') q = q.eq('status', 'delivered');
      final data = await q.order('created_at', ascending: false).limit(100);
      if (mounted) setState(() { _list = List<Map<String,dynamic>>.from(data); _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('My Deliveries'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
    body: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: SegmentedButton<String>(
        segments: const [ButtonSegment(value:'active',label:Text('Active')), ButtonSegment(value:'done',label:Text('Done')), ButtonSegment(value:'all',label:Text('All'))],
        selected: {_filter}, onSelectionChanged: (s) { setState(() => _filter = s.first); _load(); })),
      const SizedBox(height: 8),
      Expanded(child: _loading ? const LoadingList() : _list.isEmpty ? const EmptyState(icon: Icons.local_shipping_outlined, message: 'No deliveries')
          : RefreshIndicator(onRefresh: _load, child: ListView.separated(
              padding: const EdgeInsets.all(16), itemCount: _list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final d = _list[i];
                final o = d['orders'] as Map<String,dynamic>?; final r = o?['retailers'] as Map<String,dynamic>?;
                final status = d['status'] as String? ?? '—';
                final isActive = ['assigned','picked_up','out_for_delivery'].contains(status);
                return Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isActive ? kPrimary.withOpacity(0.3) : kBorder, width: isActive ? 1.5 : 1)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [Expanded(child: Text(r?['shop_name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))), StatusBadge(status, SC.order(status))]),
                    if (r?['address'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [const Icon(Icons.location_on_outlined, size: 13, color: kTextHint), const SizedBox(width: 4), Expanded(child: Text(r!['address'] as String, style: const TextStyle(fontSize: 11, color: kTextHint), maxLines: 1, overflow: TextOverflow.ellipsis))])),
                    const SizedBox(height: 4),
                    Text('${o?['estimated_birds'] ?? 0} birds ordered', style: const TextStyle(fontSize: 12, color: kTextSub)),
                    if (isActive) ...[const SizedBox(height: 10),
                      SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => context.go(R.deliveryDonePath(d['id'])), style: ElevatedButton.styleFrom(minimumSize: const Size(0, 38)), child: const Text('Complete Delivery', style: TextStyle(fontSize: 13))))],
                  ]));
              }))),
    ]),
  );
}
