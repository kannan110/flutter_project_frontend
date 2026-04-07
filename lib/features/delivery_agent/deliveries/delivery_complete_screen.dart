import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/dashboard_models.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../weighment/weighment_screen.dart';

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
  bool   _hasOpenShift   = false;

  // DC / loss data
  int    _dcBirds        = 0;
  double _dcWeight       = 0;
  double _avgBirdWeightG = 0; // grams per bird (from DC or weighment)
  String _weighmentSource = 'manual';  // 'manual' | 'bluetooth' | 'weighment_app'
  bool   _weighmentDone  = false;

  // FIX: declare the two missing fields
  int    _orderBirds       = 0;
  double _orderWeight      = 0;

  // Image proofs
  File? _mortalityImage;
  File? _deliveryImage;
  bool  _uploadingMortality = false;
  bool  _uploadingDelivery  = false;
  String? _mortalityProofUrl;
  String? _deliveryProofUrl;

  final _picker = ImagePicker();

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
      // FIX: fetch delivery without broken nested delivery_batches->delivery_challans
      final d = await Supabase.instance.client.from('deliveries')
          .select('*,'
                  'orders(id,estimated_birds,total_quantity,product_id,retailers(shop_name,address,phone))')
          .eq('id', widget.deliveryId)
          .maybeSingle();

      if (!mounted || d == null) return;

      final o = d['orders'] as Map<String,dynamic>?;

      // FIX: fetch challans separately using batch_id (avoids PostgREST nested FK issue)
      List<Map<String,dynamic>> challans = [];
      final batchId = d['batch_id'] as String?;
      if (batchId != null) {
        try {
          final chRes = await Supabase.instance.client.from('delivery_challans')
              .select('bird_count,net_weight,crates_count,avg_bird_weight')
              .eq('batch_id', batchId);
          challans = List<Map<String,dynamic>>.from(chRes as List? ?? []);
        } catch (_) {}
      }

      // DC totals are for the WHOLE batch — shown as info only, not pre-filled into delivery
      _dcBirds  = challans.fold(0,   (s, c) => s + ((c['bird_count']  as num?)?.toInt()    ?? 0));
      _dcWeight = challans.fold(0.0, (s, c) => s + ((c['net_weight']  as num?)?.toDouble() ?? 0));

      // Avg bird weight from DC (grams per bird)
      if (_dcBirds > 0 && _dcWeight > 0) {
        _avgBirdWeightG = (_dcWeight / _dcBirds) * 1000;
      } else if (challans.isNotEmpty) {
        final firstAvg = (challans.first['avg_bird_weight'] as num?)?.toDouble() ?? 0;
        _avgBirdWeightG = firstAvg * 1000;
      }

      // Pre-fill delivery fields from THIS ORDER specifically (not DC batch total)
      // Each retailer gets their own ordered quantity — not the whole DC
      final orderBirds  = (o?['estimated_birds'] as num?)?.toInt()    ?? 0;
      final orderWeight = (o?['total_quantity']  as num?)?.toDouble() ?? 0;

      // Delivered = order's quantity (what was allocated to this retailer)
      // Agent corrects it based on actual weighment at shop
      _orderBirds  = orderBirds;
      _orderWeight = orderWeight;
      // Intentionally leave delivery fields empty — agent enters actual at-shop values
      // DC weight is shown as reference; order expected is shown as hint

      // Check shift
      final dStatus = d['status'] as String? ?? '';
      bool openShift = false;
      try {
        final agentId = user?.agentId;
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

      // Load stock position
      final productId = o?['product_id'] as String?;
      if (user?.traderId != null && productId != null) {
        try {
          final stockRes = await Supabase.instance.client.rpc('get_available_stock', params: {
            'p_trader_id': user!.traderId, 'p_product_id': productId,
          });
          if (!mounted) return;
          final list = (stockRes as List? ?? []);
          if (list.isNotEmpty && mounted) {
            setState(() => _stock = StockPosition.fromMap(list.first as Map<String,dynamic>));
          }
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  // ── Image picking ───────────────────────────────────────────────
  Future<void> _pickImage(bool isMortality) async {
    try {
      final picked = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 70,
          maxWidth: 1200);
      if (picked == null) return;
      final file = File(picked.path);
      if (mounted) setState(() {
        if (isMortality) { _mortalityImage = file; _uploadingMortality = true; }
        else             { _deliveryImage  = file; _uploadingDelivery  = true; }
      });
      try {
        final bucket  = isMortality ? 'delivery-proofs' : 'delivery-proofs';
        final path    = '${isMortality ? 'mortality' : 'delivery'}/${DateTime.now().millisecondsSinceEpoch}.jpg';
        await Supabase.instance.client.storage.from(bucket).upload(path, file);
        final url = Supabase.instance.client.storage.from(bucket).getPublicUrl(path);
        if (mounted) setState(() {
          if (isMortality) { _mortalityProofUrl = url; _uploadingMortality = false; }
          else             { _deliveryProofUrl  = url; _uploadingDelivery  = false; }
        });
      } catch (e) {
        if (mounted) setState(() {
          if (isMortality) _uploadingMortality = false;
          else             _uploadingDelivery  = false;
        });
        if (mounted) showError(context, 'Upload failed: ${e.toString().replaceAll('Exception: ', '')}');
      }
    } catch (_) {}
  }

  // ── Launch weighment screen ─────────────────────────────────
  Future<void> _launchWeighment() async {
    final o = _delivery?['orders'] as Map<String,dynamic>?;
    final r = o?['retailers'] as Map<String,dynamic>?;
    await Navigator.push(context, MaterialPageRoute(builder: (_) =>
      WeighmentScreen(
        deliveryId:      widget.deliveryId,
        shopName:        r?['shop_name'] as String? ?? 'Delivery',
        expectedBirds:   _dcBirds > 0 ? _dcBirds : ((o?['estimated_birds'] as num?)?.toInt() ?? 0),
        expectedWeight:  _dcWeight > 0 ? _dcWeight : ((o?['total_quantity'] as num?)?.toDouble() ?? 0),
        onComplete: (result) {
          // Pre-fill delivery complete form with weighment data
          _birdsCtrl.text     = '${result.totalBirds}';
          _weightCtrl.text    = result.totalNetWt.toStringAsFixed(3);
          _rcvBirdsCtrl.text  = '${result.totalBirds}';
          _rcvWeightCtrl.text = result.totalNetWt.toStringAsFixed(3);
          _avgBirdWeightG     = result.avgBirdWtG;
          _weighmentSource    = result.source;
          _weighmentDone      = true;
          Navigator.pop(context); // close weighment, return to this screen
          if (mounted) setState(() {});
          showSuccess(context,
            '✓ Weight loaded: ${result.totalNetWt.toStringAsFixed(2)} kg · '
            '${result.avgBirdWtG.toStringAsFixed(1)}g/bird · '
            '${result.source == 'bluetooth' ? '🔵 Bluetooth' : '✏️ Manual'}');
        },
      )));
  }

  // ── Live loss calculations ───────────────────────────────────────
  int    get _deliveryBirds    => int.tryParse(_birdsCtrl.text)     ?? 0;
  double get _deliveryWeight   => double.tryParse(_weightCtrl.text) ?? 0;
  // Order-level expected weight (from order.total_quantity) — correct basis for loss calc
  double get _orderExpectedWt  => (_delivery?['orders']?['total_quantity'] as num?)?.toDouble() ?? 0;
  int    get _mortalityBirds  => int.tryParse(_mortalityCtrl.text) ?? 0;
  double get _mortalityWtKg   => _avgBirdWeightG > 0
      ? (_mortalityBirds * _avgBirdWeightG / 1000)
      : (double.tryParse(_shrinkKgCtrl.text) ?? 0);
  // Transport loss = ORDER expected weight - delivered weight (order-level, not batch DC)
  double get _transportLossKg => (_orderExpectedWt > 0 && _deliveryWeight > 0)
      ? (_orderExpectedWt - _deliveryWeight).clamp(0, double.infinity) : 0;
  double get _totalLossKg     => _transportLossKg + _mortalityWtKg;
  double get _lossPct         => _dcWeight > 0 ? (_totalLossKg / _dcWeight * 100) : 0;
  bool   get _isHighLoss      => _lossPct >= 2.0;
  bool   get _stockWarning    => _stock != null && _deliveryBirds > _stock!.availableBirds && _stock!.availableBirds > 0;
  bool   get _stockCritical   => _stock != null && _stock!.availableBirds <= 0;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final weight = double.tryParse(_weightCtrl.text.trim()) ?? 0;
    if (weight <= 0) { showError(context, 'Enter delivered weight'); return; }

    // Validate delivery status
    if (_deliveryStatus != 'out_for_delivery') {
      showError(context,
        'Status is "$_deliveryStatus". Must be "out_for_delivery".\nAsk admin to check batch.');
      return;
    }
    if (!_hasOpenShift) {
      showError(context, 'No active shift. Open a shift first.');
      return;
    }

    // Mortality image mandatory if mortality > 0
    if (_mortalityBirds > 0 && _mortalityProofUrl == null) {
      showError(context, 'Mortality: $_mortalityBirds birds. Photo proof is mandatory — tap the camera icon.');
      return;
    }

    if (_stockCritical) {
      final ok = await confirmDialog(context,
          title: 'No Stock', message: 'No stock available. Proceed anyway?',
          confirmText: 'Proceed', confirmColor: Colors.orange);
      if (!ok || !mounted) return;
    } else if (_stockWarning) {
      final ok = await confirmDialog(context,
          title: 'Stock Warning',
          message: 'Available: ${_stock!.availableBirds} birds\nDelivering: $_deliveryBirds birds',
          confirmText: 'Proceed', confirmColor: Colors.orange);
      if (!ok || !mounted) return;
    }

    // High loss warning
    if (_isHighLoss) {
      final ok = await confirmDialog(context,
          title: '⚠️ High Loss Alert',
          message: 'Loss: ${_lossPct.toStringAsFixed(1)}% (${_totalLossKg.toStringAsFixed(2)} kg)\n\n'
              'Transport loss: ${_transportLossKg.toStringAsFixed(2)} kg\n'
              'Mortality loss: ${_mortalityWtKg.toStringAsFixed(2)} kg\n\n'
              'This will be flagged for trader review.',
          confirmText: 'Submit Anyway', confirmColor: Colors.orange);
      if (!ok || !mounted) return;
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
        'p_mortality_birds':        _mortalityBirds,
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
        // New loss tracking params
        // ORDER-level expected weight from order.total_quantity (not batch DC total)
        'p_dc_weight_kg':           _orderExpectedWt,
        'p_avg_bird_weight_g':      _avgBirdWeightG,
        'p_mortality_proof_url':    _mortalityProofUrl,
        'p_delivery_photo_url':     _deliveryProofUrl,
        'p_diesel_cost':            0,
        'p_allowance':              0,
      });
      if (!mounted) return;
      showSuccess(context, _isHighLoss
          ? '⚠️ Delivery completed — High loss flagged for review'
          : 'Delivery completed ✓');
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
    if (!_loaded) return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back),
            onPressed: () { if (context.canPop()) context.pop(); else context.go(R.agentDeliveries); }),
        title: const Text('Complete Delivery')),
      body: const LoadingList());

    final o        = _delivery?['orders'] as Map<String,dynamic>?;
    final r        = o?['retailers'] as Map<String,dynamic>?;
    final shopName = r?['shop_name'] as String? ?? 'Delivery';

    // Blocked state
    final isReady = _deliveryStatus == 'out_for_delivery';
    if (!isReady || !_hasOpenShift) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back),
              onPressed: () { if (context.canPop()) context.pop(); else context.go(R.agentDeliveries); }),
          title: Text(shopName)),
        body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
          mainAxisSize: MainAxisSize.min, children: [
            Icon(!isReady ? Icons.pending_actions_outlined : Icons.schedule_outlined, size: 64, color: Colors.orange),
            const SizedBox(height: 16),
            Text(!isReady ? 'Not Ready for Delivery' : 'No Active Shift',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(!isReady
                ? 'Status: "$_deliveryStatus"\nMust be "out_for_delivery". Ask admin.'
                : 'Open a shift first, then come back.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: kTextSub, height: 1.5)),
            const SizedBox(height: 24),
            if (!_hasOpenShift) ElevatedButton.icon(
                onPressed: () => context.go(R.shiftOpen),
                icon: const Icon(Icons.access_time), label: const Text('Open Shift')),
            const SizedBox(height: 12),
            OutlinedButton(
                onPressed: () { if (context.canPop()) context.pop(); else context.go(R.agentDeliveries); },
                child: const Text('← Back to Deliveries')),
          ]))));
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () { if (context.canPop()) context.pop(); else context.go(R.agentDeliveries); }),
        title: Text(shopName)),
      body: Form(key: _form, child: ListView(padding: const EdgeInsets.all(16), children: [

        // Shop header
        if (r != null) Container(
          padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: kPrimary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12), border: Border.all(color: kPrimary.withValues(alpha: 0.2))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r['shop_name'] as String, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: kPrimary)),
            if (r['address'] != null) Text(r['address'] as String, style: const TextStyle(fontSize: 11, color: kTextSub)),
            if (r['phone'] != null) Text(r['phone'] as String, style: const TextStyle(fontSize: 11, color: kTextHint)),
          ])),

        // Order expected — what was ordered for THIS retailer
        if (_orderBirds > 0 || _orderWeight > 0) Container(
          padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.purple.shade200)),
          child: Row(children: [
            const Icon(Icons.shopping_cart_outlined, color: Colors.purple, size: 18), const SizedBox(width: 8),
            Expanded(child: Text(
              'Order: $_orderBirds birds · ${_orderWeight.toStringAsFixed(1)} kg expected for this shop',
              style: const TextStyle(fontSize: 12, color: Colors.purple, fontWeight: FontWeight.w600))),
          ])),

        // DC source info — full batch pickup weight (for loss reference)
        if (_dcBirds > 0 || _dcWeight > 0) Container(
          padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.shade200)),
          child: Row(children: [
            const Icon(Icons.receipt_long_outlined, color: Colors.blue, size: 18), const SizedBox(width: 8),
            Expanded(child: Text(
              'DC loaded: $_dcBirds birds · ${_dcWeight.toStringAsFixed(1)} kg total batch'
              '${_avgBirdWeightG > 0 ? ' · Avg ${_avgBirdWeightG.toStringAsFixed(0)}g/bird' : ''}',
              style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.w600))),
          ])),

        // Weighment button — primary data entry method
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [kPrimary, Colors.teal.shade600]),
            borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            onTap: _launchWeighment,
            borderRadius: BorderRadius.circular(12),
            child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
              const Icon(Icons.scale_outlined, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_weighmentDone
                    ? '✓ Weighment Complete — tap to re-weigh'
                    : '🔵 Use Weighment Machine',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                Text(_weighmentDone
                    ? 'Weight: ${_weightCtrl.text} kg · Avg: ${_avgBirdWeightG.toStringAsFixed(1)}g/bird · '
                      '${_weighmentSource == 'bluetooth' ? 'Bluetooth' : 'Manual'}'
                    : 'Connect Bluetooth scale or enter manually — recommended for accuracy',
                    style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ])),
              const Icon(Icons.chevron_right, color: Colors.white, size: 20),
            ])))),

        // OR divider
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            const Expanded(child: Divider()),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('or enter manually below',
                    style: TextStyle(fontSize: 11, color: kTextHint))),
            const Expanded(child: Divider()),
          ])),

        // Stock banner
        if (_stock != null) _stockBanner(),

        // ── DELIVERED ──────────────────────────────────────────────
        const SectionHeader('DELIVERED TO SHOP'),
        Row(children: [
          Expanded(child: TextFormField(controller: _birdsCtrl, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Birds *', suffixText: 'birds'),
              onChanged: (_) { if (mounted) setState(() {}); },
              validator: (v) => v!.isEmpty ? 'Required' : null)),
          const SizedBox(width: 12),
          Expanded(child: TextFormField(controller: _weightCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Weight (kg) *', suffixText: 'kg'),
              onChanged: (_) { if (mounted) setState(() {}); },
              validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0 ? 'Enter weight' : null)),
        ]),

        // ── LIVE LOSS CALCULATION ──────────────────────────────────
        if (_orderExpectedWt > 0 && _deliveryWeight > 0) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: _isHighLoss ? Colors.red.shade50 : Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _isHighLoss ? Colors.red.shade200 : Colors.green.shade200)),
            child: Column(children: [
              Row(children: [
                Icon(_isHighLoss ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                    color: _isHighLoss ? Colors.red : Colors.green, size: 16),
                const SizedBox(width: 6),
                Text(_isHighLoss ? '⚠️ High Loss — ${_lossPct.toStringAsFixed(1)}%' : 'Loss: ${_lossPct.toStringAsFixed(1)}%',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13,
                        color: _isHighLoss ? Colors.red : Colors.green)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                _lossStat('Order Wt', '${_orderExpectedWt.toStringAsFixed(1)} kg', Colors.blue),
                _lossStat('Delivered', '${_deliveryWeight.toStringAsFixed(1)} kg', kPrimary),
                _lossStat('Transport\nLoss', '${_transportLossKg.toStringAsFixed(2)} kg', Colors.orange),
                _lossStat('Total\nLoss', '${_totalLossKg.toStringAsFixed(2)} kg',
                    _isHighLoss ? Colors.red : Colors.orange),
              ]),
            ])),
        ],
        const SizedBox(height: 10),

        // ── RETAILER CONFIRMED ─────────────────────────────────────
        const SectionHeader('RETAILER CONFIRMED'),
        Row(children: [
          Expanded(child: TextFormField(controller: _rcvBirdsCtrl, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Birds confirmed'))),
          const SizedBox(width: 12),
          Expanded(child: TextFormField(controller: _rcvWeightCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Weight confirmed (kg)'))),
        ]),
        const SizedBox(height: 10),

        // ── MORTALITY ─────────────────────────────────────────────
        const SectionHeader('MORTALITY & LOSSES'),
        Row(children: [
          Expanded(child: TextFormField(controller: _mortalityCtrl, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Dead birds', suffixText: 'birds'),
              onChanged: (_) { if (mounted) setState(() {}); })),
          const SizedBox(width: 8),
          Expanded(child: TextFormField(controller: _rejectedCtrl, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Rejected birds'))),
          const SizedBox(width: 8),
          Expanded(child: TextFormField(controller: _shrinkKgCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Shrinkage (kg)'))),
        ]),

        // Mortality weight calculation display
        if (_mortalityBirds > 0) Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
            child: Text(
              'Mortality weight ≈ ${_mortalityWtKg.toStringAsFixed(2)} kg'
              '${_avgBirdWeightG > 0 ? ' (${_mortalityBirds} × ${_avgBirdWeightG.toStringAsFixed(0)}g)' : ''}',
              style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w600)))),

        // Mortality image upload — mandatory if mortality > 0
        const SizedBox(height: 10),
        _imageUploadTile(
          label: 'Mortality Proof Photo',
          required: _mortalityBirds > 0,
          image: _mortalityImage,
          uploading: _uploadingMortality,
          uploaded: _mortalityProofUrl != null,
          onTap: () => _pickImage(true)),

        const SizedBox(height: 10),

        // ── RETURNS ────────────────────────────────────────────────
        const SectionHeader('RETURNED TO STOCK'),
        Row(children: [
          Expanded(child: TextFormField(controller: _returnBirdsCtrl, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Return birds'))),
          const SizedBox(width: 12),
          Expanded(child: TextFormField(controller: _returnWtCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Return weight (kg)'))),
        ]),
        const SizedBox(height: 10),

        // ── CRATES ─────────────────────────────────────────────────
        const SectionHeader('CRATES'),
        Row(children: [
          Expanded(child: TextFormField(controller: _crateDropCtrl, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Given'))),
          const SizedBox(width: 12),
          Expanded(child: TextFormField(controller: _crateBackCtrl, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Received back'))),
        ]),
        const SizedBox(height: 10),

        // ── PAYMENT ────────────────────────────────────────────────
        const SectionHeader('CASH COLLECTION'),
        TextFormField(controller: _cashCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount Collected (₹)', prefixText: '₹')),
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

        // Delivery photo (optional)
        _imageUploadTile(
          label: 'Delivery Proof Photo (Optional)',
          required: false,
          image: _deliveryImage,
          uploading: _uploadingDelivery,
          uploaded: _deliveryProofUrl != null,
          onTap: () => _pickImage(false)),

        const SizedBox(height: 12),
        TextFormField(controller: _notesCtrl, maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notes (optional)', alignLabelWithHint: true)),
        const SizedBox(height: 24),

        ElevatedButton(
          onPressed: (_submitting || _uploadingMortality || _uploadingDelivery) ? null : _submit,
          style: _isHighLoss
              ? ElevatedButton.styleFrom(backgroundColor: Colors.orange)
              : null,
          child: _submitting
              ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Text(
                  _isHighLoss
                      ? '⚠️ Submit (High Loss ${_lossPct.toStringAsFixed(1)}%)'
                      : 'Mark as Delivered',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
        const SizedBox(height: 20),
      ])),
    );
  }

  Widget _imageUploadTile({
    required String label,
    required bool required,
    required File? image,
    required bool uploading,
    required bool uploaded,
    required VoidCallback onTap,
  }) {
    final Color c = uploaded ? Colors.green : (required ? Colors.red : kTextHint);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: uploaded ? Colors.green.shade50 : (required ? Colors.red.shade50 : Colors.grey.shade50),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.withValues(alpha: 0.4))),
        child: Row(children: [
          if (image != null)
            ClipRRect(borderRadius: BorderRadius.circular(6),
                child: Image.file(image, width: 48, height: 48, fit: BoxFit.cover))
          else
            Icon(Icons.camera_alt_outlined, size: 36, color: c),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c)),
            Text(
              uploading ? 'Uploading...' :
              uploaded  ? '✓ Photo uploaded' :
              required  ? 'Required — tap to take photo' :
              'Tap to take photo (optional)',
              style: TextStyle(fontSize: 11, color: c)),
          ])),
          if (uploading) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          if (uploaded && !uploading) const Icon(Icons.check_circle, color: Colors.green, size: 20),
        ])),
    );
  }

  Widget _stockBanner() {
    if (_stock == null) return const SizedBox.shrink();
    final avail = _stock!.availableBirds;
    final over  = _deliveryBirds > avail && avail > 0;
    final zero  = avail <= 0;
    final c     = zero ? Colors.red : over ? Colors.orange : Colors.green;
    return Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.withValues(alpha: 0.3))),
      child: Row(children: [
        Icon(zero ? Icons.error : over ? Icons.inventory_outlined : Icons.check_circle_outline,
            color: c, size: 18), const SizedBox(width: 8),
        Expanded(child: Text(
          zero ? 'No stock. Ask admin to add DC.' :
          over ? 'Stock: $avail birds available · Delivering: $_deliveryBirds' :
          'Stock OK: $avail birds ✓',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c))),
      ]));
  }

  Widget _lossStat(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c), textAlign: TextAlign.center),
    Text(l, style: const TextStyle(fontSize: 9, color: kTextHint), textAlign: TextAlign.center),
  ]));
}
