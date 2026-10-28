import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/responsive_layout.dart';

// ══════════════════════════════════════════════════════════════════════════
// INVOICE CORRECTION SCREEN
//
// Reuses:
//  - get_invoice_detail RPC (same one InvoiceDetailScreen uses) to preload
//  - cancel_and_reissue_invoice RPC to submit — extended with one new
//    optional p_payment_type param (Payment Type enhancement) but every
//    other field/behavior is unchanged; omitting it preserves the
//    invoice's current payment status rather than resetting it.
//  - retailers / get_trader_enabled_products — same data sources used by
//    other order-entry screens in this app
//
// No new RPC, no schema change. Change detection happens both here
// (to enable/disable the Approve Correction button) and again inside the
// RPC itself (its own "No changes detected" guard).
// ══════════════════════════════════════════════════════════════════════════

class _CorrectionLine {
  String? productId;
  String productName;
  final weightCtrl = TextEditingController();
  final birdsCtrl = TextEditingController();
  final rateCtrl = TextEditingController();

  _CorrectionLine({
    this.productId,
    this.productName = '',
    double weight = 0,
    int birds = 0,
    double rate = 0,
  }) {
    weightCtrl.text = weight == 0 ? '' : _trim(weight);
    birdsCtrl.text = birds == 0 ? '' : birds.toString();
    rateCtrl.text = rate == 0 ? '' : _trim(rate);
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  double get weight => double.tryParse(weightCtrl.text.trim()) ?? 0;
  int get birds => int.tryParse(birdsCtrl.text.trim()) ?? 0;
  double get rate => double.tryParse(rateCtrl.text.trim()) ?? 0;

  void dispose() {
    weightCtrl.dispose();
    birdsCtrl.dispose();
    rateCtrl.dispose();
  }
}

class InvoiceCorrectionScreen extends ConsumerStatefulWidget {
  const InvoiceCorrectionScreen({super.key, required this.invoiceId});
  final String invoiceId;

  @override
  ConsumerState<InvoiceCorrectionScreen> createState() => _S();
}

class _S extends ConsumerState<InvoiceCorrectionScreen> {
  final _c = Supabase.instance.client;
  bool _loading = true;
  bool _submitting = false;
  String? _err;

  Map<String, dynamic>? _original;
  List<_CorrectionLine> _lines = [];

  List<Map<String, dynamic>> _retailers = [];
  List<Map<String, dynamic>> _products = [];

  String? _origRetailerId;
  String? _selectedRetailerId;
  DateTime _origInvoiceDate = DateTime.now();
  DateTime _invoiceDate = DateTime.now();
  final _remarksCtrl = TextEditingController();
  String _origRemarks = '';

  // Payment Type (Credit / Cash Paid) — new. Defaulted from the invoice's
  // actual current state (collected >= total), not from orders.payment_type
  // (that's set once at creation and never kept in sync — collected_amount
  // is the real current truth). 'credit' | 'cash_paid'.
  String _origPaymentType = 'credit';
  String _paymentType = 'credit';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    _remarksCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _err = null; });
    try {
      final tid = ref.read(appUserProvider).valueOrNull?.traderId;
      if (tid == null) throw Exception('Not signed in.');

      final results = await Future.wait<dynamic>([
        // Same RPC InvoiceDetailScreen already uses — no new RPC.
        _c.rpc('get_invoice_detail', params: {'p_invoice_id': widget.invoiceId}),
        _c.from('retailers')
            .select('id,shop_name')
            .eq('trader_id', tid)
            .eq('is_active', true)
            .order('shop_name'),
        _c.rpc('get_trader_enabled_products', params: {'p_trader_id': tid}),
      ]);

      final data = results[0] as Map<String, dynamic>?;
      final inv = data?['invoice'] as Map<String, dynamic>?;
      final itemsRaw = data?['items'];
      if (inv == null) throw Exception('Invoice not found.');

      if (inv['status'] != 'approved') {
        throw Exception(
            'Only an approved invoice can be corrected (current status: ${inv['status']}).');
      }

      final items = (itemsRaw is List)
          ? itemsRaw.map((i) => Map<String, dynamic>.from(i as Map)).toList()
          : <Map<String, dynamic>>[];

      final lines = items.isNotEmpty
          ? items
          .map((it) => _CorrectionLine(
        productId: it['product_id'] as String?,
        productName: it['product_name'] as String? ?? '',
        weight: (it['weight_kg'] as num?)?.toDouble() ?? 0,
        birds: (it['bird_count'] as num?)?.toInt() ?? 0,
        rate: (it['applied_rate'] as num?)?.toDouble() ??
            (it['rate_per_kg'] as num?)?.toDouble() ??
            0,
      ))
          .toList()
          : [
        // Legacy fallback — invoice has no invoice_items rows.
        _CorrectionLine(
          productId: null,
          productName: inv['product_name'] as String? ?? 'Product',
          weight: (inv['quantity_kg'] as num?)?.toDouble() ?? 0,
          birds: (inv['bird_count'] as num?)?.toInt() ?? 0,
          rate: (inv['price_per_kg'] as num?)?.toDouble() ?? 0,
        ),
      ];

      final invDate =
          DateTime.tryParse(inv['invoice_date'] as String? ?? '') ?? DateTime.now();
      final remarks = inv['notes'] as String? ?? '';

      // Same signal the RPC itself uses to determine current payment
      // status — collected_amount vs total_amount, not orders.payment_type
      // (which is set once at creation and never kept in sync).
      final collected = (inv['collected_amount'] as num?)?.toDouble() ?? 0;
      final total = (inv['total_amount'] as num?)?.toDouble() ?? 0;
      final paymentType = (total > 0 && collected >= total) ? 'cash_paid' : 'credit';

      if (!mounted) return;
      setState(() {
        _original = inv;
        _lines = lines;
        _retailers = List<Map<String, dynamic>>.from(results[1] as List? ?? []);
        _products = List<Map<String, dynamic>>.from(results[2] as List? ?? []);
        _origRetailerId = inv['retailer_id'] as String?;
        _selectedRetailerId = _origRetailerId;
        _origInvoiceDate = invDate;
        _invoiceDate = invDate;
        _origRemarks = remarks;
        _remarksCtrl.text = remarks;
        _origPaymentType = paymentType;
        _paymentType = paymentType;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _err = e.toString().replaceAll('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  // ── Change detection ───────────────────────────────────────────────────
  bool get _hasChanges {
    if (_original == null) return false;
    if (_selectedRetailerId != _origRetailerId) return true;
    if (!_sameDate(_invoiceDate, _origInvoiceDate)) return true;
    if (_remarksCtrl.text.trim() != _origRemarks.trim()) return true;
    if (_paymentType != _origPaymentType) return true;

    // Compare each line against the snapshot captured right after load.
    for (final l in _lines) {
      final orig = _originalLineFor(l);
      if (orig == null) return true;
      if (l.weight != orig.weight || l.birds != orig.birds || l.rate != orig.rate) {
        return true;
      }
    }
    return false;
  }

  bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // Snapshot of original line values, captured once at load time.
  final Map<_CorrectionLine, _LineSnapshot> _origSnapshots = {};
  _LineSnapshot? _originalLineFor(_CorrectionLine l) => _origSnapshots[l];

  void _captureSnapshots() {
    _origSnapshots.clear();
    for (final l in _lines) {
      _origSnapshots[l] = _LineSnapshot(l.weight, l.birds, l.rate);
    }
  }

  // ── Confirm + submit ───────────────────────────────────────────────────
  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _invoiceDate,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
    );
    if (d != null && mounted) setState(() => _invoiceDate = d);
  }

  Future<void> _submit() async {
    if (!_hasChanges) return; // guarded by disabled button too — defence in depth

    final ok = await confirmDialog(
      context,
      title: 'Correct Invoice?',
      message: 'This will cancel the existing invoice and create a new '
          'corrected invoice.\n\nThis action cannot be undone. Continue?',
      confirmText: 'Approve Correction',
      confirmColor: kError,
    );
    if (!ok || !mounted) return;

    final user = ref.read(appUserProvider).valueOrNull;
    if (user == null) return;

    setState(() { _submitting = true; _err = null; });
    try {
      final items = _lines
          .map((l) => {
        'product_id': l.productId,
        'weight_kg': l.weight,
        'bird_count': l.birds,
        'rate_per_kg': l.rate,
      })
          .toList();

      final res = await _c.rpc('cancel_and_reissue_invoice', params: {
        'p_invoice_id': widget.invoiceId,
        'p_actor_id': user.userId,
        'p_actor_type': 'trader',
        if (_selectedRetailerId != _origRetailerId)
          'p_retailer_id': _selectedRetailerId,
        if (!_sameDate(_invoiceDate, _origInvoiceDate))
          'p_invoice_date': DateFormat('yyyy-MM-dd').format(_invoiceDate),
        'p_notes': _remarksCtrl.text.trim().isEmpty ? null : _remarksCtrl.text.trim(),
        'p_reason': 'Invoice Correction',
        'p_items': items,
        // Only sent when actually changed — the RPC treats "not passed"
        // as "preserve the invoice's current payment status", which also
        // applies to corrections that don't touch payment type at all.
        if (_paymentType != _origPaymentType) 'p_payment_type': _paymentType,
      }).timeout(const Duration(seconds: 20));

      if (!mounted) return;
      final result = (res as Map?)?.cast<String, dynamic>() ?? {};
      final newInvoiceId = result['new_invoice_id'] as String?;
      final newInvoiceNumber = result['new_invoice_number'] as String? ?? '';

      showSuccess(context, 'Invoice corrected — $newInvoiceNumber created ✓');

      // Signal InvoiceDetailScreen (of the OLD invoice) to refresh when the
      // user eventually navigates back to it, then go straight to the new one.
      if (newInvoiceId != null) {
        context.pushReplacement(R.invoiceDetailPath(newInvoiceId));
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _err = e.toString().replaceAll('Exception: ', '');
          _submitting = false;
        });
        showError(context, _err!);
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) => ResponsiveLayout(
    mobile: (_) => _scaffold(),
    desktop: (_) => _scaffold(),
  );

  Widget _scaffold() {
    if (_loading) return const Scaffold(body: LoadingList());
    if (_err != null && _original == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Correct Invoice')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_err!, style: const TextStyle(color: kError)),
          ),
        ),
      );
    }

    // Capture original snapshots exactly once, right after load, before any
    // edits happen — used by _hasChanges.
    if (_origSnapshots.isEmpty && _lines.isNotEmpty) _captureSnapshots();

    final canSubmit = _hasChanges && !_submitting;

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: Text('Correct ${_original?['invoice_number'] ?? 'Invoice'}'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: kError.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: kError.withValues(alpha: 0.25)),
            ),
            child: const Row(children: [
              Icon(Icons.warning_amber_rounded, color: kError, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'This cancels the original invoice and creates a new corrected one. '
                      'Use this only for genuine data-entry mistakes.',
                  style: TextStyle(fontSize: 12, color: kTextSub),
                ),
              ),
            ]),
          ),

          // ── Retailer ─────────────────────────────────────────────────
          WhiteCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionHeader('RETAILER'),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _selectedRetailerId,
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: _retailers
                    .map((r) => DropdownMenuItem(
                  value: r['id'] as String,
                  child: Text(r['shop_name'] as String? ?? '—'),
                ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedRetailerId = v),
              ),
            ]),
          ),
          const SizedBox(height: 14),

          // ── Invoice date ─────────────────────────────────────────────
          WhiteCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionHeader('INVOICE DATE'),
              const SizedBox(height: 10),
              InkWell(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                      border: Border.all(color: kBorderLight),
                      borderRadius: BorderRadius.circular(kRadiusInner)),
                  child: Row(children: [
                    const Icon(Icons.calendar_today_outlined, size: 16, color: kTextSub),
                    const SizedBox(width: 8),
                    Text(DateFormat('d MMMM y').format(_invoiceDate)),
                  ]),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 14),

          // ── Payment Type ─────────────────────────────────────────────
          WhiteCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionHeader('PAYMENT TYPE'),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'credit', label: Text('Credit')),
                  ButtonSegment(value: 'cash_paid', label: Text('Cash Paid')),
                ],
                selected: {_paymentType},
                onSelectionChanged: (s) => setState(() => _paymentType = s.first),
              ),
              if (_paymentType != _origPaymentType) ...[
                const SizedBox(height: 8),
                Text(
                  _paymentType == 'cash_paid'
                      ? 'Will mark the corrected invoice as fully paid and record the collection.'
                      : 'Will reverse the collected payment — the corrected invoice becomes fully outstanding.',
                  style: const TextStyle(fontSize: 11, color: kTextHint),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 14),

          // ── Line items ───────────────────────────────────────────────
          WhiteCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionHeader('PRODUCTS'),
              const SizedBox(height: 10),
              ..._lines.asMap().entries.map((e) => _lineEditor(e.key, e.value)),
            ]),
          ),
          const SizedBox(height: 14),

          // ── Remarks ──────────────────────────────────────────────────
          WhiteCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionHeader('REMARKS'),
              const SizedBox(height: 10),
              TextField(
                controller: _remarksCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Reason for correction / notes',
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),

          if (_err != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_err!, style: const TextStyle(color: kError, fontSize: 13)),
            ),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: canSubmit ? _submit : null,
              icon: _submitting
                  ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
                  : const Icon(Icons.check_circle_outline, size: 18),
              label: Text(_submitting ? 'Processing…' : 'Approve Correction'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kError,
                minimumSize: const Size(double.infinity, 52),
              ),
            ),
          ),
          if (!_hasChanges && !_submitting)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Center(
                child: Text('Change at least one field to enable correction',
                    style: TextStyle(fontSize: 11, color: kTextHint)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _lineEditor(int index, _CorrectionLine l) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kNavy.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(color: kBorderLight),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DropdownButtonFormField<String>(
          initialValue: l.productId,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: 'Product', border: OutlineInputBorder(), isDense: true),
          items: _products
              .map((p) => DropdownMenuItem(
            value: p['id'] as String,
            child: Text(p['name'] as String? ?? '—'),
          ))
              .toList(),
          onChanged: (v) => setState(() {
            l.productId = v;
            l.productName = _products.firstWhere(
                    (p) => p['id'] == v, orElse: () => {})['name'] as String? ??
                l.productName;
          }),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: l.weightCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Weight (kg)', border: OutlineInputBorder(), isDense: true),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: l.birdsCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Bird Count', border: OutlineInputBorder(), isDense: true),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: l.rateCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
              labelText: 'Rate (₹/kg)', border: OutlineInputBorder(), isDense: true),
          onChanged: (_) => setState(() {}),
        ),
      ]),
    );
  }
}

class _LineSnapshot {
  final double weight;
  final int birds;
  final double rate;
  const _LineSnapshot(this.weight, this.birds, this.rate);
}