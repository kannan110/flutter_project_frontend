import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/responsive_layout.dart';

// ══════════════════════════════════════════════════════════════════════════
// CREDIT NOTE DETAIL SCREEN
//
// Reuses the existing `credit_notes` table (written by process_return_v2 —
// unmodified) purely as a read-only view, plus a PDF export mirroring the
// same layout/pattern already used by InvoiceDetailScreen. No new RPC.
// ══════════════════════════════════════════════════════════════════════════

class CreditNoteDetailScreen extends StatefulWidget {
  const CreditNoteDetailScreen({super.key, required this.id});
  final String id;
  @override
  State<CreditNoteDetailScreen> createState() => _S();
}

class _S extends State<CreditNoteDetailScreen> {
  final _c = Supabase.instance.client;
  Map<String, dynamic>? _cn;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final data = await _c
          .from('credit_notes')
          .select('*,'
          'retailers(shop_name,owner_name,phone,address),'
          'invoices(invoice_number,invoice_date),'
          'return_entries(reason,return_type,return_date)')
          .eq('id', widget.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      setState(() {
        _cn = data == null ? null : Map<String, dynamic>.from(data);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generatePdf() async {
    if (_cn == null) return;
    final cn = _cn!;
    final retailer = cn['retailers'] as Map<String, dynamic>?;
    final invoice = cn['invoices'] as Map<String, dynamic>?;
    final ret = cn['return_entries'] as Map<String, dynamic>?;
    final date = DateTime.tryParse(cn['credit_date'] as String? ?? '');
    final qty = (cn['quantity_kg'] as num?)?.toDouble() ?? 0;
    final birds = (cn['bird_count'] as num?)?.toInt() ?? 0;
    final rate = (cn['rate_per_kg'] as num?)?.toDouble() ?? 0;
    final total = (cn['total_amount'] as num?)?.toDouble() ?? 0;

    final font = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();
    final doc = pw.Document(theme: pw.ThemeData.withFont(base: font, bold: boldFont));
    const purple = PdfColor.fromInt(0xFF6A1B9A);
    const grey = PdfColor.fromInt(0xFF616161);
    const bgLight = PdfColor.fromInt(0xFFF5F5F5);

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('CREDIT NOTE',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: purple)),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text(cn['credit_number'] as String? ?? '—',
                style: const pw.TextStyle(fontSize: 12, color: grey)),
            if (date != null)
              pw.Text('Date: ${DateFormat('d MMM y').format(date)}',
                  style: const pw.TextStyle(fontSize: 10, color: grey)),
          ]),
        ]),
        pw.SizedBox(height: 12),
        pw.Divider(color: purple),
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(color: bgLight, borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('CUSTOMER', style: pw.TextStyle(fontSize: 9, color: grey, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(retailer?['shop_name'] as String? ?? '—',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            if (retailer?['phone'] != null)
              pw.Text('Phone: ${retailer!['phone']}', style: const pw.TextStyle(fontSize: 10, color: grey)),
            if (invoice != null)
              pw.Text('Against Invoice: ${invoice['invoice_number']}',
                  style: const pw.TextStyle(fontSize: 10, color: grey)),
          ]),
        ),
        pw.SizedBox(height: 16),
        pw.Table(columnWidths: {
          0: const pw.FlexColumnWidth(2),
          1: const pw.FlexColumnWidth(1.5),
          2: const pw.FlexColumnWidth(1.5),
          3: const pw.FlexColumnWidth(2),
        }, children: [
          pw.TableRow(decoration: const pw.BoxDecoration(color: purple), children:
          ['Birds', 'Weight (kg)', 'Rate', 'Amount (₹)'].map((h) => pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(h,
                  style: pw.TextStyle(color: PdfColors.white, fontSize: 9, fontWeight: pw.FontWeight.bold))))
              .toList()),
          pw.TableRow(children: [
            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('$birds')),
            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(qty.toStringAsFixed(2))),
            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('₹${rate.toStringAsFixed(2)}/kg')),
            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('₹${total.toStringAsFixed(2)}')),
          ]),
        ]),
        pw.SizedBox(height: 16),
        if (ret?['reason'] != null)
          pw.Text('Reason: ${ret!['reason']}', style: const pw.TextStyle(fontSize: 11, color: grey)),
        pw.SizedBox(height: 20),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('TOTAL CREDIT: ₹${total.toStringAsFixed(2)}',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: purple)),
        ),
        pw.SizedBox(height: 24),
        pw.Divider(color: grey),
        pw.Text('This credit note reduces the customer\'s outstanding balance by the amount above.',
            style: pw.TextStyle(fontSize: 9, color: grey, fontStyle: pw.FontStyle.italic)),
      ]),
    ));

    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  @override
  Widget build(BuildContext context) => ResponsiveLayout(
    mobile: (_) => _scaffold(),
    desktop: (_) => _scaffold(),
  );

  Widget _scaffold() {
    if (_loading) return const Scaffold(body: LoadingList());
    if (_cn == null) {
      return Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text('Credit note not found')));
    }
    final cn = _cn!;
    final retailer = cn['retailers'] as Map<String, dynamic>?;
    final invoice = cn['invoices'] as Map<String, dynamic>?;
    final ret = cn['return_entries'] as Map<String, dynamic>?;
    final date = DateTime.tryParse(cn['credit_date'] as String? ?? '');
    final qty = (cn['quantity_kg'] as num?)?.toDouble() ?? 0;
    final birds = (cn['bird_count'] as num?)?.toInt() ?? 0;
    final rate = (cn['rate_per_kg'] as num?)?.toDouble() ?? 0;
    final total = (cn['total_amount'] as num?)?.toDouble() ?? 0;

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: Text(cn['credit_number'] as String? ?? 'Credit Note'),
        actions: [
          IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: 'Generate PDF',
              onPressed: _generatePdf),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
              color: const Color(0xFF6A1B9A),
              borderRadius: BorderRadius.circular(kRadiusHero),
              boxShadow: kCardShadow),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('CREDIT NOTE',
                style: TextStyle(fontSize: 10, color: Colors.white60,
                    fontWeight: FontWeight.w700, letterSpacing: 1.5)),
            const SizedBox(height: 4),
            Text(cn['credit_number'] as String? ?? '—',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            if (date != null)
              Text(DateFormat('d MMMM y').format(date),
                  style: const TextStyle(color: Colors.white60, fontSize: 12)),
            const Divider(color: Colors.white24, height: 18),
            Text(retailer?['shop_name'] as String? ?? '—',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
            if (retailer?['phone'] != null)
              Text(retailer!['phone'] as String, style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ]),
        ),
        const SizedBox(height: 14),

        if (invoice != null)
          WhiteCard(
            child: Row(children: [
              const Icon(Icons.receipt_long_outlined, size: 18, color: kTextSub),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Against Invoice: ${invoice['invoice_number']}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              TextButton(
                onPressed: () {
                  // Fetch the invoice id via its number is unnecessary here —
                  // invoices(invoice_number) join doesn't carry id in this
                  // select, so re-query lazily on tap.
                  _openInvoiceByNumber(invoice['invoice_number'] as String);
                },
                child: const Text('View Invoice'),
              ),
            ]),
          ),
        const SizedBox(height: 14),

        WhiteCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionHeader('RETURN DETAILS'),
            const SizedBox(height: 10),
            if (birds > 0) InfoRow('Birds', '$birds'),
            InfoRow('Weight', '${qty.toStringAsFixed(2)} kg'),
            InfoRow('Rate', '₹${rate.toStringAsFixed(2)} per kg'),
            if (ret?['reason'] != null) InfoRow('Reason', ret!['reason'] as String),
            if (ret?['return_type'] != null)
              InfoRow('Return Type',
                  (ret!['return_type'] as String) == 'same_batch' ? 'Same Batch' : 'Old Stock'),
            const Divider(height: 18),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Total Credit',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              Text(Fmt.amount(total),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF6A1B9A))),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(kRadiusCard)),
          child: const Row(children: [
            Icon(Icons.check_circle_outline, size: 16, color: Colors.green),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                  'This credit note has already reduced the customer\'s outstanding balance.',
                  style: TextStyle(fontSize: 12, color: kTextSub)),
            ),
          ]),
        ),
      ]),
    );
  }

  Future<void> _openInvoiceByNumber(String invoiceNumber) async {
    try {
      final row = await _c
          .from('invoices')
          .select('id')
          .eq('invoice_number', invoiceNumber)
          .maybeSingle();
      final id = row?['id'] as String?;
      if (id != null && mounted) {
        context.push(R.invoiceDetailPath(id));
      }
    } catch (_) {}
  }
}