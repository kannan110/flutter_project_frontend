import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class DispatchScreen extends ConsumerStatefulWidget {
  const DispatchScreen({super.key});
  @override ConsumerState<DispatchScreen> createState() => _S();
}
class _S extends ConsumerState<DispatchScreen> {
  final _c = Supabase.instance.client;
  List<Map<String,dynamic>> _batches = [];
  bool _loading = true;
  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    setState(() => _loading = true);
    try {
      // delivery_batches columns: id,trader_id,delivery_agent_id,shift_id,status,total_orders,total_birds,created_at
      final data = await _c.from('delivery_batches')
          .select('id,status,total_orders,total_birds,created_at,delivery_agents(name,vehicle_no)')
          .eq('trader_id', tid)
          .order('created_at', ascending: false).limit(100);
      if (mounted) setState(() { _batches = List<Map<String,dynamic>>.from(data); _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _createBatch() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    final agents = List<Map<String,dynamic>>.from(
        await _c.from('delivery_agents').select('id,name,vehicle_no')
            .eq('trader_id', tid).eq('is_active', true).order('name'));
    if (!mounted) return;
    if (agents.isEmpty) { showError(context, 'No active agents. Add agents first.'); return; }
    Map<String,dynamic>? sel;
    await showModalBottomSheet(context: context, useRootNavigator: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => ListView(shrinkWrap: true, padding: const EdgeInsets.all(20), children: [
        const Text('Select Agent', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        ...agents.map((a) => ListTile(
          leading: const Icon(Icons.delivery_dining, color: kPrimary),
          title: Text(a['name'] as String),
          subtitle: Text(a['vehicle_no'] as String? ?? ''),
          onTap: () { sel = a; Navigator.of(ctx, rootNavigator: true).pop(); },
        )),
      ]));
    if (sel == null) return;
    try {
      // delivery_batches: no created_by column — use: trader_id, delivery_agent_id, status
      await _c.from('delivery_batches').insert({
        'trader_id': tid, 'delivery_agent_id': sel!['id'], 'status': 'assigned',
      });
      _load();
      if (mounted) showSuccess(context, 'Batch created ✓');
    } catch (e) { if (mounted) showError(context, e.toString()); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Dispatch'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
    floatingActionButton: FloatingActionButton.extended(onPressed: _createBatch, icon: const Icon(Icons.add), label: const Text('New Batch')),
    body: _loading ? const LoadingList() : _batches.isEmpty
        ? const EmptyState(icon: Icons.local_shipping_outlined, message: 'No batches yet', sub: 'Create a batch to start dispatching')
        : RefreshIndicator(onRefresh: _load, child: ListView.separated(
            padding: const EdgeInsets.all(16), itemCount: _batches.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final b = _batches[i];
              final a = b['delivery_agents'] as Map<String,dynamic>?;
              final date = DateTime.tryParse(b['created_at'] as String? ?? '');
              return InkWell(
                onTap: () => context.go(R.batchDetailPath(b['id'])),
                borderRadius: BorderRadius.circular(12),
                child: WhiteCard(child: Row(children: [
                  Container(width: 42, height: 42, decoration: BoxDecoration(color: kPrimary.withOpacity(0.1), shape: BoxShape.circle),
                      child: const Icon(Icons.local_shipping_outlined, color: kPrimary, size: 20)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a?['name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    Row(children: [
                      StatusBadge(b['status'] as String? ?? '—', SC.order(b['status'] as String? ?? ''), small: true),
                      const SizedBox(width: 6),
                      Text('${b['total_orders'] ?? 0} orders · ${b['total_birds'] ?? 0} birds', style: const TextStyle(fontSize: 11, color: kTextHint)),
                    ]),
                  ])),
                  if (date != null) Text(DateFormat('d MMM').format(date), style: const TextStyle(fontSize: 11, color: kTextHint)),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, color: kTextHint, size: 18),
                ])),
              );
            })),
  );
}
