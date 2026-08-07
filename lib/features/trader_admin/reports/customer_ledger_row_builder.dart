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
    this.refNo,
    this.type,
    required this.description,
    this.kg,
    this.rate,
    this.saleAmt,
    this.paymentAmt,
    required this.balance,
  });

  /// Null on continuation lines (2nd+ product of the same invoice) — the
  /// caller must not repeat Date/Ref No/Type in that case.
  final String? date;
  final String? refNo;
  final String? type;

  final String description;
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
      // ★ Order Remarks — appended to the first (or only) printed line for
      // this raw row, so it shows once per order/invoice, not repeated on
      // every product line of a multi-product invoice.
      final orderRemarks = (r['order_remarks'] as String?)?.trim();
      String _withRemarks(String base) =>
          (orderRemarks == null || orderRemarks.isEmpty) ? base : '$base  ·  Remarks: $orderRemarks';

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
            refNo: i == 0 ? refNumber : null,
            type: i == 0 ? typeLabel(sourceType) : null,
            description: i == 0 ? _withRemarks((line['product_name'] as String?) ?? '—') : (line['product_name'] as String?) ?? '—',
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
          refNo: refNumber,
          type: typeLabel(sourceType),
          description: _withRemarks(description.isEmpty ? 'Sale' : description),
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
          description: _withRemarks(desc),
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
          refNo: refNumber,
          type: typeLabel(sourceType),
          description: _withRemarks(desc),
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
        description: _withRemarks(description.isEmpty ? typeLabel(sourceType) : description),
        saleAmt: isDebit ? amount : null,
        paymentAmt: !isDebit ? amount : null,
        balance: runningBalance,
      ));
    }

    return out;
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
  });

  final List<String> headers;
  final List<List<String>> rows;
  final List<String> totals;

  static const List<String> _headers = [
    'Date', 'Ref No', 'Type', 'Product / Description', 'Kg', 'Rate', 'Sale', 'Payment', 'Balance'
  ];

  static String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final d = DateTime.tryParse(iso);
    return d == null ? '' : DateFormat('dd-MMM').format(d);
  }

  static String _fmtNum(double? v) =>
      v == null ? '' : v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2);

  factory CustomerLedgerTableData.from(Map<String, dynamic> data) {
    final opening = (data['opening_balance'] as num?)?.toDouble() ?? 0;
    final closing = (data['closing_balance'] as num?)?.toDouble() ?? 0;
    final printRows = CustomerLedgerRowBuilder.build(data);

    // Period Summary — Total Birds / Kg / Sales / Payment Collected, for the
    // selected date range only (excludes Opening/Closing Balance, matching
    // the requirement exactly). Reuses the backend's own already-computed
    // `summary` object from get_retailer_statement() — no new calculation
    // logic here, so this can never drift from the authoritative ledger
    // math (running balance / opening / closing are untouched).
    final summary = (data['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    final totalBirds = (summary['total_birds'] as num?)?.toInt() ?? 0;
    final totalKg = (summary['total_weight_kg'] as num?)?.toDouble() ?? 0;
    final totalSales = (summary['total_invoiced'] as num?)?.toDouble() ?? 0;
    final totalPayment = (summary['total_collections'] as num?)?.toDouble() ?? 0;

    final rows = <List<String>>[
      ['', 'OPEN', 'Opening', 'Opening Balance', '', '', '', '', Fmt.amount(opening)],
      for (final r in printRows)
        [
          r.date == null ? '' : _fmtDate(r.date),
          r.refNo ?? '',
          r.type ?? '',
          r.description,
          _fmtNum(r.kg),
          _fmtNum(r.rate),
          r.saleAmt == null ? '' : Fmt.amount(r.saleAmt!),
          r.paymentAmt == null ? '' : Fmt.amount(r.paymentAmt!),
          Fmt.amount(r.balance),
        ],
      // Period Summary row — sits above Closing Balance. Birds has no
      // dedicated column (adding one would reshape every row of every
      // Customer Ledger ever rendered), so it's folded into the
      // Description cell alongside the "Period Summary" label instead.
      [
        '', '', 'Summary',
        'Period Summary  ·  Total Birds: $totalBirds',
        _fmtNum(totalKg), '',
        Fmt.amount(totalSales), Fmt.amount(totalPayment), '',
      ],
    ];

    final totals = ['', '', '', 'Closing Balance', '', '', '', '', Fmt.amount(closing)];

    return CustomerLedgerTableData(headers: _headers, rows: rows, totals: totals);
  }
}