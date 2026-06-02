import 'package:flutter/material.dart';
import 'package:rooster_trader/core/theme/app_theme.dart';

// ── SectionDivider ────────────────────────────────────────────────────────
class SectionDivider extends StatelessWidget {
  const SectionDivider(
      this.title, {
        super.key,
        this.showDivider = true,
        this.padding,
        this.trailing,
      });

  final String      title;
  final bool        showDivider;
  final EdgeInsets? padding;
  final Widget?     trailing;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (showDivider) const Divider(height: 1, color: kBorderLight),
      Padding(
        padding: padding ?? const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Row(children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize:      11,
                fontWeight:    FontWeight.w800,
                color:         kTextHint,
                letterSpacing: 1.2,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ]),
      ),
    ],
  );
}

// ── SectionCard ────────────────────────────────────────────────────────────
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    required this.child,
    this.padding,
    this.margin,
    this.trailing,
  });

  final String?    title;
  final Widget     child;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final Widget?    trailing;

  @override
  Widget build(BuildContext context) => Container(
    margin: margin ?? const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color:        kSurface,
      borderRadius: BorderRadius.circular(8),
      border:       Border.all(color: kBorderLight),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize:       MainAxisSize.min,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(children: [
              Expanded(
                child: Text(title!,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700,
                        color: kTextMain)),
              ),
              if (trailing != null) trailing!,
            ]),
          ),
        Padding(
          padding: padding ?? const EdgeInsets.all(20),
          child:   child,
        ),
      ],
    ),
  );
}