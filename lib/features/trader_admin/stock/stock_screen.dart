import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/dashboard_models.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key});
  @override ConsumerState<StockScreen> createState() => _S();
}
class _S extends ConsumerState<StockScreen> {
  final _c = Supabase.instance.client;
  List<StockPosition> _positions = [];
  List<Map<String,dynamic>> _ledger = [];
  List<Map<String,dynamic>> _products = [];
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null || !mounted) return;
    if (mounted) setState(() => _loading = true);
    try {
      final r0 = await _c.rpc('get_available_stock', params: {'p_trader_id': tid});
      final r1 = await _c.from('stock_ledger').select('id,entry_date,movement_type,quantity_birds,quantity_kg,notes,master_products(name)').eq('trader_id', tid).order('created_at', ascending: false).limit(50);
      final r2 = await _c.from('master_products').select('id,name').eq('is_active', true);
      final results = <dynamic>[r0, r1, r2];
      if (!mounted) return;
      if (mounted) setState(() {
        _positions = ((results[0] as List?) ?? []).map((s) => StockPosition.fromMap(s as Map<String,dynamic>)).toList();
        _ledger    = List<Map<String,dynamic>>.from((results[1] as List?) ?? []);
        _products  = List<Map<String,dynamic>>.from((results[2] as List?) ?? []);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (mounted) setState(() => _loading = false);
      if (mounted) showError(context, e.toString());
    }
  }

  Future<void> _recordOpening() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    final uid = ref.read(appUserProvider).valueOrNull?.userId;
    if (_products.isEmpty || !mounted) return;

    Map<String,dynamic>? selProd;
    final birdsCtrl = TextEditingController();
    final kgCtrl    = TextEditingController();
    final notesCtrl = TextEditingController();

    await showModalBottomSheet(context: context, isScrollControlled: true, useRootNavigator: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Record Opening Stock', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          DropdownButtonFormField<Map<String,dynamic>>(hint: const Text('Product *'),
            items: _products.map((p) => DropdownMenuItem(value: p, child: Text(p['name'] as String))).toList(),
            onChanged: (v) => selProd = v),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: birdsCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Birds *', suffixText: 'birds'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: kgCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Weight (kg) *', suffixText: 'kg'))),
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
              await _c.rpc('record_opening_stock', params: {'p_trader_id': tid, 'p_product_id': selProd!['id'], 'p_birds': b, 'p_kg': k, 'p_notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(), 'p_created_by': uid});
              _load();
              if (mounted) showSuccess(context, 'Opening stock recorded ✓');
            } catch (e) { if (mounted) showError(context, e.toString()); }
          }, child: const Text('Save')),
        ])));
    birdsCtrl.dispose(); kgCtrl.dispose(); notesCtrl.dispose();
  }

  Color _movementColor(String t) => switch(t) {
    'opening'    => Colors.blue,
    'purchased'  => Colors.green,
    'returned_in'=> Colors.purple,
    'delivered'  => kPrimary,
    'allocated'  => Colors.orange,
    'mortality'  => Colors.red,
    'shrinkage'  => Colors.deepOrange,
    _            => Colors.grey,
  };

  IconData _movementIcon(String t) => switch(t) {
    'opening'    => Icons.home_outlined,
    'purchased'  => Icons.add_shopping_cart,
    'returned_in'=> Icons.assignment_return_outlined,
    'delivered'  => Icons.local_shipping_outlined,
    'allocated'  => Icons.inventory_outlined,
    'mortality'  => Icons.sentiment_very_dissatisfied_outlined,
    'shrinkage'  => Icons.compress_outlined,
    _            => Icons.circle_outlined,
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Stock Management'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
    floatingActionButton: FloatingActionButton.extended(onPressed: _recordOpening, icon: const Icon(Icons.add), label: const Text('Opening Stock')),
    body: _loading ? const LoadingList() : ListView(padding: const EdgeInsets.all(16), children: [

      // ── Stock positions (cumulative) ──────────────────────────────
      const SectionHeader('CURRENT STOCK (CUMULATIVE)'),
      if (_positions.isEmpty) Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.shade200)),
        child: const Row(children: [Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18), SizedBox(width: 8), Expanded(child: Text('No stock yet. Tap + to record opening stock.', style: TextStyle(fontSize: 13, color: Colors.orange)))]))
      else ..._positions.map((p) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.isNegative ? Colors.red.shade200 : p.hasLowStock ? Colors.orange.shade200 : kBorder)),
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(14,12,14,8), child: Row(children: [
            Expanded(child: Text(p.productName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
            if (p.isNegative) const StatusBadge('NEGATIVE', Colors.red)
            else if (p.hasLowStock) const StatusBadge('LOW STOCK', Colors.orange),
          ])),
          Padding(padding: const EdgeInsets.fromLTRB(14,0,14,12), child: Row(children: [
            _b('Total In',    '${p.totalInBirds}',   '${p.totalInKg.toStringAsFixed(0)} kg',  Colors.blue),
            _b('Delivered',   '${p.totalOutBirds}',  '${p.totalOutKg.toStringAsFixed(0)} kg', kPrimary),
            _b('Returns',     '${p.returnedBirds}',  '',                                       Colors.purple),
            _b('Remaining',   '${p.availableBirds}', '${p.availableKg.toStringAsFixed(0)} kg', p.isNegative ? Colors.red : p.hasLowStock ? Colors.orange : Colors.green),
          ])),
        ]))),

      // ── Ledger ────────────────────────────────────────────────────
      const SectionHeader('STOCK MOVEMENTS'),
      if (_ledger.isEmpty) const Text('No movements recorded.', style: TextStyle(color: kTextHint, fontSize: 13))
      else ..._ledger.map((l) {
        final prod = l['master_products'] as Map<String,dynamic>?;
        final mt   = l['movement_type'] as String? ?? '—';
        final date = DateTime.tryParse(l['entry_date'] as String? ?? '');
        final birds= (l['quantity_birds'] as num?)?.toInt() ?? 0;
        final kg   = (l['quantity_kg'] as num?)?.toDouble() ?? 0;
        final isIn = ['opening','purchased','returned_in'].contains(mt);
        final color= _movementColor(mt);
        return Container(margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: const Border.fromBorderSide(BorderSide(color: kBorder))),
          child: ListTile(dense: true,
            leading: Container(width: 34, height: 34, decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(_movementIcon(mt), color: color, size: 16)),
            title: Text('${prod?['name'] ?? '—'} · ${mt.replaceAll('_', ' ')}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            subtitle: Text(l['notes'] as String? ?? '', style: const TextStyle(fontSize: 10, color: kTextHint), maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${isIn ? '+' : '−'}$birds birds', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
              if (kg > 0) Text('${kg.toStringAsFixed(1)} kg', style: const TextStyle(fontSize: 10, color: kTextHint)),
              if (date != null) Text(DateFormat('d MMM').format(date), style: const TextStyle(fontSize: 9, color: kTextHint)),
            ])));
      }),
    ]),
  );

  Widget _b(String label, String birds, String kg, Color color) => Expanded(child: Column(children: [
    Text(birds, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
    if (kg.isNotEmpty) Text(kg, style: const TextStyle(fontSize: 9, color: kTextSub)),
    Text(label, style: const TextStyle(fontSize: 9, color: kTextHint)),
  ]));
}
