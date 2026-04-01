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
  final _c    = Supabase.instance.client;
  final _form = GlobalKey<FormState>();

  // DC fields
  final _dcNum    = TextEditingController();
  final _farmer   = TextEditingController();
  final _farmLoc  = TextEditingController();
  final _vehicle  = TextEditingController();
  final _driver   = TextEditingController();
  final _grossWt  = TextEditingController();
  final _emptyWt  = TextEditingController(text: '0');
  final _birds    = TextEditingController();
  final _crates   = TextEditingController(text: '0');
  final _farmRate = TextEditingController();

  DateTime _dcDate   = DateTime.now();
  String   _srcType  = 'farm'; // 'farm' or 'shop_collection'
  bool _loading = false, _dataLoading = true;
  Map<String,dynamic>? _batch, _shift;
  List<Map<String,dynamic>> _existingDCs = [];
  List<Map<String,dynamic>> _deliveries  = [];

  @override void initState() { super.initState(); _load(); }
  @override void dispose() {
    for (final c in [_dcNum,_farmer,_farmLoc,_vehicle,_driver,_grossWt,_emptyWt,_birds,_crates,_farmRate]) c.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final agentId = ref.read(appUserProvider).valueOrNull?.agentId;
    setState(() => _dataLoading = true);
    try {
      final b = await _c.from('delivery_batches')
          .select('*,delivery_agents(name,vehicle_no,phone)')
          .eq('id', widget.batchId).maybeSingle();

      final shift = agentId != null
          ? await _c.from('delivery_shifts').select('id').eq('delivery_agent_id', agentId).eq('status','open').maybeSingle()
          : null;

      final dcs = await _c.from('delivery_challans').select('*').eq('batch_id', widget.batchId).order('created_at');
      final d   = await _c.from('deliveries')
          .select('id,status,orders(estimated_birds,total_quantity,retailers(shop_name))')
          .eq('batch_id', widget.batchId);

      // Pre-fill vehicle from agent
      if (b?['delivery_agents']?['vehicle_no'] != null && _vehicle.text.isEmpty) {
        _vehicle.text = b!['delivery_agents']['vehicle_no'] as String;
      }

      if (mounted) setState(() {
        _batch = b; _shift = shift;
        _existingDCs = List<Map<String,dynamic>>.from(dcs);
        _deliveries  = List<Map<String,dynamic>>.from(d);
        _dataLoading = false;
      });
    } catch (_) { if (mounted) setState(() => _dataLoading = false); }
  }

  double get _netWt => (double.tryParse(_grossWt.text) ?? 0) - (double.tryParse(_emptyWt.text) ?? 0);
  int    get _birdCount => int.tryParse(_birds.text) ?? 0;
  double get _avgWt  => _birdCount > 0 ? _netWt / _birdCount : 0;

  Future<void> _saveDC() async {
    if (!_form.currentState!.validate()) return;
    if (_dcNum.text.trim().isEmpty) { showError(context, 'Enter DC number'); return; }
    if (_farmer.text.trim().isEmpty) { showError(context, _srcType == 'farm' ? 'Enter farmer name' : 'Enter shop name'); return; }
    final gross = double.tryParse(_grossWt.text) ?? 0;
    if (gross <= 0) { showError(context, 'Enter gross weight > 0'); return; }

    setState(() => _loading = true);
    try {
      final bStatus = _batch?['status'] as String? ?? 'assigned';
      if (bStatus == 'assigned') {
        // Initial pickup — use pickup_batch
        if (_shift == null) { showError(context, 'No active shift. Open a shift first.'); setState(() => _loading = false); return; }
        await _c.rpc('pickup_batch', params: {
          'p_batch_id':       widget.batchId,
          'p_shift_id':       _shift!['id'],
          'p_dc_number':      _dcNum.text.trim(),
          'p_dc_date':        _dcDate.toIso8601String().split('T')[0],
          'p_farmer_name':    _farmer.text.trim(),
          'p_farm_location':  _farmLoc.text.trim().isEmpty ? null : _farmLoc.text.trim(),
          'p_vehicle_number': _vehicle.text.trim().isEmpty ? null : _vehicle.text.trim(),
          'p_driver_name':    _driver.text.trim().isEmpty  ? null : _driver.text.trim(),
          'p_gross_weight':   gross,
          'p_empty_weight':   double.tryParse(_emptyWt.text) ?? 0,
          'p_net_weight':     _netWt,
          'p_avg_weight':     _avgWt,
          'p_bird_count':     _birdCount,
          'p_weak_birds':     0,
          'p_crates_count':   int.tryParse(_crates.text) ?? 0,
          'p_farm_rate':      _farmRate.text.isEmpty ? null : double.tryParse(_farmRate.text),
        });
        if (mounted) { showSuccess(context, 'DC saved — batch picked up ✓'); context.go(R.agentHome); }
      } else {
        // Additional DC — use add_batch_dc
        await _c.rpc('add_batch_dc', params: {
          'p_batch_id':      widget.batchId,
          'p_dc_number':     _dcNum.text.trim(),
          'p_dc_date':       _dcDate.toIso8601String().split('T')[0],
          'p_farmer_name':   _farmer.text.trim(),
          'p_farm_location': _farmLoc.text.trim().isEmpty ? null : _farmLoc.text.trim(),
          'p_vehicle_number': _vehicle.text.trim().isEmpty ? null : _vehicle.text.trim(),
          'p_gross_weight':  gross,
          'p_empty_weight':  double.tryParse(_emptyWt.text) ?? 0,
          'p_net_weight':    _netWt,
          'p_avg_weight':    _avgWt,
          'p_bird_count':    _birdCount,
          'p_crates_count':  int.tryParse(_crates.text) ?? 0,
          'p_farm_rate':     _farmRate.text.isEmpty ? null : double.tryParse(_farmRate.text),
          'p_source_type':   _srcType,
        });
        if (mounted) { showSuccess(context, 'DC added ✓'); _clearForm(); _load(); }
      }
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ',''));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  void _clearForm() {
    _dcNum.clear(); _farmer.clear(); _farmLoc.clear(); _birds.clear(); _farmRate.clear();
    _grossWt.clear(); _emptyWt.text = '0'; _crates.text = '0';
    setState(() { _dcDate = DateTime.now(); });
  }

  @override
  Widget build(BuildContext context) {
    if (_dataLoading) return const Scaffold(body: LoadingList());
    final a       = _batch?['delivery_agents'] as Map<String,dynamic>?;
    final bStatus = _batch?['status'] as String? ?? 'assigned';
    final isAdditional = bStatus != 'assigned';

    return Scaffold(
      appBar: AppBar(
        title: Text(isAdditional ? 'Add DC (Additional Pickup)' : 'Farm Pickup — Create DC'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Form(key: _form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

        // Batch info
        WhiteCard(child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a?['name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            Text('Vehicle: ${_batch?['vehicle_no'] ?? a?['vehicle_no'] ?? '—'}', style: const TextStyle(fontSize: 11, color: kTextSub)),
          ])),
          StatusBadge(bStatus, SC.order(bStatus)),
        ])),
        const SizedBox(height: 12),

        // Deliveries summary
        if (_deliveries.isNotEmpty) ...[
          const SectionHeader('ORDERS IN THIS BATCH'),
          ..._deliveries.where((d) => d['status'] != 'cancelled').map((d) {
            final o = d['orders'] as Map<String,dynamic>?;
            final r = o?['retailers'] as Map<String,dynamic>?;
            return Padding(padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                const Icon(Icons.store_outlined, size: 13, color: kPrimary), const SizedBox(width: 6),
                Expanded(child: Text(r?['shop_name'] as String? ?? '—', style: const TextStyle(fontSize: 12))),
                Text('${o?['estimated_birds'] ?? 0} birds · ${(o?['total_quantity'] as num?)?.toStringAsFixed(0) ?? 0} kg',
                    style: const TextStyle(fontSize: 11, color: kTextSub)),
              ]));
          }),
          const SizedBox(height: 12),
        ],

        // Existing DCs
        if (_existingDCs.isNotEmpty) ...[
          const SectionHeader('EXISTING DCs'),
          ..._existingDCs.map((ch) {
            final net = (ch['net_weight'] as num?)?.toDouble() ?? 0;
            return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.shade200)),
              child: Row(children: [
                const Icon(Icons.check_circle_outline, color: Colors.green, size: 16), const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${ch['dc_number']} — ${ch['farmer_name'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  Text('${ch['bird_count'] ?? 0} birds · ${net.toStringAsFixed(0)} kg · ${ch['crates_count'] ?? 0} crates', style: const TextStyle(fontSize: 11, color: kTextSub)),
                ])),
              ]));
          }),
          const Divider(height: 20),
          const SectionHeader('ADD ANOTHER DC'),
        ] else const SectionHeader('DC DETAILS'),

        // Source type (for additional DCs)
        if (isAdditional) SegmentedButton<String>(
          segments: const [
            ButtonSegment(value:'farm',            icon: Icon(Icons.agriculture, size: 14),       label: Text('Farm Pickup')),
            ButtonSegment(value:'shop_collection', icon: Icon(Icons.store_outlined, size: 14),     label: Text('Shop Return')),
          ],
          selected: {_srcType}, onSelectionChanged: (s) => setState(() => _srcType = s.first)),
        const SizedBox(height: 12),

        // DC Number + Date row
        Row(children: [
          Expanded(child: TextFormField(controller: _dcNum, textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'DC Number *'),
              validator: (v) => v!.trim().isEmpty ? 'Required' : null)),
          const SizedBox(width: 10),
          Expanded(child: InkWell(
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: _dcDate,
                  firstDate: DateTime.now().subtract(const Duration(days: 7)), lastDate: DateTime.now());
              if (d != null) if (mounted) setState(() => _dcDate = d);
            },
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [const Icon(Icons.calendar_today_outlined, size: 16, color: kPrimary), const SizedBox(width: 8), Text(DateFormat('d MMM y').format(_dcDate), style: const TextStyle(fontSize: 13))])),
          )),
        ]),
        const SizedBox(height: 10),

        TextFormField(controller: _farmer, textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: _srcType == 'shop_collection' ? 'Shop Name *' : 'Farmer Name *'),
            validator: (v) => v!.trim().isEmpty ? 'Required' : null),
        const SizedBox(height: 8),
        TextFormField(controller: _farmLoc, decoration: InputDecoration(labelText: _srcType == 'shop_collection' ? 'Shop Location' : 'Farm Location')),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextFormField(controller: _vehicle, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Vehicle No.'))),
          const SizedBox(width: 8),
          Expanded(child: TextFormField(controller: _driver, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Driver Name'))),
        ]),
        const SizedBox(height: 12),
        const SectionHeader('WEIGHT & BIRDS'),
        Row(children: [
          Expanded(child: TextFormField(controller: _grossWt, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Gross Weight (kg) *', suffixText: 'kg'),
              onChanged: (_) => setState(() {}),
              validator: (v) { final n = double.tryParse(v ?? ''); return (n == null || n <= 0) ? 'Required' : null; })),
          const SizedBox(width: 8),
          Expanded(child: TextFormField(controller: _emptyWt, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Empty Crate (kg)', suffixText: 'kg'),
              onChanged: (_) => setState(() {}))),
        ]),
        if (_netWt > 0) Padding(padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Text('Net Weight: ${_netWt.toStringAsFixed(2)} kg', style: const TextStyle(fontSize: 12, color: kPrimary, fontWeight: FontWeight.w700))),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextFormField(controller: _birds, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Bird Count'),
              onChanged: (_) => setState(() {}))),
          const SizedBox(width: 8),
          Expanded(child: TextFormField(controller: _crates, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Crates'))),
          const SizedBox(width: 8),
          Expanded(child: TextFormField(controller: _farmRate, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: '₹/kg', prefixText: '₹'))),
        ]),
        if (_birdCount > 0 && _netWt > 0) Padding(padding: const EdgeInsets.only(top: 6),
          child: Text('Avg: ${_avgWt.toStringAsFixed(2)} kg/bird', style: const TextStyle(fontSize: 11, color: kTextSub))),
        const SizedBox(height: 24),

        ElevatedButton(
          onPressed: _loading ? null : _saveDC,
          style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
          child: _loading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Text(isAdditional ? 'Save Additional DC' : 'Confirm Pickup & Save DC',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
        const SizedBox(height: 20),
      ]))),
    );
  }
}