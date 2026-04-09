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
  final _form            = GlobalKey<FormState>();
  final _birdsCtrl       = TextEditingController();
  final _weightCtrl      = TextEditingController();
  final _rcvBirdsCtrl    = TextEditingController();
  final _rcvWeightCtrl   = TextEditingController();
  final _mortalityCtrl   = TextEditingController(text: '0');
  final _rejectedCtrl    = TextEditingController(text: '0');
  final _returnBirdsCtrl = TextEditingController(text: '0');
  final _returnWtCtrl    = TextEditingController(text: '0');
  final _shrinkKgCtrl    = TextEditingController(text: '0');
  final _crateDropCtrl   = TextEditingController(text: '0');
  final _crateBackCtrl   = TextEditingController(text: '0');
  final _cashCtrl        = TextEditingController(text: '0');
  final _notesCtrl       = TextEditingController();

  String _payMode         = 'cash';
  bool   _submitting      = false;
  bool   _loaded          = false;
  bool   _isPartial       = false;
  // Remaining-quantity handling: 'close' | 'same' | 'transfer'
  String _remainingAction = 'same';
  String? _transferAgentId;
  String? _transferAgentName;
  List<Map<String,dynamic>> _otherAgents = [];
  Map<String,dynamic>? _delivery;
  StockPosition? _stock;
  String _deliveryStatus  = '';
  bool   _hasOpenShift    = false;

  // DC / order data
  int    _dcBirds         = 0;
  double _dcWeight        = 0;
  double _avgBirdWeightG  = 0;
  int    _orderBirds      = 0;
  double _orderWeight     = 0;
  // DC weight for THIS delivery (from delivery.expected_total_weight or prorated DC)
  double _dcWeightForLoss = 0;
  String _weighmentSource = 'manual';
  bool   _weighmentDone   = false;

  // Image proofs
  File?   _mortalityImage;
  File?   _deliveryImage;
  bool    _uploadingMortality = false;
  bool    _uploadingDelivery  = false;
  String? _mortalityProofUrl;
  String? _deliveryProofUrl;

  final _picker = ImagePicker();

  @override void initState() { super.initState(); _load(); }
  @override void dispose() {
    for (final c in [_birdsCtrl,_weightCtrl,_rcvBirdsCtrl,_rcvWeightCtrl,
      _mortalityCtrl,_rejectedCtrl,_returnBirdsCtrl,_returnWtCtrl,
      _shrinkKgCtrl,_crateDropCtrl,_crateBackCtrl,_cashCtrl,_notesCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final user = ref.read(appUserProvider).valueOrNull;
    try {
      final d = await Supabase.instance.client.from('deliveries')
          .select('*,orders(id,estimated_birds,total_quantity,product_id,'
                  'fulfilled_birds,fulfilled_quantity,backorder_birds,backorder_quantity,'
                  'is_partial_delivery,partial_count,'
                  'retailers(shop_name,address,phone))')
          .eq('id', widget.deliveryId)
          .maybeSingle();

      if (!mounted || d == null) return;

      final o = d['orders'] as Map<String,dynamic>?;

      // Fetch DC challans
      List<Map<String,dynamic>> challans = [];
      final batchId = d['batch_id'] as String?;
      if (batchId != null) {
        try {
          final chRes = await Supabase.instance.client
              .from('delivery_challans')
              .select('bird_count,net_weight,avg_bird_weight')
              .eq('batch_id', batchId);
          challans = List<Map<String,dynamic>>.from(chRes as List? ?? []);
        } catch (_) {}
      }

      _dcBirds  = challans.fold(0,   (s, c) => s + ((c['bird_count'] as num?)?.toInt()    ?? 0));
      _dcWeight = challans.fold(0.0, (s, c) => s + ((c['net_weight'] as num?)?.toDouble() ?? 0));
      if (_dcBirds > 0 && _dcWeight > 0) {
        _avgBirdWeightG = (_dcWeight / _dcBirds) * 1000;
      } else if (challans.isNotEmpty) {
        _avgBirdWeightG = ((challans.first['avg_bird_weight'] as num?)?.toDouble() ?? 0) * 1000;
      }

      // If this is a partial continuation, use remaining (backorder) as the target
      final isAlreadyPartial = o?['is_partial_delivery'] == true;
      final backBirds  = (o?['backorder_birds']    as num?)?.toInt()    ?? 0;
      final backWeight = (o?['backorder_quantity']  as num?)?.toDouble() ?? 0;

      _orderBirds  = isAlreadyPartial && backBirds  > 0 ? backBirds  : ((o?['estimated_birds'] as num?)?.toInt()    ?? 0);
      _orderWeight = isAlreadyPartial && backWeight > 0 ? backWeight : ((o?['total_quantity']  as num?)?.toDouble() ?? 0);

      // DC weight for loss calc = expected_total_weight on THIS delivery
      // (not the full batch DC sum — that's for the whole batch)
      final deliveryExpected = (d['expected_total_weight'] as num?)?.toDouble() ?? 0;
      _dcWeightForLoss = deliveryExpected > 0
          ? deliveryExpected
          : (_dcWeight > 0 ? _dcWeight : _orderWeight);

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

      // Load other active agents for transfer option
      try {
        final agentId = user?.agentId;
        final traderId = user?.traderId;
        if (traderId != null) {
          final agentRes = await Supabase.instance.client
              .from('delivery_agents')
              .select('id,name,vehicle_no')
              .eq('trader_id', traderId)
              .eq('is_active', true)
              .neq('id', agentId ?? '')
              .order('name');
          if (mounted) {
            setState(() => _otherAgents = List<Map<String,dynamic>>.from(agentRes as List? ?? []));
          }
        }
      } catch (_) {}

      // Stock position
      final productId = o?['product_id'] as String?;
      if (user?.traderId != null && productId != null) {
        try {
          final res = await Supabase.instance.client.rpc('get_available_stock',
              params: {'p_trader_id': user!.traderId, 'p_product_id': productId});
          final list = (res as List? ?? []);
          if (list.isNotEmpty && mounted) {
            setState(() => _stock = StockPosition.fromMap(list.first as Map<String,dynamic>));
          }
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  // ── Image upload ───────────────────────────────────────────────
  Future<void> _pickImage(bool isMortality) async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.camera, imageQuality: 70, maxWidth: 1200);
      if (picked == null) return;
      final file = File(picked.path);
      if (mounted) setState(() {
        if (isMortality) { _mortalityImage = file; _uploadingMortality = true; }
        else             { _deliveryImage  = file; _uploadingDelivery  = true; }
      });
      try {
        final path = '${isMortality ? 'mortality' : 'delivery'}/${DateTime.now().millisecondsSinceEpoch}.jpg';
        await Supabase.instance.client.storage.from('delivery-proofs').upload(path, file);
        final url = Supabase.instance.client.storage.from('delivery-proofs').getPublicUrl(path);
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

  // ── Weighment ──────────────────────────────────────────────────
  Future<void> _launchWeighment() async {
    final o = _delivery?['orders'] as Map<String,dynamic>?;
    final r = o?['retailers'] as Map<String,dynamic>?;
    await Navigator.push(context, MaterialPageRoute(builder: (_) =>
        WeighmentScreen(
          deliveryId:     widget.deliveryId,
          shopName:       r?['shop_name'] as String? ?? 'Delivery',
          expectedBirds:  _dcBirds > 0 ? _dcBirds : _orderBirds,
          expectedWeight: _dcWeight > 0 ? _dcWeight : _orderWeight,
          onComplete: (result) {
            _birdsCtrl.text     = '${result.totalBirds}';
            _weightCtrl.text    = result.totalNetWt.toStringAsFixed(3);
            _rcvBirdsCtrl.text  = '${result.totalBirds}';
            _rcvWeightCtrl.text = result.totalNetWt.toStringAsFixed(3);
            _avgBirdWeightG     = result.avgBirdWtG;
            _weighmentSource    = result.source;
            _weighmentDone      = true;
            Navigator.pop(context);
            if (mounted) setState(() {});
            showSuccess(context, '✓ Weight loaded: ${result.totalNetWt.toStringAsFixed(2)} kg');
          })));
  }

  // ── Computed values ────────────────────────────────────────────
  int    get _deliveryBirds   => int.tryParse(_birdsCtrl.text)     ?? 0;
  double get _deliveryWeight  => double.tryParse(_weightCtrl.text) ?? 0;
  int    get _mortalityBirds  => int.tryParse(_mortalityCtrl.text) ?? 0;

  // Loss
  double get _mortalityWtKg   => _avgBirdWeightG > 0
      ? (_mortalityBirds * _avgBirdWeightG / 1000)
      : (double.tryParse(_shrinkKgCtrl.text) ?? 0);
  // FIX: loss = dc_weight_for_this_delivery - delivered_weight
  // Not the full order weight (which inflates loss % for partial deliveries)
  double get _transportLossKg => (_dcWeightForLoss > 0 && _deliveryWeight > 0)
      ? (_dcWeightForLoss - _deliveryWeight).clamp(0, double.infinity) : 0;
  double get _totalLossKg     => _transportLossKg + _mortalityWtKg;
  double get _lossPct         => _dcWeight > 0 ? (_totalLossKg / _dcWeight * 100) : 0;
  bool   get _isHighLoss      => _lossPct >= 2.0;

  // Partial delivery remaining
  int    get _remainingBirds  => (_orderBirds  - _deliveryBirds) .clamp(0, 999999);
  double get _remainingWeight => (_orderWeight - _deliveryWeight) .clamp(0.0, 99999.0);
  bool   get _hasRemaining    => _remainingBirds > 0 || _remainingWeight > 0.1;

  bool   get _stockWarning    => _stock != null && _deliveryBirds > _stock!.availableBirds && _stock!.availableBirds > 0;
  bool   get _stockCritical   => _stock != null && _stock!.availableBirds <= 0;

  // ── Remaining options bottom sheet ─────────────────────────────
  Future<void> _showRemainingOptions() async {
    // Temporarily store selection
    String chosen      = _remainingAction;
    String? chosenId   = _transferAgentId;
    String? chosenName = _transferAgentName;

    await showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => Container(
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        padding: EdgeInsets.fromLTRB(20, 16, 20,
            MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Handle
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Row(children: [
            const Icon(Icons.splitscreen_outlined, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Handle Remaining Quantity',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              Text('$_remainingBirds birds · ${_remainingWeight.toStringAsFixed(1)} kg remaining',
                  style: const TextStyle(fontSize: 12, color: kTextSub)),
            ])),
          ]),
          const SizedBox(height: 16),

          // Option 1: Close
          _optionTile(ctx, setS,
            value: 'close', chosen: chosen,
            icon: Icons.check_circle_outline,
            color: Colors.green,
            title: 'Close Remaining (Order Adjustment)',
            subtitle: 'Customer reduced quantity. Remove remaining ${_remainingBirds} birds from order. Mark as fully delivered.',
            onTap: () => setS(() { chosen = 'close'; chosenId = null; chosenName = null; })),
          const SizedBox(height: 8),

          // Option 2: Same agent
          _optionTile(ctx, setS,
            value: 'same', chosen: chosen,
            icon: Icons.delivery_dining_outlined,
            color: Colors.blue,
            title: 'Same Agent — Deliver Later',
            subtitle: 'Queue remaining ${_remainingBirds} birds for you to deliver later. Auto-assigned back to you.',
            onTap: () => setS(() { chosen = 'same'; chosenId = null; chosenName = null; })),
          const SizedBox(height: 8),

          // Option 3: Transfer
          _optionTile(ctx, setS,
            value: 'transfer', chosen: chosen,
            icon: Icons.swap_horiz_rounded,
            color: Colors.purple,
            title: 'Transfer to Another Agent',
            subtitle: chosenName != null
                ? 'Will be assigned to: $chosenName'
                : 'Select an agent to take the remaining delivery',
            onTap: () async {
              setS(() => chosen = 'transfer');
              // Show agent picker
              if (_otherAgents.isEmpty) {
                setS(() {}); return;
              }
              final picked = await showDialog<Map<String,dynamic>>(
                context: ctx,
                useRootNavigator: true,
                builder: (dctx) => AlertDialog(
                  title: const Text('Select Agent'),
                  content: SizedBox(width: 300, child: ListView(shrinkWrap: true,
                    children: _otherAgents.map((a) => ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person, size: 18)),
                      title: Text(a['name'] as String),
                      subtitle: Text(a['vehicle_no'] as String? ?? ''),
                      onTap: () => Navigator.of(dctx, rootNavigator: true).pop(a),
                    )).toList())),
                  actions: [TextButton(
                    onPressed: () => Navigator.of(dctx, rootNavigator: true).pop(),
                    child: const Text('Cancel'))],
                ));
              if (picked != null) {
                setS(() {
                  chosenId   = picked['id'] as String;
                  chosenName = picked['name'] as String;
                });
              }
            }),

          // Agent name badge when transfer selected
          if (chosen == 'transfer' && chosenName != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.purple.shade200)),
              child: Row(children: [
                const Icon(Icons.person_pin_outlined, color: Colors.purple, size: 16),
                const SizedBox(width: 6),
                Text('Transfer to: $chosenName',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.purple)),
              ])),
          ],
          if (chosen == 'transfer' && chosenName == null) ...[
            const SizedBox(height: 6),
            const Text('⚠ Tap above to select an agent',
                style: TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w600)),
          ],

          const SizedBox(height: 20),
          SizedBox(width: double.infinity, height: 50,
            child: ElevatedButton(
              onPressed: (chosen == 'transfer' && chosenId == null)
                  ? null
                  : () {
                      setState(() {
                        _remainingAction    = chosen;
                        _transferAgentId    = chosenId;
                        _transferAgentName  = chosenName;
                      });
                      Navigator.of(ctx, rootNavigator: true).pop();
                    },
              style: ElevatedButton.styleFrom(
                  backgroundColor: chosen == 'close'
                      ? Colors.green
                      : chosen == 'transfer' ? Colors.purple : Colors.blue),
              child: Text(
                  chosen == 'close'    ? '✓ Confirm — Close Remaining'  :
                  chosen == 'transfer' ? '✓ Confirm — Transfer to $chosenName' :
                                         '✓ Confirm — Queue for Me',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                      color: Colors.white)),
            )),
        ]))));
  }

  Widget _optionTile(BuildContext ctx, StateSetter setS, {
    required String value, required String chosen,
    required IconData icon, required Color color,
    required String title, required String subtitle,
    required VoidCallback onTap,
  }) {
    final selected = chosen == value;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.08) : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? color : Colors.grey.shade200,
                width: selected ? 2 : 1)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: selected ? color.withValues(alpha: 0.15) : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: selected ? color : kTextHint, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13,
                color: selected ? color : kTextMain)),
            const SizedBox(height: 3),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: kTextSub, height: 1.4)),
          ])),
          if (selected)
            Icon(Icons.check_circle, color: color, size: 20),
        ])));
  }

  // ── Submit ─────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final weight = double.tryParse(_weightCtrl.text.trim()) ?? 0;
    if (weight <= 0) { showError(context, 'Enter delivered weight'); return; }

    if (_deliveryStatus != 'out_for_delivery') {
      showError(context, 'Status is "$_deliveryStatus" — must be "out_for_delivery". Ask admin.');
      return;
    }
    if (!_hasOpenShift) {
      showError(context, 'No active shift. Open a shift first.');
      return;
    }
    if (_mortalityBirds > 0 && _mortalityProofUrl == null) {
      showError(context, 'Mortality proof photo is mandatory when mortality > 0.');
      return;
    }

    // Stock checks
    if (_stockCritical) {
      final ok = await confirmDialog(context,
          title: 'No Stock', message: 'No stock available. Proceed?',
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

    // Partial delivery confirmation
    final reallyPartial = _isPartial && _hasRemaining;
    if (reallyPartial) {
      final ok = await confirmDialog(context,
          title: 'Partial Delivery',
          message: 'Delivering: $_deliveryBirds birds · ${weight.toStringAsFixed(1)} kg\n\n'
              'Remaining: $_remainingBirds birds · ${_remainingWeight.toStringAsFixed(1)} kg\n\n'
              'The remaining will be automatically queued as a new delivery for this shop.',
          confirmText: 'Confirm Partial', confirmColor: Colors.orange);
      if (!ok || !mounted) return;
    }

    if (mounted) setState(() => _submitting = true);
    try {
      final res = await Supabase.instance.client.rpc('complete_delivery', params: {
        'p_delivery_id':            widget.deliveryId,
        'p_birds_delivered':        _deliveryBirds,
        'p_delivered_total_weight': weight,
        'p_received_bird_count':    int.tryParse(_rcvBirdsCtrl.text),
        'p_received_total_weight':  double.tryParse(_rcvWeightCtrl.text),
        'p_rejected_birds':         int.tryParse(_rejectedCtrl.text)   ?? 0,
        'p_mortality_birds':        _mortalityBirds,
        'p_crates_dropped':         int.tryParse(_crateDropCtrl.text)  ?? 0,
        'p_crates_collected':       int.tryParse(_crateBackCtrl.text)  ?? 0,
        'p_crates_returned':        0,
        'p_collected_amount':       double.tryParse(_cashCtrl.text)    ?? 0,
        'p_payment_mode':           _payMode,
        'p_delivery_notes':         _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'p_returned_birds':         int.tryParse(_returnBirdsCtrl.text) ?? 0,
        'p_returned_weight':        double.tryParse(_returnWtCtrl.text) ?? 0,
        'p_shrinkage_kg':           double.tryParse(_shrinkKgCtrl.text) ?? 0,
        'p_shrinkage_birds':        0,
        'p_dc_weight_kg':           _dcWeightForLoss,  // DC weight for THIS delivery only
        'p_avg_bird_weight_g':      _avgBirdWeightG,
        'p_mortality_proof_url':    _mortalityProofUrl,
        'p_delivery_photo_url':     _deliveryProofUrl,
        'p_diesel_cost':            0,
        'p_allowance':              0,
        'p_is_partial':             reallyPartial,
        'p_remaining_action':       reallyPartial ? _remainingAction : 'same',
        'p_transfer_agent_id':      (_remainingAction == 'transfer' && reallyPartial)
                                        ? _transferAgentId : null,
      });

      if (!mounted) return;

      final isPartialResult = (res as Map<String,dynamic>?)?['is_partial'] == true;
      final birdsRemaining  = (res as Map<String,dynamic>?)?['birds_remaining'] as int? ?? 0;

      if (isPartialResult) {
        showSuccess(context,
            '✅ Partial delivery saved!\n'
            '$_deliveryBirds birds delivered.\n'
            '$birdsRemaining birds queued for next delivery.');
      } else if (_isHighLoss) {
        showSuccess(context, '⚠️ Delivered — High loss flagged for review');
      } else {
        showSuccess(context, '✅ Delivery completed ✓');
      }
      context.go(R.agentDeliveries);
    } catch (e) {
      if (!mounted) return;
      showError(context, e.toString()
          .replaceAll('Exception: ', '')
          .replaceAll('PostgrestException(message: ', '')
          .replaceAll(')', ''));
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
    final r        = o?['retailers']      as Map<String,dynamic>?;
    final shopName = r?['shop_name']      as String? ?? 'Delivery';
    final partialCount  = (o?['partial_count']      as num?)?.toInt()  ?? 0;
    final isAlreadyPartial = o?['is_partial_delivery'] == true;

    // Blocked: wrong status or no shift
    final isReady = _deliveryStatus == 'out_for_delivery';
    if (!isReady || !_hasOpenShift) {
      return Scaffold(
          appBar: AppBar(
              leading: IconButton(icon: const Icon(Icons.arrow_back),
                  onPressed: () { if (context.canPop()) context.pop(); else context.go(R.agentDeliveries); }),
              title: Text(shopName)),
          body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
              mainAxisSize: MainAxisSize.min, children: [
            Icon(!isReady ? Icons.pending_actions_outlined : Icons.schedule_outlined,
                size: 64, color: Colors.orange),
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
          leading: IconButton(icon: const Icon(Icons.arrow_back),
              onPressed: () { if (context.canPop()) context.pop(); else context.go(R.agentDeliveries); }),
          title: Text(shopName)),
      body: Form(key: _form, child: ListView(padding: const EdgeInsets.all(16), children: [

        // ── Shop header ──────────────────────────────────────────
        if (r != null) Container(
            padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(color: kPrimary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kPrimary.withValues(alpha: 0.2))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r['shop_name'] as String,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: kPrimary)),
              if (r['address'] != null)
                Text(r['address'] as String, style: const TextStyle(fontSize: 11, color: kTextSub)),
              if (r['phone'] != null)
                Text(r['phone'] as String, style: const TextStyle(fontSize: 11, color: kTextHint)),
            ])),

        // ── Partial continuation banner ──────────────────────────
        if (isAlreadyPartial) Container(
            padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade300)),
            child: Row(children: [
              const Icon(Icons.splitscreen_outlined, color: Colors.orange, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Partial Delivery — Attempt #${partialCount + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.orange, fontSize: 13)),
                Text('Remaining: $_orderBirds birds · ${_orderWeight.toStringAsFixed(1)} kg to deliver',
                    style: const TextStyle(fontSize: 11, color: Colors.orange)),
              ])),
            ])),

        // ── Order expected ───────────────────────────────────────
        Container(
            padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.purple.shade200)),
            child: Row(children: [
              const Icon(Icons.shopping_cart_outlined, color: Colors.purple, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(
                  '${isAlreadyPartial ? 'Remaining' : 'Order'}: $_orderBirds birds · ${_orderWeight.toStringAsFixed(1)} kg',
                  style: const TextStyle(fontSize: 12, color: Colors.purple, fontWeight: FontWeight.w600))),
            ])),

        // ── DC info ──────────────────────────────────────────────
        if (_dcBirds > 0 || _dcWeight > 0) Container(
            padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade200)),
            child: Row(children: [
              const Icon(Icons.receipt_long_outlined, color: Colors.blue, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(
                  'DC loaded: $_dcBirds birds · ${_dcWeight.toStringAsFixed(1)} kg'
                  '${_avgBirdWeightG > 0 ? ' · Avg ${_avgBirdWeightG.toStringAsFixed(0)}g/bird' : ''}',
                  style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.w600))),
            ])),

        // ── PARTIAL DELIVERY TOGGLE ──────────────────────────────
        Container(
            margin: EdgeInsets.only(bottom: _isPartial ? 6 : 14),
            decoration: BoxDecoration(
                color: _isPartial ? Colors.orange.shade50 : Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _isPartial ? Colors.orange.shade400 : Colors.green.shade300,
                    width: 1.5)),
            child: SwitchListTile(
              value: _isPartial,
              onChanged: (v) => setState(() {
                _isPartial = v;
                if (!v) { _remainingAction = 'same'; _transferAgentId = null; _transferAgentName = null; }
              }),
              activeColor: Colors.orange,
              secondary: Icon(
                  _isPartial ? Icons.splitscreen_outlined : Icons.check_circle_outline,
                  color: _isPartial ? Colors.orange : Colors.green, size: 26),
              title: Text(
                  _isPartial ? '⚡ Partial Delivery' : '✅ Full Delivery',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14,
                      color: _isPartial ? Colors.orange.shade800 : Colors.green.shade700)),
              subtitle: Text(
                  _isPartial
                      ? 'Delivering part of the order today'
                      : 'Delivering the complete order — all birds today',
                  style: TextStyle(fontSize: 11,
                      color: _isPartial ? Colors.orange.shade700 : Colors.green.shade700)),
            )),

    // ── REMAINING HANDLING SELECTOR (only when partial) ──────
              if (_isPartial) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  child: InkWell(
                    onTap: _showRemainingOptions,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _remainingAction == 'close'
                              ? Colors.green.shade400
                              : _remainingAction == 'transfer'
                              ? Colors.purple.shade400
                              : Colors.blue.shade400,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _remainingAction == 'close'
                                ? Icons.check_circle_outline
                                : _remainingAction == 'transfer'
                                ? Icons.swap_horiz_rounded
                                : Icons.delivery_dining_outlined,
                            color: _remainingAction == 'close'
                                ? Colors.green
                                : _remainingAction == 'transfer'
                                ? Colors.purple
                                : Colors.blue,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Handle Remaining',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: kTextHint,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  _remainingAction == 'close'
                                      ? 'Close remaining — adjust order quantity'
                                      : _remainingAction == 'transfer'
                                      ? 'Transfer to: ${_transferAgentName ?? "select agent →"}'
                                      : 'Same agent — queue for my later delivery',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: _remainingAction == 'close'
                                        ? Colors.green.shade700
                                        : _remainingAction == 'transfer'
                                        ? Colors.purple.shade700
                                        : Colors.blue.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: kTextHint, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              ],

        // ── Weighment button ─────────────────────────────────────
        Container(
            margin: const EdgeInsets.only(bottom: 10),
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
                    Text(_weighmentDone ? '✓ Weighment done — tap to re-weigh' : '🔵 Use Weighment Machine',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                    Text(_weighmentDone
                        ? 'Weight: ${_weightCtrl.text} kg · '
                          'Avg: ${_avgBirdWeightG.toStringAsFixed(1)}g/bird · '
                          '${_weighmentSource == 'bluetooth' ? 'Bluetooth' : 'Manual'}'
                        : 'Connect Bluetooth scale or enter manually — recommended',
                        style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ])),
                  const Icon(Icons.chevron_right, color: Colors.white, size: 20),
                ])))),

        Padding(padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              const Expanded(child: Divider()),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('or enter manually', style: TextStyle(fontSize: 11, color: kTextHint))),
              const Expanded(child: Divider()),
            ])),

        // Stock banner
        if (_stock != null) _stockBanner(),

        // ── DELIVERED TO SHOP ────────────────────────────────────
        const SectionHeader('DELIVERED TO SHOP'),
        Row(children: [
          Expanded(child: TextFormField(
              controller: _birdsCtrl, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Birds delivered *', suffixText: 'birds'),
              onChanged: (_) { if (mounted) setState(() {}); },
              validator: (v) => v!.isEmpty ? 'Required' : null)),
          const SizedBox(width: 12),
          Expanded(child: TextFormField(
              controller: _weightCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Weight (kg) *', suffixText: 'kg'),
              onChanged: (_) { if (mounted) setState(() {}); },
              validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0 ? 'Enter weight' : null)),
        ]),

        // ── PARTIAL DELIVERY BREAKDOWN (live) ────────────────────
        if (_isPartial && (_deliveryBirds > 0 || _deliveryWeight > 0)) ...[
          const SizedBox(height: 10),
          Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade300)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.splitscreen_outlined, color: Colors.orange, size: 16),
                  SizedBox(width: 6),
                  Text('Partial Delivery Breakdown',
                      style: TextStyle(fontWeight: FontWeight.w800, color: Colors.orange, fontSize: 13)),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  _splitStat('✅ Delivering Now',
                      '$_deliveryBirds birds\n${_deliveryWeight.toStringAsFixed(1)} kg',
                      Colors.green),
                  Container(width: 1, height: 44, color: Colors.orange.shade200,
                      margin: const EdgeInsets.symmetric(horizontal: 10)),
                  _splitStat('⏳ Remaining (queued)',
                      '$_remainingBirds birds\n${_remainingWeight.toStringAsFixed(1)} kg',
                      _remainingBirds > 0 ? Colors.orange : Colors.grey),
                ]),
                if (_remainingBirds <= 0 && _isPartial) Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('⚠ No remaining birds — switch to Full Delivery',
                        style: const TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w600))),
              ])),
        ],

        // ── LOSS CALCULATION ─────────────────────────────────────
        if (_orderWeight > 0 && _deliveryWeight > 0) ...[
          const SizedBox(height: 10),
          Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: _isHighLoss ? Colors.red.shade50 : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: _isHighLoss ? Colors.red.shade200 : Colors.green.shade200)),
              child: Column(children: [
                Row(children: [
                  Icon(_isHighLoss ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                      color: _isHighLoss ? Colors.red : Colors.green, size: 16),
                  const SizedBox(width: 6),
                  Text(_isHighLoss ? '⚠️ High Loss — ${_lossPct.toStringAsFixed(1)}%'
                      : 'Loss: ${_lossPct.toStringAsFixed(1)}%',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13,
                          color: _isHighLoss ? Colors.red : Colors.green)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  _lossStat('DC Wt', '${_dcWeightForLoss.toStringAsFixed(1)} kg', Colors.blue),
                  _lossStat('Delivered', '${_deliveryWeight.toStringAsFixed(1)} kg', kPrimary),
                  _lossStat('Transport\nLoss', '${_transportLossKg.toStringAsFixed(2)} kg', Colors.orange),
                  _lossStat('Total\nLoss', '${_totalLossKg.toStringAsFixed(2)} kg',
                      _isHighLoss ? Colors.red : Colors.orange),
                ]),
              ])),
        ],
        const SizedBox(height: 10),

        // ── RETAILER CONFIRMED ───────────────────────────────────
        const SectionHeader('RETAILER CONFIRMED'),
        Row(children: [
          Expanded(child: TextFormField(
              controller: _rcvBirdsCtrl, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Birds confirmed'))),
          const SizedBox(width: 12),
          Expanded(child: TextFormField(
              controller: _rcvWeightCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Weight confirmed (kg)'))),
        ]),
        const SizedBox(height: 10),

        // ── MORTALITY ────────────────────────────────────────────
        const SectionHeader('MORTALITY & LOSSES'),
        Row(children: [
          Expanded(child: TextFormField(
              controller: _mortalityCtrl, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Dead birds', suffixText: 'birds'),
              onChanged: (_) { if (mounted) setState(() {}); })),
          const SizedBox(width: 8),
          Expanded(child: TextFormField(
              controller: _rejectedCtrl, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Rejected birds'))),
          const SizedBox(width: 8),
          Expanded(child: TextFormField(
              controller: _shrinkKgCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Shrinkage (kg)'))),
        ]),

        if (_mortalityBirds > 0) Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                child: Text(
                    'Mortality weight ≈ ${_mortalityWtKg.toStringAsFixed(2)} kg'
                    '${_avgBirdWeightG > 0 ? ' ($_mortalityBirds × ${_avgBirdWeightG.toStringAsFixed(0)}g)' : ''}',
                    style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w600)))),

        const SizedBox(height: 10),
        _imageUploadTile(
            label: 'Mortality Proof Photo',
            required: _mortalityBirds > 0,
            image: _mortalityImage, uploading: _uploadingMortality,
            uploaded: _mortalityProofUrl != null, onTap: () => _pickImage(true)),
        const SizedBox(height: 10),

        // ── RETURNS ──────────────────────────────────────────────
        const SectionHeader('RETURNED TO STOCK'),
        Row(children: [
          Expanded(child: TextFormField(controller: _returnBirdsCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Return birds'))),
          const SizedBox(width: 12),
          Expanded(child: TextFormField(controller: _returnWtCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Return weight (kg)'))),
        ]),
        const SizedBox(height: 10),

        // ── CRATES ───────────────────────────────────────────────
        const SectionHeader('CRATES'),
        Row(children: [
          Expanded(child: TextFormField(controller: _crateDropCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Given'))),
          const SizedBox(width: 12),
          Expanded(child: TextFormField(controller: _crateBackCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Received back'))),
        ]),
        const SizedBox(height: 10),

        // ── CASH COLLECTION ──────────────────────────────────────
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

        _imageUploadTile(
            label: 'Delivery Proof Photo (Optional)',
            required: false, image: _deliveryImage,
            uploading: _uploadingDelivery, uploaded: _deliveryProofUrl != null,
            onTap: () => _pickImage(false)),

        const SizedBox(height: 12),
        TextFormField(controller: _notesCtrl, maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'Notes (optional)', alignLabelWithHint: true)),
        const SizedBox(height: 24),

        // ── SUBMIT BUTTON ────────────────────────────────────────
        ElevatedButton(
            onPressed: (_submitting || _uploadingMortality || _uploadingDelivery)
                ? null : _submit,
            style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: _isPartial
                    ? Colors.orange
                    : (_isHighLoss ? Colors.deepOrange : null)),
            child: _submitting
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : Text(
                    _isPartial
                        ? '⚡ Submit Partial Delivery ($_deliveryBirds birds)'
                        : _isHighLoss
                            ? '⚠️ Submit (High Loss ${_lossPct.toStringAsFixed(1)}%)'
                            : '✅ Mark as Delivered',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
        const SizedBox(height: 20),
      ])),
    );
  }

  Widget _imageUploadTile({
    required String label, required bool required,
    required File? image, required bool uploading,
    required bool uploaded, required VoidCallback onTap,
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
                  uploading ? 'Uploading...' : uploaded ? '✓ Uploaded' :
                  required ? 'Required — tap to take photo' : 'Tap to take photo (optional)',
                  style: TextStyle(fontSize: 11, color: c)),
            ])),
            if (uploading)
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            if (uploaded && !uploading)
              const Icon(Icons.check_circle, color: Colors.green, size: 20),
          ])));
  }

  Widget _stockBanner() {
    final avail = _stock!.availableBirds;
    final over  = _deliveryBirds > avail && avail > 0;
    final zero  = avail <= 0;
    final c     = zero ? Colors.red : over ? Colors.orange : Colors.green;
    return Container(
        margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.withValues(alpha: 0.3))),
        child: Row(children: [
          Icon(zero ? Icons.error : over ? Icons.inventory_outlined : Icons.check_circle_outline,
              color: c, size: 18), const SizedBox(width: 8),
          Expanded(child: Text(
              zero ? 'No stock. Ask admin to add DC.' :
              over ? 'Stock: $avail birds · Delivering: $_deliveryBirds' :
              'Stock OK: $avail birds ✓',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c))),
        ]));
  }

  Widget _lossStat(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c), textAlign: TextAlign.center),
    Text(l, style: const TextStyle(fontSize: 9, color: kTextHint), textAlign: TextAlign.center),
  ]));

  Widget _splitStat(String l, String v, Color c) => Expanded(child: Column(
      crossAxisAlignment: CrossAxisAlignment.center, children: [
    Text(l, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c)),
    const SizedBox(height: 4),
    Text(v, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: c), textAlign: TextAlign.center),
  ]));
}
