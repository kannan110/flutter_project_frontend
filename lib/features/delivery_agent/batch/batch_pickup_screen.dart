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
  @override
  ConsumerState<BatchPickupScreen> createState() => _BatchPickupScreenState();
}

class _BatchPickupScreenState extends ConsumerState<BatchPickupScreen> {
  final _formKey       = GlobalKey<FormState>();
  final _dcNumber      = TextEditingController();
  final _farmerName    = TextEditingController();
  final _vehicleNumber = TextEditingController();
  final _driverName    = TextEditingController();
  final _grossWeight   = TextEditingController();
  final _emptyWeight   = TextEditingController();
  final _birdCount     = TextEditingController();
  final _farmRate      = TextEditingController();
  final _inTime        = TextEditingController();
  final _outTime       = TextEditingController();
  bool _submitting = false;
  String? _openShiftId;

  double get _netWeight {
    final g = double.tryParse(_grossWeight.text) ?? 0;
    final e = double.tryParse(_emptyWeight.text) ?? 0;
    return g - e;
  }

  double get _avgWeight {
    final birds = int.tryParse(_birdCount.text) ?? 0;
    return birds > 0 ? _netWeight / birds : 0;
  }

  @override
  void initState() {
    super.initState();
    _dcNumber.text = 'DC-${DateFormat('yyyyMMdd-HHmm').format(DateTime.now())}';
    _loadShift();
  }

  @override
  void dispose() {
    for (final c in [_dcNumber, _farmerName, _vehicleNumber, _driverName, _grossWeight, _emptyWeight, _birdCount, _farmRate, _inTime, _outTime]) c.dispose();
    super.dispose();
  }

  Future<void> _loadShift() async {
    final agentId = ref.read(appUserProvider).valueOrNull?.agentId;
    if (agentId == null) return;
    final shift = await Supabase.instance.client.from('delivery_shifts')
        .select('id').eq('delivery_agent_id', agentId).eq('status', 'open').maybeSingle();
    if (mounted) setState(() => _openShiftId = shift?['id'] as String?);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_openShiftId == null) { showError(context, 'No open shift. Start a shift first.'); return; }
    setState(() => _submitting = true);
    try {
      await Supabase.instance.client.rpc('pickup_batch', params: {
        'p_batch_id':       widget.batchId,
        'p_shift_id':       _openShiftId,
        'p_dc_number':      _dcNumber.text.trim(),
        'p_dc_date':        DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'p_farmer_name':    _farmerName.text.trim(),
        'p_vehicle_number': _vehicleNumber.text.trim(),
        'p_driver_name':    _driverName.text.trim(),
        'p_gross_weight':   double.tryParse(_grossWeight.text) ?? 0,
        'p_empty_weight':   double.tryParse(_emptyWeight.text) ?? 0,
        'p_net_weight':     _netWeight,
        'p_avg_weight':     _avgWeight,
        'p_bird_count':     int.tryParse(_birdCount.text) ?? 0,
        'p_farm_rate':      double.tryParse(_farmRate.text),
        'p_in_time':        _inTime.text.trim(),
        'p_out_time':       _outTime.text.trim(),
      });
      await Supabase.instance.client.rpc('start_batch_delivery', params: {'p_batch_id': widget.batchId});
      if (mounted) { showSuccess(context, 'Pickup recorded — starting deliveries'); context.go(Routes.agentDeliveries); }
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Farm Pickup — DC')),
    body: Form(
      key: _formKey,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        const SectionHeader('DELIVERY CHALLAN'),
        TextFormField(controller: _dcNumber, decoration: const InputDecoration(labelText: 'DC Number *'),
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextFormField(controller: _inTime, decoration: const InputDecoration(labelText: 'In Time'))),
          const SizedBox(width: 12),
          Expanded(child: TextFormField(controller: _outTime, decoration: const InputDecoration(labelText: 'Out Time'))),
        ]),
        const SizedBox(height: 16),
        const SectionHeader('FARM DETAILS'),
        TextFormField(controller: _farmerName, decoration: const InputDecoration(labelText: 'Farmer Name *'),
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextFormField(controller: _vehicleNumber, decoration: const InputDecoration(labelText: 'Vehicle No. *'),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null)),
          const SizedBox(width: 12),
          Expanded(child: TextFormField(controller: _driverName, decoration: const InputDecoration(labelText: 'Driver Name'))),
        ]),
        const SizedBox(height: 16),
        const SectionHeader('WEIGHT & BIRDS'),
        Row(children: [
          Expanded(child: TextFormField(controller: _grossWeight, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Gross Weight (kg)'),
              onChanged: (_) => setState(() {}),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null)),
          const SizedBox(width: 12),
          Expanded(child: TextFormField(controller: _emptyWeight, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Empty Crate Wt (kg)'),
              onChanged: (_) => setState(() {}))),
        ]),
        const SizedBox(height: 12),
        TextFormField(controller: _birdCount, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Bird Count *'),
            onChanged: (_) => setState(() {}),
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null),
        if (_netWeight > 0) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.07), borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Net: ${_netWeight.toStringAsFixed(2)} kg', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primary)),
              Text('Avg: ${_avgWeight.toStringAsFixed(3)} kg/bird', style: const TextStyle(fontSize: 12, color: Color(0xFF757575))),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        TextFormField(controller: _farmRate, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Farm Rate (₹/kg)', prefixIcon: Icon(Icons.currency_rupee, size: 18))),
        const SizedBox(height: 28),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Record Pickup & Start Delivery'),
        ),
      ]),
    ),
  );
}
