import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class DeliveryCompleteScreen extends ConsumerStatefulWidget {
  const DeliveryCompleteScreen({super.key, required this.deliveryId});
  final String deliveryId;
  @override
  ConsumerState<DeliveryCompleteScreen> createState() => _State();
}

class _State extends ConsumerState<DeliveryCompleteScreen> {
  final _formKey        = GlobalKey<FormState>();
  final _birdsDelivered = TextEditingController();
  final _weightDelivered = TextEditingController();
  final _receivedBirds  = TextEditingController();
  final _receivedWeight = TextEditingController();
  final _rejected       = TextEditingController(text: '0');
  final _mortality      = TextEditingController(text: '0');
  final _cratesDropped  = TextEditingController(text: '0');
  final _cratesCollected = TextEditingController(text: '0');
  final _collected      = TextEditingController(text: '0');
  final _notes          = TextEditingController();
  String _paymentMode   = 'cash';
  bool _submitting = false;
  Map<String, dynamic>? _delivery;

  @override
  void initState() { super.initState(); _loadDelivery(); }

  @override
  void dispose() {
    for (final c in [_birdsDelivered, _weightDelivered, _receivedBirds, _receivedWeight, _rejected, _mortality, _cratesDropped, _cratesCollected, _collected, _notes]) c.dispose();
    super.dispose();
  }

  Future<void> _loadDelivery() async {
    final d = await Supabase.instance.client.from('deliveries')
        .select('*, orders(*, retailers(id,shop_name,owner_name))').eq('id', widget.deliveryId).maybeSingle();
    if (mounted) {
      setState(() => _delivery = d);
      if (d != null) {
        _birdsDelivered.text  = '${d['expected_bird_count'] ?? ''}';
        _weightDelivered.text = '${(d['expected_total_weight'] as num?)?.toStringAsFixed(2) ?? ''}';
        _receivedBirds.text   = _birdsDelivered.text;
        _receivedWeight.text  = _weightDelivered.text;
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await Supabase.instance.client.rpc('complete_delivery', params: {
        'p_delivery_id':            widget.deliveryId,
        'p_birds_delivered':        int.tryParse(_birdsDelivered.text) ?? 0,
        'p_delivered_total_weight': double.tryParse(_weightDelivered.text) ?? 0,
        'p_received_bird_count':    int.tryParse(_receivedBirds.text) ?? 0,
        'p_received_total_weight':  double.tryParse(_receivedWeight.text) ?? 0,
        'p_rejected_birds':         int.tryParse(_rejected.text) ?? 0,
        'p_mortality_birds':        int.tryParse(_mortality.text) ?? 0,
        'p_crates_dropped':         int.tryParse(_cratesDropped.text) ?? 0,
        'p_crates_collected':       int.tryParse(_cratesCollected.text) ?? 0,
        'p_collected_amount':       double.tryParse(_collected.text) ?? 0,
        'p_payment_mode':           _paymentMode,
        'p_delivery_notes':         _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      });
      if (mounted) { showSuccess(context, 'Delivery completed!'); context.go(Routes.agentDeliveries); }
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final retailer = (_delivery?['orders'] as Map?)?.entries.isEmpty == true ? null
        : (_delivery?['orders'] as Map?)?['retailers'] as Map<String, dynamic>?;

    return Scaffold(
      appBar: AppBar(title: Text('Complete Delivery${retailer != null ? ' — ${retailer['shop_name']}' : ''}')),
      body: Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (retailer != null) ...[
            Container(
              padding: const EdgeInsets.all(14), margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                  border: const Border.fromBorderSide(BorderSide(color: Color(0xFFEEEEEE)))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(retailer['shop_name'] as String, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                if (retailer['owner_name'] != null) Text(retailer['owner_name'] as String, style: const TextStyle(fontSize: 13, color: Color(0xFF9E9E9E))),
              ]),
            ),
          ],

          const SectionHeader('DELIVERED'),
          Row(children: [
            Expanded(child: TextFormField(controller: _birdsDelivered, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Birds delivered *'),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null)),
            const SizedBox(width: 12),
            Expanded(child: TextFormField(controller: _weightDelivered, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Weight (kg) *'),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextFormField(controller: _receivedBirds, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Received birds'))),
            const SizedBox(width: 12),
            Expanded(child: TextFormField(controller: _receivedWeight, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Received weight'))),
          ]),
          const SizedBox(height: 16),

          const SectionHeader('LOSSES'),
          Row(children: [
            Expanded(child: TextFormField(controller: _rejected, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Rejected birds'))),
            const SizedBox(width: 12),
            Expanded(child: TextFormField(controller: _mortality, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Mortality'))),
          ]),
          const SizedBox(height: 16),

          const SectionHeader('CRATES'),
          Row(children: [
            Expanded(child: TextFormField(controller: _cratesDropped, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Crates given'))),
            const SizedBox(width: 12),
            Expanded(child: TextFormField(controller: _cratesCollected, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Crates collected'))),
          ]),
          const SizedBox(height: 16),

          const SectionHeader('PAYMENT'),
          TextFormField(controller: _collected, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount collected (₹)', prefixIcon: Icon(Icons.currency_rupee, size: 18))),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'cash',   label: Text('Cash')),
              ButtonSegment(value: 'upi',    label: Text('UPI')),
              ButtonSegment(value: 'credit', label: Text('Credit')),
            ],
            selected: {_paymentMode},
            onSelectionChanged: (s) => setState(() => _paymentMode = s.first),
          ),
          const SizedBox(height: 16),
          TextFormField(controller: _notes, maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notes (optional)', alignLabelWithHint: true)),
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Mark as Delivered'),
          ),
        ]),
      ),
    );
  }
}
