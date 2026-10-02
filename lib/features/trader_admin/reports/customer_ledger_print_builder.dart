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
// for Customer Ledger. Only page size, margins, fonts, spacing, and
// column widths differ between the two — driven entirely by the
// [PrintSheetSize] parameter, both through the SAME _addLedgerPage /
// pw.MultiPage code path (AUDIT FIX v2: no separate half-sheet builder,
// no manual row-chunking or cut-line compositing — see the pageFormat
// getter below for why). No ledger business logic lives here: row
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

  // AUDIT FIX v2 (Half Sheet: A5 → true half-of-A4, as its OWN PDF page —
  // not two blocks composited onto one A4 canvas): a "half sheet" here is
  // a genuine PDF page measuring 210mm × 148.5mm — exactly half of an A4
  // sheet's 297mm height, in the SAME width/orientation as A4 (so the
  // header/table layout that was tuned for A4's 210mm width keeps its
  // proportions, unlike the old A5 — 148mm wide, 210mm tall — which was
  // the same area but the wrong orientation).
  //
  // Earlier this session tried compositing two such halves onto one
  // physical A4 canvas with a hand-drawn cut line, using manually
  // estimated row-per-half capacity (pw.Page has no auto-pagination).
  // That surfaced a real bug: on at least one physical printer/driver
  // (HP LaserJet M1005 via a Chrome print dialog), the SECOND half —
  // sitting right at the true bottom edge of the physical A4 sheet —
  // failed to print, most likely due to printer hardware-margin/paper-
  // size mismatch nibbling content that close to the real page edge.
  //
  // Per explicit instruction, each half is now its own separate PDF page
  // at this half-height pageFormat, going through the exact same
  // pw.MultiPage code path Full Sheet already uses (_addLedgerPage,
  // completely unmodified). That means: (a) pagination across halves is
  // pw.MultiPage's own native, well-tested overflow — no more hand-
  // estimated capacity constants, no more risk of a row landing wrong;
  // (b) nothing is ever positioned near a real physical A4 edge, since
  // every page IS its own physical unit at this format, not a slice
  // glued to the edge of a bigger one. To land two halves on one
  // physical A4 sheet of paper, use the print dialog's own "Pages per
  // sheet: 2" (a.k.a. N-up) option at print time — standard printer/
  // driver functionality, not something this PDF needs to hand-build.
  PdfPageFormat get pageFormat => isHalf
      ? PdfPageFormat(210 * PdfPageFormat.mm, 148.5 * PdfPageFormat.mm)
      : PdfPageFormat.a4;

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
    // Company Logo — ROOT CAUSE FIX (Full Sheet logo-missing audit): now
    // calls ReportPdfGenerator.fetchLogo (package:http, cross-platform
    // including Web) instead of a local dart:io HttpClient copy, which
    // silently failed on Web (dart:io doesn't exist there) — that's why
    // the logo never appeared despite traders.logo_url being valid and
    // the Profile screen showing it correctly (a different, working code
    // path — Image.network — was never involved in PDF generation at all).
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
  /// starting on its own page (each retailer is its own pw.MultiPage, so a
  /// retailer whose ledger itself spans multiple pages keeps working
  /// exactly as it does today — native TableHelper pagination per
  /// retailer, "Page X of Y" local to that retailer's own pages).
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
  /// actual pw.MultiPage layout (its header/footer/build closures) is lazy
  /// — the pdf package only invokes it during doc.save() — so a failure
  /// arising purely from PDF layout itself (not the data) would surface
  /// later, when the caller calls doc.save() to print/save. That case is
  /// still handled safely, just one level up: printPreparedDocument /
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

  /// Appends ONE retailer's ledger to [doc] as its own pw.MultiPage — the
  /// exact page-construction logic build() has always used, extracted
  /// unchanged so the single-retailer path and the batch path share one
  /// implementation and can never drift apart on layout, numbers, or
  /// styling. Not exposed outside this class.
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
    // Scale factor for the shared header widgets on Half Sheet's smaller
    // page — reuses size.identityFontSize's existing ratio (7/9) as the
    // scale.
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
      // manual page counting. Local to THIS retailer's pages only, which
      // is what we want in a batch PDF too (each retailer reads as its
      // own self-contained ledger, "Page 1 of 2" not "Page 47 of 300").
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
      // is A5/A4/half-A4, which is what produced the blank-space/wrong-
      // size symptom. dynamicLayout: false stops the OS dialog's own
      // paper-size picker from re-requesting a different format than the
      // one this builder deliberately generated. Half Sheet's PDF pages
      // are genuinely half-height (210×148.5mm — see PrintSheetSizeX.
      // pageFormat), not A4 with content composited onto it, so this
      // format hint is exactly what gets printed, page for page.
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
      ) => _printTableData(headers, [...rows, totals], size, bw: bw);

  // Styling body factored out from _printTable above so both Full Sheet
  // and Half Sheet (identical call shape, different [size]) share one
  // TableHelper.fromTextArray configuration — no divergence risk between
  // the two print sizes' table styling.
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