import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:rooster_trader/features/trader_admin/reports/report_dataset.dart';

// ─────────────────────────────────────────────────────────────────────────────
// REPORT PDF GENERATOR
// Generates professional A4 PDF reports for all 11 report types.
// Uses the same `get_report_data` JSON structure from the reports hub.
// ─────────────────────────────────────────────────────────────────────────────

class ReportPdfGenerator {
  // Brand colors
  static const _primary  = PdfColor.fromInt(0xFFBF1B2C);
  static const _dark     = PdfColor.fromInt(0xFF1A1A2E);
  static const _subText  = PdfColor.fromInt(0xFF6B7280);
  static const _border   = PdfColor.fromInt(0xFFE8E8EC);
  static const _bgLight  = PdfColor.fromInt(0xFFF5F5F7);
  static const _green    = PdfColor.fromInt(0xFF1B5E20);
  static const _orange   = PdfColor.fromInt(0xFFE65100);
  static const _blue     = PdfColor.fromInt(0xFF1565C0);
  static const _purple   = PdfColor.fromInt(0xFF6A1B9A);
  static const _red      = PdfColor.fromInt(0xFFC62828);

  // ─── Generic entry: build a PDF from a ReportDataSet ─────────────────────
  // This is the NEW canonical path — every report's Card View, Table View,
  // and PDF now come from the exact same ReportDataSet, so they can never
  // disagree. Reuses the existing branded _header/_footer/_secTitle/_table/
  // _kpiRow helpers below rather than duplicating layout logic.
  static Future<pw.Document> _buildDataSetDoc({
    required ReportDataSet dataSet,
    required String companyName,
  }) async {
    final font = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();
    final doc  = pw.Document(theme: pw.ThemeData.withFont(base: font, bold: bold));
    final from = dataSet.fromDate ?? DateTime.now();
    final to   = dataSet.toDate   ?? DateTime.now();

    doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => _header(companyName, dataSet.title, from, to),
        footer: (_) => _footer(),
        build: (_) => [
          if (dataSet.summary.isNotEmpty) ...[
            _secTitle('SUMMARY'),
            _kpiRow(dataSet.summary
                .map((s) => _KpiCell(s.label, s.value, _primary))
                .toList()),
            pw.SizedBox(height: 6),
          ],
          _secTitle('DETAILS (${dataSet.rowCount} rows)'),
          if (dataSet.isEmpty)
            pw.Text('No data for the selected range.',
                style: pw.TextStyle(fontSize: 9, color: _subText))
          else
            _table(
              headers: dataSet.headers,
              rows: dataSet.rows,
              totals: dataSet.totals,
              bold: dataSet.highlightColumns,
            ),
        ]));
    return doc;
  }

  /// Download / Print entry point — opens the native print/share/save
  /// preview sheet (covers "Download PDF" and "Print" from the same,
  /// well-supported cross-platform API).
  static Future<void> generateFromDataSetAndShow({
    required BuildContext context,
    required ReportDataSet dataSet,
    required String companyName,
  }) async {
    final doc = await _buildDataSetDoc(dataSet: dataSet, companyName: companyName);
    final from = dataSet.fromDate ?? DateTime.now();
    await Printing.layoutPdf(
      onLayout: (fmt) async => doc.save(),
      name: '${companyName}_${dataSet.title.replaceAll(' ', '_')}_'
          '${DateFormat('yyyyMMdd').format(from)}.pdf',
    );
  }

  /// Explicit share-sheet entry point (mobile — WhatsApp, email, etc.).
  static Future<void> shareFromDataSet({
    required ReportDataSet dataSet,
    required String companyName,
  }) async {
    final doc = await _buildDataSetDoc(dataSet: dataSet, companyName: companyName);
    final bytes = await doc.save();
    final from = dataSet.fromDate ?? DateTime.now();
    await Printing.sharePdf(
      bytes: bytes,
      filename: '${companyName}_${dataSet.title.replaceAll(' ', '_')}_'
          '${DateFormat('yyyyMMdd').format(from)}.pdf',
    );
  }

  // ─── Main entry: build and show PDF preview (legacy, per-report-type) ────
  static Future<void> generateAndShow({
    required BuildContext context,
    required Map<String,dynamic> reportData,
    required String reportLabel,
    required String companyName,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final font     = await PdfGoogleFonts.notoSansRegular();
    final bold     = await PdfGoogleFonts.notoSansBold();
    final doc      = pw.Document(theme: pw.ThemeData.withFont(base: font, bold: bold));
    final reportKey= reportData['report'] as String? ?? '';

    // Build pages based on report type
    _addPages(doc, reportData, reportKey, reportLabel, companyName, fromDate, toDate);

    // Show in-app PDF preview with share + print
    await Printing.layoutPdf(
      onLayout: (fmt) async => doc.save(),
      name: '${companyName}_${reportLabel.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(fromDate)}.pdf',
    );
  }

  // ─── Page builder router ─────────────────────────────────────────────────
  static void _addPages(
      pw.Document doc,
      Map<String,dynamic> data,
      String key,
      String label,
      String company,
      DateTime from,
      DateTime to,
      ) {
    final s     = (data['summary'] as Map<String,dynamic>?) ?? {};

    switch (key) {
      case 'daily_summary':        _dailySummaryPdf(doc, s, data, label, company, from, to);
      case 'stock_reconciliation': _stockReconPdf(doc, s, data, label, company, from, to);
      case 'shrinkage':            _shrinkagePdf(doc, s, data, label, company, from, to);
      case 'mortality':            _mortalityPdf(doc, s, data, label, company, from, to);
      case 'delivery_history':     _deliveryHistoryPdf(doc, s, data, label, company, from, to);
      case 'agent_performance':    _agentPerfPdf(doc, data, label, company, from, to);
      case 'shift_audit':          _shiftAuditPdf(doc, data, label, company, from, to);
      case 'expense':              _expensePdf(doc, s, data, label, company, from, to);
      case 'collection':           _collectionPdf(doc, s, data, label, company, from, to);
      case 'retailer_purchase':    _retailerPurchasePdf(doc, s, data, label, company, from, to);
      case 'profitability':        _profitabilityPdf(doc, s, data, label, company, from, to);
    // ── Phase 4/5 UI additions — reuse existing generic builders only ──────
      case 'pnl_statement':         _pnlStatementPdf(doc, s, data, label, company, from, to);
      case 'cash_flow_statement':   _cashFlowStatementPdf(doc, s, data, label, company, from, to);
      case 'supplier_statement':    _supplierStatementPdf(doc, data, label, company, from, to);
      case 'profitability_breakdown': _profitabilityBreakdownPdf(doc, data, label, company, from, to);
      default:                     _genericPdf(doc, s, label, company, from, to);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SHARED LAYOUT HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  // Standard page header with company branding
  static pw.Widget _header(String company, String reportLabel, DateTime from, DateTime to) =>
      pw.Column(children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(company, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _primary)),
            pw.Text('Rooster Trader — Poultry Trading Operations',
                style: const pw.TextStyle(fontSize: 9, color: _subText)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text(reportLabel.toUpperCase(),
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _primary)),
            pw.Text('${DateFormat("d MMM yyyy").format(from)}  to  ${DateFormat("d MMM yyyy").format(to)}',
                style: pw.TextStyle(fontSize: 9, color: _subText)),
            pw.Text('Generated: ${DateFormat("d MMM yyyy, HH:mm").format(DateTime.now())}',
                style: pw.TextStyle(fontSize: 8, color: _subText)),
          ]),
        ]),
        pw.SizedBox(height: 6),
        pw.Divider(color: _primary, thickness: 1.5),
        pw.SizedBox(height: 8),
      ]);

  // Footer
  static pw.Widget _footer() => pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text('Rooster Trader PTOS v2  —  Confidential',
            style: pw.TextStyle(fontSize: 7, color: _subText)),
        pw.Text('This report is system-generated',
            style: pw.TextStyle(fontSize: 7, color: _subText)),
      ]);

  // KPI row: 2 or 4 cells
  static pw.Widget _kpiRow(List<_KpiCell> cells) => pw.Row(
      children: cells.map((c) => pw.Expanded(
          child: pw.Container(
              margin: const pw.EdgeInsets.only(right: 6),
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                  color: _bgLight,
                  borderRadius: pw.BorderRadius.circular(4),
                  border: pw.Border.all(color: _border)),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(c.label, style: pw.TextStyle(fontSize: 8, color: _subText)),
                pw.SizedBox(height: 3),
                pw.Text(c.value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold,
                    color: c.color)),
              ])))).toList());

  // Section title
  static pw.Widget _secTitle(String t) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4, top: 10),
      child: pw.Text(t, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold,
          color: _subText)));

  // Data table
  static pw.Widget _table({
    required List<String> headers,
    required List<List<String>> rows,
    List<String>? totals,
    List<int> bold = const [],
  }) {
    final colWidths = <int, pw.TableColumnWidth>{};
    for (var i = 0; i < headers.length; i++) {
      colWidths[i] = const pw.FlexColumnWidth();
    }

    pw.TableRow buildRow(List<String> cells, {bool isHeader=false, bool isTotals=false}) {
      return pw.TableRow(
          decoration: pw.BoxDecoration(
              color: isHeader  ? _primary
                  : isTotals  ? const PdfColor.fromInt(0xFFBF1B2C).shade(0.85)
                  : null),
          children: cells.asMap().map((i, cell) => MapEntry(i,
              pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  child: pw.Text(cell,
                      style: pw.TextStyle(
                          fontSize: isHeader ? 8 : 9,
                          fontWeight: (isHeader || isTotals || bold.contains(i))
                              ? pw.FontWeight.bold : pw.FontWeight.normal,
                          color: isHeader ? PdfColors.white
                              : isTotals ? _primary
                              : bold.contains(i) ? _dark : _dark))))).values.toList());
    }

    return pw.Table(
        columnWidths: colWidths,
        border: pw.TableBorder.all(color: _border, width: 0.5),
        children: [
          buildRow(headers, isHeader: true),
          ...rows.asMap().map((i, row) => MapEntry(i,
              pw.TableRow(
                  decoration: pw.BoxDecoration(color: i.isOdd ? _bgLight : PdfColors.white),
                  children: row.asMap().map((ci, cell) => MapEntry(ci,
                      pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                          child: pw.Text(cell,
                              style: pw.TextStyle(
                                  fontSize: 9,
                                  fontWeight: bold.contains(ci) ? pw.FontWeight.bold : pw.FontWeight.normal,
                                  color: _dark))))).values.toList()))).values,
          if (totals != null) buildRow(totals, isTotals: true),
        ]);
  }

  // Reconciliation row (waterfall style)
  static pw.Widget _reconRow(String label, String value, PdfColor c) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _border))),
      child: pw.Row(children: [
        pw.Container(width: 3, height: 14, color: c, margin: const pw.EdgeInsets.only(right: 8)),
        pw.Expanded(child: pw.Text(label, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: c))),
        pw.Text(value, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: c)),
      ]));

  // ══════════════════════════════════════════════════════════════════════════
  // 1. DAILY SUMMARY
  // ══════════════════════════════════════════════════════════════════════════
  static void _dailySummaryPdf(pw.Document doc, Map s, Map data,
      String label, String company, DateTime from, DateTime to) {
    final daily = _rowList(data['daily']);
    doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => _header(company, label, from, to),
        footer: (_) => _footer(),
        build: (_) => [
          _kpiRow([
            _KpiCell('Total Revenue',    _amt(s,'total_revenue'),    _primary),
            _KpiCell('Total Collected',  _amt(s,'total_collected'),  _green),
            _KpiCell('Pending',          _amt(s,'total_pending'),    _orange),
            _KpiCell('Outstanding',      _amt(s,'total_outstanding'),_red),
          ]),
          pw.SizedBox(height: 8),
          _kpiRow([
            _KpiCell('DC Birds',   '${_i(s,"total_birds_dc")} birds', _blue),
            _KpiCell('Gross Wt',   '${_f1(s,"total_gross_wt")} kg',   _blue),
            _KpiCell('Tare Wt',    '${_f1(s,"total_tare_wt")} kg',    _subText),
            _KpiCell('Net Del Wt', '${_f1(s,"total_net_wt")} kg',     PdfColor.fromInt(0xFF00695C)),
          ]),
          pw.SizedBox(height: 4),
          pw.Container(
              padding: const pw.EdgeInsets.all(8),
              color: PdfColor.fromInt(0xFF00695C).shade(0.92),
              child: pw.Text(
                  'Net Delivery Weight  =  Gross Weight  -  Cage/Tare Weight',
                  style: pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFF00695C), fontWeight: pw.FontWeight.bold))),
          _secTitle('DAILY BREAKDOWN'),
          _table(
              headers: ['Date','DC Birds','Gross Wt kg','Tare Wt kg','Net Del Wt kg','Revenue (₹)','Collected (₹)','Pending (₹)'],
              rows: daily.map((d) => [
                _fd(d['dt']), '${_i(d,"dc_birds")}',
                _f0(d,'gross_wt'), _f0(d,'tare_wt'), _f0(d,'net_wt'),
                _amt(d,'revenue'), _amt(d,'collected'), _amt(d,'pending'),
              ]).toList(),
              totals: ['TOTAL', '${_i(s,"total_birds_dc")}',
                _f0(s,'total_gross_wt'), _f0(s,'total_tare_wt'), _f0(s,'total_net_wt'),
                _amt(s,'total_revenue'), _amt(s,'total_collected'), _amt(s,'total_pending')],
              bold: [5,6,7]),
        ]));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 2. STOCK RECONCILIATION
  // ══════════════════════════════════════════════════════════════════════════
  static void _stockReconPdf(pw.Document doc, Map s, Map data,
      String label, String company, DateTime from, DateTime to) {
    final daily = _rowList(data['daily']);
    doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => _header(company, label, from, to),
        footer: (_) => _footer(),
        build: (_) => [
          _secTitle('STOCK MOVEMENT WATERFALL'),
          pw.Container(
              decoration: pw.BoxDecoration(border: pw.Border.all(color: _border),
                  borderRadius: pw.BorderRadius.circular(4)),
              child: pw.Column(children: [
                _reconRow('Opening Stock',    '${_i(s,"opening")} birds',                             _subText),
                _reconRow('+ DC Loaded',       '${_i(s,"dc_loaded")} birds  |  ${_f0(s,"dc_loaded_kg")} kg', _blue),
                _reconRow('- Delivered',       '${_i(s,"delivered")} birds  |  ${_f0(s,"delivered_kg")} kg', _green),
                _reconRow('+ Returned',        '${_i(s,"returned")} birds  |  ${_f0(s,"returned_kg")} kg',   PdfColor.fromInt(0xFF00695C)),
                _reconRow('- Mortality',       '${_i(s,"mortality")} birds  |  ${_f0(s,"mortality_kg")} kg', _red),
                _reconRow('- Transferred Out', '${_i(s,"transferred_out")} birds',                    _orange),
                _reconRow('- Shrinkage',       '${_f2(s,"shrinkage_kg")} kg',                         _purple),
                pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    color: _green.shade(0.9),
                    child: pw.Row(children: [
                      pw.Expanded(child: pw.Text('= Closing Stock',
                          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _green))),
                      pw.Text('${_i(s,"closing")} birds',
                          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _green)),
                    ])),
              ])),
          _secTitle('DAILY BREAKDOWN'),
          _table(
              headers: ['Date','DC Birds','DC kg','Del Birds','Del kg','Returned','Mortality','Transfer Out'],
              rows: daily.map((d) => [
                _fd(d['dt']), '${_i(d,"dc_birds")}', _f0(d,'dc_kg'),
                '${_i(d,"del_birds")}', _f0(d,'del_kg'),
                '${_i(d,"ret_birds")}', '${_i(d,"mort_birds")}', '${_i(d,"transfer_out")}',
              ]).toList(),
              bold: [3,4]),
        ]));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 3. SHRINKAGE
  // ══════════════════════════════════════════════════════════════════════════
  static void _shrinkagePdf(pw.Document doc, Map s, Map data,
      String label, String company, DateTime from, DateTime to) {
    final rows = _rowList(data['rows']);
    final loss = _d(s,'avg_loss_pct');
    doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => _header(company, label, from, to),
        footer: (_) => _footer(),
        build: (_) => [
          pw.Container(
              padding: const pw.EdgeInsets.all(10),
              color: _purple.shade(0.92),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('Shrinkage Formula (Calculated at Shift Close Only)',
                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _purple)),
                pw.SizedBox(height: 3),
                pw.Text('Shrinkage  =  DC Loaded kg  -  Delivered Net kg  -  Returned kg  -  Mortality kg',
                    style: pw.TextStyle(fontSize: 9, color: _purple)),
              ])),
          pw.SizedBox(height: 8),
          _kpiRow([
            _KpiCell('DC Loaded',   '${_f0(s,"total_dc_kg")} kg',       _blue),
            _KpiCell('Shrinkage',   '${_f1(s,"total_shrinkage_kg")} kg', _purple),
            _KpiCell('Avg Loss %',  '${loss.toStringAsFixed(2)}%',       loss>2?_red:_green),
            _KpiCell('High Loss',   '${_i(s,"high_loss_shifts")} shifts',_red),
          ]),
          _secTitle('SHIFT-WISE SHRINKAGE DETAIL'),
          _table(
              headers: ['Date','Agent','DC Birds','DC kg','Del kg','Ret kg','Mort kg','Shrink kg','Loss%'],
              rows: rows.map((r) {
                final lp = _d(r,'loss_percent');
                return [
                  _fd(r['shift_date']), _str(r,'agent_name'), '${_i(r,"dc_total_birds")}',
                  _f1(r,'dc_total_weight_kg'), _f1(r,'delivered_weight_kg'),
                  _f1(r,'returned_weight_kg'), _f1(r,'mortality_weight_kg'),
                  _f2(r,'shrinkage_kg'), '${lp.toStringAsFixed(2)}%',
                ];
              }).toList(),
              totals: ['TOTAL','—',_i(s,"total_dc_kg").toStringAsFixed(0),_f0(s,'total_dc_kg'),
                _f1(s,'total_delivered_kg'), _f1(s,'total_returned_kg'),
                _f1(s,'total_mortality_kg'), _f1(s,'total_shrinkage_kg'),
                '${loss.toStringAsFixed(2)}%'],
              bold: [7,8]),
        ]));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 4. MORTALITY
  // ══════════════════════════════════════════════════════════════════════════
  static void _mortalityPdf(pw.Document doc, Map s, Map data,
      String label, String company, DateTime from, DateTime to) {
    final rows = _rowList(data['rows']);
    doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => _header(company, label, from, to),
        footer: (_) => _footer(),
        build: (_) => [
          _kpiRow([
            _KpiCell('Total Mortality', '${_i(s,"total_mortality_birds")} birds', _red),
            _KpiCell('Mortality kg',    '${_f1(s,"total_mortality_kg")} kg',      _red),
            _KpiCell('DC Birds',        '${_i(s,"total_dc_birds")}',              _blue),
            _KpiCell('Mortality Rate',  '${_d(s,"mortality_rate_pct").toStringAsFixed(2)}%',
                _d(s,'mortality_rate_pct')>1?_red:_green),
          ]),
          rows.isEmpty
              ? pw.Padding(padding: const pw.EdgeInsets.all(20),
              child: pw.Text('No mortality recorded in this period.',
                  style: pw.TextStyle(fontSize: 11, color: _subText)))
              : pw.Column(children: [
            _secTitle('MORTALITY RECORDS'),
            _table(
                headers: ['Date','Agent','Shop','DC Birds','Delivered','Dead','Mort kg','Weak','Rejected'],
                rows: rows.map((r) => [
                  _fd(r['del_date']), _str(r,'agent_name'), _sh(_str(r,'shop_name'),15),
                  '${_i(r,"dc_birds")}', '${_i(r,"del_birds")}', '${_i(r,"mortality_birds")}',
                  _f1(r,'mortality_weight_kg'), '${_i(r,"weak_birds")}', '${_i(r,"rejected_birds")}',
                ]).toList(),
                bold: [5,6]),
          ]),
        ]));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 5. DELIVERY HISTORY
  // ══════════════════════════════════════════════════════════════════════════
  static void _deliveryHistoryPdf(pw.Document doc, Map s, Map data,
      String label, String company, DateTime from, DateTime to) {
    final rows = _rowList(data['rows']);
    doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => _header(company, label, from, to),
        footer: (_) => _footer(),
        build: (_) => [
          pw.Container(
              padding: const pw.EdgeInsets.all(8),
              color: PdfColor.fromInt(0xFF00695C).shade(0.92),
              child: pw.Text('Net Delivery Weight  =  Gross Weight  -  Cage/Tare Weight  (Actual bird weight at retailer)',
                  style: pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFF00695C), fontWeight: pw.FontWeight.bold))),
          pw.SizedBox(height: 8),
          _kpiRow([
            _KpiCell('Deliveries', '${_i(s,"total_deliveries")}',           _blue),
            _KpiCell('Gross Wt',   '${_f0(s,"total_gross_wt")} kg',         _subText),
            _KpiCell('Tare Wt',    '${_f0(s,"total_tare_wt")} kg',          _subText),
            _KpiCell('Net Del Wt', '${_f0(s,"total_net_del_wt")} kg',       PdfColor.fromInt(0xFF00695C)),
          ]),
          _secTitle('DELIVERY RECORDS  (Gross - Tare = Net Delivery Weight)'),
          _table(
              headers: ['Date','Agent','Shop','DC#','Gross Wt','Tare Wt','Net Del Wt','DC Birds','Del Birds','Mort','Collected'],
              rows: rows.map((r) => [
                _fd(r['del_date']), _str(r,'agent_name'), _sh(_str(r,'shop_name'),10),
                _sh(_str(r,'dc_number'),8),
                _f0(r,'gross_weight'), _f0(r,'tare_weight'), _f0(r,'net_del_weight'),
                '${_i(r,"dc_birds")}', '${_i(r,"del_birds")}', '${_i(r,"mortality_birds")}',
                _amt(r,'collected_amount'),
              ]).toList(),
              bold: [6]),
        ]));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 6. AGENT PERFORMANCE
  // ══════════════════════════════════════════════════════════════════════════
  static void _agentPerfPdf(pw.Document doc, Map data,
      String label, String company, DateTime from, DateTime to) {
    final agents = _rowList(data['agents']);
    final daily  = _rowList(data['daily']);
    doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => _header(company, label, from, to),
        footer: (_) => _footer(),
        build: (_) => [
          _secTitle('AGENT PERFORMANCE SUMMARY'),
          _table(
              headers: ['Agent','Vehicle','Deliveries','Birds','Net kg','Mortality','Shrink kg','Cash Coll.','Loss%'],
              rows: agents.map((a) {
                final lp = _d(a,'loss_pct');
                return [
                  _str(a,'agent_name'), _str(a,'vehicle_no')=='—'?'—':_str(a,'vehicle_no'),
                  '${_i(a,"deliveries")}', '${_i(a,"del_birds")}',
                  _f0(a,'del_weight'), '${_i(a,"mortality")}',
                  _f2(a,'shrinkage_kg'), _amt(a,'cash_collected'),
                  '${lp.toStringAsFixed(2)}%',
                ];
              }).toList(),
              bold: [4,7,8]),
          _secTitle('DAILY TREND'),
          _table(
              headers: ['Date','Del Birds','Net kg','Mortality','Shrink kg','Collected'],
              rows: daily.map((d) => [
                _fd(d['dt']), '${_i(d,"del_birds")}', _f0(d,'del_weight'),
                '${_i(d,"mortality")}', _f2(d,'shrinkage'), _amt(d,'collected'),
              ]).toList(),
              bold: [5]),
        ]));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 7. SHIFT AUDIT
  // ══════════════════════════════════════════════════════════════════════════
  static void _shiftAuditPdf(pw.Document doc, Map data,
      String label, String company, DateTime from, DateTime to) {
    final shifts = _rowList(data['shifts']);
    doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => _header(company, label, from, to),
        footer: (_) => _footer(),
        build: (_) => [
          _secTitle('SHIFT AUDIT LOG'),
          _table(
              headers: ['Date','Agent','DC Loaded kg','Del Birds','Del kg','Returned kg','Mortality','Var kg','Var%','Cash','Expenses','KM','Orders','Status'],
              rows: shifts.map((s) {
                final lp = _d(s,'loss_percent');
                final approved = s['shift_approval_status'] == 'approved';
                return [
                  _fd(s['shift_date']), _str(s,'agent_name'),
                  _f0(s,'dc_loaded_kg'), '${_i(s,"delivered_birds")}', _f0(s,'delivered_kg'),
                  _f0(s,'returned_weight'), '${_i(s,"total_mortality")}',
                  _f2(s,'shrinkage_kg'), '${lp.toStringAsFixed(2)}%',
                  _amt(s,'total_cash_collected'), _amt(s,'total_expenses'),
                  _f0(s,'distance_km'), '${_i(s,"total_orders")}',
                  approved ? 'APPROVED' : 'PENDING',
                ];
              }).toList(),
              bold: [7,8]),
        ]));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 8. EXPENSE
  // ══════════════════════════════════════════════════════════════════════════
  static void _expensePdf(pw.Document doc, Map s, Map data,
      String label, String company, DateTime from, DateTime to) {
    final byAgent = _rowList(data['by_agent']);
    final daily   = _rowList(data['daily']);
    doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => _header(company, label, from, to),
        footer: (_) => _footer(),
        build: (_) => [
          _kpiRow([
            _KpiCell('Total Expenses', _amt(s,'total_expenses'),                         _orange),
            _KpiCell('Diesel',         _amt(s,'diesel'),                                 _orange),
            _KpiCell('Allowance',      _amt(s,'allowance'),                              _orange),
            _KpiCell('Total KM',       '${_f0(s,"total_km")} km',                        _blue),
          ]),
          _secTitle('BY AGENT'),
          _table(
              headers: ['Agent','Shifts','Diesel','Allowance','Total Expenses','KM'],
              rows: byAgent.map((a)=>[
                _str(a,'agent_name'),'${_i(a,"shifts")}',
                _amt(a,'diesel'),_amt(a,'allowance'),_amt(a,'total_expenses'),
                _f0(a,'km_driven')]).toList(),
              bold: [4]),
          _secTitle('DAILY EXPENSES'),
          _table(
              headers: ['Date','Agent','Diesel','Allowance','Total Expenses','KM'],
              rows: daily.map((d)=>[
                _fd(d['dt']),_str(d,'agent_name'),
                _amt(d,'diesel_cost'),_amt(d,'allowance'),_amt(d,'total_expenses'),
                _f0(d,'distance_km')]).toList(),
              bold: [4]),
        ]));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 9. COLLECTION
  // ══════════════════════════════════════════════════════════════════════════
  static void _collectionPdf(pw.Document doc, Map s, Map data,
      String label, String company, DateTime from, DateTime to) {
    final retailers = _rowList(data['retailers']);
    final daily     = _rowList(data['daily']);
    doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => _header(company, label, from, to),
        footer: (_) => _footer(),
        build: (_) => [
          _kpiRow([
            _KpiCell('Billed',      _amt(s,'total_billed'),      _blue),
            _KpiCell('Collected',   _amt(s,'total_collected'),   _green),
            _KpiCell('Pending',     _amt(s,'total_pending'),     _orange),
            _KpiCell('Outstanding', _amt(s,'total_outstanding'), _red),
          ]),
          pw.SizedBox(height: 6),
          _kpiRow([
            _KpiCell('Cash',   _amt(s,'cash'),   _green),
            _KpiCell('UPI',    _amt(s,'upi'),    _blue),
            _KpiCell('Bank',   _amt(s,'bank'),   _blue),
            _KpiCell('Credit', _amt(s,'credit'), _orange),
          ]),
          if (retailers.isNotEmpty) ...[
            _secTitle('COLLECTION BY RETAILER'),
            _table(
                headers: ['Shop','Phone','Orders','Billed','Collected','Outstanding'],
                rows: retailers.map((r)=>[
                  _sh(_str(r,'shop_name'),18),_str(r,'phone'),'${_i(r,"orders")}',
                  _amt(r,'billed'),_amt(r,'collected'),_amt(r,'outstanding')]).toList(),
                bold: [5]),
          ],
          _secTitle('DAILY COLLECTION'),
          _table(
              headers: ['Date','Billed','Collected','Pending'],
              rows: daily.map((d)=>[_fd(d['dt']),_amt(d,'billed'),_amt(d,'collected'),_amt(d,'pending')]).toList(),
              totals: ['TOTAL', _amt(s,'total_billed'), _amt(s,'total_collected'), _amt(s,'total_pending')],
              bold: [1,2,3]),
        ]));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 10. RETAILER PURCHASE
  // ══════════════════════════════════════════════════════════════════════════
  static void _retailerPurchasePdf(pw.Document doc, Map s, Map data,
      String label, String company, DateTime from, DateTime to) {
    final retailers = _rowList(data['retailers']);
    final daily     = _rowList(data['daily']);
    doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => _header(company, label, from, to),
        footer: (_) => _footer(),
        build: (_) => [
          _kpiRow([
            _KpiCell('Orders',     '${_i(s,"total_orders")}',           _blue),
            _KpiCell('Total kg',   '${_f0(s,"total_kg")} kg',           _blue),
            _KpiCell('Billed',     _amt(s,'total_billed'),              _primary),
            _KpiCell('Pending',    _amt(s,'total_pending'),             _orange),
          ]),
          if (retailers.isNotEmpty) ...[
            _secTitle('BY RETAILER'),
            _table(
                headers: ['Shop','Phone','Orders','Total kg','Billed','Collected','Outstanding'],
                rows: retailers.map((r)=>[
                  _sh(_str(r,'shop_name'),16),_str(r,'phone'),'${_i(r,"orders")}',
                  _f0(r,'total_kg'),_amt(r,'billed'),_amt(r,'collected'),_amt(r,'outstanding')]).toList(),
                bold: [6]),
          ],
          _secTitle('ORDER HISTORY'),
          _table(
              headers: ['Date','Shop','kg','Birds','Rate/kg','Billed','Collected'],
              rows: daily.map((d)=>[
                _fd(d['order_date']),_sh(_str(d,'shop_name'),14),
                _f0(d,'kg'),'${_i(d,"birds")}',
                '₹${_d(d,"rate").toStringAsFixed(2)}',
                _amt(d,'billed'),_amt(d,'collected')]).toList(),
              bold: [5]),
        ]));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 11. PROFITABILITY
  // ══════════════════════════════════════════════════════════════════════════
  static void _profitabilityPdf(pw.Document doc, Map s, Map data,
      String label, String company, DateTime from, DateTime to) {
    final daily = _rowList(data['daily']);
    final rev  = _d(s,'revenue'); final pur = _d(s,'purchase_cost');
    final exp  = _d(s,'expenses'); final shL = _d(s,'shrinkage_loss');
    final morL = _d(s,'mortality_loss');
    final net  = rev - pur - exp - shL - morL;
    final margin = rev > 0 ? net/rev*100 : 0.0;

    doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => _header(company, label, from, to),
        footer: (_) => _footer(),
        build: (_) => [
          _secTitle('PROFIT & LOSS STATEMENT'),
          pw.Container(
              decoration: pw.BoxDecoration(border: pw.Border.all(color: _border),
                  borderRadius: pw.BorderRadius.circular(4)),
              child: pw.Column(children: [
                _reconRow('Revenue',             _amt(s,'revenue'),       _green),
                _reconRow('- Purchase Cost',     _amt(s,'purchase_cost'), _blue),
                _reconRow('- Operating Expenses',_amt(s,'expenses'),      _orange),
                _reconRow('- Shrinkage Loss',    _amt(s,'shrinkage_loss'),_purple),
                _reconRow('- Mortality Loss',    _amt(s,'mortality_loss'),_red),
                pw.Container(
                    padding: const pw.EdgeInsets.all(14),
                    color: net>=0?_green.shade(0.88):_red.shade(0.9),
                    child: pw.Row(children: [
                      pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                        pw.Text('= Net Profit',
                            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold,
                                color: net>=0?_green:_red)),
                        pw.Text('Margin: ${margin.toStringAsFixed(1)}%',
                            style: pw.TextStyle(fontSize: 9, color: net>=0?_green:_red)),
                      ])),
                      pw.Text('₹${_fmtAmt(net)}',
                          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold,
                              color: net>=0?_green:_red)),
                    ])),
              ])),
          pw.SizedBox(height: 8),
          _kpiRow([
            _KpiCell('Revenue',      _amt(s,'revenue'),       _green),
            _KpiCell('Purchases',    _amt(s,'purchase_cost'), _blue),
            _KpiCell('Expenses',     _amt(s,'expenses'),      _orange),
            _KpiCell('Net Profit',   '₹${_fmtAmt(net)}',     net>=0?_green:_red),
          ]),
          _secTitle('DAILY P&L'),
          _table(
              headers: ['Date','Revenue','Purchase Cost','Expenses','Gross Profit'],
              rows: daily.map((d) {
                final r2=_d(d,'revenue');final p2=_d(d,'purchase_cost');final e2=_d(d,'expenses');
                return [_fd(d['dt']),_amt(d,'revenue'),_amt(d,'purchase_cost'),_amt(d,'expenses'),
                  '₹${_fmtAmt(r2-p2-e2)}'];
              }).toList(),
              bold: [4]),
        ]));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PHASE 4 UI — P&L STATEMENT  (data from get_pnl_statement RPC)
  // ══════════════════════════════════════════════════════════════════════════
  static void _pnlStatementPdf(pw.Document doc, Map s, Map data,
      String label, String company, DateTime from, DateTime to) {
    final buckets = _rowList(data['buckets']);
    final netProfit = s['net_profit'] as num?;
    final grossProfit = s['gross_profit'] as num?;
    final pending = _i(s, 'lines_cost_pending') > 0;

    doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => _header(company, label, from, to),
        footer: (_) => _footer(),
        build: (_) => [
          if (pending)
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 8),
              padding: const pw.EdgeInsets.all(8),
              color: PdfColor.fromInt(0xFFFFA726).shade(0.9),
              child: pw.Text('Some lines are not yet costed — Gross/Net Profit shown as Pending.',
                  style: pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFFE65100))),
            ),
          _secTitle('PROFIT & LOSS STATEMENT'),
          pw.Container(
              decoration: pw.BoxDecoration(border: pw.Border.all(color: _border), borderRadius: pw.BorderRadius.circular(4)),
              child: pw.Column(children: [
                _reconRow('Revenue',          _amt(s,'revenue'),               _green),
                _reconRow('- COGS',           pending ? 'Pending' : _amt(s,'cogs'), _blue),
                _reconRow('- Mortality Loss', _amt(s,'mortality_loss_amount'), _red),
                _reconRow('- Shrinkage Loss', _amt(s,'shrinkage_loss_amount'), _purple),
                _reconRow('- Trip Expenses',  _amt(s,'trip_expenses'),         _orange),
                _reconRow('- Fixed Expenses', _amt(s,'fixed_expenses'),        _subText),
                pw.Container(
                    padding: const pw.EdgeInsets.all(14),
                    color: netProfit == null ? PdfColor.fromInt(0xFFFFA726).shade(0.9)
                        : netProfit.toDouble() >= 0 ? _green.shade(0.88) : _red.shade(0.9),
                    child: pw.Row(children: [
                      pw.Expanded(child: pw.Text('= Net Profit',
                          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold,
                              color: netProfit == null ? PdfColor.fromInt(0xFFE65100)
                                  : netProfit.toDouble() >= 0 ? _green : _red))),
                      pw.Text(netProfit == null ? 'Pending' : '₹${_fmtAmt(netProfit.toDouble())}',
                          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold,
                              color: netProfit == null ? PdfColor.fromInt(0xFFE65100)
                                  : netProfit.toDouble() >= 0 ? _green : _red)),
                    ])),
              ])),
          pw.SizedBox(height: 8),
          _kpiRow([
            _KpiCell('Revenue', _amt(s,'revenue'), _green),
            _KpiCell('Gross Profit', grossProfit == null ? 'Pending' : '₹${_fmtAmt(grossProfit.toDouble())}',
                grossProfit == null ? PdfColor.fromInt(0xFFE65100) : _green),
          ]),
          _secTitle('PERIOD BREAKDOWN'),
          _table(
              headers: ['Period','Revenue','COGS','Gross Profit','Net Profit'],
              rows: buckets.map((b) {
                final bp = _i(b,'lines_cost_pending') > 0;
                final bgp = b['gross_profit'] as num?;
                final bnp = b['net_profit'] as num?;
                return [
                  _fd(b['period_start']), _amt(b,'revenue'),
                  bp ? 'Pending' : _amt(b,'cogs'),
                  bgp == null ? 'Pending' : '₹${_fmtAmt(bgp.toDouble())}',
                  bnp == null ? 'Pending' : '₹${_fmtAmt(bnp.toDouble())}',
                ];
              }).toList(),
              bold: [3,4]),
        ]));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PHASE 4 UI — CASH FLOW STATEMENT  (data from get_cash_flow_statement RPC)
  // ══════════════════════════════════════════════════════════════════════════
  static void _cashFlowStatementPdf(pw.Document doc, Map s, Map data,
      String label, String company, DateTime from, DateTime to) {
    final daily = _rowList(data['daily']);
    doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => _header(company, label, from, to),
        footer: (_) => _footer(),
        build: (_) => [
          _kpiRow([
            _KpiCell('Total Cash In',  _amt(s,'total_cash_in'),  _green),
            _KpiCell('Total Cash Out', _amt(s,'total_cash_out'), _red),
            _KpiCell('Net Movement',   _amt(s,'net_movement'),
                _d(s,'net_movement') >= 0 ? _green : _red),
          ]),
          _secTitle('DAILY CASH FLOW'),
          _table(
              headers: ['Date','Cash In','Supplier Paid','Trip Exp','Fixed Exp','Net','Balance'],
              rows: daily.map((d) => [
                _fd(d['date']), _amt(d,'cash_in_total'), _amt(d,'cash_out_supplier'),
                _amt(d,'cash_out_trip'), _amt(d,'cash_out_fixed'), _amt(d,'net_movement'),
                _amt(d,'running_balance'),
              ]).toList(),
              bold: [5,6]),
        ]));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PHASE 4 UI — SUPPLIER STATEMENT  (data from get_supplier_statement RPC)
  // Mirrors the same structure as a retailer statement, supplier-side.
  // ══════════════════════════════════════════════════════════════════════════
  static void _supplierStatementPdf(pw.Document doc, Map data,
      String label, String company, DateTime from, DateTime to) {
    final header = (data['header'] as Map?) ?? {};
    final rows = _rowList(data['rows']);
    final opening = (data['opening_balance'] as num?)?.toDouble() ?? 0;
    final closing = (data['closing_balance'] as num?)?.toDouble() ?? 0;
    final s = (data['summary'] as Map?) ?? {};

    doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => _header(company, label, from, to),
        footer: (_) => _footer(),
        build: (_) => [
          pw.Text('${header['farmer_name'] ?? ''}  ${header['farm_name'] != null ? "(${header['farm_name']})" : ""}',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          _kpiRow([
            _KpiCell('Opening Balance', '₹${_fmtAmt(opening)}', _subText),
            _KpiCell('Total Purchases', _amt(s,'total_purchases'), _blue),
            _KpiCell('Total Paid',      _amt(s,'total_payments'),  _green),
            _KpiCell('Closing Balance', '₹${_fmtAmt(closing)}', closing > 0 ? _red : _green),
          ]),
          _secTitle('TRANSACTIONS'),
          _table(
              headers: ['Date','Type','Ref','Amount','Balance'],
              rows: rows.map((r) {
                final isDebit = r['entry_type'] == 'debit';
                final amt = _d(r, 'amount');
                final bal = _d(r, 'running_balance');
                return [
                  _fd(r['entry_date']),
                  isDebit ? 'Purchase' : 'Payment',
                  _str(r, 'ref_number'),
                  '${isDebit ? "+" : "-"}₹${_fmtAmt(amt)}',
                  '₹${_fmtAmt(bal)}',
                ];
              }).toList(),
              bold: [4]),
        ]));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PHASE 3/5 UI — PROFITABILITY BREAKDOWN  (data from get_profitability_breakdown RPC)
  // ══════════════════════════════════════════════════════════════════════════
  static void _profitabilityBreakdownPdf(pw.Document doc, Map data,
      String label, String company, DateTime from, DateTime to) {
    final rows = _rowList(data['rows']);
    final dimension = data['dimension'] as String? ?? '';

    doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => _header(company, '$label (by ${dimension.toUpperCase()})', from, to),
        footer: (_) => _footer(),
        build: (_) => [
          _secTitle('PROFITABILITY BY ${dimension.toUpperCase()}'),
          _table(
              headers: ['Name','kg','Revenue','Cost','Gross Profit','Margin %'],
              rows: rows.map((r) {
                final cost = r['total_cost'] as num?;
                final gp = r['gross_profit'] as num?;
                final margin = r['margin_pct'] as num?;
                final pendingLines = _i(r, 'lines_cost_pending');
                return [
                  _str(r, 'group_label'),
                  _f0(r, 'total_kg'),
                  _amt(r,'total_revenue'),
                  cost == null ? (pendingLines > 0 ? 'Pending' : '₹0.00') : '₹${_fmtAmt(cost.toDouble())}',
                  gp == null ? 'Pending' : '₹${_fmtAmt(gp.toDouble())}',
                  margin == null ? '—' : '${margin.toStringAsFixed(1)}%',
                ];
              }).toList(),
              bold: [4,5]),
        ]));
  }

  // Generic fallback
  static void _genericPdf(pw.Document doc, Map s, String label, String company, DateTime from, DateTime to) {
    doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => pw.Column(children: [
          _header(company, label, from, to),
          pw.Text('Report data:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          ...s.entries.map((e) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Row(children: [
                pw.Expanded(child: pw.Text('${e.key}:', style: pw.TextStyle(fontSize: 10, color: _subText))),
                pw.Text('${e.value}', style: pw.TextStyle(fontSize: 10)),
              ]))),
        ])));
  }

  // ─── DATA HELPERS ─────────────────────────────────────────────────────────
  static List<Map<String,dynamic>> _rowList(dynamic v) =>
      List<Map<String,dynamic>>.from(v as List? ?? []);

  static double _d(Map m, String k) => (m[k] as num?)?.toDouble() ?? 0;
  static int    _i(Map m, String k) => (m[k] as num?)?.toInt() ?? 0;
  static String _str(Map m, String k) => m[k] as String? ?? '—';
  static String _sh(String s, int mx) => s.length>mx ? '${s.substring(0,mx)}…' : s;

  static String _f0(Map m, String k) => _d(m,k).toStringAsFixed(0);
  static String _f1(Map m, String k) => _d(m,k).toStringAsFixed(1);
  static String _f2(Map m, String k) => _d(m,k).toStringAsFixed(2);

  static String _fmtAmt(double v) {
    if (v.abs() >= 100000) return '${(v/100000).toStringAsFixed(2)}L';
    if (v.abs() >= 1000)   return '${(v/1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(2);
  }
  static String _amt(Map m, String k) => '₹${_fmtAmt(_d(m,k))}';

  static String _fd(dynamic s) {
    if (s == null) return '—';
    try { return DateFormat('d MMM yy').format(DateTime.parse(s.toString())); }
    catch (_) { return s.toString().length>10?s.toString().substring(0,10):s.toString(); }
  }
}

class _KpiCell {
  final String label, value;
  final PdfColor color;
  const _KpiCell(this.label, this.value, this.color);
}