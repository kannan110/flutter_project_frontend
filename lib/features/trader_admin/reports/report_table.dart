// ─────────────────────────────────────────────────────────────────────────────
// Reusable Reports UI kit — Card View, Table View, view toggle, and the
// export actions bar. One component set used by every report screen.
//
// Usage: wrap a single table data set in a ReportDataSet, then render
// ReportTableBlock(dataSet: ds, companyName: ..., fromDate: ..., toDate: ...).
// It owns its own view-mode + sort state and renders everything: the toggle,
// the actions bar, and the selected view.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:rooster_trader/features/trader_admin/reports/report_dataset.dart';
import 'package:rooster_trader/features/trader_admin/reports/report_pdf_generator.dart';

import '../../../core/theme/app_theme.dart';

enum ReportViewMode { card, table }

// ── The orchestrating block — this is what report screens actually use ──────
class ReportTableBlock extends StatefulWidget {
  const ReportTableBlock({
    super.key,
    required this.dataSet,
    required this.companyName,
    this.fromDate,
    this.toDate,
    this.initialMode = ReportViewMode.card,
  });

  final ReportDataSet dataSet;
  final String companyName;
  final DateTime? fromDate;
  final DateTime? toDate;
  final ReportViewMode initialMode;

  @override
  State<ReportTableBlock> createState() => _ReportTableBlockState();
}

class _ReportTableBlockState extends State<ReportTableBlock> {
  late ReportViewMode _mode = widget.initialMode;
  int? _sortCol;
  bool _sortAsc = true;
  bool _busy = false;

  ReportDataSet get _effectiveDataSet {
    final base = ReportDataSet(
      title: widget.dataSet.title,
      headers: widget.dataSet.headers,
      rows: widget.dataSet.rows,
      fromDate: widget.fromDate ?? widget.dataSet.fromDate,
      toDate: widget.toDate ?? widget.dataSet.toDate,
      totals: widget.dataSet.totals,
      highlightColumns: widget.dataSet.highlightColumns,
      warnColumn: widget.dataSet.warnColumn,
      warnThreshold: widget.dataSet.warnThreshold,
      summary: widget.dataSet.summary,
    );
    if (_sortCol == null) return base;
    return base.sortedBy(_sortCol!, _sortAsc);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: ${e.toString().replaceAll("Exception:", "").trim()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ds = _effectiveDataSet;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(color: kBorderLight),
        boxShadow: kCardShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
          child: Row(children: [
            ReportViewToggle(
              mode: _mode,
              onChanged: (m) => setState(() => _mode = m),
            ),
            const Spacer(),
            ReportActionsBar(
              busy: _busy,
              onDownload: () => _run(() => ReportPdfGenerator.generateFromDataSetAndShow(
                context: context,
                dataSet: ds,
                companyName: widget.companyName,
              )),
              onShare: () => _run(() => ReportPdfGenerator.shareFromDataSet(
                dataSet: ds,
                companyName: widget.companyName,
              )),
              onPrint: () => _run(() => ReportPdfGenerator.generateFromDataSetAndShow(
                context: context,
                dataSet: ds,
                companyName: widget.companyName,
              )),
            ),
          ]),
        ),
        if (ds.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 4, 14, 20),
            child: Text('No data for the selected range.',
                style: TextStyle(fontSize: 12, color: kTextHint)),
          )
        else if (_mode == ReportViewMode.card)
          ReportCardList(dataSet: ds)
        else
          ReportTable(
            dataSet: ds,
            sortColumn: _sortCol,
            sortAscending: _sortAsc,
            onSort: (col, asc) => setState(() {
              _sortCol = col;
              _sortAsc = asc;
            }),
          ),
      ]),
    );
  }
}

// ── View toggle — Card / Table segmented control ────────────────────────────
class ReportViewToggle extends StatelessWidget {
  const ReportViewToggle({super.key, required this.mode, required this.onChanged});
  final ReportViewMode mode;
  final ValueChanged<ReportViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, IconData icon, ReportViewMode m) {
      final selected = mode == m;
      return GestureDetector(
        onTap: () => onChanged(m),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? kNavy : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: selected ? Colors.white : kTextHint),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : kTextHint)),
          ]),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: kBgGrey,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorderLight),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg('Card', Icons.view_agenda_outlined, ReportViewMode.card),
        seg('Table', Icons.table_rows_outlined, ReportViewMode.table),
      ]),
    );
  }
}

// ── Actions bar — PDF / Excel / Print / Share, always visible, never a
//    hidden popup menu (per the zero-learning-curve spec: "avoid hidden
//    actions"). Excel is present but not yet wired to a real generator —
//    tapping it explains that plainly rather than hiding the button.
class ReportActionsBar extends StatelessWidget {
  const ReportActionsBar({
    super.key,
    required this.onDownload,
    required this.onShare,
    required this.onPrint,
    this.busy = false,
  });

  final VoidCallback onDownload;
  final VoidCallback onShare;
  final VoidCallback onPrint;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    Widget action(IconData icon, String label, VoidCallback onTap) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: kTextSub),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 9, color: kTextHint, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      action(Icons.download_outlined, 'PDF', onDownload),
      action(Icons.grid_on_outlined, 'Excel', () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Excel export — coming soon')),
        );
      }),
      action(Icons.print_outlined, 'Print', onPrint),
      action(Icons.share_outlined, 'Share', onShare),
    ]);
  }
}

// ── Card View — one row per record, redesigned for fast scanning ───────────
// Visual redesign pass (no business logic changed — presentation only):
//   - Hierarchy inverted: the primary business value (whichever column is
//     marked highlightColumns, e.g. Revenue/Amount) is now the largest,
//     boldest element — previously the row label (date/name) was bolder
//     than the actual number, backwards for a "business first" scan.
//   - Borders removed; a plain divider between rows (like a bank statement
//     or ledger) replaces the boxed-card-per-row look — no per-row
//     background tint, no border, no rounded container.
//   - Secondary fields collapsed into a single muted line instead of a
//     wrapping multi-line block — roughly 25% shorter per row.
//   - No icons — nothing here to remove, and nothing added.
class ReportCardList extends StatelessWidget {
  const ReportCardList({super.key, required this.dataSet});
  final ReportDataSet dataSet;

  @override
  Widget build(BuildContext context) {
    // The primary business value: the first highlighted column if the
    // report designates one (e.g. Revenue, Total), else the first column
    // after the label — matches how a trader scans for "the number that
    // matters" first.
    final heroCol = dataSet.highlightColumns.isNotEmpty
        ? dataSet.highlightColumns.first
        : (dataSet.headers.length > 1 ? 1 : null);

    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Column(children: [
          ...dataSet.rows.map((row) {
            final label = row.isNotEmpty ? row.first : '';
            final heroValue = heroCol != null && heroCol < row.length ? row[heroCol] : null;
            final isWarnHero = dataSet.warnColumn == heroCol &&
                heroValue != null &&
                (double.tryParse(heroValue.replaceAll('%', '')) ?? 0) >= dataSet.warnThreshold;

            // Everything else, one compact scannable line — excludes the label
            // (already shown) and the hero value (already prominent above).
            final secondary = <String>[];
            for (var i = 0; i < row.length; i++) {
              if (i == 0 || i == heroCol) continue;
              if (row[i].isEmpty) continue;
              secondary.add('${dataSet.headers[i]}: ${row[i]}');
            }

            return Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: kBorderLight, width: 0.5)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: kTextSub)),
                    if (secondary.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(secondary.join('   ·   '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: kTextHint)),
                    ],
                  ]),
                ),
                if (heroValue != null) ...[
                  const SizedBox(width: 10),
                  Text(heroValue,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isWarnHero ? Colors.red : kNavy)),
                ],
              ]),
            );
          }),
          if (dataSet.totals != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: kNavy, width: 1.5)),
              ),
              child: Wrap(spacing: 16, runSpacing: 4, children: [
                for (var i = 0; i < dataSet.totals!.length; i++)
                  if (dataSet.totals![i].isNotEmpty)
                    Text('${dataSet.headers[i]}: ${dataSet.totals![i]}',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: kNavy)),
              ]),
            ),
        ]));
  }
}

// ── Table View — professional business table ───────────────────────────────
// Sortable columns (tap header), sticky header (fixed row above a scrollable
// body, both synced to the same horizontal ScrollController), totals footer,
// ListView.builder body so large datasets do not build every row up front.
//
// Visual redesign pass (no business logic changed — presentation only):
//   - Per-column alignment is now DETECTED from the data (numeric-looking
//     columns right-align, text columns left-align) instead of a blanket
//     "column 0 left, everything else right" assumption.
//   - Header/body/footer all use the same fixed-height + centered-alignment
//     technique (previously the header used padding, the body used a fixed
//     height — inconsistent vertical rhythm between the two).
//   - Row height reduced (44→34) for a denser, spreadsheet-like feel.
//   - Column widths are still fully fixed (deterministic, no per-row
//     reflow) but sized per column from its header length, not one
//     blanket width for every non-first column.
//   - Subtle vertical gridlines between columns — the one concretely
//     "Excel" cue that was missing.
//   - Totals row uses a firmer top border (the classic Excel double-line
//     total cue) and tighter corner radius, matching enterprise software
//     rather than a consumer-app rounded card.
class ReportTable extends StatefulWidget {
  const ReportTable({
    super.key,
    required this.dataSet,
    this.sortColumn,
    this.sortAscending = true,
    this.onSort,
    this.rowHeight = 34,
    this.headerHeight = 34,
    this.maxBodyHeight = 420,
  });

  final ReportDataSet dataSet;
  final int? sortColumn;
  final bool sortAscending;
  final void Function(int column, bool ascending)? onSort;
  final double rowHeight;
  final double headerHeight;
  final double maxBodyHeight;

  @override
  State<ReportTable> createState() => _ReportTableState();
}

class _ReportTableState extends State<ReportTable> {
  final _hCtrl = ScrollController();

  static const double _minColWidth = 92;
  static const double _maxColWidth = 150;
  static const double _firstColWidth = 100;
  static const double _charWidth = 7.2; // rough monospaced-ish estimate for width sizing

  @override
  void dispose() {
    _hCtrl.dispose();
    super.dispose();
  }

  // Fixed width per column — sized from the header label (bounded), not one
  // blanket value for every column after the first. Still fully fixed/
  // deterministic once computed, no reflow while scrolling.
  double _widthFor(int col, List<String> headers) {
    if (col == 0) return _firstColWidth;
    final estimated = headers[col].length * _charWidth + 32;
    return estimated.clamp(_minColWidth, _maxColWidth);
  }

  List<double> _colWidths(ReportDataSet ds) =>
      List.generate(ds.headers.length, (c) => _widthFor(c, ds.headers));

  double _tableWidthOf(List<double> widths) => widths.fold(0.0, (a, b) => a + b);

  // Right-align a column when its values look numeric (after stripping
  // currency symbols, %, commas, units) — detected from the data itself
  // rather than assumed from position, so a text column that is not first
  // (e.g. "Status", "Agent") still reads left-aligned.
  bool _isNumericColumn(int c, ReportDataSet ds) {
    if (c == 0) return false;
    if (ds.rows.isEmpty) return true; // no data to check — default numeric-right, matches prior behavior
    var numericCount = 0;
    final sample = ds.rows.length > 20 ? ds.rows.sublist(0, 20) : ds.rows;
    for (final row in sample) {
      if (c >= row.length) continue;
      final cleaned = row[c].replaceAll(RegExp(r'[₹,%\sa-zA-Z]'), '');
      if (cleaned.isNotEmpty && num.tryParse(cleaned) != null) numericCount++;
    }
    return numericCount >= (sample.length * 0.6);
  }

  @override
  Widget build(BuildContext context) {
    final ds = widget.dataSet;
    final colWidths = _colWidths(ds);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: LayoutBuilder(builder: (ctx, constraints) {
        final naturalWidth = _tableWidthOf(colWidths);
        final tableWidth = naturalWidth < constraints.maxWidth ? constraints.maxWidth : naturalWidth;
        // If the table is being stretched to fill a wider viewport, grow the
        // LAST column only, so earlier columns keep their sized widths.
        final widths = List<double>.from(colWidths);
        if (tableWidth > naturalWidth && widths.isNotEmpty) {
          widths[widths.length - 1] += (tableWidth - naturalWidth);
        }
        return SingleChildScrollView(
          controller: _hCtrl,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(children: [
              // ── Sticky header ──────────────────────────────────────────
              Container(
                height: widget.headerHeight,
                decoration: const BoxDecoration(
                  color: kNavy,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
                ),
                child: Row(children: [
                  for (var c = 0; c < ds.headers.length; c++)
                    _headerCell(c, widths[c], ds),
                ]),
              ),
              // ── Scrollable body — ListView.builder for large datasets ──
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: widget.maxBodyHeight),
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  itemCount: ds.rows.length,
                  itemBuilder: (ctx, i) => _dataRow(ds.rows[i], i, widths, ds),
                ),
              ),
              // ── Totals / footer row ─────────────────────────────────────
              if (ds.totals != null) _footerRow(ds.totals!, widths, ds),
            ]),
          ),
        );
      }),
    );
  }

  Widget _headerCell(int c, double width, ReportDataSet ds) {
    final isSorted = widget.sortColumn == c;
    final rightAlign = _isNumericColumn(c, ds);
    return InkWell(
      onTap: widget.onSort == null
          ? null
          : () => widget.onSort!(c, isSorted ? !widget.sortAscending : true),
      child: Container(
        width: width,
        height: widget.headerHeight,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: c < ds.headers.length - 1
            ? const BoxDecoration(
            border: Border(right: BorderSide(color: Color(0x22FFFFFF), width: 1)))
            : null,
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: rightAlign ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (rightAlign && widget.onSort != null)
              Icon(isSorted ? (widget.sortAscending ? Icons.arrow_upward : Icons.arrow_downward) : Icons.unfold_more,
                  size: 11, color: isSorted ? kGoldLight : const Color(0xFF6B7BA8)),
            if (rightAlign && widget.onSort != null) const SizedBox(width: 3),
            Flexible(
              child: Text(ds.headers[c],
                  overflow: TextOverflow.ellipsis,
                  textAlign: rightAlign ? TextAlign.right : TextAlign.left,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: ds.highlightColumns.contains(c) ? kGoldLight : const Color(0xFFB4C6F4))),
            ),
            if (!rightAlign && widget.onSort != null) const SizedBox(width: 3),
            if (!rightAlign && widget.onSort != null)
              Icon(isSorted ? (widget.sortAscending ? Icons.arrow_upward : Icons.arrow_downward) : Icons.unfold_more,
                  size: 11, color: isSorted ? kGoldLight : const Color(0xFF6B7BA8)),
          ],
        ),
      ),
    );
  }

  Widget _dataRow(List<String> row, int index, List<double> widths, ReportDataSet ds) {
    return Container(
      height: widget.rowHeight,
      color: index.isOdd ? kBgGrey.withValues(alpha: 0.4) : Colors.white,
      child: Row(children: [
        for (var c = 0; c < row.length; c++) _dataCell(row[c], c, widths[c], ds, isLast: c == row.length - 1),
      ]),
    );
  }

  Widget _dataCell(String value, int c, double width, ReportDataSet ds, {required bool isLast}) {
    final isHi = ds.highlightColumns.contains(c);
    final isWarn = ds.warnColumn != null &&
        c == ds.warnColumn &&
        (double.tryParse(value.replaceAll('%', '')) ?? 0) >= ds.warnThreshold;
    final rightAlign = _isNumericColumn(c, ds);
    return Container(
      width: width,
      alignment: rightAlign ? Alignment.centerRight : Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: !isLast
          ? const BoxDecoration(
          border: Border(right: BorderSide(color: kBorderLight, width: 0.5)))
          : null,
      child: Text(value,
          overflow: TextOverflow.ellipsis,
          textAlign: rightAlign ? TextAlign.right : TextAlign.left,
          style: TextStyle(
              fontSize: 12,
              fontWeight: isHi ? FontWeight.w700 : FontWeight.w500,
              color: isWarn ? Colors.red : (isHi ? kNavy : kTextMain))),
    );
  }

  Widget _footerRow(List<String> totals, List<double> widths, ReportDataSet ds) {
    return Container(
      height: widget.rowHeight + 4,
      decoration: BoxDecoration(
        color: kBgGrey,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(6)),
        border: const Border(top: BorderSide(color: kNavy, width: 1.5)),
      ),
      child: Row(children: [
        for (var c = 0; c < totals.length; c++)
          Container(
            width: widths[c],
            alignment: (_isNumericColumn(c, ds) || c > 0) ? Alignment.centerRight : Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: c < totals.length - 1
                ? const BoxDecoration(border: Border(right: BorderSide(color: kBorderLight, width: 0.5)))
                : null,
            child: Text(totals[c],
                overflow: TextOverflow.ellipsis,
                textAlign: (_isNumericColumn(c, ds) || c > 0) ? TextAlign.right : TextAlign.left,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: ds.highlightColumns.contains(c) ? kNavy : kTextMain)),
          ),
      ]),
    );
  }
}