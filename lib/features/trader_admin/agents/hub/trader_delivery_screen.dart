import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/models/dashboard_models.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import 'entry_mode_selector.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TRADER DELIVERY SCREEN
//
// Trader-assisted version of delivery_complete_screen.dart.
// Identical business logic, same RPC (complete_delivery), same validations.
// Differences from agent screen:
//   • p_actor_type = 'trader'
//   • EntryModeSelector shown at top
//   • BackdateField for actual_at
//   • No Bluetooth weighment integration (trader enters verbally reported data)
//   • Launched from AgentAssistanceHub, receives deliveryId + agentName
//
// CRITICAL: Zero business logic implemented here.
// All stock movements, loss calculations, partial backorder creation,
// reconciliation updates happen inside complete_delivery RPC.
// ─────────────────────────────────────────────────────────────────────────────

class TraderDeliveryScreen extends ConsumerStatefulWidget {
  const TraderDeliveryScreen({
    super.key,
    required this.deliveryId,
    required this.agentId,
    required this.agentName,
  });

  final String deliveryId;
  final String agentId;
  final String agentName;

  @override
  ConsumerState<TraderDeliveryScreen> createState() =>
      _TraderDeliveryScreenState();
}

class _TraderDeliveryScreenState
    extends ConsumerState<TraderDeliveryScreen> {
  // ── Controllers (identical set to delivery_complete_screen) ─────────────────
  final _form         = GlobalKey<FormState>();
  final _birdsCtrl    = TextEditingController();
  final _weightCtrl   = TextEditingController();
  final _rcvBirdsCtrl = TextEditingController();
  final _rcvWtCtrl    = TextEditingController();
  final _mortCtrl     = TextEditingController(text: '0');
  final _rejCtrl      = TextEditingController(text: '0');
  final _retBirdsCtrl = TextEditingController(text: '0');
  final _retWtCtrl    = TextEditingController(text: '0');
  final _shrinkCtrl   = TextEditingController(text: '0');
  final _crateDropCtrl   = TextEditingController(text: '0');
  final _crateBackCtrl   = TextEditingController(text: '0');
  final _cashCtrl     = TextEditingController(text: '0');
  final _notesCtrl    = TextEditingController();

  // ── Trader-specific state ────────────────────────────────────────────────────
  String    _entryMode = 'called';
  DateTime? _actualAt;

  // ── Delivery state (same as agent screen) ───────────────────────────────────
  String    _payMode   = 'cash';
  bool      _submitting = false;
  bool      _loaded     = false;
  bool      _isPartial  = false;

  String _remainingAction  = 'same';
  String? _transferAgentId;
  String? _transferAgentName;
  List<Map<String, dynamic>> _otherAgents = [];
  Map<String, dynamic>? _delivery;
  StockPosition? _stock;
  String _deliveryStatus = '';

  int    _dcBirds  = 0;
  double _dcWeight = 0;
  double _avgBirdWeightG = 0;
  int    _orderBirds  = 0;
  double _orderWeight = 0;
  double _dcWeightForLoss = 0;

  // ── Photo state ──────────────────────────────────────────────────────────────
  File?   _mortalityImage;
  File?   _deliveryImage;
  bool    _uploadingMortality = false;
  bool    _uploadingDelivery  = false;
  String? _mortalityProofUrl;
  String? _deliveryProofUrl;

  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _birdsCtrl, _weightCtrl, _rcvBirdsCtrl, _rcvWtCtrl,
      _mortCtrl, _rejCtrl, _retBirdsCtrl, _retWtCtrl,
      _shrinkCtrl, _crateDropCtrl, _crateBackCtrl, _cashCtrl, _notesCtrl,
    ]) c.dispose();
    super.dispose();
  }

  // ── Data load (same queries as agent screen) ─────────────────────────────────
  Future<void> _load() async {
    final user = ref.read(appUserProvider).valueOrNull;
    try {
      final d = await Supabase.instance.client
          .from('deliveries')
          .select(
          '*,orders(id,estimated_birds,total_quantity,product_id,'
              'fulfilled_birds,fulfilled_quantity,backorder_birds,backorder_quantity,'
              'is_partial_delivery,partial_count,'
              'retailers(shop_name,address,phone))')
          .eq('id', widget.deliveryId)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (!mounted || d == null) return;
      final o = (d['orders'] as Map?)?.cast<String, dynamic>();

      // DC data for batch
      List<Map<String, dynamic>> challans = [];
      final batchId = d['batch_id'] as String?;
      if (batchId != null) {
        try {
          final ch = await Supabase.instance.client
              .from('delivery_challans')
              .select('bird_count,net_weight,avg_bird_weight')
              .eq('batch_id', batchId);
          challans =
          List<Map<String, dynamic>>.from(ch as List? ?? []);
        } catch (_) {}
      }

      _dcBirds = challans.fold(0,
              (s, c) => s + ((c['bird_count'] as num?)?.toInt() ?? 0));
      _dcWeight = challans.fold(0.0,
              (s, c) => s + ((c['net_weight'] as num?)?.toDouble() ?? 0));
      if (_dcBirds > 0 && _dcWeight > 0) {
        _avgBirdWeightG = (_dcWeight / _dcBirds) * 1000;
      } else if (challans.isNotEmpty) {
        _avgBirdWeightG =
            ((challans.first['avg_bird_weight'] as num?)?.toDouble() ?? 0) *
                1000;
      }

      final isAlreadyPartial = o?['is_partial_delivery'] == true;
      final backBirds = (o?['backorder_birds'] as num?)?.toInt() ?? 0;
      final backWeight = (o?['backorder_quantity'] as num?)?.toDouble() ?? 0;
      _orderBirds = isAlreadyPartial && backBirds > 0
          ? backBirds
          : ((o?['estimated_birds'] as num?)?.toInt() ?? 0);
      _orderWeight = isAlreadyPartial && backWeight > 0
          ? backWeight
          : ((o?['total_quantity'] as num?)?.toDouble() ?? 0);

      _dcWeightForLoss = _dcWeight > 0
          ? _dcWeight
          : ((d['expected_total_weight'] as num?)?.toDouble() ?? _orderWeight);

      final dStatus = d['status'] as String? ?? '';

      if (mounted) {
        setState(() {
          _delivery       = d;
          _deliveryStatus = dStatus;
          _loaded         = true;
        });
      }

      // Other agents for transfer picker
      if (user?.traderId != null) {
        try {
          final agentRes = await Supabase.instance.client
              .from('delivery_agents')
              .select('id,name,vehicle_no')
              .eq('trader_id', user!.traderId!)
              .eq('is_active', true)
              .neq('id', widget.agentId)
              .order('name');
          if (mounted) {
            setState(() => _otherAgents =
            List<Map<String, dynamic>>.from(agentRes as List? ?? []));
          }
        } catch (_) {}
      }

      // Stock check
      final productId = o?['product_id'] as String?;
      if (user?.traderId != null && productId != null) {
        try {
          final res = await Supabase.instance.client
              .rpc('get_available_stock', params: {
            'p_trader_id': user!.traderId,
            'p_product_id': productId,
            'p_agent_id': widget.agentId,
          });
          final list = (res as List? ?? []);
          if (list.isNotEmpty && mounted) {
            setState(() => _stock = StockPosition.fromMap(
                list.first as Map<String, dynamic>));
          }
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) {
        showError(context, e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  // ── Photo upload ─────────────────────────────────────────────────────────────
  Future<void> _pickImage(bool isMortality) async {
    try {
      final picked = await _picker.pickImage(
          source: ImageSource.camera, imageQuality: 70, maxWidth: 1200);
      if (picked == null) return;
      final file = File(picked.path);
      if (mounted) {
        setState(() {
          if (isMortality) { _mortalityImage = file; _uploadingMortality = true; }
          else             { _deliveryImage  = file; _uploadingDelivery  = true; }
        });
      }
      try {
        final path =
            '${isMortality ? 'mortality' : 'delivery'}/${DateTime.now().millisecondsSinceEpoch}.jpg';
        await Supabase.instance.client.storage
            .from('delivery-proofs')
            .upload(path, file);
        final url = Supabase.instance.client.storage
            .from('delivery-proofs')
            .getPublicUrl(path);
        if (mounted) {
          setState(() {
            if (isMortality) { _mortalityProofUrl = url; _uploadingMortality = false; }
            else             { _deliveryProofUrl  = url; _uploadingDelivery  = false; }
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            if (isMortality) _uploadingMortality = false;
            else             _uploadingDelivery  = false;
          });
          showError(context,
              'Upload failed: ${e.toString().replaceAll('Exception: ', '')}');
        }
      }
    } catch (_) {}
  }

  // ── Computed values (identical formulas to agent screen) ─────────────────────
  int    get _deliveryBirds  => int.tryParse(_birdsCtrl.text)  ?? 0;
  double get _deliveryWeight => double.tryParse(_weightCtrl.text) ?? 0;
  int    get _mortalityBirds => int.tryParse(_mortCtrl.text)   ?? 0;
  double get _mortalityWtKg  => _avgBirdWeightG > 0
      ? (_mortalityBirds * _avgBirdWeightG / 1000)
      : (double.tryParse(_shrinkCtrl.text) ?? 0);
  int    get _remainingBirds =>
      (_orderBirds  - _deliveryBirds ).clamp(0, 999999);
  double get _remainingWeight =>
      (_orderWeight - _deliveryWeight).clamp(0.0, 99999.0);
  bool   get _hasRemaining   => _remainingBirds > 0 || _remainingWeight > 0.1;
  bool   get _stockWarning   => _stock != null &&
      _deliveryBirds > _stock!.availableBirds && _stock!.availableBirds > 0;
  bool   get _stockCritical  => _stock != null && _stock!.availableBirds <= 0;

  // ── Stock refresh before submit ───────────────────────────────────────────────
  Future<void> _refreshStock() async {
    final user      = ref.read(appUserProvider).valueOrNull;
    final productId = ((_delivery?['orders'] as Map?)?.cast<String, dynamic>())?
    ['product_id'] as String?;
    if (user?.traderId == null || productId == null) return;
    try {
      final res = await Supabase.instance.client
          .rpc('get_available_stock', params: {
        'p_trader_id': user!.traderId,
        'p_product_id': productId,
        'p_agent_id': widget.agentId,
      });
      final list = (res as List? ?? []);
      if (list.isNotEmpty && mounted) {
        setState(() =>
        _stock = StockPosition.fromMap(list.first as Map<String, dynamic>));
      }
    } catch (_) {}
  }

  // ── Remaining-action bottom sheet (identical to agent screen) ─────────────────
  Future<void> _showRemainingOptions() async {
    String chosen      = _remainingAction;
    String? chosenId   = _transferAgentId;
    String? chosenName = _transferAgentName;

    await showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Row(children: [
                  const Icon(Icons.splitscreen_outlined, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Handle Remaining Quantity',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        Text('$_remainingBirds birds · '
                            '${_remainingWeight.toStringAsFixed(1)} kg remaining',
                            style: const TextStyle(fontSize: 12, color: kTextSub)),
                      ])),
                ]),
                const SizedBox(height: 16),
                _optionTile(ctx, setS,
                    value: 'close', chosen: chosen,
                    icon: Icons.check_circle_outline, color: Colors.green,
                    title: 'Close Remaining (Order Adjustment)',
                    subtitle: 'Customer reduced quantity. Remove remaining $_remainingBirds birds.',
                    onTap: () => setS(() { chosen = 'close'; chosenId = null; chosenName = null; })),
                const SizedBox(height: 8),
                _optionTile(ctx, setS,
                    value: 'same', chosen: chosen,
                    icon: Icons.delivery_dining_outlined, color: Colors.blue,
                    title: 'Same Agent — Deliver Later',
                    subtitle: 'Queue remaining $_remainingBirds birds for agent to deliver later.',
                    onTap: () => setS(() { chosen = 'same'; chosenId = null; chosenName = null; })),
                const SizedBox(height: 8),
                _optionTile(ctx, setS,
                    value: 'transfer', chosen: chosen,
                    icon: Icons.swap_horiz_rounded, color: Colors.purple,
                    title: 'Transfer to Another Agent',
                    subtitle: chosenName != null
                        ? 'Will be assigned to: $chosenName'
                        : 'Select an agent to take the remaining delivery',
                    onTap: () async {
                      setS(() => chosen = 'transfer');
                      if (_otherAgents.isEmpty) return;
                      final picked = await showDialog<Map<String, dynamic>>(
                          context: ctx, useRootNavigator: true,
                          builder: (dctx) => AlertDialog(
                            title: const Text('Select Agent'),
                            content: SizedBox(width: 300,
                                child: ListView(shrinkWrap: true,
                                    children: _otherAgents.map((a) => ListTile(
                                      leading: const CircleAvatar(
                                          child: Icon(Icons.person, size: 18)),
                                      title: Text(a['name'] as String),
                                      subtitle: Text(a['vehicle_no'] as String? ?? ''),
                                      onTap: () => Navigator.of(dctx, rootNavigator: true).pop(a),
                                    )).toList())),
                            actions: [TextButton(
                                onPressed: () =>
                                    Navigator.of(dctx, rootNavigator: true).pop(),
                                child: const Text('Cancel'))],
                          ));
                      if (picked != null) {
                        setS(() {
                          chosenId   = picked['id']   as String;
                          chosenName = picked['name'] as String;
                        });
                      }
                    }),
                if (chosen == 'transfer' && chosenName != null) ...[
                  const SizedBox(height: 8),
                  Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: Colors.purple.shade50,
                          borderRadius: BorderRadius.circular(kRadiusChip),
                          border: Border.all(color: Colors.purple.shade200)),
                      child: Row(children: [
                        const Icon(Icons.person_pin_outlined,
                            color: Colors.purple, size: 16),
                        const SizedBox(width: 6),
                        Text('Transfer to: $chosenName',
                            style: const TextStyle(fontWeight: FontWeight.w700,
                                color: Colors.purple)),
                      ])),
                ],
                if (chosen == 'transfer' && chosenName == null) ...[
                  const SizedBox(height: 6),
                  const Text('⚠ Tap above to select an agent',
                      style: TextStyle(fontSize: 11, color: Colors.orange,
                          fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 20),
                SizedBox(width: double.infinity, height: 50,
                    child: ElevatedButton(
                      onPressed: (chosen == 'transfer' && chosenId == null) ? null
                          : () {
                        setState(() {
                          _remainingAction    = chosen;
                          _transferAgentId   = chosenId;
                          _transferAgentName = chosenName;
                        });
                        Navigator.of(ctx, rootNavigator: true).pop();
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: chosen == 'close' ? Colors.green
                              : chosen == 'transfer' ? Colors.purple : Colors.blue),
                      child: Text(
                          chosen == 'close'
                              ? '✓ Confirm — Close Remaining'
                              : chosen == 'transfer'
                              ? '✓ Confirm — Transfer to $chosenName'
                              : '✓ Confirm — Queue for Same Agent',
                          style: const TextStyle(fontSize: 14,
                              fontWeight: FontWeight.w700, color: Colors.white)),
                    )),
              ]),
        ),
      ),
    );
  }

  // ── Submit — calls complete_delivery with p_actor_type='trader' ───────────────
  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final weight = double.tryParse(_weightCtrl.text.trim()) ?? 0;
    if (weight <= 0) { showError(context, 'Enter delivered weight'); return; }
    // Allow trader to complete any active delivery regardless of current status.
    // The RPC handles auto-advancing assigned/picked_up → delivered atomically.
    if (!['assigned','picked_up','out_for_delivery'].contains(_deliveryStatus)) {
      showError(context,
          'Delivery status "$_deliveryStatus" cannot be completed.');
      return;
    }
    if (_mortalityBirds > 0 && _mortalityProofUrl == null) {
      showError(context,
          'Mortality proof photo is mandatory when mortality > 0.');
      return;
    }

    // Refresh stock before check
    await _refreshStock();
    if (!mounted) return;

    if (_stockCritical) {
      showError(context,
          'No stock available for this agent.\n\nAsk admin to add DC stock.');
      return;
    }
    if (_stockWarning) {
      final ok = await confirmDialog(context,
          title: 'Stock Warning',
          message: 'Available: ${_stock!.availableBirds} birds\n'
              'Delivering: $_deliveryBirds birds\n\n'
              'Proceeding may fail if stock is insufficient.',
          confirmText: 'Proceed Anyway',
          confirmColor: Colors.orange);
      if (!ok || !mounted) return;
    }

    final reallyPartial = _isPartial && _hasRemaining;
    if (reallyPartial) {
      final ok = await confirmDialog(context,
          title: 'Partial Delivery',
          message: 'Delivering: $_deliveryBirds birds · '
              '${weight.toStringAsFixed(1)} kg\n\n'
              'Remaining: $_remainingBirds birds · '
              '${_remainingWeight.toStringAsFixed(1)} kg\n\n'
              'The remaining will be queued for this agent.',
          confirmText: 'Confirm Partial',
          confirmColor: Colors.orange);
      if (!ok || !mounted) return;
    }

    final user = ref.read(appUserProvider).valueOrNull;
    if (user == null) return;

    if (mounted) setState(() => _submitting = true);
    try {
      final res = await Supabase.instance.client
          .rpc('complete_delivery', params: {
        'p_delivery_id':           widget.deliveryId,
        'p_birds_delivered':       _deliveryBirds,
        'p_delivered_total_weight': weight,
        'p_received_bird_count':   int.tryParse(_rcvBirdsCtrl.text),
        'p_received_total_weight': double.tryParse(_rcvWtCtrl.text),
        'p_rejected_birds':        int.tryParse(_rejCtrl.text)      ?? 0,
        'p_mortality_birds':       _mortalityBirds,
        'p_crates_dropped':        int.tryParse(_crateDropCtrl.text) ?? 0,
        'p_crates_collected':      int.tryParse(_crateBackCtrl.text) ?? 0,
        'p_crates_returned':       0,
        'p_collected_amount':      double.tryParse(_cashCtrl.text)  ?? 0,
        'p_payment_mode':          _payMode,
        'p_delivery_notes':        _notesCtrl.text.trim().isEmpty
            ? null : _notesCtrl.text.trim(),
        'p_returned_birds':        int.tryParse(_retBirdsCtrl.text) ?? 0,
        'p_returned_weight':       double.tryParse(_retWtCtrl.text) ?? 0,
        'p_shrinkage_kg':          double.tryParse(_shrinkCtrl.text) ?? 0,
        'p_shrinkage_birds':       0,
        'p_dc_weight_kg':          _dcWeightForLoss,
        'p_avg_bird_weight_g':     _avgBirdWeightG,
        'p_mortality_proof_url':   _mortalityProofUrl,
        'p_delivery_photo_url':    _deliveryProofUrl,
        'p_diesel_cost':           0,
        'p_allowance':             0,
        'p_is_partial':            reallyPartial,
        'p_remaining_action':      reallyPartial ? _remainingAction : 'same',
        'p_transfer_agent_id':     (_remainingAction == 'transfer' && reallyPartial)
            ? _transferAgentId : null,
        // Trader actor params
        'p_actor_type':  'trader',
        'p_actor_id':    user.userId,
        'p_entry_mode':  _entryMode,
        if (_actualAt != null)
          'p_actual_at': _actualAt!.toIso8601String(),
      });

      if (!mounted) return;
      final isPartialResult =
          (res as Map<String, dynamic>?)?['is_partial'] == true;
      final birdsRemaining =
          (res as Map<String, dynamic>?)?['birds_remaining'] as int? ?? 0;

      if (isPartialResult) {
        showSuccess(context,
            '✅ Partial delivery saved for ${widget.agentName}.\n'
                '$_deliveryBirds birds delivered.\n'
                '$birdsRemaining birds queued for next delivery.');
      } else {
        showSuccess(context,
            '✅ Delivery completed for ${widget.agentName}');
      }
      // Return to hub
      if (context.canPop()) context.pop();
    } catch (e) {
      if (!mounted) return;
      String msg = e
          .toString()
          .replaceAll('Exception: ', '')
          .replaceAll('PostgrestException(message: ', '')
          .replaceAll(')', '');
      if (msg.contains('Insufficient stock') ||
          msg.contains('Stock would go negative')) {
        final avail = _stock?.availableBirds ?? 0;
        msg = 'Not enough stock.\n\n'
            'Available: $avail birds\n'
            'Entering: $_deliveryBirds birds\n\n'
            'Reduce the delivery quantity or add more DC stock.';
      }
      showError(context, msg);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.canPop() ? context.pop() : null,
          ),
          title: Text('Delivery — ${widget.agentName}'),
        ),
        body: const LoadingList(),
      );
    }

    final o        = (_delivery?['orders'] as Map?)?.cast<String, dynamic>();
    final r        = (o?['retailers'] as Map?)?.cast<String, dynamic>();
    final shopName = r?['shop_name'] as String? ?? 'Delivery';
    final partialCount    = (o?['partial_count'] as num?)?.toInt() ?? 0;
    final isAlreadyPartial = o?['is_partial_delivery'] == true;
    // Ready when any active status — trader can complete from any state
    final isReady  = ['assigned','picked_up','out_for_delivery'].contains(_deliveryStatus);

    if (!isReady) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back),
              onPressed: () => context.canPop() ? context.pop() : null),
          title: Text(shopName),
        ),
        body: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.pending_actions_outlined,
                size: 64, color: Colors.orange),
            const SizedBox(height: 16),
            const Text('Not Ready for Delivery',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('Delivery status: "$_deliveryStatus" — will be completed by trader.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: kTextSub)),
            const SizedBox(height: 24),
            OutlinedButton(
                onPressed: () => context.canPop() ? context.pop() : null,
                child: const Text('← Back')),
          ]),
        )),
      );
    }

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kNavy,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : null,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(shopName,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800,
                    color: Colors.white)),
            Text('Assisted: ${widget.agentName}',
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFFB4C6F4))),
          ],
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [

            // ── Trader entry mode ──────────────────────────────────────────────
            _sectionCard(
              icon: Icons.support_agent_rounded,
              iconColor: Colors.orange,
              title: 'How Did Agent Report?',
              child: EntryModeSelector(
                value: _entryMode,
                onChanged: (v) => setState(() => _entryMode = v),
              ),
            ),
            const SizedBox(height: 12),

            // ── Backdate ───────────────────────────────────────────────────────
            BackdateField(
              value: _actualAt,
              onChanged: (v) => setState(() => _actualAt = v),
            ),
            const SizedBox(height: 12),

            // ── Shop info ──────────────────────────────────────────────────────
            if (r != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: kNavy.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(color: kNavy.withValues(alpha: 0.2)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r['shop_name'] as String,
                          style: const TextStyle(fontSize: 14,
                              fontWeight: FontWeight.w800, color: kNavy)),
                      if (r['address'] != null)
                        Text(r['address'] as String,
                            style: const TextStyle(fontSize: 11, color: kTextSub)),
                      if (r['phone'] != null)
                        Text(r['phone'] as String,
                            style: const TextStyle(fontSize: 11, color: kTextHint)),
                    ]),
              ),

            // ── Partial continuation banner ────────────────────────────────────
            if (isAlreadyPartial)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(children: [
                  const Icon(Icons.splitscreen_outlined,
                      color: Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Partial Delivery — Attempt #${partialCount + 1}',
                            style: const TextStyle(fontWeight: FontWeight.w800,
                                color: Colors.orange, fontSize: 13)),
                        Text(
                            'Remaining: $_orderBirds birds · '
                                '${_orderWeight.toStringAsFixed(1)} kg to deliver',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.orange)),
                      ])),
                ]),
              ),

            // ── Order expected ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(kRadiusCard),
                border: Border.all(color: Colors.purple.shade200),
              ),
              child: Row(children: [
                const Icon(Icons.shopping_cart_outlined,
                    color: Colors.purple, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(
                    '${isAlreadyPartial ? 'Remaining' : 'Order'}: '
                        '$_orderBirds birds · ${_orderWeight.toStringAsFixed(1)} kg',
                    style: const TextStyle(fontSize: 12,
                        color: Colors.purple, fontWeight: FontWeight.w600))),
              ]),
            ),

            // ── DC info ────────────────────────────────────────────────────────
            if (_dcBirds > 0 || _dcWeight > 0)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(children: [
                  const Icon(Icons.receipt_long_outlined,
                      color: Colors.blue, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                      'Batch DC: $_dcBirds birds · '
                          '${_dcWeight.toStringAsFixed(1)} kg'
                          '${_avgBirdWeightG > 0 ? ' · Avg ${_avgBirdWeightG.toStringAsFixed(0)}g/bird' : ''}',
                      style: const TextStyle(fontSize: 12,
                          color: Colors.blue, fontWeight: FontWeight.w600))),
                ]),
              ),

            // ── Stock warning ──────────────────────────────────────────────────
            if (_stock != null) _stockBanner(),

            // ── Partial toggle ─────────────────────────────────────────────────
            Container(
              margin: EdgeInsets.only(bottom: _isPartial ? 6 : 14),
              decoration: BoxDecoration(
                color: _isPartial ? Colors.orange.shade50 : Colors.green.shade50,
                borderRadius: BorderRadius.circular(kRadiusCard),
                border: Border.all(
                    color: _isPartial
                        ? Colors.orange.shade400 : Colors.green.shade300,
                    width: 1.5),
              ),
              child: SwitchListTile(
                value: _isPartial,
                onChanged: (v) => setState(() {
                  _isPartial = v;
                  if (!v) {
                    _remainingAction    = 'same';
                    _transferAgentId   = null;
                    _transferAgentName = null;
                  }
                }),
                activeColor: Colors.orange,
                secondary: Icon(
                    _isPartial
                        ? Icons.splitscreen_outlined
                        : Icons.check_circle_outline,
                    color: _isPartial ? Colors.orange : Colors.green,
                    size: 26),
                title: Text(
                    _isPartial ? '⚡ Partial Delivery' : '✅ Full Delivery',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14,
                        color: _isPartial
                            ? Colors.orange.shade800 : Colors.green.shade700)),
                subtitle: Text(
                    _isPartial
                        ? 'Delivering part of the order'
                        : 'Delivering the complete order',
                    style: TextStyle(fontSize: 11,
                        color: _isPartial
                            ? Colors.orange.shade700 : Colors.green.shade700)),
              ),
            ),

            if (_isPartial)
              Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  child: InkWell(
                    onTap: _showRemainingOptions,
                    borderRadius: BorderRadius.circular(kRadiusCard),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(kRadiusCard),
                          border: Border.all(
                              color: _remainingAction == 'close'
                                  ? Colors.green.shade400
                                  : _remainingAction == 'transfer'
                                  ? Colors.purple.shade400
                                  : Colors.blue.shade400,
                              width: 1.5)),
                      child: Row(children: [
                        Icon(
                            _remainingAction == 'close'
                                ? Icons.check_circle_outline
                                : _remainingAction == 'transfer'
                                ? Icons.swap_horiz_rounded
                                : Icons.delivery_dining_outlined,
                            color: _remainingAction == 'close' ? Colors.green
                                : _remainingAction == 'transfer'
                                ? Colors.purple : Colors.blue,
                            size: 22),
                        const SizedBox(width: 10),
                        Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Handle Remaining',
                                  style: TextStyle(
                                      fontSize: 10, color: kTextHint,
                                      fontWeight: FontWeight.w600)),
                              Text(
                                  _remainingAction == 'close'
                                      ? 'Close remaining — adjust order'
                                      : _remainingAction == 'transfer'
                                      ? 'Transfer to: ${_transferAgentName ?? "select agent →"}'
                                      : 'Same agent — queue for later delivery',
                                  style: TextStyle(fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: _remainingAction == 'close'
                                          ? Colors.green.shade700
                                          : _remainingAction == 'transfer'
                                          ? Colors.purple.shade700
                                          : Colors.blue.shade700)),
                            ])),
                        const Icon(Icons.chevron_right,
                            color: kTextHint, size: 18),
                      ]),
                    ),
                  )),

            // ── Delivered to shop ──────────────────────────────────────────────
            const SectionHeader('DELIVERED TO SHOP'),
            Row(children: [
              Expanded(child: TextFormField(
                controller: _birdsCtrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                    labelText: 'Birds delivered *', suffixText: 'birds'),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              )),
              const SizedBox(width: 12),
              Expanded(child: TextFormField(
                controller: _weightCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                    labelText: 'Weight (kg) *', suffixText: 'kg'),
                validator: (v) =>
                (double.tryParse(v ?? '') ?? 0) <= 0 ? 'Enter weight' : null,
              )),
            ]),

            // ── Partial breakdown ──────────────────────────────────────────────
            if (_isPartial && (_deliveryBirds > 0 || _deliveryWeight > 0)) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(children: [
                  _splitStat('✅ Delivering Now',
                      '$_deliveryBirds birds\n'
                          '${_deliveryWeight.toStringAsFixed(1)} kg',
                      Colors.green),
                  Container(width: 1, height: 44,
                      color: Colors.orange.shade200,
                      margin: const EdgeInsets.symmetric(horizontal: 10)),
                  _splitStat('⏳ Remaining',
                      '$_remainingBirds birds\n'
                          '${_remainingWeight.toStringAsFixed(1)} kg',
                      _remainingBirds > 0 ? Colors.orange : Colors.grey),
                ]),
              ),
            ],
            const SizedBox(height: 10),

            // ── Retailer confirmed ─────────────────────────────────────────────
            const SectionHeader('RETAILER CONFIRMED'),
            Row(children: [
              Expanded(child: TextFormField(
                controller: _rcvBirdsCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Birds confirmed'),
              )),
              const SizedBox(width: 12),
              Expanded(child: TextFormField(
                controller: _rcvWtCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Weight confirmed (kg)'),
              )),
            ]),
            const SizedBox(height: 10),

            // ── Mortality ──────────────────────────────────────────────────────
            const SectionHeader('MORTALITY & LOSSES'),
            Row(children: [
              Expanded(child: TextFormField(
                controller: _mortCtrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                    labelText: 'Dead birds', suffixText: 'birds'),
              )),
              const SizedBox(width: 8),
              Expanded(child: TextFormField(
                controller: _rejCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Rejected'),
              )),
              const SizedBox(width: 8),
              Expanded(child: TextFormField(
                controller: _shrinkCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Shrinkage (kg)'),
              )),
            ]),
            if (_mortalityBirds > 0)
              Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(
                        'Mortality weight ≈ ${_mortalityWtKg.toStringAsFixed(2)} kg'
                            '${_avgBirdWeightG > 0 ? ' ($_mortalityBirds × ${_avgBirdWeightG.toStringAsFixed(0)}g)' : ''}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.red,
                            fontWeight: FontWeight.w600)),
                  )),
            const SizedBox(height: 10),
            _imageUploadTile(
              label: 'Mortality Proof Photo',
              required: _mortalityBirds > 0,
              image: _mortalityImage,
              uploading: _uploadingMortality,
              uploaded: _mortalityProofUrl != null,
              onTap: () => _pickImage(true),
            ),
            const SizedBox(height: 10),

            // ── Returns ────────────────────────────────────────────────────────
            const SectionHeader('RETURNED TO STOCK'),
            Row(children: [
              Expanded(child: TextFormField(
                controller: _retBirdsCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Return birds'),
              )),
              const SizedBox(width: 12),
              Expanded(child: TextFormField(
                controller: _retWtCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Return weight (kg)'),
              )),
            ]),
            const SizedBox(height: 10),

            // ── Crates ─────────────────────────────────────────────────────────
            const SectionHeader('CRATES'),
            Row(children: [
              Expanded(child: TextFormField(
                controller: _crateDropCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Given'),
              )),
              const SizedBox(width: 12),
              Expanded(child: TextFormField(
                controller: _crateBackCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Received back'),
              )),
            ]),
            const SizedBox(height: 10),

            // ── Cash collection ────────────────────────────────────────────────
            const SectionHeader('CASH COLLECTION'),
            TextFormField(
              controller: _cashCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Amount Collected (₹)', prefixText: '₹'),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'cash',   label: Text('Cash')),
                ButtonSegment(value: 'upi',    label: Text('UPI')),
                ButtonSegment(value: 'credit', label: Text('Credit')),
                ButtonSegment(value: 'bank',   label: Text('Bank')),
              ],
              selected: {_payMode},
              onSelectionChanged: (s) => setState(() => _payMode = s.first),
            ),
            const SizedBox(height: 12),

            // ── Delivery proof photo ────────────────────────────────────────────
            _imageUploadTile(
              label: 'Delivery Proof Photo (Optional)',
              required: false,
              image: _deliveryImage,
              uploading: _uploadingDelivery,
              uploaded: _deliveryProofUrl != null,
              onTap: () => _pickImage(false),
            ),
            const SizedBox(height: 12),

            // ── Notes ──────────────────────────────────────────────────────────
            TextFormField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  alignLabelWithHint: true),
            ),
            const SizedBox(height: 24),

            // ── Submit ─────────────────────────────────────────────────────────
            ElevatedButton(
              onPressed: (_submitting || _uploadingMortality || _uploadingDelivery)
                  ? null : _submit,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: _isPartial ? Colors.orange : kNavy,
              ),
              child: _submitting
                  ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white))
                  : Text(
                  _isPartial
                      ? '⚡ Submit Partial Delivery ($_deliveryBirds birds)'
                      : '✅ Mark as Delivered — ${widget.agentName}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  Widget _sectionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(color: kBorderLight),
        boxShadow: kCardShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }

  Widget _stockBanner() {
    final avail = _stock!.availableBirds;
    final over  = _deliveryBirds > avail && avail > 0;
    final zero  = avail <= 0;
    final c = zero ? Colors.red : over ? Colors.orange : Colors.green;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(
            zero ? Icons.error : over
                ? Icons.inventory_outlined : Icons.check_circle_outline,
            color: c, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(
            zero
                ? 'No stock. Add DC before proceeding.'
                : over
                ? 'Stock: $avail birds · Entering: $_deliveryBirds'
                : 'Stock OK: $avail birds ✓',
            style: TextStyle(fontSize: 12,
                fontWeight: FontWeight.w600, color: c))),
      ]),
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
    final Color c = uploaded
        ? Colors.green : required ? Colors.red : kTextHint;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: uploaded ? Colors.green.shade50
              : required ? Colors.red.shade50 : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border: Border.all(color: c.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          if (image != null)
            ClipRRect(borderRadius: BorderRadius.circular(6),
                child: Image.file(image, width: 48, height: 48,
                    fit: BoxFit.cover))
          else
            Icon(Icons.camera_alt_outlined, size: 36, color: c),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w600, color: c)),
                Text(
                    uploading ? 'Uploading...'
                        : uploaded ? '✓ Uploaded'
                        : required ? 'Required — tap to take photo'
                        : 'Tap to take photo (optional)',
                    style: TextStyle(fontSize: 11, color: c)),
              ])),
          if (uploading)
            const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2)),
          if (uploaded && !uploading)
            const Icon(Icons.check_circle, color: Colors.green, size: 20),
        ]),
      ),
    );
  }

  Widget _optionTile(
      BuildContext ctx, StateSetter setS, {
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
            borderRadius: BorderRadius.circular(kRadiusCard),
            border: Border.all(
                color: selected ? color : Colors.grey.shade200,
                width: selected ? 2 : 1)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: selected
                      ? color.withValues(alpha: 0.15) : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon,
                  color: selected ? color : kTextHint, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w800,
                    fontSize: 13, color: selected ? color : kTextMain)),
                const SizedBox(height: 3),
                Text(subtitle, style: const TextStyle(
                    fontSize: 11, color: kTextSub, height: 1.4)),
              ])),
          if (selected) Icon(Icons.check_circle, color: color, size: 20),
        ]),
      ),
    );
  }

  Widget _splitStat(String l, String v, Color c) =>
      Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(l, style: TextStyle(fontSize: 10,
                fontWeight: FontWeight.w700, color: c)),
            const SizedBox(height: 4),
            Text(v, style: TextStyle(fontSize: 14,
                fontWeight: FontWeight.w900, color: c),
                textAlign: TextAlign.center),
          ]));
}