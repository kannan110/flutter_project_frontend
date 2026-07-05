import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/providers/ui_mode_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

// =============================================================================
// SHIFT CLOSE  —  Enterprise Reconciliation & Audit System
//
// Sections:
//   1. Shift Summary         timing · agent · vehicle · duration
//   2. Delivery Summary      orders · birds · weight · pending · cash
//   3. Stock Reconciliation  DC in vs delivered+mortality+return = shrinkage
//   4. Return Stock          actual birds being physically returned
//   5. Mortality             dead birds · weight · reason · proof
//   6. Expenses              diesel · allowance · toll · misc + receipts
//   7. Odometer & Vehicle    start/end · photo · km auto-calculated
//
// Reconciliation Status bar (always visible):
//   BALANCED  |  APPROVAL NEEDED  |  HIGH SHRINKAGE  |  MISMATCH  |  PENDING
// =============================================================================
class ShiftCloseScreen extends ConsumerStatefulWidget {
  const ShiftCloseScreen({super.key});

  @override
  ConsumerState<ShiftCloseScreen> createState() => _S();
}

class _S extends ConsumerState<ShiftCloseScreen> {
  final _c = Supabase.instance.client;
  final _pick = ImagePicker();

  // Controllers
  final _odoEndCtrl = TextEditingController();
  final _returnBirdsCtrl = TextEditingController(text: '0');
  final _returnWtCtrl = TextEditingController(text: '0');
  final _mortalityReasonCtrl = TextEditingController();
  final _mortReturnBirdsCtrl = TextEditingController(text: '0');
  final _mortReturnWtCtrl = TextEditingController(text: '0');
  final _expAmtCtrl = TextEditingController();
  final _expNoteCtrl = TextEditingController();
  final _dieselCtrl = TextEditingController(text: '0');
  final _allowanceCtrl = TextEditingController(text: '0');
  final _tollCtrl = TextEditingController(text: '0');

  // State
  bool _checking = true, _submitting = false;
  Map<String, dynamic>? _shift;
  Map<String, dynamic> _recon = {};
  List<Map<String, dynamic>> _deliveries = [];

  // Agent stock (live, from get_agent_dashboard)
  int _stockBirds = 0;
  double _stockKg = 0;
  bool _stockLoaded = false;

  // Photos
  File? _mortalityPhotoFile;
  String? _mortalityPhotoUrl;
  bool _uploadingMortality = false;
  File? _odoPhotoFile;
  String? _odoPhotoUrl;
  bool _uploadingOdo = false;
  File? _returnPhotoFile;
  String? _returnPhotoUrl;
  bool _uploadingReturn = false;

  // Weighment slip photos (for audit trail)
  File? _returnSlipFile;
  String? _returnSlipUrl;
  bool _uploadingReturnSlip = false;
  File? _mortReturnPhotoFile;
  String? _mortReturnPhotoUrl;
  bool _uploadingMortReturn = false;
  File? _mortReturnSlipFile;
  String? _mortReturnSlipUrl;
  bool _uploadingMortReturnSlip = false;

  // Expenses
  final List<Map<String, dynamic>> _expenses = [];
  String _expType =
      'vehicle'; // must match one of: vehicle, loading, misc, food, other

  // Section expand state
  bool _showDelivery = true;
  bool _showRecon = true;
  bool _showReturn = true;
  bool _showMortality = false;
  bool _showExpenses = false;
  bool _showOdo = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _odoEndCtrl.dispose();
    _returnBirdsCtrl.dispose();
    _returnWtCtrl.dispose();
    _mortalityReasonCtrl.dispose();
    _mortReturnBirdsCtrl.dispose();
    _mortReturnWtCtrl.dispose();
    _expAmtCtrl.dispose();
    _expNoteCtrl.dispose();
    _dieselCtrl.dispose();
    _allowanceCtrl.dispose();
    _tollCtrl.dispose();
    super.dispose();
  }

  // ── Computed values ──────────────────────────────────────────────────────
  int get _dcBirds => (_recon['dc_birds'] as num?)?.toInt() ?? 0;

  double get _dcKg => (_recon['dc_kg'] as num?)?.toDouble() ?? 0;

  int get _deliveredBirds => (_recon['delivered_birds'] as num?)?.toInt() ?? 0;

  double get _deliveredKg => (_recon['delivered_kg'] as num?)?.toDouble() ?? 0;

  int get _mortalityBirds => (_recon['mortality_birds'] as num?)?.toInt() ?? 0;

  double get _mortalityKg => (_recon['mortality_kg'] as num?)?.toDouble() ?? 0;

  int get _transferInBirds =>
      (_recon['transfer_in_birds'] as num?)?.toInt() ?? 0;

  double get _transferInKg =>
      (_recon['transfer_in_kg'] as num?)?.toDouble() ?? 0;

  int get _transferOutBirds =>
      (_recon['transfer_out_birds'] as num?)?.toInt() ?? 0;

  double get _transferOutKg =>
      (_recon['transfer_out_kg'] as num?)?.toDouble() ?? 0;

  List<String> get _transferNotes =>
      List<String>.from((_recon['transfer_notes'] as List?) ?? []);

  double get _totalCash => (_recon['total_cash'] as num?)?.toDouble() ?? 0;

  int get _pendingCount => (_recon['pending_count'] as num?)?.toInt() ?? 0;

  int get _returnBirds => int.tryParse(_returnBirdsCtrl.text.trim()) ?? 0;

  double get _returnWt => double.tryParse(_returnWtCtrl.text.trim()) ?? 0;

  // ── Section 5: Dead birds during return transport ────────────────────────
  // Independent from Section 4. Never a subset of live return.
  int get _mortReturnBirds =>
      int.tryParse(_mortReturnBirdsCtrl.text.trim()) ?? 0;

  double get _mortReturnWt =>
      double.tryParse(_mortReturnWtCtrl.text.trim()) ?? 0;

  // DC average weight — used for auto-calculation when dead bird weight not entered
  // (dead birds are usually not weighed separately — auto-calc is the default path)
  double get _dcAvgBirdWeightKg =>
      _dcBirds > 0 ? _dcKg / _dcBirds : 0.0;

  // Dead return weight:
  //   Priority 1 — actual weight entered by agent (rare)
  //   Priority 2 — auto-calculated: dead_birds × DC_avg_bird_weight (default)
  double get _mortReturnWtEffective {
    if (_mortReturnBirds <= 0) return 0.0;
    if (_mortReturnWt > 0) return _mortReturnWt;
    return double.parse(
        (_mortReturnBirds * _dcAvgBirdWeightKg).toStringAsFixed(3));
  }

  // Total mortality = shift delivery mortality + return mortality (both independent)
  int get _totalMortalityBirds => _mortalityBirds + _mortReturnBirds;
  double get _totalMortalityKg  => _mortalityKg   + _mortReturnWtEffective;

  // ─── SHRINKAGE FORMULA ───────────────────────────────────────────────────
  // DC = Delivered + LiveReturn + TotalMortality(delivery+return) + Shrinkage
  // Shrinkage = DC − Delivered − LiveReturn − TotalMortality
  //
  // _returnWt is the DIRECT live return weight (separately weighed at stock point).
  // _totalMortalityKg is INDEPENDENT — never subtracted from _returnWt.
  //
  // Example: DC=1100 | Delivered=1000 | LiveReturn=66 kg | Mortality=15.07 kg
  //   Shrinkage = 1100 − 1000 − 66 − 15.07 = 18.93 kg ✓
  double get _shrinkageKg => (_dcKg +
      _transferInKg -
      _transferOutKg -
      _deliveredKg -
      _returnWt -          // direct live return weight (Section 4)
      _totalMortalityKg)   // delivery mort + dead return (Section 5)
      .clamp(0.0, double.infinity);

  double get _shrinkagePct {
    final base = _dcKg + _transferInKg;
    return base > 0 ? (_shrinkageKg / base * 100) : 0.0;
  }

  // ─── BIRD VARIANCE ───────────────────────────────────────────────────────
  // DC = Delivered + LiveReturn(Sec4) + DeadReturn(Sec5) + ShiftMortality + Variance
  // LiveReturn and DeadReturn are INDEPENDENT — neither is a subset of the other.
  int get _birdVariance => _stockBirds - _returnBirds - _mortReturnBirds;

  double get _totalExpenses =>
      (double.tryParse(_dieselCtrl.text) ?? 0) +
          (double.tryParse(_allowanceCtrl.text) ?? 0) +
          (double.tryParse(_tollCtrl.text) ?? 0) +
          _expenses.fold(
              0.0, (s, e) => s + ((e['amount'] as num?)?.toDouble() ?? 0));

  // Reconciliation status — drives status bar + close button colour
  // Priority: loading > pending > mismatch > highShrinkage > approvalNeeded > balanced
  // Validation: total returned (live + dead) must not exceed available stock + 2
  bool get _returnExceedsStock =>
      (_returnBirds + _mortReturnBirds) > (_stockBirds + 2) && _stockLoaded;

  _RStatus get _status {
    if (!_stockLoaded) return _RStatus.loading;
    if (_pendingCount > 0) return _RStatus.pending;
    // HARD BLOCK: total returned birds exceed system stock count
    if (_returnExceedsStock) return _RStatus.returnExceedsStock;
    // Mortality proof photo is REQUIRED before close
    if (_mortalityBirds > 0 && _mortalityPhotoUrl == null)
      return _RStatus.mortProofRequired;
    if (_mortReturnBirds > 0 && _mortReturnPhotoUrl == null)
      return _RStatus.mortProofRequired;
    if (_birdVariance > 5) return _RStatus.mismatch;
    if (_shrinkagePct > 5) return _RStatus.highShrinkage;
    if (_shrinkagePct > 2) return _RStatus.approvalNeeded;
    return _RStatus.balanced;
  }

  // ── Data load ────────────────────────────────────────────────────────────
  Future<void> _load() async {
    final agentId = ref.read(appUserProvider).valueOrNull?.agentId;
    if (agentId == null) {
      if (mounted) setState(() => _checking = false);
      return;
    }
    if (mounted) setState(() => _checking = true);

    // Open shift
    Map<String, dynamic>? shift;
    try {
      shift = await _c
          .from('delivery_shifts')
          .select(
          'id,status,odometer_start,odometer_start_photo,shift_start_at,'
              'opening_bird_count,opening_weight,crates_taken,crates_returned,'
              'delivery_agents(name,vehicle_no,vehicle_type)')
          .eq('delivery_agent_id', agentId)
          .eq('status', 'open')
          .order('shift_start_at', ascending: false)
          .limit(1)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));
    } catch (_) {}

    if (shift == null) {
      if (mounted) setState(() => _checking = false);
      return;
    }

    // Deliveries for this shift
    List<Map<String, dynamic>> deliveries = [];
    try {
      final r = await _c
          .from('deliveries')
          .select('id,status,delivered_bird_count,delivered_total_weight,'
          'collected_amount,payment_mode,mortality_birds,mortality_weight_kg,'
          'returned_birds,returned_weight,shrinkage_kg,'
          'orders(retailers(shop_name))')
          .eq('delivery_shift_id', shift['id'])
          .timeout(const Duration(seconds: 10));
      deliveries = List<Map<String, dynamic>>.from(r as List? ?? []);
    } catch (_) {}

    // Live agent stock
    int stockB = 0;
    double stockK = 0;
    bool stockOk = false;
    try {
      final dash = await _c.rpc('get_agent_dashboard',
          params: {'p_agent_id': agentId}).timeout(const Duration(seconds: 10));
      final s = (dash as Map<String, dynamic>?)?['stock'] as Map?;
      stockB = ((s?['available_birds'] as num?)?.toInt() ?? 0).clamp(0, 999999);
      stockK =
          ((s?['available_kg'] as num?)?.toDouble() ?? 0).clamp(0.0, 999999.0);
      stockOk = true;
    } catch (_) {}

    // Stock ledger breakdown for this shift
    // FIX: transfers have shift_id=null (written before shift linkage fix).
    // Query ALL agent ledger rows for today — transfers are date-based not shift-linked.
    Map<String, dynamic> recon = {};
    try {
      final shiftDate = shift!['shift_start_at'] != null
          ? DateTime.tryParse(shift['shift_start_at'] as String)
          ?.toIso8601String()
          .split('T')[0]
          : null;

      // Query 1: shift-linked rows (DC, delivery, mortality — have shift_id)
      final shiftRows = List<Map<String, dynamic>>.from((await _c
          .from('stock_ledger')
          .select('movement_type,quantity_birds,quantity_kg,notes')
          .eq('agent_id', agentId)
          .eq('shift_id', shift['id'])
          .timeout(const Duration(seconds: 10))) as List? ??
          []);

      // Query 2: transfer rows for agent on shift date (shift_id may be null on older rows)
      List<Map<String, dynamic>> transferRows = [];
      if (shiftDate != null) {
        transferRows = List<Map<String, dynamic>>.from((await _c
            .from('stock_ledger')
            .select('movement_type,quantity_birds,quantity_kg,notes')
            .eq('agent_id', agentId)
            .inFilter(
            'movement_type', ['transferred_in', 'transferred_out'])
            .eq('entry_date', shiftDate)
            .timeout(const Duration(seconds: 10))) as List? ??
            []);
      }

      int dcB = 0, delB = 0, mortB = 0, tiB = 0, toB = 0;
      double dcK = 0, delK = 0, mortK = 0, tiK = 0, toK = 0;
      final List<String> transferNotes = [];
      final Set<String> seenTransferNotes = {};

      // NOTE: transfers are counted from transferRows only, not allRows.
      // transfer_birds() now always sets a valid shift_id, so a transfer row
      // can appear in BOTH shiftRows and transferRows for the same shift —
      // counting it from shiftRows too would double it. Keeping transfer
      // totals sourced from transferRows alone avoids that, and still covers
      // older rows where shift_id is still NULL.
      for (final row in shiftRows) {
        final mt = row['movement_type'] as String? ?? '';
        final b = (row['quantity_birds'] as num?)?.toInt() ?? 0;
        final k = (row['quantity_kg'] as num?)?.toDouble() ?? 0;
        switch (mt) {
          case 'purchased':
            dcB += b;
            dcK += k;
          case 'delivered':
            delB += b;
            delK += k;
          case 'mortality':
            mortB += b;
            mortK += k;
        }
      }
      for (final row in transferRows) {
        final mt = row['movement_type'] as String? ?? '';
        final b = (row['quantity_birds'] as num?)?.toInt() ?? 0;
        final k = (row['quantity_kg'] as num?)?.toDouble() ?? 0;
        final note = row['notes'] as String? ?? '';
        switch (mt) {
          case 'transferred_in':
            tiB += b;
            tiK += k;
            if (note.isNotEmpty && !seenTransferNotes.contains(note)) {
              seenTransferNotes.add(note);
              transferNotes
                  .add('IN: $b birds (${k.toStringAsFixed(1)} kg) — $note');
            }
          case 'transferred_out':
            toB += b;
            toK += k;
            if (note.isNotEmpty && !seenTransferNotes.contains(note)) {
              seenTransferNotes.add(note);
              transferNotes
                  .add('OUT: $b birds (${k.toStringAsFixed(1)} kg) — $note');
            }
        }
      }

      int pendCount = 0;
      double cash = 0;
      for (final d in deliveries) {
        if (['assigned', 'picked_up', 'out_for_delivery'].contains(d['status']))
          pendCount++;
        cash += (d['collected_amount'] as num?)?.toDouble() ?? 0;
      }

      recon = {
        'dc_birds': dcB,
        'dc_kg': dcK,
        'delivered_birds': delB,
        'delivered_kg': delK,
        'mortality_birds': mortB,
        'mortality_kg': mortK,
        'transfer_in_birds': tiB,
        'transfer_in_kg': tiK,
        'transfer_out_birds': toB,
        'transfer_out_kg': toK,
        'transfer_notes': transferNotes,
        'total_cash': cash,
        'pending_count': pendCount,
      };
    } catch (_) {}

    if (mounted)
      setState(() {
        _shift = shift;
        _deliveries = deliveries;
        _recon = recon;
        _stockBirds = stockB;
        _stockKg = stockK;
        _stockLoaded = stockOk;
        _checking = false;
        if (stockB > 0 && _returnBirdsCtrl.text == '0') {
          _returnBirdsCtrl.text = '$stockB';
          _returnWtCtrl.text = stockK.toStringAsFixed(1);
        }
        // Auto-expand mortality section when mortality recorded and proof not yet captured
        final mortBirdsInRecon =
            (recon['mortality_birds'] as num?)?.toInt() ?? 0;
        if (mortBirdsInRecon > 0) {
          _showMortality = true; // force open so agent sees the required photo
        }
      });
  }

  // ── Photo upload ─────────────────────────────────────────────────────────
  Future<String?> _upload(File f, String folder) async {
    try {
      final path = '$folder/${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _c.storage.from('delivery-proofs').upload(path, f);
      return _c.storage.from('delivery-proofs').getPublicUrl(path);
    } catch (_) {
      return null;
    }
  }

  Future<void> _capture(String type) async {
    try {
      final p = await _pick.pickImage(
          source: ImageSource.camera, imageQuality: 70, maxWidth: 1200);
      if (p == null || !mounted) return;
      final f = File(p.path);
      if (type == 'odo') {
        setState(() {
          _odoPhotoFile = f;
          _uploadingOdo = true;
        });
        final u = await _upload(f, 'odometer');
        if (mounted)
          setState(() {
            _odoPhotoUrl = u;
            _uploadingOdo = false;
          });
      } else if (type == 'mortality') {
        setState(() {
          _mortalityPhotoFile = f;
          _uploadingMortality = true;
        });
        final u = await _upload(f, 'mortality');
        if (mounted)
          setState(() {
            _mortalityPhotoUrl = u;
            _uploadingMortality = false;
          });
      } else if (type == 'return') {
        setState(() {
          _returnPhotoFile = f;
          _uploadingReturn = true;
        });
        final u = await _upload(f, 'return-stock');
        if (mounted)
          setState(() {
            _returnPhotoUrl = u;
            _uploadingReturn = false;
          });
      } else if (type == 'return-slip') {
        setState(() {
          _returnSlipFile = f;
          _uploadingReturnSlip = true;
        });
        final u = await _upload(f, 'return-slip');
        if (mounted)
          setState(() {
            _returnSlipUrl = u;
            _uploadingReturnSlip = false;
          });
      } else if (type == 'mort-return') {
        setState(() {
          _mortReturnPhotoFile = f;
          _uploadingMortReturn = true;
        });
        final u = await _upload(f, 'mortality-return');
        if (mounted)
          setState(() {
            _mortReturnPhotoUrl = u;
            _uploadingMortReturn = false;
          });
      } else if (type == 'mort-return-slip') {
        setState(() {
          _mortReturnSlipFile = f;
          _uploadingMortReturnSlip = true;
        });
        final u = await _upload(f, 'mortality-return-slip');
        if (mounted)
          setState(() {
            _mortReturnSlipUrl = u;
            _uploadingMortReturnSlip = false;
          });
      }
    } catch (_) {}
  }

  // ── Submit ───────────────────────────────────────────────────────────────
  Future<void> _doClose() async {
    if (_shift == null) return;
    if (_odoEndCtrl.text.trim().isEmpty) {
      showError(context, 'Odometer end reading required');
      return;
    }
    if (_pendingCount > 0) {
      showError(context, '$_pendingCount deliveries still in progress');
      return;
    }
    if (_stockBirds > 0 && _returnBirds == 0 && _returnWt == 0) {
      showError(
          context,
          '⚠️ Return stock not declared\n\n'
              '$_stockBirds birds in your stock.\nFill Section 4 before closing.');
      return;
    }
    // REQUIRED: mortality proof photo must be captured at shift close
    if (_mortalityBirds > 0 && _mortalityPhotoUrl == null) {
      // Auto-expand the mortality section so agent sees it
      setState(() => _showMortality = true);
      showError(
          context,
          '⚠️ Mortality proof photo required\n\n'
              '$_mortalityBirds dead birds recorded this shift.\n'
              'Open Section 5 and capture the mortality proof photo.');
      return;
    }
    // REQUIRED: return mortality photo if return mortality recorded
    if (_mortReturnBirds > 0 && _mortReturnPhotoUrl == null) {
      setState(() => _showMortality = true);
      showError(
          context,
          '⚠️ Return mortality photo required\n\n'
              '$_mortReturnBirds birds died during return.\n'
              'Capture the photo in Section 5.');
      return;
    }

    final st = _status;
    String msg =
        'Delivered: $_deliveredBirds birds · ${_deliveredKg.toStringAsFixed(1)} kg\n'
        'Collected: ${Fmt.amount(_totalCash)}\n'
        'Returning: $_returnBirds birds · ${_returnWt.toStringAsFixed(1)} kg\n'
        'Expenses: ${Fmt.amount(_totalExpenses)}';
    if (_totalMortalityBirds > 0)
      msg +=
      '\nMortality: ${_totalMortalityBirds} birds · ${_totalMortalityKg.toStringAsFixed(2)} kg';
    if (_transferInBirds > 0 || _transferOutBirds > 0)
      msg +=
      '\nTransfers: IN ${_transferInBirds} · OUT ${_transferOutBirds} birds';
    if (_shrinkageKg > 0.01)
      msg +=
      '\nShrinkage: ${_shrinkageKg.toStringAsFixed(2)} kg (${_shrinkagePct.toStringAsFixed(1)}%)';
    if (st == _RStatus.mismatch)
      msg =
      '⚠️ Bird mismatch: $_birdVariance birds unaccounted.\nTrader will review.\n\n$msg';
    if (st == _RStatus.highShrinkage)
      msg =
      '🔴 High shrinkage: ${_shrinkagePct.toStringAsFixed(1)}%\nTrader approval required.\n\n$msg';

    final ok = await confirmDialog(context,
        title: 'Close Shift',
        message: msg,
        confirmText: 'Close Shift',
        confirmColor: st == _RStatus.mismatch || st == _RStatus.highShrinkage
            ? Colors.orange
            : kPrimary);
    if (!ok || !mounted) return;

    setState(() => _submitting = true);
    try {
      final tid = ref.read(appUserProvider).valueOrNull?.traderId;
      final sid = _shift!['id'] as String;

      Future<void> ins(String type, double amt, String note) async {
        if (amt <= 0) return;
        await _c.from('delivery_expenses').insert({
          'shift_id': sid,
          'trader_id': tid,
          'expense_type': type,
          'amount': amt,
          'notes': note,
        });
      }

      await ins('fuel', double.tryParse(_dieselCtrl.text) ?? 0, 'Diesel cost');
      await ins('allowance', double.tryParse(_allowanceCtrl.text) ?? 0,
          'Agent allowance');
      await ins('toll', double.tryParse(_tollCtrl.text) ?? 0, 'Toll charges');
      for (final e in _expenses) {
        await ins(e['type'] as String, e['amount'] as double,
            e['notes'] as String? ?? '');
      }

      await _c.rpc('close_delivery_shift', params: {
        'p_shift_id':                sid,
        'p_odometer_end':            double.tryParse(_odoEndCtrl.text.trim()) ?? 0,
        'p_odometer_end_photo':      _odoPhotoUrl,
        // Live return = total returned − return mortality
        // DB writes shift_close_return for live birds, mortality for dead birds
        'p_closing_bird_count':      _returnBirds,       // live birds (Section 4, directly entered)
        'p_closing_weight':          _returnWt,           // live return weight (Section 4, directly weighed)
        'p_expenses':                _totalExpenses,
        'p_diesel_cost':             double.tryParse(_dieselCtrl.text) ?? 0,
        'p_allowance':               double.tryParse(_allowanceCtrl.text) ?? 0,
        'p_return_mortality_birds':  _mortReturnBirds,
        'p_return_mortality_weight': _mortReturnWt, // 0 = auto-calc in DB
      });

      if (mounted) {
        showSuccess(context, 'Shift closed ✓  Great work today!');
        context.go(R.agentHome);
      }
    } catch (e) {
      if (!mounted) return;
      String raw = e
          .toString()
          .replaceAll('Exception: ', '')
          .replaceAll('PostgrestException(message: ', '')
          .replaceAll(RegExp(r'\)$'), '');
      if (raw.contains('Shift close blocked') || raw.contains('unaccounted')) {
        final m = RegExp(r'(\d+) birds.*?(\d+\.?\d*)\s*kg').firstMatch(raw);
        showError(context,
            '⚠️ Cannot close\n\n${m?.group(1) ?? _stockBirds} birds unaccounted.\nFill Section 4.');
      } else if (raw.contains('still in progress')) {
        showError(context, 'Complete all deliveries first.');
      } else {
        showError(context, raw);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isSimple = ref.watch(uiModeProvider).isSimple;
    if (isSimple && !_checking && _shift != null) {
      return _buildSimpleCloseView();
    }
    return Scaffold(
        backgroundColor: kBgGrey,
        appBar: AppBar(
            backgroundColor: Colors.white,
            title: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Close Shift',
                      style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  Text('Reconciliation & Audit',
                      style: TextStyle(fontSize: 11, color: kTextHint)),
                ]),
            actions: [
              IconButton(icon: const Icon(Icons.refresh), onPressed: _load)
            ]),
        body: _checking
            ? const LoadingList()
            : _shift == null
            ? _noShift()
            : Column(children: [
          _statusBar(),
          Expanded(
              child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
                  children: [
                    _sec1ShiftSummary(),
                    _sec2DeliverySummary(),
                    _sec3StockRecon(),
                    _sec4ReturnStock(),
                    _sec5Mortality(),
                    _sec6Expenses(),
                    _sec7Odometer(),
                    const SizedBox(height: 16),
                    _closeButton(),
                  ])),
        ]));
  }

  // ── STATUS BAR ──────────────────────────────────────────────────────────
  Widget _statusBar() {
    final Color bg;
    final String label;
    final IconData ic;
    switch (_status) {
      case _RStatus.balanced:
        bg = Colors.green.shade600;
        label = 'BALANCED — Ready to Close';
        ic = Icons.check_circle_outline;
      case _RStatus.approvalNeeded:
        bg = Colors.orange;
        label =
        'APPROVAL NEEDED — Shrinkage ${_shrinkagePct.toStringAsFixed(1)}%';
        ic = Icons.pending_outlined;
      case _RStatus.highShrinkage:
        bg = Colors.red;
        label = 'HIGH SHRINKAGE — ${_shrinkagePct.toStringAsFixed(1)}% (>5%)';
        ic = Icons.warning_amber_rounded;
      case _RStatus.mismatch:
        bg = Colors.red;
        label = 'MISMATCH — $_birdVariance birds unaccounted';
        ic = Icons.error_outline;
      case _RStatus.pending:
        bg = Colors.orange;
        label = '$_pendingCount DELIVERIES STILL ACTIVE';
        ic = Icons.local_shipping_outlined;
      case _RStatus.loading:
        bg = Colors.grey;
        label = 'Loading stock data...';
        ic = Icons.hourglass_empty_outlined;
      case _RStatus.mortProofRequired:
        bg = Colors.red.shade700;
        label = 'MORTALITY PROOF REQUIRED — Capture photo in Section 5';
        ic = Icons.camera_alt_outlined;
      case _RStatus.returnExceedsStock:
        bg = Colors.red.shade900;
        label = 'RETURN EXCEEDS STOCK — ${_returnBirds + _mortReturnBirds} returned but only $_stockBirds in system';
        ic = Icons.block;
    }
    return Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Icon(ic, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700))),
          if (_status == _RStatus.pending)
            GestureDetector(
                onTap: () => context.go(R.agentDeliveries),
                child: const Text('View →',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700))),
          if (_transferInBirds > 0 || _transferOutBirds > 0)
            Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4)),
                child: Text(
                    'T:${_transferInBirds > 0 ? "+$_transferInBirds" : ""}${_transferOutBirds > 0 ? " -$_transferOutBirds" : ""}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800))),
        ]));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SEC 1 — SHIFT SUMMARY
  // ─────────────────────────────────────────────────────────────────────────
  Widget _sec1ShiftSummary() {
    final agent = _shift!['delivery_agents'] as Map?;
    final startAt =
    DateTime.tryParse(_shift!['shift_start_at'] as String? ?? '');
    final dur = startAt != null ? DateTime.now().difference(startAt) : null;
    final durStr =
    dur != null ? '${dur.inHours}h ${dur.inMinutes.remainder(60)}m' : '—';
    return _Card(
        title: '1. Shift Summary',
        icon: Icons.schedule_outlined,
        iconColor: kPrimary,
        expanded: true,
        child: Column(children: [
          Row(children: [
            Expanded(
                child: _tile('Agent', agent?['name'] as String? ?? '—',
                    Icons.person_outline)),
            const SizedBox(width: 8),
            Expanded(
                child: _tile('Vehicle', agent?['vehicle_no'] as String? ?? '—',
                    Icons.directions_car_outlined)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: _tile(
                    'Started',
                    startAt != null
                        ? DateFormat('d MMM, h:mm a').format(startAt)
                        : '—',
                    Icons.play_circle_outline)),
            const SizedBox(width: 8),
            Expanded(child: _tile('Duration', durStr, Icons.timer_outlined)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: _tile(
                    'Start Odo',
                    '${_shift!['odometer_start'] ?? '—'} km',
                    Icons.speed_outlined)),
            const SizedBox(width: 8),
            Expanded(
                child: _tile('Crates Out', '${_shift!['crates_taken'] ?? 0}',
                    Icons.grid_4x4_outlined)),
          ]),
        ]));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SEC 2 — DELIVERY SUMMARY
  // ─────────────────────────────────────────────────────────────────────────
  Widget _sec2DeliverySummary() {
    final done = _deliveries.where((d) => d['status'] == 'delivered').toList();
    final pending = _deliveries
        .where((d) =>
        ['assigned', 'picked_up', 'out_for_delivery'].contains(d['status']))
        .toList();
    final totBirds = done.fold(
        0, (s, d) => s + ((d['delivered_bird_count'] as num?)?.toInt() ?? 0));
    final totKg = done.fold(0.0,
            (s, d) => s + ((d['delivered_total_weight'] as num?)?.toDouble() ?? 0));
    final totCash = done.fold(
        0.0, (s, d) => s + ((d['collected_amount'] as num?)?.toDouble() ?? 0));
    final totMort = done.fold(
        0, (s, d) => s + ((d['mortality_birds'] as num?)?.toInt() ?? 0));

    return _Card(
        title: '2. Delivery Summary',
        icon: Icons.local_shipping_outlined,
        iconColor: Colors.teal,
        expanded: _showDelivery,
        onToggle: () => setState(() => _showDelivery = !_showDelivery),
        badge: pending.isNotEmpty
            ? '${pending.length} pending'
            : '${done.length} done',
        badgeColor: pending.isNotEmpty ? Colors.orange : Colors.teal,
        child: Column(children: [
          Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                _kpi('Done', '${done.length}', Colors.teal),
                _kpi('Birds', '$totBirds', kPrimary),
                _kpi('Weight', '${totKg.toStringAsFixed(1)} kg', Colors.blue),
                _kpi('Cash', Fmt.amount(totCash), Colors.green),
              ])),
          if (totMort > 0) ...[
            const SizedBox(height: 6),
            _alert(Icons.sentiment_dissatisfied_outlined,
                'Mortality: $totMort birds recorded', Colors.red)
          ],
          if (pending.isNotEmpty) ...[
            const SizedBox(height: 6),
            _alert(
                Icons.warning_amber_rounded,
                '${pending.length} still active — complete before closing',
                Colors.orange)
          ],
          if (done.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...done.map((d) {
              final shop = ((d['orders'] as Map?)?['retailers']
              as Map?)?['shop_name'] as String? ??
                  'Delivery';
              final b = (d['delivered_bird_count'] as num?)?.toInt() ?? 0;
              final k = (d['delivered_total_weight'] as num?)?.toDouble() ?? 0;
              final cash = (d['collected_amount'] as num?)?.toDouble() ?? 0;
              return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                            color: Colors.teal, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(shop,
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w600))),
                    Text(
                        '$b birds · ${k.toStringAsFixed(1)} kg · ${Fmt.amount(cash)}',
                        style: const TextStyle(fontSize: 10, color: kTextSub)),
                  ]));
            }),
          ],
        ]));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SEC 3 — STOCK RECONCILIATION
  // ─────────────────────────────────────────────────────────────────────────
  Widget _sec3StockRecon() {
    final sc = _shrinkagePct > 5
        ? Colors.red
        : _shrinkagePct > 2
        ? Colors.orange
        : Colors.green;
    final hasTransfers = _transferInKg > 0 || _transferOutKg > 0;
    return _Card(
        title: '3. Final Stock Reconciliation',
        icon: Icons.balance_outlined,
        iconColor: Colors.purple,
        expanded: _showRecon,
        onToggle: () => setState(() => _showRecon = !_showRecon),
        badge: _shrinkageKg > 0.01
            ? '${_shrinkageKg.toStringAsFixed(1)} kg shrinkage'
            : 'Balanced',
        badgeColor: sc,
        child: Column(children: [
          // ── Full reconciliation flow — matches exact formula from spec ─────────
          // Formula: (DC + TransferIn) - TransferOut - Delivered - Mortality - Returned = Shrinkage
          _rrow('DC Loaded', '+$_dcBirds birds',
              '+${_dcKg.toStringAsFixed(1)} kg', Colors.blue, true),
          if (_transferInBirds > 0)
            _rrow('Transfer In', '+$_transferInBirds birds',
                '+${_transferInKg.toStringAsFixed(1)} kg', Colors.teal, true),
          if (_transferOutBirds > 0)
            _rrow(
                'Transfer Out',
                '−$_transferOutBirds birds',
                '−${_transferOutKg.toStringAsFixed(1)} kg',
                Colors.indigo,
                false),
          _rrow('Delivered', '−$_deliveredBirds birds',
              '−${_deliveredKg.toStringAsFixed(1)} kg', kPrimary, false),
          if (_mortalityBirds > 0)
            _rrow('Mortality (shift)', '−$_mortalityBirds birds',
                '−${_mortalityKg.toStringAsFixed(2)} kg', Colors.red, false),
          if (_mortReturnBirds > 0)
            _rrow(
                'Mortality (return)',
                '−$_mortReturnBirds birds',
                '−${_mortReturnWtEffective.toStringAsFixed(2)} kg'
                    '${_mortReturnWt == 0 && _mortReturnBirds > 0 ? ' (auto)' : ''}',
                Colors.deepOrange,
                false),
          _rrow('Returned (actual)', '−$_returnBirds birds',
              '−${_returnWt.toStringAsFixed(1)} kg', Colors.purple, false),
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Divider(height: 1)),
          // Shrinkage result
          Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: sc.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: sc.withValues(alpha: 0.3))),
              child: Row(children: [
                Icon(
                    _shrinkagePct > 2
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline,
                    color: sc,
                    size: 16),
                const SizedBox(width: 8),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('TRANSPORT SHRINKAGE',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: sc,
                                  letterSpacing: 0.6)),
                          Text(
                              '${_shrinkageKg.toStringAsFixed(2)} kg  (${_shrinkagePct.toStringAsFixed(1)}%)',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: sc)),
                          Text(
                              'Base: ${(_dcKg + _transferInKg).toStringAsFixed(1)} kg loaded',
                              style: TextStyle(
                                  fontSize: 9, color: sc.withValues(alpha: 0.7))),
                        ])),
                if (_shrinkagePct > 2)
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: sc, borderRadius: BorderRadius.circular(6)),
                      child: Text(_shrinkagePct > 5 ? 'HIGH' : 'REVIEW',
                          style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.white))),
              ])),
          const SizedBox(height: 6),
          // Bird count reconciliation
          Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kBorder)),
              child: Row(children: [
                const Icon(Icons.egg_alt_outlined, size: 13, color: kTextSub),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(
                        'Stock: $_expectedReturnBirds  ·  Live: $_returnBirds'
                            '${_mortReturnBirds > 0 ? "  ·  Dead: $_mortReturnBirds" : ""}',
                        style: const TextStyle(fontSize: 10, color: kTextSub))),
                Text(
                    _birdVariance == 0
                        ? '✓ Matched'
                        : _birdVariance > 0
                        ? '−$_birdVariance missing'
                        : '+${-_birdVariance} extra',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _birdVariance == 0
                            ? Colors.green
                            : _birdVariance > 5
                            ? Colors.red
                            : Colors.orange)),
              ])),
          // Transfer notes (if any)
          if (_transferNotes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(8)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('TRANSFER DETAILS',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.teal,
                              letterSpacing: 0.6)),
                      const SizedBox(height: 4),
                      ..._transferNotes.map((n) => Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text('· $n',
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.teal)))),
                    ])),
          ],
          // Alerts
          if (_returnExceedsStock) ...[
            const SizedBox(height: 6),
            _alert(
                Icons.block,
                '⛔ Return exceeds available stock: '
                    '${_returnBirds} live + ${_mortReturnBirds} dead = ${_returnBirds + _mortReturnBirds} birds '
                    '> ${_stockBirds} in system. '
                    'Recount and correct before closing.',
                Colors.red.shade900),
          ],
          if (_birdVariance > 5) ...[
            const SizedBox(height: 6),
            _alert(
                Icons.warning_amber_rounded,
                'Bird mismatch: $_birdVariance birds unaccounted — trader will be notified for review',
                Colors.orange),
          ],
          if (_shrinkagePct > 5) ...[
            const SizedBox(height: 6),
            _alert(
                Icons.error_outline,
                'Unusual shrinkage: ${_shrinkagePct.toStringAsFixed(1)}% exceeds 5% threshold — trader approval required',
                Colors.red),
          ],
        ]));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SEC 4 — RETURN STOCK
  // ─────────────────────────────────────────────────────────────────────────
  Widget _sec4ReturnStock() {
    final hasStock = _stockBirds > 0;
    final declared = _returnBirds > 0 || _returnWt > 0;
    final weighmentDone = _returnWt > 0 && _returnPhotoUrl != null;

    return _Card(
        title: '4. Live Return Stock',
        icon: Icons.assignment_return_outlined,
        iconColor: Colors.purple,
        expanded: _showReturn,
        onToggle: () => setState(() => _showReturn = !_showReturn),
        badge: weighmentDone
            ? 'Weighed ✓'
            : declared
            ? _mortReturnBirds > 0
            ? '$_returnBirds live · $_mortReturnBirds dead'
            : '$_returnBirds birds'
            : hasStock
            ? 'REQUIRED'
            : null,
        badgeColor: weighmentDone
            ? Colors.green
            : declared
            ? Colors.purple
            : Colors.red,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── System expected stock ────────────────────────────────────
          if (_stockLoaded)
            Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const Icon(Icons.info_outline, color: Colors.blue, size: 13),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(
                          'Expected return: $_expectedReturnBirds birds · ${_expectedReturnKg.toStringAsFixed(1)} kg',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.blue))),
                ])),
          const SizedBox(height: 10),

          // ── WEIGHMENT: birds + weight ──────────────────────────────
          const Text('RETURN WEIGHMENT',
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: kTextHint,
                  letterSpacing: 0.6)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
                child: TextField(
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                    controller: _returnBirdsCtrl,
                    keyboardType: TextInputType.number,
                    autofocus: hasStock,
                    onChanged: (_) {
                      if (mounted) setState(() {});
                    },
                    decoration: InputDecoration(
                        labelText:
                        hasStock ? 'Live Birds Returned *' : 'Live Birds Returned',
                        suffixText: 'birds',
                        labelStyle: TextStyle(
                            color:
                            hasStock && !declared ? Colors.red : null)))),
            const SizedBox(width: 10),
            Expanded(
                child: TextField(
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                    controller: _returnWtCtrl,
                    keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) {
                      if (mounted) setState(() {});
                    },
                    decoration: InputDecoration(
                        labelText: 'Live Return Weight (kg) *',
                        suffixText: 'kg',
                        labelStyle: TextStyle(
                            color:
                            hasStock && !declared ? Colors.red : null)))),
          ]),

          // ── Weighment variance indicator ───────────────────────────
          if (declared && _stockLoaded) ...[
            const SizedBox(height: 6),
            Builder(builder: (_) {
              final expectedKg = _expectedReturnKg;
              final varKg = _returnWt - expectedKg;
              final varColor = varKg.abs() < 0.5
                  ? Colors.green
                  : varKg.abs() < 2.0
                  ? Colors.orange
                  : Colors.red;
              return Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: varColor.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(8),
                      border:
                      Border.all(color: varColor.withValues(alpha: 0.3))),
                  child: Row(children: [
                    Icon(
                        varKg.abs() < 0.5
                            ? Icons.check_circle_outline
                            : Icons.warning_amber_rounded,
                        color: varColor,
                        size: 13),
                    const SizedBox(width: 6),
                    Text(
                        varKg.abs() < 0.1
                            ? 'Weight matches expected ✓'
                            : 'Weight variance: ${varKg > 0 ? "+" : ""}${varKg.toStringAsFixed(2)} kg '
                            '(expected ${expectedKg.toStringAsFixed(1)} kg)',
                        style: TextStyle(
                            fontSize: 10,
                            color: varColor,
                            fontWeight: FontWeight.w600)),
                  ]));
            }),
          ],

          const SizedBox(height: 10),

          // ── Photo evidence ─────────────────────────────────────────
          const Text('PHOTO EVIDENCE',
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: kTextHint,
                  letterSpacing: 0.6)),
          const SizedBox(height: 6),
          _PhotoTile(
              label: 'Return Stock Photo *',
              sublabel: 'Photo of birds at stock point',
              required: _returnBirds > 0,
              file: _returnPhotoFile,
              uploaded: _returnPhotoUrl != null,
              uploading: _uploadingReturn,
              onTap: () => _capture('return')),
          const SizedBox(height: 6),
          _PhotoTile(
              label: 'Weighment Slip',
              sublabel: 'Optional — photo of scale/slip for audit',
              required: false,
              file: _returnSlipFile,
              uploaded: _returnSlipUrl != null,
              uploading: _uploadingReturnSlip,
              onTap: () => _capture('return-slip')),

          // ── Confirmation ───────────────────────────────────────────
          if (declared) ...[
            const SizedBox(height: 8),
            Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  Icon(
                      weighmentDone
                          ? Icons.verified_outlined
                          : Icons.pending_outlined,
                      color: weighmentDone ? Colors.green : Colors.purple,
                      size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _mortReturnBirds > 0
                        ? Text(
                        '$_returnBirds live birds · ${_returnWt.toStringAsFixed(1)} kg'
                            '${weighmentDone ? " — Weighed & photographed ✓" : " — Add photo to complete"}',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                            color: weighmentDone ? Colors.green : Colors.purple))
                        : Text(
                        '$_returnBirds birds · ${_returnWt.toStringAsFixed(1)} kg'
                            '${weighmentDone ? " — Weighed & photographed ✓" : " — Add photo to complete"}',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                            color: weighmentDone ? Colors.green : Colors.purple)),
                  ),
                ])),
          ],
        ]));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SEC 5 — MORTALITY
  // ─────────────────────────────────────────────────────────────────────────
  Widget _sec5Mortality() {
    final hasMort = _mortalityBirds > 0;
    final hasReturnMort = _mortReturnBirds > 0;
    final badgeText = hasMort || hasReturnMort
        ? '${_totalMortalityBirds} birds total'
        : 'None';
    return _Card(
        title: '5. Mortality & Return Mortality',
        icon: Icons.sentiment_very_dissatisfied_outlined,
        iconColor: Colors.red,
        expanded: _showMortality,
        onToggle: () => setState(() => _showMortality = !_showMortality),
        badge: badgeText,
        badgeColor: (hasMort || hasReturnMort) ? Colors.red : Colors.green,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Shift mortality (from completed deliveries) ─────────────────
          if (hasMort) ...[
            Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('DURING DELIVERY (recorded at delivery)',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.red,
                              letterSpacing: 0.5)),
                      const SizedBox(height: 6),
                      Row(children: [
                        _kpi('Dead Birds', '$_mortalityBirds', Colors.red),
                        _kpi('Weight', '${_mortalityKg.toStringAsFixed(2)} kg',
                            Colors.red),
                        _kpi('Status', 'Deducted ✓', Colors.orange),
                      ]),
                    ])),
            const SizedBox(height: 8),
            TextField(
                controller: _mortalityReasonCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Mortality Reason',
                    alignLabelWithHint: true,
                    hintText: 'Disease, injury, heat stress...')),
            const SizedBox(height: 8),
            // REQUIRED — shift close blocked until this is captured
            _PhotoTile(
                label: 'Mortality Proof Photo *',
                sublabel: _mortalityPhotoUrl != null
                    ? 'Photo captured ✓ — shift close allowed'
                    : 'REQUIRED — shift close blocked until photo captured',
                required: hasMort,
                file: _mortalityPhotoFile,
                uploaded: _mortalityPhotoUrl != null,
                uploading: _uploadingMortality,
                onTap: () => _capture('mortality')),
            if (hasMort && _mortalityPhotoUrl == null) ...[
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.block, color: Colors.red, size: 12),
                const SizedBox(width: 4),
                const Expanded(
                    child: Text(
                        'Shift cannot be closed until mortality photo is captured',
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.red,
                            fontWeight: FontWeight.w600))),
              ]),
            ],
            const SizedBox(height: 12),
          ] else
            _alert(Icons.check_circle_outline,
                'No delivery mortality recorded.', Colors.green),
          const SizedBox(height: 4),

          // ── Mortality during return transport ───────────────────────────
          const Text('MORTALITY DURING RETURN',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.deepOrange,
                  letterSpacing: 0.5)),
          const SizedBox(height: 4),
          const Text(
              'Birds that died during transport back to the stock point after shift close.',
              style: TextStyle(fontSize: 10, color: kTextHint, height: 1.4)),
          const SizedBox(height: 8),

          // ── Weighment inputs ────────────────────────────────────────
          const Text('MORTALITY WEIGHMENT',
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: kTextHint,
                  letterSpacing: 0.6)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
                child: TextField(
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                    controller: _mortReturnBirdsCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) {
                      if (mounted) setState(() {});
                    },
                    decoration: const InputDecoration(
                        labelText: 'Dead Birds (return)',
                        suffixText: 'birds',
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10)))),
            const SizedBox(width: 10),
            Expanded(
                child: TextField(
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                    controller: _mortReturnWtCtrl,
                    keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) {
                      if (mounted) setState(() {});
                    },
                    decoration: const InputDecoration(
                        labelText: 'Dead Bird Weight (kg) — optional',
                        suffixText: 'kg',
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10)))),
          ]),

          if (hasReturnMort) ...[
            const SizedBox(height: 8),

            // ── Photo evidence for mortality-return ─────────────────
            const Text('PHOTO EVIDENCE',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: kTextHint,
                    letterSpacing: 0.6)),
            const SizedBox(height: 6),
            _PhotoTile(
                label: 'Return Mortality Photo *',
                sublabel: 'Photo of dead birds being returned',
                required: true,
                file: _mortReturnPhotoFile,
                uploaded: _mortReturnPhotoUrl != null,
                uploading: _uploadingMortReturn,
                onTap: () => _capture('mort-return')),
            const SizedBox(height: 6),
            _PhotoTile(
                label: 'Weighment Slip',
                sublabel: 'Optional — scale photo for audit',
                required: false,
                file: _mortReturnSlipFile,
                uploaded: _mortReturnSlipUrl != null,
                uploading: _uploadingMortReturnSlip,
                onTap: () => _capture('mort-return-slip')),
            const SizedBox(height: 6),
            _alert(
                Icons.info_outline,
                'Return mortality: $_mortReturnBirds birds · ${_mortReturnWtEffective.toStringAsFixed(2)} kg included in reconciliation'
                    '${_mortReturnWt == 0 && _mortReturnBirds > 0 ? '\n⚡ Auto-calc: ${_mortReturnBirds} × ${_dcAvgBirdWeightKg.toStringAsFixed(3)} kg (DC avg)' : ' (actual weighed)'}',
                Colors.deepOrange),
          ],
          const SizedBox(height: 8),

          // ── Combined total ──────────────────────────────────────────────
          if (hasMort || hasReturnMort)
            Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border:
                    Border.all(color: Colors.red.withValues(alpha: 0.2))),
                child: Row(children: [
                  const Icon(Icons.summarize_outlined,
                      color: Colors.red, size: 14),
                  const SizedBox(width: 8),
                  Text(
                      'Total mortality: ${_totalMortalityBirds} birds · ${_totalMortalityKg.toStringAsFixed(2)} kg',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.red)),
                  const Spacer(),
                  const Text('Deducted from shrinkage',
                      style: TextStyle(fontSize: 9, color: kTextHint)),
                ])),
        ]));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SEC 6 — EXPENSES
  // ─────────────────────────────────────────────────────────────────────────
  Widget _sec6Expenses() => _Card(
      title: '6. Expenses & Allowances',
      icon: Icons.receipt_long_outlined,
      iconColor: Colors.orange,
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
          final idx = e.key;
          final exp = e.value;
          return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200)),
              child: Row(children: [
                Expanded(
                    child: Text(
                        '${_expLabel(exp['type'] as String)}  ₹${(exp['amount'] as double).toStringAsFixed(0)}'
                            '${(exp['notes'] as String?)?.isNotEmpty == true ? "  ·  ${exp['notes']}" : ""}',
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600))),
                GestureDetector(
                    onTap: () => setState(() => _expenses.removeAt(idx)),
                    child: const Icon(Icons.remove_circle_outline,
                        color: Colors.red, size: 18)),
              ]));
        }),
        // FIX: split into 2 rows to prevent overflow on narrow screens
        Row(children: [
          Expanded(
              child: DropdownButtonFormField<String>(
                  value: _expType,
                  isDense: true,
                  decoration: const InputDecoration(
                      labelText: 'Type',
                      contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
                  items: ['vehicle', 'loading', 'misc', 'food', 'other']
                      .map((t) => DropdownMenuItem(
                      value: t,
                      child: Text(_expLabel(t),
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1)))
                      .toList(),
                  onChanged: (v) => setState(() => _expType = v!))),
          const SizedBox(width: 8),
          Expanded(
              child: TextField(
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                  controller: _expAmtCtrl,
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Amount ₹',
                      prefixText: '₹',
                      contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 10)))),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
              child: TextField(
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                  controller: _expNoteCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                      contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 10)))),
          const SizedBox(width: 8),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(52, 48), padding: EdgeInsets.zero),
              onPressed: () {
                final amt = double.tryParse(_expAmtCtrl.text.trim()) ?? 0;
                if (amt <= 0) return;
                setState(() {
                  _expenses.add({
                    'type': _expType,
                    'amount': amt,
                    'notes': _expNoteCtrl.text.trim()
                  });
                  _expAmtCtrl.clear();
                  _expNoteCtrl.clear();
                });
              },
              child: const Icon(Icons.add, size: 20)),
        ]),
        if (_totalExpenses > 0)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                const Spacer(),
                Text('Total: ${Fmt.amount(_totalExpenses)}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.orange))
              ])),
      ]));

  // ─────────────────────────────────────────────────────────────────────────
  // SEC 7 — ODOMETER
  // ─────────────────────────────────────────────────────────────────────────
  Widget _sec7Odometer() {
    final odoStart = ((_shift!['odometer_start']) as num?)?.toDouble() ?? 0;
    final odoEnd = double.tryParse(_odoEndCtrl.text.trim()) ?? 0;
    final km = odoEnd > odoStart ? odoEnd - odoStart : 0.0;
    return _Card(
        title: '7. Odometer & Vehicle',
        icon: Icons.speed_outlined,
        iconColor: Colors.indigo,
        expanded: _showOdo,
        onToggle: () => setState(() => _showOdo = !_showOdo),
        badge: odoEnd > 0 ? '${km.toStringAsFixed(0)} km' : 'Required *',
        badgeColor: odoEnd > 0 ? Colors.indigo : Colors.red,
        child: Column(children: [
          Row(children: [
            Expanded(
                child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kBorder)),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Start Odo',
                              style: TextStyle(fontSize: 9, color: kTextHint)),
                          Text('${odoStart.toStringAsFixed(0)} km',
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w700)),
                        ]))),
            const SizedBox(width: 10),
            Expanded(
                child: TextField(
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                    controller: _odoEndCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) {
                      if (mounted) setState(() {});
                    },
                    decoration: const InputDecoration(
                        labelText: 'End Odometer * (km)',
                        prefixIcon: Icon(Icons.flag_outlined, size: 18),
                        suffixText: 'km'))),
          ]),
          if (km > 0) ...[
            const SizedBox(height: 8),
            Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const Icon(Icons.route_outlined,
                      color: Colors.indigo, size: 16),
                  const SizedBox(width: 8),
                  Text('Distance Travelled: ${km.toStringAsFixed(0)} km',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.indigo)),
                ])),
          ],
          const SizedBox(height: 10),
          _PhotoTile(
              label: 'End Odometer Photo',
              sublabel: 'Recommended for audit',
              required: false,
              file: _odoPhotoFile,
              uploaded: _odoPhotoUrl != null,
              uploading: _uploadingOdo,
              onTap: () => _capture('odo')),
        ]));
  }

  // ── CLOSE BUTTON ─────────────────────────────────────────────────────────
  Widget _closeButton() {
    final st = _status;
    final Color c;
    final String label;
    if (st == _RStatus.returnExceedsStock) {
      c = Colors.red.shade900;
      label = '⛔ Fix Bird Count — Return Exceeds Stock';
    } else if (st == _RStatus.mortProofRequired) {
      c = Colors.red.shade700;
      label = '📷 Capture Mortality Photo First (Section 5)';
    } else if (st == _RStatus.mismatch || st == _RStatus.highShrinkage) {
      c = Colors.red;
      label = '⚠️ Close Shift (Requires Trader Approval)';
    } else if (st == _RStatus.approvalNeeded) {
      c = Colors.orange;
      label = '⏳ Close Shift (Approval Needed)';
    } else {
      c = kPrimary;
      label = '✓ Close Shift';
    }

    return ElevatedButton.icon(
        onPressed: (_submitting ||
            st == _RStatus.pending ||
            st == _RStatus.loading ||
            st == _RStatus.mortProofRequired ||
            st == _RStatus.returnExceedsStock)
            ? null
            : _doClose,
        icon: _submitting
            ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.lock_outline, size: 18),
        label: Text(label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
            backgroundColor: c, minimumSize: const Size(double.infinity, 52)));
  }

  // ═════════════════════════════════════════════════════════════════════════
  // SIMPLE MODE — Simplified Shift Close
  // ═════════════════════════════════════════════════════════════════════════
  Widget _buildSimpleCloseView() {
    final st = _status;
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('📋 Close Shift',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load)
        ],
      ),
      body: Column(children: [
        _statusBar(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [
              // ── Hero Summary Card ────────────────────────────────
              _simpleHeroCard(),
              const SizedBox(height: 16),

              // ── Shift Summary ─────────────────────────────────
              _simpleShiftSummary(),
              const SizedBox(height: 16),

              // ── Delivery Summary ──────────────────────────────
              _simpleDeliverySummary(),
              const SizedBox(height: 16),

              // ── Stock Reconciliation ──────────────────────────
              _simpleStockRecon(),
              const SizedBox(height: 16),

              // ── Return Stock ────────────────────────────────────
              _simpleReturnSection(),
              const SizedBox(height: 16),

              // ── Mortality ───────────────────────────────────────
              _simpleMortalitySection(),
              const SizedBox(height: 16),

              // ── Expenses ─────────────────────────────────────
              _simpleExpensesSection(),
              const SizedBox(height: 16),

              // ── Odometer ────────────────────────────────────────
              _simpleOdometerSection(),
              const SizedBox(height: 20),

              // ── Close button ────────────────────────────────────
              _simpleCloseButton(st),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ]),
    );
  }

  // ── Simple Hero Summary Card ─────────────────────────────────────────────
  Widget _simpleHeroCard() {
    final done = _deliveries.where((d) => d['status'] == 'delivered').toList();
    final totBirds = done.fold(
        0, (s, d) => s + ((d['delivered_bird_count'] as num?)?.toInt() ?? 0));
    final totKg = done.fold(0.0,
            (s, d) => s + ((d['delivered_total_weight'] as num?)?.toDouble() ?? 0));
    final totCash = done.fold(
        0.0, (s, d) => s + ((d['collected_amount'] as num?)?.toDouble() ?? 0));

    final sc = _shrinkagePct > 5
        ? Colors.red
        : _shrinkagePct > 2
        ? Colors.orange
        : Colors.green;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 14,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Column(children: [
        const Text('✅', style: TextStyle(fontSize: 40)),
        const SizedBox(height: 10),
        const Text('SHIFT SUMMARY',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 1)),
        const SizedBox(height: 20),
        // Big KPIs
        Row(children: [
          _simpleKpi('🚛', '${done.length}', 'Deliveries'),
          _simpleKpi('🐔', '$totBirds', 'Birds'),
          _simpleKpi('💰', Fmt.amount(totCash), 'Cash'),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _simpleKpi('📦', '${totKg.toStringAsFixed(1)} kg', 'Weight'),
          _simpleKpi('📉', '${_shrinkagePct.toStringAsFixed(1)}%', 'Shrinkage',
              valueColor: sc),
          _simpleKpi('🐦', '$_stockBirds', 'Stock'),
        ]),
      ]),
    );
  }

  Widget _simpleKpi(String emoji, String value, String label,
      {Color? valueColor}) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: valueColor ?? Colors.white,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text(label,
                style: const TextStyle(fontSize: 10, color: Colors.white70),
                textAlign: TextAlign.center),
          ]),
        ),
      );

  // ── Simple Shift Summary ────────────────────────────────────────────────
  Widget _simpleShiftSummary() {
    final agent = _shift!['delivery_agents'] as Map?;
    final startAt =
    DateTime.tryParse(_shift!['shift_start_at'] as String? ?? '');
    final dur = startAt != null ? DateTime.now().difference(startAt) : null;
    final durStr =
    dur != null ? '${dur.inHours}h ${dur.inMinutes.remainder(60)}m' : '—';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('⏱️', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          const Expanded(
              child: Text('Shift Summary',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
              child: _simpleInfoTile(
                  '👤 Agent', agent?['name'] as String? ?? '—')),
          const SizedBox(width: 10),
          Expanded(
              child: _simpleInfoTile(
                  '🚗 Vehicle', agent?['vehicle_no'] as String? ?? '—')),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
              child: _simpleInfoTile(
                  '🕐 Started',
                  startAt != null
                      ? DateFormat('d MMM, h:mm a').format(startAt)
                      : '—')),
          const SizedBox(width: 10),
          Expanded(child: _simpleInfoTile('⏳ Duration', durStr)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
              child: _simpleInfoTile(
                  '🏁 Start Odo', '${_shift!['odometer_start'] ?? '—'} km')),
          const SizedBox(width: 10),
          Expanded(
              child: _simpleInfoTile(
                  '📦 Crates Out', '${_shift!['crates_taken'] ?? 0}')),
        ]),
      ]),
    );
  }

  // ── Simple Delivery Summary ─────────────────────────────────────────────
  Widget _simpleDeliverySummary() {
    final done = _deliveries.where((d) => d['status'] == 'delivered').toList();
    final pending = _deliveries
        .where((d) =>
        ['assigned', 'picked_up', 'out_for_delivery'].contains(d['status']))
        .toList();
    final totBirds = done.fold(
        0, (s, d) => s + ((d['delivered_bird_count'] as num?)?.toInt() ?? 0));
    final totKg = done.fold(0.0,
            (s, d) => s + ((d['delivered_total_weight'] as num?)?.toDouble() ?? 0));
    final totCash = done.fold(
        0.0, (s, d) => s + ((d['collected_amount'] as num?)?.toDouble() ?? 0));
    final totMort = done.fold(
        0, (s, d) => s + ((d['mortality_birds'] as num?)?.toInt() ?? 0));
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('🚛', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Delivery Summary',
                style:
                const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          if (pending.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.orange, borderRadius: BorderRadius.circular(6)),
              child: Text('${pending.length} pending',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ),
        ]),
        const SizedBox(height: 12),
        // KPI row
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            _simpleKpi('✅', '${done.length}', 'Done'),
            _simpleKpi('🐔', '$totBirds', 'Birds'),
            _simpleKpi('📦', '${totKg.toStringAsFixed(1)} kg', 'Weight'),
            _simpleKpi('💰', Fmt.amount(totCash), 'Cash'),
          ]),
        ),
        if (pending.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.orange, size: 18),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(
                      '${pending.length} delivery(s) still active — complete before closing',
                      style: const TextStyle(
                          fontSize: 12,
                          color: Colors.orange,
                          fontWeight: FontWeight.w600))),
            ]),
          ),
        ],
        if (totMort > 0) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(children: [
              const Icon(Icons.sentiment_dissatisfied_outlined,
                  color: Colors.red, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                  child: Text('Mortality recorded',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.red,
                          fontWeight: FontWeight.w600))),
            ]),
          ),
        ],
        if (done.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('DELIVERIES',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: kTextHint,
                  letterSpacing: 0.6)),
          const SizedBox(height: 6),
          ...done.map((d) {
            final shop = ((d['orders'] as Map?)?['retailers']
            as Map?)?['shop_name'] as String? ??
                'Delivery';
            final b = (d['delivered_bird_count'] as num?)?.toInt() ?? 0;
            final k = (d['delivered_total_weight'] as num?)?.toDouble() ?? 0;
            final cash = (d['collected_amount'] as num?)?.toDouble() ?? 0;
            return Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                        color: Colors.teal, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(shop,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600))),
                Text(
                    '$b birds · ${k.toStringAsFixed(1)} kg · ${Fmt.amount(cash)}',
                    style: const TextStyle(fontSize: 11, color: kTextSub)),
              ]),
            );
          }),
        ],
      ]),
    );
  }

  // ── Simple Stock Reconciliation ─────────────────────────────────────────
  Widget _simpleStockRecon() {
    final sc = _shrinkagePct > 5
        ? Colors.red
        : _shrinkagePct > 2
        ? Colors.orange
        : Colors.green;
    final hasTransfers = _transferInKg > 0 || _transferOutKg > 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: sc.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('⚖️', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          Expanded(
              child: Text('Stock Reconciliation',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800, color: sc))),
          if (_shrinkageKg > 0.01)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: sc, borderRadius: BorderRadius.circular(6)),
              child: Text('${_shrinkagePct.toStringAsFixed(1)}%',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ),
        ]),
        const SizedBox(height: 16),
        // Formula rows
        _simpleReconRow('📦 DC Loaded', '+$_dcBirds birds',
            '+${_dcKg.toStringAsFixed(1)} kg', Colors.blue, true),
        if (_transferInBirds > 0)
          _simpleReconRow('📥 Transfer In', '+$_transferInBirds birds',
              '+${_transferInKg.toStringAsFixed(1)} kg', Colors.teal, true),
        if (_transferOutBirds > 0)
          _simpleReconRow('📤 Transfer Out', '−$_transferOutBirds birds',
              '−${_transferOutKg.toStringAsFixed(1)} kg', Colors.indigo, false),
        _simpleReconRow('🚛 Delivered', '−$_deliveredBirds birds',
            '−${_deliveredKg.toStringAsFixed(1)} kg', kPrimary, false),
        if (_mortalityBirds > 0)
          _simpleReconRow('💀 Mortality', '−$_mortalityBirds birds',
              '−${_mortalityKg.toStringAsFixed(2)} kg', Colors.red, false),
        if (_mortReturnBirds > 0)
          _simpleReconRow(
              '💀 Mort-Return',
              '−$_mortReturnBirds birds',
              '−${_mortReturnWtEffective.toStringAsFixed(2)} kg'
                  '${_mortReturnWt == 0 ? '(auto)' : ''}',
              Colors.deepOrange,
              false),
        _simpleReconRow('📤 Live Return', '−$_returnBirds birds',
            '−${_returnWt.toStringAsFixed(1)} kg', Colors.purple, false),
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1)),
        // Shrinkage result
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: sc.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: sc.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            Icon(
                _shrinkagePct > 2
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_outline,
                color: sc,
                size: 22),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SHRINKAGE',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: sc,
                              letterSpacing: 0.6)),
                      Text(
                          '${_shrinkageKg.toStringAsFixed(2)} kg  (${_shrinkagePct.toStringAsFixed(1)}%)',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: sc)),
                    ])),
          ]),
        ),
        // Bird variance
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kBorder),
          ),
          child: Row(children: [
            const Icon(Icons.egg_alt_outlined, size: 16, color: kTextSub),
            const SizedBox(width: 6),
            Expanded(
                child: Text(
                    'Expected: $_expectedReturnBirds  ·  Live: $_returnBirds'
                        '${_mortReturnBirds > 0 ? "  ·  Dead: $_mortReturnBirds" : ""}',
                    style: const TextStyle(fontSize: 12, color: kTextSub))),
            Text(
                _birdVariance == 0
                    ? '✓ Matched'
                    : _birdVariance > 0
                    ? '−$_birdVariance missing'
                    : '+${-_birdVariance} extra',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _birdVariance == 0
                        ? Colors.green
                        : _birdVariance > 5
                        ? Colors.red
                        : Colors.orange)),
          ]),
        ),
        // Transfer notes
        if (_transferNotes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('TRANSFER DETAILS',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.teal,
                      letterSpacing: 0.6)),
              const SizedBox(height: 4),
              ..._transferNotes.map((n) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text('· $n',
                      style:
                      const TextStyle(fontSize: 11, color: Colors.teal)))),
            ]),
          ),
        ],
        // Alerts
        if (_birdVariance > 5) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.orange, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                  child: Text('Bird mismatch — trader will be notified',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange,
                          fontWeight: FontWeight.w600))),
            ]),
          ),
        ],
        if (_shrinkagePct > 5) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 18),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(
                      'Shrinkage ${_shrinkagePct.toStringAsFixed(1)}% exceeds 5% — trader approval required',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.w600))),
            ]),
          ),
        ],
      ]),
    );
  }

  // ── Simple Return Stock ──────────────────────────────────────────────────
  Widget _simpleReturnSection() {
    final declared = _returnBirds > 0 || _returnWt > 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: declared
                ? Colors.purple.shade200
                : (_stockBirds > 0 ? Colors.red.shade200 : kBorder),
            width: declared ? 2 : 1),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('📦', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          const Expanded(
              child: Text('Live Return Stock',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          if (_stockBirds > 0 && !declared)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.red, borderRadius: BorderRadius.circular(6)),
              child: const Text('REQUIRED',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ),
          // When mortality entered, show live/mort split in header badge
          if (declared && _mortReturnBirds > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.teal.shade100,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.teal.shade300)),
              child: Text('$_returnBirds live · $_mortReturnBirds dead',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
                      color: Colors.teal.shade800)),
            ),
        ]),
        if (_stockLoaded) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              const Icon(Icons.info_outline, color: Colors.blue, size: 16),
              const SizedBox(width: 8),
              Text(
                  'Expected: $_stockBirds birds · ${_stockKg.toStringAsFixed(1)} kg',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue)),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: TextField(
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => FocusScope.of(context).nextFocus(),
              controller: _returnBirdsCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              onChanged: (_) {
                if (mounted) setState(() {});
              },
              decoration: InputDecoration(
                labelText: 'Birds *',
                labelStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                suffixText: 'birds',
                suffixStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => FocusScope.of(context).nextFocus(),
              controller: _returnWtCtrl,
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              onChanged: (_) {
                if (mounted) setState(() {});
              },
              decoration: InputDecoration(
                labelText: 'Weight *',
                labelStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                suffixText: 'kg',
                suffixStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              ),
            ),
          ),
        ]),
        // Weighment variance indicator
        if (declared && _stockLoaded) ...[
          const SizedBox(height: 10),
          Builder(builder: (_) {
            final expectedKg = _expectedReturnKg;
            final varKg = _returnWt - expectedKg;
            final varColor = varKg.abs() < 0.5
                ? Colors.green
                : varKg.abs() < 2.0
                ? Colors.orange
                : Colors.red;
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: varColor.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: varColor.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                Icon(
                    varKg.abs() < 0.5
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_rounded,
                    color: varColor,
                    size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    varKg.abs() < 0.1
                        ? 'Weight matches expected ✓'
                        : 'Weight variance: ${varKg > 0 ? "+" : ""}${varKg.toStringAsFixed(2)} kg (expected ${expectedKg.toStringAsFixed(1)} kg)',
                    style: TextStyle(
                        fontSize: 13,
                        color: varColor,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            );
          }),
        ],
        const SizedBox(height: 14),
        // Confirmation status
        if (declared) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.purple.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              Icon(
                  _returnPhotoUrl != null
                      ? Icons.verified_outlined
                      : Icons.pending_outlined,
                  color: _returnPhotoUrl != null ? Colors.green : Colors.purple,
                  size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    '$_returnBirds live birds · ${_returnWt.toStringAsFixed(1)} kg'
                        '${_returnPhotoUrl != null ? " — Weighed & photographed ✓" : " — Add photo to complete"}',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                        color: _returnPhotoUrl != null ? Colors.green : Colors.purple)),
              ),
            ]),
          ),
          const SizedBox(height: 12),
        ],
        // Photo tiles
        Row(children: [
          Expanded(
              child: _simplePhotoTile(
                label: 'Return Photo',
                required: declared,
                file: _returnPhotoFile,
                uploaded: _returnPhotoUrl != null,
                uploading: _uploadingReturn,
                onTap: () => _capture('return'),
              )),
          const SizedBox(width: 8),
          Expanded(
              child: _simplePhotoTile(
                label: 'Weigh Slip',
                required: false,
                file: _returnSlipFile,
                uploaded: _returnSlipUrl != null,
                uploading: _uploadingReturnSlip,
                onTap: () => _capture('return-slip'),
              )),
        ]),
      ]),
    );
  }

  // ── Simple Mortality ─────────────────────────────────────────────────────
  Widget _simpleMortalitySection() {
    final hasMort = _mortalityBirds > 0 || _mortReturnBirds > 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: hasMort ? Colors.red.shade200 : kBorder,
            width: hasMort ? 2 : 1),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('💀', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          const Expanded(
              child: Text('Mortality',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          if (hasMort && _mortalityPhotoUrl == null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.red, borderRadius: BorderRadius.circular(6)),
              child: const Text('PHOTO NEEDED',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ),
        ]),
        if (_mortalityBirds > 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              _simpleKpi('💀', '$_mortalityBirds', 'During Delivery'),
              if (_mortalityKg > 0)
                _simpleKpi(
                    '⚖️', '${_mortalityKg.toStringAsFixed(1)} kg', 'Weight'),
            ]),
          ),
        ],
        if (_mortReturnBirds > 0) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.deepOrange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.deepOrange.shade200)),
            child: Row(children: [
              _simpleKpi('💀', '$_mortReturnBirds', 'During Return'),
              if (_mortReturnWt > 0)
                _simpleKpi(
                    '⚖️', '${_mortReturnWtEffective.toStringAsFixed(1)} kg', 'Weight'),
            ]),
          ),
        ],
        if (hasMort) ...[
          // Reason + photo (key action)
          const SizedBox(height: 14),
          TextField(
            controller: _mortalityReasonCtrl,
            maxLines: 2,
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              labelText: 'Reason *',
              labelStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              hintText: 'Disease, injury, heat stress...',
              border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
          const SizedBox(height: 14),
          _simplePhotoTile(
            label: _mortalityPhotoUrl != null
                ? 'Photo Captured ✓'
                : 'Mortality Proof Photo *',
            required: true,
            file: _mortalityPhotoFile,
            uploaded: _mortalityPhotoUrl != null,
            uploading: _uploadingMortality,
            onTap: () => _capture('mortality'),
          ),
          if (_mortalityPhotoUrl == null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10)),
              child: const Row(children: [
                Icon(Icons.block, color: Colors.red, size: 16),
                SizedBox(width: 8),
                Expanded(
                    child: Text(
                      'Photo required before closing shift',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.red,
                          fontWeight: FontWeight.w600),
                    )),
              ]),
            ),
          ],
        ] else ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12)),
            child: const Row(children: [
              Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
              SizedBox(width: 10),
              Text('No mortality recorded',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.green)),
            ]),
          ),
        ],
        // ── Return Mortality ──────────────────────────────────────
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.deepOrange.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.deepOrange.shade200),
          ),
          child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.deepOrange, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                  child: Text('Mortality During Return',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.deepOrange))),
            ]),
            const SizedBox(height: 4),
            const Text(
                'Birds that died during transport back to stock point after shift close.',
                style: TextStyle(fontSize: 11, color: kTextHint, height: 1.4)),
            const SizedBox(height: 10),
            // Inputs
            Row(children: [
              Expanded(
                child: TextField(
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                  controller: _mortReturnBirdsCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800),
                  onChanged: (_) {
                    if (mounted) setState(() {});
                  },
                  decoration: InputDecoration(
                    labelText: 'Dead Birds',
                    suffixText: 'birds',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                  controller: _mortReturnWtCtrl,
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800),
                  onChanged: (_) {
                    if (mounted) setState(() {});
                  },
                  decoration: InputDecoration(
                    labelText: 'Weight (kg)',
                    suffixText: 'kg',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                  ),
                ),
              ),
            ]),
            if (_mortReturnBirds > 0) ...[
              const SizedBox(height: 12),
              const Text('PHOTO EVIDENCE',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: kTextHint,
                      letterSpacing: 0.6)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                    child: _simplePhotoTile(
                      label: 'Return Mortality Photo',
                      required: true,
                      file: _mortReturnPhotoFile,
                      uploaded: _mortReturnPhotoUrl != null,
                      uploading: _uploadingMortReturn,
                      onTap: () => _capture('mort-return'),
                    )),
                const SizedBox(width: 8),
                Expanded(
                    child: _simplePhotoTile(
                      label: 'Weigh Slip',
                      required: false,
                      file: _mortReturnSlipFile,
                      uploaded: _mortReturnSlipUrl != null,
                      uploading: _uploadingMortReturnSlip,
                      onTap: () => _capture('mort-return-slip'),
                    )),
              ]),
            ],
          ]),
        ),
        // Combined total
        if (_totalMortalityBirds > 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              const Icon(Icons.summarize_outlined, color: Colors.red, size: 18),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(
                      'Total mortality: ${_totalMortalityBirds} birds · ${_totalMortalityKg.toStringAsFixed(2)} kg',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.red))),
              const Text('Deducted from shrinkage',
                  style: TextStyle(fontSize: 10, color: kTextHint)),
            ]),
          ),
        ],
      ]),
    );
  }

  // ── Simple Odometer ──────────────────────────────────────────────────────
  Widget _simpleOdometerSection() {
    final odoStart = ((_shift!['odometer_start']) as num?)?.toDouble() ?? 0;
    final odoEnd = double.tryParse(_odoEndCtrl.text.trim()) ?? 0;
    final km = odoEnd > odoStart ? odoEnd - odoStart : 0.0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('⛽', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          const Expanded(
              child: Text('Odometer Reading',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(children: [
                const Text('Start',
                    style: TextStyle(fontSize: 11, color: kTextHint)),
                Text('${odoStart.toStringAsFixed(0)} km',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w900)),
              ]),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => FocusScope.of(context).nextFocus(),
              controller: _odoEndCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              onChanged: (_) {
                if (mounted) setState(() {});
              },
              decoration: InputDecoration(
                labelText: 'End *',
                labelStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                suffixText: 'km',
                suffixStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              ),
            ),
          ),
        ]),
        if (km > 0) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              const Icon(Icons.route, color: Colors.indigo, size: 20),
              const SizedBox(width: 8),
              Text('$km km travelled',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.indigo)),
            ]),
          ),
        ],
        const SizedBox(height: 14),
        _simplePhotoTile(
          label: 'End Odo Photo',
          required: false,
          file: _odoPhotoFile,
          uploaded: _odoPhotoUrl != null,
          uploading: _uploadingOdo,
          onTap: () => _capture('odo'),
        ),
      ]),
    );
  }

  // ── Simple Expenses ─────────────────────────────────────────────────────
  Widget _simpleExpensesSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: _totalExpenses > 0 ? Colors.orange.shade200 : kBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('💰', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          const Expanded(
              child: Text('Expenses & Allowances',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          if (_totalExpenses > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Text(Fmt.amount(_totalExpenses),
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.orange)),
            ),
        ]),
        const SizedBox(height: 16),
        // Diesel, Allowance, Toll
        Row(children: [
          Expanded(
              child: _simpleExpField(
                  _dieselCtrl, '⛽ Diesel', Icons.local_gas_station)),
          const SizedBox(width: 8),
          Expanded(
              child: _simpleExpField(
                  _allowanceCtrl, '💰 Allowance', Icons.card_giftcard)),
          const SizedBox(width: 8),
          Expanded(child: _simpleExpField(_tollCtrl, '🚧 Toll', Icons.toll)),
        ]),
        const SizedBox(height: 14),
        // Custom expenses list
        ..._expenses.asMap().entries.map((e) {
          final idx = e.key;
          final exp = e.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(children: [
              Expanded(
                child: Text(
                    '${_expLabel(exp['type'] as String)}  ₹${(exp['amount'] as double).toStringAsFixed(0)}'
                        '${(exp['notes'] as String?)?.isNotEmpty == true ? "  ·  ${exp['notes']}" : ""}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              GestureDetector(
                onTap: () => setState(() => _expenses.removeAt(idx)),
                child: const Icon(Icons.remove_circle_outline,
                    color: Colors.red, size: 20),
              ),
            ]),
          );
        }),
        const SizedBox(height: 8),
        // Add expense form
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _expType,
              isDense: true,
              decoration: InputDecoration(
                labelText: 'Type',
                border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: ['vehicle', 'loading', 'misc', 'food', 'other']
                  .map((t) => DropdownMenuItem(
                  value: t,
                  child: Text(_expLabel(t),
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1)))
                  .toList(),
              onChanged: (v) => setState(() => _expType = v!),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => FocusScope.of(context).nextFocus(),
              controller: _expAmtCtrl,
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                labelText: 'Amount ₹',
                prefixText: '₹',
                border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => FocusScope.of(context).nextFocus(),
              controller: _expNoteCtrl,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Note (optional)',
                border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(52, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: EdgeInsets.zero,
              ),
              onPressed: () {
                final amt = double.tryParse(_expAmtCtrl.text.trim()) ?? 0;
                if (amt <= 0) return;
                setState(() {
                  _expenses.add({
                    'type': _expType,
                    'amount': amt,
                    'notes': _expNoteCtrl.text.trim(),
                  });
                  _expAmtCtrl.clear();
                  _expNoteCtrl.clear();
                });
              },
              child: const Icon(Icons.add, size: 22),
            ),
          ),
        ]),
        if (_totalExpenses > 0) ...[
          const SizedBox(height: 12),
          Row(children: [
            const Spacer(),
            Text('Total: ${Fmt.amount(_totalExpenses)}',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.orange)),
          ]),
        ],
      ]),
    );
  }

  // ── Simple Expense Field ─────────────────────────────────────────────────
  Widget _simpleExpField(
      TextEditingController c, String label, IconData icon) =>
      TextField(
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        onChanged: (_) {
          if (mounted) setState(() {});
        },
        decoration: InputDecoration(
          labelText: label,
          prefixText: '₹',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      );

  // ── Simple Info Tile ─────────────────────────────────────────────────────
  Widget _simpleInfoTile(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: kBorder),
    ),
    child: Row(children: [
      Expanded(
        child:
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(fontSize: 9, color: kTextHint)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ]),
      ),
    ]),
  );

  // ── Simple Recon Row ─────────────────────────────────────────────────────
  Widget _simpleReconRow(
      String label, String birds, String kg, Color c, bool isIn) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(shape: BoxShape.circle, color: c)),
          const SizedBox(width: 10),
          Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 12, color: kTextSub))),
          Text(birds,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isIn ? Colors.green.shade700 : Colors.red.shade700)),
          const SizedBox(width: 8),
          SizedBox(
              width: 90,
              child: Text(kg,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color:
                      isIn ? Colors.green.shade700 : Colors.red.shade700))),
        ]),
      );

  // ── Simple Close Button ──────────────────────────────────────────────────
  Widget _simpleCloseButton(_RStatus st) {
    final canClose = !_submitting &&
        st != _RStatus.pending &&
        st != _RStatus.loading &&
        st != _RStatus.mortProofRequired &&
        st != _RStatus.returnExceedsStock;
    String label;
    Color color;
    IconData icon;
    switch (st) {
      case _RStatus.returnExceedsStock:
        label = '⛔ Fix Bird Count — Return Exceeds Stock';
        color = Colors.red.shade900;
        icon = Icons.block;
      case _RStatus.mortProofRequired:
        label = '📷 Capture Mortality Photo First';
        color = Colors.red.shade700;
        icon = Icons.camera_alt;
      case _RStatus.pending:
        label = '⏳ Complete Pending Deliveries First';
        color = Colors.orange;
        icon = Icons.hourglass_empty;
      case _RStatus.loading:
        label = '⏳ Loading...';
        color = Colors.grey;
        icon = Icons.hourglass_empty;
      case _RStatus.mismatch:
      case _RStatus.highShrinkage:
        label = '⚠️ Close Shift (Requires Trader Review)';
        color = Colors.red;
        icon = Icons.warning_amber_rounded;
      case _RStatus.approvalNeeded:
        label = '⏳ Close Shift (Approval Needed)';
        color = Colors.orange;
        icon = Icons.pending;
      case _RStatus.balanced:
        label = '✅ CLOSE SHIFT';
        color = kPrimary;
        icon = Icons.lock_outline;
    }

    return SizedBox(
      width: double.infinity,
      height: 64,
      child: ElevatedButton.icon(
        onPressed: canClose ? _doClose : null,
        icon: _submitting
            ? const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
                strokeWidth: 3, color: Colors.white))
            : Icon(icon, size: 26),
        label: Text(label,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          elevation: 0,
        ),
      ),
    );
  }

  // ── Simple Photo Tile ────────────────────────────────────────────────────
  Widget _simplePhotoTile({
    required String label,
    required bool required,
    required File? file,
    required bool uploaded,
    required bool uploading,
    required VoidCallback onTap,
  }) {
    final Color c = uploaded
        ? Colors.green
        : required
        ? Colors.red.shade400
        : kTextHint;
    return GestureDetector(
      onTap: uploading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: uploaded
              ? Colors.green.shade50
              : required
              ? Colors.red.shade50
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          file != null
              ? ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(file!,
                  width: 44, height: 44, fit: BoxFit.cover))
              : Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.camera_alt, color: c, size: 22)),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700, color: c)),
                    Text(
                        uploading
                            ? 'Uploading...'
                            : uploaded
                            ? '✓ Uploaded'
                            : 'Tap to capture',
                        style: const TextStyle(fontSize: 10, color: kTextHint)),
                  ])),
          if (uploading)
            const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
          else if (uploaded)
            const Icon(Icons.check_circle, color: Colors.green, size: 20)
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Text('Capture',
                  style: TextStyle(
                      fontSize: 11, color: c, fontWeight: FontWeight.w700)),
            ),
        ]),
      ),
    );
  }

  Widget _noShift() => Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.info_outline, size: 56, color: kTextHint),
        const SizedBox(height: 12),
        const Text('No active shift found',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: kTextSub)),
        const SizedBox(height: 24),
        ElevatedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry')),
        const SizedBox(height: 12),
        OutlinedButton(
            onPressed: () => context.go(R.agentHome),
            child: const Text('Go Home')),
      ]));

  // ── HELPERS ──────────────────────────────────────────────────────────────
  int get _expectedReturnBirds => _stockBirds.clamp(0, 999999);

  double get _expectedReturnKg => _stockKg.clamp(0.0, 999999.0);

  Widget _expField(TextEditingController c, String label) => TextField(
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => FocusScope.of(context).unfocus(),
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) {
        if (mounted) setState(() {});
      },
      decoration: InputDecoration(
          labelText: label,
          prefixText: '₹',
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 10)));

  Widget _tile(String l, String v, IconData ic) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kBorder)),
      child: Row(children: [
        Icon(ic, size: 13, color: kTextHint),
        const SizedBox(width: 6),
        Expanded(
            child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l, style: const TextStyle(fontSize: 8, color: kTextHint)),
              Text(v,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ])),
      ]));

  Widget _kpi(String l, String v, Color c) => Expanded(
      child: Column(children: [
        Text(v,
            style:
            TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c),
            textAlign: TextAlign.center),
        Text(l,
            style: const TextStyle(fontSize: 9, color: kTextHint),
            textAlign: TextAlign.center),
      ]));

  Widget _alert(IconData ic, String msg, Color c) => Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.withValues(alpha: 0.3))),
      child: Row(children: [
        Icon(ic, color: c, size: 13),
        const SizedBox(width: 6),
        Expanded(
            child: Text(msg,
                style: TextStyle(
                    fontSize: 10, color: c, fontWeight: FontWeight.w600))),
      ]));

  Widget _rrow(String label, String birds, String kg, Color c, bool isIn) =>
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(shape: BoxShape.circle, color: c)),
            const SizedBox(width: 8),
            Expanded(
                child: Text(label,
                    style: const TextStyle(fontSize: 11, color: kTextSub))),
            Text(birds,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isIn ? Colors.green.shade700 : Colors.red.shade700)),
            const SizedBox(width: 8),
            SizedBox(
                width: 84,
                child: Text(kg,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isIn
                            ? Colors.green.shade700
                            : Colors.red.shade700))),
          ]));

  String _expLabel(String t) => switch (t) {
    'fuel' || 'diesel' => '⛽ Fuel',
    'toll' => '🚧 Toll',
    'allowance' => '💰 Allowance',
    'vehicle' => '🔧 Vehicle',
    'loading' => '📦 Loading',
    'food' => '🍽 Food',
    _ => '📋 Misc',
  };
}

// =============================================================================
// STATUS ENUM
// =============================================================================
enum _RStatus {
  balanced,
  approvalNeeded,
  highShrinkage,
  mismatch,
  pending,
  loading,
  mortProofRequired,
  returnExceedsStock  // live + dead return > available stock
}

// =============================================================================
// COLLAPSIBLE SECTION CARD
// =============================================================================
class _Card extends StatelessWidget {
  const _Card(
      {required this.title,
        required this.icon,
        required this.iconColor,
        required this.child,
        required this.expanded,
        this.onToggle,
        this.badge,
        this.badgeColor});

  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget child;
  final bool expanded;
  final VoidCallback? onToggle;
  final String? badge;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ]),
      child: Column(children: [
        InkWell(
            onTap: onToggle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(children: [
                  Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                          color: iconColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8)),
                      child: Icon(icon, color: iconColor, size: 15)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(title,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w800))),
                  if (badge != null)
                    Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                            color: (badgeColor ?? Colors.grey)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: (badgeColor ?? Colors.grey)
                                    .withValues(alpha: 0.3))),
                        child: Text(badge!,
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: badgeColor ?? Colors.grey))),
                  if (onToggle != null)
                    Icon(
                        expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: kTextHint,
                        size: 18),
                ]))),
        if (expanded) ...[
          const Divider(height: 1),
          Padding(padding: const EdgeInsets.all(14), child: child),
        ],
      ]));
}

// =============================================================================
// PHOTO TILE
// =============================================================================
class _PhotoTile extends StatelessWidget {
  const _PhotoTile(
      {required this.label,
        required this.sublabel,
        required this.required,
        required this.file,
        required this.uploaded,
        required this.uploading,
        required this.onTap});

  final String label, sublabel;
  final bool required, uploaded, uploading;
  final File? file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color c = uploaded
        ? Colors.green
        : required
        ? Colors.red.shade400
        : kTextHint;
    return GestureDetector(
        onTap: uploading ? null : onTap,
        child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: uploaded
                    ? Colors.green.shade50
                    : required
                    ? Colors.red.shade50
                    : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.withValues(alpha: 0.3))),
            child: Row(children: [
              file != null
                  ? ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(file!,
                      width: 42, height: 42, fit: BoxFit.cover))
                  : Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                      color: c.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child:
                  Icon(Icons.camera_alt_outlined, color: c, size: 18)),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: c)),
                        Text(
                            uploading
                                ? 'Uploading...'
                                : uploaded
                                ? '✓ Uploaded'
                                : sublabel,
                            style: const TextStyle(fontSize: 10, color: kTextHint)),
                      ])),
              if (uploading)
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else if (uploaded)
                const Icon(Icons.check_circle, color: Colors.green, size: 16)
              else
                Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text('Capture',
                        style: TextStyle(
                            fontSize: 10,
                            color: c,
                            fontWeight: FontWeight.w700))),
            ])));
  }
}