import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class ApprovalDetailScreen extends ConsumerStatefulWidget {
  const ApprovalDetailScreen({super.key, required this.id});
  final String id;
  @override ConsumerState<ApprovalDetailScreen> createState() => _S();
}

class _S extends ConsumerState<ApprovalDetailScreen> {
  final _c          = Supabase.instance.client;
  final _rateCtrl   = TextEditingController(); // single-product fallback
  final _notesCtrl  = TextEditingController();
  final _rejectCtrl = TextEditingController();
  // Per-product rate controllers: order_item_id -> TextEditingController
  final Map<String,TextEditingController> _itemRateCtrls = {};

  Map<String,dynamic>?       _delivery;
  Map<String,dynamic>?       _weighSession;
  List<Map<String,dynamic>>  _weighRows = [];
  List<Map<String,dynamic>>  _orderItems = [];  // order_items with product info
  bool _loading = true, _submitting = false;
  DateTime _invoiceDate = DateTime.now();

  @override void initState() { super.initState(); _load(); }
  @override void dispose() {
    _rateCtrl.dispose(); _notesCtrl.dispose(); _rejectCtrl.dispose();
    for (final c in _itemRateCtrls.values) c.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      // 1. Delivery with full join
      final d = await _c.from('deliveries')
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
      Map<String,dynamic>? ws;
      List<Map<String,dynamic>> rows = [];
      try {
        ws = await _c.from('weighment_sessions')
            .select('*').eq('delivery_id', widget.id).maybeSingle();
        if (ws != null) {
          final r = await _c.from('weighment_rows')
              .select('*')
              .eq('delivery_id', widget.id)
              .eq('deleted_flag', 'A')
              .order('seq_no');
          rows = List<Map<String,dynamic>>.from(r as List? ?? []);
        }
      } catch (_) {}

      // Extract order_items with product info
      final rawItems = (d['orders']?['order_items'] as List? ?? []);
      final parsedItems = rawItems.map((i) => Map<String,dynamic>.from(i as Map)).toList();

      // Dispose old controllers before creating new ones
      for (final c in _itemRateCtrls.values) c.dispose();
      _itemRateCtrls.clear();

      // Create per-item rate controllers, pre-fill from existing rate or delivery final_rate
      final existRate = (d['final_rate'] as num?)?.toDouble() ?? 0;
      for (final item in parsedItems) {
        final itemId    = item['id'] as String? ?? '';
        final itemRate  = (item['rate_per_kg'] as num?)?.toDouble() ?? 0;
        final fallback  = itemRate > 0 ? itemRate : existRate;
        _itemRateCtrls[itemId] = TextEditingController(
            text: fallback > 0 ? fallback.toStringAsFixed(2).replaceAll('.00', '') : '');
      }

      // Single-rate fallback for backward compat (when only 1 product)
      final firstRate = parsedItems.isNotEmpty
          ? (parsedItems.first['rate_per_kg'] as num?)?.toDouble() ?? 0 : 0;
      _rateCtrl.text = (existRate > 0 ? existRate : firstRate) > 0
          ? (existRate > 0 ? existRate : firstRate).toStringAsFixed(2).replaceAll('.00', '') : '';

      // Invoice date from delivery
      final delivAt = d['delivered_at'] as String?;
      if (delivAt != null) {
        final p = DateTime.tryParse(delivAt);
        if (p != null && mounted) _invoiceDate = p;
      }

      if (mounted) setState(() {
        _delivery    = d;
        _weighSession = ws;
        _weighRows   = rows;
        _orderItems  = parsedItems;
        _loading     = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Core values ──────────────────────────────────────────────────
  double get _rate => double.tryParse(_rateCtrl.text.trim()) ?? 0;

  // Multi-product: true when there are 2+ order items with different products
  bool get _isMultiProduct => _orderItems.length > 1;

  // Sum of all line totals from item rate controllers
  double get _multiProductTotal {
    double total = 0;
    for (final item in _orderItems) {
      final id     = item['id'] as String? ?? '';
      final weight = (item['total_weight'] as num?)?.toDouble() ?? 0;
      final rate   = double.tryParse(_itemRateCtrls[id]?.text.trim() ?? '') ?? 0;
      total += weight * rate;
    }
    return total;
  }

  // Effective billing amount: multi-product sum or single rate × billing weight
  double get _billAmount  => _isMultiProduct ? _multiProductTotal : _billingWeight * _rate;

  // Weighment net total (from BLE scale rows) — most accurate
  double get _weighNetTotal => _weighSession != null
      ? ((_weighSession!['total_net_wt'] as num?)?.toDouble() ?? 0) : 0;

  // What agent manually entered at delivery completion
  double get _agentDeliveredWt =>
      ((_delivery?['received_total_weight'] ?? _delivery?['delivered_total_weight']) as num?)?.toDouble() ?? 0;

  // Best weight to use for billing: weighment if available, else agent entry
  double get _billingWeight => _weighNetTotal > 0 ? _weighNetTotal : _agentDeliveredWt;

  // ORDER-level loss (correct formula)
  double get _orderExpectedWt =>
      (_delivery?['orders']?['total_quantity'] as num?)?.toDouble() ?? 0;
  int    get _orderExpectedBirds =>
      (_delivery?['orders']?['estimated_birds'] as num?)?.toInt() ?? 0;
  double get _transportLoss =>
      (_delivery?['transport_loss_kg'] as num?)?.toDouble() ??
      (_orderExpectedWt > 0 && _billingWeight > 0
          ? (_orderExpectedWt - _billingWeight).clamp(0.0, double.infinity) : 0);
  double get _mortalityWt =>
      (_delivery?['mortality_weight_kg'] as num?)?.toDouble() ?? 0;
  double get _totalLoss     => _transportLoss + _mortalityWt;
  double get _lossPct       => _orderExpectedWt > 0 ? (_totalLoss / _orderExpectedWt * 100) : 0;
  bool   get _isHighLoss    => _lossPct >= 2.0;

  double get _collected   => (_delivery?['collected_amount'] as num?)?.toDouble() ?? 0;
  double get _balance     => _billAmount - _collected;
  int    get _mortalityBirds => (_delivery?['mortality_birds'] as num?)?.toInt() ?? 0;

  Future<void> _approve() async {
    // Validate rates
    if (_isMultiProduct) {
      for (final item in _orderItems) {
        final id   = item['id'] as String? ?? '';
        final name = (item['master_products'] as Map?)?['name'] as String? ?? 'Item';
        final rate = double.tryParse(_itemRateCtrls[id]?.text.trim() ?? '') ?? 0;
        if (rate <= 0) { showError(context, 'Enter rate for $name'); return; }
      }
    } else {
      if (_rate <= 0) { showError(context, 'Enter rate per kg'); return; }
    }
    if (_billingWeight <= 0) { showError(context, 'No weight data available'); return; }

    final source = _weighNetTotal > 0 ? 'BLE Scale' : 'Agent Entry';

    // Build confirmation message
    String confirmMsg;
    if (_isMultiProduct) {
      final lines = _orderItems.map((item) {
        final id   = item['id'] as String? ?? '';
        final name = (item['master_products'] as Map?)?['name'] as String? ?? '—';
        final wt   = (item['total_weight'] as num?)?.toDouble() ?? 0;
        final rate = double.tryParse(_itemRateCtrls[id]?.text.trim() ?? '') ?? 0;
        return '$name: ${wt.toStringAsFixed(1)} kg × ₹${rate.toStringAsFixed(2)} = ${Fmt.amount(wt * rate)}';
      }).join('\n');
      confirmMsg = '$lines\n─────\nTotal: ${Fmt.amount(_billAmount)}\n'
                   'Weight source: $source\n'
                   'Invoice date: ${DateFormat('d MMM y').format(_invoiceDate)}';
    } else {
      confirmMsg = '${_billingWeight.toStringAsFixed(2)} kg × ₹${_rate.toStringAsFixed(2)}/kg'
               ' = ${Fmt.amount(_billAmount)}\n'
               'Weight source: $source\n'
               'Invoice date: ${DateFormat('d MMM y').format(_invoiceDate)}';
    }

    final ok = await confirmDialog(context,
      title: 'Approve Delivery',
      message: confirmMsg,
      confirmText: 'Approve & Create Bill', confirmColor: kPrimary);
    if (!ok) return;

    if (mounted) setState(() => _submitting = true);
    try {
      // Build per-item rates for multi-product orders
      List<Map<String,dynamic>>? itemRates;
      if (_isMultiProduct) {
        itemRates = _orderItems.map((item) {
          final id   = item['id'] as String;
          final rate = double.tryParse(_itemRateCtrls[id]?.text.trim() ?? '') ?? 0;
          return {'order_item_id': id, 'rate_per_kg': rate};
        }).toList();
      }

      await _c.rpc('approve_delivery_and_order', params: {
        'p_delivery_id':    widget.id,
        'p_final_rate':     _isMultiProduct ? null : _rate,
        'p_final_amount':   _billAmount > 0 ? _billAmount : null,
        'p_approved_by':    ref.read(appUserProvider).valueOrNull?.userId,
        'p_approval_notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'p_invoice_date':   _invoiceDate.toIso8601String().split('T')[0],
        if (itemRates != null) 'p_item_rates': itemRates,
      });
      if (mounted) { showSuccess(context, 'Approved! Bill created ✓'); context.go(R.approvals); }
    } catch (e) {
      if (mounted) showError(context, e.toString()
          .replaceAll('Exception: ', '')
          .replaceAll('PostgrestException(message: ', ''));
    } finally { if (mounted) setState(() => _submitting = false); }
  }

  Future<void> _reject() async {
    if (_rejectCtrl.text.trim().isEmpty) { showError(context, 'Enter rejection reason'); return; }
    final ok = await confirmDialog(context, title: 'Reject', message: 'Reject this delivery?');
    if (!ok) return;
    if (mounted) setState(() => _submitting = true);
    try {
      await _c.from('deliveries').update({
        'approval_status':  'rejected',
        'rejection_reason': _rejectCtrl.text.trim(),
        'rejected_by':      ref.read(appUserProvider).valueOrNull?.userId,
        'rejected_at':      DateTime.now().toIso8601String(),
      }).eq('id', widget.id);
      if (mounted) { showSuccess(context, 'Rejected'); context.go(R.approvals); }
    } catch (e) { if (mounted) showError(context, e.toString()); }
    finally { if (mounted) setState(() => _submitting = false); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(
        appBar: AppBar(title: const Text('Approve Delivery')), body: const LoadingList());
    if (_delivery == null) return Scaffold(
        appBar: AppBar(), body: const Center(child: Text('Not found')));

    final o = _delivery!['orders']         as Map<String,dynamic>?;
    final r = o?['retailers']              as Map<String,dynamic>?;
    final a = _delivery!['delivery_agents'] as Map<String,dynamic>?;
    final batch = _delivery!['delivery_batches'] as Map<String,dynamic>?;
    final challans = (batch?['delivery_challans'] as List? ?? []).cast<Map<String,dynamic>>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Approve Delivery'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: ListView(padding: const EdgeInsets.all(16), children: [

        // ── Customer & Agent header ───────────────────────────────
        WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r?['shop_name'] as String? ?? '—',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          if (r?['owner_name'] != null)
            Text(r!['owner_name'] as String, style: const TextStyle(fontSize: 13, color: kTextSub)),
          if (r?['phone'] != null)
            Text(r!['phone'] as String, style: const TextStyle(fontSize: 12, color: kTextHint)),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.delivery_dining, size: 14, color: kPrimary),
            const SizedBox(width: 6),
            Text('${a?['name'] ?? '—'}  ·  ${a?['vehicle_no'] ?? ''}',
                style: const TextStyle(fontSize: 12, color: kTextSub)),
          ]),
          if (_delivery!['delivered_at'] != null) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.access_time, size: 13, color: kTextHint),
              const SizedBox(width: 6),
              Text(DateFormat('d MMM y, hh:mm a').format(
                  DateTime.parse(_delivery!['delivered_at'] as String).toLocal()),
                  style: const TextStyle(fontSize: 12, color: kTextHint)),
            ]),
          ],
        ])),
        const SizedBox(height: 10),

        // ── ORDER vs DELIVERED comparison (ORDER-level loss) ──────
        _buildLossCard(o),
        const SizedBox(height: 10),

        // ── WEIGHMENT LOG (BLE Scale data) ────────────────────────
        if (_weighSession != null) ...[
          _buildWeighmentLog(challans),
          const SizedBox(height: 10),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kBorder)),
            child: const Row(children: [
              Icon(Icons.scale_outlined, size: 18, color: kTextHint),
              SizedBox(width: 8),
              Text('No scale weighment recorded for this delivery',
                  style: TextStyle(fontSize: 12, color: kTextHint)),
            ])),
          const SizedBox(height: 10),
        ],

        // ── DC / Farm Pickup details ──────────────────────────────
        if (challans.isNotEmpty) ...[
          _buildDCDetails(challans),
          const SizedBox(height: 10),
        ],

        // ── Proof photos ─────────────────────────────────────────
        if (_delivery!['mortality_proof_url'] != null ||
            _delivery!['delivery_photo_url'] != null)
          _buildPhotos(),

        // ── Rate & Bill ───────────────────────────────────────────
        WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader('BILLING'),
          // Weight source label
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
                color: _weighNetTotal > 0 ? Colors.blue.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Icon(_weighNetTotal > 0 ? Icons.scale : Icons.edit_outlined,
                  size: 14, color: _weighNetTotal > 0 ? Colors.blue : Colors.orange),
              const SizedBox(width: 6),
              Text(
                _weighNetTotal > 0
                    ? 'Using BLE scale weight: ${_billingWeight.toStringAsFixed(2)} kg'
                    : 'Using agent entry: ${_billingWeight.toStringAsFixed(2)} kg (no scale data)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: _weighNetTotal > 0 ? Colors.blue : Colors.orange)),
            ])),

          // ── Per-product rates (multi-product) OR single rate ──────────
          if (_isMultiProduct) ...[
            const Text('RATE PER PRODUCT',
                style: TextStyle(fontSize: 11, color: kTextHint, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            ..._orderItems.map((item) {
              final id        = item['id'] as String? ?? '';
              final prodName  = (item['master_products'] as Map?)?['name'] as String? ?? 'Product';
              final weight    = (item['total_weight'] as num?)?.toDouble() ?? 0;
              final birds     = (item['bird_count'] as num?)?.toInt() ?? 0;
              final ctrl      = _itemRateCtrls[id] ?? TextEditingController();
              final rate      = double.tryParse(ctrl.text.trim()) ?? 0;
              final lineTotal = weight * rate;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kBorder)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(width: 8, height: 8,
                        decoration: BoxDecoration(color: kPrimary, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(prodName,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
                    Text('${weight.toStringAsFixed(1)} kg · $birds birds',
                        style: const TextStyle(fontSize: 11, color: kTextSub)),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: TextField(
                      controller: ctrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: 'Rate/kg *', prefixText: '₹', suffixText: '/kg',
                          filled: true, fillColor: Colors.white,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none)),
                      onChanged: (_) => setState(() {}))),
                    const SizedBox(width: 12),
                    if (rate > 0) Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(Fmt.amount(lineTotal),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: kPrimary)),
                      Text('${weight.toStringAsFixed(1)} × ₹${rate.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 10, color: kTextSub)),
                    ]),
                  ]),
                ]));
            }),
          ] else ...[
            const Text('Rate per kg *',
                style: TextStyle(fontSize: 11, color: kTextHint, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            TextField(
              controller: _rateCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                prefixText: '₹', suffixText: '/kg',
                filled: true, fillColor: const Color(0xFFF3F4F6),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)),
              onChanged: (_) => setState(() {})),
          ],
          const SizedBox(height: 12),

          // Live calculation summary
          if (_billAmount > 0)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kPrimary.withValues(alpha: 0.2))),
              child: Column(children: [
                if (_isMultiProduct) ...[
                  ..._orderItems.map((item) {
                    final id       = item['id'] as String? ?? '';
                    final prodName = (item['master_products'] as Map?)?['name'] as String? ?? '—';
                    final weight   = (item['total_weight'] as num?)?.toDouble() ?? 0;
                    final rate     = double.tryParse(_itemRateCtrls[id]?.text.trim() ?? '') ?? 0;
                    if (rate <= 0) return const SizedBox.shrink();
                    return _bRow(prodName, Fmt.amount(weight * rate), kTextSub);
                  }),
                  const Divider(height: 10),
                ] else ...[
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('${_billingWeight.toStringAsFixed(2)} kg × ₹${_rateCtrl.text}/kg',
                        style: const TextStyle(fontSize: 12, color: kTextSub)),
                    const SizedBox.shrink(),
                  ]),
                ],
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Total Bill', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  Text(Fmt.amount(_billAmount),
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: kPrimary)),
                ]),
                if (_collected > 0) ...[
                  const Divider(height: 14),
                  _bRow('Collected by agent', Fmt.amount(_collected), Colors.green),
                  _bRow('Balance due', Fmt.amount(_balance),
                      _balance > 0 ? Colors.orange : Colors.green),
                ],
              ])),
          const SizedBox(height: 12),

          // Invoice date
          const Text('Invoice Date',
              style: TextStyle(fontSize: 11, color: kTextHint, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          InkWell(
            onTap: () async {
              final d = await showDatePicker(context: context,
                initialDate: _invoiceDate,
                firstDate: DateTime.now().subtract(const Duration(days: 90)),
                lastDate: DateTime.now());
              if (d != null && mounted) setState(() => _invoiceDate = d);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.calendar_today_outlined, size: 16, color: kPrimary),
                const SizedBox(width: 10),
                Text(DateFormat('d MMMM y').format(_invoiceDate),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const Spacer(),
                const Text('Change', style: TextStyle(fontSize: 12, color: kPrimary, fontWeight: FontWeight.w600)),
              ]))),
          const SizedBox(height: 10),
          TextField(controller: _notesCtrl,
              decoration: const InputDecoration(labelText: 'Notes (optional)')),
        ])),
        const SizedBox(height: 16),

        // ── Approve button ─────────────────────────────────────────
        SizedBox(height: 52, child: ElevatedButton.icon(
          onPressed: _submitting ? null : _approve,
          icon: _submitting
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check_circle_outline, size: 20),
          label: const Text('Approve & Create Bill',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))),
        const SizedBox(height: 12),

        // ── Reject ─────────────────────────────────────────────────
        ExpansionTile(
          title: const Text('Reject Delivery',
              style: TextStyle(color: kError, fontWeight: FontWeight.w600)),
          leading: const Icon(Icons.cancel_outlined, color: kError, size: 20),
          children: [Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: _rejectCtrl, maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Reason *', alignLabelWithHint: true)),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _submitting ? null : _reject,
                style: OutlinedButton.styleFrom(foregroundColor: kError, side: const BorderSide(color: kError)),
                child: const Text('Reject')),
            ]))]),
        const SizedBox(height: 20),
      ]),
    );
  }

  // ── ORDER-LEVEL LOSS CARD ────────────────────────────────────────
  Widget _buildLossCard(Map<String,dynamic>? o) {
    final expectedWt    = _orderExpectedWt;
    final expectedBirds = _orderExpectedBirds;
    final deliveredWt   = _billingWeight;
    final deliveredBirds = (_delivery?['delivered_bird_count'] as num?)?.toInt() ?? 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: _isHighLoss ? Colors.red.shade50 : Colors.green.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: _isHighLoss ? Colors.red.shade300 : Colors.green.shade300, width: 1.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(_isHighLoss ? Icons.warning_amber_rounded : Icons.check_circle_outline,
              color: _isHighLoss ? Colors.red : Colors.green, size: 18),
          const SizedBox(width: 6),
          Text(
            _isHighLoss
                ? '⚠️ High Loss — ${_lossPct.toStringAsFixed(1)}% needs attention'
                : 'Loss: ${_lossPct.toStringAsFixed(1)}%',
            style: TextStyle(
                fontWeight: FontWeight.w800, fontSize: 13,
                color: _isHighLoss ? Colors.red : Colors.green.shade700)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(6)),
            child: Text('ORDER LEVEL',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                    color: _isHighLoss ? Colors.red : Colors.green))),
        ]),
        const SizedBox(height: 12),
        // Grid: Expected vs Actual
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(8)),
          child: Column(children: [
            _lossRow('Weight', expectedWt, deliveredWt, 'kg', isHeader: true),
            const Divider(height: 10),
            _lossRow('Birds', expectedBirds.toDouble(), deliveredBirds.toDouble(), 'birds'),
          ])),
        const SizedBox(height: 10),
        // Breakdown
        Row(children: [
          _lossChip('Transport Loss', '${_transportLoss.toStringAsFixed(2)} kg', Colors.orange),
          const SizedBox(width: 8),
          _lossChip('Mortality Loss',
              '$_mortalityBirds birds\n${_mortalityWt.toStringAsFixed(2)} kg', Colors.red),
          const SizedBox(width: 8),
          _lossChip('Total Loss', '${_totalLoss.toStringAsFixed(2)} kg',
              _isHighLoss ? Colors.red : Colors.orange),
        ]),
        if (_delivery?['delivery_notes'] != null) ...[
          const SizedBox(height: 8),
          Text('Agent notes: ${_delivery!['delivery_notes']}',
              style: const TextStyle(fontSize: 11, color: kTextSub, fontStyle: FontStyle.italic)),
        ],
      ]));
  }

  Widget _lossRow(String label, double expected, double actual, String unit,
      {bool isHeader = false}) {
    final diff = actual - expected;
    return Row(children: [
      SizedBox(width: 60, child: Text(label,
          style: TextStyle(fontSize: isHeader ? 11 : 11,
              color: kTextHint, fontWeight: FontWeight.w600))),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('Expected: ${isHeader ? expected.toStringAsFixed(1) : expected.toStringAsFixed(0)} $unit',
            style: const TextStyle(fontSize: 11, color: kTextSub)),
      ])),
      const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('Delivered: ${isHeader ? actual.toStringAsFixed(1) : actual.toStringAsFixed(0)} $unit',
            style: const TextStyle(fontSize: 11, color: kTextMain)),
      ])),
      const SizedBox(width: 8),
      SizedBox(width: 70, child: Text(
        '${diff >= 0 ? '+' : ''}${isHeader ? diff.toStringAsFixed(1) : diff.toStringAsFixed(0)} $unit',
        textAlign: TextAlign.right,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
            color: diff < 0 ? Colors.red : Colors.green))),
    ]);
  }

  Widget _lossChip(String label, String value, Color c) => Expanded(child: Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 9, color: c, fontWeight: FontWeight.w700)),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w800)),
    ])));

  // ── WEIGHMENT LOG TABLE ───────────────────────────────────────────
  Widget _buildWeighmentLog(List<Map<String,dynamic>> challans) {
    final ws      = _weighSession!;
    final rows    = _weighRows;
    final totLoad = (ws['total_load_wt'] as num?)?.toDouble() ?? 0;
    final totEmpty = (ws['total_empty_wt'] as num?)?.toDouble() ?? 0;
    final totNet  = (ws['total_net_wt'] as num?)?.toDouble() ?? 0;
    final avgWt   = (ws['avg_bird_wt'] as num?)?.toDouble() ?? 0;
    final totBirds = (ws['total_birds'] as num?)?.toInt() ?? 0;
    final cages   = (ws['total_cages'] as num?)?.toInt() ?? 0;

    return Container(
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.blue.shade200, width: 1.5)),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
              color: Colors.blue.shade700,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13))),
          child: Row(children: [
            const Icon(Icons.scale, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            const Expanded(child: Text('BLE Scale Weighment Log',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6)),
              child: Text('${rows.length} readings',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))),
          ])),

        // Summary row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.blue.shade50,
          child: Row(children: [
            _wStat('Total Gross', '${totLoad.toStringAsFixed(1)} kg', Colors.blue),
            _wStat('Total Empty', '${totEmpty.toStringAsFixed(1)} kg', Colors.grey),
            _wStat('Net Weight', '${totNet.toStringAsFixed(1)} kg', Colors.blue.shade700),
            _wStat('Birds', '$totBirds', kPrimary),
            _wStat('Avg/bird', '${(avgWt * 1000).toStringAsFixed(0)}g', Colors.teal),
            _wStat('Cages', '$cages', kTextSub),
          ])),

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
            final loadWt  = (row['load_wt']   as num?)?.toDouble() ?? 0;
            final emptyWt = (row['empty_wt']  as num?)?.toDouble() ?? 0;
            final netWt   = (row['net_wt']    as num?)?.toDouble() ?? 0;
            final avgW    = (row['avg_wt']    as num?)?.toDouble() ?? 0;
            final cageL   = (row['load_cages'] as num?)?.toInt() ?? 0;
            final seq     = (row['seq_no']    as num?)?.toInt() ?? 0;
            final time    = row['entry_time'] as String? ?? '—';
            return Container(
              padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
              decoration: BoxDecoration(
                  color: seq.isOdd ? const Color(0xFFF8F9FC) : Colors.white),
              child: Row(children: [
                _tCell('$seq',                   32, kTextHint),
                _tCell(time,                     50, kTextSub),
                _tCell('${loadWt.toStringAsFixed(2)} kg',  70, kTextMain),
                _tCell('${emptyWt.toStringAsFixed(2)} kg', 70, kTextSub),
                _tCell('${netWt.toStringAsFixed(2)} kg',   70,
                    netWt > 0 ? Colors.green.shade700 : Colors.orange),
                _tCell('$cageL',                 50, kTextSub),
                _tCell('${(avgW*1000).toStringAsFixed(0)}g', 56, Colors.teal),
              ]));
          }),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(children: [
              _tHead('TOTAL', 82),
              _tHead('', 50),
              _tHead('${totLoad.toStringAsFixed(2)} kg', 70, isTotal: true),
              _tHead('${totEmpty.toStringAsFixed(2)} kg', 70),
              _tHead('${totNet.toStringAsFixed(2)} kg', 70, isTotal: true, color: Colors.blue.shade700),
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
    SizedBox(width: w, child: Text(label,
        style: TextStyle(fontSize: 10, fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600,
            color: color ?? (isTotal ? kTextMain : kTextHint))));

  Widget _tCell(String v, double w, Color c) =>
    SizedBox(width: w, child: Text(v,
        style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600)));

  Widget _wStat(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c), textAlign: TextAlign.center),
    Text(l, style: const TextStyle(fontSize: 9, color: kTextHint), textAlign: TextAlign.center),
  ]));

  // ── DC / FARM PICKUP DETAILS ──────────────────────────────────────
  Widget _buildDCDetails(List<Map<String,dynamic>> challans) =>
    Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: Colors.green.shade700,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11))),
          child: Row(children: [
            const Icon(Icons.agriculture, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text('Farm Pickup — ${challans.length} DC${challans.length > 1 ? 's' : ''}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
          ])),
        ...challans.asMap().entries.map((e) {
          final i  = e.key;
          final ch = e.value;
          final gross = (ch['gross_weight']       as num?)?.toDouble() ?? 0;
          final empty = (ch['empty_crate_weight'] as num?)?.toDouble() ?? 0;
          final net   = (ch['net_weight']         as num?)?.toDouble() ?? 0;
          final birds = (ch['bird_count']         as num?)?.toInt()    ?? 0;
          final rate  = (ch['farm_rate']          as num?)?.toDouble();
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                border: i < challans.length - 1 ? const Border(bottom: BorderSide(color: kBorder)) : null),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('DC ${ch['dc_number'] ?? '—'}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(width: 8),
                Text(ch['dc_date']?.toString() ?? '',
                    style: const TextStyle(fontSize: 11, color: kTextHint)),
              ]),
              const SizedBox(height: 6),
              Text('${ch['farmer_name'] ?? '—'}  ·  ${ch['farm_location'] ?? ''}',
                  style: const TextStyle(fontSize: 12, color: kTextSub)),
              const SizedBox(height: 6),
              Row(children: [
                _dStat('Gross',  '${gross.toStringAsFixed(1)} kg', Colors.blue),
                _dStat('Empty',  '${empty.toStringAsFixed(1)} kg', Colors.grey),
                _dStat('Net',    '${net.toStringAsFixed(1)} kg',   Colors.green),
                _dStat('Birds',  '$birds',                          kPrimary),
                if (rate != null) _dStat('Rate', '₹${rate.toStringAsFixed(0)}/kg', Colors.orange),
              ]),
              if (ch['vehicle_number'] != null)
                Padding(padding: const EdgeInsets.only(top: 4),
                  child: Text('Vehicle: ${ch['vehicle_number']}',
                      style: const TextStyle(fontSize: 11, color: kTextHint))),
              if (ch['dc_photo_url'] != null)
                Padding(padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    const Icon(Icons.photo_outlined, size: 13, color: Colors.blue),
                    const SizedBox(width: 4),
                    const Text('DC photo attached', style: TextStyle(fontSize: 11, color: Colors.blue)),
                  ])),
            ]));
        }),
        // DC totals
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
              color: Color(0xFFF0FAF0),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(11))),
          child: Row(children: [
            const Icon(Icons.summarize_outlined, size: 14, color: Colors.green), const SizedBox(width: 6),
            Text(
              'Total DC: '
              '${challans.fold(0, (s, c) => s + ((c['bird_count'] as num?)?.toInt() ?? 0))} birds · '
              '${challans.fold(0.0, (s, c) => s + ((c['net_weight'] as num?)?.toDouble() ?? 0)).toStringAsFixed(1)} kg',
              style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w700)),
          ])),
      ]));

  // ── PROOF PHOTOS ─────────────────────────────────────────────────
  Widget _buildPhotos() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader('PROOF PHOTOS'),
        Row(children: [
          if (_delivery!['mortality_proof_url'] != null)
            Expanded(child: _photoTile('Mortality Proof', _delivery!['mortality_proof_url'] as String, Colors.red)),
          if (_delivery!['mortality_proof_url'] != null && _delivery!['delivery_photo_url'] != null)
            const SizedBox(width: 8),
          if (_delivery!['delivery_photo_url'] != null)
            Expanded(child: _photoTile('Delivery Proof', _delivery!['delivery_photo_url'] as String, Colors.blue)),
        ]),
      ]));
  }

  Widget _photoTile(String label, String url, Color c) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: c.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.3))),
    child: Column(children: [
      Icon(Icons.photo_outlined, color: c, size: 24),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Text('Photo attached ✓', style: TextStyle(fontSize: 10, color: c.withValues(alpha: 0.7))),
    ]));

  Widget _bRow(String l, String v, Color c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: const TextStyle(fontSize: 12, color: kTextSub)),
      Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c)),
    ]));

  Widget _dStat(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c), textAlign: TextAlign.center),
    Text(l, style: const TextStyle(fontSize: 9, color: kTextHint), textAlign: TextAlign.center),
  ]));
}
