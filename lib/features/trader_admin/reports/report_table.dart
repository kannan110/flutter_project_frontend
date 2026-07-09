// ─────────────────────────────────────────────────────────────────────────────
// Reusable Reports UI kit — Card View, Table View, view toggle, and the
// export actions bar. One component set used by every report screen.
//
// Usage: wrap a single table's data in a ReportDataSet, then render
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

// ── Actions bar — Download PDF / Share / Print / Export (future) ───────────
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
    return PopupMenuButton<String>(
      tooltip: 'Export',
      icon: const Icon(Icons.ios_share_outlined, size: 18, color: kTextSub),
      onSelected: (v) {
        switch (v) {
          case 'download': onDownload();
          case 'share': onShare();
          case 'print': onPrint();
          case 'export':
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('CSV/Excel export — coming soon')),
            );
        }
      },
      itemBuilder: (ctx) => const [
        PopupMenuItem(value: 'download', child: Row(children: [
          Icon(Icons.download_outlined, size: 16), SizedBox(width: 8), Text('Download PDF'),
        ])),
        PopupMenuItem(value: 'share', child: Row(children: [
          Icon(Icons.share_outlined, size: 16), SizedBox(width: 8), Text('Share PDF'),
        ])),
        PopupMenuItem(value: 'print', child: Row(children: [
          Icon(Icons.print_outlined, size: 16), SizedBox(width: 8), Text('Print'),
        ])),
        PopupMenuDivider(),
        PopupMenuItem(value: 'export', enabled: true, child: Row(children: [
          Icon(Icons.table_chart_outlined, size: 16, color: kTextHint), SizedBox(width: 8),
          Text('Export (CSV/Excel)', style: TextStyle(color: kTextHint)),
        ])),
      ],
    );
  }
}

// ── Card View — one stacked card per row (mobile-first) ─────────────────────
class ReportCardList extends StatelessWidget {
  const ReportCardList({super.key, required this.dataSet});
  final ReportDataSet dataSet;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      ...dataSet.rows.asMap().entries.map((entry) {
        final row = entry.value;
        final titleText = row.isNotEmpty ? row.first : '';
        return Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: entry.key.isOdd ? kBgGrey.withValues(alpha: 0.5) : Colors.white,
            borderRadius: BorderRadius.circular(kRadiusInner),
            border: Border.all(color: kBorderLight),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titleText,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, color: kNavy)),
            const SizedBox(height: 6),
            Wrap(spacing: 16, runSpacing: 4, children: [
              for (var i = 1; i < row.length; i++)
                if (row[i].isNotEmpty)
                  RichText(
                    text: TextSpan(children: [
                      TextSpan(
                          text: '${dataSet.headers[i]}: ',
                          style: const TextStyle(fontSize: 11, color: kTextHint)),
                      TextSpan(
                          text: row[i],
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: dataSet.highlightColumns.contains(i)
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: dataSet.warnColumn == i &&
                                  (double.tryParse(row[i].replaceAll('%', '')) ?? 0) >=
                                      dataSet.warnThreshold
                                  ? Colors.red
                                  : (dataSet.highlightColumns.contains(i) ? kNavy : kTextMain))),
                    ]),
                  ),
            ]),
          ]),
        );
      }),
      if (dataSet.totals != null)
        Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: kNavy.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(kRadiusInner),
          ),
          child: Wrap(spacing: 16, runSpacing: 4, children: [
            for (var i = 0; i < dataSet.totals!.length; i++)
              if (dataSet.totals![i].isNotEmpty)
                Text('${dataSet.headers[i]}: ${dataSet.totals![i]}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: kNavy)),
          ]),
        ),
    ]);
  }
}

// ── Table View — professional business table ───────────────────────────────
// Sortable columns (tap header), sticky header (fixed row above a scrollable
// body, both synced to the same horizontal ScrollController), totals footer,
// ListView.builder body so large datasets don't build every row up front.
class ReportTable extends StatefulWidget {
  const ReportTable({
    super.key,
    required this.dataSet,
    this.sortColumn,
    this.sortAscending = true,
    this.onSort,
    this.rowHeight = 40,
    this.maxBodyHeight = 420,
  });

  final ReportDataSet dataSet;
  final int? sortColumn;
  final bool sortAscending;
  final void Function(int column, bool ascending)? onSort;
  final double rowHeight;
  final double maxBodyHeight;

  @override
  State<ReportTable> createState() => _ReportTableState();
}

class _ReportTableState extends State<ReportTable> {
  final _hCtrl = ScrollController();

  static const double _colWidth = 130;
  static const double _firstColWidth = 160;

  @override
  void dispose() {
    _hCtrl.dispose();
    super.dispose();
  }

  double _widthFor(int col) => col == 0 ? _firstColWidth : _colWidth;

  double get _tableWidth =>
      List.generate(widget.dataSet.headers.length, _widthFor).fold(0.0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    final ds = widget.dataSet;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: LayoutBuilder(builder: (ctx, constraints) {
        final tableWidth = _tableWidth < constraints.maxWidth ? constraints.maxWidth : _tableWidth;
        return SingleChildScrollView(
          controller: _hCtrl,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(children: [
              // ── Sticky header ──────────────────────────────────────────
              Container(
                decoration: const BoxDecoration(
                  color: kNavy,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
                ),
                child: Row(children: [
                  for (var c = 0; c < ds.headers.length; c++)
                    _headerCell(c, tableWidth, ds),
                ]),
              ),
              // ── Scrollable body — ListView.builder for large datasets ──
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: widget.maxBodyHeight),
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  itemCount: ds.rows.length,
                  itemBuilder: (ctx, i) => _dataRow(ds.rows[i], i, tableWidth, ds),
                ),
              ),
              // ── Totals / footer row ─────────────────────────────────────
              if (ds.totals != null) _footerRow(ds.totals!, tableWidth, ds),
            ]),
          ),
        );
      }),
    );
  }

  Widget _headerCell(int c, double tableWidth, ReportDataSet ds) {
    final isSorted = widget.sortColumn == c;
    final width = c == ds.headers.length - 1
        ? tableWidth - List.generate(c, _widthFor).fold(0.0, (a, b) => a + b)
        : _widthFor(c);
    return InkWell(
      onTap: widget.onSort == null
          ? null
          : () => widget.onSort!(c, isSorted ? !widget.sortAscending : true),
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(children: [
          Expanded(
            child: Text(ds.headers[c],
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: ds.highlightColumns.contains(c) ? kGoldLight : const Color(0xFFB4C6F4))),
          ),
          if (widget.onSort != null)
            Icon(
              isSorted
                  ? (widget.sortAscending ? Icons.arrow_upward : Icons.arrow_downward)
                  : Icons.unfold_more,
              size: 12,
              color: isSorted ? kGoldLight : const Color(0xFF6B7BA8),
            ),
        ]),
      ),
    );
  }

  Widget _dataRow(List<String> row, int index, double tableWidth, ReportDataSet ds) {
    return Container(
      height: widget.rowHeight,
      color: index.isOdd ? kBgGrey.withValues(alpha: 0.5) : Colors.white,
      child: Row(children: [
        for (var c = 0; c < row.length; c++) _dataCell(row[c], c, tableWidth, ds),
      ]),
    );
  }

  Widget _dataCell(String value, int c, double tableWidth, ReportDataSet ds) {
    final isHi = ds.highlightColumns.contains(c);
    final isWarn = ds.warnColumn != null &&
        c == ds.warnColumn &&
        (double.tryParse(value.replaceAll('%', '')) ?? 0) >= ds.warnThreshold;
    final width = c == ds.headers.length - 1
        ? tableWidth - List.generate(c, _widthFor).fold(0.0, (a, b) => a + b)
        : _widthFor(c);
    return Container(
      width: width,
      alignment: c == 0 ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Text(value,
          overflow: TextOverflow.ellipsis,
          textAlign: c == 0 ? TextAlign.left : TextAlign.right,
          style: TextStyle(
              fontSize: 12,
              fontWeight: isHi ? FontWeight.w800 : FontWeight.w500,
              color: isWarn ? Colors.red : (isHi ? kNavy : kTextMain))),
    );
  }

  Widget _footerRow(List<String> totals, double tableWidth, ReportDataSet ds) {
    return Container(
      decoration: BoxDecoration(
        color: kNavy.withValues(alpha: 0.07),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
        border: const Border(top: BorderSide(color: kBorderLight, width: 1.5)),
      ),
      child: Row(children: [
        for (var c = 0; c < totals.length; c++)
          Container(
            width: c == totals.length - 1
                ? tableWidth - List.generate(c, _widthFor).fold(0.0, (a, b) => a + b)
                : _widthFor(c),
            alignment: c == 0 ? Alignment.centerLeft : Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Text(totals[c],
                overflow: TextOverflow.ellipsis,
                textAlign: c == 0 ? TextAlign.left : TextAlign.right,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: ds.highlightColumns.contains(c) ? kNavy : kTextMain)),
          ),
      ]),
    );
  }
}