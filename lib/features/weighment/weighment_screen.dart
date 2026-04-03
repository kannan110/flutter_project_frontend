// ═══════════════════════════════════════════════════════════════════════════
//  WeighmentScreen — Flutter port of DeliveryWeighment (React Native)
//
//  FLOW:
//    Phase 1 — LOAD WT: capture weight + cages per batch → lock with birds count
//    Phase 2 — EMPTY WT: capture empty cage weight per batch → net wt calculated
//    Save: cage tally validated → confirmation → PDF → Supabase upsert → reset
//
//  Packages used (add to pubspec.yaml — see STEP 1 in documentation):
//    flutter_bluetooth_serial: ^0.4.0   — Bluetooth Classic scale
//    sqflite: ^2.3.0                    — Local SQLite persistence
//    path_provider: ^2.1.2              — App/downloads directory path
//    share_plus: ^7.2.1                 — Native share sheet
//    printing: ^5.12.0                  — PDF generation + print dialog
//    pdf: ^3.10.8                       — PDF document builder
//    supabase_flutter: ^2.3.4           — Supabase backend
//    permission_handler: ^11.3.0        — Runtime permissions
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// COLOURS (mirrors the React Native palette)
// ─────────────────────────────────────────────────────────────────────────────
class C {
  static const navy = Color(0xFF0F172A);
  static const navyMid = Color(0xFF1E293B);
  static const indigo = Color(0xFF6366F1);
  static const green = Color(0xFF059669);
  static const greenBg = Color(0xFFECFDF5);
  static const red = Color(0xFFDC2626);
  static const redBg = Color(0xFFFEF2F2);
  static const amber = Color(0xFFD97706);
  static const amberBg = Color(0xFFFEF3C7);
  static const slate = Color(0xFF475569);
  static const slateL = Color(0xFF94A3B8);
  static const border = Color(0xFFE2E8F0);
  static const bg = Color(0xFFF1F5F9);
  static const card = Color(0xFFFFFFFF);
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODEL — mirrors TypeScript TableRow interface exactly
// ─────────────────────────────────────────────────────────────────────────────
class WeighmentRow {
  final String pk;
  final double loadWt;
  final int loadCages;
  double emptyWt;
  int emptyCages;
  double netWt;
  double avgWt;
  String deletedFlag; // 'A' = active
  final int trSeqNo;
  final String wmtTime;

  WeighmentRow({
    required this.pk,
    required this.loadWt,
    required this.loadCages,
    this.emptyWt = 0,
    this.emptyCages = 0,
    this.netWt = 0,
    this.avgWt = 0,
    this.deletedFlag = 'A',
    required this.trSeqNo,
    required this.wmtTime,
  });

  // Convert to/from Supabase JSON
  Map<String, dynamic> toJson() => {
        'pk': pk,
        'load_wt': loadWt,
        'load_cages': loadCages,
        'empty_wt': emptyWt,
        'empty_cages': emptyCages,
        'net_wt': netWt,
        'avg_wt': avgWt,
        'deleted_flag': deletedFlag,
        'seq_no': trSeqNo,
        'entry_time': wmtTime,
      };

  factory WeighmentRow.fromJson(Map<String, dynamic> j) => WeighmentRow(
        pk: j['pk'] as String,
        loadWt: (j['load_wt'] as num).toDouble(),
        loadCages: j['load_cages'] as int,
        emptyWt: (j['empty_wt'] as num).toDouble(),
        emptyCages: j['empty_cages'] as int,
        netWt: (j['net_wt'] as num).toDouble(),
        avgWt: (j['avg_wt'] as num).toDouble(),
        deletedFlag: j['deleted_flag'] as String,
        trSeqNo: j['seq_no'] as int,
        wmtTime: j['entry_time'] as String,
      );

  // Convert to/from SQLite map
  Map<String, dynamic> toSqlite(String deliveryId) => {
        'pk': pk,
        'delivery_id': deliveryId,
        'load_wt': loadWt,
        'load_cages': loadCages,
        'empty_wt': emptyWt,
        'empty_cages': emptyCages,
        'net_wt': netWt,
        'avg_wt': avgWt,
        'deleted_flag': deletedFlag,
        'seq_no': trSeqNo,
        'entry_time': wmtTime,
      };

  factory WeighmentRow.fromSqlite(Map<String, dynamic> m) => WeighmentRow(
        pk: m['pk'] as String,
        loadWt: (m['load_wt'] as num).toDouble(),
        loadCages: m['load_cages'] as int,
        emptyWt: (m['empty_wt'] as num).toDouble(),
        emptyCages: m['empty_cages'] as int,
        netWt: (m['net_wt'] as num).toDouble(),
        avgWt: (m['avg_wt'] as num).toDouble(),
        deletedFlag: m['deleted_flag'] as String,
        trSeqNo: m['seq_no'] as int,
        wmtTime: m['entry_time'] as String,
      );

  WeighmentRow copyWith({
    double? emptyWt,
    int? emptyCages,
    double? netWt,
    double? avgWt,
    String? deletedFlag,
  }) =>
      WeighmentRow(
        pk: pk,
        loadWt: loadWt,
        loadCages: loadCages,
        emptyWt: emptyWt ?? this.emptyWt,
        emptyCages: emptyCages ?? this.emptyCages,
        netWt: netWt ?? this.netWt,
        avgWt: avgWt ?? this.avgWt,
        deletedFlag: deletedFlag ?? this.deletedFlag,
        trSeqNo: trSeqNo,
        wmtTime: wmtTime,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// LOCAL SQLITE HELPER
// ─────────────────────────────────────────────────────────────────────────────
class WeighmentDB {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, 'weighment.db'),
      version: 1,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS weighment_rows (
            pk           TEXT PRIMARY KEY,
            delivery_id  TEXT NOT NULL,
            load_wt      REAL DEFAULT 0,
            load_cages   INTEGER DEFAULT 0,
            empty_wt     REAL DEFAULT 0,
            empty_cages  INTEGER DEFAULT 0,
            net_wt       REAL DEFAULT 0,
            avg_wt       REAL DEFAULT 0,
            deleted_flag TEXT DEFAULT 'A',
            seq_no       INTEGER DEFAULT 0,
            entry_time   TEXT DEFAULT ''
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS weighment_session (
            delivery_id  TEXT PRIMARY KEY,
            total_birds  INTEGER DEFAULT 0,
            load_locked  INTEGER DEFAULT 0,
            mode         TEXT DEFAULT 'LOAD'
          )
        ''');
      },
    );
    return _db!;
  }

  static Future<void> upsertRow(String deliveryId, WeighmentRow row) async {
    final d = await db;
    await d.insert(
      'weighment_rows',
      row.toSqlite(deliveryId),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> upsertSession(
      String deliveryId, int totalBirds, bool locked, String mode) async {
    final d = await db;
    await d.insert(
      'weighment_session',
      {
        'delivery_id': deliveryId,
        'total_birds': totalBirds,
        'load_locked': locked ? 1 : 0,
        'mode': mode,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<WeighmentRow>> loadRows(String deliveryId) async {
    final d = await db;
    final rows = await d.query(
      'weighment_rows',
      where: 'delivery_id = ?',
      whereArgs: [deliveryId],
      orderBy: 'seq_no ASC',
    );
    return rows.map(WeighmentRow.fromSqlite).toList();
  }

  static Future<Map<String, dynamic>?> loadSession(String deliveryId) async {
    final d = await db;
    final r = await d.query(
      'weighment_session',
      where: 'delivery_id = ?',
      whereArgs: [deliveryId],
      limit: 1,
    );
    return r.isNotEmpty ? r.first : null;
  }

  static Future<void> clearDelivery(String deliveryId) async {
    final d = await db;
    await d.delete('weighment_rows',
        where: 'delivery_id = ?', whereArgs: [deliveryId]);
    await d.delete('weighment_session',
        where: 'delivery_id = ?', whereArgs: [deliveryId]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SUPABASE API LAYER
// Replace table names / column names to match your schema
// ─────────────────────────────────────────────────────────────────────────────
class WeighmentApi {
  static final _sb = Supabase.instance.client;

  /// Fetch existing rows for a delivery (used on screen open if SQLite empty)
  static Future<List<WeighmentRow>> fetchRows(String deliveryId) async {
    try {
      final res = await _sb
          .from('weighment_rows')
          .select()
          .eq('delivery_id', deliveryId)
          .order('seq_no');
      return (res as List).map((e) => WeighmentRow.fromJson(e)).toList();
    } catch (e) {
      debugPrint('[Supabase] fetchRows error: $e');
      return [];
    }
  }

  /// Upsert all rows for a delivery (called after every entry — background)
  static Future<bool> saveRows(
      String deliveryId, List<WeighmentRow> rows) async {
    try {
      final data = rows.map((r) {
        final m = r.toJson();
        m['delivery_id'] = deliveryId;
        return m;
      }).toList();
      await _sb.from('weighment_rows').upsert(data);
      return true;
    } catch (e) {
      debugPrint('[Supabase] saveRows error: $e');
      return false;
    }
  }

  /// Save session header (called on lock/unlock/complete)
  static Future<void> upsertSession({
    required String deliveryId,
    required int totalBirds,
    required bool loadLocked,
    required String mode,
    int? returnedSame,
    int? returnedOld,
    double? collectedAmount,
    String? customerName,
    String? location,
    String? orderQty,
    double? totalLoadWt,
    double? totalEmptyWt,
    double? totalNetWt,
    double? avgBirdWt,
    int? totalCages,
    String? status, // 'IN_PROGRESS' or 'COMPLETED'
  }) async {
    try {
      await _sb.from('weighment_sessions').upsert({
        'delivery_id': deliveryId,
        'total_birds': totalBirds,
        'load_locked': loadLocked,
        'mode': mode,
        if (returnedSame != null) 'returned_same': returnedSame,
        if (returnedOld != null) 'returned_old': returnedOld,
        if (collectedAmount != null) 'collected_amount': collectedAmount,
        if (customerName != null) 'customer_name': customerName,
        if (location != null) 'location': location,
        if (orderQty != null) 'order_qty': orderQty,
        if (totalLoadWt != null) 'total_load_wt': totalLoadWt,
        if (totalEmptyWt != null) 'total_empty_wt': totalEmptyWt,
        if (totalNetWt != null) 'total_net_wt': totalNetWt,
        if (avgBirdWt != null) 'avg_bird_wt': avgBirdWt,
        if (totalCages != null) 'total_cages': totalCages,
        if (status != null) 'status': status,
      });
    } catch (e) {
      debugPrint('[Supabase] upsertSession error: $e');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BLUETOOTH MANAGER
// Handles scale connection and live weight streaming
// ─────────────────────────────────────────────────────────────────────────────
class BluetoothManager {
  BluetoothConnection? _connection;
  StreamSubscription? _dataSub;
  String _buffer = '';
  String? _lastError;

  bool get isConnected => _connection?.isConnected ?? false;

  String? get lastError => _lastError;

  final _weightController = StreamController<double>.broadcast();

  Stream<double> get weightStream => _weightController.stream;

  /// Request Android BT permissions correctly for both API < 31 and API 31+
  /// On Android 12+ (API 31+), BLUETOOTH_CONNECT is required to list/connect devices
  static Future<bool> requestPermissions() async {
    // Request all permissions — permission_handler handles version differences
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.locationWhenInUse, // Required for BT scan on Android < 12
    ].request();

    // Check critical ones
    final connectOk = statuses[Permission.bluetoothConnect]?.isGranted ?? false;
    final bluetoothOk = statuses[Permission.bluetooth]?.isGranted ??
        true; // may not exist on API 31+

    debugPrint('[BT] Permissions: connect=$connectOk bt=$bluetoothOk');
    return connectOk || bluetoothOk;
  }

  /// Check if Bluetooth is enabled on the device
  static Future<bool> isBluetoothEnabled() async {
    try {
      return await FlutterBluetoothSerial.instance.isEnabled ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Get list of already PAIRED (bonded) devices.
  /// NOTE: The scale MUST be paired in Android Settings → Bluetooth first.
  static Future<List<BluetoothDevice>> getPairedDevices() async {
    try {
      final devices = await FlutterBluetoothSerial.instance.getBondedDevices();
      debugPrint('[BT] Found ${devices.length} bonded devices');
      return devices;
    } catch (e) {
      debugPrint('[BT] getBondedDevices error: $e');
      return [];
    }
  }

  /// Connect to a scale by MAC address.
  /// FIX: Added timeout, retry, and specific error messages.
  Future<bool> connect(String address) async {
    _lastError = null;
    try {
      // Use a timeout so we don't wait forever (scale may be off or out of range)
      _connection = await BluetoothConnection.toAddress(address).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException(
            '''Scale did not respond within 15 seconds.

Checklist:
• Scale is switched ON
• Scale is within 5 metres
• Scale is paired in Android Settings → Bluetooth
• No other device is connected to the scale''',
          );
        },
      );
      _startListening();
      debugPrint('[BT] Connected to $address');
      return true;
    } on TimeoutException catch (e) {
      _lastError = e.message ?? 'Connection timed out';
      debugPrint('[BT] Timeout: $_lastError');
      return false;
    } catch (e) {
      final msg = e.toString();
      // Translate common raw error codes into human-readable messages
      if (msg.contains('BLUETOOTH_CONNECT') ||
          msg.contains('permission') ||
          msg.contains('SecurityException')) {
        _lastError = '''Permission denied.

Go to Android Settings → Apps → Rooster Trader → Permissions and grant Bluetooth permission.''';
      } else if (msg.contains('paired') ||
          msg.contains('bonded') ||
          msg.contains('bond')) {
        _lastError = '''Scale is not paired.

Go to Android Settings → Bluetooth → tap the scale name to pair it first.''';
      } else if (msg.contains('connect') ||
          msg.contains('refused') ||
          msg.contains('unable')) {
        _lastError =
            'Could not connect. The scale may be busy or off. Try turning it off and on.';
      } else {
        _lastError = 'Connection failed: $msg';
      }

      debugPrint('[BT] Connect error: $_lastError');
      return false;
    }
  }

  void _startListening() {
    _dataSub = _connection!.input!.listen(
      (data) {
        _buffer += String.fromCharCodes(data);
        while (_buffer.contains('\n')) {
          final idx = _buffer.indexOf('\n');
          final line = _buffer.substring(0, idx).trim();
          _buffer = _buffer.substring(idx + 1);
          final val = _parseScaleLine(line);
          if (val != null && val >= 0) {
            _weightController.add(val);
          }
        }
      },
      onError: (e) {
        debugPrint('[BT] Stream error: $e');
        disconnect();
      },
      onDone: () {
        debugPrint('[BT] Stream done — scale disconnected');
        disconnect();
      },
      cancelOnError: false,
    );
  }

  /// Parse scale output — handles all common formats:
  ///   "85.340"          plain number
  ///   " 85.340 kg"      with unit + spaces
  ///   "ST,GS,85.340kg"  stable/unstable prefix
  ///   "+085.340"        sign + zero-padded
  double? _parseScaleLine(String line) {
    if (line.isEmpty) return null;
    // Extract only digits and decimal point
    final cleaned = line.replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty || cleaned == '.') return null;
    return double.tryParse(cleaned);
  }

  void disconnect() {
    _dataSub?.cancel();
    _dataSub = null;
    try {
      _connection?.dispose();
    } catch (_) {}
    _connection = null;
    _buffer = '';
  }

  void dispose() {
    disconnect();
    _weightController.close();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WEIGHMENT SCREEN WIDGET
// ─────────────────────────────────────────────────────────────────────────────
class WeighmentScreen extends StatefulWidget {
  final String deliveryId;
  final String orderRef;
  final String customerName;
  final String location;
  final int orderQty;

  const WeighmentScreen({
    super.key,
    required this.deliveryId,
    required this.orderRef,
    this.customerName = 'Customer',
    this.location = 'Location',
    this.orderQty = 0,
  });

  @override
  State<WeighmentScreen> createState() => _WeighmentScreenState();
}

class _WeighmentScreenState extends State<WeighmentScreen> {
  // ── Core data ──────────────────────────────────────────────────
  List<WeighmentRow> _rows = [];
  bool _loadLocked = false;
  int _totalBirds = 0;
  String _mode = 'LOAD'; // 'LOAD' or 'EMPTY'
  bool _loading = true;
  bool _saving = false;
  int _pkCounter = 0;

  // ── Editable header fields ─────────────────────────────────────
  late String _customerName;
  late String _location;
  late String _orderQty;

  // ── Weight input ───────────────────────────────────────────────
  final _weightCtrl = TextEditingController(text: '0');
  double _liveWeight = 0;
  bool _isManual = false;
  double _lastCaptured = 0;
  bool _wasReset = true;

  // ── Bluetooth ─────────────────────────────────────────────────
  final _bt = BluetoothManager();
  List<BluetoothDevice> _pairedDevices = [];
  BluetoothDevice? _connectedDevice;
  bool _btConnecting = false;
  StreamSubscription? _weightSub;

  // ── Completion fields ──────────────────────────────────────────
  final _returnedSameCtrl = TextEditingController();
  final _returnedOldCtrl = TextEditingController();
  final _collectedAmtCtrl = TextEditingController();

  // ─────────────────────────────────────────────────────────────
  // INIT
  // ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _customerName = widget.customerName;
    _location = widget.location;
    _orderQty = widget.orderQty.toString();
    _init();
    _setupBluetooth();
  }

  Future<void> _init() async {
    // 1. Load from SQLite first (crash-safe, offline)
    final localRows = await WeighmentDB.loadRows(widget.deliveryId);
    final localSession = await WeighmentDB.loadSession(widget.deliveryId);

    if (localRows.isNotEmpty) {
      setState(() {
        _rows = localRows;
        if (localSession != null) {
          _totalBirds = localSession['total_birds'] as int;
          _loadLocked = (localSession['load_locked'] as int) == 1;
          _mode = localSession['mode'] as String;
        }
        _loading = false;
      });
    } else {
      // 2. Fall back to Supabase if SQLite empty
      final remoteRows = await WeighmentApi.fetchRows(widget.deliveryId);
      for (final r in remoteRows) {
        await WeighmentDB.upsertRow(widget.deliveryId, r);
      }
      setState(() {
        _rows = remoteRows;
        _loading = false;
      });
    }
  }

  Future<void> _setupBluetooth() async {
    // Step 1: Request permissions (handles Android 12+ correctly)
    final permOk = await BluetoothManager.requestPermissions();
    if (!permOk) {
      debugPrint(
          '[BT] Permissions not fully granted — manual entry still works');
      // Don't block — manual weight entry always works as fallback
    }

    // Step 2: Check if Bluetooth is enabled
    final btEnabled = await BluetoothManager.isBluetoothEnabled();
    if (!btEnabled) {
      debugPrint('[BT] Bluetooth not enabled');
      // Don't auto-request enable — let user do it from notification bar
      return;
    }

    // Step 3: Load paired devices
    final devices = await BluetoothManager.getPairedDevices();
    if (mounted) setState(() => _pairedDevices = devices);

    // Step 4: Show picker if devices found
    if (devices.isNotEmpty && mounted) {
      // Small delay so screen is fully built before showing sheet
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) _showDevicePicker();
    }
    // If no devices: guide is shown in the BT bar "No scale connected"
    // Manual entry always works
  }

  // ─────────────────────────────────────────────────────────────
  // BLUETOOTH CONNECT
  // ─────────────────────────────────────────────────────────────
  Future<void> _connectToScale(BluetoothDevice device) async {
    setState(() => _btConnecting = true);
    final ok = await _bt.connect(device.address);
    setState(() {
      _btConnecting = false;
      _connectedDevice = ok ? device : null;
    });

    if (ok) {
      _showSnack('✅ Scale connected: ${device.name ?? device.address}');
      // Listen to live weight stream
      _weightSub = _bt.weightStream.listen((w) {
        if (!mounted) return;
        setState(() {
          _liveWeight = w;
          if (!_isManual) _weightCtrl.text = w.toStringAsFixed(3);
          // Detect reset: weight drops to/near 0 → ready for next capture
          if (w < 0.05) {
            _wasReset = true;
            _lastCaptured = 0;
          }
        });
      });
    } else {
      // Show specific error from BluetoothManager
      final errorMsg = _bt.lastError ?? 'Connection failed. Try again.';
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(children: [
              Icon(Icons.bluetooth_disabled, color: Colors.red),
              SizedBox(width: 10),
              Text('Connection Failed',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ]),
            content: Text(errorMsg,
                style: const TextStyle(
                    fontSize: 14, height: 1.6, color: Color(0xFF475569))),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _showDevicePicker(); // Let them try again
                },
                style: ElevatedButton.styleFrom(backgroundColor: C.navy),
                child: const Text('Try Again',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ADD ENTRY — called from the + button
  // ─────────────────────────────────────────────────────────────
  void _onCapture() {
    final wt = double.tryParse(_weightCtrl.text.trim()) ?? 0;
    if (wt <= 0) {
      _showSnack('Invalid weight value');
      return;
    }
    if (!_isManual && !_wasReset) {
      _showSnack('Reset scale to 0 before next capture');
      return;
    }
    _lastCaptured = wt;
    _wasReset = false;
    _showAddModal(wt);
  }

  void _showAddModal(double weight) {
    final cagesCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
                child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: C.border, borderRadius: BorderRadius.circular(2)),
            )),
            const SizedBox(height: 20),
            Text(
              _mode == 'LOAD'
                  ? '⚖️  Load Weight Entry'
                  : '📦  Empty Weight Entry',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: C.navy),
            ),
            const SizedBox(height: 16),
            // Weight display
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: C.border, width: 1.5),
              ),
              child: Row(children: [
                Text(_mode == 'LOAD' ? 'Load Weight' : 'Empty Weight',
                    style: const TextStyle(
                        color: C.slate,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(weight.toStringAsFixed(3),
                    style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: C.navy)),
                const SizedBox(width: 6),
                const Text('kg',
                    style: TextStyle(color: C.slateL, fontSize: 16)),
              ]),
            ),
            const SizedBox(height: 12),
            // Cages input
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: C.border, width: 1.5),
              ),
              child: Row(children: [
                const Text('Cages',
                    style:
                        TextStyle(color: C.slate, fontWeight: FontWeight.w600)),
                const Spacer(),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: cagesCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.right,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Enter count',
                      border: InputBorder.none,
                    ),
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: C.navy),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: C.border),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Cancel', style: TextStyle(color: C.slate)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _confirmAdd(weight, int.tryParse(cagesCtrl.text) ?? 0);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: C.navy,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('CONFIRM',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5)),
                ),
              ),
            ]),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _confirmAdd(double wt, int cages) {
    setState(() {
      if (_mode == 'LOAD') {
        _pkCounter++;
        final row = WeighmentRow(
          pk: '${widget.deliveryId}_${DateTime.now().millisecondsSinceEpoch}_$_pkCounter',
          loadWt: wt,
          loadCages: cages,
          trSeqNo: _rows.length + 1,
          wmtTime: _timeNow(),
        );
        _rows = [..._rows, row];
        _persistRowAndSession(row);
      } else {
        // Fill next unfilled empty slot in order
        final idx =
            _rows.indexWhere((r) => r.deletedFlag == 'A' && r.emptyWt == 0);
        if (idx < 0) {
          _showSnack('All rows already have empty WT');
          return;
        }

        final updated = List<WeighmentRow>.from(_rows);
        updated[idx] = updated[idx].copyWith(
          emptyWt: wt,
          emptyCages: cages,
          netWt: double.parse((updated[idx].loadWt - wt).toStringAsFixed(3)),
        );

        // Recalculate avg across all filled rows
        final filled =
            updated.where((r) => r.deletedFlag == 'A' && r.emptyWt > 0);
        final totalNet = filled.fold(0.0, (s, r) => s + r.netWt);
        final avg = _totalBirds > 0 ? totalNet / _totalBirds : 0.0;

        _rows = updated
            .map((r) => r.deletedFlag == 'A' && r.emptyWt > 0
                ? r.copyWith(avgWt: double.parse(avg.toStringAsFixed(3)))
                : r)
            .toList();

        // Persist all updated rows
        for (final r
            in _rows.where((r) => r.deletedFlag == 'A' && r.emptyWt > 0)) {
          _persistRowAsync(r);
        }
        _persistSessionAsync();
      }

      _weightCtrl.text = '0';
      _isManual = false;
    });
  }

  // ─────────────────────────────────────────────────────────────
  // LOCK LOAD WT
  // ─────────────────────────────────────────────────────────────
  void _showDoneModal() {
    if (_rows.where((r) => r.deletedFlag == 'A' && r.loadWt > 0).isEmpty) {
      _showSnack('Add at least one Load WT entry first');
      return;
    }
    final birdsCtrl = TextEditingController();
    final totalLoadWT = _rows.fold(0.0, (s, r) => s + r.loadWt);
    final totalCages = _rows.fold(0, (s, r) => s + r.loadCages);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('🐦  Enter Total Birds Count',
            style: TextStyle(fontWeight: FontWeight.w800, color: C.navy)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'You\'ve entered ${_rows.length} Load WT rows.\nEnter the total birds count for this entire load.\nAfter confirmation, Load WT will be locked.',
              style: const TextStyle(color: C.slate, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: C.indigo, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: birdsCtrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Total birds',
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                style: const TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w900, color: C.navy),
              ),
            ),
            const SizedBox(height: 12),
            // Summary
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: C.border),
              ),
              child: Column(children: [
                _lockSummaryRow('Total Load Rows', '${_rows.length}'),
                _lockSummaryRow(
                    'Total Load WT', '${totalLoadWT.toStringAsFixed(2)} kg'),
                _lockSummaryRow('Total Cages', '$totalCages'),
              ]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('NO — Add More', style: TextStyle(color: C.slate)),
          ),
          ElevatedButton(
            onPressed: () {
              final birds = int.tryParse(birdsCtrl.text) ?? 0;
              if (birds <= 0) {
                _showSnack('Enter valid birds count');
                return;
              }
              Navigator.pop(context);
              _confirmLock(birds);
            },
            style: ElevatedButton.styleFrom(backgroundColor: C.red),
            child: const Text('YES — Lock & Proceed',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  void _confirmLock(int birds) {
    setState(() {
      _totalBirds = birds;
      _loadLocked = true;
      _mode = 'EMPTY';
    });
    _persistSessionAsync();
    _showSnack('Load WT locked. Now enter Empty Weights.');
  }

  void _unlockLoad() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Release Load WT Lock?'),
        content: const Text(
          'This will unlock Load WT so you can add more entries.\n\n'
          'Existing Empty WT entries are kept. New load entries you add will '
          'need their Empty WT entered after you re-lock.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _loadLocked = false;
                _mode = 'LOAD';
              });
              _persistSessionAsync();
              _showSnack('Load WT unlocked. Add entries then lock again.');
            },
            style: ElevatedButton.styleFrom(backgroundColor: C.amber),
            child: const Text('Release & Unlock',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // SAVE & SUBMIT
  // ─────────────────────────────────────────────────────────────
  void _onSave() {
    final active = _rows.where((r) => r.deletedFlag == 'A').toList();
    final totalLoadCages = active.fold(0, (s, r) => s + r.loadCages);
    final totalEmptyCages = active.fold(0, (s, r) => s + r.emptyCages);

    if (_loadLocked && totalEmptyCages != totalLoadCages) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Cage Count Mismatch'),
          content: Text(
            'Empty cages entered ($totalEmptyCages) must exactly match '
            'Load cages ($totalLoadCages).\n\nPlease review your empty weight entries.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'))
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Save'),
        content: const Text(
          'Are you sure you want to save and complete this weighment?\n\n'
          'A PDF report will also be downloaded automatically.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('No')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _saveAndComplete();
            },
            style: ElevatedButton.styleFrom(backgroundColor: C.green),
            child:
                const Text('Yes, Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAndComplete() async {
    setState(() => _saving = true);
    try {
      // 1. Generate and share PDF first (so user always has report)
      await _generateAndSharePdf();

      // 2. Save to Supabase
      final active = _rows.where((r) => r.deletedFlag == 'A').toList();
      await WeighmentApi.saveRows(widget.deliveryId, active);

      final totalNet = active.fold(0.0, (s, r) => s + r.netWt);
      final totalLoad = active.fold(0.0, (s, r) => s + r.loadWt);
      final totalEmpty = active.fold(0.0, (s, r) => s + r.emptyWt);
      final avgWt = _totalBirds > 0 ? totalNet / _totalBirds : 0.0;
      final retSame = int.tryParse(_returnedSameCtrl.text) ?? 0;
      final retOld = int.tryParse(_returnedOldCtrl.text) ?? 0;
      final collected = double.tryParse(_collectedAmtCtrl.text) ?? 0;

      await WeighmentApi.upsertSession(
        deliveryId: widget.deliveryId,
        totalBirds: _totalBirds,
        loadLocked: true,
        mode: 'EMPTY',
        returnedSame: retSame,
        returnedOld: retOld,
        collectedAmount: collected,
        customerName: _customerName,
        location: _location,
        orderQty: _orderQty,
        totalLoadWt: totalLoad,
        totalEmptyWt: totalEmpty,
        totalNetWt: totalNet,
        avgBirdWt: avgWt,
        totalCages: active.fold(0, (s, r) => s! + r.loadCages),
        status: 'COMPLETED',
      );

      // 3. Clear local SQLite
      await WeighmentDB.clearDelivery(widget.deliveryId);

      // 4. Reset UI
      setState(() {
        _rows = [];
        _loadLocked = false;
        _totalBirds = 0;
        _mode = 'LOAD';
        _returnedSameCtrl.clear();
        _returnedOldCtrl.clear();
        _collectedAmtCtrl.clear();
      });

      _showSnack('✅ Saved & PDF downloaded!');
    } catch (e) {
      debugPrint('[Save] error: $e');
      _showSnack('Save failed. Please try again.');
    } finally {
      setState(() => _saving = false);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // PDF GENERATION
  // ─────────────────────────────────────────────────────────────
  Future<void> _generateAndSharePdf() async {
    final active = _rows.where((r) => r.deletedFlag == 'A').toList();
    final totalLoadWT = active.fold(0.0, (s, r) => s + r.loadWt);
    final totalLoadCgs = active.fold(0, (s, r) => s + r.loadCages);
    final totalEmptyWT = active.fold(0.0, (s, r) => s + r.emptyWt);
    final totalNetWT = active.fold(0.0, (s, r) => s + r.netWt);
    final totalEmpCgs = active.fold(0, (s, r) => s + r.emptyCages);
    final avgWT = _totalBirds > 0 ? totalNetWT / _totalBirds : 0.0;
    final now = DateTime.now().toString().substring(0, 19);
    final cageOk = totalEmpCgs == totalLoadCgs;

    final pdf = pw.Document();
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (ctx) => [
        // Header
        pw.Container(
          color: PdfColors.blueGrey900,
          padding: const pw.EdgeInsets.all(16),
          child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('WEIGHMENT REPORT',
                    style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold)),
                pw.Text('Generated: $now | Order: ${widget.orderRef}',
                    style: const pw.TextStyle(
                        color: PdfColors.grey, fontSize: 10)),
              ]),
        ),
        pw.SizedBox(height: 12),
        // Info grid
        pw.Row(children: [
          _pdfInfoBox('CUSTOMER', _customerName),
          pw.SizedBox(width: 8),
          _pdfInfoBox('LOCATION', _location),
          pw.SizedBox(width: 8),
          _pdfInfoBox('TOTAL BIRDS', '$_totalBirds'),
          pw.SizedBox(width: 8),
          _pdfInfoBox('ORDER QTY', _orderQty),
        ]),
        pw.SizedBox(height: 8),
        // Cage tally status
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          color: cageOk ? PdfColors.green50 : PdfColors.red50,
          child: pw.Text(
            cageOk
                ? '✓ Cage Tally OK — Load: $totalLoadCgs = Empty: $totalEmpCgs'
                : '⚠ Cage Mismatch — Load: $totalLoadCgs | Empty: $totalEmpCgs',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: cageOk ? PdfColors.green800 : PdfColors.red800,
            ),
          ),
        ),
        pw.SizedBox(height: 12),
        // Data table
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.blueGrey100),
          columnWidths: {
            0: const pw.FixedColumnWidth(28),
            1: const pw.FlexColumnWidth(1.4),
            2: const pw.FlexColumnWidth(0.8),
            3: const pw.FlexColumnWidth(1.4),
            4: const pw.FlexColumnWidth(0.8),
            5: const pw.FlexColumnWidth(1.2),
            6: const pw.FlexColumnWidth(1.2),
          },
          children: [
            // Header row
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.blueGrey900),
              children: [
                '#',
                'Load WT',
                'L.Cgs',
                'Empty WT',
                'E.Cgs',
                'Net WT',
                'Avg WT'
              ]
                  .map((h) => pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 4, vertical: 6),
                        child: pw.Text(
                          h,
                          style: pw.TextStyle(
                              color: PdfColors.blueGrey200,
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold),
                          textAlign: pw.TextAlign.center,
                        ),
                      ))
                  .toList(),
            ),
            // Data rows
            ...active.asMap().entries.map((e) {
              final i = e.key;
              final r = e.value;
              final bg = i.isEven ? PdfColors.blueGrey50 : PdfColors.white;
              return pw.TableRow(
                decoration: pw.BoxDecoration(color: bg),
                children: [
                  '${i + 1}',
                  r.loadWt.toStringAsFixed(3),
                  '${r.loadCages}',
                  r.emptyWt > 0 ? r.emptyWt.toStringAsFixed(3) : '—',
                  r.emptyCages > 0 ? '${r.emptyCages}' : '—',
                  r.netWt != 0 ? r.netWt.toStringAsFixed(3) : '—',
                  r.avgWt > 0 ? r.avgWt.toStringAsFixed(3) : '—',
                ]
                    .map((cell) => pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 4, vertical: 5),
                          child: pw.Text(cell,
                              style: const pw.TextStyle(fontSize: 8),
                              textAlign: pw.TextAlign.center),
                        ))
                    .toList(),
              );
            }),
            // Footer totals
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
              children: [
                '${active.length}',
                'TOTAL',
                '$totalLoadCgs',
                totalEmptyWT > 0 ? totalEmptyWT.toStringAsFixed(3) : '—',
                '$totalEmpCgs',
                totalNetWT != 0 ? totalNetWT.toStringAsFixed(3) : '—',
                avgWT > 0 ? avgWT.toStringAsFixed(3) : '—',
              ]
                  .map((cell) => pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 4, vertical: 6),
                        child: pw.Text(cell,
                            style: pw.TextStyle(
                                fontSize: 8, fontWeight: pw.FontWeight.bold),
                            textAlign: pw.TextAlign.center),
                      ))
                  .toList(),
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        // Summary boxes
        pw.Row(children: [
          _pdfSumBox('TOTAL LOAD WT', '${totalLoadWT.toStringAsFixed(2)} kg'),
          pw.SizedBox(width: 8),
          _pdfSumBox('TOTAL EMPTY WT',
              totalEmptyWT > 0 ? '${totalEmptyWT.toStringAsFixed(2)} kg' : '—'),
          pw.SizedBox(width: 8),
          _pdfSumBox('TOTAL NET WT',
              totalNetWT != 0 ? '${totalNetWT.toStringAsFixed(2)} kg' : '—'),
          pw.SizedBox(width: 8),
          _pdfSumBox('AVG BIRD WT',
              avgWT > 0 ? '${avgWT.toStringAsFixed(3)} kg' : '—'),
        ]),
        pw.SizedBox(height: 8),
        pw.Text('Order ID: ${widget.deliveryId} | Printed: $now',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
      ],
    ));

    // Save to temp and show print/share dialog
    final dir = await getTemporaryDirectory();
    final fileName =
        'Weighment_${widget.orderRef.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(await pdf.save());

    // Share via native share sheet (WhatsApp, Gmail, Drive, etc.)
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      subject: 'Weighment Report — ${widget.orderRef}',
      text: _buildShareText(),
    );
  }

  String _buildShareText() {
    final active = _rows.where((r) => r.deletedFlag == 'A').toList();
    final totalNet = active.fold(0.0, (s, r) => s + r.netWt);
    final totalLoad = active.fold(0.0, (s, r) => s + r.loadWt);
    final totalEmpty = active.fold(0.0, (s, r) => s + r.emptyWt);
    final totalLCgs = active.fold(0, (s, r) => s + r.loadCages);
    final totalECgs = active.fold(0, (s, r) => s + r.emptyCages);
    final avgWt = _totalBirds > 0 ? totalNet / _totalBirds : 0.0;
    return '''
📋 WEIGHMENT REPORT
━━━━━━━━━━━━━━━━━━━━
🗂 Order       : ${widget.orderRef}
👤 Customer    : $_customerName
📍 Location    : $_location
📦 LOAD SUMMARY
  Total Entries  : ${active.length}
  Total Birds    : $_totalBirds
  Load Cages     : $totalLCgs
  Empty Cages    : $totalECgs
  Cage Status    : ${totalECgs == totalLCgs ? '✅ Matched ($totalLCgs)' : '⚠️ Mismatch'}
⚖️ WEIGHT SUMMARY
  Total Load WT  : ${totalLoad.toStringAsFixed(3)} kg
  Total Empty WT : ${totalEmpty.toStringAsFixed(3)} kg
  Total Net WT   : ${totalNet.toStringAsFixed(3)} kg
  Avg Bird WT    : ${avgWt.toStringAsFixed(3)} kg
━━━━━━━━━━━━━━━━━━━━
Delivery ID: ${widget.deliveryId}''';
  }

  // ─────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────
  Future<void> _persistRowAndSession(WeighmentRow row) async {
    await WeighmentDB.upsertRow(widget.deliveryId, row);
    await WeighmentDB.upsertSession(
        widget.deliveryId, _totalBirds, _loadLocked, _mode);
    WeighmentApi.saveRows(widget.deliveryId, _rows); // background — don't await
  }

  void _persistRowAsync(WeighmentRow row) {
    WeighmentDB.upsertRow(widget.deliveryId, row);
  }

  void _persistSessionAsync() {
    WeighmentDB.upsertSession(
        widget.deliveryId, _totalBirds, _loadLocked, _mode);
    WeighmentApi.upsertSession(
        deliveryId: widget.deliveryId,
        totalBirds: _totalBirds,
        loadLocked: _loadLocked,
        mode: _mode);
  }

  String _timeNow() {
    final t = DateTime.now();
    final h = t.hour > 12 ? t.hour - 12 : (t.hour == 0 ? 12 : t.hour);
    final m = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    final p = t.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m:$s $p';
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  void _showDevicePicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: C.border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Text('🔵  Connect Scale Device',
                style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 18, color: C.navy)),
            const SizedBox(height: 4),
            const Text('Select a paired Bluetooth scale',
                style: TextStyle(color: C.slateL, fontSize: 13)),
            const SizedBox(height: 12),

            if (_pairedDevices.isEmpty) ...[
              // No paired devices — show guidance
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3CD),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFE69C)),
                ),
                child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.warning_amber_rounded,
                            color: Colors.amber, size: 20),
                        SizedBox(width: 8),
                        Text('No paired scale found',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15)),
                      ]),
                      SizedBox(height: 10),
                      Text('To connect your Bluetooth scale:',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13)),
                      SizedBox(height: 6),
                      Text('1. Turn ON the weighing scale',
                          style: TextStyle(fontSize: 13, height: 1.6)),
                      Text('2. On Android: Settings → Bluetooth',
                          style: TextStyle(fontSize: 13, height: 1.6)),
                      Text('3. Find your scale in "Available devices"',
                          style: TextStyle(fontSize: 13, height: 1.6)),
                      Text('4. Tap it to Pair (one-time setup)',
                          style: TextStyle(fontSize: 13, height: 1.6)),
                      Text('5. Come back here and tap Refresh',
                          style: TextStyle(fontSize: 13, height: 1.6)),
                    ]),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    // Retry device scan
                    final devices = await BluetoothManager.getPairedDevices();
                    if (mounted) setState(() => _pairedDevices = devices);
                    if (mounted && devices.isNotEmpty)
                      _showDevicePicker();
                    else if (mounted)
                      _showSnack(
                          'Still no paired devices. Pair in Android Settings first.');
                  },
                  icon: const Icon(Icons.refresh),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: C.navy,
                      minimumSize: const Size(double.infinity, 48)),
                  label: const Text('Refresh Paired Devices',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
            ] else
              ..._pairedDevices.map((d) => ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: C.navyMid, shape: BoxShape.circle),
                      child: const Icon(Icons.scale,
                          color: Colors.white, size: 20),
                    ),
                    title: Text(d.name ?? 'Unknown Device',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, color: C.navy)),
                    subtitle: Text(d.address,
                        style: const TextStyle(fontSize: 11, color: C.slateL)),
                    trailing: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        await _connectToScale(d);
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: C.navy,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8)),
                      child: const Text('Connect',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    ),
                  )),

            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Skip — Use Manual Entry',
                  style: TextStyle(color: C.slateL)),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // DERIVED TOTALS
  // ─────────────────────────────────────────────────────────────
  Map<String, dynamic> get _totals {
    final active = _rows.where((r) => r.deletedFlag == 'A').toList();
    return {
      'totalRows': active.length,
      'totalLoadWT': active.fold(0.0, (s, r) => s + r.loadWt),
      'totalLoadCages': active.fold(0, (s, r) => s + r.loadCages),
      'totalEmptyWT': active.fold(0.0, (s, r) => s + r.emptyWt),
      'totalEmptyCages': active.fold(0, (s, r) => s + r.emptyCages),
      'totalNetWT': active.fold(0.0, (s, r) => s + r.netWt),
      'filledEmpty': active.where((r) => r.emptyWt > 0).length,
      'avgWT': _totalBirds > 0
          ? active.fold(0.0, (s, r) => s + r.netWt) / _totalBirds
          : 0.0,
    };
  }

  // ─────────────────────────────────────────────────────────────
  // PDF WIDGET HELPERS
  // ─────────────────────────────────────────────────────────────
  pw.Widget _pdfInfoBox(String label, String value) => pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: PdfColors.blueGrey50,
            border: pw.Border.all(color: PdfColors.blueGrey200),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(label,
                    style: const pw.TextStyle(
                        fontSize: 7, color: PdfColors.blueGrey400)),
                pw.SizedBox(height: 3),
                pw.Text(value,
                    style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blueGrey900)),
              ]),
        ),
      );

  pw.Widget _pdfSumBox(String label, String value) => pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(10),
          color: PdfColors.blueGrey900,
          child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(label,
                    style: const pw.TextStyle(
                        fontSize: 7, color: PdfColors.blueGrey400)),
                pw.SizedBox(height: 4),
                pw.Text(value,
                    style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white)),
              ]),
        ),
      );

  Widget _lockSummaryRow(String key, String val) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(key, style: const TextStyle(color: C.slate, fontSize: 13)),
          Text(val,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, color: C.navy, fontSize: 14)),
        ]),
      );

  // ─────────────────────────────────────────────────────────────
  // BUILD — MAIN UI
  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final t = _totals;
    final isLoad = _mode == 'LOAD';
    final isEmpty = _mode == 'EMPTY';

    return WillPopScope(
      onWillPop: () async {
        if (_rows.isEmpty) return true;
        final leave = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Go Back?'),
            content: const Text(
                'Your weighment entries are saved locally. You can resume anytime.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Stay')),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: C.red),
                child: const Text('Go Back',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
        return leave ?? false;
      },
      child: Scaffold(
        backgroundColor: C.bg,
        body: SafeArea(
          child: Column(
            children: [
              // ── HEADER ──────────────────────────────────────────
              _buildHeader(),

              // ── ORDER STRIP (editable) ───────────────────────────
              _buildOrderStrip(),

              // ── BT STATUS BAR ────────────────────────────────────
              _buildBtBar(),

              // ── SCROLLABLE BODY ──────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Mode banner
                      _buildModeBanner(t),

                      // Weight capture card
                      if (!_loadLocked || isEmpty) _buildWeightCard(),

                      // Done Load WT button
                      if (isLoad && !_loadLocked && _rows.isNotEmpty)
                        _buildDoneLoadBtn(),

                      // Release load lock button
                      if (_loadLocked) _buildReleaseLockBtn(),

                      // Data table
                      _buildTable(t),

                      // Summary strip
                      if ((t['filledEmpty'] as int) > 0 && _totalBirds > 0)
                        _buildSummaryStrip(t),

                      // Completion fields
                      if (_loadLocked) _buildCompletionCard(),

                      // Action buttons
                      _buildActionBar(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() => Container(
        color: C.navy,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          GestureDetector(
            onTap: () async {
              if (_rows.isEmpty) {
                Navigator.pop(context);
                return;
              }
              final leave = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Go Back?'),
                  content: const Text(
                      'Your weighment entries are saved locally. You can resume anytime.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Stay')),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(backgroundColor: C.red),
                      child: const Text('Go Back',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
              if (leave == true && mounted) Navigator.pop(context);
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF334155)),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.chevron_left, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('WEIGHMENT',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3)),
            ],
          )),
          // BT badge
          _buildBtBadge(),
        ]),
      );

  Widget _buildBtBadge() {
    final connected = _bt.isConnected;
    return GestureDetector(
      onTap: () => connected ? _bt.disconnect() : _showDevicePicker(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: connected ? const Color(0xFF022C22) : const Color(0xFF1E293B),
          border:
              Border.all(color: connected ? C.green : const Color(0xFF334155)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: connected
                  ? C.green
                  : _btConnecting
                      ? Colors.amber
                      : const Color(0xFF475569),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            _btConnecting
                ? 'PAIRING…'
                : connected
                    ? 'SCALE ON'
                    : 'NO SCALE',
            style: TextStyle(
              color: connected
                  ? C.green
                  : _btConnecting
                      ? Colors.amber
                      : const Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildOrderStrip() => Container(
        color: C.navyMid,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          _orderChip('CUSTOMER', _customerName,
              (v) => setState(() => _customerName = v)),
          _vDivider(),
          _orderChip(
              'LOCATION', _location, (v) => setState(() => _location = v)),
          _vDivider(),
          _orderChipQty(),
        ]),
      );

  Widget _orderChip(
          String label, String value, ValueChanged<String> onChanged) =>
      Expanded(
          child: Column(children: [
        Text(label,
            style: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1)),
        const SizedBox(height: 2),
        IntrinsicWidth(
            child: TextField(
          controller: TextEditingController(text: value)
            ..selection = TextSelection.collapsed(offset: value.length),
          onChanged: onChanged,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 12,
              fontWeight: FontWeight.w600),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 2),
            border: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF334155))),
            focusedBorder:
                UnderlineInputBorder(borderSide: BorderSide(color: C.indigo)),
          ),
        )),
      ]));

  Widget _orderChipQty() => Expanded(
          child: Column(children: [
        const Text('QTY',
            style: TextStyle(
                color: Color(0xFF475569),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1)),
        const SizedBox(height: 2),
        IntrinsicWidth(
            child: TextField(
          controller: TextEditingController(text: _orderQty),
          onChanged: (v) => setState(() => _orderQty = v),
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Color(0xFF818CF8),
              fontSize: 13,
              fontWeight: FontWeight.w800),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 2),
            border: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF334155))),
          ),
        )),
      ]));

  Widget _vDivider() => Container(
      width: 1,
      height: 30,
      color: const Color(0xFF334155),
      margin: const EdgeInsets.symmetric(horizontal: 4));

  Widget _buildBtBar() => Container(
        color: C.navyMid,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: _bt.isConnected
            ? Row(children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: C.green, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(_connectedDevice?.name ?? 'Scale Device',
                    style: const TextStyle(
                        color: C.green, fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: const Color(0xFF064E3B),
                      border: Border.all(color: C.green),
                      borderRadius: BorderRadius.circular(4)),
                  child: const Text('LIVE',
                      style: TextStyle(
                          color: C.green,
                          fontSize: 9,
                          fontWeight: FontWeight.w800)),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    _weightSub?.cancel();
                    _bt.disconnect();
                    setState(() => _connectedDevice = null);
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        border: Border.all(color: C.red),
                        borderRadius: BorderRadius.circular(6)),
                    child: const Text('Disconnect',
                        style:
                            TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
                  ),
                ),
              ])
            : Row(children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: Color(0xFFEF4444), shape: BoxShape.circle)),
                const SizedBox(width: 8),
                const Text('No scale connected',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                const Spacer(),
                GestureDetector(
                  onTap: _showDevicePicker,
                  child: const Text('  Refresh',
                      style: TextStyle(
                          color: C.indigo, fontWeight: FontWeight.w700)),
                ),
              ]),
      );

  Widget _buildModeBanner(Map t) => Container(
        color: const Color(0xFF1E293B),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          _modeStep('1', _mode == 'LOAD', false),
          const SizedBox(width: 8),
          Text('LOAD WT ${_loadLocked ? '🔒' : ''}',
              style: TextStyle(
                  color: _mode == 'LOAD' ? C.indigo : const Color(0xFF475569),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  fontSize: 13)),
          const SizedBox(width: 12),
          const Text('›',
              style: TextStyle(color: Color(0xFF334155), fontSize: 18)),
          const SizedBox(width: 12),
          _modeStep('2', _mode == 'EMPTY', true),
          const SizedBox(width: 8),
          Text('EMPTY WT',
              style: TextStyle(
                  color: _mode == 'EMPTY' ? C.green : const Color(0xFF475569),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  fontSize: 13)),
          const Spacer(),
          if (_loadLocked && _totalBirds > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: const Color(0xFF064E3B),
                  borderRadius: BorderRadius.circular(10)),
              child: Text('Birds: $_totalBirds | Cages: ${t['totalLoadCages']}',
                  style: const TextStyle(
                      color: C.green,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
          if (_mode == 'EMPTY') ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: t['totalEmptyCages'] == t['totalLoadCages']
                    ? const Color(0xFF064E3B)
                    : const Color(0xFF1C1917),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'E.Cages: ${t['totalEmptyCages']}/${t['totalLoadCages']}',
                style: TextStyle(
                  color: t['totalEmptyCages'] == t['totalLoadCages']
                      ? C.green
                      : Colors.amber,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ]),
      );

  Widget _modeStep(String n, bool active, bool green) => Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? (green ? C.green : C.indigo) : Colors.transparent,
          border: Border.all(
              color: active
                  ? (green ? C.green : C.indigo)
                  : const Color(0xFF475569),
              width: 2),
        ),
        child: Center(
            child: Text(n,
                style: TextStyle(
                    color: active ? Colors.white : const Color(0xFF475569),
                    fontSize: 11,
                    fontWeight: FontWeight.w800))),
      );

  Widget _buildWeightCard() => Container(
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        decoration: BoxDecoration(
          color: C.card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Row(children: [
          Expanded(
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                Expanded(
                    child: TextField(
                  controller: _weightCtrl,
                  onChanged: (v) => setState(() => _isManual = true),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(
                      fontSize: 42, fontWeight: FontWeight.w900, color: C.navy),
                  decoration: const InputDecoration(
                      border: InputBorder.none, isDense: true),
                )),
                const Text('kg',
                    style: TextStyle(
                        color: C.slateL,
                        fontSize: 18,
                        fontWeight: FontWeight.w600)),
              ])),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _onCapture,
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: C.navy,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: C.navy.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4))
                ],
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 28),
            ),
          ),
        ]),
      );

  Widget _buildDoneLoadBtn() => GestureDetector(
        onTap: _showDoneModal,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: C.indigo,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: C.indigo.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4))
            ],
          ),
          child: const Center(
              child: Text('✓  Done — Enter Birds Count & Lock Load WT',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5))),
        ),
      );

  Widget _buildReleaseLockBtn() => GestureDetector(
        onTap: _unlockLoad,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: C.amberBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: C.amber, width: 1.5),
          ),
          child: const Center(
              child: Text('↩  Release Load WT Lock — Add More Entries',
                  style: TextStyle(
                      color: Color(0xFF92400E),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4))),
        ),
      );

  Widget _buildTable(Map t) {
    final active = _rows.where((r) => r.deletedFlag == 'A').toList();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      decoration: BoxDecoration(
          color: C.card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)
          ]),
      clipBehavior: Clip.hardEdge,
      child: Column(children: [
        // Header
        Container(
          color: C.navy,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Row(
              children: [
            _th('#', 0.07),
            _th('Load WT', 0.20),
            _th('L.Cgs', 0.12),
            _th('Empty WT', 0.20),
            _th('E.Cgs', 0.12),
            _th('Net WT', 0.19),
          ].map((w) => w).toList()),
        ),
        // Rows
        if (active.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('No records yet. Capture a Load Weight to begin.',
                style: TextStyle(color: C.slateL, fontStyle: FontStyle.italic)),
          )
        else
          ...active.asMap().entries.map((e) {
            final i = e.key;
            final r = e.value;
            return Container(
              color: i.isEven ? const Color(0xFFF7F9FF) : Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
              child: Row(children: [
                _td('${i + 1}', 0.07),
                _td(r.loadWt > 0 ? r.loadWt.toStringAsFixed(3) : '—', 0.20),
                _td(r.loadCages > 0 ? '${r.loadCages}' : '—', 0.12),
                _td(r.emptyWt > 0 ? r.emptyWt.toStringAsFixed(3) : '—', 0.20),
                _td(r.emptyCages > 0 ? '${r.emptyCages}' : '—', 0.12,
                    color: r.emptyCages > 0 ? C.green : null),
                _td(r.netWt != 0 ? r.netWt.toStringAsFixed(3) : '—', 0.19),
              ]),
            );
          }),
        // Footer
        Container(
          color: const Color(0xFFF8FAFC),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Row(children: [
            _td('${t['totalRows']}', 0.07, bold: true),
            _td((t['totalLoadWT'] as double).toStringAsFixed(2), 0.20,
                bold: true),
            _td('${t['totalLoadCages']}', 0.12, bold: true),
            _td(
                (t['totalEmptyWT'] as double) > 0
                    ? (t['totalEmptyWT'] as double).toStringAsFixed(2)
                    : '—',
                0.20,
                bold: true),
            _td(
                (t['totalEmptyCages'] as int) > 0
                    ? '${t['totalEmptyCages']}'
                    : '—',
                0.12,
                bold: true,
                color: (t['totalEmptyCages'] as int) ==
                        (t['totalLoadCages'] as int)
                    ? C.green
                    : C.red),
            _td(
                (t['totalNetWT'] as double) != 0
                    ? (t['totalNetWT'] as double).toStringAsFixed(2)
                    : '—',
                0.19,
                bold: true),
          ]),
        ),
      ]),
    );
  }

  Widget _th(String label, double flex) => Expanded(
        flex: (flex * 100).toInt(),
        child: Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4)),
      );

  Widget _td(String text, double flex, {bool bold = false, Color? color}) =>
      Expanded(
        flex: (flex * 100).toInt(),
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: color ?? const Color(0xFF334155),
                fontSize: 12,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
      );

  Widget _buildSummaryStrip(Map t) => Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
            color: C.navy, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          _summaryItem('TOTAL NET WT',
              '${(t['totalNetWT'] as double).toStringAsFixed(2)} kg'),
          _summaryItem(
              'AVG WT', '${(t['avgWT'] as double).toStringAsFixed(3)} kg'),
          _summaryItem('BIRDS', '$_totalBirds'),
        ]),
      );

  Widget _summaryItem(String label, String value) => Expanded(
          child: Column(children: [
        Text(label,
            style: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1)),
        const SizedBox(height: 3),
        Text(value,
            style: const TextStyle(
                color: Color(0xFFF8FAFC),
                fontSize: 16,
                fontWeight: FontWeight.w800)),
      ]));

  Widget _buildCompletionCard() => Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: C.card,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('📋  Completion Details',
              style: TextStyle(
                  color: C.navy, fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          _completionRow('Returned (Same Batch)', _returnedSameCtrl),
          _completionRow('Returned (Old Stock)', _returnedOldCtrl),
          _completionRow('Collected Amount (₹)', _collectedAmtCtrl,
              isDecimal: true),
        ]),
      );

  Widget _completionRow(String label, TextEditingController ctrl,
          {bool isDecimal = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      color: C.slate, fontWeight: FontWeight.w600))),
          SizedBox(
            width: 110,
            child: TextField(
              controller: ctrl,
              keyboardType: isDecimal
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.number,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                hintText: isDecimal ? '0.00' : '0',
                hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: C.border, width: 1.5),
                ),
              ),
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: C.navy),
            ),
          ),
        ]),
      );

  Widget _buildActionBar() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(children: [
          Expanded(
              flex: 14,
              child: _actionBtn(
                  '✅', 'SUBMIT', C.greenBg, C.green, _saving ? null : _onSave)),
          const SizedBox(width: 8),
          Expanded(
              flex: 10,
              child: _actionBtn('📄', 'PDF', const Color(0xFFFFFBEB), C.amber,
                  _generateAndSharePdf)),
          const SizedBox(width: 8),
          Expanded(
              flex: 10,
              child: _actionBtn('←', 'BACK', C.redBg, C.red, () async {
                if (_rows.isEmpty) {
                  Navigator.pop(context);
                  return;
                }
                final leave = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Go Back?'),
                    content: const Text(
                        'Your weighment entries are saved locally. You can resume anytime.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Stay')),
                      ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style:
                              ElevatedButton.styleFrom(backgroundColor: C.red),
                          child: const Text('Go Back',
                              style: TextStyle(color: Colors.white))),
                    ],
                  ),
                );
                if (leave == true && mounted) Navigator.pop(context);
              })),
        ]),
      );

  Widget _actionBtn(
          String icon, String label, Color bg, Color fg, VoidCallback? onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: fg, width: 1.5),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(icon, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 1)),
          ]),
        ),
      );

  @override
  void dispose() {
    _weightSub?.cancel();
    _bt.dispose();
    _weightCtrl.dispose();
    _returnedSameCtrl.dispose();
    _returnedOldCtrl.dispose();
    _collectedAmtCtrl.dispose();
    super.dispose();
  }
}
