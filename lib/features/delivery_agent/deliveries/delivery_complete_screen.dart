import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class DeliveryCompleteScreen extends ConsumerStatefulWidget {
  const DeliveryCompleteScreen({super.key, required this.deliveryId});
  final String deliveryId;
  @override ConsumerState<DeliveryCompleteScreen> createState() => _S();
}
class _S extends ConsumerState<DeliveryCompleteScreen> {
  final _form             = GlobalKey<FormState>();
  final _birdsCtrl        = TextEditingController();
  final _weightCtrl       = TextEditingController();
  final _rcvBirdsCtrl     = TextEditingController();
  final _rcvWeightCtrl    = TextEditingController();
  final _mortalityCtrl    = TextEditingController(text: '0');
  final _rejectedCtrl     = TextEditingController(text: '0');
  final _retBirdsCtrl     = TextEditingController(text: '0');
  final _retWeightCtrl    = TextEditingController(text: '0');
  final _shrinkCtrl       = TextEditingController(text: '0');
  final _cratesGivenCtrl  = TextEditingController(text: '0');
  final _cratesGotCtrl    = TextEditingController(text: '0');
  final _cratesRetCtrl    = TextEditingController(text: '0');
  final _cashCtrl         = TextEditingController(text: '0');
  final _notesCtrl        = TextEditingController();

  String _payMode = 'cash';
  bool _submitting = false;
  Map<String,dynamic>? _delivery;
  int _availBirds = -1;   // -1 = no stock records; ≥0 = actual count
  double _availKg  = -1;

  @override void initState() { super.initState(); _load(); }
  @override void dispose() {
    for (final c in [_birdsCtrl,_weightCtrl,_rcvBirdsCtrl,_rcvWeightCtrl,
        _mortalityCtrl,_rejectedCtrl,_retBirdsCtrl,_retWeightCtrl,_shrinkCtrl,
        _cratesGivenCtrl,_cratesGotCtrl,_cratesRetCtrl,_cashCtrl,_notesCtrl]) c.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final d = await Supabase.instance.client.from('deliveries')
        .select('*,orders(estimated_birds,total_quantity,product_id,retailers(shop_name,address,phone))')
        .eq('id', widget.deliveryId).maybeSingle();
    if (!mounted || d == null) return;
    if (mounted) setState(() => _delivery = d);

    final o = d['orders'] as Map<String,dynamic>?;
    _birdsCtrl.text   = '${d['expected_bird_count'] ?? o?['estimated_birds'] ?? ''}';
    _weightCtrl.text  = '${(d['expected_total_weight'] as num?)?.toStringAsFixed(2) ?? (o?['total_quantity'] as num?)?.toStringAsFixed(2) ?? ''}';
    _rcvBirdsCtrl.text  = _birdsCtrl.text;
    _rcvWeightCtrl.text = _weightCtrl.text;

    // Load available stock
    final tid       = ref.read(appUserProvider).valueOrNull?.traderId;
    final productId = o?['product_id'] as String?;
    if (tid != null && productId != null) {
      try {
        final res = await Supabase.instance.client.rpc('get_available_stock',
            params: {'p_trader_id': tid, 'p_product_id': productId});
        // Also get kg
        final kgRes = await Supabase.instance.client
            .from('stock_ledger')
            .select('movement_type, quantity_kg')
            .eq('trader_id', tid)
            .eq('product_id', productId);
        double inKg  = 0, outKg = 0;
        for (final row in (kgRes as List)) {
          final mt = row['movement_type'] as String;
          final kg = (row['quantity_kg'] as num?)?.toDouble() ?? 0;
          if (['opening','purchased','returned_in','adjustment'].contains(mt)) inKg += kg;
          else if (['delivered','allocated','mortality','shrinkage'].contains(mt)) outKg += kg;
        }
        if (mounted) setState(() {
          _availBirds = (res as num?)?.toInt() ?? 0;
          _availKg    = inKg - outKg;
        });
      } catch (_) {}
    }
    setState(() {});
  }

  int    get _birds  => int.tryParse(_birdsCtrl.text.trim()) ?? 0;
  double get _weight => double.tryParse(_weightCtrl.text.trim()) ?? 0;

  // Stock status: -1=unknown, 0=exact/ok, 1=insufficient
  int get _stockStatus {
    if (_availBirds < 0) return 0; // no records — allow
    if (_birds > _availBirds) return 1; // insufficient
    return 0; // ok
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_weight <= 0) { showError(context, 'Enter delivered weight in kg'); return; }

    setState(() => _submitting = true);
    try {
      await Supabase.instance.client.rpc('complete_delivery', params: {
        'p_delivery_id':           widget.deliveryId,
        'p_birds_delivered':       _birds,
        'p_delivered_total_weight': _weight,
        'p_received_bird_count':   int.tryParse(_rcvBirdsCtrl.text),
        'p_received_total_weight': double.tryParse(_rcvWeightCtrl.text),
        'p_rejected_birds':        int.tryParse(_rejectedCtrl.text) ?? 0,
        'p_mortality_birds':       int.tryParse(_mortalityCtrl.text) ?? 0,
        'p_crates_dropped':        int.tryParse(_cratesGivenCtrl.text) ?? 0,
        'p_crates_collected':      int.tryParse(_cratesGotCtrl.text) ?? 0,
        'p_crates_returned':       int.tryParse(_cratesRetCtrl.text) ?? 0,
        'p_collected_amount':      double.tryParse(_cashCtrl.text) ?? 0,
        'p_payment_mode':          _payMode,
        'p_delivery_notes':        _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'p_returned_birds':        int.tryParse(_retBirdsCtrl.text) ?? 0,
        'p_returned_weight':       double.tryParse(_retWeightCtrl.text) ?? 0,
        'p_shrinkage_kg':          double.tryParse(_shrinkCtrl.text) ?? 0,
        'p_shrinkage_birds':       0,
      });
      if (mounted) { showSuccess(context, 'Delivery completed ✓'); context.go(R.agentDeliveries); }
    } catch (e) {
      if (mounted) {
        // Parse stock error into friendly message
        String msg = e.toString();
        final re = RegExp(r'Insufficient stock\. Available: (\d+) birds\. Required: (\d+) birds\.');
        final m  = re.firstMatch(msg);
        if (m != null) {
          final avail = m.group(1); final req = m.group(2);
          showDialog(context: context, builder: (_) => AlertDialog(
            title: const Row(children: [Icon(Icons.inventory_2_outlined, color: Colors.red, size: 22), SizedBox(width: 8), Text('Insufficient Stock')]),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              _infoRow('Available stock', '$avail birds', Colors.red),
              _infoRow('Required now',    '$req birds',   Colors.orange),
              _infoRow('Shortfall',       '${int.parse(req!) - int.parse(avail!)} birds', Colors.red),
              const SizedBox(height: 12),
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                child: const Text('Add a DC (farm pickup or shop collection) to increase available stock, then retry.', style: TextStyle(fontSize: 12, color: Colors.orange))),
            ]),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ));
        } else {
          showError(context, msg.replaceAll('Exception: ','').replaceAll('PostgrestException(message: ','').split(',').first);
        }
      }
    } finally { if (mounted) setState(() => _submitting = false); }
  }

  @override
  Widget build(BuildContext context) {
    final o = _delivery?['orders'] as Map<String,dynamic>?;
    final r = o?['retailers'] as Map<String,dynamic>?;
    return Scaffold(
      appBar: AppBar(title: Text(r?['shop_name'] as String? ?? 'Complete Delivery')),
      body: Form(key: _form, child: ListView(padding: const EdgeInsets.all(14), children: [

        // Shop info
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: const Border.fromBorderSide(BorderSide(color: kBorder))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r?['shop_name'] as String? ?? '—', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kPrimary)),
            if (r?['address'] != null) Text(r!['address'] as String, style: const TextStyle(fontSize: 11, color: kTextSub)),
            if (r?['phone']   != null) Row(children: [const Icon(Icons.phone_outlined, size: 12, color: kTextHint), const SizedBox(width: 4), Text(r!['phone'] as String, style: const TextStyle(fontSize: 11, color: kTextHint))]),
          ])),
        const SizedBox(height: 10),

        // Stock status banner
        if (_availBirds >= 0) Container(
          padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: _stockStatus == 1 ? Colors.red.shade50 : Colors.green.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _stockStatus == 1 ? Colors.red.shade200 : Colors.green.shade200)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(_stockStatus == 1 ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                  color: _stockStatus == 1 ? Colors.red : Colors.green, size: 18),
              const SizedBox(width: 8),
              Text(_stockStatus == 1 ? 'Insufficient Stock' : 'Stock Available',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13,
                      color: _stockStatus == 1 ? Colors.red : Colors.green.shade700)),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: _infoRow('Available', '$_availBirds birds', _stockStatus == 1 ? Colors.red : Colors.green)),
              Expanded(child: _infoRow('Required',  '$_birds birds',      _stockStatus == 1 ? Colors.orange : kPrimary)),
              if (_availKg > 0) Expanded(child: _infoRow('Avail Kg', '${_availKg.toStringAsFixed(0)} kg', Colors.blue)),
            ]),
            if (_stockStatus == 1) ...[
              const SizedBox(height: 8),
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(6)),
                child: const Text('Add a DC to record new pickup, then retry delivery.', style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w600))),
            ],
          ])),

        // Delivered
        const SectionHeader('DELIVERED QUANTITY'),
        Row(children: [
          Expanded(child: TextFormField(controller: _birdsCtrl, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Birds delivered'),
              onChanged: (_) => setState(() {}),
              validator: (v) => v == null || v.isEmpty ? 'Required' : null)),
          const SizedBox(width: 10),
          Expanded(child: TextFormField(controller: _weightCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Weight (kg) *'),
              validator: (v) { final n = double.tryParse(v ?? ''); return (n == null || n <= 0) ? 'Enter kg > 0' : null; })),
        ]),
        const SizedBox(height: 10),

        // Retailer confirmed
        const SectionHeader('RETAILER CONFIRMED'),
        Row(children: [
          Expanded(child: TextFormField(controller: _rcvBirdsCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Confirmed birds'))),
          const SizedBox(width: 10),
          Expanded(child: TextFormField(controller: _rcvWeightCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Confirmed kg'))),
        ]),
        const SizedBox(height: 10),

        // Losses
        const SectionHeader('LOSSES'),
        Row(children: [
          Expanded(child: TextFormField(controller: _mortalityCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Dead birds'))),
          const SizedBox(width: 8),
          Expanded(child: TextFormField(controller: _rejectedCtrl,  keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Rejected'))),
          const SizedBox(width: 8),
          Expanded(child: TextFormField(controller: _shrinkCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Shrinkage kg'))),
        ]),
        const SizedBox(height: 10),

        // Returns
        const SectionHeader('RETURNS TO VEHICLE'),
        Row(children: [
          Expanded(child: TextFormField(controller: _retBirdsCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Returned birds'))),
          const SizedBox(width: 10),
          Expanded(child: TextFormField(controller: _retWeightCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Returned kg'))),
        ]),
        const SizedBox(height: 10),

        // Crates
        const SectionHeader('CRATES'),
        Row(children: [
          Expanded(child: TextFormField(controller: _cratesGivenCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Given'))),
          const SizedBox(width: 8),
          Expanded(child: TextFormField(controller: _cratesGotCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Got back'))),
          const SizedBox(width: 8),
          Expanded(child: TextFormField(controller: _cratesRetCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Returned'))),
        ]),
        const SizedBox(height: 10),

        // Payment
        const SectionHeader('PAYMENT COLLECTED'),
        TextFormField(controller: _cashCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount (₹)', prefixText: '₹', prefixIcon: Icon(Icons.currency_rupee, size: 18))),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value:'cash',   label:Text('Cash')),
            ButtonSegment(value:'upi',    label:Text('UPI')),
            ButtonSegment(value:'credit', label:Text('Credit')),
          ],
          selected: {_payMode}, onSelectionChanged: (s) => setState(() => _payMode = s.first)),
        const SizedBox(height: 10),
        TextFormField(controller: _notesCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes (optional)', alignLabelWithHint: true)),
        const SizedBox(height: 20),

        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          style: ElevatedButton.styleFrom(
              backgroundColor: _stockStatus == 1 ? Colors.orange : kPrimary,
              minimumSize: const Size(double.infinity, 52)),
          child: _submitting
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Text(_stockStatus == 1 ? '⚠️  Mark Delivered (Low Stock)' : 'Mark as Delivered',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
        const SizedBox(height: 20),
      ])),
    );
  }

  Widget _infoRow(String l, String v, Color c) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(l, style: const TextStyle(fontSize: 10, color: kTextHint)),
      Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c)),
    ]));
}