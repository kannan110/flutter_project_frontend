import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';

// ═══════════════════════════════════════════════════════════════════
//  DATA MODELS — unchanged interface so delivery_complete_screen.dart
//  can use WeighmentResult without any modification
// ═══════════════════════════════════════════════════════════════════

class WeighmentRow {
  final String pk;
  final int    seqNo;
  double loadWt;
  int    loadCages;
  double emptyWt;
  int    emptyCages;
  double get netWt => (loadWt - emptyWt).clamp(0, double.infinity);
  double avgWt;
  bool   emptyFilled;
  final String wmtTime;

  WeighmentRow({
    required this.pk,
    required this.seqNo,
    required this.loadWt,
    required this.loadCages,
    this.emptyWt    = 0,
    this.emptyCages = 0,
    this.avgWt      = 0,
    this.emptyFilled = false,
    required this.wmtTime,
  });

  Map<String, dynamic> toJson() => {
    'PK': pk, 'LOADWT': loadWt, 'LOAD_CAGES': loadCages,
    'EMPTYWT': emptyWt, 'EMPTY_CAGES': emptyCages,
    'NETWT': netWt, 'AVGWT': avgWt,
    'DELETEDFLAG': 'A', 'TRSEQNO': seqNo, 'WMTTIME': wmtTime,
  };
}

class WeighmentResult {
  final int    totalBirds;
  final double totalNetWt;
  final double avgBirdWtG;   // grams
  final double totalLoadWt;
  final double totalEmptyWt;
  final int    totalCages;
  final List<WeighmentRow> rows;
  final String source; // 'bluetooth' | 'manual'

  const WeighmentResult({
    required this.totalBirds,
    required this.totalNetWt,
    required this.avgBirdWtG,
    required this.totalLoadWt,
    required this.totalEmptyWt,
    required this.totalCages,
    required this.rows,
    required this.source,
  });
}

// ═══════════════════════════════════════════════════════════════════
//  WEIGHMENT SCREEN
//
//  FIX: Uses flutter_bluetooth_serial (Bluetooth Classic / SPP)
//       SLE scales use SPP — NOT BLE.
//       flutter_blue_plus only scans BLE → SLE invisible.
//       flutter_bluetooth_serial.getPairedDevices() shows ALL
//       paired Classic BT devices including SLE scales.
// ═══════════════════════════════════════════════════════════════════

class WeighmentScreen extends StatefulWidget {
  final String deliveryId;
  final String shopName;
  final int    expectedBirds;
  final double expectedWeight;
  final void Function(WeighmentResult) onComplete;

  const WeighmentScreen({
    super.key,
    required this.deliveryId,
    required this.shopName,
    required this.expectedBirds,
    required this.expectedWeight,
    required this.onComplete,
  });

  @override State<WeighmentScreen> createState() => _WS();
}

class _WS extends State<WeighmentScreen> {
  // ── Weighment data ──────────────────────────────────
  final List<WeighmentRow> _rows = [];
  bool   _loadLocked    = false;
  bool   _sessionLocked = false; // true after final submission — no more edits
  String _mode          = 'LOAD'; // 'LOAD' | 'EMPTY' | 'DONE'
  int    _totalBirds    = 0;
  int    _nextSeqNo     = 1;
  bool   _saving        = false;
  String? _deletingPk;  // pk of row being deleted (for loading state)
  String? _editingPk;   // pk of row being edited

  // ── Bluetooth Classic (SPP) ─────────────────────────
  // KEY FIX: Use flutter_bluetooth_serial, not flutter_blue_plus
  // SLE weighing scales use SPP (Serial Port Profile = Bluetooth Classic)
  // BLE (flutter_blue_plus) cannot see Classic BT devices at all
  List<BluetoothDevice> _pairedDevices   = [];
  BluetoothDevice?      _selectedDevice;
  BluetoothConnection?  _connection;
  StreamSubscription?   _dataSub;
  bool    _connected    = false;
  bool    _connecting   = false;
  double  _liveWeight   = 0;
  String  _btBuffer     = '';

  // ── Manual entry ────────────────────────────────────
  final _manualWtCtrl    = TextEditingController();
  final _manualCagesCtrl = TextEditingController(text: '2');

  @override
  void initState() {
    super.initState();
    _initBluetooth();
    _loadSession();
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    _manualWtCtrl.dispose();
    _manualCagesCtrl.dispose();
    _connection?.dispose();
    super.dispose();
  }

  // ── Bluetooth init ─────────────────────────────────
  Future<void> _initBluetooth() async {
    // Request permissions for Android 12+ (BLUETOOTH_CONNECT required)
    await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.locationWhenInUse,
    ].request();

    try {
      final enabled = await FlutterBluetoothSerial.instance.isEnabled ?? false;
      if (!enabled) return; // User needs to enable BT manually

      // KEY FIX: getPairedDevices() returns ALL bonded Classic BT devices
      // This includes SLE scales which use SPP (Serial Port Profile)
      // flutter_blue_plus.startScan() would NEVER see these devices
      final devices = await FlutterBluetoothSerial.instance.getBondedDevices();

      if (mounted) setState(() => _pairedDevices = devices);

      // Auto-show picker if devices found
      if (devices.isNotEmpty && mounted) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) _showScalePicker();
      }
    } catch (e) {
      // Non-fatal — manual entry always works
      debugPrint('[BT] Init error: $e');
    }
  }

  Future<void> _refreshPairedDevices() async {
    try {
      final devices = await FlutterBluetoothSerial.instance.getBondedDevices();
      if (mounted) setState(() => _pairedDevices = devices);
    } catch (_) {}
  }

  Future<void> _connectDevice(BluetoothDevice device) async {
    if (mounted) setState(() => _connecting = true);
    try {
      _connection = await BluetoothConnection.toAddress(device.address)
          .timeout(const Duration(seconds: 15), onTimeout: () {
        throw TimeoutException(
          'Scale did not respond in 15 seconds.\n\n'
          'Check:\n'
          '• Scale is switched ON\n'
          '• Scale is within range\n'
          '• Not connected to another device');
      });

      // Listen to SPP data stream
      _dataSub = _connection!.input!.listen(
        (data) {
          _btBuffer += String.fromCharCodes(data);
          while (_btBuffer.contains('\n')) {
            final idx  = _btBuffer.indexOf('\n');
            final line = _btBuffer.substring(0, idx).trim();
            _btBuffer  = _btBuffer.substring(idx + 1);
            final wt   = _parseScaleLine(line);
            if (wt != null && wt >= 0 && mounted) {
              setState(() => _liveWeight = wt);
              // Sync to manual field when not in manual mode
              _manualWtCtrl.text = wt.toStringAsFixed(3);
            }
          }
        },
        onError: (_) { _disconnect(); },
        onDone:  ()  { _disconnect(); },
        cancelOnError: false,
      );

      if (mounted) setState(() {
        _connected       = true;
        _connecting      = false;
        _selectedDevice  = device;
      });
      if (mounted) showSuccess(context, '✓ Scale connected: ${device.name}');
    } on TimeoutException catch (e) {
      if (mounted) {
        setState(() => _connecting = false);
        showError(context, e.message ?? 'Timeout');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _connecting = false);
        String msg = e.toString();
        if (msg.contains('permission') || msg.contains('BLUETOOTH_CONNECT')) {
          msg = 'Permission denied.\n\nGo to Settings → Apps → Rooster Trader → Permissions → allow Bluetooth.';
        } else if (msg.contains('bond') || msg.contains('pair')) {
          msg = 'Scale not paired.\n\nGo to Android Settings → Bluetooth, find the scale and pair it first.';
        } else {
          msg = 'Connection failed: $msg\n\nMake sure scale is ON and not connected to another device.';
        }
        showError(context, msg);
      }
    }
  }

  void _disconnect() {
    _dataSub?.cancel();
    _dataSub = null;
    try { _connection?.dispose(); } catch (_) {}
    _connection = null;
    _btBuffer   = '';
    if (mounted) setState(() { _connected = false; _selectedDevice = null; _liveWeight = 0; });
  }

  /// Parse SLE scale serial output — handles common formats:
  ///   "85.340"           plain number
  ///   " 85.340 kg"       with unit
  ///   "ST,GS,85.340"     status prefix (SLE standard)
  ///   "+085.340"         sign + padding
  ///   "0085340"          without decimal (divide by 1000)
  ///   "85.340\r"         with carriage return
  double? _parseScaleLine(String line) {
    if (line.isEmpty) return null;
    // Strip carriage return, whitespace
    final trimmed = line.replaceAll('\r', '').trim();
    if (trimmed.isEmpty) return null;
    // Try direct parse first (handles "85.340", "+085.340")
    final direct = double.tryParse(trimmed);
    if (direct != null && direct >= 0) return direct;
    // Extract the last number-like token (handles "ST,GS,85.340")
    final matches = RegExp(r'[+-]?\d+\.?\d*').allMatches(trimmed);
    if (matches.isEmpty) return null;
    // Take the last match (the actual weight value in SLE format)
    final last = matches.last.group(0);
    if (last == null) return null;
    final parsed = double.tryParse(last);
    if (parsed == null || parsed < 0) return null;
    return parsed;
  }

  // ── Session persistence ─────────────────────────────
  Future<void> _loadSession() async {
    try {
      final res = await Supabase.instance.client.rpc('get_weighment_session',
          params: {'p_delivery_id': widget.deliveryId});
      if (res == null) return;
      final session = res['session'];
      final rows    = res['rows'] as List? ?? [];
      if (session == null || rows.isEmpty) return;
      final loaded = rows.map((r) {
        final m = r as Map<String,dynamic>;
        return WeighmentRow(
          pk: m['PK'] as String, seqNo: (m['TRSEQNO'] as num).toInt(),
          loadWt: (m['LOADWT'] as num).toDouble(), loadCages: (m['LOAD_CAGES'] as num).toInt(),
          emptyWt: (m['EMPTYWT'] as num).toDouble(), emptyCages: (m['EMPTY_CAGES'] as num).toInt(),
          avgWt: (m['AVGWT'] as num).toDouble(),
          emptyFilled: (m['EMPTYWT'] as num).toDouble() > 0,
          wmtTime: m['WMTTIME'] as String? ?? '',
        );
      }).toList();
      if (!mounted) return;
      setState(() {
        _rows.addAll(loaded);
        _totalBirds    = (session['total_birds'] as num?)?.toInt() ?? 0;
        _loadLocked    = session['load_locked'] as bool? ?? false;
        _sessionLocked = (session['status'] as String?) == 'COMPLETED';
        _mode          = session['mode'] as String? ?? 'LOAD';
        _nextSeqNo     = loaded.isEmpty ? 1 : loaded.last.seqNo + 1;
      });
    } catch (_) {}
  }

  Future<void> _saveToServer() async {
    try {
      if (_rows.isEmpty) return;
      await Supabase.instance.client.rpc('upsert_weighment_rows', params: {
        'p_delivery_id': widget.deliveryId,
        'p_rows': _rows.map((r) => r.toJson()).toList(),
      });
      await Supabase.instance.client.rpc('upsert_weighment_session', params: {
        'p_delivery_id':  widget.deliveryId,
        'p_total_birds':  _totalBirds,
        'p_total_net_wt': _totalNetWt,
        'p_avg_bird_wt':  _avgBirdWtKg,
        'p_total_load_wt': _totalLoadWt,
        'p_total_empty_wt': _totalEmptyWt,
        'p_total_cages':   _totalLoadCages,
        'p_load_locked':   _loadLocked,
        'p_mode':          _mode,
      });
    } catch (_) {}
  }

  // ── Calculations ────────────────────────────────────
  double get _totalLoadWt     => _rows.fold(0.0, (s, r) => s + r.loadWt);
  double get _totalEmptyWt    => _rows.where((r) => r.emptyFilled).fold(0.0, (s, r) => s + r.emptyWt);
  double get _totalNetWt      => _rows.where((r) => r.emptyFilled).fold(0.0, (s, r) => s + r.netWt);
  int    get _totalLoadCages  => _rows.fold(0, (s, r) => s + r.loadCages);
  int    get _totalEmptyCages => _rows.fold(0, (s, r) => s + r.emptyCages);
  int    get _filledEmpty     => _rows.where((r) => r.emptyFilled).length;
  double get _avgBirdWtKg     => _totalBirds > 0 && _totalNetWt > 0 ? _totalNetWt / _totalBirds : 0;
  double get _avgBirdWtG      => _avgBirdWtKg * 1000;
  bool   get _cagesMatch      => _totalLoadCages == _totalEmptyCages;

  void _recalcAvgWt() {
    final avg = _avgBirdWtKg;
    for (final r in _rows) { if (r.emptyFilled) r.avgWt = avg; }
  }

  // ── Weight capture ──────────────────────────────────
  Future<void> _captureLoadWt() async {
    if (_loadLocked) return;
    final wt    = double.tryParse(_manualWtCtrl.text.trim()) ?? (_connected ? _liveWeight : 0);
    final cages = int.tryParse(_manualCagesCtrl.text.trim()) ?? 2;
    if (wt <= 0) { showError(context, 'Weight must be > 0'); return; }
    final ok = await _showCaptureModal(wt, cages, isLoad: true);
    if (!ok) return;
    final now = TimeOfDay.now();
    final row = WeighmentRow(
      pk: '${widget.deliveryId}_${DateTime.now().millisecondsSinceEpoch}_$_nextSeqNo',
      seqNo: _nextSeqNo,
      loadWt: wt, loadCages: cages,
      wmtTime: '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
    );
    setState(() { _rows.add(row); _nextSeqNo++; _manualWtCtrl.clear(); });
    _saveToServer();
  }

  Future<void> _captureEmptyWt() async {
    if (!_loadLocked) return;
    final row = _rows.firstWhere((r) => !r.emptyFilled, orElse: () => _rows.last);
    if (row.emptyFilled) { showError(context, 'All empty weights filled'); return; }
    final wt    = double.tryParse(_manualWtCtrl.text.trim()) ?? (_connected ? _liveWeight : 0);
    final cages = int.tryParse(_manualCagesCtrl.text.trim()) ?? row.loadCages;
    if (wt <= 0) { showError(context, 'Empty weight must be > 0'); return; }
    final ok = await _showCaptureModal(wt, cages, isLoad: false,
        rowNum: row.seqNo, loadWt: row.loadWt, loadCages: row.loadCages);
    if (!ok) return;
    setState(() {
      row.emptyWt     = wt;
      row.emptyCages  = cages;
      row.emptyFilled = true;
      _recalcAvgWt();
      _manualWtCtrl.clear();
      if (_rows.every((r) => r.emptyFilled)) _mode = 'DONE';
    });
    _saveToServer();
  }

  Future<bool> _showCaptureModal(double wt, int cages, {
    required bool isLoad, int rowNum = 0, double loadWt = 0, int loadCages = 0}) async {
    return await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(isLoad ? 'Confirm Load Weight' : 'Confirm Empty Weight',
          style: const TextStyle(fontWeight: FontWeight.w800)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        if (!isLoad) ...[
          Text('Row #$rowNum — Load: ${loadWt.toStringAsFixed(3)} kg ($loadCages cages)',
              style: const TextStyle(fontSize: 12, color: kTextSub)),
          const Divider(),
        ],
        Text('${wt.toStringAsFixed(3)} kg',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: kPrimary)),
        Text('$cages cages', style: const TextStyle(fontSize: 14, color: kTextSub)),
        if (!isLoad) ...[
          const Divider(),
          Text('Net: ${(loadWt - wt).clamp(0, double.infinity).toStringAsFixed(3)} kg',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.green)),
        ],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm ✓')),
      ],
    )) ?? false;
  }

  Future<void> _lockLoad() async {
    if (_rows.isEmpty) { showError(context, 'Add at least one load entry first'); return; }
    final ctrl = TextEditingController(
        text: widget.expectedBirds > 0 ? '${widget.expectedBirds}' : '');
    final birds = await showDialog<int>(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Total Birds Count', style: TextStyle(fontWeight: FontWeight.w800)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Enter total birds loaded:',
            style: TextStyle(fontSize: 13, color: kTextSub)),
        const SizedBox(height: 12),
        TextField(controller: ctrl, keyboardType: TextInputType.number, autofocus: true,
            decoration: const InputDecoration(labelText: 'Birds', suffixText: 'birds')),
        const SizedBox(height: 8),
        Text('Load weight: ${_totalLoadWt.toStringAsFixed(3)} kg',
            style: const TextStyle(fontSize: 12, color: kTextHint)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(onPressed: () {
          final v = int.tryParse(ctrl.text.trim());
          if (v != null && v > 0) Navigator.pop(ctx, v);
        }, child: const Text('Lock & Proceed')),
      ],
    ));
    ctrl.dispose();
    if (birds == null) return;
    setState(() {
      _totalBirds = birds;
      _loadLocked = true;
      _mode = 'EMPTY';
      _manualWtCtrl.clear();
    });
    _saveToServer();
  }

  // ── Delete latest row (soft-delete via RPC) ───────
  // Called from Dismissible.onDismissed — removes from list immediately
  // (no dialog — confirmDismiss already confirmed)
  void _deleteRowDirectly(String pk) {
    if (!mounted) return;
    setState(() {
      _rows.removeWhere((r) => r.pk == pk);
      _deletingPk = null;
      if (_rows.isEmpty) {
        _loadLocked = false;
        _mode = 'LOAD';
        _totalBirds = 0;
      } else if (_rows.isNotEmpty && _rows.every((r) => r.emptyFilled)) {
        _mode = 'DONE';
      } else if (_rows.any((r) => r.emptyFilled) && _rows.any((r) => !r.emptyFilled)) {
        _mode = 'EMPTY';
      }
    });
    // Fire DB delete async (non-blocking so UI stays responsive)
    Supabase.instance.client.rpc('delete_weighment_row', params: {
      'p_delivery_id': widget.deliveryId,
      'p_pk':          pk,
    }).catchError((e) {
      if (mounted) showError(context, 'Delete sync failed: $e');
    });
  }

  Future<void> _deleteLatestRow() async {
    if (_sessionLocked) {
      showError(context, 'Session is locked. No changes allowed after final submission.');
      return;
    }
    if (_rows.isEmpty) return;
    final latest = _rows.last;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Delete Latest Entry?', style: TextStyle(fontWeight: FontWeight.w800)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Row #${latest.seqNo} — ${latest.wmtTime}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            Text('Load: ${latest.loadWt.toStringAsFixed(3)} kg · ${latest.loadCages} cages',
                style: const TextStyle(fontSize: 12, color: kTextSub)),
            if (latest.emptyFilled) Text(
                'Empty: ${latest.emptyWt.toStringAsFixed(3)} kg · Net: ${latest.netWt.toStringAsFixed(3)} kg',
                style: const TextStyle(fontSize: 12, color: kTextSub)),
          ])),
        const SizedBox(height: 10),
        const Text('This entry will be removed. You can re-enter the correct values.',
            style: TextStyle(fontSize: 12, color: kTextSub)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete Entry', style: TextStyle(color: Colors.white))),
      ],
    )) ?? false;
    if (!ok || !mounted) return;

    setState(() => _deletingPk = latest.pk);
    try {
      await Supabase.instance.client.rpc('delete_weighment_row', params: {
        'p_delivery_id': widget.deliveryId,
        'p_pk':          latest.pk,
      });
      setState(() {
        _rows.removeLast();
        _deletingPk = null;
        // If we deleted the only row, unlock load phase
        if (_rows.isEmpty) {
          _loadLocked = false;
          _mode = 'LOAD';
          _totalBirds = 0;
        }
        // If we deleted an empty-weighed row, go back to EMPTY mode
        else if (latest.emptyFilled && _rows.any((r) => !r.emptyFilled)) {
          _mode = 'EMPTY';
        }
      });
      showSuccess(context, 'Row #${latest.seqNo} deleted — re-enter correct values');
    } catch (e) {
      if (mounted) {
        setState(() => _deletingPk = null);
        showError(context, e.toString().replaceAll('Exception: ', '')
            .replaceAll('PostgrestException(message: ', '').replaceAll(')', ''));
      }
    }
  }

  // ── Edit latest row ────────────────────────────────
  Future<void> _editLatestRow() async {
    if (_sessionLocked) {
      showError(context, 'Session is locked. No edits allowed.');
      return;
    }
    if (_rows.isEmpty) return;
    final latest = _rows.last;

    final wtCtrl    = TextEditingController(text: latest.loadWt.toStringAsFixed(3));
    final cagesCtrl = TextEditingController(text: '${latest.loadCages}');
    final emptyWtCtrl    = latest.emptyFilled ? TextEditingController(text: latest.emptyWt.toStringAsFixed(3)) : null;
    final emptyCagesCtrl = latest.emptyFilled ? TextEditingController(text: '${latest.emptyCages}') : null;

    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Edit Row #${latest.seqNo}', style: const TextStyle(fontWeight: FontWeight.w800)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('LOAD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kTextHint)),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: TextField(controller: wtCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Load Weight (kg)', isDense: true))),
          const SizedBox(width: 8),
          SizedBox(width: 80, child: TextField(controller: cagesCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Cages', isDense: true))),
        ]),
        if (latest.emptyFilled) ...[
          const SizedBox(height: 12),
          const Text('EMPTY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kTextHint)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: TextField(controller: emptyWtCtrl!,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Empty Weight (kg)', isDense: true))),
            const SizedBox(width: 8),
            SizedBox(width: 80, child: TextField(controller: emptyCagesCtrl!,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Cages', isDense: true))),
          ]),
        ],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Save Changes')),
      ],
    )) ?? false;

    if (!ok || !mounted) return;

    final newWt     = double.tryParse(wtCtrl.text.trim())    ?? latest.loadWt;
    final newCages  = int.tryParse(cagesCtrl.text.trim())    ?? latest.loadCages;
    final newEmptyWt    = emptyWtCtrl    != null ? (double.tryParse(emptyWtCtrl.text.trim())    ?? latest.emptyWt)    : null;
    final newEmptyCages = emptyCagesCtrl != null ? (int.tryParse(emptyCagesCtrl.text.trim())    ?? latest.emptyCages) : null;
    wtCtrl.dispose(); cagesCtrl.dispose();
    emptyWtCtrl?.dispose(); emptyCagesCtrl?.dispose();

    setState(() => _editingPk = latest.pk);
    try {
      await Supabase.instance.client.rpc('edit_weighment_row', params: {
        'p_delivery_id': widget.deliveryId,
        'p_pk':          latest.pk,
        'p_load_wt':     newWt,
        'p_load_cages':  newCages,
        if (newEmptyWt    != null) 'p_empty_wt':     newEmptyWt,
        if (newEmptyCages != null) 'p_empty_cages':  newEmptyCages,
      });
      setState(() {
        latest.loadWt    = newWt;
        latest.loadCages = newCages;
        if (newEmptyWt != null)    latest.emptyWt    = newEmptyWt;
        if (newEmptyCages != null) latest.emptyCages = newEmptyCages;
        _editingPk = null;
        _recalcAvgWt();
      });
      showSuccess(context, 'Row #${latest.seqNo} updated ✓');
    } catch (e) {
      if (mounted) {
        setState(() => _editingPk = null);
        showError(context, e.toString().replaceAll('Exception: ', '')
            .replaceAll('PostgrestException(message: ', '').replaceAll(')', ''));
      }
    }
  }

  Future<void> _submit() async {
    if (!_cagesMatch) {
      showError(context,
          'Cage mismatch!\nLoad: $_totalLoadCages · Empty: $_totalEmptyCages\n'
          'All empty cages must be weighed before submitting.');
      return;
    }
    if (_filledEmpty < _rows.length) {
      showError(context, 'Row ${_filledEmpty + 1} still needs empty weight.');
      return;
    }
    if (_totalBirds <= 0) {
      showError(context, 'Birds count is 0. Lock load first.');
      return;
    }
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Confirm Weighment', style: TextStyle(fontWeight: FontWeight.w800)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _summaryRow('Total Birds',    '$_totalBirds'),
        _summaryRow('Load Cages',     '$_totalLoadCages'),
        _summaryRow('Total Load WT',  '${_totalLoadWt.toStringAsFixed(3)} kg'),
        _summaryRow('Total Empty WT', '${_totalEmptyWt.toStringAsFixed(3)} kg'),
        _summaryRow('Total Net WT',   '${_totalNetWt.toStringAsFixed(3)} kg'),
        _summaryRow('Avg Bird WT',    '${_avgBirdWtG.toStringAsFixed(1)} g/bird'),
        const Divider(),
        _summaryRow('Source', _connected ? '🔵 SLE Scale (Bluetooth)' : '✏️ Manual Entry'),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Use This Weight')),
      ],
    )) ?? false;

    if (!ok) return;
    // Lock the session — no more edits after this point
    try {
      await Supabase.instance.client.rpc('lock_weighment_session',
          params: {'p_delivery_id': widget.deliveryId});
    } catch (_) {} // non-fatal if session not yet saved

    if (mounted) setState(() => _sessionLocked = true);

    widget.onComplete(WeighmentResult(
      totalBirds:   _totalBirds,
      totalNetWt:   _totalNetWt,
      avgBirdWtG:   _avgBirdWtG,
      totalLoadWt:  _totalLoadWt,
      totalEmptyWt: _totalEmptyWt,
      totalCages:   _totalLoadCages,
      rows:         List.from(_rows),
      source:       _connected ? 'bluetooth' : 'manual',
    ));
  }

  Widget _summaryRow(String l, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      Expanded(child: Text(l, style: const TextStyle(fontSize: 12, color: kTextSub))),
      Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
    ]));

  // ── Scale picker bottom sheet ───────────────────────
  void _showScalePicker() {
    showModalBottomSheet(
      context: context, useRootNavigator: true, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.scale, color: kPrimary, size: 24),
            const SizedBox(width: 10),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Connect SLE Scale', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              Text('Select your paired Bluetooth scale (Classic BT / SPP)',
                  style: TextStyle(fontSize: 11, color: kTextHint)),
            ])),
            IconButton(
              icon: const Icon(Icons.refresh, color: kPrimary),
              tooltip: 'Refresh paired devices',
              onPressed: () async {
                await _refreshPairedDevices();
                ss(() {});
              }),
          ]),
          const SizedBox(height: 12),

          if (_pairedDevices.isEmpty) ...[
            // Setup guidance when no devices paired
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade200)),
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
                  SizedBox(width: 8),
                  Text('No paired scale found', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                ]),
                SizedBox(height: 10),
                Text('To pair your SLE scale:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                SizedBox(height: 6),
                Text('1. Turn ON the weighing scale', style: TextStyle(height: 1.7)),
                Text('2. Open Android Settings → Bluetooth', style: TextStyle(height: 1.7)),
                Text('3. Find your scale and tap "Pair"', style: TextStyle(height: 1.7)),
                Text('4. Come back here and tap Refresh ↑', style: TextStyle(height: 1.7)),
              ]),
            ),
          ] else ...[
            // List all paired Classic BT devices
            // SLE scale will appear here (previously invisible with BLE scanner)
            const Text('Paired Bluetooth devices:',
                style: TextStyle(fontSize: 12, color: kTextHint, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ..._pairedDevices.map((d) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: _selectedDevice?.address == d.address ? kPrimary : kBorder,
                      width: _selectedDevice?.address == d.address ? 2 : 1)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                        color: kPrimary.withValues(alpha: 0.1),
                        shape: BoxShape.circle),
                    child: const Icon(Icons.scale, color: kPrimary, size: 20)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d.name ?? 'Unknown Device',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    Text(d.address,
                        style: const TextStyle(fontSize: 11, color: kTextHint)),
                  ])),
                  const SizedBox(width: 8),
                  _connecting && _selectedDevice?.address == d.address
                      ? const SizedBox(width: 24, height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5))
                      : ElevatedButton(
                          onPressed: () async {
                            ss(() => _selectedDevice = d);
                            Navigator.of(ctx, rootNavigator: true).pop();
                            await _connectDevice(d);
                          },
                          style: ElevatedButton.styleFrom(
                              backgroundColor: kPrimary,
                              minimumSize: const Size(80, 36),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                          child: const Text('Connect',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))),
                ])))),
          ],
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(),
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Skip — Use Manual Entry')),
        ]))));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF0F4F0),
    appBar: AppBar(
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Weighment', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        Text(widget.shopName,
            style: const TextStyle(fontSize: 11, color: kTextHint, fontWeight: FontWeight.w400)),
      ]),
      actions: [
        // BT connection status button
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: _connected ? _disconnect : _showScalePicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: _connected ? Colors.green.shade50 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: _connected ? Colors.green.shade300 : Colors.grey.shade300)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 7, height: 7,
                    decoration: BoxDecoration(
                        color: _connected ? Colors.green : (_connecting ? Colors.orange : Colors.grey),
                        shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(
                  _connecting ? 'Connecting…' :
                  _connected  ? 'Scale ON' : 'No Scale',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: _connected ? Colors.green.shade700 : kTextHint)),
              ]))),
        ),
      ],
    ),
    body: Column(children: [
      // Live weight display
      _buildWeightDisplay(),
      // Phase header
      _buildPhaseHeader(),
      // Table
      Expanded(child: _buildTable()),
    ]),
    bottomNavigationBar: _buildBottomBar(),
  );

  Widget _buildWeightDisplay() => Container(
    padding: const EdgeInsets.all(16),
    color: Colors.white,
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          _connected ? '🔵 SLE SCALE (LIVE)' : '✏️ MANUAL ENTRY',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
              color: _connected ? Colors.blue : kTextHint, letterSpacing: 0.8)),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: TextField(
            controller: _manualWtCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Weight (kg)', suffixText: 'kg',
                isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
          )),
          const SizedBox(width: 8),
          SizedBox(width: 80, child: TextField(
            controller: _manualCagesCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Cages', isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
          )),
        ]),
        if (_connected) Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Live: ${_liveWeight.toStringAsFixed(3)} kg',
              style: const TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.w600))),
      ])),
      const SizedBox(width: 12),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: kPrimary.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('Net: ${_totalNetWt.toStringAsFixed(2)} kg',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kPrimary)),
          Text('Birds: $_totalBirds',
              style: const TextStyle(fontSize: 11, color: kTextSub)),
          if (_avgBirdWtG > 0)
            Text('Avg: ${_avgBirdWtG.toStringAsFixed(1)}g',
                style: const TextStyle(fontSize: 11, color: Colors.teal)),
        ]),
      ),
    ]),
  );

  Widget _buildPhaseHeader() => Container(
    color: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(children: [
      _phaseChip('1: LOAD WT', !_loadLocked, kPrimary),
      const SizedBox(width: 8),
      const Icon(Icons.arrow_forward, size: 14, color: kTextHint),
      const SizedBox(width: 8),
      _phaseChip('2: EMPTY WT', _loadLocked, Colors.green),
      const Spacer(),
      if (!_cagesMatch && _filledEmpty > 0)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
              color: Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
          child: Text('⚠ Cage mismatch $_totalLoadCages≠$_totalEmptyCages',
              style: const TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.w700))),
    ]));

  Widget _phaseChip(String label, bool active, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
        color: active ? c.withValues(alpha: 0.1) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: active ? c : Colors.grey.shade300)),
    child: Text(label, style: TextStyle(
        fontSize: 10, fontWeight: FontWeight.w700,
        color: active ? c : kTextHint)));

  Widget _buildTable() {
    if (_rows.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.scale_outlined, size: 48, color: kTextHint),
      const SizedBox(height: 8),
      Text(_connected
          ? 'Place birds on scale, weight updates live\nTap + to capture'
          : 'Enter weight manually\nTap + to add row',
          style: const TextStyle(color: kTextSub, fontSize: 13), textAlign: TextAlign.center),
    ]));

    return ListView(padding: const EdgeInsets.all(12), children: [
      // Session locked banner
      if (_sessionLocked) Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: Colors.green.shade50, borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green.shade300)),
        child: const Row(children: [
          Icon(Icons.lock, color: Colors.green, size: 16),
          SizedBox(width: 8),
          Expanded(child: Text('Session locked — weighment submitted. No further changes allowed.',
              style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600))),
        ])),
      // Header
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(6)),
        child: const Row(children: [
          _TH('#', 28), _TH('Load WT', 88), _TH('Cages', 48),
          _TH('Empty WT', 88), _TH('Net WT', 78), _TH('✓', 40),
        ])),
      const SizedBox(height: 4),
      ..._rows.map((r) {
        final isNext = _loadLocked && !r.emptyFilled &&
            _rows.firstWhere((x) => !x.emptyFilled, orElse: () => r) == r;
        final isLastRow = _rows.last == r;
        return Dismissible(
          key: Key(r.pk),
          direction: _sessionLocked ? DismissDirection.none : DismissDirection.endToStart,
          background: Container(
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
                color: Colors.red.shade100, borderRadius: BorderRadius.circular(6)),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.delete_outline, color: Colors.red, size: 20),
              SizedBox(width: 4),
              Text('Delete', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700, fontSize: 12)),
            ])),
          confirmDismiss: (_) async {
            if (_sessionLocked) return false;
            // Only allow deleting the latest row to preserve sequence integrity
            if (!isLastRow) {
              showError(context, 'Only the latest row can be deleted.\nDelete in reverse order.');
              return false;
            }
            return await showDialog<bool>(context: context,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: Text('Delete Row #${r.seqNo}?',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  content: Text(
                      'Load: ${r.loadWt.toStringAsFixed(3)} kg · ${r.loadCages} cages'
                      '${r.emptyFilled ? '\nEmpty: ${r.emptyWt.toStringAsFixed(3)} kg · Net: ${r.netWt.toStringAsFixed(3)} kg' : ''}'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Delete', style: TextStyle(color: Colors.white))),
                  ])) ?? false;
          },
          onDismissed: (_) {
            // FIX: must remove from list synchronously in onDismissed
            // Do NOT call _deleteLatestRow() here (it shows a dialog = crash)
            // confirmDismiss already got user confirmation
            _deleteRowDirectly(r.pk);
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
                color: isNext ? Colors.blue.shade50 : Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: isNext ? Colors.blue.shade200 : kBorder)),
            child: Row(children: [
              _TD('${r.seqNo}', 30, kTextSub),
              _TD(r.loadWt.toStringAsFixed(3), 90, kTextMain),
              _TD('${r.loadCages}', 50, kTextSub),
              _TD(r.emptyFilled ? r.emptyWt.toStringAsFixed(3) : '—', 90,
                  r.emptyFilled ? Colors.orange : kTextHint),
              _TD(r.emptyFilled ? r.netWt.toStringAsFixed(3) : '—', 80,
                  r.emptyFilled ? Colors.green : kTextHint),
              SizedBox(width: 40, child: isLastRow && !_sessionLocked
                  ? GestureDetector(
                      onTap: _editLatestRow,
                      child: const Icon(Icons.edit_outlined, size: 16, color: kPrimary))
                  : Icon(
                      r.emptyFilled ? Icons.check_circle
                          : (isNext ? Icons.arrow_forward : Icons.circle_outlined),
                      size: 16,
                      color: r.emptyFilled ? Colors.green
                          : (isNext ? Colors.blue : kTextHint))),
            ])));
      }),
      if (_rows.isNotEmpty) ...[
        const Divider(height: 16),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8)),
          child: Column(children: [
            Row(children: [
              Expanded(child: _KV('Load WT', '${_totalLoadWt.toStringAsFixed(2)} kg')),
              Expanded(child: _KV('Empty WT', '${_totalEmptyWt.toStringAsFixed(2)} kg')),
              Expanded(child: _KV('Net WT', '${_totalNetWt.toStringAsFixed(2)} kg', kPrimary)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: _KV('Load Cages', '$_totalLoadCages')),
              Expanded(child: _KV('Empty Cages', '$_totalEmptyCages',
                  _cagesMatch ? Colors.green : Colors.red)),
              Expanded(child: _KV('Avg WT', '${_avgBirdWtG.toStringAsFixed(1)}g', Colors.teal)),
            ]),
          ])),
      ],
      const SizedBox(height: 80),
    ]);
  }

  Widget _buildBottomBar() => Container(
    color: Colors.white,
    padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).padding.bottom + 10),
    child: Row(children: [
      if (!_loadLocked) ...[
        Expanded(child: ElevatedButton.icon(
          onPressed: _rows.isEmpty ? null : _lockLoad,
          icon: const Icon(Icons.lock_outline, size: 16),
          label: const Text('Lock Load'),
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange, minimumSize: const Size(0, 44)))),
        const SizedBox(width: 8),
        // Edit latest row
        SizedBox(width: 48, height: 44, child: OutlinedButton(
          onPressed: _rows.isEmpty || _sessionLocked ? null : _editLatestRow,
          style: OutlinedButton.styleFrom(padding: EdgeInsets.zero,
              side: const BorderSide(color: kPrimary)),
          child: _editingPk != null
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.edit_outlined, size: 20, color: kPrimary))),
        const SizedBox(width: 8),
        // Delete latest row
        SizedBox(width: 48, height: 44, child: OutlinedButton(
          onPressed: _rows.isEmpty || _sessionLocked ? null : _deleteLatestRow,
          style: OutlinedButton.styleFrom(padding: EdgeInsets.zero,
              side: BorderSide(color: Colors.red.shade300)),
          child: _deletingPk != null
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red))
              : const Icon(Icons.delete_outline, size: 20, color: Colors.red))),
        const SizedBox(width: 8),
        SizedBox(width: 52, height: 44, child: ElevatedButton(
          onPressed: _captureLoadWt,
          style: ElevatedButton.styleFrom(padding: EdgeInsets.zero),
          child: const Icon(Icons.add, size: 28))),
      ],
      if (_loadLocked && _mode == 'EMPTY') ...[
        Expanded(child: ElevatedButton.icon(
          onPressed: _rows.any((r) => !r.emptyFilled) ? _captureEmptyWt : null,
          icon: const Icon(Icons.scale_outlined, size: 16),
          label: Text('Empty WT — Row ${_filledEmpty + 1}'),
          style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)))),
        const SizedBox(width: 8),
        // Edit latest row in empty phase
        SizedBox(width: 48, height: 44, child: OutlinedButton(
          onPressed: _rows.isEmpty || _sessionLocked ? null : _editLatestRow,
          style: OutlinedButton.styleFrom(padding: EdgeInsets.zero,
              side: const BorderSide(color: kPrimary)),
          child: _editingPk != null
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.edit_outlined, size: 20, color: kPrimary))),
        const SizedBox(width: 8),
        // Delete latest row in empty phase
        SizedBox(width: 48, height: 44, child: OutlinedButton(
          onPressed: _rows.isEmpty || _sessionLocked ? null : _deleteLatestRow,
          style: OutlinedButton.styleFrom(padding: EdgeInsets.zero,
              side: BorderSide(color: Colors.red.shade300)),
          child: _deletingPk != null
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red))
              : const Icon(Icons.delete_outline, size: 20, color: Colors.red))),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: () => setState(() { _loadLocked = false; _mode = 'LOAD'; }),
          style: OutlinedButton.styleFrom(minimumSize: const Size(48, 44), padding: EdgeInsets.zero),
          child: const Icon(Icons.lock_open, size: 18)),
      ],
      if (_mode == 'DONE' || (_loadLocked && _filledEmpty == _rows.length && _rows.isNotEmpty))
        Expanded(child: ElevatedButton.icon(
          onPressed: _saving ? null : _submit,
          icon: const Icon(Icons.check_circle_outline, size: 18),
          label: const Text('Use This Weight',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green, minimumSize: const Size(0, 48)))),
    ]),
  );
}

// Table helpers as top-level const to avoid capture issues
class _TH extends StatelessWidget {
  final String text;
  final double width;
  const _TH(this.text, this.width);
  @override Widget build(BuildContext context) =>
      SizedBox(width: width, child: Text(text,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
          textAlign: TextAlign.center));
}

class _TD extends StatelessWidget {
  final String text;
  final double width;
  final Color  color;
  const _TD(this.text, this.width, this.color);
  @override Widget build(BuildContext context) =>
      SizedBox(width: width, child: Text(text,
          style: TextStyle(fontSize: 11, color: color), textAlign: TextAlign.center));
}

class _KV extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _KV(this.label, this.value, [this.color]);
  @override Widget build(BuildContext context) => Column(children: [
    Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color ?? kTextMain)),
    Text(label,  style: const TextStyle(fontSize: 9, color: kTextHint)),
  ]);
}
