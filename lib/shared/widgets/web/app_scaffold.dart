import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/web_tokens.dart';
import '../../layouts/responsive_layout.dart';
import '../../navigation/app_topbar.dart' show topbarTitleForRoute;
import 'page_breadcrumbs_header.dart';
import 'web_card.dart';

// ═══════════════════════════════════════════════════════════════════════════
// AppScaffold — drop-in replacement for Scaffold on inner screens.
//
//  • Mobile / tablet: returns a plain Scaffold with exactly the same
//    arguments — nothing changes on phones.
//  • Desktop: the AppBar becomes a breadcrumbs page header (Back button,
//    title, the screen's own action buttons), an AppBar TabBar becomes a
//    card tab strip, and the body is centred on the slate page with the
//    web theme applied to its inputs, buttons, cards, chips and dialogs.
//    No widget, action or callback of the screen is removed.
// ═══════════════════════════════════════════════════════════════════════════
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    this.appBar,
    this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottomNavigationBar,
    this.bottomSheet,
    this.backgroundColor,
    this.resizeToAvoidBottomInset,
    this.extendBody = false,
    this.extendBodyBehindAppBar = false,
    this.drawer,
    this.endDrawer,
    this.persistentFooterButtons,
    this.webMaxWidth = double.infinity,
  });

  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? bottomNavigationBar;
  final Widget? bottomSheet;
  final Color? backgroundColor;
  final bool? resizeToAvoidBottomInset;
  final bool extendBody;
  final bool extendBodyBehindAppBar;
  final Widget? drawer;
  final Widget? endDrawer;
  final List<Widget>? persistentFooterButtons;
  /// Max content width on desktop.
  final double webMaxWidth;

  @override
  Widget build(BuildContext context) {
    if (!context.isDesktop) {
      return Scaffold(
        appBar: appBar,
        body: body,
        floatingActionButton: floatingActionButton,
        floatingActionButtonLocation: floatingActionButtonLocation,
        bottomNavigationBar: bottomNavigationBar,
        bottomSheet: bottomSheet,
        backgroundColor: backgroundColor,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        extendBody: extendBody,
        extendBodyBehindAppBar: extendBodyBehindAppBar,
        drawer: drawer,
        endDrawer: endDrawer,
        persistentFooterButtons: persistentFooterButtons,
      );
    }

    final bar = appBar is AppBar ? appBar as AppBar : null;
    final tabs = bar?.bottom;

    // Bottom nav clearance spacers exist only for the phone glass nav.
    final bottomBar = bottomNavigationBar is SizedBox &&
            (bottomNavigationBar as SizedBox).child == null
        ? null
        : bottomNavigationBar;

    return Theme(
      data: webInnerTheme(Theme.of(context)),
      child: Scaffold(
        backgroundColor: WebColors.pageBg,
        floatingActionButton: floatingActionButton,
        floatingActionButtonLocation: floatingActionButtonLocation,
        bottomNavigationBar: bottomBar,
        bottomSheet: bottomSheet,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        drawer: drawer,
        endDrawer: endDrawer,
        persistentFooterButtons: persistentFooterButtons,
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
                if (bar != null) _WebAppBarHeader(bar: bar)
                else if (appBar != null) appBar!,
                if (tabs != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: WebSpace.lg),
                    decoration: WebDecor.card(),
                    clipBehavior: Clip.antiAlias,
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        tabBarTheme: const TabBarThemeData(
                          labelColor: WebColors.text1,
                          unselectedLabelColor: WebColors.text2,
                          indicatorColor: WebColors.navy,
                          dividerColor: Colors.transparent,
                          labelStyle: TextStyle(fontSize: 13.5,
                              fontWeight: FontWeight.w700),
                          unselectedLabelStyle: TextStyle(fontSize: 13.5,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      child: tabs,
                    ),
                  ),
                if (body != null) Expanded(child: body!),
              ],
            ),
        ),
      ),
    );
  }
}

// ── AppBar → breadcrumbs header ────────────────────────────────────────────
class _WebAppBarHeader extends StatelessWidget {
  const _WebAppBarHeader({required this.bar});
  final AppBar bar;

  @override
  Widget build(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    final titleText = bar.title is Text ? (bar.title as Text).data : null;
    final current = titleText ?? topbarTitleForRoute(loc);

    // Parent section = first two path segments, e.g. /t/invoices
    final segs = loc.split('/').where((s) => s.isNotEmpty).toList();
    final parentPath = segs.length >= 2 ? '/${segs[0]}/${segs[1]}' : null;
    String? parentTitle;
    if (parentPath != null && parentPath != R.dashboard) {
      final t = topbarTitleForRoute(parentPath);
      parentTitle = t == 'Rooster Commerce OS'
          ? segs[1][0].toUpperCase() + segs[1].substring(1).replaceAll('-', ' ')
          : t;
    }
    final crumbs = <Crumb>[
      const Crumb('Dashboard', R.dashboard),
      if (parentTitle != null && parentTitle != current)
        Crumb(parentTitle, parentPath),
      Crumb(current),
    ];

    final canPop = Navigator.of(context).canPop();
    final leading = bar.leading ??
        (canPop && bar.automaticallyImplyLeading
            ? WebIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                onTap: () => Navigator.of(context).maybePop(),
              )
            : null);

    return Padding(
      padding: const EdgeInsets.only(bottom: WebSpace.lg),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        if (leading != null) ...[
          leading,
          const SizedBox(width: WebSpace.md),
        ],
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            DefaultTextStyle.merge(
              style: WebText.pageTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              child: IconTheme.merge(
                data: const IconThemeData(color: WebColors.text1),
                child: bar.title ?? Text(current),
              ),
            ),
            const SizedBox(height: WebSpace.sm),
            BreadcrumbTrail(crumbs: crumbs),
          ],
        )),
        if (bar.actions != null && bar.actions!.isNotEmpty)
          IconTheme.merge(
            data: const IconThemeData(color: WebColors.text2, size: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: WebColors.surface,
                borderRadius: BorderRadius.circular(WebRadius.button),
                border: Border.all(color: WebColors.border),
              ),
              child: Row(mainAxisSize: MainAxisSize.min,
                  children: bar.actions!),
            ),
          ),
      ]),
    );
  }
}

// ── Web theme for inner content (look only — no layout changes) ─────────────
ThemeData webInnerTheme(ThemeData base) {
  final radius = BorderRadius.circular(WebRadius.button);
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(WebRadius.sm),
      borderSide: BorderSide(color: c, width: w));

  return base.copyWith(
    scaffoldBackgroundColor: WebColors.pageBg,
    cardTheme: base.cardTheme.copyWith(
      color: WebColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WebRadius.card),
        side: const BorderSide(color: WebColors.border),
      ),
    ),
    dividerTheme: const DividerThemeData(color: WebColors.border),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: WebColors.surface,
      border: border(WebColors.border),
      enabledBorder: border(WebColors.border),
      focusedBorder: border(WebColors.navy, 1.5),
      errorBorder: border(WebColors.error),
      focusedErrorBorder: border(WebColors.error, 1.5),
      labelStyle: const TextStyle(fontSize: 13.5, color: WebColors.text2),
      floatingLabelStyle: const TextStyle(fontSize: 13,
          color: WebColors.navy, fontWeight: FontWeight.w700),
      hintStyle: const TextStyle(fontSize: 13.5, color: WebColors.text3),
    ),
    // Keep each button theme's sizing (mobile layouts rely on it);
    // only colours and shape change.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: (base.elevatedButtonTheme.style ?? const ButtonStyle()).merge(
        ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: (base.outlinedButtonTheme.style ?? const ButtonStyle()).merge(
        OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: radius),
          side: const BorderSide(color: WebColors.border),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: WebColors.navy,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: (base.textButtonTheme.style ?? const ButtonStyle()).merge(
        TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WebRadius.sm)),
      side: const BorderSide(color: WebColors.border),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: WebColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WebRadius.dialog),
        side: const BorderSide(color: WebColors.border),
      ),
    ),
    tabBarTheme: base.tabBarTheme.copyWith(
      labelColor: WebColors.text1,
      unselectedLabelColor: WebColors.text2,
      indicatorColor: WebColors.navy,
      dividerColor: WebColors.border,
    ),
    listTileTheme: base.listTileTheme.copyWith(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WebRadius.sm)),
    ),
  );
}
