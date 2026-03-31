import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class ReturnsScreen extends ConsumerStatefulWidget {
  const ReturnsScreen({super.key});
  @override ConsumerState<ReturnsScreen> createState() => _S();
}
class _S extends ConsumerState<ReturnsScreen> {
  final _c = Supabase.instance.client;
  List<Map<String,dynamic>> _returns = [];
  List<Map<String,dynamic>> _deliveries = [];
  bool _loading = true;
  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    setState(() => _loading = true);
    try {
      // return_entries: id,return_type,return_date,bird_count,weight_kg,reason,status,created_at
      // return_type CHECK: same_batch, old_stock (not: dead, rejected, excess — those were wrong)
      final r = await _c.from('return_entries')
          .select('id,return_type,return_date,bird_count,weight_kg,reason,status,created_at,retailers(shop_name),delivery_agents(name)')
          .eq('trader_id', tid).order('created_at', ascending: false).limit(100);
      // deliveries that are delivered (for adding returns against)
      final d = await _c.from('deliveries')
          .select('id,orders(retailers(shop_name)),delivery_agents(id,name)')
          .eq('trader_id', tid).eq('status','delivered');
      if (mounted) setState(() { _returns = List<Map<String,dynamic>>.from(r); _deliveries = List<Map<String,dynamic>>.from(d); _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _processReturn() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    final uid = ref.read(appUserProvider).valueOrNull?.userId;
    if (_deliveries.isEmpty) { showError(context, 'No delivered orders to process returns against'); return; }

    Map<String,dynamic>? selDel;
    // return_type CHECK: same_batch, old_stock
    String returnType = 'same_batch';
    final birdsCtrl = TextEditingController(text: '0');
    final wtCtrl = TextEditingController(text: '0');
    final rateCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();

    await showModalBottomSheet(context: context, isScrollControlled: true, useRootNavigator: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: StatefulBuilder(builder: (_, ss) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Process Return', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          DropdownButtonFormField<Map<String,dynamic>>(
            hint: const Text('Select Delivery *'),
            items: _deliveries.map((d) {
              final o = d['orders'] as Map<String,dynamic>?; final r = o?['retailers'] as Map<String,dynamic>?; final a = d['delivery_agents'] as Map<String,dynamic>?;
              return DropdownMenuItem(value: d, child: Text('${r?['shop_name'] ?? '—'} · ${a?['name'] ?? '—'}', overflow: TextOverflow.ellipsis));
            }).toList(),
            onChanged: (v) => ss(() => selDel = v)),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value:'same_batch', label:Text('Same Batch')), ButtonSegment(value:'old_stock', label:Text('Old Stock'))],
            selected: {returnType}, onSelectionChanged: (s) => ss(() => returnType = s.first)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: birdsCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Birds'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: wtCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Weight (kg)'))),
          ]),
          const SizedBox(height: 10),
          TextField(controller: rateCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '₹/kg (optional)', prefixText: '₹')),
          const SizedBox(height: 10),
          TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Reason')),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: () async {
            if (selDel == null) return;
            final o = selDel!['orders'] as Map<String,dynamic>?;
            final a = selDel!['delivery_agents'] as Map<String,dynamic>?;
            Navigator.of(ctx, rootNavigator: true).pop();
            try {
              // process_return_v2(p_trader_id, p_delivery_id, p_retailer_id, p_agent_id, p_return_type, p_bird_count, p_weight_kg, p_rate_per_kg, p_reason, p_processed_by)
              await _c.rpc('process_return_v2', params: {
                'p_trader_id': tid, 'p_delivery_id': selDel!['id'],
                'p_retailer_id': o?['retailers']?['id'],
                'p_agent_id': a?['id'],
                'p_return_type': returnType,
                'p_bird_count': int.tryParse(birdsCtrl.text) ?? 0,
                'p_weight_kg': double.tryParse(wtCtrl.text) ?? 0,
                'p_rate_per_kg': rateCtrl.text.isEmpty ? null : double.tryParse(rateCtrl.text),
                'p_reason': reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
                'p_processed_by': uid,
              });
              _load(); if (mounted) showSuccess(context, 'Return processed ✓');
            } catch (e) { if (mounted) showError(context, e.toString()); }
          }, child: const Text('Process Return')),
        ]))));

    for (final c in [birdsCtrl, wtCtrl, rateCtrl, reasonCtrl]) c.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Returns'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
    floatingActionButton: FloatingActionButton.extended(onPressed: _processReturn, icon: const Icon(Icons.assignment_return_outlined), label: const Text('Process Return')),
    body: _loading ? const LoadingList() : _returns.isEmpty ? const EmptyState(icon: Icons.assignment_return_outlined, message: 'No returns recorded')
        : ListView.separated(padding: const EdgeInsets.all(16), itemCount: _returns.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final r = _returns[i];
              final retailer = r['retailers'] as Map<String,dynamic>?;
              final date = DateTime.tryParse(r['return_date'] as String? ?? '');
              return WhiteCard(child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(retailer?['shop_name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  Row(children: [StatusBadge(r['return_type'] as String? ?? '—', Colors.orange, small: true), const SizedBox(width: 6),
                    Text('${r['bird_count'] ?? 0} birds · ${(r['weight_kg'] as num?)?.toStringAsFixed(1) ?? 0} kg', style: const TextStyle(fontSize: 11, color: kTextSub))]),
                  if (r['reason'] != null) Text(r['reason'] as String, style: const TextStyle(fontSize: 11, color: kTextHint), maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  StatusBadge(r['status'] as String? ?? 'pending', SC.order(r['status'] as String? ?? 'pending'), small: true),
                  if (date != null) Text(DateFormat('d MMM').format(date), style: const TextStyle(fontSize: 10, color: kTextHint)),
                ]),
              ]));
            }),
  );
}
