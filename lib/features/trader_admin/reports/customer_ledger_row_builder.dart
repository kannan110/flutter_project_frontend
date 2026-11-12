import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CustomerLedgerRowBuilder
//
// Turns the raw `rows` array returned by get_retailer_statement() into the
// exact print-line sequence the Customer Ledger Report needs — one line per
// product under a multi-product invoice (Date/Ref/Type shown once, blank on
// continuation lines), a running Balance recomputed per product line, and a
// single line for every other transaction type (Payment, Sales Return,
// Credit Note, Debit Note, Adjustment).
//
// This is intentionally the ONLY place this flattening happens — both
// reports_hub_screen.dart's _rCustomerLedger() (on-screen table, rendered
// via the same _tbl()/ReportTableBlock framework every other report uses)
// and ReportPdfGenerator's customer-ledger PDF builder call this same
// class, so the on-screen table and the PDF can never drift apart. No business logic (balance math, opening/
// closing balance, agent resolution) lives here — all of that stays in
// get_retailer_statement() on the backend; this class only re-shapes
// already-computed numbers for display.
// ─────────────────────────────────────────────────────────────────────────────

class LedgerPrintRow {
  const LedgerPrintRow({
    this.date,
    this.docNo,
    this.manualDocNo,
    this.refNo,
    this.type,
    required this.description,
    this.product,
    this.sourceDate,
    this.sourceDocNo,
    this.sourceManualDocNo,
    this.birds,
    this.kg,
    this.rate,
    this.saleAmt,
    this.paymentAmt,
    required this.balance,
  });

  /// Null on continuation lines (2nd+ product of the same invoice) — the
  /// caller must not repeat Date/Ref No/Type in that case.
  final String? date;

  /// The sale's Quick Entry numbers (orders.doc_no / manual_doc_no). Only
  /// set on Sale lines — blank for orders that have none.
  final String? docNo;
  final String? manualDocNo;

  final String? refNo;
  final String? type;

  final String description;

  /// The item (product) on a sale/return line, e.g. "Broiler". Null for
  /// payments and other lines. Used by the Item filter.
  final String? product;

  /// The entry's own date and doc numbers, set on EVERY line (including a
  /// multi-product sale's 2nd+ lines, where [date]/[docNo] are blank), so a
  /// line can still show them when the Item filter hides its first line.
  final String? sourceDate;
  final String? sourceDocNo;
  final String? sourceManualDocNo;

  /// Number of birds on this line (blank when none were recorded).
  final int? birds;
  final double? kg;
  final double? rate;

  /// Debit-side amount (Sale / Debit Note / Adjustment-increase). Null when
  /// this line has no debit component.
  final double? saleAmt;

  /// Credit-side amount (Payment / Sales Return / Credit Note /
  /// Adjustment-decrease). Null when this line has no credit component.
  final double? paymentAmt;

  /// Running balance AFTER this line. For a multi-product invoice this is
  /// interpolated per product line (see builder below) purely for display —
  /// the authoritative per-transaction running_balance still comes from
  /// get_retailer_statement().
  final double balance;
}

class CustomerLedgerRowBuilder {
  const CustomerLedgerRowBuilder._();

  /// Shown after the item in Details for a sale made from the Stock Point.
  static const String stockPointLabel = 'Stock Point';

  static String typeLabel(String sourceType) => switch (sourceType) {
    'invoice' => 'Sale',
    'return' => 'Return',
    'payment' => 'Payment',
    'delivery' => 'Payment',
    'credit_note' => 'Credit',
    'debit_note' => 'Debit',
    'adjustment' => 'Adjust',
    _ => 'Adjust', // invoice_cancellation and any other future type
  };

  static double? _numOrNull(dynamic v) => (v as num?)?.toDouble();
  static int? _birdsOrNull(dynamic v) {
    final n = (v as num?)?.toInt();
    return (n == null || n <= 0) ? null : n;
  }
  static double _num(dynamic v) => (v as num?)?.toDouble() ?? 0;

  /// Builds the full print-line sequence for the given from/to range.
  /// [data] is the raw map returned by get_retailer_statement() (the
  /// 'rows' key specifically is flattened here).
  static List<LedgerPrintRow> build(Map<String, dynamic> data) {
    final rows = List<Map<String, dynamic>>.from(
        (data['rows'] as List?)?.map((e) => (e as Map).cast<String, dynamic>()) ?? []);

    final out = <LedgerPrintRow>[];

    for (final r in rows) {
      final sourceType = r['source_type'] as String? ?? '';
      // Opening Balance is rendered once, separately, from the top-level
      // opening_balance field — never as a row, to avoid double-display.
      if (sourceType == 'opening_balance') continue;

      final entryType = r['entry_type'] as String? ?? 'debit';
      final isDebit = entryType == 'debit';
      final amount = _num(r['amount']);
      final runningBalance = _num(r['running_balance']);
      final refNumber = r['ref_number'] as String?;
      final entryDateStr = r['entry_date'] as String?;
      final description = (r['description'] as String? ?? '').trim();
      final docNo = r['doc_no'] as String?;
      final manualDocNo = r['manual_doc_no'] as String?;
      // ★ Order Remarks — appended to the first (or only) printed line for
      // this raw row, so it shows once per order/invoice, not repeated on
      // every product line of a multi-product invoice.
      final orderRemarks = (r['order_remarks'] as String?)?.trim();
      String withRemarks(String base) =>
          (orderRemarks == null || orderRemarks.isEmpty) ? base : '$base  ·  Remarks: $orderRemarks';
      // Stock Point sale (orders.source = 'in_house', via get_retailer_
      // statement's order_source): every line of it says so in Details.
      final isStockPoint = (r['order_source'] as String?) == 'in_house';
      String withSource(String base) => isStockPoint ? '$base · $stockPointLabel' : base;

      final rateBreakdown = (r['rate_breakdown'] as List?)
          ?.map((e) => (e as Map).cast<String, dynamic>())
          .toList();

      if (sourceType == 'invoice' && rateBreakdown != null && rateBreakdown.isNotEmpty) {
        // Multi-product invoice — one print line per product, Date/Ref/Type
        // shown only on the first line. Balance is interpolated: start from
        // the balance *before* this invoice was applied, then add each
        // product's own line_total in turn, so each printed line shows the
        // balance as of that specific product line.
        var running = isDebit ? runningBalance - amount : runningBalance + amount;
        for (var i = 0; i < rateBreakdown.length; i++) {
          final line = rateBreakdown[i];
          final lineTotal = _num(line['line_total']);
          running += isDebit ? lineTotal : -lineTotal;
          final weightKg = _numOrNull(line['weight_kg']);
          final hasWeight = weightKg != null && weightKg > 0;
          out.add(LedgerPrintRow(
            date: i == 0 ? entryDateStr : null,
            docNo: i == 0 ? docNo : null,
            manualDocNo: i == 0 ? manualDocNo : null,
            refNo: i == 0 ? refNumber : null,
            type: i == 0 ? typeLabel(sourceType) : null,
            description: i == 0
                ? withRemarks(withSource((line['product_name'] as String?) ?? '—'))
                : withSource((line['product_name'] as String?) ?? '—'),
            product: line['product_name'] as String?,
            sourceDate: entryDateStr,
            sourceDocNo: docNo,
            sourceManualDocNo: manualDocNo,
            birds: _birdsOrNull(line['bird_count']),
            kg: hasWeight ? weightKg : null,
            rate: hasWeight ? _numOrNull(line['applied_rate']) : null,
            saleAmt: isDebit ? lineTotal : null,
            paymentAmt: !isDebit ? lineTotal : null,
            balance: running,
          ));
        }
        continue;
      }

      if (sourceType == 'invoice') {
        // Fallback — an invoice row with no invoice_items found (shouldn't
        // normally happen, kept defensive rather than silently dropping
        // the transaction from the printed ledger).
        final weightKg = _numOrNull(r['weight_kg']);
        out.add(LedgerPrintRow(
          date: entryDateStr,
          docNo: docNo,
          manualDocNo: manualDocNo,
          refNo: refNumber,
          type: typeLabel(sourceType),
          description: withRemarks(withSource(description.isEmpty ? 'Sale' : description)),
          sourceDate: entryDateStr,
          sourceDocNo: docNo,
          sourceManualDocNo: manualDocNo,
          birds: _birdsOrNull(r['birds']),
          kg: weightKg,
          rate: _numOrNull(r['rate_per_kg']),
          saleAmt: isDebit ? amount : null,
          paymentAmt: !isDebit ? amount : null,
          balance: runningBalance,
        ));
        continue;
      }

      if (sourceType == 'return') {
        final productName = r['return_product_name'] as String?;
        final reason = r['return_reason'] as String?;
        final desc = (productName != null && productName.isNotEmpty)
            ? '$productName Return'
            : (reason ?? (description.isEmpty ? 'Sales Return' : description));
        final weightKg = _numOrNull(r['weight_kg']);
        final hasWeight = weightKg != null && weightKg > 0;
        out.add(LedgerPrintRow(
          date: entryDateStr,
          refNo: refNumber,
          type: typeLabel(sourceType),
          description: withRemarks(desc),
          product: productName,
          sourceDate: entryDateStr,
          birds: _birdsOrNull(r['birds']),
          kg: hasWeight ? weightKg : null,
          rate: hasWeight ? _numOrNull(r['rate_per_kg']) : null,
          saleAmt: isDebit ? amount : null,
          paymentAmt: !isDebit ? amount : null,
          balance: runningBalance,
        ));
        continue;
      }

      if (sourceType == 'payment' || sourceType == 'delivery') {
        final mode = (r['payment_mode'] as String?)?.toUpperCase();
        final desc = description.isNotEmpty
            ? description
            : (mode != null && mode.isNotEmpty ? '$mode Received' : 'Payment Received');
        out.add(LedgerPrintRow(
          date: entryDateStr,
          // Cash collection's own Doc No (CSH-…) and Man. Doc No (Bill No).
          docNo: docNo,
          manualDocNo: manualDocNo,
          refNo: refNumber,
          type: typeLabel(sourceType),
          description: withRemarks(desc),
          sourceDate: entryDateStr,
          sourceDocNo: docNo,
          sourceManualDocNo: manualDocNo,
          saleAmt: isDebit ? amount : null,
          paymentAmt: !isDebit ? amount : null,
          balance: runningBalance,
        ));
        continue;
      }

      // Credit Note / Debit Note / Adjustment / invoice_cancellation /
      // anything else — no Kg or Rate, description is the reason.
      out.add(LedgerPrintRow(
        date: entryDateStr,
        refNo: refNumber,
        type: typeLabel(sourceType),
        description: withRemarks(description.isEmpty ? typeLabel(sourceType) : description),
        saleAmt: isDebit ? amount : null,
        paymentAmt: !isDebit ? amount : null,
        balance: runningBalance,
      ));
    }

    return out;
  }

  /// The items (products) sold or returned in this ledger, A–Z, for the
  /// Item filter. Read from the same rows the table shows.
  static List<String> items(Map<String, dynamic> data) {
    final set = <String>{};
    for (final r in build(data)) {
      final p = r.product?.trim();
      if (p != null && p.isNotEmpty) set.add(p);
    }
    return set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }
}

/// Ready-to-render string table for the shared ReportDataSet/_table()
/// framework — headers, rows, and a totals (Closing Balance) row, all
/// pre-formatted (Fmt.amount, dd-MMM dates) so the on-screen table and the
/// PDF read identical text. Built once here and reused by both
/// reports_hub_screen.dart's _rCustomerLedger() and ReportPdfGenerator's
/// Customer Ledger entry points.
class CustomerLedgerTableData {
  const CustomerLedgerTableData({
    required this.headers,
    required this.rows,
    required this.totals,
    required this.columnFlex,
  });

  final List<String> headers;
  final List<List<String>> rows;
  final List<String> totals;

  /// PDF column weights, one per header, fitted to this ledger's text.
  final List<double> columnFlex;

  static const List<String> _headers = [
    'Doc.No', 'Man.Doc.No', 'Date', 'Details', 'Birds', 'Kgs', 'Rate', 'Inv Amt', 'Receipt', 'Balance'
  ];

  // A sale's 2nd+ product lines leave Date blank; S.No skips those lines.
  static const int dateColumn = 2;

  static const int balanceColumn = 9;

  static const int detailsColumn = 3;

  /// Column weights from the widest text in each column, so amounts and
  /// doc numbers fit on one line. [flexibleColumn] (Details) is capped so a
  /// long remark can't squeeze the number columns.
  static List<double> fitFlex(List<String> headers, List<List<String>> rows,
      {int? flexibleColumn}) {
    final widest = [for (final h in headers) h.length];
    for (final r in rows) {
      for (var c = 0; c < r.length && c < widest.length; c++) {
        if (r[c].length > widest[c]) widest[c] = r[c].length;
      }
    }
    return [
      for (var c = 0; c < widest.length; c++)
        (c == flexibleColumn ? widest[c].clamp(12, 28) : widest[c].clamp(3, 18)) + 1.0,
    ];
  }

  static String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final d = DateTime.tryParse(iso);
    return d == null ? '' : DateFormat('dd/MM/yyyy').format(d);
  }

  static String _fmtNum(double? v) =>
      v == null ? '' : v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2);

  factory CustomerLedgerTableData.from(Map<String, dynamic> data) {
    final opening = (data['opening_balance'] as num?)?.toDouble() ?? 0;
    final closing = (data['closing_balance'] as num?)?.toDouble() ?? 0;
    // Item filter (data['item_filter'], set by the Customer Ledger screen):
    // keep only that item's sale/return lines. Payments and other items are
    // hidden; Opening and Closing Balance stay as they are. A kept line that
    // was a 2nd+ product of a sale gets its sale's date and bill numbers.
    final item = (data['item_filter'] as String?)?.trim().toLowerCase();
    final filtered = item != null && item.isNotEmpty;
    final allRows = CustomerLedgerRowBuilder.build(data);
    final printRows = !filtered
        ? allRows
        : [
            for (final r in allRows)
              if ((r.product ?? '').trim().toLowerCase() == item)
                LedgerPrintRow(
                  date: r.sourceDate,
                  docNo: r.sourceDocNo,
                  manualDocNo: r.sourceManualDocNo,
                  refNo: r.refNo,
                  type: r.type,
                  description: r.description,
                  product: r.product,
                  sourceDate: r.sourceDate,
                  sourceDocNo: r.sourceDocNo,
                  sourceManualDocNo: r.sourceManualDocNo,
                  birds: r.birds,
                  kg: r.kg,
                  rate: r.rate,
                  saleAmt: r.saleAmt,
                  paymentAmt: r.paymentAmt,
                  balance: r.balance,
                ),
          ];

    // Period Summary — Total Birds / Kg / Sales / Payment Collected, for the
    // selected date range only (excludes Opening/Closing Balance, matching
    // the requirement exactly). Reuses the backend's own already-computed
    // `summary` object from get_retailer_statement() — no new calculation
    // logic here, so this can never drift from the authoritative ledger
    // math (running balance / opening / closing are untouched).
    final summary = (data['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    // With the Item filter on, TOTAL is that item's lines only.
    final linesBirds = printRows.fold<int>(0, (sum, r) => sum + (r.birds ?? 0));
    final totalKg = filtered
        ? printRows.fold<double>(0, (sum, r) => sum + (r.kg ?? 0))
        : (summary['total_weight_kg'] as num?)?.toDouble() ?? 0;
    final totalBirds = filtered
        ? linesBirds
        : (summary['total_birds'] as num?)?.toInt() ?? linesBirds;
    final totalSales = filtered
        ? printRows.fold<double>(0, (sum, r) => sum + (r.saleAmt ?? 0))
        : (summary['total_invoiced'] as num?)?.toDouble() ?? 0;
    final totalPayment = filtered
        ? printRows.fold<double>(0, (sum, r) => sum + (r.paymentAmt ?? 0))
        : (summary['total_collections'] as num?)?.toDouble() ?? 0;

    final rows = <List<String>>[
      // Opening Balance amount sits under Inv Amt, as on the printed bill.
      ['', '', '', 'Opening Balance', '', '', '', Fmt.amount(opening), '', ''],
      for (final r in printRows)
        [
          r.docNo ?? '',
          r.manualDocNo ?? '',
          r.date == null ? '' : _fmtDate(r.date),
          r.description,
          r.birds == null ? '' : '${r.birds}',
          _fmtNum(r.kg),
          _fmtNum(r.rate),
          r.saleAmt == null ? '' : Fmt.amount(r.saleAmt!),
          r.paymentAmt == null ? '' : Fmt.amount(r.paymentAmt!),
          Fmt.amount(r.balance),
        ],
      // TOTAL row for the period, just above Closing Balance (bill format).
      [
        '', '', '', 'TOTAL',
        totalBirds > 0 ? '$totalBirds' : '', _fmtNum(totalKg), '',
        Fmt.amount(totalSales), Fmt.amount(totalPayment), '',
      ],
    ];

    // Closing Balance amount sits under Inv Amt, as on the printed bill.
    final totals = ['', '', '', 'Closing Balance', '', '', '', Fmt.amount(closing), '', ''];

    return CustomerLedgerTableData(
      headers: _headers,
      rows: rows,
      totals: totals,
      columnFlex: fitFlex(_headers, [...rows, totals], flexibleColumn: detailsColumn),
    );
  }
}