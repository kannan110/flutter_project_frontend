import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class ApprovalsScreen extends ConsumerStatefulWidget {
  const ApprovalsScreen({super.key});
  @override ConsumerState<ApprovalsScreen> createState() => _S();
}
class _S extends ConsumerState<ApprovalsScreen> {
  final _c = Supabase.instance.client;
  List<Map<String,dynamic>> _items = [];
  bool _loading = true;
  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    if (mounted) setState(() => _loading = true);
    try {
      // deliveries: status=delivered, approval_status=pending
      final data = await _c.from('deliveries')
          .select('id,delivered_total_weight,received_total_weight,collected_amount,created_at,orders(retailers(shop_name)),delivery_agents(name)')
          .eq('trader_id', tid).eq('status','delivered').eq('approval_status','pending')
          .order('created_at', ascending: false);
      if (mounted) setState(() { _items = List<Map<String,dynamic>>.from(data); _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Row(children: [
        const Text('Pending Approvals'),
        if (_items.isNotEmpty) ...[const SizedBox(width: 8),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(10)),
            child: Text('${_items.length}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)))],
      ]),
      actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
    ),
    body: _loading ? const LoadingList() : _items.isEmpty
        ? const EmptyState(icon: Icons.fact_check_outlined, message: 'No pending approvals')
        : RefreshIndicator(onRefresh: _load, child: ListView.separated(
            padding: const EdgeInsets.all(16), itemCount: _items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final d = _items[i];
              final o = d['orders'] as Map<String,dynamic>?;
              final r = o?['retailers'] as Map<String,dynamic>?;
              final a = d['delivery_agents'] as Map<String,dynamic>?;
              // weight: received_total_weight preferred, fallback to delivered_total_weight
              final w = ((d['received_total_weight'] ?? d['delivered_total_weight']) as num?)?.toDouble() ?? 0;
              return InkWell(
                onTap: () => context.push(R.approvalDetailPath(d['id'])),
                borderRadius: BorderRadius.circular(12),
                child: Container(padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.shade200, width: 1.5)),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r?['shop_name'] as String? ?? '—', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('${w.toStringAsFixed(1)} kg · Agent: ${a?['name'] ?? '—'}', style: const TextStyle(fontSize: 12, color: kTextSub)),
                    ])),
                    const StatusBadge('review', Colors.orange),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, color: kTextHint, size: 18),
                  ])),
              );
            })),
  );
}
