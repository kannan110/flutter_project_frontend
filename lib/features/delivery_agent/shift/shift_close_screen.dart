import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class ShiftCloseScreen extends ConsumerStatefulWidget {
  const ShiftCloseScreen({super.key});
  @override ConsumerState<ShiftCloseScreen> createState() => _S();
}

class _S extends ConsumerState<ShiftCloseScreen> {
  final _c             = Supabase.instance.client;
  final _odoEnd        = TextEditingController();
  final _birds         = TextEditingController(text: '0');
  final _weight        = TextEditingController(text: '0');
  final _expAmtCtrl    = TextEditingController();
  final _expNoteCtrl   = TextEditingController();
  final _dieselCtrl    = TextEditingController(text: '0');
  final _allowanceCtrl = TextEditingController(text: '0');

  bool _loading = false, _checking = true, _uploading = false;
  Map<String,dynamic>? _shift;
  Map<String,dynamic>? _summary;

  // ── Remaining stock from get_agent_dashboard ─────────────────────────────
  // BUG C1 FIX: load the agent's live stock so we can warn them they MUST
  // declare unsold birds before the DB will allow shift-close.
  int    _remainingBirds = 0;
  double _remainingKg    = 0;
  bool   _stockLoaded    = false;

  File?   _odoEndPhoto;
  String? _odoEndPhotoUrl;
  final   _picker = ImagePicker();

  final List<Map<String,dynamic>> _expenses = [];
  String _expType = 'fuel';

  double get _totalExpenses =>
      _expenses.fold(0.0, (s, e) => s + ((e['amount'] as num?)?.toDouble() ?? 0))
      + (double.tryParse(_dieselCtrl.text) ?? 0)
      + (double.tryParse(_allowanceCtrl.text) ?? 0);

  bool   get _mustDeclareUnsold => _remainingBirds > 0;
  int    get _declaredBirds     => int.tryParse(_birds.text.trim()) ?? 0;
  double get _declaredKg        => double.tryParse(_weight.text.trim()) ?? 0;
  bool   get _hasDeclaration    => _declaredBirds > 0 || _declaredKg > 0;

  @override void initState() { super.initState(); _loadShift(); }
  @override void dispose() {
    _odoEnd.dispose(); _birds.dispose(); _weight.dispose();
    _expAmtCtrl.dispose(); _expNoteCtrl.dispose();
    _dieselCtrl.dispose(); _allowanceCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadShift() async {
    final agentId = ref.read(appUserProvider).valueOrNull?.agentId;
    if (agentId == null) { if (mounted) setState(() => _checking = false); return; }
    if (mounted) setState(() => _checking = true);
    try {
      final s = await _c
          .from('delivery_shifts')
          .select('id,status,odometer_start,odometer_start_photo,shift_start_at,'
                  'total_cash_collected,total_orders,total_birds_delivered,'
                  'total_mortality,total_expenses,opening_bird_count')
          .eq('delivery_agent_id', agentId)
          .eq('status', 'open')
          .order('shift_start_at', ascending: false)
          .limit(1)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      Map<String,dynamic>? summary;
      if (s != null) {
        final pending = await _c
            .from('deliveries')
            .select('id')
            .eq('delivery_shift_id', s['id'])
            .inFilter('status', ['assigned', 'picked_up', 'out_for_delivery']);
        final delivered = await _c
            .from('deliveries')
            .select('id,delivered_bird_count,delivered_total_weight,collected_amount,mortality_birds')
            .eq('delivery_shift_id', s['id'])
            .eq('status', 'delivered');
        final dList = List<Map<String,dynamic>>.from(delivered as List? ?? []);
        summary = {
          'pending_count':   (pending as List).length,
          'delivered_count': dList.length,
          'total_birds':     dList.fold(0,   (sum, d) => sum + ((d['delivered_bird_count']   as num?)?.toInt()    ?? 0)),
          'total_weight':    dList.fold(0.0, (sum, d) => sum + ((d['delivered_total_weight']  as num?)?.toDouble() ?? 0)),
          'total_cash':      dList.fold(0.0, (sum, d) => sum + ((d['collected_amount']        as num?)?.toDouble() ?? 0)),
          'total_mortality': dList.fold(0,   (sum, d) => sum + ((d['mortality_birds']         as num?)?.toInt()    ?? 0)),
        };
      }

      // ── Load remaining agent stock ─────────────────────────────────────
      int    remainBirds = 0;
      double remainKg    = 0;
      bool   stockLoaded = false;
      try {
        final dash = await _c
            .rpc('get_agent_dashboard', params: {'p_agent_id': agentId})
            .timeout(const Duration(seconds: 10));
        final stock = (dash as Map<String,dynamic>?)?['stock'] as Map?;
        remainBirds = ((stock?['available_birds'] as num?)?.toInt()    ?? 0).clamp(0, 999999);
        remainKg    = ((stock?['available_kg']    as num?)?.toDouble() ?? 0).clamp(0.0, 999999.0);
        stockLoaded = true;
      } catch (_) {}

      if (mounted) setState(() {
        _shift          = s;
        _summary        = summary;
        _remainingBirds = remainBirds;
        _remainingKg    = remainKg;
        _stockLoaded    = stockLoaded;
        _checking       = false;
        // Pre-fill unsold birds fields with remaining stock as a convenience.
        // Agent must confirm or correct the value before submitting.
        if (remainBirds > 0 && _birds.text == '0') {
          _birds.text  = '$remainBirds';
          _weight.text = remainKg.toStringAsFixed(1);
        }
      });
    } catch (_) {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _takeEndOdoPhoto() async {
    try {
      final picked = await _picker.pickImage(
          source: ImageSource.camera, imageQuality: 70, maxWidth: 1200);
      if (picked == null || !mounted) return;
      final file = File(picked.path);
      if (mounted) setState(() { _odoEndPhoto = file; _uploading = true; });
      try {
        final path = 'odometer/end_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await _c.storage.from('delivery-proofs').upload(path, file);
        final url = _c.storage.from('delivery-proofs').getPublicUrl(path);
        if (mounted) setState(() { _odoEndPhotoUrl = url; _uploading = false; });
      } catch (_) {
        if (mounted) setState(() => _uploading = false);
      }
    } catch (_) {}
  }

  Future<void> _close() async {
    if (_odoEnd.text.trim().isEmpty) { showError(context, 'Enter odometer end reading'); return; }
    if (_shift == null)              { showError(context, 'No active shift found. Pull to refresh.'); return; }

    // ── Pre-validate before hitting DB ────────────────────────────────────
    // If the agent has stock and hasn't declared unsold birds, show a clear
    // message before the DB returns its block error string.
    if (_mustDeclareUnsold && !_hasDeclaration) {
      showError(
        context,
        '⚠️ Cannot close shift\n\n'
        '$_remainingBirds birds (${_remainingKg.toStringAsFixed(1)} kg) '
        'are still in your stock.\n\n'
        'Enter the unsold bird count in the "Unsold Birds" section above, '
        'then try again.',
      );
      return;
    }

    final pending = (_summary?['pending_count'] as int?) ?? 0;
    String msg = 'Close your shift for today?\n\n'
        'Deliveries done: ${_summary?['delivered_count'] ?? 0}\n'
        'Birds delivered: ${_summary?['total_birds'] ?? 0}\n'
        'Cash collected: ${Fmt.amount((_summary?['total_cash'] as double?) ?? 0)}';
    if (_hasDeclaration) {
      msg += '\n\nUnsold birds returning to stock: '
             '$_declaredBirds (${_declaredKg.toStringAsFixed(1)} kg)';
    }
    if (pending > 0) {
      msg = '⚠ $pending deliveries still pending!\n\n'
            'Closing shift will NOT cancel them. Admin will handle them.\n\n'
            '$msg';
    }

    final ok = await confirmDialog(context,
        title: 'Close Shift', message: msg,
        confirmText: 'Close Shift',
        confirmColor: pending > 0 ? Colors.orange : kPrimary);
    if (!ok || !mounted) return;

    if (mounted) setState(() => _loading = true);
    try {
      final tid = ref.read(appUserProvider).valueOrNull?.traderId;
      final dieselAmt = double.tryParse(_dieselCtrl.text.trim()) ?? 0;
      if (dieselAmt > 0) {
        await _c.from('delivery_expenses').insert({
          'shift_id': _shift!['id'], 'trader_id': tid,
          'expense_type': 'fuel', 'amount': dieselAmt, 'notes': 'Diesel cost',
        });
      }
      final allowAmt = double.tryParse(_allowanceCtrl.text.trim()) ?? 0;
      if (allowAmt > 0) {
        await _c.from('delivery_expenses').insert({
          'shift_id': _shift!['id'], 'trader_id': tid,
          'expense_type': 'other', 'amount': allowAmt, 'notes': 'Agent allowance',
        });
      }
      for (final exp in _expenses) {
        await _c.from('delivery_expenses').insert({
          'shift_id':     _shift!['id'], 'trader_id': tid,
          'expense_type': exp['type'], 'amount': exp['amount'], 'notes': exp['notes'],
        });
      }
      await _c.rpc('close_delivery_shift', params: {
        'p_shift_id':           _shift!['id'],
        'p_odometer_end':       double.tryParse(_odoEnd.text.trim()) ?? 0,
        'p_odometer_end_photo': _odoEndPhotoUrl,
        'p_closing_bird_count': _declaredBirds, // always pass, even 0
        'p_closing_weight':     _declaredKg,    // always pass, even 0
        'p_expenses':           _totalExpenses,
      });
      if (mounted) {
        showSuccess(context, 'Shift closed ✓ — great work today!');
        context.go(R.agentHome);
      }
    } catch (e) {
      if (!mounted) return;
      String raw = e.toString()
          .replaceAll('Exception: ', '')
          .replaceAll('PostgrestException(message: ', '')
          .replaceAll(RegExp(r'\)$'), '');
      // ── Parse the DB stock-block error into a clear friendly message ──
      if (raw.contains('Shift close blocked') || raw.contains('unaccounted')) {
        final match = RegExp(r'(\d+) birds.*?(\d+\.?\d*)\s*kg').firstMatch(raw);
        final bStr = match?.group(1) ?? '$_remainingBirds';
        final kStr = match?.group(2) ?? _remainingKg.toStringAsFixed(1);
        showError(
          context,
          '⚠️ Cannot close shift\n\n'
          '$bStr birds ($kStr kg) are still unaccounted.\n\n'
          'Fill in the "Unsold Birds" section with the birds you are '
          'returning to the stock point, then try again.',
        );
      } else {
        showError(context, raw);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
        title: const Text('Close Shift'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadShift)]),
    body: _checking
        ? const LoadingList()
        : _shift == null
            ? _buildNoShift()
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _buildSummaryCard(),
                  if ((_summary?['pending_count'] ?? 0) > 0) ...[
                    const SizedBox(height: 12), _buildPendingWarning(),
                  ],
                  const SizedBox(height: 20),
                  _buildUnsoldBirdsSection(),
                  const SizedBox(height: 20),
                  const SectionHeader('ODOMETER END READING'),
                  TextField(
                    controller: _odoEnd,
                    keyboardType: TextInputType.number,
                    autofocus: !_mustDeclareUnsold,
                    decoration: const InputDecoration(
                        labelText: 'End Reading (km) *',
                        prefixIcon: Icon(Icons.speed_outlined, size: 20),
                        suffixText: 'km')),
                  const SizedBox(height: 10),
                  _buildOdoPhotoTile(),
                  const SizedBox(height: 16),
                  const SectionHeader('DIESEL & ALLOWANCE'),
                  Row(children: [
                    Expanded(child: TextField(
                      controller: _dieselCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) { if (mounted) setState(() {}); },
                      decoration: const InputDecoration(
                          labelText: '⛽ Diesel Cost (₹)', prefixText: '₹',
                          prefixIcon: Icon(Icons.local_gas_station_outlined, size: 18)))),
                    const SizedBox(width: 12),
                    Expanded(child: TextField(
                      controller: _allowanceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) { if (mounted) setState(() {}); },
                      decoration: const InputDecoration(
                          labelText: '💰 Allowance (₹)', prefixText: '₹',
                          prefixIcon: Icon(Icons.payments_outlined, size: 18)))),
                  ]),
                  const SizedBox(height: 16),
                  const SectionHeader('OTHER EXPENSES'),
                  ..._expenses.asMap().entries.map((e) {
                    final idx = e.key; final exp = e.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade200)),
                      child: Row(children: [
                        const Icon(Icons.check_circle_outline, color: Colors.green, size: 16),
                        const SizedBox(width: 8),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${exp['type']} — ₹${(exp['amount'] as double).toStringAsFixed(0)}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          if ((exp['notes'] as String?)?.isNotEmpty == true)
                            Text(exp['notes'] as String,
                                style: const TextStyle(fontSize: 11, color: kTextSub)),
                        ])),
                        GestureDetector(
                            onTap: () => setState(() => _expenses.removeAt(idx)),
                            child: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20)),
                      ]));
                  }),
                  if (_expenses.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(bottom: 8),
                        child: Text('Total Expenses: ₹${_totalExpenses.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kPrimary))),
                  Row(children: [
                    Expanded(flex: 2, child: DropdownButtonFormField<String>(
                      value: _expType,
                      decoration: const InputDecoration(labelText: 'Type',
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                      items: const [
                        DropdownMenuItem(value: 'fuel',    child: Text('⛽ Fuel')),
                        DropdownMenuItem(value: 'toll',    child: Text('🚧 Toll')),
                        DropdownMenuItem(value: 'parking', child: Text('🅿️ Parking')),
                        DropdownMenuItem(value: 'food',    child: Text('🍽 Food')),
                        DropdownMenuItem(value: 'other',   child: Text('📦 Other')),
                      ],
                      onChanged: (v) => setState(() => _expType = v!))),
                    const SizedBox(width: 8),
                    Expanded(flex: 2, child: TextField(controller: _expAmtCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Amount (₹)', prefixText: '₹'))),
                    const SizedBox(width: 8),
                    Expanded(flex: 2, child: TextField(controller: _expNoteCtrl,
                        decoration: const InputDecoration(labelText: 'Note (opt.)'))),
                    const SizedBox(width: 8),
                    ElevatedButton(
                        style: ElevatedButton.styleFrom(minimumSize: const Size(44, 44), padding: EdgeInsets.zero),
                        onPressed: () {
                          final amt = double.tryParse(_expAmtCtrl.text.trim()) ?? 0;
                          if (amt <= 0) return;
                          setState(() {
                            _expenses.add({'type': _expType, 'amount': amt, 'notes': _expNoteCtrl.text.trim()});
                            _expAmtCtrl.clear(); _expNoteCtrl.clear();
                          });
                        },
                        child: const Icon(Icons.add, size: 20)),
                  ]),
                  const SizedBox(height: 28),
                  ElevatedButton.icon(
                    onPressed: (_loading || _uploading) ? null : _close,
                    icon: _loading
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.lock_outline, size: 18),
                    label: const Text('Close Shift',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(backgroundColor: kError)),
                  const SizedBox(height: 20),
                ])));

  // ── UNSOLD BIRDS — C1 + U1 FIX ───────────────────────────────────────────
  Widget _buildUnsoldBirdsSection() {
    final hasStock = _remainingBirds > 0;
    final declared = _hasDeclaration;

    return Container(
      decoration: BoxDecoration(
          color: hasStock ? (declared ? Colors.green.shade50 : Colors.red.shade50) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: hasStock ? (declared ? Colors.green.shade300 : Colors.red.shade400) : Colors.grey.shade300,
              width: hasStock ? 1.5 : 1)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
              color: hasStock ? (declared ? Colors.green.shade100 : Colors.red.shade100) : Colors.grey.shade100,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13))),
          child: Row(children: [
            Icon(
                hasStock ? (declared ? Icons.check_circle : Icons.warning_amber_rounded)
                         : Icons.inventory_2_outlined,
                color: hasStock ? (declared ? Colors.green : Colors.red) : Colors.grey,
                size: 20),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                hasStock
                    ? (declared ? 'Unsold Birds Declared ✓' : '⚠️ REQUIRED: Declare Unsold Birds')
                    : 'Unsold Birds (Returning to Stock)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                    color: hasStock ? (declared ? Colors.green.shade700 : Colors.red.shade700) : Colors.grey.shade700)),
              if (hasStock && !declared)
                Text('You have $_remainingBirds birds in stock. Declare before closing.',
                    style: TextStyle(fontSize: 11, color: Colors.red.shade600)),
              if (!hasStock && _stockLoaded)
                const Text('No unsold birds in stock — good to close.',
                    style: TextStyle(fontSize: 11, color: kTextSub)),
            ])),
            if (_stockLoaded && _remainingBirds > 0)
              Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: declared ? Colors.green : Colors.red,
                      borderRadius: BorderRadius.circular(8)),
                  child: Text('$_remainingBirds birds\n${_remainingKg.toStringAsFixed(1)} kg',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800))),
          ])),

        Padding(padding: const EdgeInsets.all(14), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (hasStock)
            Padding(padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                    child: const Row(children: [
                      Icon(Icons.info_outline, color: Colors.blue, size: 14),
                      SizedBox(width: 8),
                      Expanded(child: Text(
                          'Enter the birds you are physically returning to the stock point. '
                          'They will be credited back to in-house stock.',
                          style: TextStyle(fontSize: 11, color: Colors.blue))),
                    ]))),
          Row(children: [
            Expanded(child: TextField(
              controller: _birds,
              keyboardType: TextInputType.number,
              autofocus: hasStock, // focus here when stock needs declaring
              onChanged: (_) { if (mounted) setState(() {}); },
              decoration: InputDecoration(
                  labelText: hasStock ? 'Unsold Birds * (Required)' : 'Unsold Birds',
                  suffixText: 'birds',
                  labelStyle: TextStyle(color: hasStock && !declared ? Colors.red : null),
                  focusedBorder: hasStock && !declared
                      ? OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.red, width: 1.5))
                      : null))),
            const SizedBox(width: 12),
            Expanded(child: TextField(
              controller: _weight,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) { if (mounted) setState(() {}); },
              decoration: InputDecoration(
                  labelText: hasStock ? 'Weight (kg) * (Required)' : 'Weight (kg)',
                  suffixText: 'kg',
                  labelStyle: TextStyle(color: hasStock && !declared ? Colors.red : null)))),
          ]),
          if (hasStock && !declared)
            Padding(padding: const EdgeInsets.only(top: 8),
                child: Text('* Shift close will be blocked until this is filled.',
                    style: TextStyle(fontSize: 11, color: Colors.red.shade600, fontWeight: FontWeight.w600))),
          if (declared)
            Padding(padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 14),
                  const SizedBox(width: 6),
                  Text('$_declaredBirds birds (${_declaredKg.toStringAsFixed(1)} kg) will be returned to stock.',
                      style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600)),
                ])),
        ])),
      ]));
  }

  Widget _buildSummaryCard() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
        color: kPrimary.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kPrimary.withValues(alpha: 0.2))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.radio_button_on, color: kPrimary, size: 14),
        const SizedBox(width: 6),
        const Text('SHIFT ACTIVE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kPrimary, letterSpacing: 1)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _stat('Deliveries', '${_summary?['delivered_count'] ?? 0}', kPrimary),
        _stat('Birds',      '${_summary?['total_birds'] ?? 0}',     Colors.teal),
        _stat('Cash',       Fmt.amount((_summary?['total_cash'] as double?) ?? 0), Colors.green),
        _stat('Mortality',  '${_summary?['total_mortality'] ?? 0}',
            (_summary?['total_mortality'] as int? ?? 0) > 0 ? Colors.red : kTextHint),
      ]),
      const SizedBox(height: 8),
      Text('Start odometer: ${_shift!['odometer_start'] ?? '—'} km',
          style: const TextStyle(fontSize: 12, color: kTextSub)),
    ]));

  Widget _buildPendingWarning() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade200)),
    child: Row(children: [
      const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
      const SizedBox(width: 8),
      Expanded(child: Text('${_summary!['pending_count']} deliveries still pending.',
          style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w600))),
      TextButton(onPressed: () => context.go(R.agentDeliveries), child: const Text('View →')),
    ]));

  Widget _buildOdoPhotoTile() => GestureDetector(
    onTap: _uploading ? null : _takeEndOdoPhoto,
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: _odoEndPhoto != null ? Colors.green.shade50 : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _odoEndPhoto != null ? Colors.green.shade300 : Colors.grey.shade300)),
      child: Row(children: [
        if (_odoEndPhoto != null)
          ClipRRect(borderRadius: BorderRadius.circular(6),
              child: Image.file(_odoEndPhoto!, width: 48, height: 48, fit: BoxFit.cover))
        else
          const Icon(Icons.camera_alt_outlined, size: 36, color: kTextHint),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_odoEndPhoto != null ? 'End odometer photo captured' : 'Take End Odometer Photo',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: _odoEndPhoto != null ? Colors.green : kTextSub)),
          Text(_uploading ? 'Uploading...' : _odoEndPhotoUrl != null ? '✓ Uploaded' : 'Optional — recommended for audit',
              style: const TextStyle(fontSize: 11, color: kTextHint)),
        ])),
        if (_uploading)
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
        else if (_odoEndPhotoUrl != null)
          const Icon(Icons.check_circle, color: Colors.green, size: 20)
        else
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: kPrimary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
              child: const Text('Capture', style: TextStyle(fontSize: 12, color: kPrimary, fontWeight: FontWeight.w700))),
      ])));

  Widget _buildNoShift() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.info_outline, size: 56, color: kTextHint),
    const SizedBox(height: 12),
    const Text('No active shift found',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kTextSub)),
    const SizedBox(height: 6),
    const Text('You need an open shift to close one.',
        style: TextStyle(fontSize: 13, color: kTextHint)),
    const SizedBox(height: 24),
    ElevatedButton.icon(onPressed: _loadShift, icon: const Icon(Icons.refresh), label: const Text('Retry')),
    const SizedBox(height: 12),
    OutlinedButton(onPressed: () => context.go(R.agentHome), child: const Text('Go to Home')),
  ]));

  Widget _stat(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c)),
    Text(l, style: const TextStyle(fontSize: 10, color: kTextHint), textAlign: TextAlign.center),
  ]));
}
