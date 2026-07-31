import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../../core/theme/app_theme.dart' show Fmt;
import 'customer_ledger_row_builder.dart';

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
// _buildDataSetDoc — those remain completely unchanged, along with every
// one of the other 17 reports and Customer Ledger's own existing Header
// PDF and Table PDF. This builder is additive only.
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
    pw.Font? regularFont,
    pw.Font? boldFont,
  }) async {
    // Same row-building logic as every other Customer Ledger PDF path —
    // no reimplementation, no risk of the numbers disagreeing.
    final header = (data['header'] as Map?)?.cast<String, dynamic>() ?? {};
    final opening = (data['opening_balance'] as num?)?.toDouble() ?? 0;
    final t = CustomerLedgerTableData.from(data);

    final customerName = header['retailer_name'] as String? ?? 'Customer';
    final periodLabel =
        '${DateFormat("d MMM yyyy").format(fromDate)} - ${DateFormat("d MMM yyyy").format(toDate)}';
    final openingLabel = Fmt.amount(opening);

    final font = regularFont ?? await PdfGoogleFonts.notoSansRegular();
    final bold = boldFont ?? await PdfGoogleFonts.notoSansBold();
    final doc = pw.Document(theme: pw.ThemeData.withFont(base: font, bold: bold));

    doc.addPage(pw.MultiPage(
      pageFormat: size.pageFormat,
      margin: size.margin,
      // Repeats on every page — this is what makes the customer header
      // survive a page break, unlike the existing Table PDF's identity
      // block (which lives in page content, not this header slot).
      header: (_) => _printHeader(
        companyName: companyName,
        customerName: customerName,
        periodLabel: periodLabel,
        openingLabel: openingLabel,
        size: size,
      ),
      // ctx.pageNumber / ctx.pagesCount — native to pw.MultiPage, no
      // manual page counting.
      footer: (ctx) => _printFooter(ctx, size),
      build: (_) => [
        _printTable(t.headers, t.rows, t.totals, size),
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
  }) async {
    final doc = await build(
      data: data, companyName: companyName, fromDate: fromDate, toDate: toDate, size: size,
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
  }) async {
    final doc = await build(
      data: data, companyName: companyName, fromDate: fromDate, toDate: toDate, size: size,
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

  // ── Compact customer header — repeats every page via MultiPage.header ──
  static pw.Widget _printHeader({
    required String companyName,
    required String customerName,
    required String periodLabel,
    required String openingLabel,
    required PrintSheetSize size,
  }) {
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(companyName,
            style: pw.TextStyle(fontSize: size.companyFontSize, fontWeight: pw.FontWeight.bold, color: _primary)),
        pw.Text('CUSTOMER LEDGER',
            style: pw.TextStyle(fontSize: size.titleFontSize, fontWeight: pw.FontWeight.bold, color: _primary)),
      ]),
      pw.SizedBox(height: size.isHalf ? 2 : 4),
      pw.Text('Customer : $customerName',
          style: pw.TextStyle(fontSize: size.identityFontSize, fontWeight: pw.FontWeight.bold, color: _dark)),
      pw.Text('$periodLabel  |  Opening : $openingLabel',
          style: pw.TextStyle(fontSize: size.identityFontSize, color: _subText)),
      pw.SizedBox(height: size.isHalf ? 3 : 5),
      pw.Divider(color: _primary, thickness: size.dividerThickness),
      pw.SizedBox(height: size.isHalf ? 3 : 5),
    ]);
  }

  // ── Footer — "Page X of Y" on every page, via native MultiPage context ──
  static pw.Widget _printFooter(pw.Context ctx, PrintSheetSize size) => pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text('RoosterHub Trader OS', style: pw.TextStyle(fontSize: size.footerFontSize, color: _subText)),
      pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
          style: pw.TextStyle(fontSize: size.footerFontSize, color: _subText)),
    ],
  );

  // ── Ledger table — TableHelper.fromTextArray, which (unlike the shared
  //    _table() used by the existing Header/Table PDFs) natively repeats
  //    its header row across page breaks. Native pagination only — no row
  //    counting, no manual page splitting; rows 9-10 of an 8-per-page
  //    ledger simply flow onto page 2 on their own.
  static pw.Widget _printTable(
      List<String> headers,
      List<List<String>> rows,
      List<String> totals,
      PrintSheetSize size,
      ) {
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: [...rows, totals],
      border: pw.TableBorder.all(color: _border, width: 0.4),
      headerDecoration: const pw.BoxDecoration(color: _primary),
      headerStyle: pw.TextStyle(
          fontSize: size.tableHeaderFontSize, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      cellStyle: pw.TextStyle(fontSize: size.tableCellFontSize, color: _dark),
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