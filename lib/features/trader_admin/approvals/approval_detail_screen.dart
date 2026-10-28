import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/responsive_layout.dart';

class ApprovalDetailScreen extends ConsumerStatefulWidget {
  const ApprovalDetailScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<ApprovalDetailScreen> createState() => _S();
}

class _S extends ConsumerState<ApprovalDetailScreen> {
  final _c = Supabase.instance.client;
  final _rateCtrl = TextEditingController(); // single-product fallback
  final _notesCtrl = TextEditingController();
  final _rejectCtrl   = TextEditingController();  // legacy — kept for backward compat
  final _flagNotesCtrl = TextEditingController();
  String? _flagCategory;
  bool _showBleExpanded   = false;   // BLE log collapsed for 5-second approval
  bool _showFlagExpanded  = false;

  // Per-product rate controllers: order_item_id -> TextEditingController
  final Map<String, TextEditingController> _itemRateCtrls = {};

  Map<String, dynamic>? _delivery;
  Map<String, dynamic>? _weighSession;
  List<Map<String, dynamic>> _weighRows = [];
  List<Map<String, dynamic>> _orderItems = []; // order_items with product info
  List<Map<String, dynamic>> _ratePreview = []; // Phase 3: v4 resolved rates
  bool _loading = true, _submitting = false;
  DateTime _invoiceDate = DateTime.now();
  String? _orderId; // kept to re-fetch the rate preview if Invoice Date changes

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _rateCtrl.dispose();
    _notesCtrl.dispose();
    _rejectCtrl.dispose();
    _flagNotesCtrl.dispose();
    for (final c in _itemRateCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      // 1. Delivery with full join
      final d = await _c
          .from('deliveries')
          .select('*,'
          'orders(id,estimated_birds,total_quantity,retailer_id,'
          '  retailers(shop_name,owner_name,phone,address),'
          '  order_items(id,product_id,rate_per_kg,total_weight,bird_count,master_products(name))),'
          'delivery_agents(name,vehicle_no,phone),'
          'delivery_batches(id,'
          '  delivery_challans(dc_number,dc_date,farmer_name,farm_location,'
          '    vehicle_number,gross_weight,empty_crate_weight,net_weight,'
          '    bird_count,crates_count,farm_rate,dc_photo_url))')
          .eq('id', widget.id)
          .maybeSingle();
      if (!mounted || d == null) return;

      // 2. Weighment session
      Map<String, dynamic>? ws;
      List<Map<String, dynamic>> rows = [];
      try {
        ws = await _c
            .from('weighment_sessions')
            .select('*')
            .eq('delivery_id', widget.id)
            .maybeSingle();
        if (ws != null) {
          final r = await _c
              .from('weighment_rows')
              .select('*')
              .eq('delivery_id', widget.id)
              .eq('deleted_flag', 'A')
              .order('seq_no');
          rows = List<Map<String, dynamic>>.from(r as List? ?? []);
        }
      } catch (_) {}

      // Extract order_items with product info
      final rawItems = (d['orders']?['order_items'] as List? ?? []);
      final parsedItems =
      rawItems.map((i) => Map<String, dynamic>.from(i as Map)).toList();

      // Dispose old controllers before creating new ones
      for (final c in _itemRateCtrls.values) {
        c.dispose();
      }
      _itemRateCtrls.clear();

      // Create per-item rate controllers, pre-fill from existing rate or delivery final_rate
      final existRate = (d['final_rate'] as num?)?.toDouble() ?? 0;
      for (final item in parsedItems) {
        final itemId = item['id'] as String? ?? '';
        final itemRate = (item['rate_per_kg'] as num?)?.toDouble() ?? 0;
        final fallback = itemRate > 0 ? itemRate : existRate;
        _itemRateCtrls[itemId] = TextEditingController(
            text: fallback > 0
                ? fallback.toStringAsFixed(2).replaceAll('.00', '')
                : '');
      }

      // Single-rate fallback for backward compat (when only 1 product)
      final firstRate = parsedItems.isNotEmpty
          ? (parsedItems.first['rate_per_kg'] as num?)?.toDouble() ?? 0
          : 0;
      _rateCtrl.text = (existRate > 0 ? existRate : firstRate) > 0
          ? (existRate > 0 ? existRate : firstRate)
          .toStringAsFixed(2)
          .replaceAll('.00', '')
          : '';

      // Invoice date from delivery
      final delivAt = d['delivered_at'] as String?;
      if (delivAt != null) {
        final p = DateTime.tryParse(delivAt);
        if (p != null && mounted) _invoiceDate = p;
      }

      // Phase 3: Load v4 rate preview (what will be charged at approval).
      // p_date must match the Invoice Date, not "today" — otherwise a
      // trader who has just corrected a missed/wrong Product Zone Price
      // for a past day (up to 7 days back) would still see and submit
      // today's rate for a multi-product order dated that past day.
      List<Map<String, dynamic>> preview = [];
      try {
        final orderId = d['orders']?['id'] as String?;
        _orderId = orderId;
        if (orderId != null) {
          final res = await _c.rpc('get_order_rate_preview', params: {
            'p_order_id': orderId,
            'p_date': DateFormat('yyyy-MM-dd').format(_invoiceDate),
          });
          preview = List<Map<String, dynamic>>.from(res as List? ?? []);
          // Pre-fill rate controllers from v4 resolved rates
          for (final item in preview) {
            final oid = item['order_item_id'] as String?;
            final rate = (item['rate'] as num?)?.toDouble() ?? 0;
            if (oid != null && _itemRateCtrls.containsKey(oid) && rate > 0) {
              _itemRateCtrls[oid]!.text =
                  rate.toStringAsFixed(2).replaceAll('.00', '');
            }
          }
          if (preview.isNotEmpty) {
            final firstRate = (preview.first['rate'] as num?)?.toDouble() ?? 0;
            if (firstRate > 0 && _rateCtrl.text.isEmpty) {
              _rateCtrl.text =
                  firstRate.toStringAsFixed(2).replaceAll('.00', '');
            }
          }
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _delivery = d;
          _weighSession = ws;
          _weighRows = rows;
          _orderItems = parsedItems;
          _ratePreview = preview;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Re-resolves the v4 rate preview for the *current* Invoice Date and
  // refreshes the rate boxes. Called whenever the trader changes Invoice
  // Date, so the per-item rates that get submitted to
  // approve_delivery_and_order (as p_item_rates, for multi-product orders)
  // always reflect the latest applicable Product Zone Price for that date —
  // required so back-dated rate corrections (now up to 7 days) actually
  // flow through to Pending Approval instead of silently billing today's
  // rate. Single-product orders already re-resolve server-side regardless,
  // but refreshing here keeps what the trader sees on screen honest too.
  Future<void> _refreshRatePreview() async {
    if (_orderId == null) return;
    try {
      final res = await _c.rpc('get_order_rate_preview', params: {
        'p_order_id': _orderId,
        'p_date': DateFormat('yyyy-MM-dd').format(_invoiceDate),
      });
      final preview = List<Map<String, dynamic>>.from(res as List? ?? []);
      for (final item in preview) {
        final oid = item['order_item_id'] as String?;
        final rate = (item['rate'] as num?)?.toDouble() ?? 0;
        if (oid != null && _itemRateCtrls.containsKey(oid) && rate > 0) {
          _itemRateCtrls[oid]!.text =
              rate.toStringAsFixed(2).replaceAll('.00', '');
        }
      }
      if (preview.isNotEmpty) {
        final firstRate = (preview.first['rate'] as num?)?.toDouble() ?? 0;
        if (firstRate > 0) {
          _rateCtrl.text = firstRate.toStringAsFixed(2).replaceAll('.00', '');
        }
      }
      if (mounted) setState(() => _ratePreview = preview);
    } catch (_) {}
  }

  // ── Core values ──────────────────────────────────────────────────
  double get _rate => double.tryParse(_rateCtrl.text.trim()) ?? 0;

  // Multi-product: true when there are 2+ order items with different products
  bool get _isMultiProduct => _orderItems.length > 1;

  // Proportional share of billing weight for one order_item.
  // Single-product: returns _billingWeight exactly.
  // Multi-product: distributes delivered total proportionally by ordered weight.
  double _itemDeliveredWeight(Map<String, dynamic> item) {
    final totalOrdered = _orderItems.fold<double>(
        0.0, (s, i) => s + ((i['total_weight'] as num?)?.toDouble() ?? 0.0));
    final itemOrdered = (item['total_weight'] as num?)?.toDouble() ?? 0.0;
    if (totalOrdered > 0) return _billingWeight * itemOrdered / totalOrdered;
    if (_orderItems.isNotEmpty) return _billingWeight / _orderItems.length;
    return 0.0;
  }

  // Sum of all line totals — uses DELIVERED (not ordered) weight per item
  double get _multiProductTotal {
    double total = 0;
    for (final item in _orderItems) {
      final id   = item['id'] as String? ?? '';
      final rate = double.tryParse(_itemRateCtrls[id]?.text.trim() ?? '') ?? 0;
      total += _itemDeliveredWeight(item) * rate;
    }
    return total;
  }

  // Effective billing amount: multi-product sum or single rate × billing weight
  double get _billAmount =>
      _isMultiProduct ? _multiProductTotal : _billingWeight * _rate;

  // ── BLE weight sources ────────────────────────────────────────────────────

  // Sum of INDIVIDUAL weighment_rows.net_wt — most authoritative BLE weight.
  // More reliable than session summary which can be corrupted (e.g. bird count
  // stored as net weight in some BLE device firmware versions).
  double get _weighRowNetTotal => _weighRows.fold<double>(
      0, (sum, r) => sum + ((r['net_wt'] as num?)?.toDouble() ?? 0));

  // Session summary net weight (may differ from row sum if device had a bug)
  double get _weighSessionNetTotal => _weighSession != null
      ? ((_weighSession!['total_net_wt'] as num?)?.toDouble() ?? 0)
      : 0;

  // Whether BLE session summary differs significantly from individual row sum.
  bool get _bleDiscrepancy {
    if (_weighRows.isEmpty || _weighSessionNetTotal <= 0) return false;
    final ratio =
        (_weighRowNetTotal - _weighSessionNetTotal).abs() / _weighSessionNetTotal;
    return ratio > 0.01;
  }

  double get _bleDiscrepancyKg =>
      (_weighRowNetTotal - _weighSessionNetTotal).abs();

  // What agent manually entered at delivery completion
  double get _agentDeliveredWt =>
      ((_delivery?['received_total_weight'] ??
          _delivery?['delivered_total_weight']) as num?)
          ?.toDouble() ??
          0;

  // ── BILLING WEIGHT PRIORITY CHAIN ─────────────────────────────────────────
  // Priority 1: SUM(weighment_rows.net_wt) — immune to session summary corruption
  // Priority 2: delivery.delivered_total_weight — stored by complete_delivery RPC
  // Priority 3: Session summary — last resort (may equal bird count due to BLE bug)
  double get _billingWeight {
    if (_weighRows.isNotEmpty && _weighRowNetTotal > 0) return _weighRowNetTotal;
    if (_agentDeliveredWt > 0) return _agentDeliveredWt;
    return _weighSessionNetTotal;
  }

  // Legacy alias used by BLE display header
  double get _weighNetTotal => _weighSessionNetTotal;

  // ORDER-level loss (correct formula)
  double get _orderExpectedWt =>
      (_delivery?['orders']?['total_quantity'] as num?)?.toDouble() ?? 0;

  int get _orderExpectedBirds =>
      (_delivery?['orders']?['estimated_birds'] as num?)?.toInt() ?? 0;

  // DC weight stored on delivery (set by complete_delivery RPC) — best base for loss %
  double get _dcWeightForLoss =>
      (_delivery?['dc_weight_kg'] as num?)?.toDouble() ?? 0;

  double get _transportLoss =>
      (_delivery?['transport_loss_kg'] as num?)?.toDouble() ??
          (_dcWeightForLoss > 0 && _billingWeight > 0
              ? (_dcWeightForLoss - _billingWeight).clamp(0.0, double.infinity)
              : 0);

  double get _mortalityWt =>
      (_delivery?['mortality_weight_kg'] as num?)?.toDouble() ?? 0;

  double get _totalLoss => _transportLoss + _mortalityWt;

  // Use stored loss_percentage when available (most accurate); else compute vs DC weight
  double get _lossPct =>
      (_delivery?['loss_percentage'] as num?)?.toDouble() ??
          (_dcWeightForLoss > 0 ? (_totalLoss / _dcWeightForLoss * 100) : 0);

  bool get _isHighLoss => _lossPct >= 2.0;

  double get _collected =>
      (_delivery?['collected_amount'] as num?)?.toDouble() ?? 0;

  double get _balance => _billAmount - _collected;

  int get _mortalityBirds =>
      (_delivery?['mortality_birds'] as num?)?.toInt() ?? 0;

  Future<void> _approve() async {
    // Validate rates
    if (_isMultiProduct) {
      for (final item in _orderItems) {
        final id = item['id'] as String? ?? '';
        final name =
            (item['master_products'] as Map?)?['name'] as String? ?? 'Item';
        final rate =
            double.tryParse(_itemRateCtrls[id]?.text.trim() ?? '') ?? 0;
        if (rate <= 0) {
          showError(context, 'Enter rate for $name');
          return;
        }
      }
    } else {
      if (_rate <= 0) {
        showError(context, 'Enter rate per kg');
        return;
      }
    }
    if (_billingWeight <= 0) {
      showError(context, 'No weight data available');
      return;
    }

    final source = _weighNetTotal > 0 ? 'BLE Scale' : 'Agent Entry';

    // Build confirmation message
    String confirmMsg;
    if (_isMultiProduct) {
      final lines = _orderItems.map((item) {
        final id   = item['id'] as String? ?? '';
        final name = (item['master_products'] as Map?)?['name'] as String? ?? '—';
        final wt   = _itemDeliveredWeight(item); // ← delivered weight share
        final rate = double.tryParse(_itemRateCtrls[id]?.text.trim() ?? '') ?? 0;
        return '$name: ${wt.toStringAsFixed(2)} kg × ₹${rate.toStringAsFixed(2)} = ${Fmt.amount(wt * rate)}';
      }).join('\n');
      confirmMsg = '$lines\n─────\nTotal: ${Fmt.amount(_billAmount)}\n'
          'Weight source: $source\n'
          'Invoice date: ${DateFormat('d MMM y').format(_invoiceDate)}';
    } else {
      confirmMsg =
      '${_billingWeight.toStringAsFixed(2)} kg × ₹${_rate.toStringAsFixed(2)}/kg'
          ' = ${Fmt.amount(_billAmount)}\n'
          'Weight source: $source\n'
          'Invoice date: ${DateFormat('d MMM y').format(_invoiceDate)}';
    }

    final ok = await confirmDialog(context,
        title: 'Approve Delivery',
        message: confirmMsg,
        confirmText: 'Approve & Create Bill',
        confirmColor: kPrimary);
    if (!ok) return;

    if (mounted) setState(() => _submitting = true);
    try {
      // Build per-item rates for multi-product orders
      List<Map<String, dynamic>>? itemRates;
      if (_isMultiProduct) {
        itemRates = _orderItems.map((item) {
          final id = item['id'] as String;
          final rate =
              double.tryParse(_itemRateCtrls[id]?.text.trim() ?? '') ?? 0;
          return {'order_item_id': id, 'rate_per_kg': rate};
        }).toList();
      }

      await _c.rpc('approve_delivery_and_order', params: {
        'p_delivery_id': widget.id,
        'p_final_rate': _isMultiProduct ? null : _rate,
        'p_final_amount': _billAmount > 0 ? _billAmount : null,
        'p_approved_by': ref.read(appUserProvider).valueOrNull?.userId,
        'p_approval_notes':
        _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'p_invoice_date': _invoiceDate.toIso8601String().split('T')[0],
        if (itemRates != null) 'p_item_rates': itemRates,
      });
      if (mounted) {
        showSuccess(context, 'Approved! Bill created ✓');
        context.go(R.approvals);
      }
    } catch (e) {
      if (mounted) showError(context, _cleanPgError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // Strips Postgres/PostgREST wrapper noise so the trader sees just the
  // RAISE EXCEPTION message (e.g. "Cannot approve: this delivery was
  // undone...") instead of the full "PostgrestException(message: ..., code:
  // P0001, details: Bad Request, hint: null)" wrapper.
  String _cleanPgError(Object e) {
    var s = e.toString().replaceAll('Exception: ', '');
    final match = RegExp(r'PostgrestException\(message:\s*(.*?),\s*code:').firstMatch(s);
    if (match != null) return match.group(1)!.trim();
    return s.replaceAll('PostgrestException(message: ', '');
  }

  Future<void> _reject() async {
    if (_rejectCtrl.text.trim().isEmpty) {
      showError(context, 'Enter rejection reason');
      return;
    }
    final ok = await confirmDialog(context,
        title: 'Reject', message: 'Reject this delivery?');
    if (!ok) return;
    if (mounted) setState(() => _submitting = true);
    try {
      await _c.from('deliveries').update({
        'approval_status': 'rejected',
        'rejection_reason': _rejectCtrl.text.trim(),
        'rejected_by': ref.read(appUserProvider).valueOrNull?.userId,
        'rejected_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.id);
      if (mounted) {
        showSuccess(context, 'Rejected');
        context.go(R.approvals);
      }
    } catch (e) {
      if (mounted) showError(context, e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FLAG ISSUE (replaces Reject for structured issue reporting)
  // Delivery stays in pending state but is tagged for review.
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _flagIssue() async {
    if (_flagCategory == null) {
      showError(context, 'Select an issue category');
      return;
    }
    final ok = await confirmDialog(context,
        title: 'Flag Issue',
        message: 'Flag this delivery for review? '
            'It will remain pending until the issue is resolved.');
    if (!ok || !mounted) return;
    if (mounted) setState(() => _submitting = true);
    try {
      final userId = ref.read(appUserProvider).valueOrNull?.userId;
      await _c.from('deliveries').update({
        'flag_category':   _flagCategory,
        'flag_notes':      _flagNotesCtrl.text.trim().isEmpty
            ? null : _flagNotesCtrl.text.trim(),
        'flagged_by':      userId,
        'flagged_at':      DateTime.now().toIso8601String(),
        'approval_status': 'flagged',
      }).eq('id', widget.id);
      if (mounted) {
        showSuccess(context, 'Issue flagged — delivery held for review');
        context.go(R.approvals);
      }
    } catch (e) {
      if (mounted) showError(context, e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(backgroundColor: kBgPage, body: LoadingList());
    }
    if (_delivery == null) {
      return Scaffold(
          backgroundColor: kBgPage,
          appBar: AppBar(backgroundColor: kSurface),
          body: const Center(child: Text('Not found')));
    }

    // ★ NEW: this delivery was undone (Undo Delivery) — its stock and cash
    // effects were already reversed, so it must never be approvable. This
    // is checked BEFORE any billing UI renders, not just at submit time —
    // the backend guard in approve_delivery_and_order still exists too
    // (defense in depth), but a trader should never get as far as entering
    // rates for something that can't actually be approved.
    if (_delivery!['is_undone'] == true) {
      return Scaffold(
        backgroundColor: kBgPage,
        appBar: AppBar(
          backgroundColor: kSurface,
          title: const Text('Approve Delivery'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.replay_circle_filled_outlined,
                    size: 48, color: Colors.orange.shade700),
                const SizedBox(height: 16),
                const Text('This Delivery Was Undone',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  'Its stock and cash effects have already been reversed, '
                  'so it cannot be approved.'
                  '${_delivery!['undo_reason'] != null ? '\n\nReason: ${_delivery!['undo_reason']}' : ''}',
                  style: const TextStyle(fontSize: 13, color: kTextSub, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: () => context.go(R.approvals),
                  child: const Text('Back to Approvals'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final o = _delivery!['orders'] as Map<String, dynamic>?;
    final r = o?['retailers'] as Map<String, dynamic>?;
    final a = _delivery!['delivery_agents'] as Map<String, dynamic>?;
    final batch = _delivery!['delivery_batches'] as Map<String, dynamic>?;
    final challans = (batch?['delivery_challans'] as List? ?? [])
        .cast<Map<String, dynamic>>();

    final isDesktop = context.isDesktop;
    final appBar = AppBar(
      backgroundColor: kSurface,
      title: const Text('Approve Delivery'),
      actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
    );

    // ══ REDESIGNED SECTION FLOW ══════════════════════════════════════════
    //  Goal: trader approves within 5 seconds
    //  Order: Customer → Delivery Summary → BLE (collapsed) → Mortality → Billing → Approve → Flag
    final allSections = <Widget>[

      // ── 1. CUSTOMER HEADER (compact + View DC link) ─────────────────
      WhiteCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r?['shop_name'] as String? ?? '—',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                if (r?['owner_name'] != null)
                  Text(r!['owner_name'] as String,
                      style: const TextStyle(fontSize: 13, color: kTextSub)),
                if (r?['phone'] != null)
                  Text(r!['phone'] as String,
                      style: const TextStyle(fontSize: 12, color: kTextHint)),
              ])),
              // View DC Details link — replaces the full DC card in main flow
              if (challans.isNotEmpty)
                GestureDetector(
                  onTap: () => _showDCSheet(context, challans),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.receipt_long_outlined, size: 13, color: Colors.blue),
                      SizedBox(width: 4),
                      Text('View DC', style: TextStyle(fontSize: 11,
                          fontWeight: FontWeight.w700, color: Colors.blue)),
                    ]),
                  ),
                ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.delivery_dining, size: 14, color: kPrimary),
              const SizedBox(width: 6),
              Text('${a?['name'] ?? '—'}  ·  ${a?['vehicle_no'] ?? ''}',
                  style: const TextStyle(fontSize: 12, color: kTextSub)),
              if (_delivery!['delivered_at'] != null) ...[
                const SizedBox(width: 10),
                const Icon(Icons.access_time, size: 13, color: kTextHint),
                const SizedBox(width: 4),
                Text(DateFormat('d MMM, hh:mm a').format(
                    DateTime.parse(_delivery!['delivered_at'] as String).toLocal()),
                    style: const TextStyle(fontSize: 12, color: kTextHint)),
              ],
            ]),
          ])),
      const SizedBox(height: 10),

      // ── 2. DELIVERY SUMMARY — Ordered / Delivered / Variance ────────
      _buildDeliverySummary(o),
      const SizedBox(height: 10),

      // ── 3. BLE SCALE LOG — collapsed by default ──────────────────────
      _buildBleCollapsible(challans),
      const SizedBox(height: 10),

      // ── 4. MORTALITY & PROOF IMAGES ──────────────────────────────────
      _buildPhotos(),

      // ── Rate & Bill ───────────────────────────────────────────
      WhiteCard(
          child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionHeader('BILLING'),
            // Weight source label
            Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: _weighNetTotal > 0
                        ? Colors.blue.shade50
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  Icon(_weighNetTotal > 0 ? Icons.scale : Icons.edit_outlined,
                      size: 14,
                      color: _weighNetTotal > 0 ? Colors.blue : Colors.orange),
                  const SizedBox(width: 6),
                  Text(
                      _weighNetTotal > 0
                          ? 'Using BLE row sum: ${_billingWeight.toStringAsFixed(2)} kg'
                          '${_bleDiscrepancy ? "  ⚠ Session showed ${_weighSessionNetTotal.toStringAsFixed(1)} kg" : ""}'
                          : 'Using agent entry: ${_billingWeight.toStringAsFixed(2)} kg (no scale data)',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _weighNetTotal > 0 ? Colors.blue : Colors.orange)),
                ])),

            // ── Phase 3: Auto-resolved rate preview from pricing engine ──────
            if (_ratePreview.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: kNavy.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(color: kNavy.withValues(alpha: 0.12)),
                ),
                child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Icon(Icons.auto_fix_high_rounded, size: 14, color: kNavy),
                    SizedBox(width: 6),
                    Text('AUTO-RESOLVED RATES',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: kNavy,
                            letterSpacing: 0.6)),
                    Spacer(),
                    Text('Editable below',
                        style: TextStyle(fontSize: 10, color: kTextHint)),
                  ]),
                  const SizedBox(height: 8),
                  ..._ratePreview.map((p) {
                    final label = p['rate_label'] as String? ?? '';
                    final prodName = p['product_name'] as String? ?? '—';
                    final rate = (p['rate'] as num?)?.toDouble() ?? 0;
                    final lineTotal = (p['line_total'] as num?)?.toDouble() ?? 0;
                    final source = p['rate_source'] as String? ?? '';
                    final sourceColor = switch (source) {
                      'fixed_customer' || 'contract' => const Color(0xFF7C3AED),
                      'customer_adjustment' => const Color(0xFF059669),
                      'zone_rate' => kNavy,
                      _ => kTextSub,
                    };
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(children: [
                        Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                                color: sourceColor, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(prodName,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: kNavy)),
                                  Text(label,
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: sourceColor,
                                          fontWeight: FontWeight.w500)),
                                ])),
                        Text('${Fmt.amount(rate)}/kg',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: kNavy)),
                        const SizedBox(width: 8),
                        Text(Fmt.amount(lineTotal),
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: kTextSub)),
                      ]),
                    );
                  }),
                ]),
              ),
            ],

            // ── Per-product rates (multi-product) OR single rate ──────────
            if (_isMultiProduct) ...[
              const Text('RATE PER PRODUCT',
                  style: TextStyle(
                      fontSize: 11,
                      color: kTextHint,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8)),
              const SizedBox(height: 8),
              ..._orderItems.map((item) {
                final id = item['id'] as String? ?? '';
                final prodName =
                    (item['master_products'] as Map?)?['name'] as String? ??
                        'Product';
                final weight = (item['total_weight'] as num?)?.toDouble() ?? 0;
                final birds = (item['bird_count'] as num?)?.toInt() ?? 0;
                final ctrl = _itemRateCtrls[id] ?? TextEditingController();
                final rate = double.tryParse(ctrl.text.trim()) ?? 0;
                final lineTotal = weight * rate;
                return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FA),
                        borderRadius: BorderRadius.circular(kRadiusCard),
                        border: Border.all(color: kBorder)),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                    color: kPrimary, shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(prodName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14))),
                            Text('${weight.toStringAsFixed(1)} kg · $birds birds',
                                style:
                                const TextStyle(fontSize: 11, color: kTextSub)),
                          ]),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(
                                child: TextField(
                                    controller: ctrl,
                                    keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                    decoration: InputDecoration(
                                        labelText: 'Rate/kg *',
                                        prefixText: '₹',
                                        suffixText: '/kg',
                                        filled: true,
                                        fillColor: Colors.white,
                                        border: OutlineInputBorder(
                                            borderRadius:
                                            BorderRadius.circular(kRadiusInner),
                                            borderSide: BorderSide.none)),
                                    onChanged: (_) => setState(() {}))),
                            const SizedBox(width: 12),
                            if (rate > 0)
                              Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(Fmt.amount(lineTotal),
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w900,
                                            color: kPrimary)),
                                    Text(
                                        '${weight.toStringAsFixed(1)} × ₹${rate.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                            fontSize: 10, color: kTextSub)),
                                  ]),
                          ]),
                        ]));
              }),
            ] else ...[
              const Text('Rate per kg *',
                  style: TextStyle(
                      fontSize: 11, color: kTextHint, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              TextField(
                  controller: _rateCtrl,
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      prefixText: '₹',
                      suffixText: '/kg',
                      filled: true,
                      fillColor: const Color(0xFFF3F4F6),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(kRadiusCard),
                          borderSide: BorderSide.none)),
                  onChanged: (_) => setState(() {})),
            ],
            const SizedBox(height: 12),

            // Live calculation summary
            if (_billAmount > 0)
              Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: kPrimary.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(kRadiusCard),
                      border: Border.all(color: kPrimary.withValues(alpha: 0.2))),
                  child: Column(children: [
                    if (_isMultiProduct) ...[
                      ..._orderItems.map((item) {
                        final id = item['id'] as String? ?? '';
                        final prodName =
                            (item['master_products'] as Map?)?['name'] as String? ??
                                '—';
                        final weight =
                            (item['total_weight'] as num?)?.toDouble() ?? 0;
                        final rate = double.tryParse(
                            _itemRateCtrls[id]?.text.trim() ?? '') ??
                            0;
                        if (rate <= 0) return const SizedBox.shrink();
                        return _bRow(prodName, Fmt.amount(weight * rate), kTextSub);
                      }),
                      const Divider(height: 10),
                    ] else ...[
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                                '${_billingWeight.toStringAsFixed(2)} kg × ₹${_rateCtrl.text}/kg',
                                style:
                                const TextStyle(fontSize: 12, color: kTextSub)),
                            const SizedBox.shrink(),
                          ]),
                    ],
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total Bill',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 14)),
                          Text(Fmt.amount(_billAmount),
                              style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  color: kPrimary)),
                        ]),
                    if (_collected > 0) ...[
                      const Divider(height: 14),
                      _bRow('Collected by agent', Fmt.amount(_collected),
                          Colors.green),
                      _bRow('Balance due', Fmt.amount(_balance),
                          _balance > 0 ? Colors.orange : Colors.green),
                    ],
                  ])),
            const SizedBox(height: 12),

            // Invoice date
            const Text('Invoice Date',
                style: TextStyle(
                    fontSize: 11, color: kTextHint, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                      context: context,
                      initialDate: _invoiceDate,
                      firstDate: DateTime.now().subtract(const Duration(days: 90)),
                      lastDate: DateTime.now());
                  if (d != null && mounted) {
                    setState(() => _invoiceDate = d);
                    // Re-resolve rates for the new date — see
                    // _refreshRatePreview for why this matters.
                    await _refreshRatePreview();
                  }
                },
                child: Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [
                      const Icon(Icons.calendar_today_outlined,
                          size: 16, color: kPrimary),
                      const SizedBox(width: 10),
                      Text(DateFormat('d MMMM y').format(_invoiceDate),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      const Text('Change',
                          style: TextStyle(
                              fontSize: 12,
                              color: kPrimary,
                              fontWeight: FontWeight.w600)),
                    ]))),
            const SizedBox(height: 10),
            TextField(
                controller: _notesCtrl,
                decoration: const InputDecoration(labelText: 'Notes (optional)')),
          ])),
      const SizedBox(height: 16),

      // ── Approve button ─────────────────────────────────────────
      SizedBox(
          height: 52,
          child: ElevatedButton.icon(
              onPressed: _submitting ? null : _approve,
              icon: _submitting
                  ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_circle_outline, size: 20),
              label: const Text('Approve & Create Bill',
                  style:
                  TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))),
      const SizedBox(height: 12),

      // ── Flag Issue (replaces Reject) ─────────────────────────────────
      _buildFlagIssueSection(),
      const SizedBox(height: 20),
    ];

    if (!isDesktop) {
      return Scaffold(
        backgroundColor: kBgPage,
        appBar: appBar,
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: allSections,
        ),
      );
    }

    // ── Desktop 2-column layout ──────────────────────────────────────────
    // Left: delivery info + loss + weighment + DCs + photos
    // Right: rate entry + approve/reject (always last 2 sections)
    final splitIdx = allSections.length > 2 ? allSections.length - 2 : 0;
    final leftSections = allSections.sublist(0, splitIdx);
    final rightSections = allSections.sublist(splitIdx);

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: appBar,
      body: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Left: delivery details + loss + weighment ──────────────────
        Expanded(
          flex: 6,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 16, 40),
            children: leftSections,
          ),
        ),
        Container(width: 1, color: kBorderLight),
        // ── Right: rate + approve/reject ───────────────────────────────
        SizedBox(
          width: 360,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 24, 40),
            children: rightSections,
          ),
        ),
      ]),
    );
  }

  // ── ORDER-LEVEL LOSS CARD ────────────────────────────────────────
  Widget _buildLossCard(Map<String, dynamic>? o) {
    final dcWt = _dcWeightForLoss;
    final expectedBirds = _orderExpectedBirds;
    final deliveredWt = _billingWeight;
    final deliveredBirds =
        (_delivery?['delivered_bird_count'] as num?)?.toInt() ?? 0;

    // U5 FIX: when dc_weight_kg = 0 (DC not yet recorded or old delivery),
    // show an informational label rather than a misleading "0.0% loss".
    // Loss calculation is meaningless without DC weight as the base.
    final bool dcAvailable = dcWt > 0;

    return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: !dcAvailable
                ? Colors.grey.shade50
                : (_isHighLoss ? Colors.red.shade50 : Colors.green.shade50),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: !dcAvailable
                    ? Colors.grey.shade300
                    : (_isHighLoss
                    ? Colors.red.shade300
                    : Colors.green.shade300),
                width: 1.5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(
                !dcAvailable
                    ? Icons.info_outline
                    : (_isHighLoss
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_outline),
                color: !dcAvailable
                    ? kTextSub
                    : (_isHighLoss ? Colors.red : Colors.green),
                size: 18),
            const SizedBox(width: 6),
            Expanded(
                child: Text(
                    !dcAvailable
                        ? 'DC weight not recorded — loss cannot be computed'
                        : (_isHighLoss
                        ? '⚠️ Weight Variance — ${_lossPct.toStringAsFixed(1)}% vs DC (preliminary)'
                        : 'Weight Variance: ${_lossPct.toStringAsFixed(1)}% vs DC'),
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: !dcAvailable
                            ? kTextSub
                            : (_isHighLoss
                            ? Colors.red
                            : Colors.green.shade700)))),
            if (dcAvailable)
              Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6)),
                  child: Text('DC WEIGHT BASIS',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: _isHighLoss ? Colors.red : Colors.green))),
          ]),
          // U5: show "DC not recorded" advisory when no DC weight
          if (!dcAvailable) ...[
            const SizedBox(height: 8),
            Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8)),
                child: const Row(children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: 14),
                  SizedBox(width: 8),
                  Expanded(
                      child: Text(
                          'No DC challan was recorded for this batch, or the delivery '
                              'was completed before DC tracking was enabled. '
                              'The authoritative loss will be computed when the shift is approved.',
                          style: TextStyle(fontSize: 11, color: Colors.blue))),
                ])),
          ],
          const SizedBox(height: 12),
          Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(8)),
              child: Column(children: [
                _lossRow('Weight', dcWt, deliveredWt, 'kg', isHeader: true),
                const Divider(height: 10),
                _lossRow('Birds', expectedBirds.toDouble(),
                    deliveredBirds.toDouble(), 'birds'),
              ])),
          const SizedBox(height: 10),
          Row(children: [
            _lossChip('vs Order Expected',
                '${_transportLoss.toStringAsFixed(2)} kg',
                Colors.orange),
            const SizedBox(width: 8),
            _lossChip(
                'Mortality',
                '$_mortalityBirds birds\n${_mortalityWt.toStringAsFixed(2)} kg',
                Colors.red),
            const SizedBox(width: 8),
            _lossChip('Vs DC (Prelim)',
                '${_totalLoss.toStringAsFixed(2)} kg',
                _isHighLoss ? Colors.red : Colors.orange),
          ]),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline, size: 12, color: Colors.blue),
              SizedBox(width: 6),
              Expanded(child: Text(
                  'Preliminary only. Actual loss (including live returns, return mortality, '
                      'weight variance) is calculated when the shift is approved.',
                  style: TextStyle(fontSize: 10, color: Colors.blue))),
            ]),
          ),
          if (_delivery?['delivery_notes'] != null) ...[
            const SizedBox(height: 8),
            Text('Agent notes: ${_delivery!['delivery_notes']}',
                style: const TextStyle(
                    fontSize: 11,
                    color: kTextSub,
                    fontStyle: FontStyle.italic)),
          ],
        ]));
  }

  Widget _lossRow(String label, double expected, double actual, String unit,
      {bool isHeader = false}) {
    final diff = actual - expected;
    return Row(children: [
      SizedBox(
          width: 60,
          child: Text(label,
              style: TextStyle(
                  fontSize: isHeader ? 11 : 11,
                  color: kTextHint,
                  fontWeight: FontWeight.w600))),
      Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
                'Expected: ${isHeader ? expected.toStringAsFixed(1) : expected.toStringAsFixed(0)} $unit',
                style: const TextStyle(fontSize: 11, color: kTextSub)),
          ])),
      const SizedBox(width: 8),
      Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
                'Delivered: ${isHeader ? actual.toStringAsFixed(1) : actual.toStringAsFixed(0)} $unit',
                style: const TextStyle(fontSize: 11, color: kTextMain)),
          ])),
      const SizedBox(width: 8),
      SizedBox(
          width: 70,
          child: Text(
              '${diff >= 0 ? '+' : ''}${isHeader ? diff.toStringAsFixed(1) : diff.toStringAsFixed(0)} $unit',
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: diff < 0 ? Colors.red : Colors.green))),
    ]);
  }

  Widget _lossChip(String label, String value, Color c) => Expanded(
      child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: c.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8)),
          child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(
                    fontSize: 9, color: c, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(
                    fontSize: 11, color: c, fontWeight: FontWeight.w800)),
          ])));

  // ── WEIGHMENT LOG TABLE ───────────────────────────────────────────
  Widget _buildWeighmentLog(List<Map<String, dynamic>> challans) {
    final ws = _weighSession!;
    final rows = _weighRows;
    final totLoad = (ws['total_load_wt'] as num?)?.toDouble() ?? 0;
    final totEmpty = (ws['total_empty_wt'] as num?)?.toDouble() ?? 0;
    final totNet = (ws['total_net_wt'] as num?)?.toDouble() ?? 0;
    final avgWt = (ws['avg_bird_wt'] as num?)?.toDouble() ?? 0;
    final totBirds = (ws['total_birds'] as num?)?.toInt() ?? 0;
    final cages = (ws['total_cages'] as num?)?.toInt() ?? 0;

    return Container(
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.blue.shade200, width: 1.5)),
        child: Column(children: [
          // Header
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                  color: Colors.blue.shade700,
                  borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(13))),
              child: Row(children: [
                const Icon(Icons.scale, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                    child: Text('BLE Scale Weighment Log',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14))),
                Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text('${rows.length} readings',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600))),
              ])),

          // Summary row
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.blue.shade50,
              child: Row(children: [
                _wStat('Total Gross', '${totLoad.toStringAsFixed(1)} kg',
                    Colors.blue),
                _wStat('Total Empty', '${totEmpty.toStringAsFixed(1)} kg',
                    Colors.grey),
                _wStat('Net Weight', '${totNet.toStringAsFixed(1)} kg',
                    Colors.blue.shade700),
                _wStat('Birds', '$totBirds', kPrimary),
                _wStat('Avg/bird', '${(avgWt * 1000).toStringAsFixed(0)}g',
                    Colors.teal),
                _wStat('Cages', '$cages', kTextSub),
              ])),

          // ── Scale reading note (only when row sum ≠ session summary) ──────
          // This can appear when the weighment was saved mid-session before
          // all crate empty-weights were recorded. The DB trigger now keeps
          // these in sync automatically; this is shown only as an audit trail.
          if (_bleDiscrepancy) ...[
            Container(
              margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: 14),
                  SizedBox(width: 6),
                  Text('SCALE LOG NOTE',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900,
                          color: Colors.blue, letterSpacing: 0.4)),
                ]),
                const SizedBox(height: 6),
                Text('Individual readings sum: ${_weighRowNetTotal.toStringAsFixed(2)} kg  '
                    '·  Session total: ${_weighSessionNetTotal.toStringAsFixed(2)} kg',
                    style: const TextStyle(fontSize: 11, color: Colors.blue,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                const Text(
                    'Billing uses the individual readings sum (more precise).',
                    style: TextStyle(fontSize: 10, color: kTextSub)),
              ]),
            ),
          ],

          // Row-by-row table header
          if (rows.isNotEmpty) ...[
            Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(children: [
                  _tHead('#', 32),
                  _tHead('Time', 50),
                  _tHead('Load Wt', 70),
                  _tHead('Empty Wt', 70),
                  _tHead('Net Wt', 70),
                  _tHead('Cages', 50),
                  _tHead('Avg Wt', 56),
                ])),
            const Divider(height: 8),
            ...rows.map((row) {
              final loadWt = (row['load_wt'] as num?)?.toDouble() ?? 0;
              final emptyWt = (row['empty_wt'] as num?)?.toDouble() ?? 0;
              final netWt = (row['net_wt'] as num?)?.toDouble() ?? 0;
              final avgW = (row['avg_wt'] as num?)?.toDouble() ?? 0;
              final cageL = (row['load_cages'] as num?)?.toInt() ?? 0;
              final seq = (row['seq_no'] as num?)?.toInt() ?? 0;
              final time = row['entry_time'] as String? ?? '—';
              return Container(
                  padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
                  decoration: BoxDecoration(
                      color:
                      seq.isOdd ? const Color(0xFFF8F9FC) : Colors.white),
                  child: Row(children: [
                    _tCell('$seq', 32, kTextHint),
                    _tCell(time, 50, kTextSub),
                    _tCell('${loadWt.toStringAsFixed(2)} kg', 70, kTextMain),
                    _tCell('${emptyWt.toStringAsFixed(2)} kg', 70, kTextSub),
                    _tCell('${netWt.toStringAsFixed(2)} kg', 70,
                        netWt > 0 ? Colors.green.shade700 : Colors.orange),
                    _tCell('$cageL', 50, kTextSub),
                    _tCell('${(avgW * 1000).toStringAsFixed(0)}g', 56,
                        Colors.teal),
                  ]));
            }),
            Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(children: [
                  _tHead('TOTAL', 82),
                  _tHead('', 50),
                  _tHead('${totLoad.toStringAsFixed(2)} kg', 70, isTotal: true),
                  _tHead('${totEmpty.toStringAsFixed(2)} kg', 70),
                  _tHead('${totNet.toStringAsFixed(2)} kg', 70,
                      isTotal: true, color: Colors.blue.shade700),
                  _tHead('', 50),
                  _tHead('', 56),
                ])),
          ] else
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No individual weighment rows found.',
                    style: TextStyle(fontSize: 12, color: kTextHint))),
        ]));
  }

  Widget _tHead(String label, double w, {bool isTotal = false, Color? color}) =>
      SizedBox(
          width: w,
          child: Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600,
                  color: color ?? (isTotal ? kTextMain : kTextHint))));

  Widget _tCell(String v, double w, Color c) => SizedBox(
      width: w,
      child: Text(v,
          style:
          TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600)));

  Widget _wStat(String l, String v, Color c) => Expanded(
      child: Column(children: [
        Text(v,
            style:
            TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c),
            textAlign: TextAlign.center),
        Text(l,
            style: const TextStyle(fontSize: 9, color: kTextHint),
            textAlign: TextAlign.center),
      ]));

  // ── DC / FARM PICKUP DETAILS ──────────────────────────────────────
  Widget _buildDCDetails(List<Map<String, dynamic>> challans) => Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
                color: Colors.green.shade700,
                borderRadius:
                const BorderRadius.vertical(top: Radius.circular(11))),
            child: Row(children: [
              const Icon(Icons.agriculture, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text(
                  'Farm Pickup — ${challans.length} DC${challans.length > 1 ? 's' : ''}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13)),
            ])),
        ...challans.asMap().entries.map((e) {
          final i = e.key;
          final ch = e.value;
          final gross = (ch['gross_weight'] as num?)?.toDouble() ?? 0;
          final empty = (ch['empty_crate_weight'] as num?)?.toDouble() ?? 0;
          final net = (ch['net_weight'] as num?)?.toDouble() ?? 0;
          final birds = (ch['bird_count'] as num?)?.toInt() ?? 0;
          final rate = (ch['farm_rate'] as num?)?.toDouble();
          return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  border: i < challans.length - 1
                      ? const Border(bottom: BorderSide(color: kBorder))
                      : null),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text('DC ${ch['dc_number'] ?? '—'}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(width: 8),
                      Text(ch['dc_date']?.toString() ?? '',
                          style:
                          const TextStyle(fontSize: 11, color: kTextHint)),
                    ]),
                    const SizedBox(height: 6),
                    Text(
                        '${ch['farmer_name'] ?? '—'}  ·  ${ch['farm_location'] ?? ''}',
                        style: const TextStyle(fontSize: 12, color: kTextSub)),
                    const SizedBox(height: 6),
                    Row(children: [
                      _dStat('Gross', '${gross.toStringAsFixed(1)} kg',
                          Colors.blue),
                      _dStat('Empty', '${empty.toStringAsFixed(1)} kg',
                          Colors.grey),
                      _dStat(
                          'Net', '${net.toStringAsFixed(1)} kg', Colors.green),
                      _dStat('Birds', '$birds', kPrimary),
                      if (rate != null)
                        _dStat('Rate', '₹${rate.toStringAsFixed(0)}/kg',
                            Colors.orange),
                    ]),
                    if (ch['vehicle_number'] != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('Vehicle: ${ch['vehicle_number']}',
                              style: const TextStyle(
                                  fontSize: 11, color: kTextHint))),
                    if (ch['dc_photo_url'] != null)
                      const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Row(children: [
                            Icon(Icons.photo_outlined,
                                size: 13, color: Colors.blue),
                            SizedBox(width: 4),
                            Text('DC photo attached',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.blue)),
                          ])),
                  ]));
        }),
        // DC totals
        Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
                color: Color(0xFFF0FAF0),
                borderRadius:
                BorderRadius.vertical(bottom: Radius.circular(11))),
            child: Row(children: [
              const Icon(Icons.summarize_outlined,
                  size: 14, color: Colors.green),
              const SizedBox(width: 6),
              Text(
                  'Total DC: '
                      '${challans.fold(0, (s, c) => s + ((c['bird_count'] as num?)?.toInt() ?? 0))} birds · '
                      '${challans.fold(0.0, (s, c) => s + ((c['net_weight'] as num?)?.toDouble() ?? 0)).toStringAsFixed(1)} kg',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.green,
                      fontWeight: FontWeight.w700)),
            ])),
      ]));

  // ── MORTALITY & PROOF IMAGES ──────────────────────────────────────
  Widget _buildPhotos() {
    final mortUrl = _delivery!['mortality_proof_url'] as String?;
    final delivUrl = _delivery!['delivery_photo_url'] as String?;
    final hasAnyPhoto = mortUrl != null || delivUrl != null;

    return Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: _mortalityBirds > 0 ? Colors.red.shade300 : kBorder,
                width: _mortalityBirds > 0 ? 1.5 : 1)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                  color: _mortalityBirds > 0
                      ? Colors.red.shade50
                      : Colors.grey.shade50,
                  borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(13))),
              child: Row(children: [
                Icon(
                    _mortalityBirds > 0
                        ? Icons.warning_amber_rounded
                        : Icons.photo_library_outlined,
                    color: _mortalityBirds > 0 ? Colors.red : kTextHint,
                    size: 18),
                const SizedBox(width: 8),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Mortality & Proof Images',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 13)),
                          if (_mortalityBirds > 0)
                            Text(
                                '$_mortalityBirds dead birds  |  ${_mortalityWt.toStringAsFixed(2)} kg',
                                style:
                                const TextStyle(fontSize: 11, color: kTextSub)),
                        ])),
                if (_mortalityBirds > 0)
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(6)),
                      child: const Text('VERIFY',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800))),
              ])),
          Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                // Mortality proof image
                if (mortUrl != null) ...[
                  _imageCard('Mortality Proof Photo', mortUrl, Colors.red,
                      Icons.warning_amber_rounded),
                  if (delivUrl != null) const SizedBox(height: 10),
                ] else if (_mortalityBirds > 0) ...[
                  Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(kRadiusCard),
                          border: Border.all(color: Colors.orange.shade300)),
                      child: const Row(children: [
                        Icon(Icons.photo_camera_outlined,
                            color: Colors.orange, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                            child: Text(
                                'No mortality photo uploaded. Verify with agent before approving.',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange,
                                    fontWeight: FontWeight.w600))),
                      ])),
                  const SizedBox(height: 10),
                ] else if (!hasAnyPhoto) ...[
                  Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(kRadiusCard),
                          border: Border.all(color: Colors.green.shade200)),
                      child: const Row(children: [
                        Icon(Icons.check_circle_outline,
                            color: Colors.green, size: 18),
                        SizedBox(width: 8),
                        Text('No mortality reported for this delivery.',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.green,
                                fontWeight: FontWeight.w600)),
                      ])),
                ],
                // Delivery proof image
                if (delivUrl != null) ...[
                  if (mortUrl != null || _mortalityBirds > 0)
                    const SizedBox(height: 10),
                  _imageCard('Delivery Proof Photo', delivUrl, Colors.blue,
                      Icons.local_shipping_outlined),
                ],
              ])),
        ]));
  }

  Widget _imageCard(String label, String url, Color c, IconData icon) {
    return GestureDetector(
        onTap: () => _showFullImage(context, url, label),
        child: Container(
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(kRadiusCard),
                border: Border.all(color: c.withValues(alpha: 0.3))),
            child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      color: c.withValues(alpha: 0.08),
                      borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(9))),
                  child: Row(children: [
                    Icon(icon, size: 14, color: c),
                    const SizedBox(width: 6),
                    Text(label,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: c)),
                    const Spacer(),
                    Icon(Icons.open_in_full,
                        size: 13, color: c.withValues(alpha: 0.6)),
                    const SizedBox(width: 4),
                    Text('Tap to expand',
                        style: TextStyle(
                            fontSize: 10, color: c.withValues(alpha: 0.6))),
                  ])),
              ClipRRect(
                  borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(9)),
                  child: Image.network(
                    url,
                    width: double.infinity,
                    height: 200,
                    fit: BoxFit.cover,
                    loadingBuilder: (ctx, child, prog) => prog == null
                        ? child
                        : Container(
                        height: 200,
                        color: c.withValues(alpha: 0.05),
                        child: Center(
                            child: CircularProgressIndicator(
                                value: prog.expectedTotalBytes != null
                                    ? prog.cumulativeBytesLoaded /
                                    prog.expectedTotalBytes!
                                    : null,
                                color: c,
                                strokeWidth: 2))),
                    errorBuilder: (_, __, ___) => Container(
                        height: 120,
                        color: c.withValues(alpha: 0.05),
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.broken_image_outlined,
                                  size: 36, color: c.withValues(alpha: 0.4)),
                              const SizedBox(height: 6),
                              Text('Failed to load image',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: c.withValues(alpha: 0.6))),
                            ])),
                  )),
            ])));
  }

  void _showFullImage(BuildContext context, String url, String title) {
    showDialog(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => Dialog(
            backgroundColor: Colors.black,
            insetPadding: EdgeInsets.zero,
            child: Stack(children: [
              InteractiveViewer(
                  child: Center(
                      child: Image.network(url,
                          fit: BoxFit.contain,
                          loadingBuilder: (_, child, prog) => prog == null
                              ? child
                              : const Center(
                              child: CircularProgressIndicator(
                                  color: Colors.white)),
                          errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.broken_image,
                                  color: Colors.white, size: 64))))),
              Positioned(
                  top: 16,
                  left: 16,
                  child: Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          shadows: [
                            Shadow(color: Colors.black54, blurRadius: 4)
                          ]))),
              Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                      icon: const Icon(Icons.close,
                          color: Colors.white, size: 28),
                      onPressed: () =>
                          Navigator.of(ctx, rootNavigator: true).pop())),
            ])));
  }

  Widget _bRow(String l, String v, Color c) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(l, style: const TextStyle(fontSize: 12, color: kTextSub)),
        Text(v,
            style:
            TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c)),
      ]));

  Widget _dStat(String l, String v, Color c) => Expanded(
      child: Column(children: [
        Text(v,
            style:
            TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c),
            textAlign: TextAlign.center),
        Text(l,
            style: const TextStyle(fontSize: 9, color: kTextHint),
            textAlign: TextAlign.center),
      ]));

  // ═══════════════════════════════════════════════════════════════════════════
  // NEW WIDGET 1 — DELIVERY SUMMARY (Ordered / Delivered / Variance)
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildDeliverySummary(Map<String, dynamic>? o) {
    final orderedWt   = _orderExpectedWt;
    final deliveredWt = _billingWeight;
    final variance    = deliveredWt - orderedWt;
    final shortagePct = orderedWt > 0
        ? ((orderedWt - deliveredWt) / orderedWt * 100).clamp(0.0, 100.0)
        : 0.0;

    final Color varColor;
    final String varLabel;
    final IconData varIcon;

    if (variance >= 0) {
      varColor = Colors.green;
      varLabel  = orderedWt > 0 ? '+${variance.toStringAsFixed(1)} kg' : 'Delivered';
      varIcon   = Icons.check_circle_outline;
    } else if (shortagePct <= 3) {
      varColor = Colors.orange;
      varLabel  = '−${variance.abs().toStringAsFixed(1)} kg  (${shortagePct.toStringAsFixed(1)}%)';
      varIcon   = Icons.warning_amber_outlined;
    } else {
      varColor = Colors.red;
      varLabel  = '−${variance.abs().toStringAsFixed(1)} kg  (${shortagePct.toStringAsFixed(1)}%)';
      varIcon   = Icons.cancel_outlined;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: varColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(kRadiusCard),
          border: Border.all(color: varColor.withValues(alpha: 0.3), width: 1.5)),
      child: Column(children: [
        // ── Three-column header ─────────────────────────────────
        Row(children: [
          Expanded(child: _summaryCol('ORDERED', kTextSub)),
          Expanded(child: _summaryCol('DELIVERED', kTextSub)),
          Expanded(child: _summaryCol('VARIANCE', varColor)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _summaryVal(
              orderedWt > 0 ? '${orderedWt.toStringAsFixed(1)} kg' : '— kg',
              kTextMain)),
          Expanded(child: _summaryVal('${deliveredWt.toStringAsFixed(1)} kg', kTextMain)),
          Expanded(child: _summaryVal(varLabel, varColor)),
        ]),
        const SizedBox(height: 12),
        // ── Visual progress bar ─────────────────────────────────
        if (orderedWt > 0) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (deliveredWt / orderedWt).clamp(0.0, 1.0),
              minHeight: 7,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(varColor),
            ),
          ),
          const SizedBox(height: 8),
        ],
        // ── Variance status chip ────────────────────────────────
        Row(children: [
          Icon(varIcon, size: 14, color: varColor),
          const SizedBox(width: 6),
          Text(
              variance >= 0
                  ? 'Delivered meets or exceeds order'
                  : shortagePct <= 3
                  ? 'Minor shortage — within 3% tolerance'
                  : 'Significant shortage — exceeds 3% threshold',
              style: TextStyle(fontSize: 11, color: varColor, fontWeight: FontWeight.w600)),
        ]),
        // ── BLE mismatch warning — surfaced here, NOT buried in the BLE log ──
        // Shown only when session total differs from row sum by >1%.
        // After the DB trigger fix this should rarely appear; if it does,
        // it means the session was saved before all crate empty-weights were
        // recorded and the auto-sync hasn't run yet.
        if (_bleDiscrepancy) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade300)),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 13, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(child: Text(
                  'Scale reading updated — billing uses ${_weighRowNetTotal.toStringAsFixed(1)} kg '
                      '(from ${_weighRows.length} individual readings). '
                      'Expand the scale log to review.',
                  style: const TextStyle(fontSize: 10, color: Colors.deepOrange,
                      fontWeight: FontWeight.w600))),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _summaryCol(String label, Color c) => Text(label,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
          color: c, letterSpacing: 0.5));

  Widget _summaryVal(String val, Color c) => Text(val,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: c));

  // ═══════════════════════════════════════════════════════════════════════════
  // NEW WIDGET 2 — BLE COLLAPSIBLE (replaces always-expanded BLE log)
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildBleCollapsible(List<Map<String, dynamic>> challans) {
    // Header summary row — always visible
    final rowCount   = _weighRows.length;
    final rowNetSum  = _weighRowNetTotal;
    final sessNet    = _weighSessionNetTotal;
    final totBirds   = (_weighSession?['total_birds'] as num?)?.toInt() ?? 0;

    return Container(
      decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border: Border.all(color: Colors.blue.shade200, width: 1.5)),
      child: Column(children: [
        // ── Always-visible header ─────────────────────────────────────────
        InkWell(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(kRadiusCard - 2)),
          onTap: () => setState(() => _showBleExpanded = !_showBleExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              const Icon(Icons.scale, size: 16, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('BLE Scale Weighment',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                if (_weighSession == null)
                  const Text('No BLE session recorded',
                      style: TextStyle(fontSize: 11, color: kTextHint))
                else
                  Row(children: [
                    _bleSummaryChip('Net', '${rowNetSum.toStringAsFixed(1)} kg', Colors.blue.shade700),
                    const SizedBox(width: 8),
                    _bleSummaryChip('Birds', '$totBirds', kPrimary),
                    const SizedBox(width: 8),
                    _bleSummaryChip('Rows', '$rowCount readings', Colors.teal),
                    if (_bleDiscrepancy) ...[
                      const SizedBox(width: 8),
                      _bleSummaryChip('⚠ Mismatch', '!', Colors.red),
                    ],
                  ]),
              ])),
              Icon(_showBleExpanded ? Icons.expand_less : Icons.expand_more,
                  color: kTextSub, size: 20),
            ]),
          ),
        ),
        // ── Expandable full log ───────────────────────────────────────────
        if (_showBleExpanded && _weighSession != null) ...[
          const Divider(height: 1),
          _buildBleFullLog(),
        ],
      ]),
    );
  }

  Widget _bleSummaryChip(String label, String val, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6)),
      child: Text('$label: $val',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c)));

  // Full BLE details — only rendered when expanded
  Widget _buildBleFullLog() {
    final ws       = _weighSession!;
    final rows     = _weighRows;
    final sessLoad = (ws['total_load_wt'] as num?)?.toDouble() ?? 0;
    final sessEmpty= (ws['total_empty_wt'] as num?)?.toDouble() ?? 0;
    final sessNet  = _weighSessionNetTotal;
    final rowNet   = _weighRowNetTotal;
    final avgWt    = (ws['avg_bird_wt'] as num?)?.toDouble() ?? 0;
    final totBirds = (ws['total_birds'] as num?)?.toInt() ?? 0;
    final cages    = (ws['total_cages'] as num?)?.toInt() ?? 0;

    // ── Formula validation ──
    // 1. Session: net = load - empty
    final sessNetCalc    = sessLoad - sessEmpty;
    final sessNetOk      = (sessNet - sessNetCalc).abs() < 0.1;
    // 2. Row sum vs session net
    final rowSumMatchesSess = (rowNet - sessNet).abs() / (sessNet > 0 ? sessNet : 1) < 0.01;
    // 3. Avg bird weight sanity (broilers: 1000–3000g)
    final avgG           = (avgWt * 1000);
    final avgSane        = avgG >= 800 && avgG <= 3500;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Formula validation summary ────────────────────────────
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kBorder)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('FORMULA AUDIT', style: TextStyle(fontSize: 9,
                fontWeight: FontWeight.w900, color: kTextHint, letterSpacing: 0.6)),
            const SizedBox(height: 6),
            _formulaRow(
                'Session: Net = Load − Empty',
                '${sessLoad.toStringAsFixed(1)} − ${sessEmpty.toStringAsFixed(1)} = ${sessNetCalc.toStringAsFixed(1)} kg (session: ${sessNet.toStringAsFixed(1)})',
                sessNetOk),
            _formulaRow(
                'Row sum vs session net',
                '${rowNet.toStringAsFixed(2)} kg vs ${sessNet.toStringAsFixed(2)} kg',
                rowSumMatchesSess),
            _formulaRow(
                'Avg bird weight (broiler: 1000–3000g)',
                '${avgG.toStringAsFixed(0)}g/bird${avgSane ? "" : " ← SUSPECT — verify bird count"}',
                avgSane),
          ]),
        ),
        const SizedBox(height: 10),

        // ── Individual rows ───────────────────────────────────────
        Row(children: [
          _tHead('#', 28), _tHead('Time', 48),
          _tHead('Load', 68), _tHead('Empty', 68),
          _tHead('Net', 68), _tHead('Cages', 45),
          _tHead('Check', 56),
        ]),
        const Divider(height: 8),
        ...rows.map((row) {
          final loadWt  = (row['load_wt']   as num?)?.toDouble() ?? 0;
          final emptyWt = (row['empty_wt']  as num?)?.toDouble() ?? 0;
          final netWt   = (row['net_wt']    as num?)?.toDouble() ?? 0;
          final cageL   = (row['load_cages'] as num?)?.toInt() ?? 0;
          final seq     = (row['seq_no']    as num?)?.toInt() ?? 0;
          final time    = row['entry_time'] as String? ?? '—';
          // Per-row formula check
          final calcNet = loadWt - emptyWt;
          final rowOk   = (netWt - calcNet).abs() < 0.1;
          return Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              color: seq.isOdd ? const Color(0xFFF8F9FC) : Colors.white,
              child: Row(children: [
                _tCell('$seq', 28, kTextHint),
                _tCell(time, 48, kTextSub),
                _tCell(loadWt.toStringAsFixed(1), 68, kTextMain),
                _tCell(emptyWt.toStringAsFixed(1), 68, kTextSub),
                _tCell(netWt.toStringAsFixed(1), 68, Colors.green.shade700),
                _tCell('$cageL', 45, kTextSub),
                SizedBox(width: 56, child: Icon(
                    rowOk ? Icons.check : Icons.warning_amber,
                    size: 14,
                    color: rowOk ? Colors.green : Colors.red)),
              ]));
        }),
        // ── Footer totals ────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
          decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.blue.shade200))),
          child: Row(children: [
            _tHead('TOTAL', 76),
            _tHead('', 48),
            _tHead('', 68),
            _tHead('', 68),
            _tHead('${rowNet.toStringAsFixed(2)} kg', 68,
                isTotal: true, color: Colors.blue.shade700),
            _tHead('', 45),
            _tHead(rowSumMatchesSess ? '✓' : '⚠', 56,
                isTotal: true, color: rowSumMatchesSess ? Colors.green : Colors.red),
          ]),
        ),
        // ── Row sum vs billing weight ────────────────────────────
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(6)),
          child: Text(
              'Billing weight: ${_billingWeight.toStringAsFixed(2)} kg '
                  '(from ${_weighRows.isNotEmpty ? "row sum" : _agentDeliveredWt > 0 ? "delivery record" : "session total"})',
              style: const TextStyle(fontSize: 10, color: Colors.blue,
                  fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _formulaRow(String label, String detail, bool ok) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(ok ? Icons.check_circle : Icons.error_outline,
            size: 13, color: ok ? Colors.green : Colors.red),
        const SizedBox(width: 6),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
          Text(detail, style: TextStyle(fontSize: 9,
              color: ok ? kTextSub : Colors.red)),
        ])),
      ]));

  // ═══════════════════════════════════════════════════════════════════════════
  // NEW WIDGET 3 — VIEW DC BOTTOM SHEET
  // ═══════════════════════════════════════════════════════════════════════════
  void _showDCSheet(BuildContext context, List<Map<String, dynamic>> challans) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),
          const Row(children: [
            Icon(Icons.local_shipping_outlined, size: 18, color: kNavy),
            SizedBox(width: 8),
            Text('Farm Pickup — DC Details',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 14),
          ...challans.map((dc) {
            final gross  = (dc['gross_weight']       as num?)?.toDouble() ?? 0;
            final empty  = (dc['empty_crate_weight'] as num?)?.toDouble() ?? 0;
            final net    = (dc['net_weight']          as num?)?.toDouble() ?? 0;
            final birds  = (dc['bird_count']          as num?)?.toInt()   ?? 0;
            final dcNum  = dc['dc_number'] as String? ?? '—';
            final dcDate = dc['dc_date']   as String? ?? '—';
            final farm   = (dc['farms']?['name'])     as String?? '—';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(color: kBorder)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('DC $dcNum',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text(dcDate, style: const TextStyle(fontSize: 11, color: kTextSub)),
                ]),
                const SizedBox(height: 4),
                Text(farm, style: const TextStyle(fontSize: 11, color: kTextSub)),
                const Divider(height: 14),
                Row(children: [
                  _dcStat('Gross', '${gross.toStringAsFixed(1)} kg', Colors.blue),
                  _dcStat('Empty', '${empty.toStringAsFixed(1)} kg', Colors.grey),
                  _dcStat('Net', '${net.toStringAsFixed(1)} kg', Colors.green.shade700),
                  _dcStat('Birds', '$birds', kPrimary),
                ]),
              ]),
            );
          }),
        ]),
      ),
    );
  }

  Widget _dcStat(String l, String v, Color c) => Expanded(
      child: Column(children: [
        Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c),
            textAlign: TextAlign.center),
        Text(l, style: const TextStyle(fontSize: 9, color: kTextHint),
            textAlign: TextAlign.center),
      ]));

  // ═══════════════════════════════════════════════════════════════════════════
  // NEW WIDGET 4 — FLAG ISSUE SECTION (replaces Reject)
  // ═══════════════════════════════════════════════════════════════════════════
  static const _flagCategories = [
    ('weight_mismatch',      '⚖️ Weight Mismatch',      'Delivered weight differs from expected'),
    ('ble_issue',            '📡 BLE Issue',             'Scale readings look incorrect or inconsistent'),
    ('mortality_concern',    '🐦 Mortality Concern',     'Dead birds not properly recorded or disputed'),
    ('customer_complaint',   '🏪 Customer Complaint',    'Retailer has raised a concern about delivery'),
    ('rate_concern',         '💰 Rate Concern',          'Applied rate is disputed or incorrect'),
    ('other',                '📋 Other',                 'Issue not covered by above categories'),
  ];

  Widget _buildFlagIssueSection() {
    return Container(
      decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border: Border.all(color: Colors.orange.shade200)),
      child: Column(children: [
        InkWell(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(kRadiusCard - 2)),
          onTap: () => setState(() => _showFlagExpanded = !_showFlagExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              const Icon(Icons.flag_outlined, size: 18, color: Colors.orange),
              const SizedBox(width: 8),
              const Expanded(child: Text('Flag Issue',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                      color: Colors.orange))),
              const Text('Hold for review without rejecting',
                  style: TextStyle(fontSize: 10, color: kTextSub)),
              const SizedBox(width: 8),
              Icon(_showFlagExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.orange, size: 18),
            ]),
          ),
        ),
        if (_showFlagExpanded) ...[
          const Divider(height: 1, color: Color(0xFFFFE0B2)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // Category chips
              const Text('SELECT ISSUE CATEGORY *',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                      color: kTextHint, letterSpacing: 0.5)),
              const SizedBox(height: 8),
              ...(_flagCategories.map((cat) {
                final selected = _flagCategory == cat.$1;
                return GestureDetector(
                  onTap: () => setState(() => _flagCategory =
                  selected ? null : cat.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                        color: selected
                            ? Colors.orange.withValues(alpha: 0.12)
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(kRadiusChip),
                        border: Border.all(
                            color: selected
                                ? Colors.orange
                                : Colors.grey.shade300,
                            width: selected ? 1.5 : 1)),
                    child: Row(children: [
                      Text(cat.$2,
                          style: TextStyle(

                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: selected ? Colors.orange : kTextMain)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(cat.$3,
                          style: const TextStyle(
                              fontSize: 11, color: kTextSub))),
                      if (selected)
                        const Icon(Icons.check_circle,
                            size: 16, color: Colors.orange),
                    ]),
                  ),
                );
              })),
              const SizedBox(height: 10),
              // Optional notes
              TextField(
                controller: _flagNotesCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Additional notes (optional)',
                  hintText: 'Describe the issue in detail...',
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _submitting ? null : _flagIssue,
                icon: const Icon(Icons.flag, size: 16),
                label: const Text('Flag & Hold for Review'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
                    padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}