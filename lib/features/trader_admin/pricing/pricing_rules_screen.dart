import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/responsive_layout.dart';

class PricingRulesScreen extends ConsumerStatefulWidget {
  const PricingRulesScreen({super.key});
  @override ConsumerState<PricingRulesScreen> createState() => _S();
}
class _S extends ConsumerState<PricingRulesScreen> {
  final _c = Supabase.instance.client;
  List<Map<String,dynamic>> _rules = [], _retailers = [], _products = [];
  bool _loading = true;
  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    if (mounted) setState(() => _loading = true);
    try {
      // pricing_rules: id,rule_type,rate_per_kg,discount_pct,discount_amount,min_quantity_kg,is_active,created_at
      // rule_type CHECK: flat, percentage_discount, absolute_discount, bulk_tier
      final r = await _c.from('pricing_rules').select('*,retailers(shop_name),master_products(name)').eq('trader_id', tid).order('created_at', ascending: false);
      final ret = await _c.from('retailers').select('id,shop_name').eq('trader_id', tid).eq('is_active', true);
      final prod = await _c.from('master_products').select('id,name').eq('is_active', true);
      if (mounted) setState(() { _rules = List<Map<String,dynamic>>.from(r); _retailers = List<Map<String,dynamic>>.from(ret); _products = List<Map<String,dynamic>>.from(prod); _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _addRule() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    final uid = ref.read(appUserProvider).valueOrNull?.userId;
    Map<String,dynamic>? selRetailer, selProduct;
    String ruleType = 'flat';
    final rateCtrl = TextEditingController(); final discPctCtrl = TextEditingController(text: '0'); final minQtyCtrl = TextEditingController(text: '0');

    await showModalBottomSheet(context: context, isScrollControlled: true, useRootNavigator: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: StatefulBuilder(builder: (_, ss) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Add Pricing Rule', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              DropdownButtonFormField<Map<String,dynamic>>(hint: const Text('Retailer (blank = all)'),
                  items: [const DropdownMenuItem(value: null, child: Text('All Retailers')), ..._retailers.map((r) => DropdownMenuItem(value: r, child: Text(r['shop_name'] as String)))],
                  onChanged: (v) => ss(() => selRetailer = v)),
              const SizedBox(height: 8),
              DropdownButtonFormField<Map<String,dynamic>>(hint: const Text('Product (blank = all)'),
                  items: [const DropdownMenuItem(value: null, child: Text('All Products')), ..._products.map((p) => DropdownMenuItem(value: p, child: Text(p['name'] as String)))],
                  onChanged: (v) => ss(() => selProduct = v)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                  segments: const [ButtonSegment(value:'flat', label:Text('Flat Rate')), ButtonSegment(value:'percentage_discount', label:Text('% Disc.')), ButtonSegment(value:'absolute_discount', label:Text('Abs. Disc.'))],
                  selected: {ruleType}, onSelectionChanged: (s) => ss(() => ruleType = s.first)),
              const SizedBox(height: 8),
              if (ruleType == 'flat') TextField(controller: rateCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Rate ₹/kg', prefixText: '₹')),
              if (ruleType == 'percentage_discount') TextField(controller: discPctCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Discount %', suffixText: '%')),
              if (ruleType == 'absolute_discount') TextField(controller: rateCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Discount Amount ₹', prefixText: '₹')),
              const SizedBox(height: 8),
              TextField(controller: minQtyCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Min Qty (kg, 0=always)', suffixText: 'kg')),
              const SizedBox(height: 14),
              ElevatedButton(onPressed: () async {
                Navigator.of(ctx, rootNavigator: true).pop();
                try {
                  await _c.from('pricing_rules').insert({
                    'trader_id': tid, 'retailer_id': selRetailer?['id'], 'product_id': selProduct?['id'],
                    'rule_type': ruleType,
                    'rate_per_kg': ruleType == 'flat' ? double.tryParse(rateCtrl.text) : null,
                    'discount_pct': ruleType == 'percentage_discount' ? double.tryParse(discPctCtrl.text) ?? 0 : 0,
                    'discount_amount': ruleType == 'absolute_discount' ? double.tryParse(rateCtrl.text) ?? 0 : 0,
                    'min_quantity_kg': double.tryParse(minQtyCtrl.text) ?? 0,
                    'is_active': true, 'created_by': uid,
                  });
                  _load(); if (mounted) showSuccess(context, 'Rule added ✓');
                } catch (e) { if (mounted) showError(context, e.toString()); }
              }, child: const Text('Add Rule')),
            ]))));
    for (final c in [rateCtrl, discPctCtrl, minQtyCtrl]) c.dispose();
  }

  Widget _buildScaffold(BuildContext context) => Scaffold(
    backgroundColor: kBgPage,
    appBar: AppBar(backgroundColor: kSurface, title: const Text('Pricing Rules'), actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)]),
    floatingActionButton: FloatingActionButton.extended(onPressed: _addRule, icon: const Icon(Icons.add), label: const Text('Add Rule')),
    body: _loading ? const LoadingList() : _rules.isEmpty ? const EmptyState(icon: Icons.rule_outlined, message: 'No pricing rules', sub: 'Set custom rates or discounts per retailer or product')
        : ListView.separated(padding: const EdgeInsets.all(16), itemCount: _rules.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final rule = _rules[i];
          final retailer = rule['retailers'] as Map<String,dynamic>?;
          final product = rule['master_products'] as Map<String,dynamic>?;
          final type = rule['rule_type'] as String? ?? 'flat';
          final rate = (rule['rate_per_kg'] as num?)?.toDouble();
          final pct = (rule['discount_pct'] as num?)?.toDouble() ?? 0;
          final abs = (rule['discount_amount'] as num?)?.toDouble() ?? 0;
          final valueStr = type == 'flat' ? '₹${rate?.toStringAsFixed(2) ?? '—'}/kg'
              : type == 'percentage_discount' ? '${pct.toStringAsFixed(1)}% off'
              : '₹${abs.toStringAsFixed(2)} off';
          return WhiteCard(child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(retailer?['shop_name'] as String? ?? 'All Retailers', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              Text(product?['name'] as String? ?? 'All Products', style: const TextStyle(fontSize: 12, color: kTextSub)),
              StatusBadge(type.replaceAll('_',' '), Colors.blue, small: true),
            ])),
            Text(valueStr, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: kNavy)),
            IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: kError), onPressed: () async {
              final ok = await confirmDialog(context, title: 'Delete Rule', message: 'Delete this pricing rule?');
              if (ok) { await _c.from('pricing_rules').delete().eq('id', rule['id']); _load(); }
            }),
          ]));
        }),
  );
  @override
  Widget build(BuildContext context) => ResponsiveLayout(
    mobile:  (_) => _buildScaffold(context),
    desktop: (_) => _buildScaffold(context),
  );

}