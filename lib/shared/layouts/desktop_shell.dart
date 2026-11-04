import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/web_tokens.dart';
import '../navigation/app_sidebar.dart';
import '../navigation/app_topbar.dart';
import '../widgets/web/app_scaffold.dart' show webInnerTheme;

// ── DesktopShell ──────────────────────────────────────────────────────────────
// Layout:
//   ┌────────────────────────────────────────────┐
//   │  [Sidebar 200px]  │  [Topbar 56px]         │
//   │  (collapsible     │  ─────────────────────  │
//   │   to 60px)        │  [Content area]         │
//   └────────────────────────────────────────────┘
class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({
    super.key,
    required this.child,
    this.pendingApprovals = 0,
    this.unreadAlerts     = 0,
    this.pendingOrders    = 0,
    this.onRefresh,
    this.langNotifier,
    this.currentLang,
  });

  final Widget               child;
  final int                  pendingApprovals;
  final int                  unreadAlerts;
  final int                  pendingOrders;
  final VoidCallback?        onRefresh;
  final StateController<String>? langNotifier;
  final String?              currentLang;

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed) &&
        (event.logicalKey == LogicalKeyboardKey.keyG ||
            event.logicalKey == LogicalKeyboardKey.keyK)) {
      if (mounted) {
        ref.read(topbarSearchFocusNodeProvider).requestFocus();
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final loc   = GoRouterState.of(context).matchedLocation;
    final title = topbarTitleForRoute(loc);

    final collapsed = ref.watch(sidebarCollapsedProvider);
    final sideW = collapsed ? kSidebarCollapsedWidth : kSidebarWidth;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyG, control: true): () =>
            ref.read(topbarSearchFocusNodeProvider).requestFocus(),
        const SingleActivator(LogicalKeyboardKey.keyG, meta: true): () =>
            ref.read(topbarSearchFocusNodeProvider).requestFocus(),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            ref.read(topbarSearchFocusNodeProvider).requestFocus(),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            ref.read(topbarSearchFocusNodeProvider).requestFocus(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: WebColors.pageBg,
          body: Stack(children: [
            Row(children: [
              // ── Collapsible sidebar (mounted once; only content changes) ────
              AppSidebar(
                pendingApprovals: widget.pendingApprovals,
                unreadAlerts:     widget.unreadAlerts,
                pendingOrders:    widget.pendingOrders,
              ),

              // ── Content column (topbar + page content) ───────────────────────
              Expanded(child: Column(children: [
                // Sticky topbar
                AppTopbar(
                  title:        title,
                  unreadAlerts: widget.unreadAlerts,
                  onRefresh:    widget.onRefresh,
                  langNotifier: widget.langNotifier,
                  currentLang:  widget.currentLang,
                ),
                // Page content — scrolls independently
                Expanded(child: ColoredBox(
                  color: WebColors.pageBg,
                  // Web look for inner widgets (colours/shape only)
                  child: Theme(data: webInnerTheme(Theme.of(context)), child: widget.child),
                )),
              ])),
            ]),

            // ── Round collapse toggle on the sidebar's right edge ─────────────
            AnimatedPositioned(
              duration: const Duration(milliseconds: 180),
              curve:    Curves.easeInOut,
              left: sideW - 13,
              top:  (WebSize.topbar - 26) / 2,
              child: const SidebarEdgeToggle(),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── TabletShell ───────────────────────────────────────────────────────────────
class TabletShell extends ConsumerWidget {
  const TabletShell({
    super.key,
    required this.child,
    required this.railItems,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final Widget                          child;
  final List<NavigationRailDestination> railItems;
  final int                             selectedIndex;
  final ValueChanged<int>               onDestinationSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    backgroundColor: WebColors.pageBg,
    body: Row(children: [
      // NavigationRail needs a bounded height and can't scroll itself, so in
      // windows too short for every destination the rail scrolls instead
      // of overflowing.
      LayoutBuilder(builder: (_, box) => SingleChildScrollView(
          child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(child: NavigationRail(
        backgroundColor:       WebColors.sideBg,
        selectedIndex:         selectedIndex,
        onDestinationSelected: onDestinationSelected,
        labelType:             NavigationRailLabelType.all,
        selectedIconTheme:     const IconThemeData(color: WebColors.navy),
        unselectedIconTheme:   const IconThemeData(color: WebColors.sideText),
        selectedLabelTextStyle: const TextStyle(
            color: WebColors.navy, fontWeight: FontWeight.w700, fontSize: 11),
        unselectedLabelTextStyle: const TextStyle(
            color: WebColors.sideText, fontSize: 11),
        indicatorColor: WebColors.gold,
        destinations:   railItems,
        leading: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 12),
          child: Container(
            width: 36, height: 36,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: WebColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: WebColors.sideBorder),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A0F172A),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Image.asset(
              'assets/images/app_icon.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
      ))))),
      Container(width: 1, color: WebColors.sideBorder),
      Expanded(child: ClipRect(child: child)),
    ]),
  );
}