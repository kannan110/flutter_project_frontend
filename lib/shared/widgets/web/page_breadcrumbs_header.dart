import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/web_tokens.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PageBreadcrumbsHeader
//
//   Title  [titleTrailing]                                   [action]
//   Subtitle (optional)
//   Home  •  Section  •  Current
//
// Crumbs with a `route` are links (underline on hover); the last crumb is
// the current page — grey and not clickable.
// ═══════════════════════════════════════════════════════════════════════════

class Crumb {
  const Crumb(this.label, [this.route]);
  final String  label;
  final String? route;
}

class PageBreadcrumbsHeader extends StatelessWidget {
  const PageBreadcrumbsHeader({
    super.key,
    required this.title,
    required this.crumbs,
    this.subtitle,
    this.titleTrailing,
    this.action,
    this.padding = const EdgeInsets.only(bottom: WebSpace.lg),
  });

  final String       title;
  final List<Crumb>  crumbs;
  final String?      subtitle;
  final Widget?      titleTrailing;
  /// Right-hand slot — usually the primary "+ New …" button, or a Wrap of
  /// several existing header controls.
  final Widget?      action;
  final EdgeInsets   padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Flexible(child: Text(title, style: WebText.pageTitle,
                maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (titleTrailing != null) ...[
              const SizedBox(width: WebSpace.md),
              titleTrailing!,
            ],
          ]),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: WebText.bodySub),
          ],
          const SizedBox(height: WebSpace.sm),
          BreadcrumbTrail(crumbs: crumbs),
        ],
      )),
      if (action != null) ...[
        const SizedBox(width: WebSpace.lg),
        action!,
      ],
    ]),
  );
}

// ── Trail on its own (detail pages whose banner already shows the title) ──
class BreadcrumbTrail extends StatelessWidget {
  const BreadcrumbTrail({super.key, required this.crumbs});
  final List<Crumb> crumbs;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < crumbs.length; i++) {
      final last = i == crumbs.length - 1;
      if (i > 0) children.add(const _Dot());
      children.add(_CrumbText(crumb: crumbs[i], current: last));
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();
  @override
  Widget build(BuildContext context) => Container(
    width: 4, height: 4,
    margin: const EdgeInsets.symmetric(horizontal: 10),
    decoration: const BoxDecoration(
        color: WebColors.text3, shape: BoxShape.circle),
  );
}

class _CrumbText extends StatefulWidget {
  const _CrumbText({required this.crumb, required this.current});
  final Crumb crumb;
  final bool  current;
  @override
  State<_CrumbText> createState() => _CrumbTextState();
}

class _CrumbTextState extends State<_CrumbText> {
  bool _hov = false;

  @override
  Widget build(BuildContext context) {
    final link = !widget.current && widget.crumb.route != null;
    final text = Text(widget.crumb.label, style: TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w500,
      color: widget.current ? WebColors.text3 : WebColors.text1,
      decoration: link && _hov ? TextDecoration.underline : null,
    ));
    if (!link) return text;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hov = true),
      onExit:  (_) => setState(() => _hov = false),
      child: GestureDetector(
        onTap: () => context.go(widget.crumb.route!),
        child: text,
      ),
    );
  }
}
