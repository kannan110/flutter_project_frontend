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

  final _birdsCtrl  = TextEditingController();
  final _avgWtCtrl  = TextEditingController();
  final _totalWtCtrl= TextEditingController();
  final _rateCtrl   = TextEditingController();
  final _notesCtrl  = TextEditingController();

  List<Map<String,dynamic>> _retailers = [], _products = [];
  Map<String,dynamic>? _selRetailer, _selProduct;
  bool _saving = false, _dataLoading = true, _rateLoading = false;
  bool _wtManual = false; // user overrode total weight manually
  double? _suggestRate;

  @override void initState() { super.initState(); _loadMeta(); }
  @override void dispose() {
    _birdsCtrl.dispose(); _avgWtCtrl.dispose(); _totalWtCtrl.dispose();
    _rateCtrl.dispose(); _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMeta() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    try {
      final r = await _c.from('retailers').select('id,shop_name').eq('trader_id', tid).eq('is_active', true).order('shop_name');
      final p = await _c.from('master_products').select('id,name').eq('is_active', true).order('name');
      if (mounted) setState(() {
        _retailers   = List<Map<String,dynamic>>.from(r);
        _products    = List<Map<String,dynamic>>.from(p);
        _dataLoading = false;
      });
    } catch (e) { if (mounted) setState(() { _dataLoading = false; showError(context, e.toString()); }); }
  }

  void _autoCalcWeight() {
    if (_wtManual) return;
    final b = int.tryParse(_birdsCtrl.text.trim()) ?? 0;
    final a = double.tryParse(_avgWtCtrl.text.trim()) ?? 0;
    if (b > 0 && a > 0) {
      _totalWtCtrl.text = (b * a).toStringAsFixed(2);
    }
    setState(() {});
  }

  Future<void> _fetchRate() async {
    if (_selRetailer == null || _selProduct == null) return;
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    final kg = _totalKg > 0 ? _totalKg : (int.tryParse(_birdsCtrl.text) ?? 0) * 1.8;
    if (kg <= 0) return;
    setState(() => _rateLoading = true);
    try {
      final res = await _c.rpc('get_effective_rate_v2', params: {
        'p_trader_id': tid, 'p_retailer_id': _selRetailer!['id'],
        'p_product_id': _selProduct!['id'], 'p_quantity_kg': kg,
      });
      final rate = (res as num?)?.toDouble() ?? 0;
      if (mounted) setState(() {
        _suggestRate = rate > 0 ? rate : null;
        if (rate > 0 && _rateCtrl.text.isEmpty) _rateCtrl.text = rate.toStringAsFixed(2);
        _rateLoading = false;
      });
    } catch (_) { if (mounted) setState(() => _rateLoading = false); }
  }

  double get _totalKg  => double.tryParse(_totalWtCtrl.text.trim()) ?? 0;
  double get _rate     => double.tryParse(_rateCtrl.text.trim()) ?? 0;
  int    get _birds    => int.tryParse(_birdsCtrl.text.trim()) ?? 0;
  double get _estAmt   => _totalKg * _rate;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_selRetailer == null) { showError(context, 'Select a customer'); return; }
    if (_selProduct  == null) { showError(context, 'Select a product');  return; }

    final tid    = ref.read(appUserProvider).valueOrNull?.traderId;
    final avgWt  = double.tryParse(_avgWtCtrl.text.trim());
    final totalKg = _totalKg;
    final rate   = _rate;

    setState(() => _saving = true);
    try {
      // Insert order
      final order = await _c.from('orders').insert({
        'trader_id':   tid,
        'retailer_id': _selRetailer!['id'],
        'product_id':  _selProduct!['id'],
        'status':      'pending',
        'order_date':  DateTime.now().toIso8601String().split('T')[0],
        if (_birds > 0)              'estimated_birds': _birds,
        if (totalKg > 0)             'total_quantity':  totalKg,
        if (rate > 0 && totalKg > 0) 'total_amount':    _estAmt,
        if (rate > 0)                'final_price':     rate,
        if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
      }).select().single();

      // Insert order_items
      await _c.from('order_items').insert({
        'order_id':  order['id'],
        'trader_id': tid,
        'product_id': _selProduct!['id'],
        if (_birds > 0)                      'bird_count':         _birds,
        if (avgWt != null && avgWt > 0)      'avg_weight_per_bird': avgWt,
        if (totalKg > 0)                     'total_weight':        totalKg,
        if (rate > 0)                        'rate_per_kg':         rate,
        if (rate > 0 && totalKg > 0)         'line_total':          _estAmt,
      });

      if (mounted) {
        showSuccess(context, 'Order created ✓');
        context.go(R.orders);
      }
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', '').replaceAll('PostgrestException(message: ', ''));
    } finally { if (mounted) setState(() => _saving = false); }
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kTextHint, letterSpacing: 0.4)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('New Order')),
    body: _dataLoading ? const LoadingList() : Form(
      key: _form,
      child: ListView(padding: const EdgeInsets.all(20), children: [

        // ── Customer ──────────────────────────────────────────────
        _label('CUSTOMER'),
        DropdownButtonFormField<Map<String,dynamic>>(
          value: _selRetailer,
          hint: const Text('Select Customer'),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.store_outlined, size: 20, color: kPrimary)),
          isExpanded: true,
          items: _retailers.map((r) => DropdownMenuItem(value: r,
              child: Text(r['shop_name'] as String, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) { setState(() { _selRetailer = v; _suggestRate = null; }); _fetchRate(); },
          validator: (v) => v == null ? 'Select a customer' : null),
        const SizedBox(height: 16),

        // ── Product ───────────────────────────────────────────────
        _label('PRODUCT'),
        DropdownButtonFormField<Map<String,dynamic>>(
          value: _selProduct,
          hint: const Text('Select Product'),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.set_meal_outlined, size: 20, color: kPrimary)),
          isExpanded: true,
          items: _products.map((p) => DropdownMenuItem(value: p,
              child: Text(p['name'] as String))).toList(),
          onChanged: (v) { setState(() { _selProduct = v; _suggestRate = null; }); _fetchRate(); },
          validator: (v) => v == null ? 'Select a product' : null),
        const SizedBox(height: 16),

        // ── Weight section ────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.blue.shade100)),
          child: const Row(children: [
            Icon(Icons.info_outline, color: Colors.blue, size: 16),
            SizedBox(width: 8),
            Expanded(child: Text('Bill is calculated on weight (kg), not on number of birds.',
                style: TextStyle(fontSize: 12, color: Colors.blue))),
          ])),
        const SizedBox(height: 14),

        _label('NUMBER OF BIRDS (OPTIONAL)'),
        TextFormField(
          controller: _birdsCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'e.g. 150',
            suffixText: 'birds',
            prefixIcon: Icon(Icons.numbers_outlined, size: 20, color: kPrimary)),
          onChanged: (_) { _autoCalcWeight(); _fetchRate(); }),
        const SizedBox(height: 12),

        _label('AVG WEIGHT PER BIRD (KG)'),
        TextFormField(
          controller: _avgWtCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            hintText: 'e.g. 1.8',
            suffixText: 'kg/bird',
            prefixIcon: Icon(Icons.scale_outlined, size: 20, color: kPrimary),
            helperText: 'Total weight = birds × avg weight'),
          onChanged: (_) { _autoCalcWeight(); _fetchRate(); }),
        const SizedBox(height: 12),

        _label('TOTAL WEIGHT (KG) *'),
        TextFormField(
          controller: _totalWtCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: 'e.g. 270.5',
            suffixText: 'kg',
            prefixIcon: const Icon(Icons.balance_outlined, size: 20, color: kPrimary),
            helperText: _birds > 0 && !_wtManual
                ? 'Auto-calculated: $_birds × ${_avgWtCtrl.text} kg'
                : 'Enter actual total weight',
            suffixIcon: _wtManual
                ? TextButton(
                    onPressed: () { setState(() => _wtManual = false); _autoCalcWeight(); },
                    child: const Text('Auto', style: TextStyle(fontSize: 11, color: kPrimary)))
                : null),
          onChanged: (v) { _wtManual = v.isNotEmpty; setState(() {}); _fetchRate(); },
          validator: (v) {
            final n = double.tryParse(v?.trim() ?? '');
            return (n == null || n <= 0) ? 'Enter total weight in kg' : null;
          }),
        const SizedBox(height: 16),

        // ── Rate ──────────────────────────────────────────────────
        _label('RATE PER KG (₹)'),
        TextFormField(
          controller: _rateCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: 'e.g. 200',
            prefixText: '₹',
            suffixText: '/kg',
            prefixIcon: const Icon(Icons.currency_rupee, size: 20, color: kPrimary),
            helperText: _suggestRate != null
                ? 'Suggested: ₹${_suggestRate!.toStringAsFixed(2)}/kg'
                : 'Optional — can be set later at approval',
            suffixIcon: _rateLoading
                ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                : null),
          onChanged: (_) => setState(() {})),

        // ── Estimate ──────────────────────────────────────────────
        if (_totalKg > 0 && _rate > 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kPrimary.withOpacity(0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kPrimary.withOpacity(0.2))),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Estimated Bill', style: TextStyle(fontSize: 12, color: kTextSub, fontWeight: FontWeight.w600)),
                Text(Fmt.amount(_estAmt), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: kPrimary)),
              ]),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('${_totalKg.toStringAsFixed(2)} kg', style: const TextStyle(fontSize: 12, color: kTextSub)),
                Text('× ₹${_rateCtrl.text}/kg', style: const TextStyle(fontSize: 12, color: kTextSub)),
              ]),
            ])),
        ],
        const SizedBox(height: 16),

        // ── Notes ─────────────────────────────────────────────────
        _label('NOTES (OPTIONAL)'),
        TextFormField(controller: _notesCtrl, maxLines: 2,
            decoration: const InputDecoration(hintText: 'Any special instructions...')),
        const SizedBox(height: 28),

        // ── Submit ────────────────────────────────────────────────
        SizedBox(height: 52, child: ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : const Text('Create Order', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        )),
        const SizedBox(height: 8),
        const Center(child: Text('Actual bill will be calculated on delivered weight at approval',
            style: TextStyle(fontSize: 11, color: kTextHint), textAlign: TextAlign.center)),
        const SizedBox(height: 20),
      ]),
    ),
  );
}
