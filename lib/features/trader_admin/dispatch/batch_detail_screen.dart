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
  List<Map<String,dynamic>> _deliveries = [];
  List<Map<String,dynamic>> _challans   = [];   // Fix 4: DC list
  List<Map<String,dynamic>> _confirmedOrders = [];
  bool _loading = true, _submitting = false;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    setState(() => _loading = true);
    try {
      final b  = await _c.from('delivery_batches').select('*,delivery_agents(name,vehicle_no,phone)').eq('id', widget.id).maybeSingle();
      final d  = await _c.from('deliveries').select('id,status,orders(id,estimated_birds,total_quantity,retailers(shop_name))').eq('batch_id', widget.id);
      // Fix 4: load challans for this batch
      final ch = await _c.from('delivery_challans').select('*').eq('batch_id', widget.id).order('created_at');
      final co = await _c.from('orders').select('id,estimated_birds,total_quantity,retailers(shop_name)').eq('trader_id', tid!).eq('status','confirmed');
      if (mounted) setState(() {
        _batch = b; _deliveries = List<Map<String,dynamic>>.from(d);
        _challans = List<Map<String,dynamic>>.from(ch);
        _confirmedOrders = List<Map<String,dynamic>>.from(co); _loading = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _addOrder(String orderId) async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    try {
      await _c.from('deliveries').insert({
        'batch_id': widget.id, 'trader_id': tid,
        'order_id': orderId, 'delivery_agent_id': _batch?['delivery_agent_id'],
        'status': 'assigned',
      });
      _load();
    } catch (e) { if (mounted) showError(context, e.toString()); }
  }

  Future<void> _start() async {
    if (_deliveries.isEmpty) { showError(context, 'Add at least one order first'); return; }
    final ok = await confirmDialog(context, title: 'Start Deliveries', message: 'Start all ${_deliveries.length} deliveries?', confirmText: 'Start', confirmColor: kPrimary);
    if (!ok) return;
    if (mounted) setState(() => _submitting = true);
    try {
      await _c.rpc('start_batch_delivery', params: {'p_batch_id': widget.id});
      _load();
      if (mounted) showSuccess(context, 'Batch started — deliveries are out ✓');
    } catch (e) { if (mounted) showError(context, e.toString()); }
    finally { if (mounted) setState(() => _submitting = false); }
  }

  // Fix 2: Add DC at any non-terminal batch status
  Future<void> _addDC() async {
    final status = _batch?['status'] as String? ?? '';
    if (status == 'completed' || status == 'cancelled') {
      showError(context, 'Cannot add DC to a $status batch'); return;
    }

    final dcNumCtrl     = TextEditingController();
    final farmerCtrl    = TextEditingController();
    final farmLocCtrl   = TextEditingController();
    final vehicleCtrl   = TextEditingController(text: _batch?['delivery_agents']?['vehicle_no'] as String? ?? '');
    final grossWtCtrl   = TextEditingController();
    final emptyWtCtrl   = TextEditingController(text: '0');
    final birdsCtrl     = TextEditingController();
    final cratesCtrl    = TextEditingController(text: '0');
    final rateCtrl      = TextEditingController();
    DateTime dcDate = DateTime.now();
    String sourceType = 'farm';

    await showModalBottomSheet(
      context: context, isScrollControlled: true, useRootNavigator: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [const Text('Add DC', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const Spacer(), Icon(Icons.receipt_long_outlined, color: kPrimary)]),
          const SizedBox(height: 10),
          // Source type
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value:'farm', icon: Icon(Icons.agriculture, size: 14), label: Text('Farm Pickup')),
              ButtonSegment(value:'shop_collection', icon: Icon(Icons.store, size: 14), label: Text('Shop Collection')),
            ],
            selected: {sourceType}, onSelectionChanged: (s) => ss(() => sourceType = s.first)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: dcNumCtrl, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'DC Number *'))),
            const SizedBox(width: 10),
            Expanded(child: InkWell(onTap: () async {
              final d = await showDatePicker(context: ctx, initialDate: dcDate, firstDate: DateTime.now().subtract(const Duration(days: 7)), lastDate: DateTime.now());
              if (d != null) ss(() => dcDate = d);
            }, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(10)),
              child: Text(DateFormat('d MMM').format(dcDate), style: const TextStyle(fontSize: 14))))),
          ]),
          const SizedBox(height: 8),
          TextField(controller: farmerCtrl, textCapitalization: TextCapitalization.words, decoration: Text(sourceType == 'shop_collection' ? 'Shop Name *' : 'Farmer Name *', style: const TextStyle()).toString().isEmpty ? const InputDecoration(labelText: 'Farmer Name *') : InputDecoration(labelText: sourceType == 'shop_collection' ? 'Shop Name *' : 'Farmer Name *')),
          const SizedBox(height: 8),
          TextField(controller: farmLocCtrl, decoration: const InputDecoration(labelText: 'Location (optional)')),
          const SizedBox(height: 8),
          TextField(controller: vehicleCtrl, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Vehicle No.')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: grossWtCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Gross Wt (kg) *'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: emptyWtCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Empty Crate Wt'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: birdsCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Bird Count'))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: cratesCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Crates'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: rateCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '₹/kg (optional)', prefixText: '₹'))),
          ]),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: () async {
            if (dcNumCtrl.text.trim().isEmpty || farmerCtrl.text.trim().isEmpty) { showError(ctx, 'Enter DC number and farmer name'); return; }
            final gross = double.tryParse(grossWtCtrl.text) ?? 0;
            final empty = double.tryParse(emptyWtCtrl.text) ?? 0;
            if (gross <= 0) { showError(ctx, 'Enter gross weight'); return; }
            Navigator.of(ctx, rootNavigator: true).pop();
            try {
              final tid = ref.read(appUserProvider).valueOrNull?.traderId;
              final net   = gross - empty;
              final birds = int.tryParse(birdsCtrl.text) ?? 0;
              final avg   = birds > 0 ? net/birds : 0.0;
              // If batch is 'assigned', use pickup_batch; otherwise use add_batch_dc
              final bStatus = _batch?['status'] as String? ?? 'assigned';
              if (bStatus == 'assigned') {
                final shiftId = await _c.from('delivery_shifts')
                    .select('id').eq('delivery_agent_id', _batch!['delivery_agent_id'])
                    .eq('status','open').maybeSingle();
                await _c.rpc('pickup_batch', params: {
                  'p_batch_id': widget.id, 'p_shift_id': shiftId?['id'],
                  'p_dc_number': dcNumCtrl.text.trim(), 'p_dc_date': dcDate.toIso8601String().split('T')[0],
                  'p_farmer_name': farmerCtrl.text.trim(), 'p_farm_location': farmLocCtrl.text.trim().isEmpty ? null : farmLocCtrl.text.trim(),
                  'p_vehicle_number': vehicleCtrl.text.trim().isEmpty ? null : vehicleCtrl.text.trim(),
                  'p_gross_weight': gross, 'p_empty_weight': empty, 'p_net_weight': net,
                  'p_avg_weight': avg, 'p_bird_count': birds,
                  'p_weak_birds': 0, 'p_crates_count': int.tryParse(cratesCtrl.text) ?? 0,
                  'p_farm_rate': rateCtrl.text.isEmpty ? null : double.tryParse(rateCtrl.text),
                });
              } else {
                await _c.rpc('add_batch_dc', params: {
                  'p_batch_id': widget.id,
                  'p_dc_number': dcNumCtrl.text.trim(), 'p_dc_date': dcDate.toIso8601String().split('T')[0],
                  'p_farmer_name': farmerCtrl.text.trim(), 'p_farm_location': farmLocCtrl.text.trim().isEmpty ? null : farmLocCtrl.text.trim(),
                  'p_vehicle_number': vehicleCtrl.text.trim().isEmpty ? null : vehicleCtrl.text.trim(),
                  'p_gross_weight': gross, 'p_empty_weight': empty, 'p_net_weight': net,
                  'p_avg_weight': avg, 'p_bird_count': birds,
                  'p_crates_count': int.tryParse(cratesCtrl.text) ?? 0,
                  'p_farm_rate': rateCtrl.text.isEmpty ? null : double.tryParse(rateCtrl.text),
                  'p_source_type': sourceType,
                });
              }
              _load();
              if (mounted) showSuccess(context, 'DC added ✓');
            } catch (e) { if (mounted) showError(context, e.toString()); }
          }, child: const Text('Save DC')),
        ])),
      )),
    );
    for (final c in [dcNumCtrl,farmerCtrl,farmLocCtrl,vehicleCtrl,grossWtCtrl,emptyWtCtrl,birdsCtrl,cratesCtrl,rateCtrl]) c.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingList());
    if (_batch == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Not found')));
    final a      = _batch!['delivery_agents'] as Map<String,dynamic>?;
    final status = _batch!['status'] as String? ?? 'assigned';
    final canAddDC = !['completed','cancelled'].contains(status);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Batch Detail'),
        actions: [
          if (canAddDC) TextButton.icon(onPressed: _addDC, icon: const Icon(Icons.add, size: 18), label: const Text('Add DC')),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [

        // ── Agent card ─────────────────────────────────────────────
        WhiteCard(child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a?['name'] as String? ?? '—', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            if (a?['vehicle_no'] != null) Text('Vehicle: ${a!['vehicle_no']}', style: const TextStyle(fontSize: 12, color: kTextSub)),
          ])),
          StatusBadge(status, SC.order(status)),
        ])),
        const SizedBox(height: 14),

        // ── Fix 4: DC List ─────────────────────────────────────────
        Row(children: [
          const Text('Delivery Challans (DC)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (canAddDC) TextButton.icon(onPressed: _addDC, icon: const Icon(Icons.add, size: 16), label: const Text('Add DC'), style: TextButton.styleFrom(foregroundColor: kPrimary)),
        ]),
        const SizedBox(height: 6),
        if (_challans.isEmpty) Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange.shade200)),
          child: const Row(children: [
            Icon(Icons.info_outline, color: Colors.orange, size: 18), SizedBox(width: 8),
            Expanded(child: Text('No DC yet. Add DC before starting deliveries.', style: TextStyle(fontSize: 12, color: Colors.orange))),
          ]))
        else ..._challans.map((ch) {
          final date = DateTime.tryParse(ch['dc_date'] as String? ?? '');
          final net  = (ch['net_weight'] as num?)?.toDouble() ?? 0;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: const Border.fromBorderSide(BorderSide(color: kBorder))),
            child: ListTile(
              dense: true,
              leading: Container(width: 36, height: 36, decoration: BoxDecoration(color: kPrimary.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.receipt_long_outlined, color: kPrimary, size: 18)),
              title: Text(ch['dc_number'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              subtitle: Text('${ch['farmer_name'] ?? '—'} · ${ch['bird_count'] ?? 0} birds · ${net.toStringAsFixed(1)} kg', style: const TextStyle(fontSize: 11)),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('${ch['crates_count'] ?? 0} crates', style: const TextStyle(fontSize: 10, color: kTextHint)),
                if (date != null) Text(DateFormat('d MMM').format(date), style: const TextStyle(fontSize: 10, color: kTextHint)),
              ]),
            ),
          );
        }),
        const SizedBox(height: 14),

        // ── Deliveries ─────────────────────────────────────────────
        const SectionHeader('ORDERS IN BATCH'),
        if (_deliveries.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(12), child: Text('No orders yet', style: TextStyle(color: kTextHint)))),
        ..._deliveries.map((d) {
          final o = d['orders'] as Map<String,dynamic>?;
          final r = o?['retailers'] as Map<String,dynamic>?;
          final kg = (o?['total_quantity'] as num?)?.toStringAsFixed(1) ?? '—';
          return Container(margin: const EdgeInsets.only(bottom: 6), child: WhiteCard(padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r?['shop_name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text('${o?['estimated_birds'] ?? '—'} birds · $kg kg', style: const TextStyle(fontSize: 11, color: kTextSub)),
              ])),
              StatusBadge(d['status'] as String? ?? '—', SC.order(d['status'] as String? ?? ''), small: true),
            ])));
        }),

        // Add confirmed orders (only if batch is assigned)
        if (status == 'assigned' && _confirmedOrders.isNotEmpty) ...[
          const SizedBox(height: 8),
          const SectionHeader('ADD FROM CONFIRMED ORDERS'),
          ..._confirmedOrders.where((o) => !_deliveries.any((d) => (d['orders'] as Map?)?['id'] == o['id'])).map((o) {
            final r = o['retailers'] as Map<String,dynamic>?;
            return ListTile(dense: true,
              title: Text(r?['shop_name'] as String? ?? '—', style: const TextStyle(fontSize: 13)),
              subtitle: Text('${o['estimated_birds'] ?? 0} birds'),
              trailing: IconButton(icon: const Icon(Icons.add_circle_outline, color: kPrimary), onPressed: () => _addOrder(o['id'])));
          }),
        ],
        const SizedBox(height: 20),

        if (status == 'picked_up') ElevatedButton.icon(
          onPressed: _submitting ? null : _start,
          icon: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.play_arrow),
          label: const Text('Start Deliveries (Out for Delivery)'),
        ),
        if (status == 'assigned' && _challans.isNotEmpty) Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue.shade100)),
          child: const Text('DC added. Now the batch will be picked up when delivery starts.', style: TextStyle(fontSize: 12, color: Colors.blue))),
      ]),
    );
  }
}
