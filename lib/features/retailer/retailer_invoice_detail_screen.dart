import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../core/util/weight_calc.dart';

// ══════════════════════════════════════════════════════════════════════════
// RETAILER INVOICE DETAIL — read-only view for a retailer's own invoice.
//
// Reuses get_invoice_detail exactly as the trader-side InvoiceDetailScreen
// does — same RPC, same 'invoice'/'items' shape, same rate_label strings
// already computed server-side. That RPC now requires the caller to be
// either the invoice's trader_admin or the invoice's own retailer (added
// as part of this feature) — nothing here duplicates that authorization
// or any billing/rate calculation; this file is presentation only.
//
// No PDF/edit/correction actions here (those are trader-only actions) —
// this is intentionally a simpler, read-only counterpart, not a shared
// widget with the trader screen, since the trader screen's PDF-export and
// Correct Invoice actions have no place in a customer-facing view.
// ══════════════════════════════════════════════════════════════════════════
class RetailerInvoiceDetailScreen extends StatefulWidget {
  const RetailerInvoiceDetailScreen({super.key, required this.invoiceId});
  final String invoiceId;

  @override
  State<RetailerInvoiceDetailScreen> createState() => _RetailerInvoiceDetailScreenState();
}

class _RetailerInvoiceDetailScreenState extends State<RetailerInvoiceDetailScreen> {
  final _c = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _invoice;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final res = await _c.rpc('get_invoice_detail',
          params: {'p_invoice_id': widget.invoiceId}).timeout(const Duration(seconds: 12));
      final data = (res as Map?)?.cast<String, dynamic>();
      if (mounted) {
        setState(() {
          _invoice = (data?['invoice'] as Map?)?.cast<String, dynamic>();
          _items = List<Map<String, dynamic>>.from(data?['items'] as List? ?? []);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString().replaceAll('Exception: ', '').replaceAll('PostgrestException: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: Text(_invoice?['invoice_number'] as String? ?? 'Invoice'),
      ),
      body: _loading
          ? const LoadingList()
          : _error != null
          ? Center(child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(_error!, style: const TextStyle(color: kError), textAlign: TextAlign.center)))
          : _invoice == null
          ? const EmptyState(icon: Icons.receipt_long_outlined, message: 'Invoice not found')
          : _body(),
    );
  }

  Widget _body() {
    final inv = _invoice!;
    final total     = (inv['total_amount']     as num?)?.toDouble() ?? 0;
    final collected = (inv['collected_amount']  as num?)?.toDouble() ?? 0;
    final balance   = (inv['balance_amount']    as num?)?.toDouble() ?? 0;
    final subtotal  = (inv['subtotal_amount']   as num?)?.toDouble() ?? total;
    final discount  = (inv['discount_amount']   as num?)?.toDouble() ?? 0;
    final invDate   = DateTime.tryParse(inv['invoice_date'] as String? ?? '');
    final isPaid    = balance <= 0;
    final boxCount   = (inv['box_count']       as num?)?.toInt();
    final grossWt    = (inv['gross_weight_kg'] as num?)?.toDouble();
    final emptyWt    = (inv['empty_weight_kg'] as num?)?.toDouble();
    final hasWeightBreakdown = boxCount != null || grossWt != null || emptyWt != null;

    return RefreshIndicator(onRefresh: _load, child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [kNavy, kNavyMid],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(kRadiusHero)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(inv['company_name'] as String? ?? '',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white)),
                const SizedBox(height: 4),
                Text(inv['invoice_number'] as String? ?? '—',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: kGoldLight)),
                const SizedBox(height: 4),
                if (invDate != null)
                  Text(DateFormat('d MMM yyyy').format(invDate),
                      style: const TextStyle(fontSize: 12, color: Color(0xFFB4C6F4))),
              ])),
          const SizedBox(height: 12),

          // Payment status banner — clearly separate from the amount
          // figures below, per the "payment status" requirement.
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                  color: (isPaid ? Colors.green : Colors.orange).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(color: (isPaid ? Colors.green : Colors.orange).withValues(alpha: 0.3))),
              child: Row(children: [
                Icon(isPaid ? Icons.check_circle_outline : Icons.pending_outlined,
                    size: 18, color: isPaid ? Colors.green : Colors.orange),
                const SizedBox(width: 8),
                Text(isPaid ? 'Paid in Full' : 'Outstanding: ${Fmt.amount(balance)}',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                        color: isPaid ? Colors.green.shade700 : Colors.orange.shade700)),
              ])),

          // Corrected-invoice reference — same field the trader side
          // already stores (corrected_from_invoice_id), just surfaced
          // here for the first time on the retailer side.
          if (inv['corrected_from_invoice_id'] != null) ...[
            const SizedBox(height: 8),
            Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(kRadiusCard),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3))),
                child: const Row(children: [
                  Icon(Icons.info_outline, size: 14, color: Colors.brown),
                  SizedBox(width: 8),
                  Expanded(child: Text(
                      'This invoice was corrected from an earlier version. The details below reflect the current, corrected invoice.',
                      style: TextStyle(fontSize: 11, color: Colors.brown))),
                ])),
          ],

          const SizedBox(height: 16),
          const Text('PRODUCTS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: kNavy, letterSpacing: 0.6)),
          const SizedBox(height: 8),
          ..._items.map((it) {
            final weight = (it['weight_kg'] as num?)?.toDouble() ?? 0;
            final birds  = (it['bird_count'] as num?)?.toInt() ?? 0;
            final lineTotal = (it['line_total'] as num?)?.toDouble() ?? 0;
            return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: kSurface,
                    borderRadius: BorderRadius.circular(kRadiusCard),
                    border: Border.all(color: kBorderLight), boxShadow: kCardShadow),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(it['product_name'] as String? ?? '—',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
                    Text(Fmt.amount(lineTotal),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kPrimary)),
                  ]),
                  const SizedBox(height: 4),
                  Text('${birds > 0 ? "$birds birds · " : ""}${weight.toStringAsFixed(2)} kg',
                      style: const TextStyle(fontSize: 11, color: kTextSub)),
                  if (it['rate_label'] != null)
                    Text(it['rate_label'] as String,
                        style: const TextStyle(fontSize: 10, color: kTextHint)),
                ]));
          }),

          // Optional Box Count / Gross / Empty / Net Weight — same
          // conditional display rule as the trader invoice screen (only
          // shown when at least one value exists).
          if (hasWeightBreakdown) ...[
            const SizedBox(height: 4),
            Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: kBgPage,
                    borderRadius: BorderRadius.circular(kRadiusCard),
                    border: Border.all(color: kBorderLight)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (boxCount != null) _row('Box Count', '$boxCount'),
                  if (grossWt != null) _row('Gross Weight', '${grossWt.toStringAsFixed(2)} kg'),
                  if (emptyWt != null) _row('Empty Weight', '${emptyWt.toStringAsFixed(2)} kg'),
                  if (grossWt != null && emptyWt != null)
                    _row('Net Weight', '${WeightCalc.net(grossWt, emptyWt).toStringAsFixed(2)} kg'),
                ])),
          ],

          const SizedBox(height: 16),
          const Text('SUMMARY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: kNavy, letterSpacing: 0.6)),
          const SizedBox(height: 8),
          Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: kSurface,
                  borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(color: kBorderLight), boxShadow: kCardShadow),
              child: Column(children: [
                _row('Subtotal', Fmt.amount(subtotal)),
                if (discount > 0) _row('Discount', '−${Fmt.amount(discount)}'),
                const Divider(height: 18),
                _row('Total Amount', Fmt.amount(total), bold: true),
                _row('Collected', Fmt.amount(collected)),
                _row('Balance', Fmt.amount(balance), color: balance > 0 ? Colors.orange : Colors.green),
              ])),

          if ((inv['notes'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(height: 16),
            const Text('REMARKS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: kNavy, letterSpacing: 0.6)),
            const SizedBox(height: 8),
            Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: kSurface,
                    borderRadius: BorderRadius.circular(kRadiusCard),
                    border: Border.all(color: kBorderLight)),
                child: Text(inv['notes'] as String, style: const TextStyle(fontSize: 12, color: kTextSub))),
          ],
          const SizedBox(height: 24),
        ]));
  }

  Widget _row(String label, String value, {bool bold = false, Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(fontSize: 12, color: color ?? kTextSub,
            fontWeight: bold ? FontWeight.w800 : FontWeight.normal)),
        Text(value, style: TextStyle(fontSize: bold ? 15 : 13, color: color ?? kTextMain,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w700)),
      ]));
}