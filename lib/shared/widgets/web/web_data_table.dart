import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/web_tokens.dart';
import 'web_card.dart';

// ═══════════════════════════════════════════════════════════════════════════
// WebDataTable — the one table used on every web list screen.
//  • Fixed header (when `height` is given the rows scroll under it)
//  • Sortable columns (⇅ idle, ↑/↓ active in navy)
//  • Drag a header edge to resize, double-click the edge to auto-fit like Excel
//  • Excel-style dedicated bottom left-to-right scroll bar with step buttons
//  • Never squashed below minimum content widths — scrolls sideways smoothly
//  • Safe cell clipping so badges and text never trigger overflow stripes
//  • Hover rows, whole-row tap, dense mode
//  • Dashed loading / empty states
// ═══════════════════════════════════════════════════════════════════════════

class WebColumn {
  const WebColumn(this.label, {
    this.width,
    this.minWidth,
    this.maxWidth,
    this.flex = 1,
    this.sortKey,
    this.align = TextAlign.left,
  });

  final String    label;
  /// Fixed or preferred width. When null the column takes `flex` share of free space.
  final double?   width;
  /// Minimum width below which column will never shrink.
  final double?   minWidth;
  /// Maximum width above which column will not expand.
  final double?   maxWidth;
  final int       flex;
  /// Non-null = sortable.
  final String?   sortKey;
  final TextAlign align;
}

class WebDataTable<T> extends StatefulWidget {
  const WebDataTable({
    super.key,
    required this.columns,
    required this.rows,
    required this.cellBuilder,
    this.onRowTap,
    this.sortKey,
    this.sortAscending = true,
    this.onSort,
    this.dense = false,
    this.loading = false,
    this.emptyText = 'No Data',
    this.emptyAction,
    this.minWidth = WebSize.tableMinWidth,
    this.height,
    this.maxHeight = 560.0,
    this.showScrollbars = true,
    this.paginate = false,
    this.rowsPerPage = 25,
    this.rowsPerPageOptions = const [25, 50, 75, 100, 150, 200],
    this.onPageChanged,
    this.onRowsPerPageChanged,
  });

  final List<WebColumn> columns;
  final List<T>         rows;
  final Widget Function(T row, int column) cellBuilder;
  final ValueChanged<T>? onRowTap;
  final String?         sortKey;
  final bool            sortAscending;
  final ValueChanged<String>? onSort;
  final bool            dense;
  final bool            loading;
  final String          emptyText;
  /// Optional button shown under the empty message.
  final Widget?         emptyAction;
  final double          minWidth;
  /// When set, the table has this exact height and rows scroll under the header.
  final double?         height;
  /// Maximum height for table before rows scroll vertically under the sticky header.
  final double?         maxHeight;
  /// Whether to show interactive scrollbars for both axes.
  final bool            showScrollbars;
  /// When true, the table automatically paginates [rows] internally and renders
  /// [WebTablePagination] at the bottom.
  final bool            paginate;
  final int             rowsPerPage;
  final List<int>       rowsPerPageOptions;
  final ValueChanged<int>? onPageChanged;
  final ValueChanged<int>? onRowsPerPageChanged;

  @override
  State<WebDataTable<T>> createState() => _WebDataTableState<T>();
}

class _WebDataTableState<T> extends State<WebDataTable<T>> {
  // Session-only column widths set by dragging, keyed by column labels.
  static final Map<String, Map<int, double>> _memory = {};
  late final String _memKey = widget.columns.map((c) => c.label).join('|');
  Map<int, double> get _resized => _memory.putIfAbsent(_memKey, () => {});
  final _hScroll = ScrollController();
  final _vScroll = ScrollController();

  int? _hoveredResizeCol;
  int? _isDraggingCol;

  late int _page = 0;
  late int _rowsPerPage = widget.rowsPerPage;
  late bool _dense = widget.dense;

  @override
  void initState() {
    super.initState();
    _rowsPerPage = widget.rowsPerPage;
    _dense = widget.dense;
  }

  @override
  void didUpdateWidget(covariant WebDataTable<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.dense != oldWidget.dense) {
      _dense = widget.dense;
    }
    if (widget.rowsPerPage != oldWidget.rowsPerPage) {
      _rowsPerPage = widget.rowsPerPage;
    }
    final lastPage = widget.rows.isEmpty ? 0 : (widget.rows.length - 1) ~/ _rowsPerPage;
    if (_page > lastPage) {
      _page = lastPage;
    }
  }

  @override
  void dispose() {
    _hScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  double _minHeaderWidth(WebColumn col) {
    double w = col.label.length * 8.5 + 32.0; // 16px horizontal padding
    if (col.sortKey != null && widget.onSort != null) {
      w += 22.0; // Sort icon
    }
    return math.max(65.0, w);
  }

  List<double> _widths(double availableWidth) {
    final cols = widget.columns;
    if (cols.isEmpty) return [];

    final baseWidths = <double>[];
    final isFlexible = <bool>[];
    double totalBaseWidth = 0.0;
    int flexSum = 0;

    for (var i = 0; i < cols.length; i++) {
      final col = cols[i];
      final minW = col.minWidth ?? _minHeaderWidth(col);
      final maxW = col.maxWidth ?? double.infinity;

      if (_resized.containsKey(i)) {
        final w = _resized[i]!.clamp(minW, maxW);
        baseWidths.add(w);
        isFlexible.add(false);
        totalBaseWidth += w;
      } else if (col.width != null) {
        final w = math.max(minW, col.width!).clamp(minW, maxW);
        baseWidths.add(w);
        isFlexible.add(false);
        totalBaseWidth += w;
      } else {
        final base = math.max(minW, (110.0 * col.flex).clamp(90.0, 320.0)).clamp(minW, maxW);
        baseWidths.add(base);
        isFlexible.add(true);
        totalBaseWidth += base;
        flexSum += col.flex;
      }
    }

    final targetTotal = math.max(widget.minWidth, availableWidth);
    final freeSpace = targetTotal - totalBaseWidth;

    if (freeSpace > 0.5) {
      final result = List<double>.from(baseWidths);
      if (flexSum > 0) {
        for (var i = 0; i < cols.length; i++) {
          if (isFlexible[i]) {
            final share = freeSpace * (cols[i].flex / flexSum);
            final maxW = cols[i].maxWidth ?? double.infinity;
            result[i] = (result[i] + share).clamp(result[i], maxW);
          }
        }
      } else {
        final scale = targetTotal / totalBaseWidth;
        for (var i = 0; i < cols.length; i++) {
          final maxW = cols[i].maxWidth ?? double.infinity;
          result[i] = (result[i] * scale).clamp(result[i], maxW);
        }
      }
      return result;
    } else {
      return baseWidths;
    }
  }

  double _extractWidgetWidth(Widget w) {
    if (w is Text) {
      final text = w.data ?? w.textSpan?.toPlainText() ?? '';
      final fontSize = w.style?.fontSize ?? 13.5;
      return text.length * (fontSize * 0.6) + 32.0;
    }
    if (w is WebLabel) {
      return w.text.length * 7.5 + (w.dot ? 24.0 : 0.0) + (w.icon != null ? 24.0 : 0.0) + 36.0;
    }
    if (w is WebTwoLineCell) {
      final pLen = w.primary.length;
      final sLen = w.secondary?.length ?? 0;
      return (pLen + sLen) * 7.5 + 32.0;
    }
    if (w is Row) {
      double rowW = 0;
      for (final child in w.children) {
        if (child is SizedBox) {
          rowW += child.width ?? 0;
        } else if (child is Flexible) {
          rowW += _extractWidgetWidth(child.child);
        } else if (child is Expanded) {
          rowW += _extractWidgetWidth(child.child);
        } else {
          rowW += _extractWidgetWidth(child);
        }
      }
      return rowW + 32.0;
    }
    if (w is MouseRegion && w.child != null) return _extractWidgetWidth(w.child!);
    if (w is GestureDetector && w.child != null) return _extractWidgetWidth(w.child!);
    if (w is Padding) {
      return (w.child != null ? _extractWidgetWidth(w.child!) : 80.0) + w.padding.horizontal;
    }
    return 100.0;
  }

  void _autoFitColumn(int colIndex) {
    final col = widget.columns[colIndex];
    double maxW = _minHeaderWidth(col) + 20.0;

    for (final r in widget.rows.take(50)) {
      try {
        final cellWidget = widget.cellBuilder(r, colIndex);
        final w = _extractWidgetWidth(cellWidget);
        if (w > maxW) maxW = w;
      } catch (_) {}
    }

    final minW = col.minWidth ?? 70.0;
    final maxWLimit = col.maxWidth ?? 500.0;
    final optimal = (maxW + 20.0).clamp(minW, maxWLimit);

    setState(() {
      _resized[colIndex] = optimal;
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, c) {
    final widths = _widths(c.maxWidth);
    final tableW = math.max(c.maxWidth, widths.fold<double>(0, (s, w) => s + w));
    final headerH = _dense ? 42.0 : 52.0;
    final bottomBarH = widget.showScrollbars ? 14.0 : 0.0;
    final paginationH = widget.paginate ? 52.0 : 0.0;

    final total = widget.rows.length;
    final lastPage = total == 0 ? 0 : (total - 1) ~/ _rowsPerPage;
    final page = _page.clamp(0, lastPage);
    final displayedRows = widget.paginate
        ? widget.rows.skip(page * _rowsPerPage).take(_rowsPerPage).toList()
        : widget.rows;

    Widget body;
    if (widget.loading) {
      body = const WebTableState.loading();
    } else if (widget.rows.isEmpty) {
      body = WebTableState.empty(
          text: widget.emptyText, action: widget.emptyAction);
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in displayedRows) _row(r, widths),
        ],
      );
    }

    final double? effectiveHeight = widget.height;
    final double? effectiveMaxHeight = widget.height != null
        ? null
        : (widget.maxHeight != null && widget.maxHeight!.isFinite ? widget.maxHeight : null);

    Widget scrollableBody;
    if (effectiveHeight != null) {
      Widget vView = SingleChildScrollView(
        controller: _vScroll,
        scrollDirection: Axis.vertical,
        child: body,
      );
      if (widget.showScrollbars) {
        vView = Scrollbar(
          controller: _vScroll,
          thumbVisibility: true,
          child: vView,
        );
      }
      scrollableBody = SizedBox(
        height: math.max(60.0, effectiveHeight - headerH - bottomBarH - paginationH),
        child: vView,
      );
    } else if (effectiveMaxHeight != null && effectiveMaxHeight.isFinite) {
      Widget vView = SingleChildScrollView(
        controller: _vScroll,
        scrollDirection: Axis.vertical,
        child: body,
      );
      if (widget.showScrollbars) {
        vView = Scrollbar(
          controller: _vScroll,
          thumbVisibility: true,
          child: vView,
        );
      }
      scrollableBody = ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: math.max(60.0, effectiveMaxHeight - headerH - bottomBarH - paginationH),
        ),
        child: vView,
      );
    } else {
      scrollableBody = body;
    }

    final table = SizedBox(
      width: tableW,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_header(widths), scrollableBody],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          controller: _hScroll,
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: table,
        ),
        if (widget.showScrollbars)
          _buildBottomScrollBar(tableW, c.maxWidth),
        if (widget.paginate)
          WebTablePagination(
            page: page,
            rowsPerPage: _rowsPerPage,
            total: total,
            rowsPerPageOptions: widget.rowsPerPageOptions,
            onPage: (p) {
              setState(() => _page = p);
              widget.onPageChanged?.call(p);
            },
            onRowsPerPage: (n) {
              setState(() {
                _rowsPerPage = n;
                _page = 0;
              });
              widget.onRowsPerPageChanged?.call(n);
            },
            dense: _dense,
            onDense: (v) => setState(() => _dense = v),
          ),
      ],
    );
  });

  Widget _buildBottomScrollBar(double tableW, double viewportW) {
    final maxScroll = math.max(0.0, tableW - viewportW);
    final canScroll = maxScroll > 0.5;

    return AnimatedBuilder(
      animation: _hScroll,
      builder: (context, _) {
        final currentOffset = _hScroll.hasClients ? _hScroll.offset : 0.0;
        final canScrollLeft = canScroll && currentOffset > 1.0;
        final canScrollRight = canScroll && currentOffset < maxScroll - 1.0;

        return Container(
          height: 14,
          decoration: const BoxDecoration(
            color: WebColors.surfaceAlt,
            border: Border(
              top: BorderSide(color: WebColors.border, width: 1.0),
            ),
          ),
          child: Row(
            children: [
              // Left scroll step button ◀
              Tooltip(
                message: 'Scroll left',
                waitDuration: const Duration(milliseconds: 500),
                child: InkWell(
                  onTap: canScrollLeft
                      ? () {
                          final target = math.max(0.0, currentOffset - 180.0);
                          _hScroll.animateTo(
                            target,
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                          );
                        }
                      : null,
                  child: SizedBox(
                    width: 22,
                    height: 14,
                    child: Icon(
                      Icons.chevron_left_rounded,
                      size: 13,
                      color: canScrollLeft ? WebColors.navy : WebColors.text3.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              ),
              const VerticalDivider(width: 1, thickness: 1, color: WebColors.border),

              // Interactive Track & Thumb
              Expanded(
                child: LayoutBuilder(
                  builder: (context, trackC) {
                    final tWidth = trackC.maxWidth;
                    final thumbW = canScroll
                        ? math.max(40.0, (viewportW / tableW) * tWidth)
                        : tWidth;
                    final scrollableTrack = tWidth - thumbW;
                    final thumbLeft = canScroll && maxScroll > 0
                        ? (currentOffset / maxScroll).clamp(0.0, 1.0) * scrollableTrack
                        : 0.0;

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) {
                        if (!canScroll || scrollableTrack <= 0) return;
                        final localX = details.localPosition.dx;
                        final fraction = ((localX - thumbW / 2) / scrollableTrack).clamp(0.0, 1.0);
                        _hScroll.jumpTo(fraction * maxScroll);
                      },
                      onHorizontalDragUpdate: (details) {
                        if (!canScroll || scrollableTrack <= 0) return;
                        final deltaFraction = details.delta.dx / scrollableTrack;
                        final newOffset = (currentOffset + deltaFraction * maxScroll).clamp(0.0, maxScroll);
                        _hScroll.jumpTo(newOffset);
                      },
                      child: Container(
                        height: 14,
                        color: const Color(0xFFF1F5F9), // Slate-100 subtle track
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            if (canScroll)
                              Positioned(
                                left: thumbLeft,
                                width: thumbW,
                                top: 2,
                                bottom: 2,
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.grab,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF94A3B8), // Slate-400 thumb
                                      borderRadius: BorderRadius.circular(6),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x1F0F172A),
                                          blurRadius: 1,
                                          offset: Offset(0, 0.5),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Container(
                                        width: 12,
                                        height: 2,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.65),
                                          borderRadius: BorderRadius.circular(1),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            else
                              Center(
                                child: Text(
                                  'All columns visible',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    color: WebColors.text3.withValues(alpha: 0.7),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const VerticalDivider(width: 1, thickness: 1, color: WebColors.border),
              // Right scroll step button ▶
              Tooltip(
                message: 'Scroll right',
                waitDuration: const Duration(milliseconds: 500),
                child: InkWell(
                  onTap: canScrollRight
                      ? () {
                          final target = math.min(maxScroll, currentOffset + 180.0);
                          _hScroll.animateTo(
                            target,
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                          );
                        }
                      : null,
                  child: SizedBox(
                    width: 22,
                    height: 14,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 13,
                      color: canScrollRight ? WebColors.navy : WebColors.text3.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────
  Widget _header(List<double> widths) => Container(
    height: _dense ? 42 : 52,
    decoration: const BoxDecoration(
      color: WebColors.surfaceAlt,
      border: Border(bottom: BorderSide(color: WebColors.border, width: 1.2)),
    ),
    child: Row(children: [
      for (var i = 0; i < widget.columns.length; i++)
        SizedBox(
          width: widths[i],
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: _headCell(widget.columns[i])),
              // Excel-style interactive resize handle
              Positioned(
                right: -6,
                top: 0,
                bottom: 0,
                width: 14,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  onEnter: (_) => setState(() => _hoveredResizeCol = i),
                  onExit:  (_) => setState(() => _hoveredResizeCol = null),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (_) => setState(() => _isDraggingCol = i),
                    onHorizontalDragUpdate: (d) {
                      setState(() {
                        final cur = _resized[i] ?? widths[i];
                        final minW = widget.columns[i].minWidth ?? 60.0;
                        final maxW = widget.columns[i].maxWidth ?? 800.0;
                        _resized[i] = (cur + d.delta.dx).clamp(minW, maxW);
                      });
                    },
                    onHorizontalDragEnd: (_) => setState(() => _isDraggingCol = null),
                    onDoubleTap: () => _autoFitColumn(i),
                    child: Tooltip(
                      message: 'Drag to resize · Double-click to auto-fit',
                      waitDuration: const Duration(milliseconds: 600),
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: (_hoveredResizeCol == i || _isDraggingCol == i) ? 2.5 : 1.0,
                          height: double.infinity,
                          color: (_hoveredResizeCol == i || _isDraggingCol == i)
                              ? WebColors.navy
                              : WebColors.border,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
    ]),
  );

  Widget _headCell(WebColumn col) {
    final sortable = col.sortKey != null && widget.onSort != null;
    final active   = sortable && col.sortKey == widget.sortKey;
    final align = switch (col.align) {
      TextAlign.right  => MainAxisAlignment.end,
      TextAlign.center => MainAxisAlignment.center,
      _                => MainAxisAlignment.start,
    };
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(mainAxisAlignment: align, children: [
        Flexible(child: Text(col.label,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: WebText.tableHead.copyWith(
              color: active ? WebColors.navy : WebColors.text2,
              fontWeight: active ? FontWeight.w800 : FontWeight.w700,
            ))),
        if (sortable) ...[
          const SizedBox(width: 4),
          Icon(
            !active ? Icons.unfold_more_rounded
                : widget.sortAscending ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
            size: 15,
            color: active ? WebColors.navy : WebColors.text3.withValues(alpha: 0.7),
          ),
        ],
      ]),
    );
    if (!sortable) return content;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onSort!(col.sortKey!),
        child: content,
      ),
    );
  }

  // ── Row ─────────────────────────────────────────────────────────────────
  Widget _row(T row, List<double> widths) => _HoverRow(
    onTap: widget.onRowTap == null ? null : () => widget.onRowTap!(row),
    child: Padding(
      padding: EdgeInsets.symmetric(vertical: _dense ? 8 : 14),
      child: Row(children: [
        for (var i = 0; i < widget.columns.length; i++)
          SizedBox(
            width: widths[i],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: ClipRect(
                child: Align(
                  alignment: switch (widget.columns[i].align) {
                    TextAlign.right  => Alignment.centerRight,
                    TextAlign.center => Alignment.center,
                    _                => Alignment.centerLeft,
                  },
                  child: DefaultTextStyle.merge(
                    style: WebText.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: widget.cellBuilder(row, i),
                  ),
                ),
              ),
            ),
          ),
      ]),
    ),
  );
}

class _HoverRow extends StatefulWidget {
  const _HoverRow({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;
  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hov = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.onTap != null
        ? SystemMouseCursors.click : SystemMouseCursors.basic,
    onEnter: (_) => setState(() => _hov = true),
    onExit:  (_) => setState(() => _hov = false),
    child: GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: _hov ? WebColors.hover : Colors.transparent,
          border: const Border(
              bottom: BorderSide(color: WebColors.divider)),
        ),
        child: widget.child,
      ),
    ),
  );
}

// ── Loading / empty states (dashed box) ───────────────────────────────────
class WebTableState extends StatelessWidget {
  const WebTableState.loading({super.key})
      : loading = true, text = '', action = null;
  const WebTableState.empty({super.key, this.text = 'No Data', this.action})
      : loading = false;

  final bool    loading;
  final String  text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(WebSpace.lg),
    child: CustomPaint(
      painter: _DashedRRect(),
      child: SizedBox(
        height: 240,
        width: double.infinity,
        child: Center(child: loading
            ? const SizedBox(width: 40, height: 40,
                child: CircularProgressIndicator(
                    strokeWidth: 3, color: WebColors.navy))
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.inbox_outlined, size: 72,
                    color: WebColors.text3.withValues(alpha: 0.6)),
                const SizedBox(height: WebSpace.sm),
                Text(text, style: const TextStyle(fontSize: 15,
                    fontWeight: FontWeight.w700, color: WebColors.text3)),
                if (action != null) ...[
                  const SizedBox(height: WebSpace.md),
                  action!,
                ],
              ])),
      ),
    ),
  );
}

class _DashedRRect extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = WebColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()..addRRect(RRect.fromRectAndRadius(
        Offset.zero & size, const Radius.circular(WebRadius.sm)));
    for (final m in path.computeMetrics()) {
      for (double d = 0; d < m.length; d += 9) {
        canvas.drawPath(m.extractPath(d, math.min(d + 5, m.length)), p);
      }
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ── Cell helpers ──────────────────────────────────────────────────────────
class WebLetterAvatar extends StatelessWidget {
  const WebLetterAvatar(this.name, {super.key, this.dense = false});
  final String name;
  final bool dense;

  static const _palette = [
    Color(0xFF0A1F44), Color(0xFFC5A059), Color(0xFF059669),
    Color(0xFF2563EB), Color(0xFF7C3AED), Color(0xFFD97706),
    Color(0xFF0D9488), Color(0xFFDC2626),
  ];

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final color  = _palette[letter.codeUnitAt(0) % _palette.length];
    final s = dense ? 32.0 : 40.0;
    return Container(
      width: s, height: s,
      decoration: BoxDecoration(
          shape: BoxShape.circle, color: color.withValues(alpha: 0.14)),
      alignment: Alignment.center,
      child: Text(letter, style: TextStyle(fontSize: s * 0.4,
          fontWeight: FontWeight.w800, color: color)),
    );
  }
}

class WebTwoLineCell extends StatelessWidget {
  const WebTwoLineCell(this.primary, this.secondary, {super.key});
  final String primary;
  final String? secondary;
  @override
  Widget build(BuildContext context) {
    if (secondary == null || secondary!.trim().isEmpty) {
      return Text(
        primary,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            fontSize: 13.5, fontWeight: FontWeight.w600, color: WebColors.text1),
      );
    }
    return Text.rich(
      TextSpan(
        text: primary,
        style: const TextStyle(
            fontSize: 13.5, fontWeight: FontWeight.w600, color: WebColors.text1),
        children: [
          TextSpan(
            text: ' · $secondary',
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w400,
                color: WebColors.text3),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// WebTablePagination — Dense switch · Rows per page · 1–25 of 340 · ‹ ›
// ═══════════════════════════════════════════════════════════════════════════
class WebTablePagination extends StatelessWidget {
  const WebTablePagination({
    super.key,
    required this.page,
    required this.rowsPerPage,
    required this.total,
    required this.onPage,
    required this.onRowsPerPage,
    this.dense,
    this.onDense,
    this.rowsPerPageOptions = const [25, 50, 75, 100, 150, 200],
  });

  /// Zero-based page index.
  final int  page;
  final int  rowsPerPage;
  final int  total;
  final ValueChanged<int> onPage;
  final ValueChanged<int> onRowsPerPage;
  final bool? dense;
  final ValueChanged<bool>? onDense;
  final List<int> rowsPerPageOptions;

  @override
  Widget build(BuildContext context) {
    final from = total == 0 ? 0 : page * rowsPerPage + 1;
    final to   = math.min(total, (page + 1) * rowsPerPage);
    final lastPage = total == 0 ? 0 : (total - 1) ~/ rowsPerPage;
    const s = TextStyle(fontSize: 13.5, color: WebColors.text1);

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: WebSpace.lg),
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: WebColors.border))),
      child: Row(children: [
        if (onDense != null) ...[
          Switch(
            value: dense ?? false,
            onChanged: onDense,
            activeTrackColor: WebColors.navy,
          ),
          const SizedBox(width: 6),
          const Text('Dense', style: s),
        ],
        const Spacer(),
        const Text('Rows per page:', style: s),
        const SizedBox(width: WebSpace.sm),
        DropdownButtonHideUnderline(child: DropdownButton<int>(
          value: rowsPerPageOptions.contains(rowsPerPage)
              ? rowsPerPage : rowsPerPageOptions.first,
          style: s,
          borderRadius: BorderRadius.circular(WebRadius.sm),
          items: [
            for (final o in rowsPerPageOptions)
              DropdownMenuItem(value: o, child: Text('$o')),
          ],
          onChanged: (v) { if (v != null) onRowsPerPage(v); },
        )),
        const SizedBox(width: WebSpace.xl),
        Text('$from–$to of $total', style: s),
        const SizedBox(width: WebSpace.md),
        IconButton(
          tooltip: 'Previous page',
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: page > 0 ? () => onPage(page - 1) : null,
        ),
        IconButton(
          tooltip: 'Next page',
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: page < lastPage ? () => onPage(page + 1) : null,
        ),
      ]),
    );
  }
}
