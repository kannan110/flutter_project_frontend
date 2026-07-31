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
import 'customer_ledger_print_builder.dart';

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
      cardPrimaryColumns: widget.dataSet.cardPrimaryColumns,
      // BUG FIX: these two were previously dropped here, which meant the
      // Customer Ledger's compact identity block and branded-footer flag
      // never survived this rebuild — every Table PDF fell back to the
      // generic "DETAILS (n rows)" path regardless of what _tbl() set.
      customerIdentity: widget.dataSet.customerIdentity,
      useBrandedFooter: widget.dataSet.useBrandedFooter,
      customerLedgerData: widget.dataSet.customerLedgerData,
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
          SnackBar(
              content: Text(
                  'Export failed: ${e.toString().replaceAll("Exception:", "").trim()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Full Sheet / Half Sheet menu — shown only when ds.customerLedgerData is
  // set (currently: Customer Ledger only). Every other report's Print
  // button is untouched and keeps calling generateFromDataSetAndShow
  // directly, exactly as before.
  Future<void> _showPrintSheetMenu(BuildContext context, ReportDataSet ds) async {
    final data = ds.customerLedgerData!;
    final from = ds.fromDate ?? widget.fromDate ?? DateTime.now();
    final to = ds.toDate ?? widget.toDate ?? DateTime.now();

    Widget option(IconData icon, String label, String sub, PrintSheetSize size) => ListTile(
      leading: Icon(icon, color: kNavy),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(sub),
      onTap: () {
        Navigator.of(context, rootNavigator: true).pop();
        _run(() => CustomerLedgerPrintBuilder.printAndShow(
          context: context,
          data: data,
          companyName: widget.companyName,
          fromDate: from,
          toDate: to,
          size: size,
        ));
      },
    );

    await showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Print Customer Ledger', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ),
          ),
          option(Icons.description_outlined, 'Full Sheet Print', 'A4 — one full page per customer', PrintSheetSize.full),
          option(Icons.crop_7_5_outlined, 'Half Sheet Print', 'A5 — compact, saves paper for batch printing', PrintSheetSize.half),
          const SizedBox(height: 8),
        ]),
      ),
    );
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
              onDownload: () =>
                  _run(() => ReportPdfGenerator.generateFromDataSetAndShow(
                    context: context,
                    dataSet: ds,
                    companyName: widget.companyName,
                  )),
              onShare: () => _run(() => ReportPdfGenerator.shareFromDataSet(
                dataSet: ds,
                companyName: widget.companyName,
              )),
              onPrint: () => ds.customerLedgerData != null
                  ? _showPrintSheetMenu(context, ds)
                  : _run(() => ReportPdfGenerator.generateFromDataSetAndShow(
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
  const ReportViewToggle(
      {super.key, required this.mode, required this.onChanged});

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
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2)),
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
            Text(label,
                style: const TextStyle(
                    fontSize: 9,
                    color: kTextHint,
                    fontWeight: FontWeight.w600)),
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

// ── Card View — vertical "business summary" layout, nothing truncated ──────
// Second redesign pass: the previous version still squeezed a curated set
// of metrics into one row plus an overflow line, which is still
// compressing a table into a card. This version is genuinely vertical: a
// header line, the hero metric as its own prominent block, then EVERY
// remaining column in a wrapping grid where each cell gets the width its
// content actually needs. Nothing is capped to one line or given an
// ellipsis; items wrap to the next row instead of shrinking or hiding.
// Card height grows to fit the data on purpose, reversing the earlier
// "reduce height" direction because it is now in direct conflict with
// "never truncate."
class ReportCardList extends StatelessWidget {
  const ReportCardList({super.key, required this.dataSet});

  final ReportDataSet dataSet;

  // Matches the _fd() "d MMM" format (e.g. "10 Jul") used by every
  // date-titled report. Only reformats the title into a day/month block
  // when it actually looks like this -- ReportCardList is shared by
  // reports whose first column is a name (Agent, Retailer), not a date.
  static final _dateLikeRe = RegExp(r'^(\d{1,2})\s+([A-Za-z]{3,})$');

  @override
  Widget build(BuildContext context) {
    final heroCol = dataSet.highlightColumns.isNotEmpty
        ? dataSet.highlightColumns.first
        : (dataSet.headers.length > 1 ? 1 : null);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(children: [
        ...dataSet.rows.map((row) {
          final title = row.isNotEmpty ? row.first : '';
          final dateMatch = _dateLikeRe.firstMatch(title);

          final heroValue =
          heroCol != null && heroCol < row.length ? row[heroCol] : null;
          final heroNum = heroValue == null
              ? null
              : num.tryParse(heroValue.replaceAll(RegExp(r'[₹,%\s]'), ''));
          final isWarnHero = dataSet.warnColumn == heroCol &&
              heroValue != null &&
              (double.tryParse(heroValue.replaceAll('%', '')) ?? 0) >=
                  dataSet.warnThreshold;
          final noActivity = heroNum != null && heroNum == 0;

          // Every remaining column -- nothing curated out, nothing hidden.
          final gridItems = <MapEntry<String, String>>[];
          for (var i = 1; i < row.length; i++) {
            if (i == heroCol) continue;
            if (row[i].isEmpty) continue;
            gridItems.add(MapEntry(dataSet.headers[i], row[i]));
          }

          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: kSpMd),
            padding: const EdgeInsets.all(kSpLg),
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(kRadiusInner),
              border: Border.all(color: kBorderLight),
            ),
            child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // -- Header line: title/date + status badge --
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: dateMatch != null
                      ? Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(dateMatch.group(1)!,
                            style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: kNavy)),
                        const SizedBox(width: kSpXs),
                        Text(dateMatch.group(2)!,
                            style: kTypeBody.copyWith(
                                fontWeight: FontWeight.w700,
                                color: kTextSub)),
                      ])
                      : Text(title,
                      style: kTypeBody.copyWith(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                ),
                if (heroValue != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: kSpSm, vertical: 3),
                    decoration: BoxDecoration(
                      color: noActivity
                          ? kBgGrey
                          : const Color(0xFF1565C0).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(kRadiusChip),
                    ),
                    child: Text(noActivity ? 'No Activity' : 'Active',
                        style: kTypeCaption.copyWith(
                            fontWeight: FontWeight.w700,
                            color: noActivity
                                ? kTextHint
                                : const Color(0xFF1565C0))),
                  ),
              ]),

              // -- Hero metric: its own full-width block, never squeezed --
              if (heroValue != null) ...[
                const SizedBox(height: kSpMd),
                Text(dataSet.headers[heroCol!], style: kTypeKpiLabel),
                const SizedBox(height: 2),
                Text(heroValue,
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: isWarnHero ? Colors.red : kNavy)),
              ],

              // -- Everything else: a wrapping grid, full label + full
              //    value, every item, none of it capped to a single line
              //    or shortened with an ellipsis --
              if (gridItems.isNotEmpty) ...[
                const SizedBox(height: kSpMd),
                Container(height: 1, color: kBorderLight),
                const SizedBox(height: kSpMd),
                Wrap(
                  spacing: kSpXl,
                  runSpacing: kSpMd,
                  children: [
                    for (final item in gridItems)
                      ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 88),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.key, style: kTypeKpiLabel),
                              const SizedBox(height: 2),
                              Text(item.value, style: kTypeKpiSecondary),
                            ]),
                      ),
                  ],
                ),
              ],
            ]),
          );
        }),
        if (dataSet.totals != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: kSpMd),
            padding: const EdgeInsets.all(kSpLg),
            decoration: BoxDecoration(
              color: kNavy.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(kRadiusInner),
              border: Border.all(color: kNavy.withValues(alpha: 0.15)),
            ),
            child: Wrap(
              spacing: kSpXl,
              runSpacing: kSpMd,
              children: [
                for (var i = 0; i < dataSet.totals!.length; i++)
                  if (dataSet.totals![i].isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 88),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(dataSet.headers[i], style: kTypeKpiLabel),
                            const SizedBox(height: 2),
                            Text(dataSet.totals![i],
                                style: kTypeKpiSecondary.copyWith(
                                    fontWeight: FontWeight.w800, color: kNavy)),
                          ]),
                    ),
              ],
            ),
          ),
      ]),
    );
  }
}

// -- Table View -- professional business table, fully responsive --------
// Sortable columns (tap header), sticky header (fixed row above a
// scrollable body), sticky totals footer, ListView.builder body so large
// datasets do not build every row up front.
//
// Responsive strategy (three distinct modes, not one layout reused
// everywhere):
//   - Mobile (< 600 px): fixed, content-sized column widths inside a
//     horizontally-scrolling row. Horizontal scroll is expected here.
//   - Tablet (600-1023 px): same fixed-width scrolling approach, but with
//     roomier minimum column widths ("better spacing", not just mobile
//     stretched out).
//   - Desktop (>= 1024 px): if the table natural content width fits the
//     available space, columns render with Expanded/flex instead of fixed
//     pixel widths, so the grid fills exactly 100% of the available width
//     with no dead space and no horizontal scrollbar -- while still
//     respecting each column relative proportions (Date stays a fixed
//     narrow width always; Revenue/Collected/Pending-style highlighted
//     columns get a wider flex share). If there are enough columns that
//     the natural width would exceed the viewport even on desktop, it
//     falls back to the scrollable fixed-width mode rather than squeezing
//     everything illegibly thin.
class ReportTable extends StatefulWidget {
  const ReportTable({
    super.key,
    required this.dataSet,
    this.sortColumn,
    this.sortAscending = true,
    this.onSort,
    this.rowHeight = 52,
    this.headerHeight = 52,
    this.maxBodyHeight = 460,
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
  int? _hoveredRow;

  static const double _mobileBreakpoint = 600;
  static const double _desktopBreakpoint = 1024;

  static const double _minColWidthMobile = 92;
  static const double _minColWidthTablet = 116;
  static const double _maxColWidth = 170;
  static const double _firstColWidth = 110; // Date -- always fixed, never grows
  static const double _highlightMinWidth =
  130; // Revenue/Collected/Pending-style columns
  static const double _charWidth = 7.4;
  static const double _cellPadding = 14;

  @override
  void dispose() {
    _hCtrl.dispose();
    super.dispose();
  }

  // Per-column base (natural) width -- used directly on mobile/tablet, and
  // as the proportional basis for flex ratios on desktop fill mode.
  double _widthFor(
      int col, List<String> headers, ReportDataSet ds, double minColWidth) {
    if (col == 0) return _firstColWidth;
    final base = headers[col].length * _charWidth + (_cellPadding * 2) + 14;
    final floor =
    ds.highlightColumns.contains(col) ? _highlightMinWidth : minColWidth;
    return base.clamp(floor, _maxColWidth);
  }

  List<double> _colWidths(ReportDataSet ds, double minColWidth) =>
      List.generate(
          ds.headers.length, (c) => _widthFor(c, ds.headers, ds, minColWidth));

  double _tableWidthOf(List<double> widths) =>
      widths.fold(0.0, (a, b) => a + b);

  // Right-align a column when its values look numeric (after stripping
  // currency symbols, %, commas, units) -- detected from the data itself
  // rather than assumed from position, so a text column that is not first
  // (e.g. "Status", "Agent") still reads left-aligned.
  bool _isNumericColumn(int c, ReportDataSet ds) {
    if (c == 0) return false;
    if (ds.rows.isEmpty) return true;
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: LayoutBuilder(builder: (ctx, constraints) {
        final isMobile = constraints.maxWidth < _mobileBreakpoint;
        final isDesktop = constraints.maxWidth >= _desktopBreakpoint;
        final minColWidth = isMobile ? _minColWidthMobile : _minColWidthTablet;
        final widths = _colWidths(ds, minColWidth);
        final naturalWidth = _tableWidthOf(widths);

        // Desktop fill mode only when the content genuinely fits -- never
        // force-fit a wide table into a narrow desktop window.
        final useFillMode = isDesktop && naturalWidth <= constraints.maxWidth;

        if (useFillMode) {
          final flexWidths = List<double>.from(widths);
          return _buildGrid(ds, flexWidths,
              useFlex: true, totalWidth: constraints.maxWidth);
        }

        return SingleChildScrollView(
          controller: _hCtrl,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: naturalWidth,
            child: _buildGrid(ds, widths,
                useFlex: false, totalWidth: naturalWidth),
          ),
        );
      }),
    );
  }

  Widget _buildGrid(ReportDataSet ds, List<double> widths,
      {required bool useFlex, required double totalWidth}) {
    return Column(children: [
      // -- Sticky header --
      Container(
        height: widget.headerHeight,
        width: useFlex ? totalWidth : null,
        decoration: const BoxDecoration(
          color: kNavy,
          borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
        ),
        child: Row(children: [
          for (var c = 0; c < ds.headers.length; c++)
            _wrapCell(c, widths[c], useFlex, _headerCellContent(c, ds)),
        ]),
      ),
      // -- Scrollable body --
      ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxBodyHeight),
        child: ListView.builder(
          shrinkWrap: true,
          physics: const ClampingScrollPhysics(),
          itemCount: ds.rows.length,
          itemBuilder: (ctx, i) =>
              _dataRow(ds.rows[i], i, widths, ds, useFlex, totalWidth),
        ),
      ),
      // -- Sticky totals footer --
      if (ds.totals != null)
        _footerRow(ds.totals!, widths, ds, useFlex, totalWidth),
    ]);
  }

  // Wraps cell content in either a fixed SizedBox (mobile/tablet, scrolling
  // mode) or an Expanded/flex slot (desktop fill mode) -- same inner
  // content either way, only the outer sizing strategy differs.
  Widget _wrapCell(int c, double width, bool useFlex, Widget content) {
    if (useFlex) {
      return Expanded(flex: width.round(), child: content);
    }
    return SizedBox(width: width, child: content);
  }

  Widget _headerCellContent(int c, ReportDataSet ds) {
    final isSorted = widget.sortColumn == c;
    final rightAlign = _isNumericColumn(c, ds);
    return InkWell(
      onTap: widget.onSort == null
          ? null
          : () => widget.onSort!(c, isSorted ? !widget.sortAscending : true),
      child: Container(
        height: widget.headerHeight,
        padding: const EdgeInsets.symmetric(horizontal: _cellPadding),
        decoration: c < ds.headers.length - 1
            ? const BoxDecoration(
            border: Border(
                right: BorderSide(color: Color(0x22FFFFFF), width: 1)))
            : null,
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment:
          rightAlign ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (rightAlign && widget.onSort != null)
              Icon(
                  isSorted
                      ? (widget.sortAscending
                      ? Icons.arrow_upward
                      : Icons.arrow_downward)
                      : Icons.unfold_more,
                  size: 12,
                  color: isSorted ? kGoldLight : const Color(0xFF6B7BA8)),
            if (rightAlign && widget.onSort != null) const SizedBox(width: 4),
            Flexible(
              child: Text(ds.headers[c],
                  overflow: TextOverflow.ellipsis,
                  textAlign: rightAlign ? TextAlign.right : TextAlign.left,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: ds.highlightColumns.contains(c)
                          ? kGoldLight
                          : const Color(0xFFB4C6F4))),
            ),
            if (!rightAlign && widget.onSort != null) const SizedBox(width: 4),
            if (!rightAlign && widget.onSort != null)
              Icon(
                  isSorted
                      ? (widget.sortAscending
                      ? Icons.arrow_upward
                      : Icons.arrow_downward)
                      : Icons.unfold_more,
                  size: 12,
                  color: isSorted ? kGoldLight : const Color(0xFF6B7BA8)),
          ],
        ),
      ),
    );
  }

  Widget _dataRow(List<String> row, int index, List<double> widths,
      ReportDataSet ds, bool useFlex, double totalWidth) {
    final isHovered = _hoveredRow == index;
    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredRow = index),
      onExit: (_) => setState(() => _hoveredRow = null),
      child: Container(
        height: widget.rowHeight,
        width: useFlex ? totalWidth : null,
        color: isHovered
            ? const Color(0xFF1565C0).withValues(alpha: 0.06)
            : (index.isOdd ? kBgGrey.withValues(alpha: 0.4) : Colors.white),
        child: Row(children: [
          for (var c = 0; c < row.length; c++)
            _wrapCell(c, widths[c], useFlex,
                _dataCellContent(row[c], c, ds, isLast: c == row.length - 1)),
        ]),
      ),
    );
  }

  Widget _dataCellContent(String value, int c, ReportDataSet ds,
      {required bool isLast}) {
    final isHi = ds.highlightColumns.contains(c);
    final isWarn = ds.warnColumn != null &&
        c == ds.warnColumn &&
        (double.tryParse(value.replaceAll('%', '')) ?? 0) >= ds.warnThreshold;
    final rightAlign = _isNumericColumn(c, ds);
    return Container(
      alignment: rightAlign ? Alignment.centerRight : Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: _cellPadding),
      decoration: !isLast
          ? const BoxDecoration(
          border:
          Border(right: BorderSide(color: kBorderLight, width: 0.5)))
          : null,
      child: Text(value,
          overflow: TextOverflow.ellipsis,
          textAlign: rightAlign ? TextAlign.right : TextAlign.left,
          style: TextStyle(
              fontSize: 13,
              fontWeight: isHi ? FontWeight.w700 : FontWeight.w500,
              color: isWarn ? Colors.red : (isHi ? kNavy : kTextMain))),
    );
  }

  Widget _footerRow(List<String> totals, List<double> widths, ReportDataSet ds,
      bool useFlex, double totalWidth) {
    return Container(
      height: widget.rowHeight + 4,
      width: useFlex ? totalWidth : null,
      decoration: BoxDecoration(
        color: kBgGrey,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(6)),
        border: const Border(top: BorderSide(color: kNavy, width: 1.5)),
      ),
      child: Row(children: [
        for (var c = 0; c < totals.length; c++)
          _wrapCell(
              c,
              widths[c],
              useFlex,
              Container(
                alignment: (_isNumericColumn(c, ds) || c > 0)
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: _cellPadding),
                decoration: c < totals.length - 1
                    ? const BoxDecoration(
                    border: Border(
                        right: BorderSide(color: kBorderLight, width: 0.5)))
                    : null,
                child: Text(totals[c],
                    overflow: TextOverflow.ellipsis,
                    textAlign: (_isNumericColumn(c, ds) || c > 0)
                        ? TextAlign.right
                        : TextAlign.left,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: ds.highlightColumns.contains(c)
                            ? kNavy
                            : kTextMain)),
              )),
      ]),
    );
  }
}