import 'package:flutter/material.dart';

// ── Breakpoints ───────────────────────────────────────────────────────────────
//
//  Mobile  : < 768 px   → BottomNavigationBar
//  Tablet  : 768–1199px → NavigationRail
//  Desktop : ≥ 1200 px  → Sidebar + Topbar
//
const double kMobileBreak  = 600.0;
const double kDesktopBreak = 900.0;

// ── BuildContext extension ────────────────────────────────────────────────────
//
// Usage:
//   if (context.isDesktop) ...
//   if (context.isMobile)  ...
//
extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.of(this).size.width;

  bool get isMobile  => screenWidth < kMobileBreak;
  bool get isTablet  => screenWidth >= kMobileBreak && screenWidth < kDesktopBreak;
  bool get isDesktop => screenWidth >= kDesktopBreak;

  // Convenience: anything that should behave like "wide screen"
  bool get isWide => screenWidth >= kMobileBreak;
}

// ── ResponsiveLayout ─────────────────────────────────────────────────────────
//
// Switches between three builders based on the current breakpoint.
// All three are optional; falls back to mobile if tablet/desktop omitted.
//
// Usage:
//   ResponsiveLayout(
//     mobile:  (context) => MobileWidget(),
//     tablet:  (context) => TabletWidget(),   // optional
//     desktop: (context) => DesktopWidget(),  // optional
//   )
//
class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  final WidgetBuilder mobile;
  final WidgetBuilder? tablet;
  final WidgetBuilder? desktop;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;

    if (w >= kDesktopBreak) {
      return (desktop ?? tablet ?? mobile)(context);
    }
    if (w >= kMobileBreak) {
      return (tablet ?? mobile)(context);
    }
    return mobile(context);
  }
}

// ── ResponsiveValue ───────────────────────────────────────────────────────────
//
// Returns a typed value based on breakpoint — useful for padding, column counts,
// font sizes, etc. without building whole widget trees.
//
// Usage:
//   final columns = ResponsiveValue(context, mobile: 1, tablet: 2, desktop: 4).value;
//
class ResponsiveValue<T> {
  const ResponsiveValue(
      this._context, {
        required this.mobile,
        this.tablet,
        this.desktop,
      });

  final BuildContext _context;
  final T mobile;
  final T? tablet;
  final T? desktop;

  T get value {
    final w = MediaQuery.of(_context).size.width;
    if (w >= kDesktopBreak) return desktop ?? tablet ?? mobile;
    if (w >= kMobileBreak)  return tablet ?? mobile;
    return mobile;
  }
}