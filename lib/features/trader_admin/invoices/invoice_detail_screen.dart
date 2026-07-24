import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/responsive_layout.dart';

// ══════════════════════════════════════════════════════════════════════════════
// INVOICE DETAIL SCREEN — Phase 4
// Uses get_invoice_detail RPC → carries full rate snapshot from invoice_items
// Shows: rate_label, base_rate, adjustment breakdown, zone name
// Falls back gracefully for legacy invoices (no invoice_items rows)
// ══════════════════════════════════════════════════════════════════════════════

class InvoiceDetailScreen extends StatefulWidget {
  const InvoiceDetailScreen({super.key, required this.id});
  final String id;
  @override
  State<InvoiceDetailScreen> createState() => _S();
}

class _S extends State<InvoiceDetailScreen> {
  final _c = Supabase.instance.client;
  Map<String, dynamic>? _inv;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  // ★ NEW: Invoice Correction feature — the RPC-exposed link is already
  // returned by get_invoice_detail (via `i.*`), so `_inv['corrected_from_invoice_id']`
  // needs no extra query. The reverse direction (which NEW invoice superseded
  // THIS one, if any) has no RPC support and isn't needed elsewhere, so it's
  // fetched with a small, targeted direct table read — no RPC change required.
  Map<String, dynamic>? _supersededBy; // {id, invoice_number} — set only if this invoice was cancelled-and-replaced
  Map<String, dynamic>? _correctedFrom; // {id, invoice_number} — set only if this invoice IS a replacement

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      // Phase 4: single RPC carries invoice + items with full snapshot
      final raw = await _c
          .rpc('get_invoice_detail', params: {'p_invoice_id': widget.id})
          .timeout(const Duration(seconds: 10));
      final data = raw as Map<String, dynamic>?;
      final inv = data?['invoice'] as Map<String, dynamic>?;
      final itemsRaw = data?['items'];

      List<Map<String, dynamic>> items = [];
      if (itemsRaw is List) {
        items = itemsRaw.map((i) => Map<String, dynamic>.from(i as Map)).toList();
      } else if (itemsRaw is String) {
        // JSON string fallback
        items = [];
      }

      // Legacy fallback: if no invoice_items, load from order_items
      if (items.isEmpty && inv?['order_id'] != null) {
        try {
          final raw2 = await _c
              .from('order_items')
              .select('id,bird_count,avg_weight_per_bird,total_weight,rate_per_kg,line_total,master_products(name,unit)')
              .eq('order_id', inv!['order_id'] as String)
              .order('created_at');
          final list = raw2 as List? ?? [];
          items = list.map((i) {
            final m = Map<String, dynamic>.from(i as Map);
            final mp = m['master_products'] as Map<String, dynamic>?;
            return {
              'product_name':    mp?['name'] ?? 'Product',
              'bird_count':      m['bird_count'],
              'weight_kg':       m['total_weight'],
              'rate_per_kg':     m['rate_per_kg'],
              'applied_rate':    m['rate_per_kg'],
              'base_rate':       m['rate_per_kg'],
              'adjustment_type': 'fixed',
              'adjustment_value':0,
              'rate_source':     'manual',
              'rate_zone_name':  null,
              'line_total':      m['line_total'],
              'rate_label':      '₹${(m['rate_per_kg'] as num?)?.toStringAsFixed(2)}/kg',
            };
          }).toList();
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _inv = inv;
        _items = items;
        _loading = false;
      });

      // ★ NEW: resolve correction links (best-effort, non-blocking failures)
      if (inv != null) {
        final correctedFromId = inv['corrected_from_invoice_id'] as String?;
        if (correctedFromId != null) {
          try {
            final r = await _c
                .from('invoices')
                .select('id,invoice_number')
                .eq('id', correctedFromId)
                .maybeSingle();
            if (mounted && r != null) {
              setState(() => _correctedFrom = Map<String, dynamic>.from(r));
            }
          } catch (_) {}
        }
        if (inv['status'] == 'cancelled') {
          try {
            final r = await _c
                .from('invoices')
                .select('id,invoice_number')
                .eq('corrected_from_invoice_id', widget.id)
                .maybeSingle();
            if (mounted && r != null) {
              setState(() => _supersededBy = Map<String, dynamic>.from(r));
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _hasItems => _items.isNotEmpty;
  bool get _isMultiItem => _items.length >= 2;

  // ── Rate badge display helper ────────────────────────────────────────────
  Widget _rateBadge(Map<String, dynamic> item) {
    final adjType  = item['adjustment_type'] as String? ?? 'fixed';
    final adjValue = (item['adjustment_value'] as num?)?.toDouble() ?? 0;
    final baseRate = (item['base_rate'] as num?)?.toDouble();
    final applied  = (item['applied_rate'] as num?)?.toDouble() ?? 0;
    final zoneName = item['rate_zone_name'] as String?;
    final label    = item['rate_label'] as String?;

    // No adjustment — simple display
    if (adjType == 'fixed' || adjType == 'manual' || adjType == 'none' ||
        adjValue == 0 || baseRate == null) {
      return Text(
        label ?? '₹${applied.toStringAsFixed(2)}/kg',
        style: const TextStyle(fontSize: 11, color: kTextSub),
      );
    }

    // Adjustment types — show breakdown
    final (sign, color) = switch (adjType) {
      'flat_discount' || 'pct_discount' => ('−', kError),
      'flat_premium'  || 'pct_premium'  => ('+', kSuccess),
      _                                  => ('', kTextSub),
    };
    final adjStr = adjType.startsWith('pct') ? '$adjValue%' : '₹${adjValue.toStringAsFixed(2)}';

    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (zoneName != null) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: kNavy.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(kRadiusChip),
          ),
          child: Text(zoneName,
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: kNavy)),
        ),
        const SizedBox(width: 4),
      ],
      Text('₹${baseRate.toStringAsFixed(2)}',
          style: const TextStyle(fontSize: 11, color: kTextSub)),
      Text(' $sign$adjStr ',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      Text('= ₹${applied.toStringAsFixed(2)}/kg',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: kNavy)),
    ]);
  }

  // ── WhatsApp text builder ──────────────────────────────────────────────────
  String _buildWhatsAppText() {
    final inv    = _inv!;
    final date   = DateTime.tryParse(inv['invoice_date'] as String? ?? '');
    final total  = (inv['total_amount']     as num?)?.toDouble() ?? 0;
    final coll   = (inv['collected_amount'] as num?)?.toDouble() ?? 0;
    final bal    = (inv['balance_amount']   as num?)?.toDouble() ?? 0;
    final invNum = inv['invoice_number'] as String? ?? '—';
    final dateStr = date != null ? DateFormat('d MMM y').format(date) : '—';
    final company = inv['company_name'] as String? ?? 'Rooster Trader';
    final shop    = inv['shop_name']    as String? ?? '—';

    final buf = StringBuffer();
    buf.writeln('🐓 *$company*');
    buf.writeln();
    buf.writeln('📄 *Invoice: $invNum*');
    buf.writeln('📅 Date: $dateStr');
    buf.writeln();
    buf.writeln('👤 Customer: $shop');
    buf.writeln();
    buf.writeln('────────────────────');

    if (_hasItems) {
      for (final item in _items) {
        final name    = item['product_name']  as String? ?? 'Product';
        final birds   = (item['bird_count']   as num?)?.toInt()    ?? 0;
        final wt      = (item['weight_kg']    as num?)?.toDouble() ?? 0;
        final rate    = (item['applied_rate'] as num?)?.toDouble() ?? 0;
        final lineT   = (item['line_total']   as num?)?.toDouble() ?? (wt * rate);
        final rLabel  = item['rate_label']    as String? ?? '₹${rate.toStringAsFixed(2)}/kg';

        buf.writeln('🐔 *$name*');
        if (birds > 0) buf.writeln('   Birds: $birds');
        buf.writeln('   Weight: ${wt.toStringAsFixed(2)} kg');
        buf.writeln('   Rate:   $rLabel');
        buf.writeln('   Amount: ${Fmt.amount(lineT)}');
        buf.writeln();
      }
    } else {
      final kg   = (inv['quantity_kg']  as num?)?.toDouble() ?? 0;
      final rate = (inv['price_per_kg'] as num?)?.toDouble() ?? 0;
      final birds = (inv['bird_count'] as num?)?.toInt() ?? 0;
      if (birds > 0) buf.writeln('🐔 Birds: $birds');
      buf.writeln('⚖️  Weight: ${kg.toStringAsFixed(2)} kg');
      buf.writeln('💰 Rate:   ₹${rate.toStringAsFixed(2)}/kg');
      buf.writeln();
    }

    buf.writeln('────────────────────');
    buf.writeln('💵 Total:     ${Fmt.amount(total)}');
    buf.writeln('✅ Collected: ${Fmt.amount(coll)}');
    buf.writeln('⏳ Balance:   ${Fmt.amount(bal)}');
    buf.writeln('────────────────────');
    buf.writeln();
    buf.writeln(bal > 0 ? '⚠️ Balance due: ${Fmt.amount(bal)}' : '✅ Fully paid');
    buf.writeln();
    buf.writeln('_Rooster Trader PTOS_');
    return buf.toString();
  }

  // ── PDF ───────────────────────────────────────────────────────────────────
  Future<void> _generatePdf() async {
    if (_inv == null) return;
    final inv   = _inv!;
    final date  = DateTime.tryParse(inv['invoice_date'] as String? ?? '');
    final total = (inv['total_amount']     as num?)?.toDouble() ?? 0;
    final coll  = (inv['collected_amount'] as num?)?.toDouble() ?? 0;
    final bal   = (inv['balance_amount']   as num?)?.toDouble() ?? 0;
    final disc  = (inv['discount_amount']  as num?)?.toDouble() ?? 0;
    final sub   = (inv['subtotal_amount']  as num?)?.toDouble() ?? total;
    final num_  = inv['invoice_number'] as String? ?? 'INVOICE';

    final font     = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();
    final doc      = pw.Document(theme: pw.ThemeData.withFont(base: font, bold: boldFont));

    final primary = PdfColor.fromInt(0xFFBF1B2C);
    final grey    = PdfColor.fromInt(0xFF616161);
    final bgLight = PdfColor.fromInt(0xFFF5F5F5);
    final green   = PdfColor.fromInt(0xFF1B5E20);

    // ★ NEW: cancelled invoices get a diagonal watermark rather than a
    // blocked PDF — traders may still want a copy for their own records,
    // clearly marked so it's never mistaken for the active invoice.
    final isCancelled = inv['status'] == 'cancelled';

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => pw.Stack(children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Header
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(inv['company_name'] as String? ?? 'Rooster Trader',
                    style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: primary)),
                if (inv['trader_phone'] != null)
                  pw.Text('Phone: ${inv['trader_phone']}',
                      style: pw.TextStyle(fontSize: 10, color: grey)),
                if (inv['gst_number'] != null)
                  pw.Text('GST: ${inv['gst_number']}',
                      style: pw.TextStyle(fontSize: 10, color: grey)),
              ]),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text('TAX INVOICE',
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: primary)),
                pw.Text(num_, style: pw.TextStyle(fontSize: 11, color: grey)),
                if (date != null)
                  pw.Text('Date: ${DateFormat('d MMM y').format(date)}',
                      style: pw.TextStyle(fontSize: 10, color: grey)),
              ]),
            ]),
            pw.SizedBox(height: 12),
            pw.Divider(color: primary),
            pw.SizedBox(height: 10),

            // Bill To
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(color: bgLight, borderRadius: pw.BorderRadius.circular(4)),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('BILL TO', style: pw.TextStyle(fontSize: 9, color: grey, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text(inv['shop_name'] as String? ?? '—',
                    style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                if (inv['owner_name'] != null)
                  pw.Text(inv['owner_name'] as String, style: pw.TextStyle(fontSize: 10, color: grey)),
                if (inv['retailer_phone'] != null)
                  pw.Text('Phone: ${inv['retailer_phone']}', style: pw.TextStyle(fontSize: 10, color: grey)),
              ]),
            ),
            pw.SizedBox(height: 16),

            // Items table
            pw.Table(columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(1.2),
              2: const pw.FlexColumnWidth(1.8),
              3: const pw.FlexColumnWidth(1.8),
              4: const pw.FlexColumnWidth(2),
            }, children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: primary),
                children: ['Product', 'Birds', 'Weight (kg)', 'Rate', 'Amount (₹)'].map((h) =>
                    pw.Padding(padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(h, style: pw.TextStyle(
                            color: PdfColors.white, fontSize: 9, fontWeight: pw.FontWeight.bold)))).toList(),
              ),
              if (_hasItems)
                ..._items.map((item) {
                  final birds  = (item['bird_count']   as num?)?.toInt()    ?? 0;
                  final wt     = (item['weight_kg']    as num?)?.toDouble() ?? 0;
                  final applied = (item['applied_rate'] as num?)?.toDouble() ?? 0;
                  final lineT  = (item['line_total']   as num?)?.toDouble() ?? (wt * applied);
                  final rLabel = item['rate_label']    as String? ?? '₹${applied.toStringAsFixed(2)}/kg';
                  final name   = item['product_name']  as String? ?? '—';
                  return pw.TableRow(children: [
                    _pdfCell(name, PdfColors.white),
                    _pdfCell(birds > 0 ? '$birds' : '—', PdfColors.white),
                    _pdfCell(wt.toStringAsFixed(2), PdfColors.white),
                    _pdfCell(rLabel, PdfColors.white, fontSize: 8),
                    _pdfCell('₹${lineT.toStringAsFixed(2)}', PdfColors.white),
                  ]);
                })
              else
                pw.TableRow(children: [
                  _pdfCell(inv['product_name'] as String? ?? 'Broiler', bgLight),
                  _pdfCell('${(inv['bird_count'] as num?)?.toInt() ?? 0}', bgLight),
                  _pdfCell('${(inv['quantity_kg'] as num?)?.toStringAsFixed(2) ?? '0'}', bgLight),
                  _pdfCell('₹${(inv['price_per_kg'] as num?)?.toStringAsFixed(2) ?? '0'}/kg', bgLight),
                  _pdfCell('₹${sub.toStringAsFixed(2)}', bgLight),
                ]),
            ]),
            pw.SizedBox(height: 16),

            // Totals
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Container(width: 220, child: pw.Column(children: [
                if (disc > 0) ...[
                  _pdfTotRow('Subtotal', '₹${sub.toStringAsFixed(2)}', grey),
                  _pdfTotRow('Discount', '-₹${disc.toStringAsFixed(2)}', grey),
                ],
                pw.Divider(color: grey),
                _pdfTotRow('TOTAL', '₹${total.toStringAsFixed(2)}', primary, bold: true, size: 13),
                _pdfTotRow('Collected', '₹${coll.toStringAsFixed(2)}', green),
                pw.Divider(color: PdfColor.fromInt(0xFFE57373)),
                _pdfTotRow('BALANCE DUE', '₹${bal.toStringAsFixed(2)}',
                    bal > 0 ? PdfColor.fromInt(0xFFE65100) : green, bold: true, size: 12),
              ])),
            ),
            pw.SizedBox(height: 20),

            // Footer
            pw.Divider(color: grey),
            pw.SizedBox(height: 6),
            pw.Text('Thank you for your business!',
                style: pw.TextStyle(fontSize: 10, color: grey, fontStyle: pw.FontStyle.italic)),
            pw.Text('Generated by Rooster Trader • ${DateFormat('d MMM y, h:mm a').format(DateTime.now())}',
                style: pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFF9E9E9E))),
          ],
        ),
        if (isCancelled)
          pw.Positioned.fill(
            child: pw.Center(
              child: pw.Transform.rotate(
                angle: 0.5,
                child: pw.Text('CANCELLED',
                    style: pw.TextStyle(
                        fontSize: 72,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor(0.90, 0.22, 0.21, 0.28))),
              ),
            ),
          ),
      ]),
    ));

    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  static pw.Widget _pdfCell(String text, PdfColor bg, {double fontSize = 10}) =>
      pw.Padding(padding: const pw.EdgeInsets.all(6),
          child: pw.Text(text, style: pw.TextStyle(fontSize: fontSize)));

  static pw.Widget _pdfTotRow(String label, String value, PdfColor color,
      {bool bold = false, double size = 11}) =>
      pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(label, style: pw.TextStyle(fontSize: size, color: color,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            pw.Text(value, style: pw.TextStyle(fontSize: size, color: color,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ]));

  // ── Share ─────────────────────────────────────────────────────────────────
  Future<void> _shareWhatsApp() async {
    // ★ NEW: a cancelled invoice must never be shared as if it were active —
    // only the latest approved invoice should reach a customer.
    if (_inv?['status'] == 'cancelled') {
      if (_supersededBy != null) {
        showError(context,
            'This invoice was cancelled and replaced by ${_supersededBy!['invoice_number']}. Share that one instead.');
      } else {
        showError(context, 'This invoice was cancelled and cannot be shared.');
      }
      return;
    }
    final text = _buildWhatsAppText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showSuccess(context, 'Invoice copied — paste in WhatsApp ✓');
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('WhatsApp Invoice Ready'),
        content: SingleChildScrollView(
            child: SelectableText(text, style: const TextStyle(fontSize: 13, height: 1.5))),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(),
              child: const Text('Close')),
          ElevatedButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                Navigator.of(ctx, rootNavigator: true).pop();
                if (mounted) showSuccess(context, 'Copied ✓');
              },
              child: const Text('Copy Again')),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  Widget _buildScaffold(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingList());
    if (_inv == null) return Scaffold(
        appBar: AppBar(), body: const Center(child: Text('Invoice not found')));

    final inv   = _inv!;
    final date  = DateTime.tryParse(inv['invoice_date'] as String? ?? '');
    final status = inv['status'] as String? ?? 'draft';
    final total  = (inv['total_amount']     as num?)?.toDouble() ?? 0;
    final coll   = (inv['collected_amount'] as num?)?.toDouble() ?? 0;
    // Cancelled invoices' stored balance_amount is a stale pre-cancellation
    // snapshot (the RPC doesn't rewrite it — the ledger, not this column, is
    // the source of truth for what's actually owed). Nothing is due on a
    // cancelled invoice, so force it to neutral for display.
    final bal    = status == 'cancelled' ? 0.0 : (inv['balance_amount'] as num?)?.toDouble() ?? 0;
    final disc   = (inv['discount_amount']  as num?)?.toDouble() ?? 0;
    final kg     = (inv['quantity_kg']      as num?)?.toDouble() ?? 0;
    final birds  = (inv['bird_count']       as num?)?.toInt() ?? 0;
    final rate   = (inv['price_per_kg']     as num?)?.toDouble() ?? 0;
    final zoneName = inv['zone_name'] as String?;

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: Text(inv['invoice_number'] as String? ?? 'Invoice'),
        actions: [
          IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: 'Generate PDF',
              onPressed: _generatePdf),
          IconButton(icon: const Icon(Icons.share), onPressed: _shareWhatsApp),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: [

        // ── Header card ────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
              color: kPrimary,
              borderRadius: BorderRadius.circular(kRadiusHero),
              boxShadow: kCardShadow),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('INVOICE', style: TextStyle(fontSize: 10,
                  color: Colors.white60, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
              StatusBadge(status, Colors.white70),
            ]),
            const SizedBox(height: 4),
            Text(inv['invoice_number'] as String? ?? '—',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            if (date != null)
              Text(DateFormat('d MMMM y').format(date),
                  style: const TextStyle(color: Colors.white60, fontSize: 12)),
            const Divider(color: Colors.white24, height: 18),
            Text(inv['shop_name'] as String? ?? '—',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
            if (inv['owner_name'] != null)
              Text(inv['owner_name'] as String,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            if (inv['retailer_phone'] != null)
              Text(inv['retailer_phone'] as String,
                  style: const TextStyle(color: Colors.white60, fontSize: 12)),
            // Zone chip
            if (zoneName != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(kRadiusChip)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.location_on_outlined, size: 12, color: kGoldLight),
                  const SizedBox(width: 4),
                  Text(zoneName,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kGoldLight)),
                ]),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 14),

        // ── Invoice Correction banners ───────────────────────────────────
        // Cancelled invoice: point to whatever replaced it.
        if (status == 'cancelled')
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
                color: kTextHint.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(kRadiusCard),
                border: Border.all(color: kBorderLight)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: const [
                Icon(Icons.info_outline, size: 16, color: kTextSub),
                SizedBox(width: 6),
                Text('This invoice was corrected.',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: kTextSub)),
              ]),
              if (_supersededBy != null) ...[
                const SizedBox(height: 4),
                Text('Current Invoice: ${_supersededBy!['invoice_number']}',
                    style: const TextStyle(fontSize: 12, color: kTextHint)),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => context.push(R.invoiceDetailPath(_supersededBy!['id'] as String)),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                    label: const Text('Open Corrected Invoice'),
                    style: ElevatedButton.styleFrom(backgroundColor: kNavy),
                  ),
                ),
              ],
            ]),
          ),

        // This invoice IS a replacement — link back to the original.
        if (_correctedFrom != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
                color: kGold.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(kRadiusCard),
                border: Border.all(color: kGold.withValues(alpha: 0.3))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: const [
                Icon(Icons.history_rounded, size: 16, color: kGold),
                SizedBox(width: 6),
                Text('Corrected From', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: kGold)),
              ]),
              const SizedBox(height: 4),
              Text(_correctedFrom!['invoice_number'] as String? ?? '—',
                  style: const TextStyle(fontSize: 12, color: kTextSub)),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context.push(R.invoiceDetailPath(_correctedFrom!['id'] as String)),
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: const Text('Open Original Invoice'),
                ),
              ),
            ]),
          ),

        // Correct Invoice — only for a currently-active, approved invoice.
        // Hidden for cancelled, draft, and rejected.
        if (status == 'approved')
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  // The correction screen navigates onward to the new
                  // invoice via pushReplacement on success (not a plain
                  // pop), so the value this push resolves to isn't a
                  // reliable "did it change" signal either way. Reloading
                  // unconditionally on return is cheap and always correct —
                  // if nothing changed, _load() just re-fetches the same data.
                  await context.push<bool>(R.invoiceCorrectionPath(widget.id));
                  if (mounted) _load();
                },
                icon: const Icon(Icons.edit_note_rounded, size: 18),
                label: const Text('Correct Invoice'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: kError,
                    side: const BorderSide(color: kError),
                    padding: const EdgeInsets.symmetric(vertical: 13)),
              ),
            ),
          ),

        // ── Item breakdown ─────────────────────────────────────────────
        WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: SectionHeader('BILL DETAILS')),
            if (_isMultiItem)
              Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: kNavy.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text('${_items.length} products',
                      style: const TextStyle(fontSize: 10, color: kNavy, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 10),

          if (_hasItems) ...[
            // Per-item rows with rate breakdown
            ..._items.map((item) {
              final name    = item['product_name']  as String? ?? 'Product';
              final iBirds  = (item['bird_count']   as num?)?.toInt()    ?? 0;
              final iWt     = (item['weight_kg']    as num?)?.toDouble() ?? 0;
              final iTotal  = (item['line_total']   as num?)?.toDouble() ?? 0;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: kNavy.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(kRadiusCard),
                    border: Border.all(color: kBorderLight)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Product badge
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: kNavy.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(name, style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800, color: kNavy)),
                    ),
                  ]),
                  const SizedBox(height: 8),

                  // Stats row
                  Row(children: [
                    if (iBirds > 0) _itemCol('Birds', '$iBirds', kSuccess),
                    _itemCol('Weight', '${iWt.toStringAsFixed(2)} kg', kNavy),
                  ]),
                  const SizedBox(height: 6),

                  // Rate breakdown — the key Phase 4 feature
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: kSurface,
                        borderRadius: BorderRadius.circular(kRadiusInner),
                        border: Border.all(color: kBorderLight)),
                    child: Row(children: [
                      const Icon(Icons.currency_rupee, size: 12, color: kTextHint),
                      const SizedBox(width: 4),
                      Expanded(child: _rateBadge(item)),
                    ]),
                  ),
                  const SizedBox(height: 6),

                  // Line total
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                        color: kNavy.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(
                        '${iWt.toStringAsFixed(2)} kg × '
                            '₹${((item['applied_rate'] as num?)?.toStringAsFixed(2) ?? '0')} = ${Fmt.amount(iTotal)}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w900, color: kNavy)),
                  ),
                ]),
              );
            }),

          ] else ...[
            // Legacy single-product fallback
            if (birds > 0) InfoRow('Birds', '$birds'),
            InfoRow('Weight', '${kg.toStringAsFixed(3)} kg'),
            InfoRow('Rate', '₹${rate.toStringAsFixed(2)} per kg'),
            if (disc > 0) InfoRow('Discount', '−${Fmt.amount(disc)}'),
          ],

          // Summary totals
          const Divider(height: 18),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Total Bill',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            Text(Fmt.amount(total),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: kPrimary)),
          ]),
          if (disc > 0) ...[
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Discount', style: TextStyle(fontSize: 12, color: kTextSub)),
              Text('−${Fmt.amount(disc)}',
                  style: const TextStyle(fontSize: 12, color: kSuccess, fontWeight: FontWeight.w600)),
            ]),
          ],
          if (coll > 0) ...[
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Collected', style: TextStyle(fontSize: 12, color: kTextSub)),
              Text(Fmt.amount(coll),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kSuccess)),
            ]),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Balance Due',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              Text(Fmt.amount(bal),
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: bal > 0 ? Colors.orange : kSuccess)),
            ]),
          ],
          if (bal <= 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  color: kSuccess.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8)),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.check_circle_outline, color: kSuccess, size: 16),
                SizedBox(width: 6),
                Text('Fully Paid', style: TextStyle(color: kSuccess, fontWeight: FontWeight.w700)),
              ]),
            ),
          ],
        ])),
        const SizedBox(height: 14),

        // ── WhatsApp share ─────────────────────────────────────────────
        ElevatedButton.icon(
            onPressed: _shareWhatsApp,
            icon: const Icon(Icons.share_outlined, size: 18),
            label: const Text('Copy Invoice for WhatsApp'),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                minimumSize: const Size(double.infinity, 48))),
        const SizedBox(height: 6),
        const Center(child: Text(
            'Copies formatted invoice to clipboard — paste in WhatsApp',
            style: TextStyle(fontSize: 11, color: kTextHint),
            textAlign: TextAlign.center)),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _itemCol(String label, String value, Color color) =>
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 9, color: kTextHint)),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
      ]));

  @override
  Widget build(BuildContext context) => ResponsiveLayout(
    mobile:  (_) => _buildScaffold(context),
    desktop: (_) => _buildScaffold(context),
  );
}