import 'dart:math' as math;
import 'dart:typed_data';
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
// The ONE reusable builder behind both Full Sheet and Half Sheet printing
// for Customer Ledger. No ledger business logic lives here: row flattening,
// multi-product grouping, and running-balance math all come from
// CustomerLedgerTableData.from() (the exact same call every other
// Customer Ledger PDF path already uses), so this can never disagree with
// the on-screen table or the existing Header/Table PDFs on the numbers.
//
// FULL SHEET  → one pw.MultiPage on A4 portrait (unchanged).
//
// HALF SHEET  → every PDF page is a real A4 PORTRAIT page that holds TWO
//               stacked "halves". Each half is a complete mini-statement:
//               company header + logo, BILL TO, table header, rows, footer.
//               Half 1 sits in the top half of the sheet, half 2 in the
//               bottom half, a faint dashed cut line marks the exact middle
//               (148.5mm). If the ledger needs more than two halves, it
//               continues on the NEXT A4 sheet (halves 3 and 4), and so on.
//               The printer always receives ONE normal A4 portrait page per
//               sheet — no dependency on N-up, rotation, or multi-page
//               placement in the print dialog/driver.
//
// This is deliberately separate from ReportPdfGenerator's _table()/
// _buildDataSetDoc — but the COMPANY HEADER (logo/name/contact details/
// BILL TO/CUSTOMER LEDGER block) calls ReportPdfGenerator's public
// richCompanyHeader/customerLedgerHeaderRight/billToBlock/fetchLogo
// directly, so Full Sheet, Half Sheet and the Table PDF can never diverge.
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

  // Both sizes are A4 portrait. (Half Sheet fits two halves inside it — see
  // the _half* layout constants in CustomerLedgerPrintBuilder.)
  PdfPageFormat get pageFormat => PdfPageFormat.a4;

  // Used by Full Sheet's pw.MultiPage. Half Sheet positions its own halves
  // explicitly and uses zero page margin (see _addHalfSheetPages).
  pw.EdgeInsets get margin => const pw.EdgeInsets.fromLTRB(24, 26, 24, 22);

  double get companyFontSize     => isHalf ? 12 : 14;
  double get titleFontSize       => isHalf ? 9.5 : 11;
  double get identityFontSize    => isHalf ? 8 : 9;
  double get tableHeaderFontSize => isHalf ? 7.5 : 8;
  double get tableCellFontSize   => isHalf ? 8 : 9;
  double get footerFontSize      => isHalf ? 6.5 : 7;
  double get cellPaddingH        => isHalf ? 3 : 6;
  double get cellPaddingV        => isHalf ? 2.2 : 5;
  double get dividerThickness    => isHalf ? 0.9 : 1.2;

  // Same 9 columns on both sizes — nothing is removed or reordered, so
  // multi-product grouping and totals render identically either way.
  // Half Sheet uses tighter text-driven widths (narrow Product column, wide
  // Ref No / amount columns) so Ref No and the rupee amounts fit on ONE line
  // — Half Sheet rows are fixed-height single-line rows.
  Map<int, pw.TableColumnWidth> get columnWidths => isHalf
      ? const {
    0: pw.FlexColumnWidth(3.3),   // Date
    1: pw.FlexColumnWidth(8.2),   // Ref No
    2: pw.FlexColumnWidth(3.7),   // Type
    3: pw.FlexColumnWidth(15.8),  // Product / Description
    4: pw.FlexColumnWidth(3.6),   // Kg
    5: pw.FlexColumnWidth(2.2),   // Rate
    6: pw.FlexColumnWidth(6.2),   // Sale
    7: pw.FlexColumnWidth(6.2),   // Payment
    8: pw.FlexColumnWidth(6.4),   // Balance
  }
      : const {
    0: pw.FlexColumnWidth(0.9),  // Date
    1: pw.FlexColumnWidth(1.0),  // Ref No
    2: pw.FlexColumnWidth(0.8),  // Type
    3: pw.FlexColumnWidth(2.8),  // Product / Description
    4: pw.FlexColumnWidth(0.7),  // Kg
    5: pw.FlexColumnWidth(0.7),  // Rate
    6: pw.FlexColumnWidth(1.0),  // Sale
    7: pw.FlexColumnWidth(1.0),  // Payment
    8: pw.FlexColumnWidth(1.1),  // Balance
  };
}

// ── Bulk Print data model ──────────────────────────────────────────────────
// One retailer's already-fetched get_retailer_statement() response, ready
// to become a page (or pages) in a batch PDF. Built by
// BulkCustomerLedgerService (data-fetch phase, separate file) and consumed
// by CustomerLedgerPrintBuilder.buildBatch() (PDF-assembly phase) below —
// kept as a plain data holder so neither phase needs to know about the
// other's implementation.
class RetailerLedgerJob {
  const RetailerLedgerJob({
    required this.retailerId,
    required this.retailerName,
    required this.data,
  });
  final String retailerId;
  final String retailerName;
  final Map<String, dynamic> data;
}

/// Which phase a batch failure happened in — shown to the trader so
/// "Retry" is only offered where retrying can plausibly help (a network/
/// RPC fetch failure is often transient; a PDF-build failure on the same
/// data will almost certainly fail again identically).
enum BatchFailureStage { fetch, build }

class BatchLedgerFailure {
  const BatchLedgerFailure({
    required this.retailerId,
    required this.retailerName,
    required this.stage,
    required this.reason,
  });
  final String retailerId;
  final String retailerName;
  final BatchFailureStage stage;
  final String reason;
}

/// Result of CustomerLedgerPrintBuilder.buildBatch(). [document] is null
/// only when EVERY retailer failed — callers must treat that as "nothing
/// to print/save", never fall back to an empty document.
class BatchLedgerResult {
  const BatchLedgerResult({
    required this.document,
    required this.totalRequested,
    required this.succeeded,
    required this.failures,
  });
  final pw.Document? document;
  final int totalRequested;
  final int succeeded;
  final List<BatchLedgerFailure> failures;
}

/// One independently-generated, fully self-contained PDF for a single
/// retailer — its own pw.Document, own embedded fonts/logo, ready to be
/// shared/downloaded on its own with no dependency on any other file.
/// Produced by buildIndividual() (Download All / Download Selected),
/// never by buildBatch() (Print All / Print Selected, which stays a
/// single combined document by design).
class IndividualLedgerFile {
  const IndividualLedgerFile({
    required this.retailerId,
    required this.retailerName,
    required this.filename,
    required this.bytes,
  });
  final String retailerId;
  final String retailerName;
  final String filename;
  final Uint8List bytes;
}

class IndividualBuildResult {
  const IndividualBuildResult({
    required this.files,
    required this.totalRequested,
    required this.failures,
  });
  final List<IndividualLedgerFile> files;
  final int totalRequested;
  final List<BatchLedgerFailure> failures;
  int get succeeded => files.length;
}

class CustomerLedgerPrintBuilder {
  const CustomerLedgerPrintBuilder._();

  static const _primary = PdfColor.fromInt(0xFFBF1B2C);
  static const _dark    = PdfColor.fromInt(0xFF1A1A1A);
  static const _subText = PdfColor.fromInt(0xFF6B6B6B);
  static const _border  = PdfColor.fromInt(0xFFDDDDDD);

  // ── HALF SHEET layout constants (points; 1pt = 1/72 inch) ────────────────
  // A4 = 595.28 × 841.89pt. The sheet is split into two equal slots whose
  // vertical centre is the exact half line (420.945pt = 148.5mm).
  //
  //   y = 0 ─────────────────────────────────────────
  //        _halfTopMargin (22)
  //        SLOT 1  (height _halfSlotH = 372)
  //        gap  ── dashed cut line at y = 420.945 ──
  //        SLOT 2  (height _halfSlotH = 372)
  //        _halfTopMargin (22)  ← also the bottom margin (≈7.8mm), kept
  //                               well clear of the printer's unprintable
  //                               edge so the lower half is never clipped
  //   y = 841.89 ────────────────────────────────────
  static const double _halfTopMargin = 22;
  static const double _halfSlotH     = 372;
  static const double _halfSideMargin = 24;
  static const bool   _halfShowCutLine = true;

  // Row capacity per half. Every Half Sheet table row (and the table
  // header row) is EXACTLY _halfRowH tall — single line, text shrinks to fit
  // its column instead of wrapping (see _halfTable) — and the header block
  // heights are budgeted below, so the number of rows per half is exact. If
  // you ever see the table touching the footer, raise _halfHeaderEst /
  // _halfBillEst by a few points; if there is too much empty space above
  // the footer, lower them.
  static const double _halfRowH      = 15;   // every table row + table header row
  static const double _halfHeaderEst = 82;   // company header block (scale 0.8)
  static const double _halfBillEst   = 46;   // BILL TO block
  static const double _halfBlockGap  = 5;    // gap between BILL TO and table
  static const double _halfFooterH   = 12;   // footer line
  static const double _halfSafety    = 8;    // spare points

  static int get _halfRowsPerSlot {
    final avail = _halfSlotH -
        _halfHeaderEst -
        _halfBillEst -
        _halfBlockGap -
        _halfRowH - // the table's own header row
        _halfFooterH -
        _halfSafety;
    return math.max(1, (avail / _halfRowH).floor());
  }

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
    final font = regularFont ?? await PdfGoogleFonts.notoSansRegular();
    final bold = boldFont ?? await PdfGoogleFonts.notoSansBold();
    final doc = pw.Document(theme: pw.ThemeData.withFont(base: font, bold: bold));

    final header = (data['header'] as Map?)?.cast<String, dynamic>() ?? {};
    // Company Logo — uses ReportPdfGenerator.fetchLogo (package:http,
    // cross-platform including Web) instead of a dart:io HttpClient copy,
    // which silently failed on Web.
    final logo = await ReportPdfGenerator.fetchLogo(header['company_logo'] as String?);

    _addLedgerPage(
      doc,
      data: data,
      companyName: companyName,
      fromDate: fromDate,
      toDate: toDate,
      size: size,
      style: style,
      logo: logo,
    );

    return doc;
  }

  /// Batch build — ONE combined pw.Document with every retailer in [jobs]
  /// starting on its own page (each retailer is its own set of pages, so a
  /// retailer whose ledger itself spans multiple pages keeps working
  /// exactly as it does today — "Page X of Y" local to that retailer's own
  /// pages).
  ///
  /// Reuses the EXACT same [_addLedgerPage] the single-retailer build()
  /// above uses — same header/BILL TO/table/calculations, so a batch PDF
  /// can never render a retailer differently than printing them one at a
  /// time would. Fonts are loaded once for the whole batch; the company
  /// logo (identical for every retailer of one trader) is fetched once
  /// from the first job's header and the same pw.MemoryImage instance is
  /// reused for every page, so the pdf package embeds it a single time
  /// rather than once per retailer.
  ///
  /// A retailer whose PAGE fails to build (malformed data, etc.) is
  /// skipped and recorded in the returned result's `failures` — never
  /// silently dropped, and never allowed to abort the rest of the batch.
  /// [onProgress] fires once per retailer processed (build phase only —
  /// data-fetch progress is reported separately by
  /// BulkCustomerLedgerService before jobs ever reach this method).
  ///
  /// Note on what this can and can't catch: CustomerLedgerTableData.from()
  /// — the row-flattening/balance step, and the most likely place a
  /// malformed retailer response would throw — runs eagerly inside
  /// _addLedgerPage, so a bad retailer is caught and isolated here. The
  /// actual page layout (header/footer/build closures) is lazy — the pdf
  /// package only invokes it during doc.save() — so a failure arising
  /// purely from PDF layout itself (not the data) would surface later,
  /// when the caller calls doc.save() to print/save. That case is still
  /// handled safely, just one level up: printPreparedDocument /
  /// savePreparedDocument's caller wraps that call in try/catch too, so
  /// the trader gets a clear error rather than a silent or partial file —
  /// it just means nothing is produced that time, rather than isolating
  /// only the one bad retailer at that specific failure point.
  static Future<BatchLedgerResult> buildBatch({
    required List<RetailerLedgerJob> jobs,
    required String companyName,
    required DateTime fromDate,
    required DateTime toDate,
    required PrintSheetSize size,
    ReportPrintStyle style = ReportPrintStyle.color,
    void Function(int done, int total, String currentRetailerName)? onProgress,
  }) async {
    if (jobs.isEmpty) {
      return const BatchLedgerResult(document: null, totalRequested: 0, succeeded: 0, failures: []);
    }

    final font = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();
    final doc = pw.Document(theme: pw.ThemeData.withFont(base: font, bold: bold));

    final firstHeader = (jobs.first.data['header'] as Map?)?.cast<String, dynamic>() ?? {};
    final logo = await ReportPdfGenerator.fetchLogo(firstHeader['company_logo'] as String?);

    final failures = <BatchLedgerFailure>[];
    for (var i = 0; i < jobs.length; i++) {
      final job = jobs[i];
      try {
        _addLedgerPage(
          doc,
          data: job.data,
          companyName: companyName,
          fromDate: fromDate,
          toDate: toDate,
          size: size,
          style: style,
          logo: logo,
        );
      } catch (e) {
        failures.add(BatchLedgerFailure(
          retailerId: job.retailerId,
          retailerName: job.retailerName,
          stage: BatchFailureStage.build,
          reason: e.toString().replaceAll('Exception: ', ''),
        ));
      }
      onProgress?.call(i + 1, jobs.length, job.retailerName);
    }

    final succeeded = jobs.length - failures.length;
    return BatchLedgerResult(
      document: succeeded == 0 ? null : doc,
      totalRequested: jobs.length,
      succeeded: succeeded,
      failures: failures,
    );
  }

  /// Individual build — Download All / Download Selected. Unlike
  /// buildBatch() above (one shared pw.Document, for Print, which stays
  /// combined into one job by design), this produces ONE fully
  /// independent pw.Document PER retailer — each with its own embedded
  /// fonts and its own copy of the company logo, because each file must
  /// be valid and shareable entirely on its own with no dependency on
  /// any other file or on this app still being open. That per-file
  /// duplication (rather than the byte-size optimization buildBatch does)
  /// is the necessary cost of "N separate files" being the actual
  /// deliverable.
  ///
  /// Because each retailer's pw.Document is independent, a failure for
  /// one retailer — whether in the eager CustomerLedgerTableData.from()
  /// step or in that retailer's own doc.save() — can NEVER affect any
  /// other retailer's file. That's a strictly better isolation guarantee
  /// than buildBatch() can offer, where all retailers share one Document
  /// and a layout failure only surfaces at the single shared doc.save().
  static Future<IndividualBuildResult> buildIndividual({
    required List<RetailerLedgerJob> jobs,
    required String companyName,
    required DateTime fromDate,
    required DateTime toDate,
    required PrintSheetSize size,
    ReportPrintStyle style = ReportPrintStyle.color,
    void Function(int done, int total, String currentRetailerName)? onProgress,
  }) async {
    if (jobs.isEmpty) {
      return const IndividualBuildResult(files: [], totalRequested: 0, failures: []);
    }

    final font = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();

    // Same trader for every retailer in the batch → same logo URL.
    // Fetched once, reused by reference across every independent
    // document rather than re-downloaded per retailer.
    final firstHeader = (jobs.first.data['header'] as Map?)?.cast<String, dynamic>() ?? {};
    final logo = await ReportPdfGenerator.fetchLogo(firstHeader['company_logo'] as String?);

    final files = <IndividualLedgerFile>[];
    final failures = <BatchLedgerFailure>[];

    for (var i = 0; i < jobs.length; i++) {
      final job = jobs[i];
      try {
        final doc = pw.Document(theme: pw.ThemeData.withFont(base: font, bold: bold));
        _addLedgerPage(
          doc,
          data: job.data,
          companyName: companyName,
          fromDate: fromDate,
          toDate: toDate,
          size: size,
          style: style,
          logo: logo,
        );
        final bytes = await doc.save();
        files.add(IndividualLedgerFile(
          retailerId: job.retailerId,
          retailerName: job.retailerName,
          filename: individualFilename(retailerName: job.retailerName, date: fromDate),
          bytes: bytes,
        ));
      } catch (e) {
        failures.add(BatchLedgerFailure(
          retailerId: job.retailerId,
          retailerName: job.retailerName,
          stage: BatchFailureStage.build,
          reason: e.toString().replaceAll('Exception: ', ''),
        ));
      }
      onProgress?.call(i + 1, jobs.length, job.retailerName);
    }

    return IndividualBuildResult(files: files, totalRequested: jobs.length, failures: failures);
  }

  /// `CustomerName_CustomerLedger_<date>.pdf` — sanitized for
  /// filesystem/share-sheet safety (strips characters invalid on
  /// Windows/Android/iOS filesystems, collapses whitespace to
  /// underscores). [date] is the report's from-date, matching the
  /// dating convention already used by the single-retailer filenames.
  static String individualFilename({required String retailerName, required DateTime date}) {
    final safe = retailerName
        .trim()
        .replaceAll(RegExp(r'[\/\\:*?"<>|]'), '')
        .replaceAll(RegExp(r'\s+'), '_');
    final name = safe.isEmpty ? 'Customer' : safe;
    return '${name}_CustomerLedger_${DateFormat('yyyyMMdd').format(date)}.pdf';
  }

  /// Appends ONE retailer's ledger to [doc]. Full Sheet → one pw.MultiPage
  /// (unchanged). Half Sheet → A4 portrait pages with two stacked halves
  /// each (see _addHalfSheetPages). Single-retailer and batch paths share
  /// this one implementation so they can never drift apart on layout,
  /// numbers, or styling. Not exposed outside this class.
  static void _addLedgerPage(
      pw.Document doc, {
        required Map<String, dynamic> data,
        required String companyName,
        required DateTime fromDate,
        required DateTime toDate,
        required PrintSheetSize size,
        required ReportPrintStyle style,
        required pw.MemoryImage? logo,
      }) {
    // Same row-building logic as every other Customer Ledger PDF path —
    // no reimplementation, no risk of the numbers disagreeing.
    final header = (data['header'] as Map?)?.cast<String, dynamic>() ?? {};
    final opening = (data['opening_balance'] as num?)?.toDouble() ?? 0;
    final t = CustomerLedgerTableData.from(data);

    final customerName = header['retailer_name'] as String? ?? 'Customer';
    final openingLabel = Fmt.amount(opening);
    final bw = style == ReportPrintStyle.blackAndWhite;
    // Scale factor for the shared header widgets on Half Sheet, where each
    // half only has ~131mm of height.
    final headerScale = size.isHalf ? 0.8 : 1.0;

    // Shared builders so Full and Half produce the identical header/BILL TO
    // content — only the scale differs.
    pw.Widget companyHeader() => ReportPdfGenerator.richCompanyHeader(
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
    );

    // BILL TO — same shared block the Table PDF uses. Any field genuinely
    // absent for this customer is simply omitted, not shown blank.
    pw.Widget billTo() => ReportPdfGenerator.billToBlock(
      customerName: header['retailer_name'] as String? ?? customerName,
      contactPerson: header['retailer_owner'] as String?,
      mobile: header['retailer_phone'] as String?,
      areaOrAddress: (header['retailer_address'] as String?)?.isNotEmpty == true
          ? header['retailer_address'] as String?
          : header['retailer_area'] as String?,
      bw: bw,
      scale: headerScale,
    );

    if (size.isHalf) {
      _addHalfSheetPages(
        doc,
        headers: t.headers,
        rows: t.rows,
        totals: t.totals,
        size: size,
        bw: bw,
        companyHeader: companyHeader,
        billTo: billTo,
      );
      return;
    }

    // ── FULL SHEET (unchanged flow) ────────────────────────────────────────
    doc.addPage(pw.MultiPage(
      pageFormat: size.pageFormat,
      margin: size.margin,
      // Repeats on every page — this is what makes the customer header
      // survive a page break, unlike the existing Table PDF's identity
      // block (which lives in page content, not this header slot).
      header: (_) => companyHeader(),
      // ctx.pageNumber / ctx.pagesCount — native to pw.MultiPage, no
      // manual page counting. Local to THIS retailer's pages only, which
      // is what we want in a batch PDF too (each retailer reads as its
      // own self-contained ledger, "Page 1 of 2" not "Page 47 of 300").
      footer: (ctx) => _printFooter(ctx, size, bw: bw),
      build: (_) => [
        billTo(),
        pw.SizedBox(height: 8),
        _printTable(t.headers, t.rows, t.totals, size, bw: bw),
      ],
    ));
  }

  /// HALF SHEET: splits the ledger rows into "halves" of fixed row capacity,
  /// then places two halves on each A4 portrait page — top half and bottom
  /// half — with a dashed cut line at exactly 148.5mm. Every half repeats
  /// the company header, BILL TO and the table header row, and carries its
  /// own "Page X of Y" footer. When the ledger needs more than two halves,
  /// the rest continues on the next A4 sheet.
  static void _addHalfSheetPages(
      pw.Document doc, {
        required List<String> headers,
        required List<List<String>> rows,
        required List<String> totals,
        required PrintSheetSize size,
        required bool bw,
        required pw.Widget Function() companyHeader,
        required pw.Widget Function() billTo,
      }) {
    // Opening / data rows + the Total/Closing row, chunked by capacity.
    final all = <List<String>>[...rows, totals];
    final cap = _halfRowsPerSlot;
    final chunks = <List<List<String>>>[];
    for (var i = 0; i < all.length; i += cap) {
      chunks.add(all.sublist(i, math.min(i + cap, all.length)));
    }
    // Never leave the Total/Closing row alone in its own half: pull the last
    // data row of the previous half down with it.
    if (chunks.length > 1 &&
        chunks.last.length == 1 &&
        chunks[chunks.length - 2].length > 1) {
      final prev = chunks[chunks.length - 2];
      chunks.last.insert(0, prev.removeLast());
    }
    final totalHalves = chunks.length;

    // One complete half (header block → table → spacer → footer pinned to
    // the bottom of the half). Fresh widget instances every call.
    pw.Widget half(int idx) => pw.SizedBox(
      height: _halfSlotH,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          companyHeader(),
          billTo(),
          pw.SizedBox(height: _halfBlockGap),
          _halfTable(headers, chunks[idx], size, bw: bw),
          pw.Spacer(),
          _printFooterText(idx + 1, totalHalves, size, bw: bw),
        ],
      ),
    );

    // Space between the two halves; the cut line sits in the exact middle,
    // i.e. at y = A4 height / 2 = 420.945pt = 148.5mm.
    final gap = PdfPageFormat.a4.height - 2 * _halfTopMargin - 2 * _halfSlotH;
    pw.Widget cutGap() => pw.SizedBox(
      height: gap,
      child: _halfShowCutLine
          ? pw.Column(children: [
        pw.SizedBox(height: gap / 2 - 0.25),
        pw.Container(
          height: 0.5,
          decoration: pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(
                color: bw ? PdfColors.black : PdfColors.grey500,
                width: 0.5,
                style: pw.BorderStyle.dashed,
              ),
            ),
          ),
        ),
      ])
          : pw.SizedBox(height: gap),
    );

    for (var i = 0; i < totalHalves; i += 2) {
      final hasSecond = i + 1 < totalHalves;
      doc.addPage(pw.Page(
        pageFormat: size.pageFormat, // A4 portrait
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(
              _halfSideMargin, _halfTopMargin, _halfSideMargin, 0),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            mainAxisAlignment: pw.MainAxisAlignment.start,
            children: [
              half(i),
              cutGap(),
              hasSecond ? half(i + 1) : pw.SizedBox(height: _halfSlotH),
            ],
          ),
        ),
      ));
    }
  }

  // HALF SHEET table. Built by hand (instead of TableHelper.fromTextArray) so
  // every row is EXACTLY _halfRowH tall: each cell is one line that shrinks
  // to fit its column (FittedBox.scaleDown) instead of wrapping onto a second
  // line. That makes rows-per-half exact, so a half can never overflow its
  // slot — a table taller than its slot is dropped by the pdf package, which
  // is what made the table and footer vanish in the earlier version (cells
  // like Ref No and the rupee amounts were wrapping to two lines).
  static pw.Widget _halfTable(
      List<String> headers,
      List<List<String>> data,
      PrintSheetSize size,
      {bool bw = false}
      ) {
    const aligns = <pw.Alignment>[
      pw.Alignment.centerLeft,
      pw.Alignment.centerLeft,
      pw.Alignment.centerLeft,
      pw.Alignment.centerLeft,
      pw.Alignment.centerRight,
      pw.Alignment.centerRight,
      pw.Alignment.centerRight,
      pw.Alignment.centerRight,
      pw.Alignment.centerRight,
    ];
    final headStyle = pw.TextStyle(
        fontSize: size.tableHeaderFontSize, fontWeight: pw.FontWeight.bold,
        color: bw ? PdfColors.black : PdfColors.white);
    final cellStyle = pw.TextStyle(
        fontSize: size.tableCellFontSize, color: bw ? PdfColors.black : _dark);

    pw.Widget cell(String text, int col, pw.TextStyle style) {
      // Empty cells (blank Payment, blank Ref No on summary rows, ...) must
      // NOT go through FittedBox: a zero-width child trips the pdf package's
      // `width > 0.0` assertion (geometry.dart) and the whole page fails to
      // build. A plain fixed-height box keeps the row height identical.
      if (text.trim().isEmpty) return pw.SizedBox(height: _halfRowH);
      return pw.Container(
        height: _halfRowH,
        alignment: aligns[col],
        padding: pw.EdgeInsets.symmetric(horizontal: size.cellPaddingH),
        child: pw.FittedBox(
          fit: pw.BoxFit.scaleDown,
          child: pw.Text(text, style: style),
        ),
      );
    }

    pw.TableRow row(List<String> r, pw.TextStyle style, {pw.BoxDecoration? decoration}) =>
        pw.TableRow(
          decoration: decoration,
          children: [
            for (var c = 0; c < aligns.length; c++)
              cell(c < r.length ? r[c] : '', c, style),
          ],
        );

    return pw.Table(
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
      columnWidths: size.columnWidths,
      children: [
        row(
          headers,
          headStyle,
          decoration: bw
              ? const pw.BoxDecoration(
              color: PdfColors.white,
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 1.0)))
              : const pw.BoxDecoration(color: _primary),
        ),
        for (final r in data) row(r, cellStyle),
      ],
    );
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
      // layoutPdf's `format` parameter defaults to PdfPageFormat.standard,
      // completely separate from the pageFormat baked into `doc` above.
      // Without this, the print dialog assumes "standard" paper while the
      // real document is A4, which produces blank-space/wrong-size
      // symptoms. dynamicLayout: false stops the OS dialog's own
      // paper-size picker from re-requesting a different format than the
      // one this builder deliberately generated. Both Full Sheet and Half
      // Sheet are A4 portrait — Half Sheet already has its two halves laid
      // out INSIDE each A4 page, so this is exactly what gets printed,
      // sheet for sheet.
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

  // ── Bulk Print — prepared-document I/O primitives ───────────────────────
  //
  // buildBatch() above ONLY assembles the pw.Document (data → PDF) and
  // never touches Print/Share/Save — that split lets the caller (see
  // bulk_ledger_print_sheet.dart) inspect `failures` and show the
  // "N of M included" decision to the trader BEFORE anything is printed
  // or saved, so an incomplete batch is only ever produced with the
  // trader's explicit go-ahead, never silently.
  //
  // "Print" opens the native print/layout dialog (Printing.layoutPdf) —
  // same mechanism the single-retailer flow already uses.
  //
  // "Save PDF" is a SEPARATE method from the existing "Share" action
  // above (different call site, different button, never reused for
  // Share) per the explicit requirement that Save must not be treated as
  // Share. Today it is implemented via Printing.sharePdf() because this
  // project has no direct-file-write dependency (path_provider was
  // deliberately removed earlier after a Flutter-Web crash — see
  // report_pdf_generator.dart's fetchLogo comment) — on Flutter Web this
  // already performs a genuine direct browser download with no chooser;
  // on Android/iOS it currently opens the OS share sheet, same underlying
  // call as "Share" would use, until a real direct-save dependency is
  // added. Isolating it in its own method now means that swap is a
  // one-line change with no call-site impact later.
  static Future<void> printPreparedDocument({
    required pw.Document doc,
    required PdfPageFormat pageFormat,
    required String filename,
  }) async {
    await Printing.layoutPdf(
      onLayout: (fmt) async => doc.save(),
      name: filename,
      format: pageFormat,
      dynamicLayout: false,
    );
  }

  static Future<void> savePreparedDocument({
    required pw.Document doc,
    required String filename,
  }) async {
    final bytes = await doc.save();
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }

  // ── Footer — "Page X of Y" on every page, via native MultiPage context ──
  // (Full Sheet.)
  static pw.Widget _printFooter(pw.Context ctx, PrintSheetSize size, {bool bw = false}) =>
      _printFooterText(ctx.pageNumber, ctx.pagesCount, size, bw: bw);

  // Footer with explicit numbers (used directly by Half Sheet, where each
  // half is its own "page" of the statement, exactly like Page 1 of 2 /
  // Page 2 of 2 in a normal printed statement).
  static pw.Widget _printFooterText(int page, int total, PrintSheetSize size, {bool bw = false}) => pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text('RoosterHub Trader OS',
          style: pw.TextStyle(fontSize: size.footerFontSize, color: bw ? PdfColors.black : _subText)),
      pw.Text('Page $page of $total',
          style: pw.TextStyle(fontSize: size.footerFontSize, color: bw ? PdfColors.black : _subText)),
    ],
  );

  // ── Ledger table — TableHelper.fromTextArray. Full Sheet relies on its
  //    native header-repeat across MultiPage breaks; Half Sheet passes one
  //    pre-chunked set of rows per half (header row drawn in every half).
  //
  //    Note (Print Style audit): fromTextArray's cellStyle/headerStyle are
  //    static per-call values, not per-row callbacks, so unlike the shared
  //    _table() in report_pdf_generator.dart, this builder cannot bold or
  //    thick-border individual Opening/Summary/Closing rows without a
  //    larger rewrite to a manually-built pw.Table. Scoped out of this
  //    pass — flagged, not silently skipped. Right-alignment of numeric
  //    columns is native here via cellAlignments for both Color and
  //    Black & White.
  static pw.Widget _printTable(
      List<String> headers,
      List<List<String>> rows,
      List<String> totals,
      PrintSheetSize size,
      {bool bw = false}
      ) => _printTableData(headers, [...rows, totals], size, bw: bw);

  // Styling body factored out so Full Sheet and Half Sheet share one
  // TableHelper.fromTextArray configuration — no divergence risk between
  // the two print sizes' table styling. (Half Sheet's halves use
  // _halfTable below, which needs fixed-height single-line rows.)
  static pw.Widget _printTableData(
      List<String> headers,
      List<List<String>> data,
      PrintSheetSize size,
      {bool bw = false}
      ) {
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
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