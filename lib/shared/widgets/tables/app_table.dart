import 'package:flutter/material.dart';
import 'package:rooster_trader/core/theme/app_theme.dart';
import 'package:rooster_trader/shared/layouts/responsive_layout.dart';

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
    final isMobile = w < kDesktopBreak;

    if (isMobile && mobileCardBuilder != null) {
      return _MobileList<T>(
        rows:         rows,
        cardBuilder:  mobileCardBuilder!,
        padding:      mobilePadding ?? const EdgeInsets.fromLTRB(16, 8, 16, 100),
        emptyWidget:  emptyWidget,
        footerWidget: footerWidget,
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
      // ── Navy header ──────────────────────────────────────────────────────
      Container(
        height:  headerHeight,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [kNavy, kNavyMid],
            begin:  Alignment.centerLeft,
            end:    Alignment.centerRight,
          ),
        ),
        padding: padding,
        child: Row(
          children: columns.map((col) => _headerCell(col)).toList(),
        ),
      ),

      // ── Rows ─────────────────────────────────────────────────────────────
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

// ── ListToolbar ────────────────────────────────────────────────────────────
// Consistent search + action bar across all list screens
class ListToolbar extends StatelessWidget {
  const ListToolbar({
    super.key,
    required this.searchController,
    required this.searchHint,
    required this.onSearch,
    this.onClearSearch,
    this.primaryLabel,
    this.primaryIcon,
    this.onPrimary,
    this.secondaryActions,
  });

  final TextEditingController  searchController;
  final String                 searchHint;
  final void Function(String)  onSearch;
  final VoidCallback?          onClearSearch;
  final String?                primaryLabel;
  final IconData?              primaryIcon;
  final VoidCallback?          onPrimary;
  final List<Widget>?          secondaryActions;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= kDesktopBreak;

    return Container(
      padding: EdgeInsets.fromLTRB(
          isDesktop ? 24 : 16,
          isDesktop ? 14 : 10,
          isDesktop ? 24 : 16,
          isDesktop ? 14 : 10),
      color: kSurface,
      child: Row(children: [
        // Search box
        Expanded(child: Container(
          height:     42,
          decoration: BoxDecoration(
            color:        kBgPage,
            borderRadius: BorderRadius.circular(kRadiusCard),
            border:       Border.all(color: kBorderLight),
          ),
          child: TextField(
            controller: searchController,
            onChanged:  onSearch,
            style: const TextStyle(fontSize: 14, color: kTextMain),
            decoration: InputDecoration(
              hintText:       searchHint,
              hintStyle:      const TextStyle(color: kTextHint, fontSize: 14),
              prefixIcon:     const Icon(Icons.search_rounded,
                  color: kTextHint, size: 18),
              suffixIcon: AnimatedBuilder(
                animation: searchController,
                builder: (_, __) => searchController.text.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.close_rounded,
                      size: 16, color: kTextHint),
                  onPressed: () {
                    searchController.clear();
                    onClearSearch?.call();
                  },
                  padding:       EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                )
                    : const SizedBox.shrink(),
              ),
              border:         InputBorder.none,
              enabledBorder:  InputBorder.none,
              focusedBorder:  InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        )),

        // Secondary actions
        if (secondaryActions != null) ...secondaryActions!,

        // Primary action — navy button, always visible on desktop
        if (onPrimary != null && primaryLabel != null) ...[
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onPrimary,
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color:        kNavy,
                borderRadius: BorderRadius.circular(kRadiusCard),
                boxShadow: [BoxShadow(
                    color:      kNavy.withValues(alpha: 0.3),
                    blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(primaryIcon ?? Icons.add_rounded,
                    color: kGoldLight, size: 18),
                const SizedBox(width: 8),
                Text(primaryLabel!,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}

// ── ListScreenScaffold ─────────────────────────────────────────────────────
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
    final isDesktop = MediaQuery.of(context).size.width >= kDesktopBreak;

    if (isDesktop) {
      return Scaffold(
        backgroundColor: kBgPage,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Toolbar area — white, border-bottom
            Container(
              decoration: const BoxDecoration(
                color:  kSurface,
                border: Border(bottom: BorderSide(color: kBorderLight)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                toolbar,
                if (summaryStrip != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                    child:   summaryStrip,
                  ),
                if (filterBar != null) filterBar!,
              ]),
            ),
            // Content — cream bg
            Expanded(child: content),
          ],
        ),
      );
    }

    // Mobile / Tablet
    return Scaffold(
      appBar:               appBar,
      floatingActionButton: fab,
      backgroundColor:      kBgPage,
      body: Column(children: [
        Container(
          decoration: const BoxDecoration(
            color:  kSurface,
            border: Border(bottom: BorderSide(color: kBorderLight)),
          ),
          child: Column(children: [
            toolbar,
            if (summaryStrip != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child:   summaryStrip,
              ),
            if (filterBar != null) filterBar!,
          ]),
        ),
        Expanded(child: content),
      ]),
    );
  }
}