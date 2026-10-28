import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart' hide AppSearchBar;
import '../../../shared/widgets/filters/search_bar.dart';

// ══════════════════════════════════════════════════════════════════════════
// RETURN CREATE SCREEN — real trader workflow:
//   Customer (searchable) → Recent Deliveries (cards) → Products (multi,
//   auto-loaded) → Return Details → Approve
//
// Backend: process_return_batch_v1 (new) loops over process_return_v2
// (existing, now accepts p_product_id + p_return_date) — one call per
// product line, all inside a single Postgres function invocation, so the
// whole batch commits or rolls back together. No business logic is
// duplicated here; every calculation (credit amount, stock ledger, order
// rollup, batch costing) happens exactly where it always did, server-side.
// ══════════════════════════════════════════════════════════════════════════

class ReturnCreateScreen extends ConsumerStatefulWidget {
  const ReturnCreateScreen({super.key});

  @override
  ConsumerState<ReturnCreateScreen> createState() => _S();
}

const _kDeliveryPageSize = 10;

const _reasons = [
  'Mortality',
  'Quality Issue',
  'Customer Cancellation',
  'Wrong Supply',
  'Excess Quantity',
  'Weight Difference',
  'Unsold Birds',
  'Other',
];

class _S extends ConsumerState<ReturnCreateScreen> {
  final _c = Supabase.instance.client;

  // ── Step control ──────────────────────────────────────────────────────
  // 0 = customer, 1 = delivery, 2 = products, 3 = return details
  int _step = 0;

  // ── Step 0: Customer ──────────────────────────────────────────────────
  bool _loadingRetailers = true;
  List<Map<String, dynamic>> _retailers = [];
  List<Map<String, dynamic>> _filteredRetailers = [];
  final _customerSearchCtrl = TextEditingController();
  Map<String, dynamic>? _selectedRetailer;

  // ── Step 1: Recent deliveries ─────────────────────────────────────────
  bool _loadingDeliveries = false;
  List<Map<String, dynamic>> _deliveries = [];
  int _deliveryOffset = 0;
  bool _hasMoreDeliveries = false;
  Map<String, dynamic>? _selectedDelivery;

  // ── Step 2: Products (auto-loaded from the delivery's invoice) ───────
  bool _loadingProducts = false;
  List<Map<String, dynamic>> _productLines = [];
  final List<TextEditingController> _weightCtrls = [];
  final List<TextEditingController> _birdCtrls = [];

  // ── Step 3: Return details ────────────────────────────────────────────
  DateTime _returnDate = DateTime.now();
  String _reason = _reasons.first;
  final _remarksCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadRetailers();
    _customerSearchCtrl.addListener(() => _applyCustomerSearch(_customerSearchCtrl.text));
  }

  @override
  void dispose() {
    _customerSearchCtrl.dispose();
    _remarksCtrl.dispose();
    for (final ctrl in _weightCtrls) {
      ctrl.dispose();
    }
    for (final ctrl in _birdCtrls) {
      ctrl.dispose();
    }
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────

  Future<void> _loadRetailers() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null || !mounted) return;
    setState(() => _loadingRetailers = true);
    try {
      final r = await _c
          .from('retailers')
          .select('id,shop_name,owner_name,phone')
          .eq('trader_id', tid)
          .eq('is_active', true)
          .order('shop_name');
      if (!mounted) return;
      setState(() {
        _retailers = List<Map<String, dynamic>>.from(r);
        _filteredRetailers = List.from(_retailers);
        _loadingRetailers = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingRetailers = false);
      showError(context, e.toString());
    }
  }

  void _applyCustomerSearch(String q) {
    if (!mounted) return;
    final lower = q.trim().toLowerCase();
    setState(() => _filteredRetailers = lower.isEmpty
        ? List.from(_retailers)
        : _retailers.where((r) {
      return (r['shop_name'] as String? ?? '').toLowerCase().contains(lower) ||
          (r['owner_name'] as String? ?? '').toLowerCase().contains(lower) ||
          (r['phone'] as String? ?? '').contains(lower);
    }).toList());
  }

  Future<void> _selectRetailer(Map<String, dynamic> retailer) async {
    setState(() {
      _selectedRetailer = retailer;
      _deliveries = [];
      _deliveryOffset = 0;
      _hasMoreDeliveries = false;
      _step = 1;
    });
    await _loadDeliveries();
  }

  // Only the latest 10 deliveries for this customer, newest first — with
  // "View Older Deliveries" paginating in further pages of 10 on demand.
  Future<void> _loadDeliveries({bool loadMore = false}) async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    final retailerId = _selectedRetailer?['id'];
    if (tid == null || retailerId == null || !mounted) return;
    setState(() => _loadingDeliveries = true);
    try {
      final offset = loadMore ? _deliveryOffset : 0;
      final rows = await _c
          .from('deliveries')
          .select('id,delivery_agent_id,delivered_at,delivered_bird_count,'
          'delivered_total_weight,final_rate,batch_id,order_id,'
          'invoices(id,invoice_number,invoice_date,status),'
          'delivery_batches(delivery_challans(dc_number))')
          .eq('trader_id', tid)
          .eq('retailer_id', retailerId)
          .eq('status', 'delivered')
          .order('delivered_at', ascending: false)
          .range(offset, offset + _kDeliveryPageSize - 1);
      if (!mounted) return;
      final page = List<Map<String, dynamic>>.from(rows);
      setState(() {
        _deliveries = loadMore ? [..._deliveries, ...page] : page;
        _deliveryOffset = offset + page.length;
        _hasMoreDeliveries = page.length == _kDeliveryPageSize;
        _loadingDeliveries = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingDeliveries = false);
      showError(context, e.toString());
    }
  }

  Map<String, dynamic>? _approvedInvoice(Map<String, dynamic> delivery) {
    final raw = delivery['invoices'];
    final list = raw is List
        ? raw.cast<Map<String, dynamic>>()
        : (raw is Map ? [Map<String, dynamic>.from(raw)] : <Map<String, dynamic>>[]);
    if (list.isEmpty) return null;
    final approved = list.where((m) => m['status'] == 'approved');
    return approved.isNotEmpty ? approved.first : list.first;
  }

  String _dcNumbers(Map<String, dynamic> delivery) {
    final batch = delivery['delivery_batches'] as Map<String, dynamic>?;
    final challans = batch?['delivery_challans'] as List?;
    if (challans == null || challans.isEmpty) return '—';
    final nums = challans
        .map((c) => (c as Map)['dc_number'] as String? ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    return nums.isEmpty ? '—' : nums.join(', ');
  }

  Future<void> _selectDelivery(Map<String, dynamic> delivery) async {
    final invoice = _approvedInvoice(delivery);
    if (invoice == null) {
      showError(context, 'No approved invoice found for this delivery — cannot process a return.');
      return;
    }
    setState(() {
      _selectedDelivery = delivery;
      _loadingProducts = true;
      _step = 2;
    });
    try {
      final rows = await _c
          .from('invoice_items')
          .select('id,product_id,product_name,bird_count,weight_kg,rate_per_kg,line_total')
          .eq('invoice_id', invoice['id']);
      if (!mounted) return;
      for (final ctrl in _weightCtrls) {
        ctrl.dispose();
      }
      for (final ctrl in _birdCtrls) {
        ctrl.dispose();
      }
      _weightCtrls.clear();
      _birdCtrls.clear();
      final lines = List<Map<String, dynamic>>.from(rows);
      for (final _ in lines) {
        final wCtrl = TextEditingController();
        final bCtrl = TextEditingController();
        wCtrl.addListener(() => setState(() {}));
        _weightCtrls.add(wCtrl);
        _birdCtrls.add(bCtrl);
      }
      setState(() {
        _productLines = lines;
        _loadingProducts = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingProducts = false);
      showError(context, e.toString());
    }
  }

  double _lineCredit(int i) {
    final wt = double.tryParse(_weightCtrls[i].text) ?? 0;
    final rate = (_productLines[i]['rate_per_kg'] as num?)?.toDouble() ?? 0;
    return wt * rate;
  }

  double get _grandTotalCredit {
    var total = 0.0;
    for (var i = 0; i < _productLines.length; i++) {
      total += _lineCredit(i);
    }
    return total;
  }

  bool get _hasAnyReturnQty =>
      _weightCtrls.any((c) => (double.tryParse(c.text) ?? 0) > 0);

  // ── Submit ────────────────────────────────────────────────────────────

  Future<void> _approve() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    final uid = ref.read(appUserProvider).valueOrNull?.userId;
    if (tid == null || _selectedDelivery == null || _selectedRetailer == null) return;

    // Only products with an entered return weight are submitted.
    final items = <Map<String, dynamic>>[];
    for (var i = 0; i < _productLines.length; i++) {
      final wt = double.tryParse(_weightCtrls[i].text) ?? 0;
      if (wt <= 0) continue;
      items.add({
        'product_id': _productLines[i]['product_id'],
        'bird_count': int.tryParse(_birdCtrls[i].text) ?? 0,
        'weight_kg': wt,
        'rate_per_kg': (_productLines[i]['rate_per_kg'] as num?)?.toDouble(),
      });
    }
    if (items.isEmpty) {
      showError(context, 'Enter a return weight for at least one product');
      return;
    }

    final combinedReason = _remarksCtrl.text.trim().isEmpty
        ? _reason
        : '$_reason — ${_remarksCtrl.text.trim()}';

    setState(() => _submitting = true);
    try {
      final res = await _c.rpc('process_return_batch_v1', params: {
        'p_trader_id': tid,
        'p_delivery_id': _selectedDelivery!['id'],
        'p_retailer_id': _selectedRetailer!['id'],
        'p_agent_id': _selectedDelivery!['delivery_agent_id'],
        'p_return_type': 'same_batch',
        'p_return_date': DateFormat('yyyy-MM-dd').format(_returnDate),
        'p_reason': combinedReason,
        'p_processed_by': uid,
        'p_items': items,
        'p_stock_credited': true,
        'p_credit_note_amount': _grandTotalCredit,
        // This screen is the Trader Return flow (trader verifies and
        // approves) — returned stock goes in-house, never to the delivery
        // agent. A future Delivery Agent Return screen reuses this exact
        // RPC with 'agent' instead; no other change needed here.
        'p_returned_to': 'trader',
      }).timeout(const Duration(seconds: 25));
      if (!mounted) return;
      final result = (res as Map?)?.cast<String, dynamic>() ?? {};
      final count = (result['items_processed'] as num?)?.toInt() ?? items.length;
      Navigator.of(context).pop(true);
      showSuccess(context, 'Return processed — $count product(s) updated ✓');
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        showError(context, e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  // ── Navigation ────────────────────────────────────────────────────────

  void _back() {
    if (_step == 0) {
      Navigator.of(context).pop(false);
    } else {
      setState(() => _step -= 1);
    }
  }

  static const _stepTitles = ['Select Customer', 'Recent Deliveries', 'Products', 'Return Details'];

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kBgPage,
    appBar: AppBar(
      backgroundColor: kSurface,
      leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
      title: Text(_stepTitles[_step]),
    ),
    bottomNavigationBar: const SizedBox(height: kBottomNavClearance),
    body: switch (_step) {
      0 => _customerStep(),
      1 => _deliveryStep(),
      2 => _productsStep(),
      _ => _detailsStep(),
    },
  );

  // ── Step 0: Customer ──────────────────────────────────────────────────

  Widget _customerStep() => Column(children: [
    Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: AppSearchBar(
        controller: _customerSearchCtrl,
        hint: 'Search customer name or mobile',
        autofocus: true,
        onChanged: _applyCustomerSearch,
        onClear: () {
          _customerSearchCtrl.clear();
          _applyCustomerSearch('');
        },
      ),
    ),
    const Divider(height: 1),
    Expanded(
      child: _loadingRetailers
          ? const LoadingList()
          : _filteredRetailers.isEmpty
          ? const EmptyState(icon: Icons.storefront_outlined, message: 'No customers found')
          : ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        itemCount: _filteredRetailers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final r = _filteredRetailers[i];
          return _card(
            onTap: () => _selectRetailer(r),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: kNavy.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.storefront_outlined, color: kNavy, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r['shop_name'] as String? ?? '—',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    if ((r['owner_name'] as String?)?.isNotEmpty == true)
                      Text(r['owner_name'] as String,
                          style: const TextStyle(fontSize: 12, color: kTextSub)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: kTextHint),
            ]),
          );
        },
      ),
    ),
  ]);

  // ── Step 1: Recent deliveries ─────────────────────────────────────────

  Widget _deliveryStep() => Column(children: [
    Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Text(_selectedRetailer?['shop_name'] as String? ?? '—',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: kNavy)),
    ),
    const Divider(height: 1),
    Expanded(
      child: _loadingDeliveries && _deliveries.isEmpty
          ? const LoadingList()
          : _deliveries.isEmpty
          ? const EmptyState(
          icon: Icons.local_shipping_outlined, message: 'No delivered orders for this customer')
          : ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        itemCount: _deliveries.length + (_hasMoreDeliveries ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          if (i == _deliveries.length) {
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: OutlinedButton.icon(
                onPressed: _loadingDeliveries ? null : () => _loadDeliveries(loadMore: true),
                icon: _loadingDeliveries
                    ? const SizedBox(
                    width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.expand_more, size: 18),
                label: const Text('View Older Deliveries'),
              ),
            );
          }
          final d = _deliveries[i];
          final date = DateTime.tryParse(d['delivered_at'] as String? ?? '');
          final invoice = _approvedInvoice(d);
          final birds = (d['delivered_bird_count'] as num?)?.toInt() ?? 0;
          final weight = (d['delivered_total_weight'] as num?)?.toDouble() ?? 0;
          return _card(
            onTap: () => _selectDelivery(d),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.event_outlined, size: 14, color: kTextHint),
                const SizedBox(width: 4),
                Text(date != null ? DateFormat('d MMM y').format(date) : '—',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                const Spacer(),
                const Icon(Icons.chevron_right, color: kTextHint),
              ]),
              const SizedBox(height: 6),
              Text('Invoice: ${invoice?['invoice_number'] as String? ?? '—'}',
                  style: const TextStyle(fontSize: 12, color: kTextSub)),
              Text('DC: ${_dcNumbers(d)}',
                  style: const TextStyle(fontSize: 12, color: kTextSub)),
              const SizedBox(height: 6),
              Row(children: [
                _pill('${weight.toStringAsFixed(1)} kg'),
                const SizedBox(width: 8),
                _pill('$birds birds'),
              ]),
            ]),
          );
        },
      ),
    ),
  ]);

  // ── Step 2: Products ──────────────────────────────────────────────────

  Widget _productsStep() => Column(children: [
    Expanded(
      child: _loadingProducts
          ? const LoadingList()
          : _productLines.isEmpty
          ? const EmptyState(icon: Icons.inventory_2_outlined, message: 'No products on this invoice')
          : ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        itemCount: _productLines.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _productCard(i),
      ),
    ),
    if (!_loadingProducts && _productLines.isNotEmpty)
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: SafeArea(
          top: false,
          child: ElevatedButton(
            onPressed: _hasAnyReturnQty ? () => setState(() => _step = 3) : null,
            child: const Text('Continue'),
          ),
        ),
      ),
  ]);

  Widget _productCard(int i) {
    final p = _productLines[i];
    final deliveredBirds = (p['bird_count'] as num?)?.toInt() ?? 0;
    final deliveredKg = (p['weight_kg'] as num?)?.toDouble() ?? 0;
    final rate = (p['rate_per_kg'] as num?)?.toDouble() ?? 0;
    final credit = _lineCredit(i);
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(p['product_name'] as String? ?? '—',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: kNavy)),
        const SizedBox(height: 6),
        Row(children: [
          _pill('Delivered: $deliveredBirds birds · ${deliveredKg.toStringAsFixed(1)} kg'),
          const SizedBox(width: 8),
          _pill('Rate: ${Fmt.amount(rate)}/kg'),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _weightCtrls[i],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Return Weight (kg) *', border: OutlineInputBorder(), isDense: true),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _birdCtrls[i],
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Return Birds', border: OutlineInputBorder(), isDense: true),
            ),
          ),
        ]),
        if (credit > 0) ...[
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Credit for this product', style: TextStyle(fontSize: 12, color: kTextSub)),
            Text(Fmt.amount(credit),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: kNavy)),
          ]),
        ],
      ]),
    );
  }

  // ── Step 3: Return details ────────────────────────────────────────────

  Widget _detailsStep() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.purple.shade50, borderRadius: BorderRadius.circular(8)),
        child: Text(
            '${_productLines.length} product line(s) on this invoice · '
                '${_weightCtrls.where((c) => (double.tryParse(c.text) ?? 0) > 0).length} being returned',
            style: const TextStyle(fontSize: 12, color: Colors.purple)),
      ),
      const SizedBox(height: 14),
      InkWell(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: _returnDate,
            firstDate: DateTime.now().subtract(const Duration(days: 90)),
            lastDate: DateTime.now(),
          );
          if (picked != null) setState(() => _returnDate = picked);
        },
        child: InputDecorator(
          decoration: const InputDecoration(labelText: 'Return Date', border: OutlineInputBorder()),
          child: Text(DateFormat('d MMMM y').format(_returnDate)),
        ),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: _reason,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Reason *', border: OutlineInputBorder()),
        items: _reasons.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
        onChanged: (v) => setState(() => _reason = v ?? _reason),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _remarksCtrl,
        maxLines: 2,
        decoration: const InputDecoration(labelText: 'Remarks', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 16),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: kNavy.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kBorderLight)),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Total Credit Amount', style: TextStyle(fontSize: 13, color: kTextSub)),
          Text(Fmt.amount(_grandTotalCredit),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: kNavy)),
        ]),
      ),
      const SizedBox(height: 16),
      ElevatedButton.icon(
        onPressed: _submitting ? null : _approve,
        icon: _submitting
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.assignment_return_outlined, size: 18),
        label: Text(_submitting ? 'Processing…' : 'Approve Return'),
      ),
    ]),
  );

  // ── Shared bits ───────────────────────────────────────────────────────

  Widget _card({required Widget child, VoidCallback? onTap}) {
    final content = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard), boxShadow: kCardShadow),
      child: child,
    );
    if (onTap == null) return content;
    return InkWell(borderRadius: BorderRadius.circular(kRadiusCard), onTap: onTap, child: content);
  }

  Widget _pill(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: kBgPage, borderRadius: BorderRadius.circular(6)),
    child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kTextSub)),
  );
}