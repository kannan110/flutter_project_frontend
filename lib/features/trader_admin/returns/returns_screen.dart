import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';

class ReturnsScreen extends ConsumerStatefulWidget {
  const ReturnsScreen({super.key});
  @override ConsumerState<ReturnsScreen> createState() => _S();
}
class _S extends ConsumerState<ReturnsScreen> {
  final _c = Supabase.instance.client;
  List<Map<String,dynamic>> _returns = [];
  List<Map<String,dynamic>> _deliveries = [];
  // Stock summary from returns
  int _totalReturnedBirds = 0;
  double _totalReturnedKg = 0;
  bool _loading = true;
  String _filter = 'all';

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null || !mounted) return;
    if (mounted) setState(() => _loading = true);
    try {
      var q = _c.from('return_entries')
          .select('id,return_type,return_date,bird_count,weight_kg,reason,status,stock_credited,created_at,retailers(shop_name),delivery_agents(name)')
          .eq('trader_id', tid);
      if (_filter != 'all') q = q.eq('status', _filter);
      final r = await q.order('created_at', ascending: false).limit(100);
      // Delivered orders for processing returns against
      final d = await _c.from('deliveries')
          .select('id,orders(retailers(shop_name,id)),delivery_agents(id,name)')
          .eq('trader_id', tid).eq('status', 'delivered');
      // Return stock summary from stock_ledger
      final sl = await _c.from('stock_ledger')
          .select('quantity_birds,quantity_kg')
          .eq('trader_id', tid).eq('movement_type', 'returned_in');
      if (!mounted) return;
      int birds = 0; double kg = 0;
      for (final s in sl) { birds += (s['quantity_birds'] as num?)?.toInt() ?? 0; kg += (s['quantity_kg'] as num?)?.toDouble() ?? 0; }
      if (mounted) setState(() {
        _returns = List<Map<String,dynamic>>.from(r);
        _deliveries = List<Map<String,dynamic>>.from(d);
        _totalReturnedBirds = birds; _totalReturnedKg = kg;
        _loading = false;
      });
    } catch (e) { if (mounted) setState(() => _loading = false); showError(context, e.toString()); }
  }

  Future<void> _processReturn() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    final uid = ref.read(appUserProvider).valueOrNull?.userId;
    if (_deliveries.isEmpty && !mounted) { showError(context, 'No delivered orders to return against'); return; }
    Map<String,dynamic>? selDel;
    String returnType = 'same_batch';
    final birdsCtrl = TextEditingController(text: '0');
    final wtCtrl    = TextEditingController(text: '0');
    final rateCtrl  = TextEditingController();
    final reasonCtrl= TextEditingController();

    await showModalBottomSheet(context: context, isScrollControlled: true, useRootNavigator: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: StatefulBuilder(builder: (_, ss) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Process Return', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(8)),
            child: const Text('Returns are added back to available stock automatically.', style: TextStyle(fontSize: 11, color: Colors.purple))),
          const SizedBox(height: 12),
          DropdownButtonFormField<Map<String,dynamic>>(
            hint: const Text('Select Delivery *'),
            items: _deliveries.map((d) {
              final o = d['orders'] as Map<String,dynamic>?;
              final r = o?['retailers'] as Map<String,dynamic>?;
              final a = d['delivery_agents'] as Map<String,dynamic>?;
              return DropdownMenuItem(value: d, child: Text('${r?['shop_name'] ?? '—'} · ${a?['name'] ?? '—'}', overflow: TextOverflow.ellipsis));
            }).toList(),
            onChanged: (v) => ss(() => selDel = v)),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value:'same_batch', label:Text('Same Batch')), ButtonSegment(value:'old_stock', label:Text('Old Stock'))],
            selected: {returnType}, onSelectionChanged: (s) => ss(() => returnType = s.first)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: birdsCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Birds *'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: wtCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Weight (kg) *'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: rateCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '₹/kg', prefixText: '₹'))),
          ]),
          const SizedBox(height: 10),
          TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Reason *')),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.assignment_return_outlined, size: 18),
            label: const Text('Process Return'),
            onPressed: () async {
              if (selDel == null || reasonCtrl.text.trim().isEmpty) return;
              final birds = int.tryParse(birdsCtrl.text) ?? 0;
              final wt    = double.tryParse(wtCtrl.text) ?? 0;
              if (birds <= 0 || wt <= 0) return;
              final o = selDel!['orders'] as Map<String,dynamic>?;
              final a = selDel!['delivery_agents'] as Map<String,dynamic>?;
              Navigator.of(ctx, rootNavigator: true).pop();
              try {
                await _c.rpc('process_return_v2', params: {
                  'p_trader_id': tid, 'p_delivery_id': selDel!['id'],
                  'p_retailer_id': o?['retailers']?['id'],
                  'p_agent_id': a?['id'],
                  'p_return_type': returnType, 'p_bird_count': birds, 'p_weight_kg': wt,
                  'p_rate_per_kg': rateCtrl.text.isEmpty ? null : double.tryParse(rateCtrl.text),
                  'p_reason': reasonCtrl.text.trim(), 'p_processed_by': uid,
                });
                _load();
                if (mounted) showSuccess(context, 'Return processed — stock updated ✓');
              } catch (e) { if (mounted) showError(context, e.toString()); }
            }),
        ]))));
    for (final c in [birdsCtrl, wtCtrl, rateCtrl, reasonCtrl]) c.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Returns'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
    floatingActionButton: FloatingActionButton.extended(onPressed: _processReturn, icon: const Icon(Icons.assignment_return_outlined), label: const Text('Process Return')),
    body: _loading ? const LoadingList() : Column(children: [
      // Stock integration summary
      if (_totalReturnedBirds > 0) Container(
        color: Colors.white, padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.purple.shade50, shape: BoxShape.circle),
              child: Icon(Icons.assignment_return_outlined, color: Colors.purple.shade600, size: 22)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Total Returned to Stock', style: TextStyle(fontSize: 11, color: kTextHint)),
            Text('$_totalReturnedBirds birds · ${_totalReturnedKg.toStringAsFixed(1)} kg',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.purple.shade700)),
            const Text('These birds are available for redelivery', style: TextStyle(fontSize: 10, color: kTextSub)),
          ])),
        ])),
      // Filter
      Container(color: Colors.white, padding: const EdgeInsets.fromLTRB(16, 0, 16, 10), child:
        SegmentedButton<String>(
          segments: const [ButtonSegment(value:'all', label:Text('All')), ButtonSegment(value:'pending', label:Text('Pending')), ButtonSegment(value:'processed', label:Text('Processed'))],
          selected: {_filter}, onSelectionChanged: (s) { if (mounted) setState(() => _filter = s.first); _load(); })),
      const Divider(height: 1),
      Expanded(child: _returns.isEmpty
          ? const EmptyState(icon: Icons.assignment_return_outlined, message: 'No returns recorded')
          : ListView.separated(padding: const EdgeInsets.all(16), itemCount: _returns.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final r = _returns[i];
                final retailer = r['retailers'] as Map<String,dynamic>?;
                final agent    = r['delivery_agents'] as Map<String,dynamic>?;
                final date     = DateTime.tryParse(r['return_date'] as String? ?? '');
                final status   = r['status'] as String? ?? 'pending';
                final credited = r['stock_credited'] as bool? ?? false;
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: status == 'processed' ? Colors.green.shade200 : Colors.orange.shade200, width: 1.2)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(retailer?['shop_name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                      StatusBadge(status, status == 'processed' ? Colors.green : Colors.orange),
                    ]),
                    const SizedBox(height: 6),
                    Row(children: [
                      const Icon(Icons.delivery_dining, size: 13, color: kTextHint), const SizedBox(width: 4),
                      Text(agent?['name'] as String? ?? '—', style: const TextStyle(fontSize: 11, color: kTextSub)),
                      const SizedBox(width: 12),
                      StatusBadge(r['return_type'] as String? ?? '—', Colors.blue, small: true),
                    ]),
                    const SizedBox(height: 6),
                    Row(children: [
                      Text('${r['bird_count'] ?? 0} birds · ${(r['weight_kg'] as num?)?.toStringAsFixed(1) ?? 0} kg',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      if (credited) Row(children: [Icon(Icons.check_circle, color: Colors.green.shade600, size: 14), const SizedBox(width: 4), Text('Stock Updated ✓', style: TextStyle(fontSize: 10, color: Colors.green.shade700, fontWeight: FontWeight.w600))]),
                      if (date != null) ...[const SizedBox(width: 8), Text(DateFormat('d MMM').format(date), style: const TextStyle(fontSize: 11, color: kTextHint))],
                    ]),
                    if (r['reason'] != null) Padding(padding: const EdgeInsets.only(top: 4),
                        child: Text(r['reason'] as String, style: const TextStyle(fontSize: 11, color: kTextSub), maxLines: 2, overflow: TextOverflow.ellipsis)),
                  ]),
                );
              })),
    ]),
  );
}
