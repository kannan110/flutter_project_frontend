import 'package:flutter/material.dart';
import 'package:rooster_trader/core/theme/app_theme.dart';

// ── AppTableColumn ─────────────────────────────────────────────────────────
class AppTableColumn<T> {
  const AppTableColumn({
    required this.label,
    required this.cellBuilder,
    this.width,
    this.flex        = 1,
    this.alignment   = Alignment.centerLeft,
    this.sortKey,
  });
  final String                  label;
  final Widget Function(T item) cellBuilder;
  final double?                 width;
  final int                     flex;
  final Alignment               alignment;
  final String?                 sortKey;
}

// ── AppTable ───────────────────────────────────────────────────────────────
// Enterprise data table: Navy header, white rows, kBorderLight dividers
// 15-16px font throughout, 52px row height for readability
class AppTable<T> extends StatelessWidget {
  const AppTable({
    super.key,
    required this.columns,
    required this.rows,
    this.onRowTap,
    this.mobileCardBuilder,
    this.rowHeight        = 56.0,
    this.headerHeight     = 44.0,
    this.mobilePadding,
    this.desktopPadding,
    this.emptyWidget,
    this.footerWidget,
    this.sortColumn,
    this.sortAscending    = true,
    this.onSort,
    this.rowDecoration,
  });

  final List<AppTableColumn<T>> columns;
  final List<T>                 rows;
  final void Function(T)?       onRowTap;
  final Widget Function(T)?     mobileCardBuilder;
  final double                  rowHeight;
  final double                  headerHeight;
  final EdgeInsets?              mobilePadding;
  final EdgeInsets?              desktopPadding;
  final Widget?                 emptyWidget;
  final Widget?                 footerWidget;
  final String?                 sortColumn;
  final bool                    sortAscending;
  final void Function(String)?  onSort;
  final BoxDecoration Function(T)? rowDecoration;

  @override
  Widget build(BuildContext context) {
    final w        = MediaQuery.of(context).size.width;
    final isMobile = w < 768;

    if (isMobile && mobileCardBuilder != null) {
      return _MobileList<T>(
        rows:        rows,
        cardBuilder: mobileCardBuilder!,
        padding:     mobilePadding ?? const EdgeInsets.fromLTRB(16, 8, 16, 100),
        emptyWidget: emptyWidget,
        footerWidget:footerWidget,
      );
    }

    return _DesktopTable<T>(
      columns:       columns,
      rows:          rows,
      onRowTap:      onRowTap,
      rowHeight:     rowHeight,
      headerHeight:  headerHeight,
      padding:       desktopPadding ?? EdgeInsets.zero,
      emptyWidget:   emptyWidget,
      footerWidget:  footerWidget,
      sortColumn:    sortColumn,
      sortAscending: sortAscending,
      onSort:        onSort,
      rowDecoration: rowDecoration,
    );
  }
}

// ── Desktop table ──────────────────────────────────────────────────────────
class _DesktopTable<T> extends StatelessWidget {
  const _DesktopTable({
    required this.columns,
    required this.rows,
    required this.rowHeight,
    required this.headerHeight,
    required this.padding,
    this.onRowTap,
    this.emptyWidget,
    this.footerWidget,
    this.sortColumn,
    this.sortAscending = true,
    this.onSort,
    this.rowDecoration,
  });

  final List<AppTableColumn<T>> columns;
  final List<T>                 rows;
  final void Function(T)?       onRowTap;
  final double                  rowHeight;
  final double                  headerHeight;
  final EdgeInsets              padding;
  final Widget?                 emptyWidget;
  final Widget?                 footerWidget;
  final String?                 sortColumn;
  final bool                    sortAscending;
  final void Function(String)?  onSort;
  final BoxDecoration Function(T)? rowDecoration;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // ── Navy header ────────────────────────────────────────────────────
      Container(
        height:  headerHeight,
        color:   kNavy,
        padding: padding,
        child: Row(
          children: columns.map((col) => _headerCell(col)).toList(),
        ),
      ),

      // ── Rows ────────────────────────────────────────────────────────────
      if (rows.isEmpty && emptyWidget != null)
        Expanded(child: emptyWidget!)
      else
        Expanded(
          child: ListView.builder(
            padding:     EdgeInsets.zero,
            itemCount:   rows.length + (footerWidget != null ? 1 : 0),
            itemBuilder: (_, i) {
              if (footerWidget != null && i == rows.length) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child:   footerWidget,
                );
              }
              return _TableRow<T>(
                item:       rows[i],
                columns:    columns,
                height:     rowHeight,
                padding:    padding,
                onTap:      onRowTap != null ? () => onRowTap!(rows[i]) : null,
                isEven:     i.isEven,
                decoration: rowDecoration?.call(rows[i]),
              );
            },
          ),
        ),
    ]);
  }

  Widget _headerCell(AppTableColumn<T> col) {
    final canSort  = col.sortKey != null && onSort != null;
    final isActive = sortColumn == col.sortKey;

    Widget label = Text(
      col.label.toUpperCase(),
      style: TextStyle(
        fontSize:      11,
        fontWeight:    FontWeight.w800,
        color:         isActive ? kGoldLight : kSidebarText,
        letterSpacing: 0.8,
      ),
    );

    if (canSort) {
      label = InkWell(
        onTap:        () => onSort!(col.sortKey!),
        borderRadius: BorderRadius.circular(2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          label,
          const SizedBox(width: 4),
          Icon(
            isActive
                ? (sortAscending
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded)
                : Icons.unfold_more_rounded,
            size:  11,
            color: isActive ? kGoldLight : kNavyLight,
          ),
        ]),
      );
    }

    if (col.width != null) {
      return SizedBox(
        width: col.width,
        child: Align(alignment: col.alignment, child: label),
      );
    }
    return Expanded(
      flex:  col.flex,
      child: Align(alignment: col.alignment, child: label),
    );
  }
}

// ── Table row ──────────────────────────────────────────────────────────────
class _TableRow<T> extends StatefulWidget {
  const _TableRow({
    required this.item,
    required this.columns,
    required this.height,
    required this.padding,
    required this.isEven,
    this.onTap,
    this.decoration,
  });

  final T                       item;
  final List<AppTableColumn<T>> columns;
  final double                  height;
  final EdgeInsets              padding;
  final bool                    isEven;
  final VoidCallback?           onTap;
  final BoxDecoration?          decoration;

  @override
  State<_TableRow<T>> createState() => _TableRowState<T>();
}

class _TableRowState<T> extends State<_TableRow<T>> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final defaultDeco = BoxDecoration(
      color: _hovered
          ? kNavy.withValues(alpha: 0.04)
          : widget.isEven
          ? kSurface
          : kBgPage,
      border: const Border(
          bottom: BorderSide(color: kBorderLight, width: 1)),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor:  widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height:     widget.height,
          padding:    widget.padding,
          decoration: widget.decoration ?? defaultDeco,
          child: Row(
            children: widget.columns.map((col) {
              final cell = col.cellBuilder(widget.item);
              if (col.width != null) {
                return SizedBox(
                  width: col.width,
                  child: Align(alignment: col.alignment, child: cell),
                );
              }
              return Expanded(
                flex:  col.flex,
                child: Align(alignment: col.alignment, child: cell),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

// ── Mobile list ────────────────────────────────────────────────────────────
class _MobileList<T> extends StatelessWidget {
  const _MobileList({
    required this.rows,
    required this.cardBuilder,
    required this.padding,
    this.emptyWidget,
    this.footerWidget,
  });

  final List<T>          rows;
  final Widget Function(T) cardBuilder;
  final EdgeInsets       padding;
  final Widget?          emptyWidget;
  final Widget?          footerWidget;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty && emptyWidget != null) return emptyWidget!;
    return ListView.separated(
      padding:          padding,
      itemCount:        rows.length + (footerWidget != null ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        if (footerWidget != null && i == rows.length) return footerWidget!;
        return cardBuilder(rows[i]);
      },
    );
  }
}

// ── ListScreenScaffold ─────────────────────────────────────────────────────
// Enterprise scaffold: white content area, navy table header
class ListScreenScaffold extends StatelessWidget {
  const ListScreenScaffold({
    super.key,
    this.appBar,
    required this.toolbar,
    required this.content,
    this.filterBar,
    this.summaryStrip,
    this.fab,
  });

  final PreferredSizeWidget? appBar;
  final Widget               toolbar;
  final Widget               content;
  final Widget?              filterBar;
  final Widget?              summaryStrip;
  final Widget?              fab;

  @override
  Widget build(BuildContext context) {
    final w         = MediaQuery.of(context).size.width;
    final isDesktop = w >= 1200;

    if (isDesktop) {
      return Scaffold(
        backgroundColor: kBgPage,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // White toolbar area
            Container(
              color: kSurface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  toolbar,
                  if (summaryStrip != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: summaryStrip,
                    ),
                  if (filterBar != null) filterBar!,
                  const Divider(height: 1, color: kBorderLight),
                ],
              ),
            ),
            // Content area (table fills remaining)
            Expanded(child: content),
          ],
        ),
      );
    }

    // Mobile / Tablet
    return Scaffold(
      appBar:              appBar,
      floatingActionButton: fab,
      backgroundColor:     kBgPage,
      body: Column(children: [
        Container(
          color: kSurface,
          child: Column(children: [
            toolbar,
            if (summaryStrip != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child:   summaryStrip,
              ),
            if (filterBar != null) filterBar!,
            const Divider(height: 1, color: kBorderLight),
          ]),
        ),
        Expanded(child: content),
      ]),
    );
  }
}