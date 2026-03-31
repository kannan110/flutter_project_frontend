import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key});
  @override ConsumerState<StockScreen> createState() => _S();
}
class _S extends ConsumerState<StockScreen> {
  final _c = Supabase.instance.client;
  List<Map<String,dynamic>> _positions = [];
  List<Map<String,dynamic>> _ledger = [];
  List<Map<String,dynamic>> _products = [];
  bool _loading = true;
  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    setState(() => _loading = true);
    try {
      final pos = await _c.rpc('get_stock_position_v2', params: {'p_trader_id': tid});
      // stock_ledger columns: id,entry_date,movement_type,quantity_birds,quantity_kg,notes,created_at
      final led = await _c.from('stock_ledger').select('id,entry_date,movement_type,quantity_birds,quantity_kg,notes,master_products(name)').eq('trader_id', tid).order('created_at', ascending: false).limit(50);
      final prod = await _c.from('master_products').select('id,name').eq('is_active', true);
      if (mounted) setState(() { _positions = List<Map<String,dynamic>>.from(pos as List? ?? []); _ledger = List<Map<String,dynamic>>.from(led); _products = List<Map<String,dynamic>>.from(prod); _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _recordOpening() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    final uid = ref.read(appUserProvider).valueOrNull?.userId;
    if (_products.isEmpty) { showError(context, 'No products found'); return; }
    Map<String,dynamic>? selProd;
    final birdsCtrl = TextEditingController(); final kgCtrl = TextEditingController(); final notesCtrl = TextEditingController();

    await showModalBottomSheet(context: context, isScrollControlled: true, useRootNavigator: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Record Opening Stock', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          DropdownButtonFormField<Map<String,dynamic>>(hint: const Text('Product *'),
              items: _products.map((p) => DropdownMenuItem(value: p, child: Text(p['name'] as String))).toList(),
              onChanged: (v) => selProd = v),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: birdsCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Birds *'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: kgCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Weight (kg) *'))),
          ]),
          const SizedBox(height: 10),
          TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes (optional)')),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: () async {
            if (selProd == null) return;
            final b = int.tryParse(birdsCtrl.text); final k = double.tryParse(kgCtrl.text);
            if (b == null || k == null || b <= 0 || k <= 0) return;
            Navigator.of(ctx, rootNavigator: true).pop();
            try {
              // record_opening_stock(p_trader_id, p_product_id, p_birds, p_kg, p_notes, p_created_by)
              await _c.rpc('record_opening_stock', params: {'p_trader_id': tid, 'p_product_id': selProd!['id'], 'p_birds': b, 'p_kg': k, 'p_notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(), 'p_created_by': uid});
              _load(); if (mounted) showSuccess(context, 'Opening stock recorded ✓');
            } catch (e) { if (mounted) showError(context, e.toString()); }
          }, child: const Text('Record Stock')),
        ])));
    for (final c in [birdsCtrl, kgCtrl, notesCtrl]) c.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Stock'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
    floatingActionButton: FloatingActionButton.extended(onPressed: _recordOpening, icon: const Icon(Icons.add), label: const Text('Opening Stock')),
    body: _loading ? const LoadingList() : ListView(padding: const EdgeInsets.all(16), children: [
      const SectionHeader('CURRENT STOCK POSITION'),
      if (_positions.isEmpty)
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.shade200)),
          child: Row(children: [Icon(Icons.warning_amber_outlined, color: Colors.orange.shade700, size: 18), const SizedBox(width: 8), const Expanded(child: Text('No stock recorded today. Tap + to add opening stock.', style: TextStyle(fontSize: 13, color: Colors.orange)))]))
      else ..._positions.map((p) => Container(margin: const EdgeInsets.only(bottom: 10), child: WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(p['product_name'] as String? ?? '—', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(children: [
          _stat('Opening', '${p['opening_birds'] ?? 0}', '${(p['opening_kg'] as num?)?.toStringAsFixed(1) ?? 0} kg'),
          _stat('Sold', '${p['sold_birds'] ?? 0}', '${(p['sold_kg'] as num?)?.toStringAsFixed(1) ?? 0} kg'),
          _stat('Remaining', '${p['remaining_birds'] ?? 0}', '${(p['remaining_kg'] as num?)?.toStringAsFixed(1) ?? 0} kg',
              color: (p['remaining_birds'] as int? ?? 0) < 50 ? Colors.orange : kPrimary),
        ]),
      ])))),
      const SizedBox(height: 14),
      if (_ledger.isNotEmpty) ...[
        const SectionHeader('STOCK MOVEMENTS'),
        ..._ledger.map((l) {
          final prod = l['master_products'] as Map<String,dynamic>?;
          // stock_ledger: movement_type CHECK: opening,purchased,allocated,delivered,returned_in,mortality,shrinkage,adjustment
          final mt = l['movement_type'] as String? ?? '—';
          final date = DateTime.tryParse(l['entry_date'] as String? ?? '');
          return Container(margin: const EdgeInsets.only(bottom: 6), child: WhiteCard(padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(prod?['name'] as String? ?? '—', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                // Correct columns: quantity_birds, quantity_kg (NOT birds, kg)
                Text('${l['quantity_birds'] ?? 0} birds · ${(l['quantity_kg'] as num?)?.toStringAsFixed(1) ?? 0} kg', style: const TextStyle(fontSize: 11, color: kTextSub)),
              ])),
              StatusBadge(mt.replaceAll('_',' '), _mtColor(mt), small: true),
              if (date != null) ...[const SizedBox(width: 6), Text(DateFormat('d MMM').format(date), style: const TextStyle(fontSize: 10, color: kTextHint))],
            ])));
        }),
      ],
    ]),
  );

  Widget _stat(String l, String b, String k, {Color? color}) => Expanded(child: Column(children: [
    Text(l, style: const TextStyle(fontSize: 10, color: kTextHint)),
    Text(b, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color ?? kTextMain)),
    Text(k, style: const TextStyle(fontSize: 10, color: kTextSub)),
  ]));

  Color _mtColor(String m) => switch(m) { 'opening' => Colors.blue, 'purchased' => Colors.blue, 'allocated' => Colors.orange, 'delivered' => Colors.green, 'returned_in' => Colors.purple, 'mortality' => Colors.red, _ => Colors.grey };
}
