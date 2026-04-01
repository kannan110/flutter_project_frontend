import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/dashboard_models.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class DeliveryCompleteScreen extends ConsumerStatefulWidget {
  const DeliveryCompleteScreen({super.key, required this.deliveryId});
  final String deliveryId;
  @override ConsumerState<DeliveryCompleteScreen> createState() => _S();
}

class _S extends ConsumerState<DeliveryCompleteScreen> {
  final _form          = GlobalKey<FormState>();
  final _birdsCtrl     = TextEditingController();
  final _weightCtrl    = TextEditingController();
  final _rcvBirdsCtrl  = TextEditingController();
  final _rcvWeightCtrl = TextEditingController();
  final _mortalityCtrl = TextEditingController(text: '0');
  final _rejectedCtrl  = TextEditingController(text: '0');
  final _returnBirdsCtrl = TextEditingController(text: '0');
  final _returnWtCtrl  = TextEditingController(text: '0');
  final _shrinkKgCtrl  = TextEditingController(text: '0');
  final _crateDropCtrl = TextEditingController(text: '0');
  final _crateBackCtrl = TextEditingController(text: '0');
  final _cashCtrl      = TextEditingController(text: '0');
  final _notesCtrl     = TextEditingController();

  String _payMode = 'cash';
  bool _submitting = false, _loaded = false;
  Map<String,dynamic>? _delivery;
  StockPosition? _stock;
  String _deliveryStatus = '';
  bool _hasOpenShift     = false;

  // DC totals for pre-fill
  int    _dcBirds  = 0;
  double _dcWeight = 0;

  @override void initState() { super.initState(); _load(); }
  @override void dispose() {
    for (final c in [_birdsCtrl, _weightCtrl, _rcvBirdsCtrl, _rcvWeightCtrl,
      _mortalityCtrl, _rejectedCtrl, _returnBirdsCtrl, _returnWtCtrl,
      _shrinkKgCtrl, _crateDropCtrl, _crateBackCtrl, _cashCtrl, _notesCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final user = ref.read(appUserProvider).valueOrNull;
    try {
      // FIX: load delivery + DC challans to get actual farm birds/weight
      final d = await Supabase.instance.client.from('deliveries')
          .select('*,'
                  'orders(id,estimated_birds,total_quantity,product_id,retailers(shop_name,address,phone)),'
                  'delivery_batches(id,delivery_challans(bird_count,net_weight,crates_count))')
          .eq('id', widget.deliveryId)
          .maybeSingle();

      if (!mounted) return;
      if (d == null) return;

      final o       = d['orders'] as Map<String,dynamic>?;
      final batch   = d['delivery_batches'] as Map<String,dynamic>?;
      final challans = (batch?['delivery_challans'] as List? ?? []).cast<Map<String,dynamic>>();

      // FIX: Sum DC birds/weight across all challans in the batch
      _dcBirds  = challans.fold(0,   (s, c) => s + ((c['bird_count']  as num?)?.toInt()    ?? 0));
      _dcWeight = challans.fold(0.0, (s, c) => s + ((c['net_weight']  as num?)?.toDouble() ?? 0));

      final orderBirds  = (o?['estimated_birds'] as num?)?.toInt()    ?? 0;
      final orderWeight = (o?['total_quantity']  as num?)?.toDouble() ?? 0;

      // FIX: pre-fill from DC actual data first, then order estimate as fallback
      final fillBirds  = _dcBirds  > 0 ? _dcBirds  : orderBirds;
      final fillWeight = _dcWeight > 0 ? _dcWeight  : orderWeight;

      _birdsCtrl.text     = fillBirds  > 0 ? '$fillBirds'                             : '';
      _weightCtrl.text    = fillWeight > 0 ? fillWeight.toStringAsFixed(2)             : '';
      _rcvBirdsCtrl.text  = fillBirds  > 0 ? '$fillBirds'                             : '';
      _rcvWeightCtrl.text = fillWeight > 0 ? fillWeight.toStringAsFixed(2)             : '';

      // Check if delivery is in correct status AND agent has open shift
      final dStatus = d['status'] as String? ?? '';
      bool openShift = false;
      try {
        final agentId = ref.read(appUserProvider).valueOrNull?.agentId;
        if (agentId != null) {
          final s = await Supabase.instance.client
              .from('delivery_shifts')
              .select('id')
              .eq('delivery_agent_id', agentId)
              .eq('status', 'open')
              .maybeSingle();
          openShift = s != null;
        }
      } catch (_) {}

      if (mounted) setState(() {
        _delivery       = d;
        _deliveryStatus = dStatus;
        _hasOpenShift   = openShift;
        _loaded         = true;
      });

      // Load live stock position
      final productId = o?['product_id'] as String?;
      if (user?.traderId != null && productId != null) {
        try {
          final stockRes = await Supabase.instance.client.rpc('get_available_stock', params: {
            'p_trader_id': user!.traderId,
            'p_product_id': productId,
          });
          if (!mounted) return;
          final list = (stockRes as List? ?? []);
          if (list.isNotEmpty && mounted) {
            setState(() => _stock = StockPosition.fromMap(list.first as Map<String,dynamic>));
          }
        } catch (_) {} // stock load is non-fatal
      }
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  int    get _deliveryBirds  => int.tryParse(_birdsCtrl.text)   ?? 0;
  double get _deliveryWeight => double.tryParse(_weightCtrl.text) ?? 0;
  bool   get _stockWarning   => _stock != null && _deliveryBirds > _stock!.availableBirds && _stock!.availableBirds > 0;
  bool   get _stockCritical  => _stock != null && _stock!.availableBirds <= 0;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final weight = double.tryParse(_weightCtrl.text.trim()) ?? 0;
    if (weight <= 0) { showError(context, 'Enter delivered weight'); return; }

    if (_stockCritical) {
      final ok = await confirmDialog(context,
          title: 'No Stock Available',
          message: 'Available stock: ${_stock?.availableBirds ?? 0} birds.\n'
                   'Delivery will be blocked unless admin has added stock.',
          confirmText: 'Proceed Anyway', confirmColor: Colors.orange);
      if (!ok || !mounted) return;
    } else if (_stockWarning) {
      final ok = await confirmDialog(context,
          title: 'Stock Warning',
          message: 'Available: ${_stock!.availableBirds} birds\n'
                   'Delivering: $_deliveryBirds birds\n\n'
                   'Continuing will reduce stock below zero.',
          confirmText: 'Proceed', confirmColor: Colors.orange);
      if (!ok || !mounted) return;
    }

    // Validate delivery is in correct state
    if (_deliveryStatus != 'out_for_delivery') {
      showError(context,
        'Delivery status is "$_deliveryStatus". '
        'Status must be "out_for_delivery" before completing.\n\n'
        'Please ask admin to check batch status.');
      return;
    }

    // Validate shift is open
    if (!_hasOpenShift) {
      showError(context,
        'No active shift found.\n\n'
        'You must have an open shift to complete deliveries. '
        'Please open a shift first.');
      return;
    }

    if (mounted) setState(() => _submitting = true);
    try {
      await Supabase.instance.client.rpc('complete_delivery', params: {
        'p_delivery_id':            widget.deliveryId,
        'p_birds_delivered':        _deliveryBirds,
        'p_delivered_total_weight': weight,
        'p_received_bird_count':    int.tryParse(_rcvBirdsCtrl.text),
        'p_received_total_weight':  double.tryParse(_rcvWeightCtrl.text),
        'p_rejected_birds':         int.tryParse(_rejectedCtrl.text)  ?? 0,
        'p_mortality_birds':        int.tryParse(_mortalityCtrl.text) ?? 0,
        'p_crates_dropped':         int.tryParse(_crateDropCtrl.text) ?? 0,
        'p_crates_collected':       int.tryParse(_crateBackCtrl.text) ?? 0,
        'p_crates_returned':        0,
        'p_collected_amount':       double.tryParse(_cashCtrl.text)   ?? 0,
        'p_payment_mode':           _payMode,
        'p_delivery_notes':         _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'p_returned_birds':         int.tryParse(_returnBirdsCtrl.text) ?? 0,
        'p_returned_weight':        double.tryParse(_returnWtCtrl.text) ?? 0,
        'p_shrinkage_kg':           double.tryParse(_shrinkKgCtrl.text) ?? 0,
        'p_shrinkage_birds':        0,
      });
      if (!mounted) return;
      showSuccess(context, 'Delivery completed ✓');
      context.go(R.agentDeliveries);
    } catch (e) {
      if (!mounted) return;
      showError(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Scaffold(body: LoadingList());
    final o = _delivery?['orders'] as Map<String,dynamic>?;
    final r = o?['retailers'] as Map<String,dynamic>?;

    // Show blocked screen if delivery not ready or no open shift
    final isReady = _deliveryStatus == 'out_for_delivery';
    final shopName = r?['shop_name'] as String? ?? 'Delivery';

    if (!isReady || !_hasOpenShift) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (context.canPop()) context.pop();
              else context.go(R.agentDeliveries);
            }),
          title: Text(shopName)),
        body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(!isReady ? Icons.pending_actions_outlined : Icons.schedule_outlined,
                size: 64, color: Colors.orange),
            const SizedBox(height: 16),
            Text(
              !isReady
                  ? 'Delivery Not Ready'
                  : 'No Active Shift',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              !isReady
                  ? 'Current status: "$_deliveryStatus"\n\n'
                    'Delivery must be "Out for Delivery" before completing.\n'
                    'Ask admin to check the batch status.'
                  : 'You must have an open shift to complete deliveries.\n\n'
                    'Open a shift first, then come back.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: kTextSub, height: 1.5)),
            const SizedBox(height: 24),
            if (!_hasOpenShift)
              ElevatedButton.icon(
                onPressed: () => context.go(R.shiftOpen),
                icon: const Icon(Icons.access_time),
                label: const Text('Open Shift')),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {
                if (context.canPop()) context.pop();
                else context.go(R.agentDeliveries);
              },
              child: const Text('← Back to Deliveries')),
          ],
        ))));
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) context.pop();
            else context.go(R.agentDeliveries);
          }),
        title: Text(r?['shop_name'] as String? ?? 'Complete Delivery')),
      body: Form(key: _form, child: ListView(padding: const EdgeInsets.all(16), children: [

        // Shop header
        if (r != null) Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kPrimary.withValues(alpha: 0.2))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r['shop_name'] as String,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: kPrimary)),
            if (r['address'] != null) ...[
              const SizedBox(height: 2),
              Text(r['address'] as String, style: const TextStyle(fontSize: 11, color: kTextSub)),
            ],
            if (r['phone'] != null) ...[
              const SizedBox(height: 2),
              Text(r['phone'] as String, style: const TextStyle(fontSize: 11, color: kTextHint)),
            ],
          ])),

        // FIX: DC source info banner — shows what was loaded from farm
        if (_dcBirds > 0 || _dcWeight > 0) Container(
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.shade200)),
          child: Row(children: [
            const Icon(Icons.receipt_long_outlined, color: Colors.blue, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'From DC: $_dcBirds birds · ${_dcWeight.toStringAsFixed(1)} kg loaded from farm',
              style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.w600))),
          ])),

        // Stock banner
        _stockBanner(),

        // ── DELIVERED ─────────────────────────────────────────────
        const SectionHeader('DELIVERED TO SHOP'),
        Row(children: [
          Expanded(child: TextFormField(
            controller: _birdsCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Birds *', suffixText: 'birds'),
            onChanged: (_) { if (mounted) setState(() {}); },
            validator: (v) => v!.isEmpty ? 'Required' : null)),
          const SizedBox(width: 12),
          Expanded(child: TextFormField(
            controller: _weightCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Weight (kg) *', suffixText: 'kg'),
            validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0 ? 'Enter weight' : null)),
        ]),

        // FIX: Live amount preview when rate is known
        if (_deliveryWeight > 0) Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Text(
            'Delivering: $_deliveryBirds birds · ${_deliveryWeight.toStringAsFixed(2)} kg',
            style: const TextStyle(fontSize: 12, color: kPrimary, fontWeight: FontWeight.w600))),

        const SizedBox(height: 12),

        // ── RETAILER CONFIRMED ────────────────────────────────────
        const SectionHeader('RETAILER CONFIRMED (received)'),
        Row(children: [
          Expanded(child: TextFormField(
            controller: _rcvBirdsCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Birds confirmed'))),
          const SizedBox(width: 12),
          Expanded(child: TextFormField(
            controller: _rcvWeightCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Weight confirmed (kg)'))),
        ]),
        const SizedBox(height: 12),

        // ── LOSSES ────────────────────────────────────────────────
        const SectionHeader('LOSSES (if any)'),
        Row(children: [
          Expanded(child: TextFormField(
            controller: _mortalityCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Dead birds', suffixText: 'birds'))),
          const SizedBox(width: 8),
          Expanded(child: TextFormField(
            controller: _rejectedCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Rejected birds'))),
          const SizedBox(width: 8),
          Expanded(child: TextFormField(
            controller: _shrinkKgCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Shrinkage (kg)', suffixText: 'kg'))),
        ]),
        const SizedBox(height: 12),

        // ── RETURNS ───────────────────────────────────────────────
        const SectionHeader('RETURNED TO STOCK (unsold)'),
        Row(children: [
          Expanded(child: TextFormField(
            controller: _returnBirdsCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Return birds'))),
          const SizedBox(width: 12),
          Expanded(child: TextFormField(
            controller: _returnWtCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Return weight (kg)'))),
        ]),
        const SizedBox(height: 12),

        // ── CRATES ────────────────────────────────────────────────
        const SectionHeader('CRATES'),
        Row(children: [
          Expanded(child: TextFormField(
            controller: _crateDropCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Given'))),
          const SizedBox(width: 12),
          Expanded(child: TextFormField(
            controller: _crateBackCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Received back'))),
        ]),
        const SizedBox(height: 12),

        // ── PAYMENT ───────────────────────────────────────────────
        const SectionHeader('CASH COLLECTION'),
        TextFormField(
          controller: _cashCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
              labelText: 'Amount Collected (₹)', prefixText: '₹')),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'cash',   label: Text('Cash')),
            ButtonSegment(value: 'upi',    label: Text('UPI')),
            ButtonSegment(value: 'credit', label: Text('Credit')),
            ButtonSegment(value: 'bank',   label: Text('Bank')),
          ],
          selected: {_payMode},
          onSelectionChanged: (s) => setState(() => _payMode = s.first)),
        const SizedBox(height: 12),

        TextFormField(
          controller: _notesCtrl,
          maxLines: 2,
          decoration: const InputDecoration(
              labelText: 'Notes (optional)', alignLabelWithHint: true)),
        const SizedBox(height: 24),

        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          style: _stockWarning
              ? ElevatedButton.styleFrom(backgroundColor: Colors.orange)
              : null,
          child: _submitting
              ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Text(
                  _stockWarning ? '⚠  Mark Delivered (Low Stock)' : 'Mark as Delivered',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
        const SizedBox(height: 20),
      ])),
    );
  }

  Widget _stockBanner() {
    if (_stock == null) return const SizedBox.shrink();
    final avail = _stock!.availableBirds;
    final over  = _deliveryBirds > avail && avail > 0;
    final zero  = avail <= 0;
    Color c = zero ? Colors.red : over ? Colors.orange : Colors.green;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.withValues(alpha: 0.3))),
      child: Row(children: [
        Icon(zero ? Icons.error : over ? Icons.inventory_outlined : Icons.check_circle_outline,
            color: c, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(
          zero
              ? 'No stock available! Ask admin to add a DC/purchase.'
              : over
                  ? 'Stock: $avail birds available · Delivering: $_deliveryBirds birds'
                  : 'Stock OK: $avail birds available ✓',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c))),
      ]));
  }
}
