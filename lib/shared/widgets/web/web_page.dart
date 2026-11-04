import 'package:flutter/material.dart';
import '../../../core/theme/web_tokens.dart';

// ═══════════════════════════════════════════════════════════════════════════
// WebPage   — standard web page body: slate background, page padding,
//             1400px max width, header then content (scrolls as one).
// WebKpiRow — KPI / summary cards side by side, equal height, 16px gaps.
// ═══════════════════════════════════════════════════════════════════════════

class WebPage extends StatelessWidget {
  const WebPage({
    super.key,
    required this.header,
    required this.children,
    this.footer,
  });

  final Widget       header;
  final List<Widget> children;
  /// Optional bar pinned under the scrolling content (e.g. a selection bar).
  final Widget?      footer;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: WebColors.pageBg,
    child: Column(children: [
      Expanded(child: SingleChildScrollView(
        padding: WebSpace.page,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [header, ...children],
        ),
      )),
      ?footer,
    ]),
  );
}

class WebKpiRow extends StatelessWidget {
  const WebKpiRow({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(width: WebSpace.lg),
        Expanded(child: children[i]),
      ],
    ]),
  );
}

/// Two independent columns (masonry) — cards of different heights stack
/// without leaving gaps, unlike a Wrap/grid.
class WebMasonry extends StatelessWidget {
  const WebMasonry({super.key, required this.children, this.columns = 2,
    this.rowGap = WebSpace.lg});
  final List<Widget> children;
  final int columns;
  /// Vertical gap between cards (0 when the cards carry their own margin).
  final double rowGap;

  @override
  Widget build(BuildContext context) {
    final cols = List.generate(columns, (_) => <Widget>[]);
    for (var i = 0; i < children.length; i++) {
      final c = cols[i % columns];
      if (c.isNotEmpty && rowGap > 0) c.add(SizedBox(height: rowGap));
      c.add(children[i]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < columns; i++) ...[
        if (i > 0) const SizedBox(width: WebSpace.lg),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: cols[i])),
      ],
    ]);
  }
}
