import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class RatesScreen extends ConsumerStatefulWidget {
  const RatesScreen({super.key});
  @override ConsumerState<RatesScreen> createState() => _S();
}
class _S extends ConsumerState<RatesScreen> {
  final _c = Supabase.instance.client;
  List<Map<String,dynamic>> _products = [];
  Map<String, double> _rates = {};
  bool _loading = true;
  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    setState(() => _loading = true);
    try {
      final products = await _c.from('master_products').select('id,name').eq('is_active', true).order('name');
      // rate_history: id, trader_id, product_id, rate_per_kg, effective_date, created_at
      final history = await _c.from('rate_history').select('product_id,rate_per_kg').eq('trader_id', tid).order('effective_date', ascending: false).limit(100);
      final Map<String,double> rates = {};
      for (final h in history) { final pid = h['product_id'] as String; if (!rates.containsKey(pid)) rates[pid] = (h['rate_per_kg'] as num).toDouble(); }
      if (mounted) setState(() { _products = List<Map<String,dynamic>>.from(products); _rates = rates; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _setRate(Map<String,dynamic> product) async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    final ctrl = TextEditingController(text: _rates[product['id']]?.toStringAsFixed(2) ?? '');
    final result = await showDialog<double>(context: context, builder: (ctx) => AlertDialog(
      title: Text('Rate — ${product['name']}'),
      content: TextField(controller: ctrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), autofocus: true,
          decoration: const InputDecoration(labelText: '₹ per kg')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(onPressed: () { final v = double.tryParse(ctrl.text); if (v != null && v > 0) Navigator.pop(ctx, v); }, child: const Text('Save')),
      ]));
    ctrl.dispose();
    if (result == null) return;
    try {
      // rate_history: trader_id, product_id, rate_per_kg, effective_date
      await _c.from('rate_history').insert({'trader_id': tid, 'product_id': product['id'], 'rate_per_kg': result, 'effective_date': DateTime.now().toIso8601String().split('T')[0]});
      setState(() => _rates[product['id'] as String] = result);
      if (mounted) showSuccess(context, 'Rate updated ✓');
    } catch (e) { if (mounted) showError(context, e.toString()); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("Today's Rates"), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
    body: _loading ? const LoadingList() : ListView.separated(
      padding: const EdgeInsets.all(16), itemCount: _products.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final p = _products[i];
        final rate = _rates[p['id']];
        return WhiteCard(child: Row(children: [
          const Icon(Icons.set_meal_outlined, color: kPrimary, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(p['name'] as String, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
          if (rate != null) Text('₹${rate.toStringAsFixed(2)}/kg', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: kPrimary))
          else const Text('Not set', style: TextStyle(color: kTextHint)),
          const SizedBox(width: 8),
          IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _setRate(p)),
        ]));
      }),
  );
}
