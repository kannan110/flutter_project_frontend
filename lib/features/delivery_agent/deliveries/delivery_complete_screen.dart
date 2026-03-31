import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
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
  final _form = GlobalKey<FormState>();
  // deliveries columns: birds_delivered, delivered_total_weight, received_bird_count, received_total_weight
  // mortality_birds, rejected_birds, returned_birds, returned_weight, shrinkage_kg, shrinkage_birds
  // crates_dropped, crates_collected, crates_returned, collected_amount, payment_mode, delivery_notes
  final _birdsDelivered = TextEditingController(); final _weightDelivered = TextEditingController();
  final _receivedBirds = TextEditingController(); final _receivedWeight = TextEditingController();
  final _mortality = TextEditingController(text: '0'); final _rejected = TextEditingController(text: '0');
  final _returnedBirds = TextEditingController(text: '0'); final _returnedWeight = TextEditingController(text: '0');
  final _shrinkageKg = TextEditingController(text: '0');
  final _cratesDropped = TextEditingController(text: '0'); final _cratesCollected = TextEditingController(text: '0'); final _cratesReturned = TextEditingController(text: '0');
  final _collected = TextEditingController(text: '0'); final _notes = TextEditingController();
  String _payMode = 'cash'; bool _submitting = false;
  Map<String,dynamic>? _delivery;

  @override void initState() { super.initState(); _load(); }
  @override void dispose() { for (final c in [_birdsDelivered,_weightDelivered,_receivedBirds,_receivedWeight,_mortality,_rejected,_returnedBirds,_returnedWeight,_shrinkageKg,_cratesDropped,_cratesCollected,_cratesReturned,_collected,_notes]) c.dispose(); super.dispose(); }

  Future<void> _load() async {
    // deliveries: expected_bird_count, expected_total_weight
    final d = await Supabase.instance.client.from('deliveries').select('*,orders(estimated_birds,expected_total_weight,retailers(shop_name,address))').eq('id', widget.deliveryId).maybeSingle();
    if (mounted) {
      setState(() => _delivery = d);
      if (d != null) {
        final o = d['orders'] as Map<String,dynamic>?;
        _birdsDelivered.text = '${d['expected_bird_count'] ?? o?['estimated_birds'] ?? ''}';
        _weightDelivered.text = '${(d['expected_total_weight'] as num?)?.toStringAsFixed(2) ?? ''}';
        _receivedBirds.text = _birdsDelivered.text;
        _receivedWeight.text = _weightDelivered.text;
      }
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final birds = int.tryParse(_birdsDelivered.text) ?? 0;
    final weight = double.tryParse(_weightDelivered.text) ?? 0;
    if (weight <= 0) { showError(context, 'Enter delivered weight'); return; }
    setState(() => _submitting = true);
    try {
      // complete_delivery — 17 params, all with correct names:
      // p_delivery_id, p_birds_delivered, p_delivered_total_weight, p_received_bird_count,
      // p_received_total_weight, p_rejected_birds, p_mortality_birds, p_crates_dropped,
      // p_crates_collected, p_crates_returned, p_collected_amount, p_payment_mode,
      // p_delivery_notes, p_returned_birds, p_returned_weight, p_shrinkage_kg, p_shrinkage_birds
      await Supabase.instance.client.rpc('complete_delivery', params: {
        'p_delivery_id': widget.deliveryId,
        'p_birds_delivered': birds,
        'p_delivered_total_weight': weight,
        'p_received_bird_count': int.tryParse(_receivedBirds.text),
        'p_received_total_weight': double.tryParse(_receivedWeight.text),
        'p_rejected_birds': int.tryParse(_rejected.text) ?? 0,
        'p_mortality_birds': int.tryParse(_mortality.text) ?? 0,
        'p_crates_dropped': int.tryParse(_cratesDropped.text) ?? 0,
        'p_crates_collected': int.tryParse(_cratesCollected.text) ?? 0,
        'p_crates_returned': int.tryParse(_cratesReturned.text) ?? 0,
        'p_collected_amount': double.tryParse(_collected.text) ?? 0,
        'p_payment_mode': _payMode,
        'p_delivery_notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'p_returned_birds': int.tryParse(_returnedBirds.text) ?? 0,
        'p_returned_weight': double.tryParse(_returnedWeight.text) ?? 0,
        'p_shrinkage_kg': double.tryParse(_shrinkageKg.text) ?? 0,
        'p_shrinkage_birds': 0,
      });
      if (mounted) { showSuccess(context, 'Delivery completed ✓'); context.go(R.agentDeliveries); }
    } catch (e) { if (mounted) showError(context, e.toString()); }
    finally { if (mounted) setState(() => _submitting = false); }
  }

  @override
  Widget build(BuildContext context) {
    final o = _delivery?['orders'] as Map<String,dynamic>?; final r = o?['retailers'] as Map<String,dynamic>?;
    return Scaffold(
      appBar: AppBar(title: Text(r?['shop_name'] as String? ?? 'Complete Delivery')),
      body: Form(key: _form, child: ListView(padding: const EdgeInsets.all(16), children: [
        if (r != null) Container(padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 14), decoration: BoxDecoration(color: kPrimary.withOpacity(0.07), borderRadius: BorderRadius.circular(12), border: Border.all(color: kPrimary.withOpacity(0.2))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(r['shop_name'] as String, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kPrimary)), if (r['address'] != null) Text(r['address'] as String, style: const TextStyle(fontSize: 11, color: kTextSub))])),

        const SectionHeader('DELIVERED'),
        Row(children: [Expanded(child: TextFormField(controller: _birdsDelivered, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Birds *'), validator: (v) => v!.isEmpty ? 'Required' : null)), const SizedBox(width: 12), Expanded(child: TextFormField(controller: _weightDelivered, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Weight (kg) *'), validator: (v) => (double.tryParse(v??'')??0) <= 0 ? '> 0' : null))]),
        const SizedBox(height: 12),
        const SectionHeader('RECEIVED BY RETAILER'),
        Row(children: [Expanded(child: TextFormField(controller: _receivedBirds, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Birds'))), const SizedBox(width: 12), Expanded(child: TextFormField(controller: _receivedWeight, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Weight (kg)')))]),
        const SizedBox(height: 12),
        const SectionHeader('LOSSES'),
        Row(children: [Expanded(child: TextFormField(controller: _mortality, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Mortality'))), const SizedBox(width: 12), Expanded(child: TextFormField(controller: _rejected, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Rejected')))]),
        const SizedBox(height: 10),
        TextFormField(controller: _shrinkageKg, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Shrinkage (kg)', helperText: 'Weight lost in transit')),
        const SizedBox(height: 12),
        const SectionHeader('RETURNS'),
        Row(children: [Expanded(child: TextFormField(controller: _returnedBirds, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Returned birds'))), const SizedBox(width: 12), Expanded(child: TextFormField(controller: _returnedWeight, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Returned wt (kg)')))]),
        const SizedBox(height: 12),
        const SectionHeader('CRATES'),
        Row(children: [Expanded(child: TextFormField(controller: _cratesDropped, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Given'))), const SizedBox(width: 8), Expanded(child: TextFormField(controller: _cratesCollected, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Got back'))), const SizedBox(width: 8), Expanded(child: TextFormField(controller: _cratesReturned, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Returned')))]),
        const SizedBox(height: 12),
        const SectionHeader('PAYMENT'),
        TextFormField(controller: _collected, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount Collected (₹)', prefixText: '₹')),
        const SizedBox(height: 10),
        // payment_mode CHECK: cash, upi, bank, credit, adjustment
        SegmentedButton<String>(
          segments: const [ButtonSegment(value:'cash',label:Text('Cash')), ButtonSegment(value:'upi',label:Text('UPI')), ButtonSegment(value:'credit',label:Text('Credit'))],
          selected: {_payMode}, onSelectionChanged: (s) => setState(() => _payMode = s.first)),
        const SizedBox(height: 12),
        TextFormField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes (optional)', alignLabelWithHint: true)),
        const SizedBox(height: 24),
        ElevatedButton(onPressed: _submitting ? null : _submit,
          child: _submitting ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Mark as Delivered')),
      ])),
    );
  }
}
