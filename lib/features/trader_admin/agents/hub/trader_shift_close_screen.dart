import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_theme.dart';
import 'entry_mode_selector.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TRADER SHIFT CLOSE SCREEN
//
// Trader-assisted version of shift_close_screen.dart.
// Identical business logic, same RPC (close_delivery_shift), same reconciliation
// formula, same stock ledger queries.
//
// Differences from agent screen:
//   • p_actor_type = 'trader'
//   • EntryModeSelector shown at top
//   • BackdateField for actual_at
//   • Mortality proof photo is OPTIONAL (not blocking) — trader can't take it
//     physically; writes a note to indicate it was waived
//   • In-progress deliveries do NOT block close — RPC bypasses guard when
//     actor_type='trader' AND entry_mode != 'self'
//
// Section order mirrors shift_close_screen.dart exactly:
//   1. Entry mode + backdate
//   2. Shift summary
//   3. Delivery summary
//   4. Stock reconciliation
//   5. Return stock
//   6. Mortality + mortality-during-return
//   7. Expenses
//   8. Odometer
//
// Submit flow: INSERT expenses → call close_delivery_shift RPC
// ─────────────────────────────────────────────────────────────────────────────

class TraderShiftCloseScreen extends ConsumerStatefulWidget {
  const TraderShiftCloseScreen({
    super.key,
    required this.agentId,
    required this.agentName,
    required this.shiftId,
  });

  final String agentId;
  final String agentName;
  final String shiftId;

  @override
  ConsumerState<TraderShiftCloseScreen> createState() =>
      _TraderShiftCloseScreenState();
}

class _TraderShiftCloseScreenState
    extends ConsumerState<TraderShiftCloseScreen> {
  final _c    = Supabase.instance.client;
  final _pick = ImagePicker();

  // ── Controllers ─────────────────────────────────────────────────────────────
  final _odoEndCtrl          = TextEditingController();
  final _returnBirdsCtrl     = TextEditingController(text: '0');
  final _returnWtCtrl        = TextEditingController(text: '0');
  final _mortalityReasonCtrl = TextEditingController();
  final _mortReturnBirdsCtrl = TextEditingController(text: '0');
  final _mortReturnWtCtrl    = TextEditingController(text: '0');
  final _expAmtCtrl          = TextEditingController();
  final _expNoteCtrl         = TextEditingController();
  final _dieselCtrl          = TextEditingController(text: '0');
  final _allowanceCtrl       = TextEditingController(text: '0');
  final _tollCtrl            = TextEditingController(text: '0');

  // ── Trader-specific ──────────────────────────────────────────────────────────
  String    _entryMode = 'called';
  DateTime? _actualAt;

  // ── State ────────────────────────────────────────────────────────────────────
  bool _checking   = true;
  bool _submitting = false;

  Map<String, dynamic>? _shift;
  Map<String, dynamic>  _recon      = {};
  List<Map<String, dynamic>> _deliveries = [];

  int    _stockBirds  = 0;
  double _stockKg     = 0;
  bool   _stockLoaded = false;

  // ── Photos ───────────────────────────────────────────────────────────────────
  File?   _mortalityPhotoFile;  String? _mortalityPhotoUrl;  bool _uploadingMortality   = false;
  File?   _odoPhotoFile;        String? _odoPhotoUrl;        bool _uploadingOdo          = false;
  File?   _returnPhotoFile;     String? _returnPhotoUrl;     bool _uploadingReturn       = false;
  File?   _returnSlipFile;      String? _returnSlipUrl;      bool _uploadingReturnSlip   = false;
  File?   _mortReturnPhotoFile; String? _mortReturnPhotoUrl; bool _uploadingMortReturn   = false;

  // ── Expenses ─────────────────────────────────────────────────────────────────
  final List<Map<String, dynamic>> _expenses = [];
  String _expType = 'vehicle';

  // ── Section expand ───────────────────────────────────────────────────────────
  bool _showDelivery  = true;
  bool _showRecon     = true;
  bool _showReturn    = true;
  bool _showMortality = false;
  bool _showExpenses  = false;
  bool _showOdo       = false;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() {
    for (final c in [
      _odoEndCtrl, _returnBirdsCtrl, _returnWtCtrl, _mortalityReasonCtrl,
      _mortReturnBirdsCtrl, _mortReturnWtCtrl, _expAmtCtrl, _expNoteCtrl,
      _dieselCtrl, _allowanceCtrl, _tollCtrl,
    ]) c.dispose();
    super.dispose();
  }

  // ── Computed — identical formulas to shift_close_screen.dart ─────────────────
  int    get _dcBirds         => (_recon['dc_birds']          as num?)?.toInt()    ?? 0;
  double get _dcKg            => (_recon['dc_kg']             as num?)?.toDouble() ?? 0;
  int    get _deliveredBirds  => (_recon['delivered_birds']   as num?)?.toInt()    ?? 0;
  double get _deliveredKg     => (_recon['delivered_kg']      as num?)?.toDouble() ?? 0;
  int    get _mortalityBirds  => (_recon['mortality_birds']   as num?)?.toInt()    ?? 0;
  double get _mortalityKg     => (_recon['mortality_kg']      as num?)?.toDouble() ?? 0;
  int    get _transferInBirds => (_recon['transfer_in_birds'] as num?)?.toInt()    ?? 0;
  double get _transferInKg    => (_recon['transfer_in_kg']    as num?)?.toDouble() ?? 0;
  int    get _transferOutBirds=> (_recon['transfer_out_birds']as num?)?.toInt()    ?? 0;
  double get _transferOutKg   => (_recon['transfer_out_kg']   as num?)?.toDouble() ?? 0;
  List<String> get _transferNotes =>
      List<String>.from((_recon['transfer_notes'] as List?) ?? []);
  double get _totalCash       => (_recon['total_cash']        as num?)?.toDouble() ?? 0;
  int    get _pendingCount    => (_recon['pending_count']     as num?)?.toInt()    ?? 0;

  int    get _returnBirds      => int.tryParse(_returnBirdsCtrl.text.trim())     ?? 0;
  double get _returnWt         => double.tryParse(_returnWtCtrl.text.trim())     ?? 0;
  int    get _mortReturnBirds  => int.tryParse(_mortReturnBirdsCtrl.text.trim()) ?? 0;
  double get _mortReturnWt     => double.tryParse(_mortReturnWtCtrl.text.trim()) ?? 0;

  int    get _totalMortalityBirds => _mortalityBirds + _mortReturnBirds;
  double get _totalMortalityKg    => _mortalityKg    + _mortReturnWt;

  // Shrinkage formula — identical to shift_close_screen.dart
  double get _shrinkageKg => (_dcKg + _transferInKg - _transferOutKg
      - _deliveredKg - _totalMortalityKg - _returnWt).clamp(0.0, double.infinity);

  double get _shrinkagePct {
    final base = _dcKg + _transferInKg;
    return base > 0 ? (_shrinkageKg / base * 100) : 0.0;
  }

  int get _birdVariance => _stockBirds - (_returnBirds + _mortReturnBirds);

  double get _totalExpenses =>
      (double.tryParse(_dieselCtrl.text)    ?? 0) +
          (double.tryParse(_allowanceCtrl.text) ?? 0) +
          (double.tryParse(_tollCtrl.text)      ?? 0) +
          _expenses.fold(0.0, (s, e) => s + ((e['amount'] as num?)?.toDouble() ?? 0));

  // Reconciliation status — same thresholds as agent screen
  // Trader: mortality proof NOT blocking (agent can't physically take it)
  _RStatus get _status {
    if (!_stockLoaded)     return _RStatus.loading;
    if (_pendingCount > 0) return _RStatus.pending;
    if (_birdVariance > 5) return _RStatus.mismatch;
    if (_shrinkagePct > 5) return _RStatus.highShrinkage;
    if (_shrinkagePct > 2) return _RStatus.approvalNeeded;
    return _RStatus.balanced;
  }

  // ── Data load — identical queries to shift_close_screen.dart ─────────────────
  Future<void> _load() async {
    if (mounted) setState(() => _checking = true);

    Map<String, dynamic>? shift;
    try {
      shift = await _c
          .from('delivery_shifts')
          .select('id,status,odometer_start,odometer_start_photo,'
          'shift_start_at,opening_bird_count,opening_weight,'
          'crates_taken,crates_returned,'
          'delivery_agents(name,vehicle_no,vehicle_type)')
          .eq('id', widget.shiftId)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));
    } catch (_) {}

    if (shift == null || shift['status'] != 'open') {
      if (mounted) setState(() => _checking = false);
      return;
    }

    List<Map<String, dynamic>> deliveries = [];
    try {
      final r = await _c
          .from('deliveries')
          .select('id,status,delivered_bird_count,delivered_total_weight,'
          'collected_amount,payment_mode,mortality_birds,mortality_weight_kg,'
          'returned_birds,returned_weight,shrinkage_kg,'
          'orders(retailers(shop_name))')
          .eq('delivery_shift_id', widget.shiftId)
          .timeout(const Duration(seconds: 10));
      deliveries = List<Map<String, dynamic>>.from(r as List? ?? []);
    } catch (_) {}

    // Live stock via get_agent_dashboard
    int stockB = 0; double stockK = 0; bool stockOk = false;
    try {
      final dash = await _c.rpc('get_agent_dashboard',
          params: {'p_agent_id': widget.agentId})
          .timeout(const Duration(seconds: 10));
      final s = (dash as Map?)?.cast<String, dynamic>()?['stock'] as Map?;
      stockB = ((s?['available_birds'] as num?)?.toInt()    ?? 0).clamp(0, 999999);
      stockK = ((s?['available_kg']    as num?)?.toDouble() ?? 0).clamp(0.0, 999999.0);
      stockOk = true;
    } catch (_) {}

    // Stock ledger reconciliation — two-query approach from shift_close_screen.dart
    Map<String, dynamic> recon = {};
    try {
      final shiftDate = shift['shift_start_at'] != null
          ? DateTime.tryParse(shift['shift_start_at'] as String)
          ?.toIso8601String().split('T')[0]
          : null;

      final shiftRows = List<Map<String, dynamic>>.from(
          (await _c.from('stock_ledger')
              .select('movement_type,quantity_birds,quantity_kg,notes')
              .eq('agent_id', widget.agentId)
              .eq('shift_id', widget.shiftId)
              .timeout(const Duration(seconds: 10))) as List? ?? []);

      List<Map<String, dynamic>> transferRows = [];
      if (shiftDate != null) {
        transferRows = List<Map<String, dynamic>>.from(
            (await _c.from('stock_ledger')
                .select('movement_type,quantity_birds,quantity_kg,notes')
                .eq('agent_id', widget.agentId)
                .inFilter('movement_type', ['transferred_in', 'transferred_out'])
                .eq('entry_date', shiftDate)
                .timeout(const Duration(seconds: 10))) as List? ?? []);
      }

      int dcB = 0, delB = 0, mortB = 0, tiB = 0, toB = 0;
      double dcK = 0, delK = 0, mortK = 0, tiK = 0, toK = 0;
      final List<String> tNotes = [];
      final Set<String> seen = {};

      for (final row in [...shiftRows, ...transferRows]) {
        final mt   = row['movement_type'] as String? ?? '';
        final b    = (row['quantity_birds'] as num?)?.toInt()    ?? 0;
        final k    = (row['quantity_kg']    as num?)?.toDouble() ?? 0;
        final note = row['notes'] as String? ?? '';
        switch (mt) {
          case 'purchased':        dcB  += b; dcK  += k;
          case 'delivered':        delB += b; delK += k;
          case 'mortality':        mortB+= b; mortK+= k;
          case 'transferred_in':
            tiB += b; tiK += k;
            if (note.isNotEmpty && seen.add(note))
              tNotes.add('IN: $b birds (${k.toStringAsFixed(1)} kg) — $note');
          case 'transferred_out':
            toB += b; toK += k;
            if (note.isNotEmpty && seen.add(note))
              tNotes.add('OUT: $b birds (${k.toStringAsFixed(1)} kg) — $note');
        }
      }

      int pendCount = 0; double cash = 0;
      for (final d in deliveries) {
        if (['assigned','picked_up','out_for_delivery'].contains(d['status']))
          pendCount++;
        cash += (d['collected_amount'] as num?)?.toDouble() ?? 0;
      }

      recon = {
        'dc_birds': dcB, 'dc_kg': dcK,
        'delivered_birds': delB, 'delivered_kg': delK,
        'mortality_birds': mortB, 'mortality_kg': mortK,
        'transfer_in_birds': tiB, 'transfer_in_kg': tiK,
        'transfer_out_birds': toB, 'transfer_out_kg': toK,
        'transfer_notes': tNotes, 'total_cash': cash, 'pending_count': pendCount,
      };
    } catch (_) {}

    if (mounted) {
      setState(() {
      _shift       = shift;
      _deliveries  = deliveries;
      _recon       = recon;
      _stockBirds  = stockB;
      _stockKg     = stockK;
      _stockLoaded = stockOk;
      _checking    = false;
      // Pre-fill return fields with current stock
      if (stockB > 0 && _returnBirdsCtrl.text == '0') {
        _returnBirdsCtrl.text = '$stockB';
        _returnWtCtrl.text    = stockK.toStringAsFixed(1);
      }
      // Auto-open mortality section if shift has mortality
      if (((recon['mortality_birds'] as num?)?.toInt() ?? 0) > 0) {
        _showMortality = true;
      }
    });
    }
  }

  // ── Photo upload ─────────────────────────────────────────────────────────────
  Future<String?> _upload(File f, String folder) async {
    try {
      final path = '$folder/${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _c.storage.from('delivery-proofs').upload(path, f);
      return _c.storage.from('delivery-proofs').getPublicUrl(path);
    } catch (_) { return null; }
  }

  Future<void> _capture(String type) async {
    try {
      final p = await _pick.pickImage(
          source: ImageSource.camera, imageQuality: 70, maxWidth: 1200);
      if (p == null || !mounted) return;
      final f = File(p.path);
      switch (type) {
        case 'odo':
          setState(() { _odoPhotoFile = f; _uploadingOdo = true; });
          final u = await _upload(f, 'odometer');
          if (mounted) setState(() { _odoPhotoUrl = u; _uploadingOdo = false; });
        case 'mortality':
          setState(() { _mortalityPhotoFile = f; _uploadingMortality = true; });
          final u = await _upload(f, 'mortality');
          if (mounted) setState(() { _mortalityPhotoUrl = u; _uploadingMortality = false; });
        case 'return':
          setState(() { _returnPhotoFile = f; _uploadingReturn = true; });
          final u = await _upload(f, 'return-stock');
          if (mounted) setState(() { _returnPhotoUrl = u; _uploadingReturn = false; });
        case 'return-slip':
          setState(() { _returnSlipFile = f; _uploadingReturnSlip = true; });
          final u = await _upload(f, 'return-slip');
          if (mounted) setState(() { _returnSlipUrl = u; _uploadingReturnSlip = false; });
        case 'mort-return':
          setState(() { _mortReturnPhotoFile = f; _uploadingMortReturn = true; });
          final u = await _upload(f, 'mortality-return');
          if (mounted) setState(() { _mortReturnPhotoUrl = u; _uploadingMortReturn = false; });
      }
    } catch (_) {}
  }

  // ── Submit ────────────────────────────────────────────────────────────────────
  Future<void> _doClose() async {
    if (_shift == null) return;
    if (_odoEndCtrl.text.trim().isEmpty) {
      showError(context, 'Odometer end reading required'); return;
    }
    // Stock guard: must declare return if stock remains
    if (_stockBirds > 0 && _returnBirds == 0 && _returnWt == 0) {
      showError(context,
          '⚠️ Return stock not declared\n\n'
              '$_stockBirds birds in system stock.\n'
              'Fill the Return Stock section before closing.');
      return;
    }

    final user = ref.read(appUserProvider).valueOrNull;
    if (user?.traderId == null) return;

    final st  = _status;
    var msg = 'Delivered: $_deliveredBirds birds · ${_deliveredKg.toStringAsFixed(1)} kg\n'
        'Cash: ${Fmt.amount(_totalCash)}\n'
        'Returning: $_returnBirds birds · ${_returnWt.toStringAsFixed(1)} kg\n'
        'Expenses: ${Fmt.amount(_totalExpenses)}';
    if (_totalMortalityBirds > 0)
      msg += '\nMortality: $_totalMortalityBirds birds · '
          '${_totalMortalityKg.toStringAsFixed(2)} kg';
    if (_transferInBirds > 0 || _transferOutBirds > 0)
      msg += '\nTransfers: IN $_transferInBirds · OUT $_transferOutBirds birds';
    if (_shrinkageKg > 0.01)
      msg += '\nShrinkage: ${_shrinkageKg.toStringAsFixed(2)} kg '
          '(${_shrinkagePct.toStringAsFixed(1)}%)';
    if (_pendingCount > 0)
      msg = '⚠️ $_pendingCount deliveries still active.\n'
          'Trader override will close anyway.\n\n$msg';

    final ok = await confirmDialog(context,
        title: 'Close Shift — ${widget.agentName}',
        message: msg,
        confirmText: 'Close Shift',
        confirmColor: st == _RStatus.mismatch || st == _RStatus.highShrinkage
            ? Colors.orange : kNavy);
    if (!ok || !mounted) return;

    setState(() => _submitting = true);
    try {
      final sid = widget.shiftId;
      final tid = user!.traderId!;

      // INSERT expenses BEFORE calling RPC — identical to shift_close_screen.dart
      Future<void> ins(String type, double amt, String note) async {
        if (amt <= 0) return;
        await _c.from('delivery_expenses').insert({
          'shift_id':              sid,
          'trader_id':             tid,
          'agent_id':              widget.agentId,
          'expense_type':          type,
          'amount':                amt,
          'notes':                 note,
          'entered_by_actor_type': 'trader',
          'entered_by_actor_id':   user.userId,
        });
      }

      await ins('fuel',      double.tryParse(_dieselCtrl.text)    ?? 0, 'Diesel cost');
      await ins('allowance', double.tryParse(_allowanceCtrl.text) ?? 0, 'Agent allowance');
      await ins('toll',      double.tryParse(_tollCtrl.text)      ?? 0, 'Toll charges');
      for (final e in _expenses) {
        await ins(e['type'] as String, e['amount'] as double,
            e['notes'] as String? ?? '');
      }

      await _c.rpc('close_delivery_shift', params: {
        'p_shift_id':           sid,
        'p_odometer_end':       double.tryParse(_odoEndCtrl.text.trim()) ?? 0,
        'p_odometer_end_photo': _odoPhotoUrl,
        'p_closing_bird_count': _returnBirds,
        'p_closing_weight':     _returnWt,
        'p_expenses':           _totalExpenses,
        'p_diesel_cost':        double.tryParse(_dieselCtrl.text)    ?? 0,
        'p_allowance':          double.tryParse(_allowanceCtrl.text) ?? 0,
        // Trader actor params
        'p_actor_type':   'trader',
        'p_actor_id':     user.userId,
        'p_entry_mode':   _entryMode,
        if (_actualAt != null)
          'p_actual_at':  _actualAt!.toIso8601String(),
      });

      if (mounted) {
        showSuccess(context,
            '✅ Shift closed for ${widget.agentName}');
        if (context.canPop()) context.pop();
      }
    } catch (e) {
      if (!mounted) return;
      String raw = e.toString()
          .replaceAll('Exception: ', '')
          .replaceAll('PostgrestException(message: ', '')
          .replaceAll(RegExp(r'\)$'), '');
      if (raw.contains('unaccounted') || raw.contains('Shift close blocked')) {
        showError(context, '⚠️ Cannot close\n\n$raw');
      } else if (raw.contains('already closed')) {
        showError(context, 'Shift is already closed.');
      } else {
        showError(context, raw);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgGrey,
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
            const Text('Close Shift',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                    color: Colors.white)),
            Text('${widget.agentName} · Trader-assisted',
                style: const TextStyle(fontSize: 11,
                    color: Color(0xFFB4C6F4))),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _checking
          ? const LoadingList()
          : _shift == null
          ? _noShift()
          : Column(children: [
        _statusBar(),
        Expanded(child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
          children: [
            // ── Entry mode + backdate ─────────────────────────────
            _Card(
              title: '0. Trader Entry Details',
              icon: Icons.support_agent_rounded,
              iconColor: Colors.orange,
              expanded: true,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('HOW DID AGENT REPORT?',
                        style: TextStyle(fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: kTextHint, letterSpacing: 0.8)),
                    const SizedBox(height: 8),
                    EntryModeSelector(
                      value: _entryMode,
                      onChanged: (v) => setState(() => _entryMode = v),
                    ),
                    const SizedBox(height: 12),
                    BackdateField(
                      value: _actualAt,
                      onChanged: (v) => setState(() => _actualAt = v),
                    ),
                  ]),
            ),
            // ── Shift summary ─────────────────────────────────────
            _sec1ShiftSummary(),
            // ── Delivery summary ──────────────────────────────────
            _sec2DeliverySummary(),
            // ── Stock reconciliation ──────────────────────────────
            _sec3StockRecon(),
            // ── Return stock ──────────────────────────────────────
            _sec4ReturnStock(),
            // ── Mortality ─────────────────────────────────────────
            _sec5Mortality(),
            // ── Expenses ──────────────────────────────────────────
            _sec6Expenses(),
            // ── Odometer ──────────────────────────────────────────
            _sec7Odometer(),
            const SizedBox(height: 16),
            _closeButton(),
          ],
        )),
      ]),
    );
  }

  // ── Status bar ───────────────────────────────────────────────────────────────
  Widget _statusBar() {
    final Color bg; final String label; final IconData ic;
    switch (_status) {
      case _RStatus.balanced:
        bg = Colors.green.shade600; label = 'BALANCED — Ready to Close';
        ic = Icons.check_circle_outline;
      case _RStatus.approvalNeeded:
        bg = Colors.orange;
        label = 'APPROVAL NEEDED — Shrinkage ${_shrinkagePct.toStringAsFixed(1)}%';
        ic = Icons.pending_outlined;
      case _RStatus.highShrinkage:
        bg = Colors.red;
        label = 'HIGH SHRINKAGE — ${_shrinkagePct.toStringAsFixed(1)}% (>5%)';
        ic = Icons.warning_amber_rounded;
      case _RStatus.mismatch:
        bg = Colors.red; label = 'MISMATCH — $_birdVariance birds unaccounted';
        ic = Icons.error_outline;
      case _RStatus.pending:
        bg = Colors.orange.shade700;
        label = '$_pendingCount DELIVERIES ACTIVE (will close with trader override)';
        ic = Icons.local_shipping_outlined;
      case _RStatus.loading:
        bg = Colors.grey; label = 'Loading stock data…';
        ic = Icons.hourglass_empty_outlined;
    }
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Icon(ic, color: Colors.white, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 11,
                fontWeight: FontWeight.w700))),
      ]),
    );
  }

  // ── Section 1: Shift Summary ──────────────────────────────────────────────
  Widget _sec1ShiftSummary() {
    final agent   = (_shift!['delivery_agents'] as Map?)?.cast<String, dynamic>();
    final startAt = DateTime.tryParse(_shift!['shift_start_at'] as String? ?? '');
    final dur     = startAt != null ? DateTime.now().difference(startAt) : null;
    final durStr  = dur != null
        ? '${dur.inHours}h ${dur.inMinutes.remainder(60)}m' : '—';
    return _Card(
      title: '1. Shift Summary',
      icon: Icons.schedule_outlined, iconColor: kNavy, expanded: true,
      child: Column(children: [
        Row(children: [
          Expanded(child: _tile('Agent',   agent?['name']       as String? ?? '—', Icons.person_outline)),
          const SizedBox(width: 8),
          Expanded(child: _tile('Vehicle', agent?['vehicle_no'] as String? ?? '—', Icons.directions_car_outlined)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _tile('Started',
              startAt != null ? DateFormat('d MMM, h:mm a').format(startAt) : '—',
              Icons.play_circle_outline)),
          const SizedBox(width: 8),
          Expanded(child: _tile('Duration', durStr, Icons.timer_outlined)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _tile('Start Odo',
              '${_shift!['odometer_start'] ?? '—'} km', Icons.speed_outlined)),
          const SizedBox(width: 8),
          Expanded(child: _tile('Crates Out',
              '${_shift!['crates_taken'] ?? 0}', Icons.grid_4x4_outlined)),
        ]),
      ]),
    );
  }

  // ── Section 2: Delivery Summary ──────────────────────────────────────────
  Widget _sec2DeliverySummary() {
    final done    = _deliveries.where((d) => d['status'] == 'delivered').toList();
    final pending = _deliveries.where((d) =>
        ['assigned','picked_up','out_for_delivery'].contains(d['status'])).toList();
    final totBirds = done.fold(0, (s, d) =>
    s + ((d['delivered_bird_count'] as num?)?.toInt() ?? 0));
    final totKg    = done.fold(0.0, (s, d) =>
    s + ((d['delivered_total_weight'] as num?)?.toDouble() ?? 0));
    final totCash  = done.fold(0.0, (s, d) =>
    s + ((d['collected_amount'] as num?)?.toDouble() ?? 0));
    final totMort  = done.fold(0, (s, d) =>
    s + ((d['mortality_birds'] as num?)?.toInt() ?? 0));

    return _Card(
      title: '2. Delivery Summary',
      icon: Icons.local_shipping_outlined, iconColor: Colors.teal,
      expanded: _showDelivery,
      onToggle: () => setState(() => _showDelivery = !_showDelivery),
      badge: pending.isNotEmpty ? '${pending.length} pending' : '${done.length} done',
      badgeColor: pending.isNotEmpty ? Colors.orange : Colors.teal,
      child: Column(children: [
        Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              _kpi('Done',   '${done.length}',                          Colors.teal),
              _kpi('Birds',  '$totBirds',                               kNavy),
              _kpi('Weight', '${totKg.toStringAsFixed(1)} kg',          Colors.blue),
              _kpi('Cash',   Fmt.amount(totCash),                       Colors.green),
            ])),
        if (totMort > 0) ...[
          const SizedBox(height: 6),
          _alert(Icons.sentiment_dissatisfied_outlined,
              'Mortality: $totMort birds recorded', Colors.red),
        ],
        if (pending.isNotEmpty) ...[
          const SizedBox(height: 6),
          _alert(Icons.warning_amber_rounded,
              '${pending.length} still active — trader override will close anyway',
              Colors.orange),
        ],
        if (done.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...done.map((d) {
            final shop = (((d['orders'] as Map?)?['retailers'] as Map?)?
            ['shop_name'] as String?) ?? 'Delivery';
            final b    = (d['delivered_bird_count']   as num?)?.toInt()    ?? 0;
            final k    = (d['delivered_total_weight'] as num?)?.toDouble() ?? 0;
            final cash = (d['collected_amount']       as num?)?.toDouble() ?? 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Container(width: 5, height: 5,
                    decoration: const BoxDecoration(
                        color: Colors.teal, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(shop,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600))),
                Text('$b birds · ${k.toStringAsFixed(1)} kg · ${Fmt.amount(cash)}',
                    style: const TextStyle(fontSize: 10, color: kTextSub)),
              ]),
            );
          }),
        ],
      ]),
    );
  }

  // ── Section 3: Stock Reconciliation ──────────────────────────────────────
  Widget _sec3StockRecon() {
    final sc = _shrinkagePct > 5 ? Colors.red
        : _shrinkagePct > 2 ? Colors.orange : Colors.green;
    return _Card(
      title: '3. Stock Reconciliation',
      icon: Icons.balance_outlined, iconColor: Colors.purple,
      expanded: _showRecon,
      onToggle: () => setState(() => _showRecon = !_showRecon),
      badge: _shrinkageKg > 0.01
          ? '${_shrinkageKg.toStringAsFixed(1)} kg shrinkage' : 'Balanced',
      badgeColor: sc,
      child: Column(children: [
        _rrow('DC Loaded', '+$_dcBirds birds',
            '+${_dcKg.toStringAsFixed(1)} kg', Colors.blue, true),
        if (_transferInBirds > 0)
          _rrow('Transfer In', '+$_transferInBirds birds',
              '+${_transferInKg.toStringAsFixed(1)} kg', Colors.teal, true),
        if (_transferOutBirds > 0)
          _rrow('Transfer Out', '−$_transferOutBirds birds',
              '−${_transferOutKg.toStringAsFixed(1)} kg', Colors.indigo, false),
        _rrow('Delivered', '−$_deliveredBirds birds',
            '−${_deliveredKg.toStringAsFixed(1)} kg', kNavy, false),
        if (_mortalityBirds > 0)
          _rrow('Mortality (shift)', '−$_mortalityBirds birds',
              '−${_mortalityKg.toStringAsFixed(2)} kg', Colors.red, false),
        if (_mortReturnBirds > 0)
          _rrow('Mortality (return)', '−$_mortReturnBirds birds',
              '−${_mortReturnWt.toStringAsFixed(2)} kg', Colors.deepOrange, false),
        _rrow('Returned', '−$_returnBirds birds',
            '−${_returnWt.toStringAsFixed(1)} kg', Colors.purple, false),
        const Padding(padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1)),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: sc.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: sc.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            Icon(_shrinkagePct > 2
                ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                color: sc, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TRANSPORT SHRINKAGE', style: TextStyle(fontSize: 9,
                      fontWeight: FontWeight.w800, color: sc, letterSpacing: 0.6)),
                  Text('${_shrinkageKg.toStringAsFixed(2)} kg  '
                      '(${_shrinkagePct.toStringAsFixed(1)}%)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                          color: sc)),
                  Text('Base: ${(_dcKg + _transferInKg).toStringAsFixed(1)} kg loaded',
                      style: TextStyle(fontSize: 9, color: sc.withValues(alpha: 0.7))),
                ])),
          ]),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kBorderLight)),
          child: Row(children: [
            const Icon(Icons.egg_alt_outlined, size: 13, color: kTextSub),
            const SizedBox(width: 6),
            Expanded(child: Text(
                'Stock: $_stockBirds  ·  Returned: $_returnBirds'
                    '${_mortReturnBirds > 0 ? "  ·  Mort-return: $_mortReturnBirds" : ""}',
                style: const TextStyle(fontSize: 10, color: kTextSub))),
            Text(
                _birdVariance == 0 ? '✓ Matched'
                    : _birdVariance > 0 ? '−$_birdVariance missing'
                    : '+${-_birdVariance} extra',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    color: _birdVariance == 0 ? Colors.green
                        : _birdVariance > 5 ? Colors.red : Colors.orange)),
          ]),
        ),
        if (_transferNotes.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('TRANSFER DETAILS', style: TextStyle(fontSize: 9,
                      fontWeight: FontWeight.w800, color: Colors.teal,
                      letterSpacing: 0.6)),
                  const SizedBox(height: 4),
                  ..._transferNotes.map((n) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text('· $n', style: const TextStyle(
                          fontSize: 10, color: Colors.teal)))),
                ]),
          ),
        ],
      ]),
    );
  }

  // ── Section 4: Return Stock ───────────────────────────────────────────────
  Widget _sec4ReturnStock() {
    final declared = _returnBirds > 0 || _returnWt > 0;
    return _Card(
      title: '4. Return Stock Weighment',
      icon: Icons.assignment_return_outlined, iconColor: Colors.purple,
      expanded: _showReturn,
      onToggle: () => setState(() => _showReturn = !_showReturn),
      badge: declared ? '$_returnBirds birds'
          : _stockBirds > 0 ? 'REQUIRED' : null,
      badgeColor: declared ? Colors.purple : Colors.red,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_stockLoaded)
          Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                const Icon(Icons.info_outline, color: Colors.blue, size: 13),
                const SizedBox(width: 8),
                Expanded(child: Text(
                    'Expected return: $_stockBirds birds · '
                        '${_stockKg.toStringAsFixed(1)} kg',
                    style: const TextStyle(fontSize: 11, color: Colors.blue))),
              ])),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(
            controller: _returnBirdsCtrl,
            keyboardType: TextInputType.number,
            onChanged: (_) { if (mounted) setState(() {}); },
            decoration: InputDecoration(
                labelText: _stockBirds > 0 ? 'Returned Birds *' : 'Returned Birds',
                suffixText: 'birds'),
          )),
          const SizedBox(width: 10),
          Expanded(child: TextField(
            controller: _returnWtCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) { if (mounted) setState(() {}); },
            decoration: const InputDecoration(
                labelText: 'Weight (kg) *', suffixText: 'kg'),
          )),
        ]),
        const SizedBox(height: 10),
        _photoTile('Return Stock Photo', false,
            _returnPhotoFile, _returnPhotoUrl != null,
            _uploadingReturn, () => _capture('return')),
        const SizedBox(height: 6),
        _photoTile('Weighment Slip (optional)', false,
            _returnSlipFile, _returnSlipUrl != null,
            _uploadingReturnSlip, () => _capture('return-slip')),
      ]),
    );
  }

  // ── Section 5: Mortality ──────────────────────────────────────────────────
  Widget _sec5Mortality() {
    final hasMort = _mortalityBirds > 0;
    return _Card(
      title: '5. Mortality',
      icon: Icons.sentiment_very_dissatisfied_outlined, iconColor: Colors.red,
      expanded: _showMortality,
      onToggle: () => setState(() => _showMortality = !_showMortality),
      badge: _totalMortalityBirds > 0
          ? '$_totalMortalityBirds birds' : 'None',
      badgeColor: _totalMortalityBirds > 0 ? Colors.red : Colors.green,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (hasMort) ...[
          Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200)),
              child: Row(children: [
                _kpi('Dead Birds', '$_mortalityBirds', Colors.red),
                _kpi('Weight', '${_mortalityKg.toStringAsFixed(2)} kg', Colors.red),
              ])),
          const SizedBox(height: 8),
          TextField(
              controller: _mortalityReasonCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Mortality Reason',
                  alignLabelWithHint: true,
                  hintText: 'Disease, injury, heat stress…')),
          const SizedBox(height: 8),
          // Trader: mortality proof is OPTIONAL (not blocking)
          _photoTile('Mortality Proof Photo (optional — trader-assisted)',
              false, _mortalityPhotoFile, _mortalityPhotoUrl != null,
              _uploadingMortality, () => _capture('mortality')),
          Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200)),
              child: const Row(children: [
                Icon(Icons.info_outline, color: Colors.orange, size: 13),
                SizedBox(width: 6),
                Expanded(child: Text(
                    'Mortality photo is optional for trader-assisted close. '
                        'Agent should provide proof separately if required.',
                    style: TextStyle(fontSize: 10, color: Colors.orange))),
              ])),
        ] else
          _alert(Icons.check_circle_outline,
              'No delivery mortality recorded.', Colors.green),
        const SizedBox(height: 12),
        const Text('MORTALITY DURING RETURN', style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w800,
            color: Colors.deepOrange, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(
            controller: _mortReturnBirdsCtrl,
            keyboardType: TextInputType.number,
            onChanged: (_) { if (mounted) setState(() {}); },
            decoration: const InputDecoration(
                labelText: 'Dead Birds (return)', suffixText: 'birds'),
          )),
          const SizedBox(width: 10),
          Expanded(child: TextField(
            controller: _mortReturnWtCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) { if (mounted) setState(() {}); },
            decoration: const InputDecoration(
                labelText: 'Weight (kg)', suffixText: 'kg'),
          )),
        ]),
        if (_mortReturnBirds > 0) ...[
          const SizedBox(height: 8),
          _photoTile('Return Mortality Photo', false,
              _mortReturnPhotoFile, _mortReturnPhotoUrl != null,
              _uploadingMortReturn, () => _capture('mort-return')),
        ],
        if (_totalMortalityBirds > 0) ...[
          const SizedBox(height: 8),
          Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.2))),
              child: Row(children: [
                const Icon(Icons.summarize_outlined, color: Colors.red, size: 14),
                const SizedBox(width: 8),
                Text(
                    'Total mortality: $_totalMortalityBirds birds · '
                        '${_totalMortalityKg.toStringAsFixed(2)} kg',
                    style: const TextStyle(fontSize: 11,
                        fontWeight: FontWeight.w700, color: Colors.red)),
              ])),
        ],
      ]),
    );
  }

  // ── Section 6: Expenses ───────────────────────────────────────────────────
  Widget _sec6Expenses() => _Card(
    title: '6. Expenses',
    icon: Icons.receipt_long_outlined, iconColor: Colors.orange,
    expanded: _showExpenses,
    onToggle: () => setState(() => _showExpenses = !_showExpenses),
    badge: _totalExpenses > 0 ? Fmt.amount(_totalExpenses) : null,
    badgeColor: Colors.orange,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _expField(_dieselCtrl, '⛽ Diesel')),
        const SizedBox(width: 6),
        Expanded(child: _expField(_allowanceCtrl, '💰 Allowance')),
        const SizedBox(width: 6),
        Expanded(child: _expField(_tollCtrl, '🚧 Toll')),
      ]),
      const SizedBox(height: 10),
      ..._expenses.asMap().entries.map((e) {
        final idx = e.key; final exp = e.value;
        return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200)),
            child: Row(children: [
              Expanded(child: Text(
                  '${exp['type']}  ₹${(exp['amount'] as double).toStringAsFixed(0)}'
                      '${(exp['notes'] as String?)?.isNotEmpty == true ? "  ·  ${exp['notes']}" : ""}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
              GestureDetector(
                  onTap: () => setState(() => _expenses.removeAt(idx)),
                  child: const Icon(Icons.remove_circle_outline,
                      color: Colors.red, size: 18)),
            ]));
      }),
      Row(children: [
        Expanded(child: DropdownButtonFormField<String>(
          value: _expType,
          isDense: true,
          decoration: const InputDecoration(labelText: 'Type',
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
          items: ['vehicle','loading','misc','food','other'].map((t) =>
              DropdownMenuItem(value: t,
                  child: Text(_expLabel(t),
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => setState(() => _expType = v!),
        )),
        const SizedBox(width: 8),
        Expanded(child: TextField(
          controller: _expAmtCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount ₹', prefixText: '₹',
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
        )),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: TextField(
          controller: _expNoteCtrl,
          decoration: const InputDecoration(labelText: 'Note (optional)',
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
        )),
        const SizedBox(width: 8),
        ElevatedButton(
            style: ElevatedButton.styleFrom(
                minimumSize: const Size(52, 48), padding: EdgeInsets.zero),
            onPressed: () {
              final amt = double.tryParse(_expAmtCtrl.text.trim()) ?? 0;
              if (amt <= 0) return;
              setState(() {
                _expenses.add({'type': _expType, 'amount': amt,
                  'notes': _expNoteCtrl.text.trim()});
                _expAmtCtrl.clear(); _expNoteCtrl.clear();
              });
            },
            child: const Icon(Icons.add, size: 20)),
      ]),
      if (_totalExpenses > 0)
        Padding(padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              const Spacer(),
              Text('Total: ${Fmt.amount(_totalExpenses)}',
                  style: const TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w800, color: Colors.orange)),
            ])),
    ]),
  );

  // ── Section 7: Odometer ───────────────────────────────────────────────────
  Widget _sec7Odometer() {
    final odoStart = ((_shift!['odometer_start']) as num?)?.toDouble() ?? 0;
    final odoEnd   = double.tryParse(_odoEndCtrl.text.trim()) ?? 0;
    final km       = odoEnd > odoStart ? odoEnd - odoStart : 0.0;
    return _Card(
      title: '7. Odometer',
      icon: Icons.speed_outlined, iconColor: Colors.indigo,
      expanded: _showOdo,
      onToggle: () => setState(() => _showOdo = !_showOdo),
      badge: odoEnd > 0 ? '${km.toStringAsFixed(0)} km' : 'Required *',
      badgeColor: odoEnd > 0 ? Colors.indigo : Colors.red,
      child: Column(children: [
        Row(children: [
          Expanded(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kBorderLight)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Start Odo',
                      style: TextStyle(fontSize: 9, color: kTextHint)),
                  Text('${odoStart.toStringAsFixed(0)} km',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                ]),
          )),
          const SizedBox(width: 10),
          Expanded(child: TextField(
            controller: _odoEndCtrl,
            keyboardType: TextInputType.number,
            onChanged: (_) { if (mounted) setState(() {}); },
            decoration: const InputDecoration(
                labelText: 'End Odometer * (km)',
                prefixIcon: Icon(Icons.flag_outlined, size: 18),
                suffixText: 'km'),
          )),
        ]),
        if (km > 0) ...[
          const SizedBox(height: 8),
          Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.indigo.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                const Icon(Icons.route_outlined, color: Colors.indigo, size: 16),
                const SizedBox(width: 8),
                Text('Distance: ${km.toStringAsFixed(0)} km',
                    style: const TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w700, color: Colors.indigo)),
              ])),
        ],
        const SizedBox(height: 10),
        _photoTile('End Odometer Photo (recommended)', false,
            _odoPhotoFile, _odoPhotoUrl != null,
            _uploadingOdo, () => _capture('odo')),
      ]),
    );
  }

  // ── Close button ─────────────────────────────────────────────────────────
  Widget _closeButton() {
    final st = _status;
    final Color c;
    final String label;
    if (st == _RStatus.mismatch || st == _RStatus.highShrinkage) {
      c = Colors.red; label = '⚠️ Close Shift (Requires Trader Approval)';
    } else if (st == _RStatus.approvalNeeded) {
      c = Colors.orange; label = '⏳ Close Shift (Approval Needed)';
    } else if (st == _RStatus.pending) {
      c = Colors.orange.shade700;
      label = '⚠️ Close Shift (Override — $_pendingCount deliveries active)';
    } else {
      c = kNavy; label = '✓ Close Shift for ${widget.agentName}';
    }

    return ElevatedButton.icon(
      onPressed: (_submitting || st == _RStatus.loading) ? null : _doClose,
      icon: _submitting
          ? const SizedBox(width: 18, height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.lock_outline, size: 18),
      label: Text(label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
              color: Colors.white)),
      style: ElevatedButton.styleFrom(
          backgroundColor: c,
          minimumSize: const Size(double.infinity, 52)),
    );
  }

  // ── No shift fallback ────────────────────────────────────────────────────
  Widget _noShift() => Center(child: Column(mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.info_outline, size: 56, color: kTextHint),
        const SizedBox(height: 12),
        const Text('Shift not found or already closed',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                color: kTextSub)),
        const SizedBox(height: 24),
        ElevatedButton.icon(onPressed: _load,
            icon: const Icon(Icons.refresh), label: const Text('Retry')),
        const SizedBox(height: 12),
        OutlinedButton(
            onPressed: () => context.canPop() ? context.pop() : null,
            child: const Text('← Back')),
      ]));

  // ── Helpers ──────────────────────────────────────────────────────────────
  Widget _photoTile(String label, bool required, File? file,
      bool uploaded, bool uploading, VoidCallback onTap) {
    final Color c = uploaded ? Colors.green : required ? Colors.red : kTextHint;
    return GestureDetector(
      onTap: uploading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: uploaded ? Colors.green.shade50
                : required ? Colors.red.shade50 : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.withValues(alpha: 0.3))),
        child: Row(children: [
          file != null
              ? ClipRRect(borderRadius: BorderRadius.circular(6),
              child: Image.file(file, width: 42, height: 42, fit: BoxFit.cover))
              : Container(width: 42, height: 42,
              decoration: BoxDecoration(color: c.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.camera_alt_outlined, color: c, size: 18)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w700, color: c)),
                Text(uploading ? 'Uploading…'
                    : uploaded ? '✓ Uploaded' : 'Tap to capture',
                    style: const TextStyle(fontSize: 10, color: kTextHint)),
              ])),
          if (uploading)
            const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
          else if (uploaded)
            const Icon(Icons.check_circle, color: Colors.green, size: 16)
          else
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: c.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6)),
                child: Text('Capture', style: TextStyle(fontSize: 10,
                    color: c, fontWeight: FontWeight.w700))),
        ]),
      ),
    );
  }

  Widget _expField(TextEditingController c, String label) => TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) { if (mounted) setState(() {}); },
      decoration: InputDecoration(labelText: label, prefixText: '₹',
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10)));

  Widget _tile(String l, String v, IconData ic) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kBorderLight)),
      child: Row(children: [
        Icon(ic, size: 13, color: kTextHint), const SizedBox(width: 6),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l, style: const TextStyle(fontSize: 8, color: kTextHint)),
              Text(v, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
      ]));

  Widget _kpi(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c),
        textAlign: TextAlign.center),
    Text(l, style: const TextStyle(fontSize: 9, color: kTextHint),
        textAlign: TextAlign.center),
  ]));

  Widget _alert(IconData ic, String msg, Color c) => Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.withValues(alpha: 0.3))),
      child: Row(children: [
        Icon(ic, color: c, size: 13), const SizedBox(width: 6),
        Expanded(child: Text(msg, style: TextStyle(
            fontSize: 10, color: c, fontWeight: FontWeight.w600))),
      ]));

  Widget _rrow(String label, String birds, String kg, Color c, bool isIn) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Container(width: 4, height: 4,
                decoration: BoxDecoration(shape: BoxShape.circle, color: c)),
            const SizedBox(width: 8),
            Expanded(child: Text(label,
                style: const TextStyle(fontSize: 11, color: kTextSub))),
            Text(birds, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                color: isIn ? Colors.green.shade700 : Colors.red.shade700)),
            const SizedBox(width: 8),
            SizedBox(width: 84, child: Text(kg, textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    color: isIn ? Colors.green.shade700 : Colors.red.shade700))),
          ]));

  String _expLabel(String t) => switch (t) {
    'fuel' || 'diesel' => '⛽ Fuel', 'toll' => '🚧 Toll',
    'allowance' => '💰 Allowance', 'vehicle' => '🔧 Vehicle',
    'loading' => '📦 Loading', 'food' => '🍽 Food', _ => '📋 Misc',
  };
}

// ─────────────────────────────────────────────────────────────────────────────
enum _RStatus { balanced, approvalNeeded, highShrinkage, mismatch,
  pending, loading }

// ─────────────────────────────────────────────────────────────────────────────
class _Card extends StatelessWidget {
  const _Card({
    required this.title, required this.icon, required this.iconColor,
    required this.child, required this.expanded,
    this.onToggle, this.badge, this.badgeColor,
  });
  final String title; final IconData icon; final Color iconColor;
  final Widget child; final bool expanded;
  final VoidCallback? onToggle; final String? badge; final Color? badgeColor;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6, offset: const Offset(0, 2))]),
    child: Column(children: [
      InkWell(
          onTap: onToggle,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          child: Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(children: [
                Container(width: 30, height: 30,
                    decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8)),
                    child: Icon(icon, color: iconColor, size: 15)),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800))),
                if (badge != null)
                  Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                          color: (badgeColor ?? Colors.grey).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: (badgeColor ?? Colors.grey).withValues(alpha: 0.3))),
                      child: Text(badge!, style: TextStyle(fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: badgeColor ?? Colors.grey))),
                if (onToggle != null)
                  Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: kTextHint, size: 18),
              ]))),
      if (expanded) ...[
        const Divider(height: 1),
        Padding(padding: const EdgeInsets.all(14), child: child),
      ],
    ]),
  );
}