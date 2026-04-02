// weighment_service.dart
// Bluetooth weighing scale integration for Rooster Trader
// Supports two-phase weighment: LOAD WT → EMPTY WT → Net weight calculation
// Compatible with common Bluetooth serial/UART weight indicators
//
// ──────────────────────────────────────────────────────────────────────────────
// PUBSPEC DEPENDENCY REQUIRED:
//   flutter_blue_plus: ^1.32.0
// Also add to android/app/src/main/AndroidManifest.xml:
//   <uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
//   <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
//   <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// ── Data Models ───────────────────────────────────────────────────────────────

/// One row in the weighment table.
/// Mirrors the doc's TableRow: LOADWT, EMPTYWT, NETWT, LOAD_CAGES, EMPTY_CAGES
class WeighmentRow {
  final int    seqNo;
  double loadWt;
  int    loadCages;
  double emptyWt;
  int    emptyCages;
  final String wmtTime; // HH:MM:SS AM/PM

  WeighmentRow({
    required this.seqNo,
    required this.loadWt,
    required this.loadCages,
    this.emptyWt   = 0,
    this.emptyCages = 0,
    required this.wmtTime,
  });

  double get netWt => loadWt - emptyWt;
  bool   get emptyFilled => emptyWt > 0;

  WeighmentRow copyWith({double? emptyWt, int? emptyCages}) => WeighmentRow(
    seqNo: seqNo, loadWt: loadWt, loadCages: loadCages,
    emptyWt: emptyWt ?? this.emptyWt,
    emptyCages: emptyCages ?? this.emptyCages,
    wmtTime: wmtTime,
  );
}

/// Session-level data — one per delivery
class WeighmentSession {
  final String deliveryId;
  List<WeighmentRow> rows;
  int    totalBirds;
  bool   loadLocked;
  WeighmentPhase phase;
  WeighmentSession({
    required this.deliveryId,
    List<WeighmentRow>? rows,
    this.totalBirds  = 0,
    this.loadLocked  = false,
    this.phase       = WeighmentPhase.load,
  }) : rows = List.from(rows ?? []);

  double get totalLoadWt    => rows.fold(0, (s, r) => s + r.loadWt);
  double get totalEmptyWt   => rows.fold(0, (s, r) => s + r.emptyWt);
  double get totalNetWt     => rows.fold(0, (s, r) => s + r.netWt);
  int    get totalLoadCages => rows.fold(0, (s, r) => s + r.loadCages);
  int    get totalEmptyCages=> rows.fold(0, (s, r) => s + r.emptyCages);
  int    get filledEmptyRows=> rows.where((r) => r.emptyFilled).length;
  double get avgBirdWt      => totalBirds > 0 ? totalNetWt / totalBirds : 0;

  /// Next row that needs empty weight filled (in order)
  WeighmentRow? get nextEmptyRow =>
      rows.where((r) => !r.emptyFilled).firstOrNull;

  /// Cage count validation before submit
  bool get cagesMatch => totalLoadCages == totalEmptyCages;

  /// All rows have empty weight filled
  bool get allEmptyFilled => rows.isNotEmpty && rows.every((r) => r.emptyFilled);

  /// Final summary for complete_delivery
  WeighmentResult toResult() => WeighmentResult(
    totalBirds:    totalBirds,
    totalLoadWt:   totalLoadWt,
    totalEmptyWt:  totalEmptyWt,
    totalNetWt:    totalNetWt,
    avgBirdWtKg:   avgBirdWt,
    avgBirdWtG:    avgBirdWt * 1000,
    totalLoadCages:totalLoadCages,
    totalEmptyCages: totalEmptyCages,
    rows:          List.unmodifiable(rows),
  );
}

enum WeighmentPhase { load, empty }

/// Final result passed back to DeliveryCompleteScreen
class WeighmentResult {
  final int    totalBirds;
  final double totalLoadWt;
  final double totalEmptyWt;
  final double totalNetWt;
  final double avgBirdWtKg;
  final double avgBirdWtG;
  final int    totalLoadCages;
  final int    totalEmptyCages;
  final List<WeighmentRow> rows;

  const WeighmentResult({
    required this.totalBirds,
    required this.totalLoadWt,
    required this.totalEmptyWt,
    required this.totalNetWt,
    required this.avgBirdWtKg,
    required this.avgBirdWtG,
    required this.totalLoadCages,
    required this.totalEmptyCages,
    required this.rows,
  });
}

// ── Bluetooth Service ─────────────────────────────────────────────────────────

/// Connects to a Bluetooth weight scale and streams live weight readings.
///
/// Most weighing scale indicators use a BLE UART profile:
///   Service UUID:  6E400001-B5A3-F393-E0A9-E50E24DCCA9E  (Nordic UART)
///   TX Char UUID:  6E400002-B5A3-F393-E0A9-E50E24DCCA9E  (write to scale)
///   RX Char UUID:  6E400003-B5A3-F393-E0A9-E50E24DCCA9E  (read weight from scale)
///
/// Weight data format varies by manufacturer. Common formats:
///   "  85.340\r\n"   (plain decimal)
///   "85340g\r\n"     (grams with unit)
///   "+085.34kg\r\n"  (with sign and unit)
///   "ST,GS,  85.340kg\r\n"  (Mettler-Toledo / A&D style)
///
/// This service handles all common formats via _parseWeight().
class WeighmentBluetoothService {
  // Nordic UART Service (most common for scale indicators)
  static const _uartServiceUuid  = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const _uartRxCharUuid   = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

  BluetoothDevice? _device;
  BluetoothCharacteristic? _rxChar;
  StreamSubscription? _sub;
  final _weightController = StreamController<double>.broadcast();
  String _buffer = '';

  Stream<double> get weightStream => _weightController.stream;
  bool get isConnected => _device?.isConnected == true && _rxChar != null;

  /// Scan for nearby paired/bonded BLE devices that look like scales.
  /// Returns devices visible in the scan — user must pick one.
  Future<List<BluetoothDevice>> scanForScales({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final results = <BluetoothDevice>[];
    try {
      // Check if BT is on
      if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
        return [];
      }
      await FlutterBluePlus.startScan(timeout: timeout);
      await for (final r in FlutterBluePlus.scanResults) {
        for (final sr in r) {
          if (!results.any((d) => d.remoteId == sr.device.remoteId)) {
            results.add(sr.device);
          }
        }
      }
    } catch (e) {
      debugPrint('[BT] Scan error: $e');
    }
    return results;
  }

  /// Also return system-bonded devices (already paired in phone Settings)
  Future<List<BluetoothDevice>> getBondedDevices() async {
    try {
      return await FlutterBluePlus.bondedDevices;
    } catch (_) {
      return [];
    }
  }

  /// Connect to a specific device and start receiving weight data
  Future<bool> connect(BluetoothDevice device) async {
    try {
      await disconnect();
      await device.connect(timeout: const Duration(seconds: 10));
      _device = device;

      final services = await device.discoverServices();
      for (final svc in services) {
        if (svc.uuid.toString().toLowerCase() == _uartServiceUuid) {
          for (final char in svc.characteristics) {
            if (char.uuid.toString().toLowerCase() == _uartRxCharUuid) {
              _rxChar = char;
              await char.setNotifyValue(true);
              _sub = char.lastValueStream.listen(_onData);
              debugPrint('[BT] Connected to ${device.platformName} — weight stream active');
              return true;
            }
          }
        }
      }
      // If UART service not found, try to read any notifiable characteristic
      for (final svc in services) {
        for (final char in svc.characteristics) {
          if (char.properties.notify || char.properties.indicate) {
            _rxChar = char;
            await char.setNotifyValue(true);
            _sub = char.lastValueStream.listen(_onData);
            debugPrint('[BT] Connected using fallback char ${char.uuid}');
            return true;
          }
        }
      }
      debugPrint('[BT] No suitable characteristic found');
      return false;
    } catch (e) {
      debugPrint('[BT] Connect error: $e');
      return false;
    }
  }

  void _onData(List<int> bytes) {
    if (bytes.isEmpty) return;
    _buffer += utf8.decode(bytes, allowMalformed: true);

    // Process complete lines
    while (_buffer.contains('\n')) {
      final idx  = _buffer.indexOf('\n');
      final line = _buffer.substring(0, idx).trim();
      _buffer    = _buffer.substring(idx + 1);
      if (line.isNotEmpty) {
        final weight = _parseWeight(line);
        if (weight != null && weight > 0) {
          _weightController.add(weight);
        }
      }
    }
  }

  /// Parse weight from various scale output formats.
  /// Returns weight in KG always. Returns null if unparseable.
  double? _parseWeight(String raw) {
    // Remove non-numeric except . - +
    final cleaned = raw.replaceAll(RegExp(r'[^\d.\-+]'), ' ').trim();
    final parts   = cleaned.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();

    for (final part in parts) {
      final n = double.tryParse(part);
      if (n == null || n <= 0) continue;

      // Check if original had 'g' or 'gram' → convert to kg
      if (raw.toLowerCase().contains('g') && !raw.toLowerCase().contains('kg')) {
        return n / 1000;
      }
      // Check if value looks like grams (> 500 without kg unit, likely not kg)
      if (n > 500 && !raw.toLowerCase().contains('kg')) {
        return n / 1000;
      }
      return n; // assume kg
    }
    return null;
  }

  Future<void> disconnect() async {
    await _sub?.cancel();
    _sub    = null;
    _rxChar = null;
    try { await _device?.disconnect(); } catch (_) {}
    _device = null;
    _buffer = '';
    debugPrint('[BT] Disconnected');
  }

  void dispose() {
    disconnect();
    _weightController.close();
  }
}
