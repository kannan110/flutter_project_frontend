import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class CreateOrderScreen extends ConsumerStatefulWidget {
  const CreateOrderScreen({super.key});
  @override ConsumerState<CreateOrderScreen> createState() => _S();
}

class _S extends ConsumerState<CreateOrderScreen> {
  final _c    = Supabase.instance.client;
  final _form = GlobalKey<FormState>();
  final _birds    = TextEditingController();
  final _avgWt    = TextEditingController();
  final _totalWt  = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _notes    = TextEditingController();

  List<Map<String,dynamic>> _retailers = [], _products = [];
  Map<String,dynamic>? _selRetailer, _selProduct;
  bool _loading = false, _dataLoading = true, _rateLoading = false;
  bool _totalWtManual = false;
  double? _suggestedRate;

  @override void initState() { super.initState(); _loadData(); }
  @override void dispose() {
    _birds.dispose(); _avgWt.dispose(); _totalWt.dispose();
    _rateCtrl.dispose(); _notes.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    final r = await _c.from('retailers').select('id,shop_name').eq('trader_id', tid).eq('is_active', true).order('shop_name');
    final p = await _c.from('master_products').select('id,name').eq('is_active', true).order('name');
    if (mounted) setState(() {
      _retailers = List<Map<String,dynamic>>.from(r);
      _products  = List<Map<String,dynamic>>.from(p);
      _dataLoading = false;
    });
  }

  void _calcTotalWeight() {
    if (_totalWtManual) return;
    final birds = int.tryParse(_birds.text.trim()) ?? 0;
    final avg   = double.tryParse(_avgWt.text.trim()) ?? 0;
    if (birds > 0 && avg > 0) {
      _totalWt.text = (birds * avg).toStringAsFixed(2);
    }
    setState(() {});
  }

  Future<void> _fetchRate() async {
    if (_selRetailer == null || _selProduct == null) return;
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    final kg  = double.tryParse(_totalWt.text) ?? ((int.tryParse(_birds.text) ?? 0) * 1.8);
    setState(() => _rateLoading = true);
    try {
      final res = await _c.rpc('get_effective_rate_v2', params: {
        'p_trader_id': tid, 'p_retailer_id': _selRetailer!['id'],
        'p_product_id': _selProduct!['id'], 'p_quantity_kg': kg,
      });
      final rate = (res as num?)?.toDouble() ?? 0;
      if (mounted) setState(() {
        _suggestedRate = rate > 0 ? rate : null;
        if (rate > 0 && _rateCtrl.text.isEmpty) _rateCtrl.text = rate.toStringAsFixed(2);
        _rateLoading = false;
      });
    } catch (_) { if (mounted) setState(() => _rateLoading = false); }
  }

  double get _totalKg => double.tryParse(_totalWt.text) ?? 0;
  double get _rate    => double.tryParse(_rateCtrl.text) ?? 0;
  double get _estAmt  => _totalKg * _rate;
  int    get _birdCount => int.tryParse(_birds.text) ?? 0;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_selRetailer == null) { showError(context, 'Select a customer'); return; }
    if (_selProduct  == null) { showError(context, 'Select a product'); return; }

    final tid     = ref.read(appUserProvider).valueOrNull?.traderId;
    final birds   = _birdCount;
    final avgWt   = double.tryParse(_avgWt.text.trim());
    final totalKg = _totalKg;
    final rate    = _rate;

    setState(() => _loading = true);
    try {
      final order = await _c.from('orders').insert({
        'trader_id': tid, 'retailer_id': _selRetailer!['id'],
        'product_id': _selProduct!['id'], 'status': 'pending',
        'order_date': DateTime.now().toIso8601String().split('T')[0],
        if (birds > 0)     'estimated_birds': birds,
        if (totalKg > 0)   'total_quantity': totalKg,
        if (rate > 0 && totalKg > 0) 'total_amount': _estAmt,
        if (rate > 0)      'final_price': rate,
        if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
      }).select().single();

      await _c.from('order_items').insert({
        'order_id': order['id'], 'trader_id': tid, 'product_id': _selProduct!['id'],
        if (birds > 0)               'bird_count': birds,
        if (avgWt != null && avgWt > 0) 'avg_weight_per_bird': avgWt,
        if (totalKg > 0)             'total_weight': totalKg,
        if (rate > 0)                'rate_per_kg': rate,
        if (rate > 0 && totalKg > 0) 'line_total': _estAmt,
      });

      if (mounted) { showSuccess(context, 'Order created'); context.go(R.orders); }
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('New Order')),
    body: _dataLoading ? const LoadingList() : SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(key: _form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

        const SectionHeader('CUSTOMER'),
        DropdownButtonFormField<Map<String,dynamic>>(
          value: _selRetailer, hint: const Text('Select Customer'),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.store_outlined, size: 20)),
          items: _retailers.map((r) => DropdownMenuItem(value: r, child: Text(r['shop_name'] as String, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) { setState(() { _selRetailer = v; _suggestedRate = null; }); _fetchRate(); },
          validator: (v) => v == null ? 'Select a customer' : null),
        const SizedBox(height: 14),

        const SectionHeader('PRODUCT'),
        DropdownButtonFormField<Map<String,dynamic>>(
          value: _selProduct, hint: const Text('Select Product'),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.set_meal_outlined, size: 20)),
          items: _products.map((p) => DropdownMenuItem(value: p, child: Text(p['name'] as String))).toList(),
          onChanged: (v) { setState(() { _selProduct = v; _suggestedRate = null; }); _fetchRate(); },
          validator: (v) => v == null ? 'Select a product' : null),
        const SizedBox(height: 14),

        const SectionHeader('WEIGHT (BILL IS CALCULATED ON WEIGHT)'),
        TextFormField(
          controller: _birds, keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Number of Birds (optional)', suffixText: 'birds',
            prefixIcon: Icon(Icons.numbers_outlined, size: 20),
            helperText: 'Enter to auto-calculate weight'),
          onChanged: (_) { _calcTotalWeight(); _fetchRate(); }),
        const SizedBox(height: 10),

        TextFormField(
          controller: _avgWt, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Avg Weight per Bird (kg)', suffixText: 'kg/bird',
            prefixIcon: Icon(Icons.scale_outlined, size: 20),
            helperText: 'e.g. 1.8 kg — used to auto-calculate total'),
          onChanged: (_) { _calcTotalWeight(); _fetchRate(); }),
        const SizedBox(height: 10),

        TextFormField(
          controller: _totalWt, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Total Weight (kg) *', suffixText: 'kg',
            prefixIcon: const Icon(Icons.balance_outlined, size: 20),
            helperText: _birdCount > 0 && !_totalWtManual
                ? 'Auto: $_birdCount birds × ${_avgWt.text} kg'
                : 'Enter total weight in kg',
            suffixIcon: _totalWtManual ? TextButton(
              onPressed: () { setState(() => _totalWtManual = false); _calcTotalWeight(); },
              child: const Text('Auto', style: TextStyle(fontSize: 11))) : null),
          onChanged: (v) { _totalWtManual = v.isNotEmpty; setState(() {}); _fetchRate(); },
          validator: (v) {
            final n = double.tryParse(v ?? '');
            return (n == null || n <= 0) ? 'Enter total weight in kg' : null;
          }),
        const SizedBox(height: 14),

        const SectionHeader('RATE PER KG (₹)'),
        TextFormField(
          controller: _rateCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Rate per kg (₹)', prefixText: '₹',
            prefixIcon: const Icon(Icons.currency_rupee, size: 20),
            helperText: _suggestedRate != null
                ? 'Suggested: ₹${_suggestedRate!.toStringAsFixed(2)}/kg (you can change)'
                : 'Can be set later at delivery approval',
            suffixIcon: _rateLoading ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null),
          onChanged: (_) => setState(() {})),

        if (_totalKg > 0 && _rate > 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kPrimary.withOpacity(0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kPrimary.withOpacity(0.2))),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Estimated Bill', style: TextStyle(fontSize: 12, color: kTextSub, fontWeight: FontWeight.w600)),
                Text(Fmt.amount(_estAmt), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: kPrimary)),
              ]),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('${_totalKg.toStringAsFixed(2)} kg', style: const TextStyle(fontSize: 12, color: kTextSub)),
                Text('× ₹${_rate.toStringAsFixed(2)}/kg', style: const TextStyle(fontSize: 12, color: kTextSub)),
              ]),
              if (_birdCount > 0) Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('$_birdCount birds', style: const TextStyle(fontSize: 11, color: kTextHint)),
                Text('≈ ${(_totalKg / _birdCount).toStringAsFixed(2)} kg/bird', style: const TextStyle(fontSize: 11, color: kTextHint)),
              ]),
            ])),
        ],
        const SizedBox(height: 14),

        TextFormField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes (optional)', alignLabelWithHint: true)),
        const SizedBox(height: 28),

        ElevatedButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : const Text('Create Order', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
        const SizedBox(height: 8),
        const Center(child: Text('Bill is calculated on actual delivered weight — not bird count',
            style: TextStyle(fontSize: 11, color: kTextHint), textAlign: TextAlign.center)),
      ])),
    ),
  );
}
