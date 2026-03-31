import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class BatchPickupScreen extends ConsumerStatefulWidget {
  const BatchPickupScreen({super.key, required this.batchId});
  final String batchId;
  @override ConsumerState<BatchPickupScreen> createState() => _S();
}
class _S extends ConsumerState<BatchPickupScreen> {
  final _c = Supabase.instance.client;
  final _form = GlobalKey<FormState>();
  final _dcNum = TextEditingController(); final _farmerName = TextEditingController();
  final _vehicleNo = TextEditingController(); final _driverName = TextEditingController();
  final _farmLoc = TextEditingController(); final _grossWt = TextEditingController(text: '0');
  final _emptyWt = TextEditingController(text: '0'); final _birdCount = TextEditingController(text: '0');
  final _crates = TextEditingController(text: '0'); final _farmRate = TextEditingController();
  DateTime _dcDate = DateTime.now();
  bool _loading = false, _dataLoading = true;
  Map<String,dynamic>? _batch, _shift;
  @override void initState() { super.initState(); _load(); }
  @override void dispose() { for (final c in [_dcNum,_farmerName,_vehicleNo,_driverName,_farmLoc,_grossWt,_emptyWt,_birdCount,_crates,_farmRate]) c.dispose(); super.dispose(); }

  Future<void> _load() async {
    final agentId = ref.read(appUserProvider).valueOrNull?.agentId;
    setState(() => _dataLoading = true);
    final b = await _c.from('delivery_batches').select('*,deliveries(id,status,orders(estimated_birds,retailers(shop_name)))').eq('id', widget.batchId).maybeSingle();
    final s = agentId != null ? await _c.from('delivery_shifts').select('id').eq('delivery_agent_id', agentId).eq('status','open').maybeSingle() : null;
    if (mounted) setState(() { _batch = b; _shift = s; _dataLoading = false; });
  }

  Future<void> _pickup() async {
    if (!_form.currentState!.validate()) return;
    if (_shift == null) { showError(context, 'No active shift. Open a shift first.'); return; }
    final gross = double.tryParse(_grossWt.text) ?? 0;
    final empty = double.tryParse(_emptyWt.text) ?? 0;
    final net = gross - empty;
    final birds = int.tryParse(_birdCount.text) ?? 0;
    setState(() => _loading = true);
    try {
      // pickup_batch(p_batch_id, p_shift_id, p_dc_number, p_dc_date, p_farmer_name, p_vehicle_number, p_driver_name, ...)
      await _c.rpc('pickup_batch', params: {
        'p_batch_id': widget.batchId, 'p_shift_id': _shift!['id'],
        'p_dc_number': _dcNum.text.trim(), 'p_dc_date': _dcDate.toIso8601String().split('T')[0],
        'p_farmer_name': _farmerName.text.trim(), 'p_vehicle_number': _vehicleNo.text.trim(),
        'p_driver_name': _driverName.text.trim(), 'p_farm_location': _farmLoc.text.trim(),
        'p_gross_weight': gross, 'p_empty_weight': empty, 'p_net_weight': net,
        'p_avg_weight': birds > 0 ? net/birds : 0.0, 'p_bird_count': birds,
        'p_weak_birds': 0, 'p_crates_count': int.tryParse(_crates.text) ?? 0,
        'p_farm_rate': _farmRate.text.isEmpty ? null : double.tryParse(_farmRate.text),
      });
      if (mounted) { showSuccess(context, 'Pickup recorded ✓'); context.go(R.agentHome); }
    } catch (e) { if (mounted) showError(context, e.toString()); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    if (_dataLoading) return const Scaffold(body: LoadingList());
    final isPickedUp = _batch?['status'] != 'assigned';
    if (isPickedUp) return Scaffold(appBar: AppBar(title: const Text('Farm Pickup')),
      body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.check_circle, color: Colors.green, size: 60), const SizedBox(height: 12), const Text('Batch already picked up', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)), const SizedBox(height: 16), ElevatedButton(onPressed: () => context.go(R.agentDeliveries), child: const Text('Go to Deliveries'))])));

    final deliveries = _batch?['deliveries'] as List? ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('Farm Pickup')),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Form(key: _form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (deliveries.isNotEmpty) ...[
          const SectionHeader('DELIVERIES IN BATCH'),
          ...deliveries.map((d) { final o = d['orders'] as Map<String,dynamic>?; final r = o?['retailers'] as Map<String,dynamic>?; return Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(children: [const Icon(Icons.store_outlined, size: 14, color: kPrimary), const SizedBox(width: 6), Expanded(child: Text(r?['shop_name'] as String? ?? '—', style: const TextStyle(fontSize: 13))), Text('${o?['estimated_birds'] ?? 0} birds', style: const TextStyle(fontSize: 12, color: kTextSub))])); }),
          const SizedBox(height: 14),
        ],
        const SectionHeader('DC DETAILS'),
        TextFormField(controller: _dcNum, decoration: const InputDecoration(labelText: 'DC Number *'), validator: (v) => v!.trim().isEmpty ? 'Required' : null),
        const SizedBox(height: 10),
        InkWell(onTap: () async { final d = await showDatePicker(context: context, initialDate: _dcDate, firstDate: DateTime.now().subtract(const Duration(days: 7)), lastDate: DateTime.now()); if (d != null) setState(() => _dcDate = d); },
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [const Icon(Icons.calendar_today_outlined, size: 18, color: kTextSub), const SizedBox(width: 10), Text('DC Date: ${_dcDate.toIso8601String().split('T')[0]}', style: const TextStyle(fontSize: 14))]))),
        const SizedBox(height: 14),
        const SectionHeader('FARM & VEHICLE'),
        TextFormField(controller: _farmerName, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Farmer Name *'), validator: (v) => v!.trim().isEmpty ? 'Required' : null),
        const SizedBox(height: 10),
        TextFormField(controller: _farmLoc, decoration: const InputDecoration(labelText: 'Farm Location')),
        const SizedBox(height: 10),
        Row(children: [Expanded(child: TextFormField(controller: _vehicleNo, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Vehicle No.'))), const SizedBox(width: 10), Expanded(child: TextFormField(controller: _driverName, decoration: const InputDecoration(labelText: 'Driver Name')))]),
        const SizedBox(height: 14),
        const SectionHeader('WEIGHT & BIRDS'),
        Row(children: [Expanded(child: TextFormField(controller: _grossWt, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Gross Wt (kg)'), validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0 ? 'Required' : null)), const SizedBox(width: 10), Expanded(child: TextFormField(controller: _emptyWt, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Empty Wt (kg)')))]),
        const SizedBox(height: 10),
        Row(children: [Expanded(child: TextFormField(controller: _birdCount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Bird Count'))), const SizedBox(width: 10), Expanded(child: TextFormField(controller: _crates, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Crates')))]),
        const SizedBox(height: 10),
        TextFormField(controller: _farmRate, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Farm Rate ₹/kg (optional)', prefixText: '₹')),
        const SizedBox(height: 28),
        ElevatedButton.icon(onPressed: _loading ? null : _pickup,
          icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check_circle_outline, size: 18),
          label: const Text('Confirm Pickup')),
      ]))),
    );
  }
}
