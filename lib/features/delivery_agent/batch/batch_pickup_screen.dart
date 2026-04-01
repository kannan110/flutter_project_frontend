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

  DateTime _dcDate  = DateTime.now();
  // FIX: source type toggle for ALL DCs (first and additional)
  String _srcType   = 'farm';
  bool _loading = false, _dataLoading = true;
  Map<String,dynamic>? _batch, _shift;
  List<Map<String,dynamic>> _existingDCs = [];
  List<Map<String,dynamic>> _deliveries  = [];

  @override void initState() { super.initState(); _load(); }
  @override void dispose() {
    for (final c in [_dcNum,_farmer,_farmLoc,_vehicle,_driver,
                     _grossWt,_emptyWt,_birds,_crates,_farmRate]) c.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final agentId = ref.read(appUserProvider).valueOrNull?.agentId;
    if (mounted) setState(() => _dataLoading = true);

    // FIX: each query independent with own try/catch — same fix as agent_home
    Map<String,dynamic>? batch;
    try {
      batch = await _c
          .from('delivery_batches')
          .select('*,delivery_agents(id,name,vehicle_no,phone)')
          .eq('id', widget.batchId)
          .maybeSingle();
    } catch (_) {}

    // FIX: shift query isolated — prevents silent null from shared try/catch
    Map<String,dynamic>? shift;
    try {
      if (agentId != null) {
        shift = await _c
            .from('delivery_shifts')
            .select('id,status,shift_start_at')
            .eq('delivery_agent_id', agentId)
            .eq('status', 'open')
            .maybeSingle();
      }
    } catch (_) {}

    List<Map<String,dynamic>> dcs = [];
    try {
      final raw = await _c
          .from('delivery_challans')
          .select('id,dc_number,dc_date,farmer_name,farm_location,'
                  'bird_count,gross_weight,empty_weight,net_weight,'
                  'crates_count,farm_rate,source_type')
          .eq('batch_id', widget.batchId)
          .order('created_at');
      dcs = List<Map<String,dynamic>>.from(raw as List? ?? []);
    } catch (_) {}

    List<Map<String,dynamic>> deliveries = [];
    try {
      final raw = await _c
          .from('deliveries')
          .select('id,status,orders(id,estimated_birds,total_quantity,'
                  'retailers(shop_name,address,phone))')
          .eq('batch_id', widget.batchId);
      deliveries = List<Map<String,dynamic>>.from(raw as List? ?? []);
    } catch (_) {}

    // Pre-fill vehicle from agent profile
    if (batch?['delivery_agents']?['vehicle_no'] != null && _vehicle.text.isEmpty) {
      _vehicle.text = batch!['delivery_agents']['vehicle_no'] as String;
    }

    if (mounted) setState(() {
      _batch       = batch;
      _shift       = shift;
      _existingDCs = dcs;
      _deliveries  = deliveries;
      _dataLoading = false;
    });
  }

  double get _grossWtVal => double.tryParse(_grossWt.text.trim()) ?? 0;
  double get _emptyWtVal => double.tryParse(_emptyWt.text.trim()) ?? 0;
  double get _netWt      => (_grossWtVal - _emptyWtVal).clamp(0, double.infinity);
  int    get _birdCount  => int.tryParse(_birds.text.trim()) ?? 0;
  double get _avgWt      => _birdCount > 0 && _netWt > 0 ? _netWt / _birdCount : 0;

  int    get _totalDcBirds  => _existingDCs.fold(0,   (s, c) => s + ((c['bird_count']  as num?)?.toInt()    ?? 0)) + _birdCount;
  double get _totalDcWeight => _existingDCs.fold(0.0, (s, c) => s + ((c['net_weight']  as num?)?.toDouble() ?? 0)) + _netWt;
  int    get _expectedBirds => _deliveries.where((d) => d['status'] != 'cancelled')
      .fold(0, (s, d) => s + (((d['orders'] as Map?)?.cast<String,dynamic>()?['estimated_birds'] as num?)?.toInt() ?? 0));
  double get _expectedWeight => _deliveries.where((d) => d['status'] != 'cancelled')
      .fold(0.0, (s, d) => s + (((d['orders'] as Map?)?.cast<String,dynamic>()?['total_quantity'] as num?)?.toDouble() ?? 0));

  Future<void> _saveDC() async {
    if (!_form.currentState!.validate()) return;
    if (_dcNum.text.trim().isEmpty)  { showError(context, 'Enter DC number'); return; }
    if (_farmer.text.trim().isEmpty) { showError(context, 'Enter ${_srcType == "farm" ? "Farmer" : "Source"} name'); return; }
    if (_grossWtVal <= 0)            { showError(context, 'Enter gross weight (must be > 0)'); return; }

    final bStatus      = _batch?['status'] as String? ?? 'assigned';
    final isFirstPickup = bStatus == 'assigned';

    if (isFirstPickup && _shift == null) {
      showError(context, 'No active shift. Open a shift first then come back.');
      return;
    }

    if (mounted) setState(() => _loading = true);
    try {
      // FIX: always pass empty_weight as double (never null) — DB has NOT NULL constraint
      final emptyWt = _emptyWtVal; // already defaults to 0.0

      if (isFirstPickup) {
        // Step 1: Record DC and move batch to picked_up
        // pickup_batch exact signature: no p_source_type param
        await _c.rpc('pickup_batch', params: {
          'p_batch_id':       widget.batchId,
          'p_shift_id':       _shift!['id'],
          'p_dc_number':      _dcNum.text.trim(),
          'p_dc_date':        _dcDate.toIso8601String().split('T')[0],
          'p_farmer_name':    _farmer.text.trim(),
          'p_farm_location':  _farmLoc.text.trim().isEmpty ? null : _farmLoc.text.trim(),
          'p_vehicle_number': _vehicle.text.trim().isEmpty ? null : _vehicle.text.trim(),
          'p_driver_name':    _driver.text.trim().isEmpty  ? null : _driver.text.trim(),
          'p_supervisor_name': null,
          'p_gross_weight':   _grossWtVal,
          'p_empty_weight':   emptyWt,
          'p_net_weight':     _netWt,
          'p_avg_weight':     _avgWt > 0 ? _avgWt : 0.0,
          'p_bird_count':     _birdCount,
          'p_weak_birds':     0,
          'p_crates_count':   int.tryParse(_crates.text.trim()) ?? 0,
          'p_farm_rate':      _farmRate.text.trim().isEmpty ? null : double.tryParse(_farmRate.text.trim()),
          'p_in_time':        null,
          'p_out_time':       null,
          'p_dc_photo_url':   null,
        });

        // Step 2: CRITICAL — advance all deliveries picked_up → out_for_delivery
        // DB trigger blocks: picked_up → delivered directly
        // start_batch_delivery moves batch + all deliveries to out_for_delivery
        await _c.rpc('start_batch_delivery', params: {'p_batch_id': widget.batchId});

        if (mounted) {
          showSuccess(context, 'DC saved ✓ — ready to deliver!');
          if (context.canPop()) context.pop();
          else context.go(R.agentHome);
        }
      } else {
        // add_batch_dc exact signature: has p_source_type, p_bird_count int DEFAULT 0
        await _c.rpc('add_batch_dc', params: {
          'p_batch_id':       widget.batchId,
          'p_dc_number':      _dcNum.text.trim(),
          'p_dc_date':        _dcDate.toIso8601String().split('T')[0],
          'p_farmer_name':    _farmer.text.trim(),
          'p_farm_location':  _farmLoc.text.trim().isEmpty ? null : _farmLoc.text.trim(),
          'p_vehicle_number': _vehicle.text.trim().isEmpty ? null : _vehicle.text.trim(),
          'p_gross_weight':   _grossWtVal,
          'p_empty_weight':   emptyWt,
          'p_net_weight':     _netWt,
          'p_avg_weight':     _avgWt > 0 ? _avgWt : 0.0,
          'p_bird_count':     _birdCount,        // int DEFAULT 0 — always pass int
          'p_crates_count':   int.tryParse(_crates.text.trim()) ?? 0,
          'p_farm_rate':      _farmRate.text.trim().isEmpty ? null : double.tryParse(_farmRate.text.trim()),
          'p_source_type':    _srcType,
        });
        if (mounted) {
          showSuccess(context, 'DC added ✓');
          _clearForm();
          _load();
        }
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString()
            .replaceAll('Exception: ', '')
            .replaceAll('PostgrestException(message: ', '')
            .replaceAll(')', '');
        showError(context, msg);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _clearForm() {
    _dcNum.clear(); _farmer.clear(); _farmLoc.clear();
    _birds.clear(); _farmRate.clear(); _grossWt.clear();
    _emptyWt.text = '0'; _crates.text = '0';
    if (mounted) setState(() { _dcDate = DateTime.now(); });
  }

  @override
  Widget build(BuildContext context) {
    if (_dataLoading) return Scaffold(
      appBar: AppBar(title: const Text('Add DC')),
      body: const LoadingList());

    final a            = _batch?['delivery_agents'] as Map<String,dynamic>?;
    final bStatus      = _batch?['status'] as String? ?? 'assigned';
    final isAdditional = bStatus != 'assigned';

    return Scaffold(
      appBar: AppBar(
        // FIX: explicit back button always present
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) context.pop();
            else context.go(R.agentHome);
          }),
        title: Text(isAdditional ? 'Add DC — Additional Pickup' : 'Farm Pickup — Create DC'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(key: _form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

          // ── Batch info card ──────────────────────────────────
          WhiteCard(child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a?['name'] as String? ?? '—',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              Text('Vehicle: ${_batch?['vehicle_no'] ?? a?['vehicle_no'] ?? '—'}',
                  style: const TextStyle(fontSize: 11, color: kTextSub)),
            ])),
            StatusBadge(bStatus, SC.order(bStatus)),
          ])),
          const SizedBox(height: 12),

          // ── Shift status ─────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: _shift != null ? Colors.green.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _shift != null ? Colors.green.shade200 : Colors.red.shade200)),
            child: Row(children: [
              Icon(_shift != null ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                  color: _shift != null ? Colors.green : Colors.red, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(
                _shift != null ? 'Shift active ✓ — ready to add DC' : 'No active shift! Open a shift first.',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: _shift != null ? Colors.green.shade700 : Colors.red))),
              if (_shift == null)
                TextButton(
                  onPressed: () {
                    if (context.canPop()) context.pop();
                    context.go(R.shiftOpen);
                  },
                  child: const Text('Open Shift →',
                      style: TextStyle(fontWeight: FontWeight.w700))),
            ])),
          const SizedBox(height: 12),

          // ── Orders in batch ──────────────────────────────────
          if (_deliveries.isNotEmpty) ...[
            const SectionHeader('ORDERS IN THIS BATCH'),
            WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  _miniStat('Expected Birds',  '$_expectedBirds',                          Colors.blue),
                  _miniStat('Expected Weight', '${_expectedWeight.toStringAsFixed(0)} kg', Colors.teal),
                  _miniStat('Orders',          '${_deliveries.where((d) => d['status'] != 'cancelled').length}', kPrimary),
                ])),
              ..._deliveries.where((d) => d['status'] != 'cancelled').map((d) {
                final o = d['orders'] as Map<String,dynamic>?;
                final r = o?['retailers'] as Map<String,dynamic>?;
                final birds  = (o?['estimated_birds'] as num?)?.toInt()    ?? 0;
                final weight = (o?['total_quantity']  as num?)?.toDouble() ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    const Icon(Icons.store_outlined, size: 13, color: kPrimary),
                    const SizedBox(width: 6),
                    Expanded(child: Text(r?['shop_name'] as String? ?? '—',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                    Text(
                      '${birds > 0 ? '$birds birds' : ''}${birds > 0 && weight > 0 ? ' · ' : ''}${weight > 0 ? '${weight.toStringAsFixed(0)} kg' : ''}',
                      style: const TextStyle(fontSize: 11, color: kTextSub)),
                  ]));
              }),
            ])),
            const SizedBox(height: 12),
          ],

          // ── Existing DCs ─────────────────────────────────────
          if (_existingDCs.isNotEmpty) ...[
            const SectionHeader('EXISTING DCs'),
            ..._existingDCs.map((ch) {
              final net    = (ch['net_weight']  as num?)?.toDouble() ?? 0;
              final birds  = (ch['bird_count']  as num?)?.toInt()    ?? 0;
              final crates = (ch['crates_count'] as num?)?.toInt()   ?? 0;
              final src    = ch['source_type'] as String? ?? 'farm';
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200)),
                child: Row(children: [
                  const Icon(Icons.check_circle_outline, color: Colors.green, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${ch['dc_number'] ?? '—'} — ${ch['farmer_name'] ?? '—'}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                    Text('$birds birds · ${net.toStringAsFixed(1)} kg · $crates crates · $src',
                        style: const TextStyle(fontSize: 11, color: kTextSub)),
                  ])),
                ]));
            }),
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                const Icon(Icons.summarize_outlined, size: 14, color: kPrimary),
                const SizedBox(width: 6),
                Expanded(child: Text(
                  'Total picked up: '
                  '${_existingDCs.fold(0, (s, c) => s + ((c['bird_count'] as num?)?.toInt() ?? 0))} birds · '
                  '${_existingDCs.fold(0.0, (s, c) => s + ((c['net_weight'] as num?)?.toDouble() ?? 0)).toStringAsFixed(1)} kg',
                  style: const TextStyle(fontSize: 12, color: kPrimary, fontWeight: FontWeight.w700))),
              ])),
            const Divider(height: 20),
          ],

          // ── New DC section header ────────────────────────────
          Text(
            _existingDCs.isEmpty ? '📋 DC DETAILS' : '📋 ADD ANOTHER DC',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                color: kTextHint, letterSpacing: 0.8)),
          const SizedBox(height: 10),

          // FIX: Source type toggle for ALL DCs (first AND additional)
          const Text('Source Type', style: TextStyle(fontSize: 11, color: kTextHint, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                  value: 'farm',
                  icon: Icon(Icons.agriculture, size: 14),
                  label: Text('Farm')),
              ButtonSegment(
                  value: 'shop_collection',
                  icon: Icon(Icons.store_outlined, size: 14),
                  label: Text('Shop')),
              ButtonSegment(
                  value: 'inhouse_stock',
                  icon: Icon(Icons.warehouse_outlined, size: 14),
                  label: Text('In-House')),
            ],
            selected: {_srcType},
            onSelectionChanged: (s) => setState(() => _srcType = s.first)),
          const SizedBox(height: 12),

          // ── DC Number + Date ─────────────────────────────────
          Row(children: [
            Expanded(child: TextFormField(
              controller: _dcNum,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'DC Number *'),
              validator: (v) => v!.trim().isEmpty ? 'Required' : null)),
            const SizedBox(width: 10),
            Expanded(child: InkWell(
              onTap: () async {
                final d = await showDatePicker(
                    context: context,
                    initialDate: _dcDate,
                    firstDate: DateTime.now().subtract(const Duration(days: 7)),
                    lastDate: DateTime.now());
                if (d != null && mounted) setState(() => _dcDate = d);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                decoration: BoxDecoration(color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Icon(Icons.calendar_today_outlined, size: 16, color: kPrimary),
                  const SizedBox(width: 8),
                  Text(DateFormat('d MMM y').format(_dcDate),
                      style: const TextStyle(fontSize: 13)),
                ])))),
          ]),
          const SizedBox(height: 10),

          TextFormField(
            controller: _farmer,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
                labelText: _srcType == 'shop_collection'
                    ? 'Shop Name *'
                    : _srcType == 'inhouse_stock'
                        ? 'Stock Point Name *'
                        : 'Farmer Name *',
                prefixIcon: Icon(
                    _srcType == 'farm'
                        ? Icons.agriculture
                        : _srcType == 'shop_collection'
                            ? Icons.store_outlined
                            : Icons.warehouse_outlined,
                    size: 18, color: kPrimary)),
            validator: (v) => v!.trim().isEmpty ? 'Required' : null),
          const SizedBox(height: 8),
          TextFormField(
            controller: _farmLoc,
            decoration: InputDecoration(
                labelText: _srcType == 'shop_collection'
                    ? 'Shop Location (optional)'
                    : _srcType == 'inhouse_stock'
                        ? 'Storage Location (optional)'
                        : 'Farm Location (optional)')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextFormField(
              controller: _vehicle,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Vehicle No.'))),
            const SizedBox(width: 8),
            Expanded(child: TextFormField(
              controller: _driver,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Driver Name'))),
          ]),
          const SizedBox(height: 16),

          // ── Weight & Birds ───────────────────────────────────
          const SectionHeader('WEIGHT & BIRDS'),
          Row(children: [
            Expanded(child: TextFormField(
              controller: _grossWt,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Gross Weight (kg) *', suffixText: 'kg'),
              onChanged: (_) => setState(() {}),
              validator: (v) {
                final n = double.tryParse(v?.trim() ?? '');
                return (n == null || n <= 0) ? 'Enter gross weight' : null;
              })),
            const SizedBox(width: 8),
            Expanded(child: TextFormField(
              controller: _emptyWt,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Empty Crates (kg)', suffixText: 'kg'),
              onChanged: (_) => setState(() {}))),
          ]),

          // Live net weight display
          if (_grossWtVal > 0) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: _netWt > 0 ? Colors.green.shade50 : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Icon(Icons.balance_outlined,
                    size: 14, color: _netWt > 0 ? Colors.green : Colors.orange),
                const SizedBox(width: 8),
                Text(
                  'Net = ${_grossWtVal.toStringAsFixed(2)} − ${_emptyWtVal.toStringAsFixed(2)} = ${_netWt.toStringAsFixed(2)} kg',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700,
                      color: _netWt > 0 ? Colors.green.shade700 : Colors.orange)),
              ]))),
          const SizedBox(height: 8),

          Row(children: [
            Expanded(child: TextFormField(
              controller: _birds,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Bird Count', suffixText: 'birds'),
              onChanged: (_) => setState(() {}))),
            const SizedBox(width: 8),
            Expanded(child: TextFormField(
              controller: _crates,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Crates'))),
            const SizedBox(width: 8),
            Expanded(child: TextFormField(
              controller: _farmRate,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Rate (₹/kg)', prefixText: '₹'))),
          ]),

          if (_birdCount > 0 && _netWt > 0) Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Avg: ${_avgWt.toStringAsFixed(3)} kg/bird',
                style: const TextStyle(fontSize: 11, color: kTextSub))),

          // Running total vs expected
          if (_expectedBirds > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade100)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Running Total (this DC + previous):',
                    style: TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Row(children: [
                  _miniStat('DC Birds',    '$_totalDcBirds',                          Colors.blue),
                  _miniStat('DC Weight',   '${_totalDcWeight.toStringAsFixed(1)} kg', Colors.teal),
                  _miniStat('Need Birds',  '$_expectedBirds',                         kPrimary),
                  _miniStat('Need Weight', '${_expectedWeight.toStringAsFixed(0)} kg', kPrimary),
                ]),
                if (_totalDcBirds < _expectedBirds && _totalDcBirds > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('⚠ ${_expectedBirds - _totalDcBirds} birds still needed',
                        style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w600))),
                if (_totalDcBirds >= _expectedBirds && _expectedBirds > 0)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('✓ Sufficient birds for all orders',
                        style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600))),
              ])),
          ],
          const SizedBox(height: 24),

          ElevatedButton(
            onPressed: (_loading || _shift == null && !isAdditional) ? null : _saveDC,
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
            child: _loading
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : Text(
                    isAdditional ? 'Save Additional DC' : 'Confirm Pickup & Save DC',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
          const SizedBox(height: 20),
        ])),
      ),
    );
  }

  Widget _miniStat(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c)),
    Text(l, style: const TextStyle(fontSize: 9, color: kTextHint), textAlign: TextAlign.center),
  ]));
}
