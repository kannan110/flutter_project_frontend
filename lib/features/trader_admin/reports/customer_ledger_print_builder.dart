import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../../core/theme/app_theme.dart' show Fmt;
import 'customer_ledger_row_builder.dart';
import 'report_dataset.dart' show ReportPrintStyle;
import 'report_pdf_generator.dart' show ReportPdfGenerator;

// ─────────────────────────────────────────────────────────────────────────────
// CustomerLedgerPrintBuilder
//
// The ONE reusable builder behind both Full Sheet (A4) and Half Sheet (A5)
// printing for Customer Ledger. Only page size, margins, fonts, spacing,
// and column widths differ between the two — driven entirely by the
// [PrintSheetSize] parameter. No ledger business logic lives here: row
// flattening, multi-product grouping, and running-balance math all come
// from CustomerLedgerTableData.from() (the exact same call every other
// Customer Ledger PDF path already uses), so this can never disagree with
// the on-screen table or the existing Header/Table PDFs on the numbers.
//
// This is deliberately separate from ReportPdfGenerator's _table()/
// _buildDataSetDoc for the TABLE specifically (TableHelper.fromTextArray
// gives native multi-page header repeat that a hand-built pw.Table
// doesn't) — but the COMPANY HEADER (logo/name/contact details/BILL TO/
// CUSTOMER LEDGER block) now calls ReportPdfGenerator's public
// richCompanyHeader/customerLedgerHeaderRight/billToBlock/fetchLogo
// directly, rather than maintaining a second, divergence-prone copy of
// that layout. Full Sheet and Half Sheet both go through this same
// shared implementation, scaled by [PrintSheetSize].
//
// Future Batch Print (All Customers): loop `build()` once per customer's
// get_retailer_statement() result, same PrintSheetSize each time. The
// per-customer font loading is intentionally exposed via optional
// [regularFont]/[boldFont] parameters so a batch caller can load fonts
// once and pass them into every iteration instead of reloading per
// customer.
// ─────────────────────────────────────────────────────────────────────────────

enum PrintSheetSize { full, half }

extension PrintSheetSizeX on PrintSheetSize {
  bool get isHalf => this == PrintSheetSize.half;

  PdfPageFormat get pageFormat => isHalf ? PdfPageFormat.a5 : PdfPageFormat.a4;

  pw.EdgeInsets get margin => isHalf
      ? const pw.EdgeInsets.fromLTRB(14, 16, 14, 14)
      : const pw.EdgeInsets.fromLTRB(24, 26, 24, 22);

  double get companyFontSize    => isHalf ? 10 : 14;
  double get titleFontSize      => isHalf ? 8.5 : 11;
  double get identityFontSize   => isHalf ? 7 : 9;
  double get tableHeaderFontSize=> isHalf ? 6.5 : 8;
  double get tableCellFontSize  => isHalf ? 6.5 : 9;
  double get footerFontSize     => isHalf ? 5.5 : 7;
  double get cellPaddingH       => isHalf ? 3 : 6;
  double get cellPaddingV       => isHalf ? 2.5 : 5;
  double get dividerThickness   => isHalf ? 0.75 : 1.2;

  // Same 9 columns on both sizes — only the relative weighting (and the
  // font sizes above) change. Nothing here removes or reorders a column,
  // so multi-product grouping and totals render identically either way.
  Map<int, pw.TableColumnWidth> get columnWidths => {
    0: const pw.FlexColumnWidth(0.9),  // Date
    1: const pw.FlexColumnWidth(1.0),  // Ref No
    2: const pw.FlexColumnWidth(0.8),  // Type
    3: pw.FlexColumnWidth(isHalf ? 2.0 : 2.8), // Product / Description
    4: const pw.FlexColumnWidth(0.7),  // Kg
    5: const pw.FlexColumnWidth(0.7),  // Rate
    6: const pw.FlexColumnWidth(1.0),  // Sale
    7: const pw.FlexColumnWidth(1.0),  // Payment
    8: pw.FlexColumnWidth(isHalf ? 1.0 : 1.1), // Balance
  };
}

class CustomerLedgerPrintBuilder {
  const CustomerLedgerPrintBuilder._();

  static const _primary = PdfColor.fromInt(0xFFBF1B2C);
  static const _dark    = PdfColor.fromInt(0xFF1A1A1A);
  static const _subText = PdfColor.fromInt(0xFF6B6B6B);
  static const _border  = PdfColor.fromInt(0xFFDDDDDD);

  /// Builds the Full Sheet / Half Sheet PDF document. [data] is the raw,
  /// unmodified get_retailer_statement() response — the exact same map
  /// the Header PDF and Table PDF already consume. Optional pre-loaded
  /// [regularFont]/[boldFont] let a future Batch Print loop load fonts
  /// once instead of once per customer.
  static Future<pw.Document> build({
    required Map<String, dynamic> data,
    required String companyName,
    required DateTime fromDate,
    required DateTime toDate,
    required PrintSheetSize size,
    ReportPrintStyle style = ReportPrintStyle.color,
    pw.Font? regularFont,
    pw.Font? boldFont,
  }) async {
    // Same row-building logic as every other Customer Ledger PDF path —
    // no reimplementation, no risk of the numbers disagreeing.
    final header = (data['header'] as Map?)?.cast<String, dynamic>() ?? {};
    final opening = (data['opening_balance'] as num?)?.toDouble() ?? 0;
    final t = CustomerLedgerTableData.from(data);

    final customerName = header['retailer_name'] as String? ?? 'Customer';
    final openingLabel = Fmt.amount(opening);

    final font = regularFont ?? await PdfGoogleFonts.notoSansRegular();
    final bold = boldFont ?? await PdfGoogleFonts.notoSansBold();
    final doc = pw.Document(theme: pw.ThemeData.withFont(base: font, bold: bold));

    final bw = style == ReportPrintStyle.blackAndWhite;
    // Company Logo — ROOT CAUSE FIX (Full Sheet logo-missing audit): now
    // calls ReportPdfGenerator.fetchLogo (package:http, cross-platform
    // including Web) instead of a local dart:io HttpClient copy, which
    // silently failed on Web (dart:io doesn't exist there) — that's why
    // the logo never appeared despite traders.logo_url being valid and
    // the Profile screen showing it correctly (a different, working code
    // path — Image.network — was never involved in PDF generation at all).
    final logo = await ReportPdfGenerator.fetchLogo(header['company_logo'] as String?);
    // Scale factor for the shared header widgets at A5 (Half Sheet) —
    // reuses size.identityFontSize's existing ratio (7/9) as the scale.
    final headerScale = size.isHalf ? 0.75 : 1.0;

    doc.addPage(pw.MultiPage(
      pageFormat: size.pageFormat,
      margin: size.margin,
      // Repeats on every page — this is what makes the customer header
      // survive a page break, unlike the existing Table PDF's identity
      // block (which lives in page content, not this header slot).
      header: (_) => ReportPdfGenerator.richCompanyHeader(
        companyName: companyName,
        phone: header['company_phone'] as String?,
        address: [header['company_address'], header['company_city']]
            .where((s) => s != null && (s as String).isNotEmpty).join(', '),
        email: header['company_email'] as String?,
        gstNumber: header['company_gst'] as String?,
        logo: logo,
        bw: bw,
        scale: headerScale,
        right: ReportPdfGenerator.customerLedgerHeaderRight(
          customerName: customerName,
          from: fromDate, to: toDate,
          openingLabel: openingLabel,
          bw: bw,
          scale: headerScale,
        ),
      ),
      // ctx.pageNumber / ctx.pagesCount — native to pw.MultiPage, no
      // manual page counting.
      footer: (ctx) => _printFooter(ctx, size, bw: bw),
      build: (_) => [
        // BILL TO — same shared block the Table PDF uses, scaled for
        // Half Sheet. Any field genuinely absent for this customer is
        // simply omitted, not shown blank.
        ReportPdfGenerator.billToBlock(
          customerName: header['retailer_name'] as String? ?? customerName,
          contactPerson: header['retailer_owner'] as String?,
          mobile: header['retailer_phone'] as String?,
          areaOrAddress: (header['retailer_address'] as String?)?.isNotEmpty == true
              ? header['retailer_address'] as String?
              : header['retailer_area'] as String?,
          bw: bw,
          scale: headerScale,
        ),
        pw.SizedBox(height: size.isHalf ? 5 : 8),
        _printTable(t.headers, t.rows, t.totals, size, bw: bw),
      ],
    ));

    return doc;
  }

  /// Opens the native print/save preview sheet.
  static Future<void> printAndShow({
    required BuildContext context,
    required Map<String, dynamic> data,
    required String companyName,
    required DateTime fromDate,
    required DateTime toDate,
    required PrintSheetSize size,
    ReportPrintStyle style = ReportPrintStyle.color,
  }) async {
    final doc = await build(
      data: data, companyName: companyName, fromDate: fromDate, toDate: toDate, size: size,
      style: style,
    );
    final header = (data['header'] as Map?)?.cast<String, dynamic>() ?? {};
    final name = (header['retailer_name'] as String? ?? 'Customer')
        .toString()
        .replaceAll(RegExp(r'\s+'), '_');
    final sheetLabel = size.isHalf ? 'HalfSheet' : 'FullSheet';
    await Printing.layoutPdf(
      onLayout: (fmt) async => doc.save(),
      name: 'Ledger_${name}_${sheetLabel}_${DateFormat('yyyyMMdd').format(fromDate)}.pdf',
      // FIX (verified against printing 5.14.3's actual signature, which
      // this project has pinned via pubspec.lock): layoutPdf's `format`
      // parameter defaults to PdfPageFormat.standard, completely separate
      // from the pageFormat already baked into `doc` above. Without this,
      // the print dialog assumes "standard" paper while the real document
      // is A5/A4, which is what produced the blank-space/wrong-size
      // symptom. dynamicLayout: false stops the OS dialog's own paper-size
      // picker from re-requesting a different format than the one this
      // builder deliberately generated for Half/Full Sheet.
      format: size.pageFormat,
      dynamicLayout: false,
    );
  }

  /// Explicit share-sheet entry point (mirrors the existing Header/Table
  /// PDF share methods).
  static Future<void> share({
    required Map<String, dynamic> data,
    required String companyName,
    required DateTime fromDate,
    required DateTime toDate,
    required PrintSheetSize size,
    ReportPrintStyle style = ReportPrintStyle.color,
  }) async {
    final doc = await build(
      data: data, companyName: companyName, fromDate: fromDate, toDate: toDate, size: size,
      style: style,
    );
    final bytes = await doc.save();
    final header = (data['header'] as Map?)?.cast<String, dynamic>() ?? {};
    final name = (header['retailer_name'] as String? ?? 'Customer')
        .toString()
        .replaceAll(RegExp(r'\s+'), '_');
    final sheetLabel = size.isHalf ? 'HalfSheet' : 'FullSheet';
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'Ledger_${name}_${sheetLabel}_${DateFormat('yyyyMMdd').format(fromDate)}.pdf',
    );
  }

  // ── Old duplicate header removed (Full Sheet header-consolidation audit)
  //    — company header + BILL TO now come from ReportPdfGenerator's
  //    shared richCompanyHeader/customerLedgerHeaderRight/billToBlock,
  //    called directly from build() above, so Full Sheet, Half Sheet, and
  //    the Table PDF can never diverge again.

  // ── Footer — "Page X of Y" on every page, via native MultiPage context ──
  static pw.Widget _printFooter(pw.Context ctx, PrintSheetSize size, {bool bw = false}) => pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text('RoosterHub Trader OS',
          style: pw.TextStyle(fontSize: size.footerFontSize, color: bw ? PdfColors.black : _subText)),
      pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
          style: pw.TextStyle(fontSize: size.footerFontSize, color: bw ? PdfColors.black : _subText)),
    ],
  );

  // ── Ledger table — TableHelper.fromTextArray, which (unlike the shared
  //    _table() used by the existing Header/Table PDFs) natively repeats
  //    its header row across page breaks. Native pagination only — no row
  //    counting, no manual page splitting; rows 9-10 of an 8-per-page
  //    ledger simply flow onto page 2 on their own.
  //
  //    Note (Print Style audit): fromTextArray's cellStyle/headerStyle are
  //    static per-call values, not per-row callbacks, so unlike the shared
  //    _table() in report_pdf_generator.dart, this builder cannot bold or
  //    thick-border individual Opening/Summary/Closing rows without a
  //    larger rewrite to a manually-built pw.Table (which would also need
  //    to reimplement this builder's native multi-page header repeat by
  //    hand). Scoped out of this pass — flagged, not silently skipped.
  //    Right-alignment of numeric columns and header-repeat-per-page are
  //    already native here via cellAlignments/fromTextArray respectively,
  //    for both Color and Black & White.
  static pw.Widget _printTable(
      List<String> headers,
      List<List<String>> rows,
      List<String> totals,
      PrintSheetSize size,
      {bool bw = false}
      ) {
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: [...rows, totals],
      border: bw
          ? pw.TableBorder(
        top: const pw.BorderSide(color: PdfColors.black, width: 1.0),
        bottom: const pw.BorderSide(color: PdfColors.black, width: 1.0),
        left: const pw.BorderSide(color: PdfColors.black, width: 1.0),
        right: const pw.BorderSide(color: PdfColors.black, width: 1.0),
        horizontalInside: const pw.BorderSide(color: PdfColors.black, width: 0.4),
        verticalInside: const pw.BorderSide(color: PdfColors.black, width: 0.4),
      )
          : pw.TableBorder.all(color: _border, width: 0.4),
      headerDecoration: bw
          ? const pw.BoxDecoration(
          color: PdfColors.white,
          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 1.0)))
          : const pw.BoxDecoration(color: _primary),
      headerStyle: pw.TextStyle(
          fontSize: size.tableHeaderFontSize, fontWeight: pw.FontWeight.bold,
          color: bw ? PdfColors.black : PdfColors.white),
      cellStyle: pw.TextStyle(fontSize: size.tableCellFontSize, color: bw ? PdfColors.black : _dark),
      cellPadding: pw.EdgeInsets.symmetric(horizontal: size.cellPaddingH, vertical: size.cellPaddingV),
      cellAlignments: const {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerLeft,
        3: pw.Alignment.centerLeft,
        4: pw.Alignment.centerRight,
        5: pw.Alignment.centerRight,
        6: pw.Alignment.centerRight,
        7: pw.Alignment.centerRight,
        8: pw.Alignment.centerRight,
      },
      columnWidths: size.columnWidths,
    );
  }
}