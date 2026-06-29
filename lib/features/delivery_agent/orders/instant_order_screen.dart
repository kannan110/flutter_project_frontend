import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Instant Order Screen — Delivery Agent
//
// Business rules:
//   • Retailer   — required
//   • Product    — required
//   • Weight     — required (mandatory)
//   • Bird Count — optional
//   • Remarks    — optional
//
// Pricing is HIDDEN from the agent entirely.
//   • No rate field, no total, no pricing source shown to agent.
//   • p_rate_per_kg is NOT sent to the RPC (defaults to NULL in DB).
//   • order_items row is created with rate_per_kg = NULL.
//   • Selling rate resolved at Trader Approval via get_effective_rate_v4.
//   • Trader sees resolved rate, pricing source, and invoice amount as usual.
// ─────────────────────────────────────────────────────────────────────────────

class InstantOrderScreen extends ConsumerStatefulWidget {
  const InstantOrderScreen({super.key});
  @override ConsumerState<InstantOrderScreen> createState() => _S();
}

class _S extends ConsumerState<InstantOrderScreen> {
  final _c           = Supabase.instance.client;
  final _weightCtrl  = TextEditingController();
  final _birdsCtrl   = TextEditingController();
  final _notesCtrl   = TextEditingController();

  bool _loading    = true;
  bool _submitting = false;
  bool _hasShift   = false;

  List<Map<String,dynamic>> _retailers = [];
  List<Map<String,dynamic>> _products  = [];
  Map<String,dynamic>? _selRetailer;
  Map<String,dynamic>? _selProduct;
  String _payMode = 'cash';
  String? _err;

  @override void initState() { super.initState(); _load(); }

  @override void dispose() {
    _weightCtrl.dispose();
    _birdsCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final user     = ref.read(appUserProvider).valueOrNull;
    final agentId  = user?.agentId;
    final traderId = user?.traderId;
    if (agentId == null || traderId == null) {
      if (mounted) setState(() { _loading = false; _hasShift = false; });
      return;
    }
    try {
      final shift = await _c.from('delivery_shifts')
          .select('id')
          .eq('delivery_agent_id', agentId)
          .eq('status', 'open')
          .maybeSingle();
      if (shift == null) {
        if (mounted) setState(() { _loading = false; _hasShift = false; });
        return;
      }
      final results = await Future.wait([
        _c.from('retailers')
            .select('id,shop_name,phone,address')
            .eq('trader_id', traderId)
            .eq('is_active', true)
            .order('shop_name'),
        _c.from('master_products')
            .select('id,name,unit')
            .eq('is_active', true)
            .order('name'),
      ]);
      if (!mounted) return;
      setState(() {
        _hasShift  = true;
        _retailers = List<Map<String,dynamic>>.from(results[0] as List? ?? []);
        _products  = List<Map<String,dynamic>>.from(results[1] as List? ?? []);
        _loading   = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _hasShift = false; });
    }
  }

  double get _weight => double.tryParse(_weightCtrl.text.trim()) ?? 0;
  int    get _birds  => int.tryParse(_birdsCtrl.text.trim())     ?? 0;

  Future<void> _submit() async {
    setState(() => _err = null);

    if (_selRetailer == null) { setState(() => _err = 'Select a retailer'); return; }
    if (_selProduct  == null) { setState(() => _err = 'Select a product');  return; }
    if (_weight <= 0)         { setState(() => _err = 'Enter weight (kg)'); return; }

    final agentId = ref.read(appUserProvider).valueOrNull?.agentId;
    if (agentId == null) return;

    final birdsLine = _birds > 0 ? 'Birds: $_birds\n' : '';
    final ok = await confirmDialog(context,
        title: 'Create Instant Order',
        message: 'Retailer: ${_selRetailer!['shop_name']}\n'
            'Product: ${_selProduct!['name']}\n'
            '${birdsLine}'
            'Weight: ${_weight.toStringAsFixed(2)} kg\n'
            'Payment: $_payMode\n\n'
            'Rate will be set by trader at approval.',
        confirmText: 'Create & Deliver',
        confirmColor: kPrimary);
    if (!ok || !mounted) return;

    if (mounted) setState(() => _submitting = true);
    try {
      // p_rate_per_kg intentionally omitted — defaults to NULL in DB.
      // order_items created with rate_per_kg=NULL (same as normal orders).
      // approve_delivery_and_order resolves zone rate via get_effective_rate_v4.
      final res = await _c.rpc('agent_create_instant_order', params: {
        'p_agent_id':     agentId,
        'p_retailer_id':  _selRetailer!['id'],
        'p_product_id':   _selProduct!['id'],
        'p_birds':        _birds > 0 ? _birds : null,  // null = weight-only, DB treats as 0
        'p_weight_kg':    _weight,
        'p_payment_mode': _payMode,
        'p_notes': _notesCtrl.text.trim().isEmpty
            ? null
            : _notesCtrl.text.trim(),
      });
      if (!mounted) return;

      final result     = res as Map<String,dynamic>;
      final deliveryId = result['delivery_id'] as String?;
      final birdsMsg   = _birds > 0 ? ' · $_birds birds' : '';

      showSuccess(context,
          'Instant order created!\n'
              '${result['retailer_name']}$birdsMsg · ${_weight.toStringAsFixed(2)} kg');

      if (deliveryId != null && mounted) {
        context.push(R.deliveryDonePath(deliveryId));
      } else {
        if (context.canPop()) context.pop();
        else context.go(R.agentDeliveries);
      }
    } catch (e) {
      if (mounted) setState(() {
        _err = e.toString()
            .replaceAll('Exception: ', '')
            .replaceAll('PostgrestException(message: ', '')
            .replaceAll(')', '');
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
          backgroundColor: const Color(0xFFEA580C),
          foregroundColor: Colors.white,
          leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                if (context.canPop()) context.pop();
                else context.go(R.agentHome);
              }),
          title: const Text('Instant Order'),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          ]),
      body: _loading
          ? const LoadingList()
          : !_hasShift
          ? _buildNoShift()
          : _buildForm());

  Widget _buildNoShift() => Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.lock_clock_outlined, size: 64, color: kTextHint),
        const SizedBox(height: 16),
        const Text('Shift Required',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('Open a shift first before creating instant orders.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: kTextSub)),
        const SizedBox(height: 24),
        ElevatedButton.icon(
            onPressed: () => context.go(R.shiftOpen),
            icon: const Icon(Icons.schedule),
            label: const Text('Open Shift')),
        const SizedBox(height: 12),
        OutlinedButton(
            onPressed: () {
              if (context.canPop()) context.pop();
              else context.go(R.agentHome);
            },
            child: const Text('Back to Home')),
      ])));

  Widget _buildForm() => ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [

        // ── Shift banner ──────────────────────────────────────────────────────────
        Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(kRadiusCard),
                border: Border.all(color: kPrimary.withValues(alpha: 0.2))),
            child: Row(children: [
              const Icon(Icons.electric_bolt, color: kPrimary, size: 20),
              const SizedBox(width: 10),
              const Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Instant Order Mode',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: kPrimary,
                            fontSize: 13)),
                    Text('Rate will be confirmed by trader at approval.',
                        style: TextStyle(fontSize: 11, color: kTextSub)),
                  ])),
              Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(6)),
                  child: const Text('Shift Active',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700))),
            ])),

        // ── Error ─────────────────────────────────────────────────────────────────
        if (_err != null) Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(kRadiusCard),
                border: Border.all(color: Colors.red.shade200)),
            child: Row(children: [
              const Icon(Icons.error_outline, color: kError, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(_err!,
                  style: const TextStyle(color: kError, fontSize: 13))),
            ])),

        // ── Retailer ──────────────────────────────────────────────────────────────
        const SectionHeader('SELECT RETAILER *'),
        _retailers.isEmpty
            ? Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10)),
            child: const Text(
                'No retailers found. Ask admin to add retailers.',
                style: TextStyle(color: Colors.deepOrange)))
            : SearchableRetailerPicker(
            items: _retailers,
            labelKey: 'shop_name',
            subKey: 'phone',
            hint: 'Choose retailer / shop',
            sheetTitle: 'Select Retailer',
            prefixIcon: const Icon(Icons.store_outlined,
                size: 18, color: kPrimary),
            value: _selRetailer,
            onChanged: (v) => setState(() => _selRetailer = v)),

        if (_selRetailer?['address'] != null) Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              const Icon(Icons.location_on_outlined, size: 12, color: kTextSub),
              const SizedBox(width: 4),
              Expanded(child: Text(_selRetailer!['address'] as String,
                  style: const TextStyle(fontSize: 11, color: kTextSub))),
            ])),
        const SizedBox(height: 16),

        // ── Product ───────────────────────────────────────────────────────────────
        const SectionHeader('PRODUCT *'),
        if (_products.isNotEmpty)
          DropdownButtonFormField<Map<String,dynamic>>(
              value: _selProduct,
              isExpanded: true,
              decoration: const InputDecoration(
                  hintText: 'Select product',
                  prefixIcon: Icon(Icons.egg_alt_outlined,
                      size: 18, color: kPrimary)),
              items: [
                const DropdownMenuItem(
                    value: null,
                    child: Text('Select product',
                        style: TextStyle(color: kTextHint))),
                ..._products.map((p) => DropdownMenuItem(
                    value: p,
                    child: Text(p['name'] as String,
                        style: const TextStyle(fontSize: 13)))),
              ],
              onChanged: (v) => setState(() => _selProduct = v)),
        const SizedBox(height: 16),

        // ── Quantity ──────────────────────────────────────────────────────────────
        const SectionHeader('QUANTITY'),
        Row(children: [
          // Weight — mandatory
          Expanded(child: TextField(
              controller: _weightCtrl,
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  labelText: 'Weight (kg) *',
                  suffixText: 'kg',
                  prefixIcon: Icon(Icons.scale_outlined,
                      size: 18, color: kPrimary)))),
          const SizedBox(width: 12),
          // Bird count — optional
          Expanded(child: TextField(
              controller: _birdsCtrl,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  labelText: 'Bird Count',
                  suffixText: 'birds',
                  hintText: 'Optional',
                  prefixIcon: Icon(Icons.numbers,
                      size: 18, color: kPrimary)))),
        ]),
        if (_birds > 0 && _weight > 0) Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                'Avg: ${(_weight / _birds * 1000).toStringAsFixed(0)} g/bird',
                style: const TextStyle(fontSize: 11, color: kTextSub))),
        const SizedBox(height: 16),

        // ── Payment Mode ──────────────────────────────────────────────────────────
        const SectionHeader('PAYMENT MODE'),
        SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'cash',   label: Text('Cash')),
              ButtonSegment(value: 'upi',    label: Text('UPI')),
              ButtonSegment(value: 'credit', label: Text('Credit')),
              ButtonSegment(value: 'bank',   label: Text('Bank')),
            ],
            selected: {_payMode},
            onSelectionChanged: (s) =>
                setState(() => _payMode = s.first)),
        const SizedBox(height: 16),

        // ── Remarks ───────────────────────────────────────────────────────────────
        TextField(
            controller: _notesCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'Remarks (optional)',
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.notes_outlined,
                    size: 18, color: kPrimary))),
        const SizedBox(height: 24),

        // ── Order Summary — no pricing shown ──────────────────────────────────────
        if (_selRetailer != null && _weight > 0) Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(kRadiusCard),
                border: Border.all(color: Colors.green.shade300)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.receipt_long_outlined,
                        size: 16, color: Colors.green),
                    SizedBox(width: 6),
                    Text('Order Summary',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.green,
                            fontSize: 13)),
                  ]),
                  const SizedBox(height: 10),
                  _row('Retailer', _selRetailer!['shop_name'] as String),
                  if (_selProduct != null)
                    _row('Product', _selProduct!['name'] as String),
                  _row('Weight', '${_weight.toStringAsFixed(2)} kg'),
                  if (_birds > 0) _row('Birds', '$_birds birds'),
                  _row('Payment', _payMode),
                  _row('Assigned to', 'You (instant)'),
                  // Rate intentionally omitted — resolved by trader at approval
                ])),

        // ── Submit ────────────────────────────────────────────────────────────────
        ElevatedButton.icon(
            onPressed:
            (_submitting || _selRetailer == null || _selProduct == null)
                ? null
                : _submit,
            style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 54),
                backgroundColor: kPrimary),
            icon: _submitting
                ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white))
                : const Icon(Icons.electric_bolt, size: 20),
            label: Text(
                _submitting ? 'Creating...' : 'Create & Go to Delivery',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800))),
        const SizedBox(height: 20),
      ]);

  Widget _row(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        SizedBox(width: 90,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, color: kTextSub))),
        Expanded(child: Text(value,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700))),
      ]));
}