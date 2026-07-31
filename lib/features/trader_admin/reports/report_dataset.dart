// ─────────────────────────────────────────────────────────────────────────────
// ReportDataSet — the single source of truth for one report tabular data set.
//
// Built ONCE per table, then fed into three consumers that must always agree:
//   • ReportCardList  (mobile-friendly stacked cards — "Card View")
//   • ReportTable     (sortable, sticky-header business table — "Table View")
//   • ReportPdfGenerator (A4 PDF export)
//
// This is the fix for the duplicate-code problem found during the Reports
// module audit: previously each report screen built its own `heads`/`rows`
// for the on-screen table AND the PDF generator independently recomputed a
// similar-but-separate table from the raw report JSON. Any future change to
// a report columns only needs to happen once, here.
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// CustomerReportIdentity — THE standard compact identity block for every
// customer-specific PDF (Customer Ledger's Header PDF, its Table PDF, and
// any future customer-specific report). One shared model, one shared
// renderer (ReportPdfGenerator._customerIdentityBlock) — a trader printing
// 20-100 of these at once sees the exact same 3-line format on every one:
//
//   Customer : <name>
//   Area : <area>
//   <date range> | Opening : <opening>   (only the parts that apply)
//
// Deliberately excludes mobile, address, delivery agent, and any KPI/
// summary content — see report_pdf_generator.dart's _customerIdentityBlock.
// ─────────────────────────────────────────────────────────────────────────────
class CustomerReportIdentity {
  final String customerName;
  final String? area;
  final String? periodLabel;   // pre-formatted, e.g. "2 Jul 2026 - 31 Jul 2026"
  final String? openingLabel;  // pre-formatted, e.g. "₹1,29,176" — omitted if null
  const CustomerReportIdentity({
    required this.customerName,
    this.area,
    this.periodLabel,
    this.openingLabel,
  });
}

class ReportSummaryItem {
  final String label;
  final String value;
  const ReportSummaryItem(this.label, this.value);
}

class ReportDataSet {
  /// Report title, e.g. "Daily Summary", "Agent Performance".
  final String title;

  /// Optional date range this data covers (shown in PDF header / table caption).
  final DateTime? fromDate;
  final DateTime? toDate;

  /// Column headers, left to right.
  final List<String> headers;

  /// Row data — every inner list must be the same length as [headers].
  /// Values are pre-formatted display strings (currency, %, etc. already
  /// applied) so Card/Table/PDF never disagree on formatting.
  final List<List<String>> rows;

  /// Optional totals/footer row — same length as [headers]. Null = no footer.
  final List<String>? totals;

  /// Column indexes that should render with emphasis (bold/brand color) in
  /// both the Table View and the PDF.
  final List<int> highlightColumns;

  /// If set, cells in this column are shown in warning color (e.g. red) when
  /// their numeric value (after stripping `%`) is >= [warnThreshold].
  final int? warnColumn;
  final double warnThreshold;

  /// Optional KPI-style summary shown above the table (Card View header +
  /// PDF summary section). Independent of the row data itself.
  final List<ReportSummaryItem> summary;

  /// Optional Card View curation: which columns (besides the hero/
  /// highlighted one) belong in the primary "at a glance" mini-grid, in
  /// order. When null, Card View falls back to a generic default (the
  /// first couple of non-title columns) — this is purely a presentation
  /// hint, never affects Table View, PDF, or any calculation.
  final List<int>? cardPrimaryColumns;

  /// The ONE standard customer-identity block for customer-specific PDFs
  /// (see CustomerReportIdentity above). Null for every non-customer-
  /// specific report — no visual change for them. When set, the PDF
  /// renders this compact block and skips straight to the table (no
  /// SUMMARY section, no "DETAILS (n rows)" title, no extra spacing).
  final CustomerReportIdentity? customerIdentity;

  /// Whether this PDF uses the branded footer (RoosterHub Trader OS +
  /// generation timestamp) instead of the plain default footer every other
  /// report gets. Kept independent of [customerIdentity] specifically so
  /// the Header PDF and Table PDF — which both carry a customerIdentity —
  /// can still differ on this one aspect, as required.
  final bool useBrandedFooter;

  /// Raw get_retailer_statement() response, carried alongside
  /// [customerIdentity] so CustomerLedgerPrintBuilder (Full/Half Sheet
  /// Print) can call CustomerLedgerTableData.from() itself — reusing the
  /// same row-building logic as every other Customer Ledger PDF path
  /// rather than a fourth copy of it. Null for every report except
  /// Customer Ledger.
  final Map<String, dynamic>? customerLedgerData;

  const ReportDataSet({
    required this.title,
    required this.headers,
    required this.rows,
    this.fromDate,
    this.toDate,
    this.totals,
    this.highlightColumns = const [],
    this.warnColumn,
    this.warnThreshold = 0,
    this.summary = const [],
    this.cardPrimaryColumns,
    this.customerIdentity,
    this.useBrandedFooter = false,
    this.customerLedgerData,
  });

  int get columnCount => headers.length;
  int get rowCount => rows.length;
  bool get isEmpty => rows.isEmpty;

  /// Returns a copy with rows reordered — used by ReportTable column sort.
  /// Sorting is numeric-aware: strips currency symbols/commas/% before
  /// attempting a numeric compare, falling back to plain string compare.
  ReportDataSet sortedBy(int columnIndex, bool ascending) {
    if (columnIndex < 0 || columnIndex >= headers.length) return this;
    final copy = List<List<String>>.from(rows);
    copy.sort((a, b) {
      final av = _sortKey(a[columnIndex]);
      final bv = _sortKey(b[columnIndex]);
      int cmp;
      if (av is num && bv is num) {
        cmp = av.compareTo(bv);
      } else {
        cmp = a[columnIndex].toLowerCase().compareTo(b[columnIndex].toLowerCase());
      }
      return ascending ? cmp : -cmp;
    });
    return ReportDataSet(
      title: title,
      headers: headers,
      rows: copy,
      fromDate: fromDate,
      toDate: toDate,
      totals: totals,
      highlightColumns: highlightColumns,
      warnColumn: warnColumn,
      warnThreshold: warnThreshold,
      summary: summary,
      cardPrimaryColumns: cardPrimaryColumns,
      customerIdentity: customerIdentity,
      useBrandedFooter: useBrandedFooter,
      customerLedgerData: customerLedgerData,
    );
  }

  static dynamic _sortKey(String raw) {
    final cleaned = raw
        .replaceAll('₹', '')
        .replaceAll(',', '')
        .replaceAll('%', '')
        .replaceAll('kg', '')
        .replaceAll('birds', '')
        .trim();
    return num.tryParse(cleaned) ?? raw;
  }
}