import 'package:flutter/material.dart';

/// A wrapper widget that equips any data table (like [DataTable], custom grids,
/// or reports) with both left-to-right (horizontal) and top-to-bottom (vertical)
/// scrolling and interactive scrollbars.
///
/// Handles unbounded vertical constraints automatically (e.g. when placed inside
/// a [SingleChildScrollView] or [ListView]) by applying [maxHeight]. When placed
/// inside bounded vertical constraints (such as [Expanded] or fixed [SizedBox]),
/// it naturally expands to fill the available space.
class ScrollableTableWrapper extends StatefulWidget {
  const ScrollableTableWrapper({
    super.key,
    required this.child,
    this.maxHeight,
    this.minWidth,
    this.height,
    this.padding,
    this.showScrollbars = true,
  });

  /// The table widget to make scrollable.
  final Widget child;

  /// Optional maximum height constraint. If the parent provides unbounded
  /// height (such as inside a vertically scrolling page or list), defaults
  /// to 500.0 to prevent layout exceptions.
  final double? maxHeight;

  /// Optional minimum width constraint for the horizontal viewport.
  final double? minWidth;

  /// Optional fixed height for the table container.
  final double? height;

  /// Optional padding around the table child inside the scroll views.
  final EdgeInsetsGeometry? padding;

  /// Whether to display visible interactive scrollbars for both axes.
  final bool showScrollbars;

  @override
  State<ScrollableTableWrapper> createState() => _ScrollableTableWrapperState();
}

class _ScrollableTableWrapperState extends State<ScrollableTableWrapper> {
  final ScrollController _hScroll = ScrollController();
  final ScrollController _vScroll = ScrollController();

  @override
  void dispose() {
    _hScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isVerticalUnbounded = constraints.maxHeight == double.infinity;
        final effectiveMaxHeight = widget.height == null
            ? (widget.maxHeight ?? (isVerticalUnbounded ? 500.0 : null))
            : null;

        Widget content = widget.child;
        if (widget.padding != null) {
          content = Padding(padding: widget.padding!, child: content);
        }

        if (widget.minWidth != null) {
          content = ConstrainedBox(
            constraints: BoxConstraints(minWidth: widget.minWidth!),
            child: content,
          );
        }

        Widget horizontalView = SingleChildScrollView(
          controller: _hScroll,
          scrollDirection: Axis.horizontal,
          child: content,
        );

        if (widget.showScrollbars) {
          horizontalView = Scrollbar(
            controller: _hScroll,
            thumbVisibility: true,
            notificationPredicate: (notif) => notif.metrics.axis == Axis.horizontal,
            child: horizontalView,
          );
        }

        Widget verticalView = SingleChildScrollView(
          controller: _vScroll,
          scrollDirection: Axis.vertical,
          child: horizontalView,
        );

        if (widget.showScrollbars) {
          verticalView = Scrollbar(
            controller: _vScroll,
            thumbVisibility: true,
            notificationPredicate: (notif) => notif.metrics.axis == Axis.vertical,
            child: verticalView,
          );
        }

        if (widget.height != null) {
          return SizedBox(
            height: widget.height,
            child: verticalView,
          );
        }

        if (effectiveMaxHeight != null && effectiveMaxHeight.isFinite) {
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: effectiveMaxHeight),
            child: verticalView,
          );
        }

        return verticalView;
      },
    );
  }
}
