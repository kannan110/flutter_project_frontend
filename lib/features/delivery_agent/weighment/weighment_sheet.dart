// weighment_sheet.dart
// Two-phase Bluetooth weighment bottom sheet for Rooster Trader
// Phase 1 → LOAD WT: capture bird+cage batches from Bluetooth scale or manual
// Phase 2 → EMPTY WT: capture empty cage weights in sequence
// Returns WeighmentResult to DeliveryCompleteScreen via Navigator.pop()

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'weighment_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Entry point — call this from DeliveryCompleteScreen:
//   final result = await WeighmentSheet.show(context, deliveryId: widget.deliveryId);
//   if (result != null) { /* auto-fill fields */ }
// ─────────────────────────────────────────────────────────────────────────────

class WeighmentSheet extends StatefulWidget {
  final String deliveryId;
  final int    prefillBirds;    // from DC challan
  final double prefillWeight;   // from DC challan net weight

  const WeighmentSheet({
    super.key,
    required this.deliveryId,
    this.prefillBirds  = 0,
    this.prefillWeight = 0,
  });

  static Future<WeighmentResult?> show(
    BuildContext context, {
    required String deliveryId,
    int    prefillBirds  = 0,
    double prefillWeight = 0,
  }) {
    return showModalBottomSheet<WeighmentResult>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WeighmentSheet(
        deliveryId:    deliveryId,
        prefillBirds:  prefillBirds,
        prefillWeight: prefillWeight,
      ),
    );
  }

  @override State<WeighmentSheet> createState() => _WeighmentSheetState();
}

class _WeighmentSheetState extends State<WeighmentSheet> {
  final _bt      = WeighmentBluetoothService();
  late  WeighmentSession _session;

  // BT state
  List<BluetoothDevice> _devices  = [];
  BluetoothDevice?      _selected;
  bool   _scanning    = false;
  bool   _connecting  = false;
  double _liveWeight  = 0;        // streaming weight from scale
  StreamSubscription? _weightSub;
  bool   _weightStable = false;   // true when weight has been stable for 0.8s
  double _lastEmitted  = 0;
  Timer? _stabilityTimer;

  // Manual entry fallback
  final _manualWtCtrl    = TextEditingController();
  final _cagesCtrl       = TextEditingController(text: '1');

  // Birds modal
  final _birdsCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _session = WeighmentSession(
      deliveryId: widget.deliveryId,
      totalBirds: widget.prefillBirds,
    );
    _startWeightStream();
    _scanDevices();
  }

  @override
  void dispose() {
    _weightSub?.cancel();
    _stabilityTimer?.cancel();
    _bt.dispose();
    _manualWtCtrl.dispose();
    _cagesCtrl.dispose();
    _birdsCtrl.dispose();
    super.dispose();
  }

  void _startWeightStream() {
    _weightSub = _bt.weightStream.listen((w) {
      if (!mounted) return;
      setState(() { _liveWeight = w; _weightStable = false; });

      // Stability detection: if weight doesn't change for 0.8s → mark stable
      _stabilityTimer?.cancel();
      _stabilityTimer = Timer(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        if ((_liveWeight - _lastEmitted).abs() < 0.01) {
          setState(() => _weightStable = true);
        }
        _lastEmitted = _liveWeight;
      });
    });
  }

  Future<void> _scanDevices() async {
    if (!mounted) return;
    setState(() { _scanning = true; _devices = []; });
    try {
      final bonded  = await _bt.getBondedDevices();
      final scanned = await _bt.scanForScales(timeout: const Duration(seconds: 5));
      final all     = [...bonded];
      for (final d in scanned) {
        if (!all.any((b) => b.remoteId == d.remoteId)) all.add(d);
      }
      if (mounted) setState(() { _devices = all; _scanning = false; });
    } catch (_) {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _connectDevice(BluetoothDevice device) async {
    setState(() { _connecting = true; _selected = device; });
    final ok = await _bt.connect(device);
    if (mounted) {
      setState(() => _connecting = false);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not connect. Try again.')));
        setState(() => _selected = null);
      }
    }
  }

  // ── Phase 1: capture load weight row ─────────────────────────────────────

  void _captureLoadWeight() {
    final wt    = _bt.isConnected ? _liveWeight : (double.tryParse(_manualWtCtrl.text.trim()) ?? 0);
    final cages = int.tryParse(_cagesCtrl.text.trim()) ?? 1;
    if (wt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Weight must be > 0')));
      return;
    }
    final now = TimeOfDay.now();
    final h   = now.hourOfPeriod == 0 ? 12 : now.hourOfPeriod;
    final time = '${h.toString().padLeft(2,'0')}:'
                 '${now.minute.toString().padLeft(2,'0')}:00 '
                 '${now.period == DayPeriod.am ? 'AM' : 'PM'}';
    final row  = WeighmentRow(
      seqNo:     _session.rows.length + 1,
      loadWt:    wt,
      loadCages: cages,
      wmtTime:   time,
    );
    setState(() {
      _session.rows.add(row);
      _manualWtCtrl.clear();
      _cagesCtrl.text = '1';
      _liveWeight     = 0;
      _weightStable   = false;
    });
    HapticFeedback.lightImpact();
  }

  void _deleteLoadRow(int index) {
    if (_session.loadLocked) return;
    setState(() => _session.rows.removeAt(index));
  }

  // ── Lock Load WT + ask total birds ───────────────────────────────────────

  Future<void> _lockLoadWT() async {
    if (_session.rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add at least one load entry first.')));
      return;
    }
    _birdsCtrl.text = _session.totalBirds > 0 ? '${_session.totalBirds}' : '';
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Enter Total Birds Count'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Total Load WT: ${_session.totalLoadWt.toStringAsFixed(3)} kg\n'
             'Total Cages: ${_session.totalLoadCages}',
             style: const TextStyle(fontSize: 13, color: Colors.grey)),
        const SizedBox(height: 16),
        TextField(
          controller: _birdsCtrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Total Birds *',
            helperText: 'Count all birds in all batches combined'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final b = int.tryParse(_birdsCtrl.text.trim()) ?? 0;
            if (b <= 0) return;
            Navigator.pop(ctx, true);
          },
          child: const Text('Lock & Proceed to Empty WT')),
      ],
    )) ?? false;

    if (confirmed && mounted) {
      final birds = int.tryParse(_birdsCtrl.text.trim()) ?? 0;
      if (birds <= 0) return;
      setState(() {
        _session.totalBirds = birds;
        _session.loadLocked  = true;
        _session.phase       = WeighmentPhase.empty;
        _liveWeight          = 0;
        _weightStable        = false;
        _manualWtCtrl.clear();
        _cagesCtrl.text = '1';
      });
    }
  }

  void _unlockLoadWT() {
    setState(() {
      _session.loadLocked = false;
      _session.phase      = WeighmentPhase.load;
      _liveWeight         = 0;
    });
  }

  // ── Phase 2: capture empty weight ────────────────────────────────────────

  void _captureEmptyWeight() {
    final next = _session.nextEmptyRow;
    if (next == null) return;

    final wt    = _bt.isConnected ? _liveWeight : (double.tryParse(_manualWtCtrl.text.trim()) ?? 0);
    final cages = int.tryParse(_cagesCtrl.text.trim()) ?? next.loadCages;
    if (wt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Weight must be > 0')));
      return;
    }

    setState(() {
      final idx = _session.rows.indexWhere((r) => r.seqNo == next.seqNo);
      _session.rows[idx] = next.copyWith(emptyWt: wt, emptyCages: cages);
      _manualWtCtrl.clear();
      _cagesCtrl.text = '1';
      _liveWeight     = 0;
      _weightStable   = false;
    });
    HapticFeedback.lightImpact();
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  void _submit() {
    if (!_session.allEmptyFilled) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All empty weights must be filled.')));
      return;
    }
    if (!_session.cagesMatch) {
      showDialog(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Cage Count Mismatch'),
        content: Text('Load cages: ${_session.totalLoadCages}\n'
                      'Empty cages: ${_session.totalEmptyCages}\n\n'
                      'These must match. Correct the empty cage entries.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ));
      return;
    }
    Navigator.of(context, rootNavigator: true).pop(_session.toResult());
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mq      = MediaQuery.of(context);
    final sheetH  = mq.size.height * 0.92;
    final phase   = _session.phase;
    final locked  = _session.loadLocked;

    return Container(
      height: sheetH,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [

        // ── Handle ────────────────────────────────────────────────
        Container(margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),

        // ── Header ────────────────────────────────────────────────
        _buildHeader(phase, locked),

        // ── BT Connection bar ─────────────────────────────────────
        _buildBluetoothBar(),

        // ── Live weight display ───────────────────────────────────
        if (_bt.isConnected) _buildLiveWeightDisplay(),

        // ── Main content ──────────────────────────────────────────
        Expanded(child: ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [

          // Phase indicator
          _buildPhaseIndicator(phase),
          const SizedBox(height: 12),

          // Summary row
          if (_session.rows.isNotEmpty) _buildSummaryRow(),
          const SizedBox(height: 8),

          // Table
          if (_session.rows.isNotEmpty) _buildRowsTable(phase),
          const SizedBox(height: 12),

          // Input area
          if (!locked || phase == WeighmentPhase.empty) _buildInputArea(phase),

          const SizedBox(height: 12),

          // Action buttons
          _buildActionButtons(phase, locked),
          const SizedBox(height: 20),
        ])),
      ]),
    );
  }

  Widget _buildHeader(WeighmentPhase phase, bool locked) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Weighment', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        Text(
          phase == WeighmentPhase.load
              ? 'Phase 1 — Load Weight (birds + cages)'
              : 'Phase 2 — Empty Weight (cages only)',
          style: TextStyle(fontSize: 11, color: phase == WeighmentPhase.load ? Colors.blue : Colors.orange)),
      ])),
      IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.of(context, rootNavigator: true).pop(null)),
    ]),
  );

  Widget _buildBluetoothBar() => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: _bt.isConnected ? Colors.green.shade50 : Colors.grey.shade50,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _bt.isConnected ? Colors.green.shade200 : Colors.grey.shade200)),
    child: Row(children: [
      Icon(_bt.isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
          color: _bt.isConnected ? Colors.green : Colors.grey, size: 20),
      const SizedBox(width: 8),
      Expanded(child: _bt.isConnected
          ? Text('Connected: ${_selected?.platformName ?? 'Scale'}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.green))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('No scale connected — manual entry available',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
              if (_devices.isNotEmpty)
                DropdownButton<BluetoothDevice>(
                  hint: const Text('Select scale', style: TextStyle(fontSize: 12)),
                  isExpanded: true, isDense: true,
                  value: _selected,
                  items: _devices.map((d) => DropdownMenuItem(
                    value: d,
                    child: Text(d.platformName.isEmpty ? d.remoteId.toString() : d.platformName,
                        style: const TextStyle(fontSize: 12)))).toList(),
                  onChanged: (d) { if (d != null) _connectDevice(d); }),
            ])),
      if (_connecting) const SizedBox(width: 18, height: 18,
          child: CircularProgressIndicator(strokeWidth: 2))
      else if (!_bt.isConnected) ...[
        if (_scanning) const SizedBox(width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2))
        else IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'Scan',
            onPressed: _scanDevices),
      ] else IconButton(
          icon: const Icon(Icons.bluetooth_disabled, size: 18, color: Colors.red),
          tooltip: 'Disconnect',
          onPressed: () async { await _bt.disconnect(); setState(() { _selected = null; _liveWeight = 0; }); }),
    ]),
  );

  Widget _buildLiveWeightDisplay() => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [Colors.blue.shade700, Colors.blue.shade500]),
      borderRadius: BorderRadius.circular(12)),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Column(children: [
        Text('${_liveWeight.toStringAsFixed(3)} kg',
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white,
                letterSpacing: 1, fontFeatures: [FontFeature.tabularFigures()])),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _weightStable ? Colors.greenAccent : Colors.orangeAccent)),
          Text(_weightStable ? 'STABLE — tap + to capture' : 'Live reading...',
              style: TextStyle(fontSize: 11, color: _weightStable ? Colors.greenAccent : Colors.white70)),
        ]),
      ]),
    ]),
  );

  Widget _buildPhaseIndicator(WeighmentPhase phase) => Row(children: [
    _phaseChip('1  LOAD WT', phase == WeighmentPhase.load, Colors.blue,
        done: _session.loadLocked),
    const SizedBox(width: 8),
    Container(width: 20, height: 2, color: Colors.grey.shade300),
    const SizedBox(width: 8),
    _phaseChip('2  EMPTY WT', phase == WeighmentPhase.empty, Colors.orange),
  ]);

  Widget _phaseChip(String label, bool active, Color c, {bool done = false}) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(
        color: done ? Colors.green.shade50 : active ? c.withOpacity(0.1) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: done ? Colors.green : active ? c : Colors.grey.shade300, width: done || active ? 1.5 : 0.5)),
    child: Text(done ? '✓ $label' : label, textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
            color: done ? Colors.green : active ? c : Colors.grey))));

  Widget _buildSummaryRow() => Row(children: [
    _summaryChip('Rows', '${_session.rows.length}', Colors.blue),
    const SizedBox(width: 8),
    _summaryChip('Total Load', '${_session.totalLoadWt.toStringAsFixed(2)} kg', Colors.indigo),
    const SizedBox(width: 8),
    _summaryChip('Net WT', '${_session.totalNetWt.toStringAsFixed(2)} kg', Colors.green),
    const SizedBox(width: 8),
    _summaryChip('Avg/Bird', _session.totalBirds > 0
        ? '${(_session.avgBirdWt * 1000).toStringAsFixed(0)}g' : '—', Colors.teal),
  ]);

  Widget _summaryChip(String l, String v, Color c) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(vertical: 6),
    decoration: BoxDecoration(color: c.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
    child: Column(children: [
      Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c)),
      Text(l, style: const TextStyle(fontSize: 9, color: Colors.grey)),
    ])));

  Widget _buildRowsTable(WeighmentPhase phase) {
    final nextSeq = _session.nextEmptyRow?.seqNo;
    return Column(children: [
      // Header
      Container(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
        child: const Row(children: [
          SizedBox(width: 24, child: Text('#', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700))),
          Expanded(child: Text('Load WT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700))),
          Expanded(child: Text('Empty WT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700))),
          Expanded(child: Text('Net WT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700))),
          SizedBox(width: 28),
        ])),
      const SizedBox(height: 4),
      ..._session.rows.map((row) {
        final isNext = row.seqNo == nextSeq;
        final filled = row.emptyFilled;
        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
            color: isNext ? Colors.orange.shade50 : filled ? Colors.green.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isNext ? Colors.orange.shade300 : filled ? Colors.green.shade200 : Colors.grey.shade200)),
          child: Row(children: [
            SizedBox(width: 24, child: Text('${row.seqNo}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                    color: isNext ? Colors.orange : filled ? Colors.green : Colors.black))),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${row.loadWt.toStringAsFixed(3)} kg',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              Text('${row.loadCages} cages · ${row.wmtTime}',
                  style: const TextStyle(fontSize: 9, color: Colors.grey)),
            ])),
            Expanded(child: row.emptyFilled
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${row.emptyWt.toStringAsFixed(3)} kg',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.orange)),
                    Text('${row.emptyCages} cages', style: const TextStyle(fontSize: 9, color: Colors.grey)),
                  ])
                : Text(isNext ? '← Enter now' : '—',
                    style: TextStyle(fontSize: 11, color: isNext ? Colors.orange : Colors.grey.shade400))),
            Expanded(child: row.emptyFilled
                ? Text('${row.netWt.toStringAsFixed(3)} kg',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.green))
                : const Text('—', style: TextStyle(color: Colors.grey))),
            SizedBox(width: 28, child: phase == WeighmentPhase.load
                ? IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                    icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                    onPressed: () => _deleteLoadRow(_session.rows.indexOf(row)))
                : const SizedBox.shrink()),
          ]),
        );
      }),
    ]);
  }

  Widget _buildInputArea(WeighmentPhase phase) {
    final isLoad  = phase == WeighmentPhase.load;
    final next    = _session.nextEmptyRow;
    final label   = isLoad ? 'Load WT (kg)' : 'Empty WT (kg) — Row ${next?.seqNo ?? '?'}';
    final hint    = isLoad ? 'e.g. 85.340' : 'e.g. 18.200';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isLoad ? Colors.blue.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isLoad ? Colors.blue.shade200 : Colors.orange.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(isLoad ? 'Add Load Batch' : 'Enter Empty Weight — Row ${next?.seqNo}',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                color: isLoad ? Colors.blue.shade700 : Colors.orange.shade700)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextFormField(
            controller: _manualWtCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: _bt.isConnected ? '${_liveWeight.toStringAsFixed(3)} kg (live)' : label,
              hintText: hint,
              suffixText: 'kg',
              enabled: !_bt.isConnected, // disable manual when BT connected
            ),
            onChanged: (_) => setState(() {}),
          )),
          const SizedBox(width: 10),
          SizedBox(width: 90, child: TextFormField(
            controller: _cagesCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Cages'),
          )),
          const SizedBox(width: 10),
          // Capture button
          SizedBox(height: 52, width: 52,
            child: ElevatedButton(
              onPressed: isLoad ? _captureLoadWeight : _captureEmptyWeight,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: isLoad ? Colors.blue : Colors.orange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Icon(Icons.add, color: Colors.white, size: 28))),
        ]),
        if (_bt.isConnected && _liveWeight > 0)
          Padding(padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Live: ${_liveWeight.toStringAsFixed(3)} kg ${_weightStable ? '— STABLE ✓' : '...'}',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                  color: _weightStable ? Colors.green : Colors.blue))),
      ]),
    );
  }

  Widget _buildActionButtons(WeighmentPhase phase, bool locked) {
    if (!locked) {
      // Phase 1 actions
      return Column(children: [
        if (_session.rows.isNotEmpty) ElevatedButton.icon(
          onPressed: _lockLoadWT,
          icon: const Icon(Icons.lock_outline, size: 18),
          label: const Text('Done — Lock Load WT & Enter Birds Count'),
          style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              backgroundColor: Colors.blue)),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(null),
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 44)),
          child: const Text('Cancel')),
      ]);
    }

    // Phase 2 actions
    return Column(children: [
      // Cage tally
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _session.cagesMatch ? Colors.green.shade50 : Colors.red.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _session.cagesMatch ? Colors.green.shade200 : Colors.red.shade200)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(_session.cagesMatch ? Icons.check_circle_outline : Icons.warning_amber_outlined,
              color: _session.cagesMatch ? Colors.green : Colors.red, size: 18),
          const SizedBox(width: 8),
          Text('Cages: Load ${_session.totalLoadCages} — Empty ${_session.totalEmptyCages}'
               ' ${_session.cagesMatch ? '✓ Match' : '✗ Mismatch'}',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                  color: _session.cagesMatch ? Colors.green : Colors.red)),
        ])),
      const SizedBox(height: 10),

      if (_session.allEmptyFilled && _session.cagesMatch) ...[
        // Final summary before submit
        Container(
          padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade200)),
          child: Column(children: [
            _summaryLine('Total Birds',   '${_session.totalBirds}'),
            _summaryLine('Total Load WT', '${_session.totalLoadWt.toStringAsFixed(3)} kg'),
            _summaryLine('Total Empty WT','${_session.totalEmptyWt.toStringAsFixed(3)} kg'),
            _summaryLine('Total Net WT',  '${_session.totalNetWt.toStringAsFixed(3)} kg',  bold: true),
            _summaryLine('Avg Bird WT',   '${(_session.avgBirdWt * 1000).toStringAsFixed(0)} g/bird', bold: true),
          ])),
        ElevatedButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check_circle_outline, size: 20),
          label: const Text('Use These Weights', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              backgroundColor: Colors.green)),
      ] else
        OutlinedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.hourglass_top, size: 16),
          label: Text('Fill all ${_session.rows.length - _session.filledEmptyRows} remaining empty weights'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48))),

      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: _unlockLoadWT,
        icon: const Icon(Icons.lock_open, size: 16),
        label: const Text('Release Load WT Lock — Add More Batches')),
    ]);
  }

  Widget _summaryLine(String label, String value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
      Text(value, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
          color: bold ? Colors.green.shade800 : Colors.black)),
    ]));
}
