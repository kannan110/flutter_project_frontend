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
//               company header + logo, period dates, customer name and
//               opening balance, table header, rows, footer.
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
    1: pw.FlexColumnWidth(7.6),   // Ref No
    2: pw.FlexColumnWidth(3.7),   // Type
    3: pw.FlexColumnWidth(13.6),  // Product / Description
    4: pw.FlexColumnWidth(4.4),   // Kg
    5: pw.FlexColumnWidth(2.2),   // Rate
    6: pw.FlexColumnWidth(7.2),   // Sale
    7: pw.FlexColumnWidth(6.6),   // Payment
    8: pw.FlexColumnWidth(7.6),   // Balance
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

  // HALF SHEET MODE
  //   false (default) → ONE half per A4 portrait page, placed in the TOP half
  //     of the page; the bottom half of the page stays blank. Use this when
  //     the paper in the printer tray is a sheet that has been physically cut
  //     exactly in half (210 × 148.5mm): the printer still receives a normal
  //     A4 job, prints the top 148.5mm onto the half-sheet, ejects it, and the
  //     NEXT page (the next half of the ledger) prints on the next half-sheet.
  //   true → TWO halves stacked on one full A4 page with a dashed cut line
  //     (for printing on an uncut A4 sheet and cutting it afterwards).
  static const bool _halfTwoPerA4 = false;

  // Row capacity per half. Every Half Sheet table row (and the table
  // header row) is EXACTLY _halfRowH tall — single line, text shrinks to fit
  // its column instead of wrapping (see _halfTable) — and the header block
  // heights are budgeted below, so the number of rows per half is exact. If
  // you ever see the table touching the footer, raise _halfHeaderEst /
  // _halfHeaderContentH by a few points; if there is too much empty space
  // above the footer, lower them.
  static const double _halfRowH      = 15;   // every table row + table header row
  static const double _halfHeaderContentH = 66; // header row (company | dates | customer)
  static const double _halfHeaderEst = 74;   // header row + 3 + 1.2 divider + 3
  static const double _halfBlockGap  = 6;    // gap between header and table
  static const double _halfFooterH   = 12;   // footer line
  static const double _halfSafety    = 8;    // spare points

  static int get _halfRowsPerSlot {
    const avail = _halfSlotH -
        _halfHeaderEst -
        _halfBlockGap -
        _halfRowH - // the table's own header row
        _halfFooterH -
        _halfSafety;
    return math.max(1, (avail / _halfRowH).floor());
  }

  /// Case-insensitive A→Z by retailer name. Bulk Print / Bulk Download
  /// always go through this, so the printed pages and the downloaded files
  /// come out in alphabetical order no matter what order the caller passes
  /// the jobs in. Returns a NEW list — the caller's list is never mutated.
  static List<RetailerLedgerJob> _alphabetical(List<RetailerLedgerJob> jobs) {
    final sorted = List<RetailerLedgerJob>.of(jobs);
    sorted.sort((a, b) => a.retailerName
        .trim()
        .toLowerCase()
        .compareTo(b.retailerName.trim().toLowerCase()));
    return sorted;
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
  /// pages). Retailers are always laid out in ALPHABETICAL order.
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

    // Alphabetical A→Z, regardless of the order the caller passed in.
    final ordered = _alphabetical(jobs);

    final font = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();
    final doc = pw.Document(theme: pw.ThemeData.withFont(base: font, bold: bold));

    final firstHeader = (ordered.first.data['header'] as Map?)?.cast<String, dynamic>() ?? {};
    final logo = await ReportPdfGenerator.fetchLogo(firstHeader['company_logo'] as String?);

    final failures = <BatchLedgerFailure>[];
    for (var i = 0; i < ordered.length; i++) {
      final job = ordered[i];
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
      onProgress?.call(i + 1, ordered.length, job.retailerName);
    }

    final succeeded = ordered.length - failures.length;
    return BatchLedgerResult(
      document: succeeded == 0 ? null : doc,
      totalRequested: ordered.length,
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
  /// deliverable. Files are produced in ALPHABETICAL order.
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

    // Alphabetical A→Z, regardless of the order the caller passed in.
    final ordered = _alphabetical(jobs);

    final font = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();

    // Same trader for every retailer in the batch → same logo URL.
    // Fetched once, reused by reference across every independent
    // document rather than re-downloaded per retailer.
    final firstHeader = (ordered.first.data['header'] as Map?)?.cast<String, dynamic>() ?? {};
    final logo = await ReportPdfGenerator.fetchLogo(firstHeader['company_logo'] as String?);

    final files = <IndividualLedgerFile>[];
    final failures = <BatchLedgerFailure>[];

    for (var i = 0; i < ordered.length; i++) {
      final job = ordered[i];
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
      onProgress?.call(i + 1, ordered.length, job.retailerName);
    }

    return IndividualBuildResult(files: files, totalRequested: ordered.length, failures: failures);
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
        header: () => _halfHeader(
          companyName: companyName,
          phone: header['company_phone'] as String?,
          address: [header['company_address'], header['company_city']]
              .where((s) => s != null && (s as String).isNotEmpty).join(', '),
          email: header['company_email'] as String?,
          gstNumber: header['company_gst'] as String?,
          logo: logo,
          customerName: customerName,
          customerMobile: header['retailer_phone'] as String?,
          from: fromDate,
          to: toDate,
          openingLabel: openingLabel,
          size: size,
          bw: bw,
        ),
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
  /// the Half Sheet header (company, period dates, customer, opening
  /// balance) and the table header row, and carries its
  /// own "Page X of Y" footer. When the ledger needs more than two halves,
  /// the rest continues on the next A4 sheet.
  static void _addHalfSheetPages(
      pw.Document doc, {
        required List<String> headers,
        required List<List<String>> rows,
        required List<String> totals,
        required PrintSheetSize size,
        required bool bw,
        required pw.Widget Function() header,
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

    // One complete half (header block → table → closing block → spacer →
    // footer pinned to the bottom of the half). Fresh widget instances every
    // call. On the LAST half, the Closing Balance row is taken out of the
    // table and shown as a bold, header-sized line right below the table
    // (it does NOT expand to fill the leftover space).
    pw.Widget half(int idx) {
      final isLast = idx == totalHalves - 1;
      var tableRows = chunks[idx];
      List<String>? closingRow;

      if (isLast && tableRows.isNotEmpty) {
        final lastRow = tableRows.last;
        final label = lastRow.length > 3 ? lastRow[3].toLowerCase() : '';
        if (label.contains('closing balance')) {
          closingRow = lastRow;
          tableRows = tableRows.sublist(0, tableRows.length - 1);
        }
      }

      return pw.SizedBox(
        height: _halfSlotH,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            header(),
            pw.SizedBox(height: _halfBlockGap),
            _halfTable(headers, tableRows, size, bw: bw),
            if (closingRow != null) ...[
              // Closing Balance sits right below the table at a fixed,
              // header-like height. It no longer expands to fill the space.
              pw.SizedBox(height: 2),
              _halfClosingBlock(closingRow, bw: bw),
            ],
            pw.Spacer(),
            _printFooterText(idx + 1, totalHalves, size, bw: bw),
          ],
        ),
      );
    }

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

    const perSheet = _halfTwoPerA4 ? 2 : 1;
    for (var i = 0; i < totalHalves; i += perSheet) {
      final hasSecond = _halfTwoPerA4 && i + 1 < totalHalves;
      doc.addPage(pw.Page(
        pageFormat: size.pageFormat, // A4 portrait
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(
              _halfSideMargin, _halfTopMargin, _halfSideMargin, 0),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            mainAxisAlignment: pw.MainAxisAlignment.start,
            children: _halfTwoPerA4
                ? [
              half(i),
              cutGap(),
              hasSecond ? half(i + 1) : pw.SizedBox(height: _halfSlotH),
            ]
                : [
              // One half per page, in the top 148.5mm only.
              half(i),
            ],
          ),
        ),
      ));
    }
  }

  // HALF SHEET header (replaces the shared company header + BILL TO box on
  // Half Sheet only; Full Sheet still uses ReportPdfGenerator's widgets):
  //   left   → logo + company name and contact details
  //   centre → statement period "<from> - <to>" at the top centre
  //   right  → CUSTOMER LEDGER, customer name (bold, larger), opening
  //            balance (bold, larger), generated time
  // followed by a divider line. No BILL TO box. Texts are wrapped in
  // FittedBox(scaleDown) so long names shrink instead of wrapping, which
  // keeps the header height fixed (_halfHeaderContentH).
  static pw.Widget _halfHeader({
    required String companyName,
    String? phone,
    String? address,
    String? email,
    String? gstNumber,
    required pw.MemoryImage? logo,
    required String customerName,
    String? customerMobile,
    required DateTime from,
    required DateTime to,
    required String openingLabel,
    required PrintSheetSize size,
    bool bw = false,
  }) {
    final ink = bw ? PdfColors.black : _dark;
    final sub = bw ? PdfColors.black : _subText;
    final dateFmt = DateFormat('d MMM yyyy');

    pw.Widget fit(String text, pw.TextStyle style, pw.Alignment al) => pw.FittedBox(
      fit: pw.BoxFit.scaleDown,
      alignment: al,
      child: pw.Text(text, style: style),
    );

    bool has(String? v) => v != null && v.trim().isNotEmpty;
    final detailStyle = pw.TextStyle(fontSize: 7, color: sub);

    final left = pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logo != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(right: 6),
            child: pw.Image(logo, width: 32, height: 32, fit: pw.BoxFit.contain),
          ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (has(companyName))
                fit(
                  companyName.trim(),
                  pw.TextStyle(
                      fontSize: size.companyFontSize,
                      fontWeight: pw.FontWeight.bold,
                      color: ink),
                  pw.Alignment.centerLeft,
                ),
              pw.SizedBox(height: 2),
              if (has(phone)) pw.Text(phone!.trim(), style: detailStyle),
              if (has(address)) pw.Text(address!.trim(), style: detailStyle),
              if (has(email)) pw.Text(email!.trim(), style: detailStyle),
              if (has(gstNumber)) pw.Text('GSTIN: ${gstNumber!.trim()}', style: detailStyle),
            ],
          ),
        ),
      ],
    );

    final centre = pw.Align(
      alignment: pw.Alignment.topCenter,
      child: fit(
        '${dateFmt.format(from)} - ${dateFmt.format(to)}',
        pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: ink),
        pw.Alignment.center,
      ),
    );

    // Customer mobile (bold, under the customer name) — only when the customer
    // has one. In that case the 3 gaps tighten from 2pt to 1pt and the header
    // block grows by 4pt so the extra line never overflows (rows per half are
    // unchanged — the 4pt comes out of the spare points). No mobile → exactly
    // the same layout as before.
    final mobile = (customerMobile ?? '').trim();
    final hasMobile = mobile.isNotEmpty;
    final rGap = hasMobile ? 1.0 : 2.0;
    final contentH = hasMobile ? _halfHeaderContentH + 4 : _halfHeaderContentH;

    final right = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text('CUSTOMER LEDGER',
            style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: ink)),
        pw.SizedBox(height: rGap),
        fit(
          'Customer : ${customerName.trim().isEmpty ? 'Customer' : customerName.trim()}',
          pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold, color: ink),
          pw.Alignment.centerRight,
        ),
        if (hasMobile) ...[
          pw.SizedBox(height: rGap),
          fit(
            'Mobile : $mobile',
            pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: ink),
            pw.Alignment.centerRight,
          ),
        ],
        pw.SizedBox(height: rGap),
        fit(
          'Opening Balance : $openingLabel',
          pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: ink),
          pw.Alignment.centerRight,
        ),
        pw.SizedBox(height: rGap),
        pw.Text(
          'Generated: ${DateFormat('d MMM yyyy, HH:mm').format(DateTime.now())}',
          style: pw.TextStyle(fontSize: 6.5, color: sub),
        ),
      ],
    );

    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.SizedBox(
          height: contentH,
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(flex: 22, child: left),
              pw.Expanded(flex: 11, child: centre),
              pw.Expanded(flex: 17, child: right),
            ],
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Container(height: 1.2, color: ink),
        pw.SizedBox(height: 3),
      ],
    );
  }

  // HALF SHEET display-only cleanup (front-end only, no data change):
  //  • Product column: drop the word "Remarks" (and its colon),
  //    "Broiler · Remarks:angeripalayam" → "Broiler · angeripalayam"
  //  • Kg column: always show 2 decimals (40 → 40.00, 43 → 43.00)
  static List<String> _halfCleanRow(List<String> r) {
    final out = List<String>.from(r);

    if (out.length > 3) {
      out[3] = out[3]
          .replaceAll(RegExp(r'remarks\s*:?\s*', caseSensitive: false), '')
          .replaceAll(RegExp(r'\s*[·•\-]\s*$'), '') // no dangling separator if remarks was empty
          .trim();
    }

    if (out.length > 4) {
      final raw = out[4].trim();
      final v = double.tryParse(raw.replaceAll(',', ''));
      if (raw.isNotEmpty && v != null) {
        out[4] = raw.contains(',')
            ? NumberFormat('#,##0.00').format(v)
            : v.toStringAsFixed(2);
      }
    }
    return out;
  }

  // HALF SHEET: Closing Balance shown right below the table (last half only),
  // bold and header-sized. Fixed height (_halfClosingH), so it never grows to
  // fill the leftover space. FittedBox(scaleDown) keeps long amounts on one line.
  static const double _halfClosingH = 18;

  static pw.Widget _halfClosingBlock(List<String> row, {bool bw = false}) {
    final ink = bw ? PdfColors.black : _dark;
    final amount = (row.isNotEmpty && row.last.trim().isNotEmpty) ? row.last.trim() : '-';

    return pw.Container(
      height: _halfClosingH,
      alignment: pw.Alignment.centerRight,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: bw ? PdfColors.black : _primary, width: 1.0),
      ),
      child: pw.FittedBox(
        fit: pw.BoxFit.scaleDown,
        alignment: pw.Alignment.centerRight,
        child: pw.Row(
          mainAxisSize: pw.MainAxisSize.min,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text('Closing Balance :  ',
                style: pw.TextStyle(
                    fontSize: 13, fontWeight: pw.FontWeight.bold, color: ink)),
            pw.Text(amount,
                style: pw.TextStyle(
                    fontSize: 15, fontWeight: pw.FontWeight.bold, color: ink)),
          ],
        ),
      ),
    );
  }

  // HALF SHEET table. Built by hand (instead of TableHelper.fromTextArray) so
  // every row is EXACTLY _halfRowH tall: each cell is one line that shrinks
  // to fit its column (FittedBox.scaleDown) instead of wrapping onto a second
  // line. That makes rows-per-half exact, so a half can never overflow its
  // slot — a table taller than its slot is dropped by the pdf package, which
  // is what made the table and footer vanish in an earlier version.
  //
  // Emphasis: the Opening Balance row's balance cell, the whole Period
  // Summary row and the whole Closing Balance row are bold, and their
  // numbers are shown bigger than every other cell.
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
    final ink = bw ? PdfColors.black : _dark;
    final headStyle = pw.TextStyle(
        fontSize: size.tableHeaderFontSize, fontWeight: pw.FontWeight.bold,
        color: bw ? PdfColors.black : PdfColors.white);
    final cellStyle = pw.TextStyle(fontSize: size.tableCellFontSize, color: ink);
    final boldStyle = pw.TextStyle(
        fontSize: size.tableCellFontSize, fontWeight: pw.FontWeight.bold, color: ink);
    final bigStyle = pw.TextStyle(
        fontSize: size.tableCellFontSize + 2.5, // bigger than every other cell
        fontWeight: pw.FontWeight.bold, color: ink);

    pw.Widget cell(String text, int col, pw.TextStyle style) {
      // Empty cells must NOT go through FittedBox: a zero-width child trips
      // the pdf package's `width > 0.0` assertion (geometry.dart) and the
      // whole page fails to build. A plain fixed-height box keeps the row
      // height identical.
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

    pw.TableRow row(
        List<String> r,
        pw.TextStyle Function(int col) styleFor, {
          pw.BoxDecoration? decoration,
        }) =>
        pw.TableRow(
          decoration: decoration,
          children: [
            for (var c = 0; c < aligns.length; c++)
              cell(c < r.length ? r[c] : '', c, styleFor(c)),
          ],
        );

    String product(List<String> r) => r.length > 3 ? r[3].trim().toLowerCase() : '';
    String type(List<String> r) => r.length > 2 ? r[2].trim().toLowerCase() : '';
    bool isOpening(List<String> r) => product(r) == 'opening balance';
    bool isSummary(List<String> r) =>
        type(r) == 'summary' || product(r).startsWith('period summary');
    bool isClosing(List<String> r) => product(r).contains('closing balance');

    pw.TableRow bodyRow(List<String> raw) {
      final r = _halfCleanRow(raw);
      // Summary & Closing rows: label stays bold, all numbers big + bold
      if (isSummary(r) || isClosing(r)) {
        return row(r, (c) => c >= 4 ? bigStyle : boldStyle);
      }
      // Opening row: balance value big + bold
      if (isOpening(r)) {
        return row(r, (c) => c == aligns.length - 1 ? bigStyle : cellStyle);
      }
      return row(r, (_) => cellStyle);
    }

    return pw.Table(
      border: bw
          ? const pw.TableBorder(
        top: pw.BorderSide(color: PdfColors.black, width: 1.0),
        bottom: pw.BorderSide(color: PdfColors.black, width: 1.0),
        left: pw.BorderSide(color: PdfColors.black, width: 1.0),
        right: pw.BorderSide(color: PdfColors.black, width: 1.0),
        horizontalInside: pw.BorderSide(color: PdfColors.black, width: 0.4),
        verticalInside: pw.BorderSide(color: PdfColors.black, width: 0.4),
      )
          : pw.TableBorder.all(color: _border, width: 0.4),
      columnWidths: size.columnWidths,
      children: [
        row(
          headers,
          (_) => headStyle,
          decoration: bw
              ? const pw.BoxDecoration(
              color: PdfColors.white,
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 1.0)))
              : const pw.BoxDecoration(color: _primary),
        ),
        for (final r in data) bodyRow(r),
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
          ? const pw.TableBorder(
        top: pw.BorderSide(color: PdfColors.black, width: 1.0),
        bottom: pw.BorderSide(color: PdfColors.black, width: 1.0),
        left: pw.BorderSide(color: PdfColors.black, width: 1.0),
        right: pw.BorderSide(color: PdfColors.black, width: 1.0),
        horizontalInside: pw.BorderSide(color: PdfColors.black, width: 0.4),
        verticalInside: pw.BorderSide(color: PdfColors.black, width: 0.4),
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