import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class BatchDetailScreen extends ConsumerStatefulWidget {
  const BatchDetailScreen({super.key, required this.id});
  final String id;
  @override ConsumerState<BatchDetailScreen> createState() => _S();
}

class _S extends ConsumerState<BatchDetailScreen> {
  final _c = Supabase.instance.client;
  Map<String,dynamic>? _batch;
  List<Map<String,dynamic>> _deliveries      = [];
  List<Map<String,dynamic>> _challans        = [];
  List<Map<String,dynamic>> _confirmedOrders = [];
  List<Map<String,dynamic>> _agents          = [];
  bool _loading = true, _submitting = false;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (mounted) setState(() => _loading = true);
    try {
      final b  = await _c.from('delivery_batches')
          .select('*,delivery_agents(id,name,vehicle_no,phone)')
          .eq('id', widget.id).maybeSingle();
      final d  = await _c.from('deliveries')
          .select('id,status,orders(id,estimated_birds,total_quantity,retailers(shop_name))')
          .eq('batch_id', widget.id);
      final ch = await _c.from('delivery_challans')
          .select('*').eq('batch_id', widget.id).order('created_at');
      // Only confirmed (not already in a batch)
      final co = await _c.from('orders')
          .select('id,estimated_birds,total_quantity,retailers(shop_name)')
          .eq('trader_id', tid!)
          .eq('status', 'confirmed');
      final ag = await _c.from('delivery_agents')
          .select('id,name,vehicle_no')
          .eq('trader_id', tid).eq('is_active', true).order('name');
      if (mounted) setState(() {
        _batch           = b;
        _deliveries      = List<Map<String,dynamic>>.from(d);
        _challans        = List<Map<String,dynamic>>.from(ch);
        _confirmedOrders = List<Map<String,dynamic>>.from(co);
        _agents          = List<Map<String,dynamic>>.from(ag);
        _loading         = false;
      });
    } catch (e) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _addOrder(String orderId) async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    try {
      // FIX: use add_order_to_batch RPC — updates order status to 'assigned'
      await _c.rpc('add_order_to_batch', params: {
        'p_batch_id':  widget.id,
        'p_order_id':  orderId,
        'p_trader_id': tid,
      });
      _load();
      if (mounted) showSuccess(context, 'Order added to batch ✓');
    } catch (e) {
      if (mounted) showError(context,
        e.toString().replaceAll('Exception: ', '').replaceAll('PostgrestException(message: ', ''));
    }
  }

  Future<void> _removeDelivery(String deliveryId, String shopName) async {
    final ok = await confirmDialog(context,
        title: 'Remove from Batch',
        message: 'Remove "$shopName" from this batch? Order returns to Confirmed status.',
        confirmText: 'Remove', confirmColor: Colors.red);
    if (!ok) return;
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    try {
      // Get the order_id for this delivery first
      final del = await _c.from('deliveries')
          .select('order_id')
          .eq('id', deliveryId)
          .maybeSingle();
      final orderId = del?['order_id'] as String?;

      // FIX: use remove_order_from_batch RPC — resets order status to 'confirmed'
      if (orderId != null && tid != null) {
        await _c.rpc('remove_order_from_batch', params: {
          'p_batch_id': widget.id,
          'p_order_id': orderId,
        });
      } else {
        // Fallback: manual update
        await _c.from('deliveries').update({'status': 'cancelled'}).eq('id', deliveryId);
        if (orderId != null) {
          await _c.from('orders').update({'status': 'confirmed', 'batch_id': null}).eq('id', orderId);
        }
      }
      if (mounted) { showSuccess(context, 'Removed ✓'); _load(); }
    } catch (e) {
      if (mounted) showError(context,
        e.toString().replaceAll('Exception: ', '').replaceAll('PostgrestException(message: ', ''));
    }
  }

  Future<void> _reassignAgent() async {
    if (_agents.isEmpty) { showError(context, 'No active agents available'); return; }
    Map<String,dynamic>? sel;
    await showModalBottomSheet(
      context: context, useRootNavigator: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => ListView(shrinkWrap: true, padding: const EdgeInsets.all(20), children: [
        const Text('Reassign to Agent', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        ..._agents.map((a) => ListTile(
          leading: const Icon(Icons.delivery_dining, color: kPrimary),
          title: Text(a['name'] as String),
          subtitle: Text(a['vehicle_no'] as String? ?? ''),
          trailing: _batch?['delivery_agent_id'] == a['id']
              ? const StatusBadge('current', kPrimary, small: true) : null,
          onTap: () { sel = a; Navigator.of(ctx, rootNavigator: true).pop(); },
        )),
      ]));
    if (sel == null || sel!['id'] == _batch?['delivery_agent_id']) return;
    final ok = await confirmDialog(context,
        title: 'Reassign Agent',
        message: 'Reassign batch to ${sel!['name']}?',
        confirmText: 'Reassign', confirmColor: kPrimary);
    if (!ok) return;
    try {
      await _c.from('delivery_batches').update({'delivery_agent_id': sel!['id']}).eq('id', widget.id);
      // Also update all assigned deliveries in this batch
      await _c.from('deliveries').update({'delivery_agent_id': sel!['id']})
          .eq('batch_id', widget.id).inFilter('status', ['assigned', 'picked_up', 'out_for_delivery']);
      if (mounted) { showSuccess(context, 'Reassigned to ${sel!['name']} ✓'); _load(); }
    } catch (e) { if (mounted) showError(context, e.toString()); }
  }

  Future<void> _deleteBatch() async {
    final status = _batch?['status'] as String? ?? '';
    if (['picked_up', 'out_for_delivery'].contains(status)) {
      showError(context, 'Cannot delete a batch in transit. Agent must close their shift first.');
      return;
    }
    final ok = await confirmDialog(context,
        title: 'Delete Batch',
        message: 'Delete this batch?\n\n'
            '• All deliveries will be cancelled\n'
            '• All DCs for this batch will be removed\n'
            '• Orders return to Confirmed status',
        confirmText: 'Delete Batch', confirmColor: Colors.red);
    if (!ok) return;
    if (mounted) setState(() => _submitting = true);
    try {
      // FIX: Delete in correct FK order
      // Step 1: Nullify batch_id on delivery_shifts if FK exists
      try {
        await _c.from('delivery_shifts').update({'batch_id': null}).eq('batch_id', widget.id);
      } catch (_) { /* column may not exist — safe to ignore */ }
      // Step 2: Delete delivery_challans (FK: batch_id -> delivery_batches.id)
      await _c.from('delivery_challans').delete().eq('batch_id', widget.id);
      // Step 3: Unlock orders linked to this batch (reset to confirmed)
      final deliveryRows = await _c
          .from('deliveries')
          .select('id, order_id')
          .eq('batch_id', widget.id);
      for (final d in (deliveryRows as List<dynamic>)) {
        final oid = d['order_id'];
        if (oid != null) {
          await _c.from('orders').update({'status': 'confirmed', 'batch_id': null}).eq('id', oid);
        }
      }
      // Step 4: Delete deliveries (batch_id is NOT NULL — cannot nullify, must delete)
      await _c.from('deliveries').delete().eq('batch_id', widget.id);
      // Step 5: Now safe to delete the batch
      await _c.from('delivery_batches').delete().eq('id', widget.id);
      if (mounted) {
        showSuccess(context, 'Batch deleted ✓');
        context.go(R.dispatch);
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceAll('Exception: ', '').replaceAll('PostgrestException(message: ', '');
        showError(context, 'Delete failed: $msg');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _start() async {
    if (_deliveries.where((d) => d['status'] != 'cancelled').isEmpty) {
      showError(context, 'Add at least one order first');
      return;
    }
    final ok = await confirmDialog(context,
        title: 'Start Deliveries',
        message: 'Mark batch as Out for Delivery?',
        confirmText: 'Start', confirmColor: kPrimary);
    if (!ok) return;
    if (mounted) setState(() => _submitting = true);
    try {
      await _c.rpc('start_batch_delivery', params: {'p_batch_id': widget.id});
      _load();
      if (mounted) showSuccess(context, 'Deliveries started ✓');
    } catch (e) { if (mounted) showError(context, e.toString()); }
    finally { if (mounted) setState(() => _submitting = false); }
  }

  Future<void> _addDC() async {
    final status = _batch?['status'] as String? ?? '';
    if (['completed', 'cancelled'].contains(status)) {
      showError(context, 'Cannot add DC to a $status batch');
      return;
    }

    final dcNumCtrl   = TextEditingController();
    final farmerCtrl  = TextEditingController();
    final farmLocCtrl = TextEditingController();
    final vehicleCtrl = TextEditingController(
        text: _batch?['delivery_agents']?['vehicle_no'] as String? ?? '');
    final grossWtCtrl = TextEditingController();
    final emptyWtCtrl = TextEditingController(text: '0');
    final birdsCtrl   = TextEditingController();
    final cratesCtrl  = TextEditingController(text: '0');
    final rateCtrl    = TextEditingController();
    DateTime dcDate   = DateTime.now();
    String sourceType = 'farm';

    await showModalBottomSheet(
      context: context, useRootNavigator: true, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        final grossVal = double.tryParse(grossWtCtrl.text) ?? 0;
        final emptyVal = double.tryParse(emptyWtCtrl.text) ?? 0;
        final netWt    = (grossVal - emptyVal).clamp(0, double.infinity);
        final birds    = int.tryParse(birdsCtrl.text) ?? 0;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Text('Add DC', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const Spacer(),
                const Icon(Icons.receipt_long_outlined, color: kPrimary),
              ]),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'farm',            icon: Icon(Icons.agriculture, size: 14),     label: Text('Farm')),
                  ButtonSegment(value: 'shop_collection', icon: Icon(Icons.store, size: 14),            label: Text('Shop')),
                  ButtonSegment(value: 'inhouse_stock',   icon: Icon(Icons.warehouse_outlined, size: 14), label: Text('In-House')),
                ],
                selected: {sourceType},
                onSelectionChanged: (s) => ss(() => sourceType = s.first)),
              if (sourceType == 'inhouse_stock') ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200)),
                  child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.warehouse_outlined, color: Colors.orange, size: 14),
                      SizedBox(width: 6),
                      Text('IN-HOUSE DC — Internal Transfer',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.orange)),
                    ]),
                    SizedBox(height: 4),
                    Text(
                      'Moves stock FROM in-house inventory TO agent.\n'
                      'In-house stock DECREASES. Agent stock INCREASES.',
                      style: TextStyle(fontSize: 10, color: Colors.orange, height: 1.4)),
                  ])),
              ],
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(
                  controller: dcNumCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'DC Number *'))),
                const SizedBox(width: 10),
                Expanded(child: InkWell(
                  onTap: () async {
                    final d = await showDatePicker(context: ctx,
                        initialDate: dcDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 7)),
                        lastDate: DateTime.now());
                    if (d != null) ss(() => dcDate = d);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(10)),
                    child: Text(DateFormat('d MMM y').format(dcDate), style: const TextStyle(fontSize: 13))))),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: farmerCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                    labelText: sourceType == 'shop_collection'
                        ? 'Shop Name *'
                        : sourceType == 'inhouse_stock'
                            ? 'Stock Point Name *'
                            : 'Farmer Name *')),
              const SizedBox(height: 8),
              TextField(controller: farmLocCtrl, decoration: const InputDecoration(labelText: 'Location (optional)')),
              const SizedBox(height: 8),
              TextField(controller: vehicleCtrl, textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Vehicle No.')),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(
                  controller: grossWtCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Gross Wt (kg) *'),
                  onChanged: (_) => ss(() {}))),
                const SizedBox(width: 8),
                Expanded(child: TextField(
                  controller: emptyWtCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Empty Crate'),
                  onChanged: (_) => ss(() {}))),
                const SizedBox(width: 8),
                Expanded(child: TextField(
                  controller: birdsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Birds'),
                  onChanged: (_) => ss(() {}))),
              ]),
              if (grossVal > 0) Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Net: ${netWt.toStringAsFixed(2)} kg${birds > 0 ? ' · Avg: ${(netWt/birds).toStringAsFixed(3)} kg/bird' : ''}',
                    style: const TextStyle(fontSize: 12, color: kPrimary, fontWeight: FontWeight.w700))),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: cratesCtrl, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Crates'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: rateCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: '₹/kg', prefixText: '₹'))),
              ]),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  if (dcNumCtrl.text.trim().isEmpty) { showError(ctx, 'DC number required'); return; }
                  if (farmerCtrl.text.trim().isEmpty) { showError(ctx, 'Name required'); return; }
                  final gross = double.tryParse(grossWtCtrl.text) ?? 0;
                  if (gross <= 0) { showError(ctx, 'Enter gross weight'); return; }
                  Navigator.of(ctx, rootNavigator: true).pop();
                  try {
                    final bStatus = _batch?['status'] as String? ?? 'assigned';
                    final tid     = ref.read(appUserProvider).valueOrNull?.traderId;
                    final empty   = double.tryParse(emptyWtCtrl.text) ?? 0;
                    final net     = (gross - empty).clamp(0, double.infinity);
                    final bCount  = int.tryParse(birdsCtrl.text) ?? 0;
                    final avg     = bCount > 0 ? net / bCount : 0.0;

                    if (bStatus == 'assigned') {
                      final shiftRow = await _c.from('delivery_shifts')
                          .select('id')
                          .eq('delivery_agent_id', _batch!['delivery_agent_id'])
                          .eq('status', 'open')
                          .maybeSingle();
                      // FIX: pass p_source_type — was missing, inhouse_stock treated as farm
                      await _c.rpc('pickup_batch', params: {
                        'p_batch_id':       widget.id,
                        'p_shift_id':       shiftRow?['id'],
                        'p_dc_number':      dcNumCtrl.text.trim(),
                        'p_dc_date':        dcDate.toIso8601String().split('T')[0],
                        'p_farmer_name':    farmerCtrl.text.trim(),
                        'p_farm_location':  farmLocCtrl.text.trim().isEmpty ? null : farmLocCtrl.text.trim(),
                        'p_vehicle_number': vehicleCtrl.text.trim().isEmpty ? null : vehicleCtrl.text.trim(),
                        'p_driver_name':    null,
                        'p_supervisor_name': null,
                        'p_gross_weight':   gross,
                        'p_empty_weight':   empty,
                        'p_net_weight':     net,
                        'p_avg_weight':     avg > 0 ? avg : 0.0,
                        'p_bird_count':     bCount,
                        'p_weak_birds':     0,
                        'p_crates_count':   int.tryParse(cratesCtrl.text) ?? 0,
                        'p_farm_rate':      rateCtrl.text.isEmpty ? null : double.tryParse(rateCtrl.text),
                        'p_in_time':        null,
                        'p_out_time':       null,
                        'p_dc_photo_url':   null,
                        'p_source_type':    sourceType,  // FIX: was missing
                      });
                      // Advance picked_up → out_for_delivery so agent can complete
                      await _c.rpc('start_batch_delivery', params: {'p_batch_id': widget.id});
                    } else {
                      await _c.rpc('add_batch_dc', params: {
                        'p_batch_id':      widget.id,
                        'p_dc_number':     dcNumCtrl.text.trim(),
                        'p_dc_date':       dcDate.toIso8601String().split('T')[0],
                        'p_farmer_name':   farmerCtrl.text.trim(),
                        'p_farm_location': farmLocCtrl.text.trim().isEmpty ? null : farmLocCtrl.text.trim(),
                        'p_vehicle_number': vehicleCtrl.text.trim().isEmpty ? null : vehicleCtrl.text.trim(),
                        'p_gross_weight':  gross,
                        'p_empty_weight':  empty,
                        'p_net_weight':    net,
                        'p_avg_weight':    avg > 0 ? avg : 0.0,
                        'p_bird_count':    bCount,
                        'p_crates_count':  int.tryParse(cratesCtrl.text) ?? 0,
                        'p_farm_rate':     rateCtrl.text.isEmpty ? null : double.tryParse(rateCtrl.text),
                        'p_source_type':   sourceType,
                      });
                    }
                    _load();
                    if (mounted) showSuccess(context, 'DC added ✓');
                  } catch (e) { if (mounted) showError(context, e.toString().replaceAll('Exception: ', '')); }
                },
                child: const Text('Save DC')),
            ])));
      }));
    for (final c in [dcNumCtrl,farmerCtrl,farmLocCtrl,vehicleCtrl,grossWtCtrl,emptyWtCtrl,birdsCtrl,cratesCtrl,rateCtrl]) {
      c.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingList());
    if (_batch == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Not found')));
    final a       = _batch!['delivery_agents'] as Map<String,dynamic>?;
    final status  = _batch!['status'] as String? ?? 'assigned';
    final canEdit = !['completed', 'cancelled'].contains(status);
    final activeDeliveries = _deliveries.where((d) => d['status'] != 'cancelled').toList();

    // DC totals
    final dcBirds  = _challans.fold(0,   (s, c) => s + ((c['bird_count']  as num?)?.toInt()    ?? 0));
    final dcWeight = _challans.fold(0.0, (s, c) => s + ((c['net_weight']  as num?)?.toDouble() ?? 0));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Batch Detail'),
        actions: [
          if (canEdit) ...[
            TextButton.icon(onPressed: _addDC,
                icon: const Icon(Icons.receipt_long_outlined, size: 16),
                label: const Text('+ DC')),
            IconButton(
                icon: const Icon(Icons.person_outline, size: 20),
                tooltip: 'Reassign Agent',
                onPressed: _reassignAgent),
          ],
          if (canEdit && status == 'assigned')
            IconButton(
                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                tooltip: 'Delete Batch',
                onPressed: _deleteBatch),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [

        // ── Agent card ────────────────────────────────────────────
        WhiteCard(child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a?['name'] as String? ?? '—',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            if (a?['vehicle_no'] != null)
              Text('Vehicle: ${a!['vehicle_no']}', style: const TextStyle(fontSize: 12, color: kTextSub)),
            if (a?['phone'] != null)
              Text('Phone: ${a!['phone']}', style: const TextStyle(fontSize: 12, color: kTextHint)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            StatusBadge(status, SC.order(status)),
            if (canEdit) ...[
              const SizedBox(height: 6),
              GestureDetector(
                onTap: _reassignAgent,
                child: const Row(children: [
                  Icon(Icons.swap_horiz, size: 14, color: kPrimary),
                  SizedBox(width: 4),
                  Text('Swap Agent', style: TextStyle(fontSize: 11, color: kPrimary, fontWeight: FontWeight.w600)),
                ])),
            ],
          ]),
        ])),
        const SizedBox(height: 14),

        // ── DC List ───────────────────────────────────────────────
        Row(children: [
          const Expanded(child: Text('Delivery Challans (DC)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
          if (canEdit) TextButton.icon(
            onPressed: _addDC,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add DC')),
        ]),
        if (_challans.isNotEmpty) Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              _miniStat('Total Birds',  '$dcBirds',                          kPrimary),
              _miniStat('Total Weight', '${dcWeight.toStringAsFixed(1)} kg', Colors.teal),
              _miniStat('DCs',          '${_challans.length}',               Colors.blue),
            ]))),
        if (_challans.isEmpty) Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.shade200)),
          child: const Row(children: [
            Icon(Icons.info_outline, color: Colors.orange, size: 18), SizedBox(width: 8),
            Expanded(child: Text('No DC yet. Add DC before dispatching.',
                style: TextStyle(fontSize: 12, color: Colors.orange))),
          ]))
        else ..._challans.asMap().entries.map((entry) {
          final idx = entry.key;
          final ch  = entry.value;
          return _DcCard(challan: ch, index: idx + 1);
        }),
        const SizedBox(height: 14),

        // ── Orders / Deliveries ───────────────────────────────────
        Row(children: [
          Expanded(child: Text('Orders (${activeDeliveries.length})',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 6),
        if (activeDeliveries.isEmpty)
          const Center(child: Padding(padding: EdgeInsets.all(12),
              child: Text('No orders in this batch', style: TextStyle(color: kTextHint))))
        else ...activeDeliveries.map((d) {
          final o     = d['orders'] as Map<String,dynamic>?;
          final r     = o?['retailers'] as Map<String,dynamic>?;
          final dStat = d['status'] as String? ?? '';
          final kg    = (o?['total_quantity'] as num?)?.toStringAsFixed(1) ?? '—';
          final birds = (o?['estimated_birds'] as num?)?.toInt() ?? 0;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            child: WhiteCard(padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r?['shop_name'] as String? ?? '—',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text('$birds birds · $kg kg',
                      style: const TextStyle(fontSize: 11, color: kTextSub)),
                ])),
                StatusBadge(dStat, SC.order(dStat), small: true),
                if (canEdit && dStat == 'assigned') ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _removeDelivery(d['id'], r?['shop_name'] as String? ?? '—'),
                    child: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20)),
                ],
              ])));
        }),

        // Add confirmed orders (only when batch is assigned)
        if (status == 'assigned') ...[
          const SizedBox(height: 8),
          const SectionHeader('ADD FROM CONFIRMED ORDERS'),
          ...() {
            final alreadyInBatch = _deliveries.map((d) => (d['orders'] as Map?)?.cast<String,dynamic>()?['id']).toSet();
            final available = _confirmedOrders.where((o) => !alreadyInBatch.contains(o['id'])).toList();
            if (available.isEmpty) {
              return [const Padding(
                padding: EdgeInsets.all(12),
                child: Text('No confirmed orders available', style: TextStyle(color: kTextHint, fontSize: 13)))];
            }
            return available.map((o) {
              final r = o['retailers'] as Map<String,dynamic>?;
              return ListTile(
                dense: true,
                leading: const Icon(Icons.store_outlined, size: 18, color: kPrimary),
                title: Text(r?['shop_name'] as String? ?? '—', style: const TextStyle(fontSize: 13)),
                subtitle: Text('${o['estimated_birds'] ?? 0} birds · ${(o['total_quantity'] as num?)?.toStringAsFixed(0) ?? '—'} kg',
                    style: const TextStyle(fontSize: 11)),
                trailing: IconButton(
                    icon: const Icon(Icons.add_circle_outline, color: kPrimary),
                    onPressed: () => _addOrder(o['id'])));
            }).toList();
          }(),
        ],

        const SizedBox(height: 20),

        // ── Action buttons ────────────────────────────────────────
        if (status == 'picked_up')
          ElevatedButton.icon(
            onPressed: _submitting ? null : _start,
            icon: _submitting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.play_arrow),
            label: const Text('Start Deliveries (Out for Delivery)',
                style: TextStyle(fontWeight: FontWeight.w700))),
        if (status == 'assigned' && _challans.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade100)),
            child: const Text(
              'DC saved — batch is out for delivery. Agent can now complete deliveries.',
              style: TextStyle(fontSize: 12, color: Colors.blue))),
        if (status == 'out_for_delivery')
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.shade200)),
            child: const Row(children: [
              Icon(Icons.local_shipping, color: Colors.green, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text(
                'Batch is Out for Delivery — agent is delivering now',
                style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600))),
            ])),
        if (canEdit && status == 'assigned') ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _deleteBatch,
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            label: const Text('Delete Batch'),
            style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red))),
        ],
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _miniStat(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: c)),
    Text(l, style: const TextStyle(fontSize: 9, color: kTextHint), textAlign: TextAlign.center),
  ]));
}

// ── DC Card — expandable with image ─────────────────────────────────────────
class _DcCard extends StatefulWidget {
  const _DcCard({required this.challan, required this.index});
  final Map<String,dynamic> challan;
  final int index;
  @override State<_DcCard> createState() => _DcCardState();
}

class _DcCardState extends State<_DcCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ch     = widget.challan;
    final date   = DateTime.tryParse(ch['dc_date'] as String? ?? '');
    final net    = (ch['net_weight']       as num?)?.toDouble() ?? 0;
    final gross  = (ch['gross_weight']     as num?)?.toDouble() ?? 0;
    final empty  = (ch['empty_crate_weight'] as num?)?.toDouble() ?? 0;
    final birds  = (ch['bird_count']       as num?)?.toInt()    ?? 0;
    final crates = (ch['crates_count']     as num?)?.toInt()    ?? 0;
    final rate   = (ch['farm_rate']        as num?)?.toDouble();
    final photoUrl = ch['dc_photo_url'] as String?;
    final hasPic = photoUrl != null && photoUrl.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: hasPic ? Colors.green.shade200 : kBorder),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4, offset: const Offset(0, 2))]),
      child: Column(children: [
        // ── Header (always visible) ────────────────────────────
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                    color: kPrimary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Center(child: Text('${widget.index}',
                    style: const TextStyle(fontSize: 14,
                        fontWeight: FontWeight.w900, color: kPrimary)))),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(ch['dc_number'] as String? ?? '—',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  const SizedBox(width: 8),
                  if (hasPic) Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(4)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.photo_outlined, size: 10, color: Colors.green),
                      SizedBox(width: 3),
                      Text('Photo', style: TextStyle(fontSize: 9,
                          color: Colors.green, fontWeight: FontWeight.w700)),
                    ])),
                ]),
                Text(
                  '${ch['farmer_name'] ?? '—'} · $birds birds · ${net.toStringAsFixed(1)} kg',
                  style: const TextStyle(fontSize: 11, color: kTextSub)),
              ])),
              Row(children: [
                if (date != null) Text(DateFormat('d MMM').format(date),
                    style: const TextStyle(fontSize: 10, color: kTextHint)),
                const SizedBox(width: 4),
                Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 18, color: kTextHint),
              ]),
            ])),
        ),

        // ── Expanded detail ────────────────────────────────────
        if (_expanded) Container(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Divider(height: 12),

            // Weight breakdown
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: const Color(0xFFF5F7FF),
                  borderRadius: BorderRadius.circular(8)),
              child: Column(children: [
                _row('Gross Weight',       '${gross.toStringAsFixed(2)} kg'),
                _row('Empty Crate Weight', '${empty.toStringAsFixed(2)} kg'),
                _row('Net Weight',         '${net.toStringAsFixed(2)} kg',  kPrimary),
                _row('Bird Count',         '$birds birds'),
                _row('Crates',             '$crates'),
                if (rate != null) _row('Farm Rate', '₹${rate.toStringAsFixed(2)}/kg'),
                if (rate != null && net > 0)
                  _row('Farm Amount', '₹${(rate * net).toStringAsFixed(2)}', Colors.green),
              ])),

            // Extra info
            if (ch['farm_location'] != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.location_on_outlined, size: 13, color: kTextSub),
                const SizedBox(width: 4),
                Expanded(child: Text(ch['farm_location'] as String,
                    style: const TextStyle(fontSize: 11, color: kTextSub))),
              ]),
            ],
            if (ch['vehicle_number'] != null) ...[
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.directions_car_outlined, size: 13, color: kTextSub),
                const SizedBox(width: 4),
                Text(ch['vehicle_number'] as String,
                    style: const TextStyle(fontSize: 11, color: kTextSub)),
              ]),
            ],

            // DC Photo
            if (hasPic) ...[
              const SizedBox(height: 12),
              Row(children: [
                const Icon(Icons.photo_library_outlined, size: 13, color: Colors.green),
                const SizedBox(width: 6),
                const Text('DC Photo Proof',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.green)),
              ]),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _showImageFull(context, photoUrl!),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(children: [
                    Image.network(
                      photoUrl!,
                      width: double.infinity, height: 180,
                      fit: BoxFit.cover,
                      loadingBuilder: (ctx, child, prog) => prog == null ? child
                          : Container(height: 180,
                              color: Colors.grey.shade100,
                              child: const Center(
                                  child: CircularProgressIndicator(strokeWidth: 2))),
                      errorBuilder: (_, __, ___) => Container(
                          height: 80, color: Colors.grey.shade100,
                          child: const Center(
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.broken_image_outlined, color: Colors.grey),
                                Text('Image unavailable', style: TextStyle(fontSize: 11, color: Colors.grey)),
                              ]))),
                    ),
                    Positioned(bottom: 8, right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: Colors.black54,
                            borderRadius: BorderRadius.circular(6)),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.zoom_in, size: 12, color: Colors.white),
                          SizedBox(width: 4),
                          Text('Tap to expand', style: TextStyle(fontSize: 10, color: Colors.white)),
                        ]))),
                  ])))
            ] else ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200)),
                child: const Row(children: [
                  Icon(Icons.camera_alt_outlined, size: 14, color: Colors.orange),
                  SizedBox(width: 6),
                  Text('No DC photo uploaded yet',
                      style: TextStyle(fontSize: 11, color: Colors.orange)),
                ])),
            ],
          ])),
      ]));
  }

  void _showImageFull(BuildContext context, String url) {
    showDialog(
      context: context, useRootNavigator: true, builder: (ctx) =>
      Dialog(
        insetPadding: const EdgeInsets.all(8),
        child: Stack(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(url, fit: BoxFit.contain)),
          Positioned(top: 8, right: 8,
            child: GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close, color: Colors.white, size: 18)))),
        ])));
  }

  Widget _row(String l, String v, [Color? c]) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(children: [
      SizedBox(width: 120, child: Text(l, style: const TextStyle(fontSize: 11, color: kTextSub))),
      Text(v, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c ?? kTextMain)),
    ]));
}
