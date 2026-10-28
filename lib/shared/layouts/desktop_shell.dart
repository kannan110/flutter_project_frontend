import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../navigation/app_sidebar.dart';
import '../navigation/app_topbar.dart';

// ── DesktopShell ──────────────────────────────────────────────────────────────
// Layout:
//   ┌────────────────────────────────────────────┐
//   │  [Sidebar 200px]  │  [Topbar 56px]         │
//   │  (collapsible     │  ─────────────────────  │
//   │   to 60px)        │  [Content area]         │
//   └────────────────────────────────────────────┘
class DesktopShell extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final loc   = GoRouterState.of(context).matchedLocation;
    final title = topbarTitleForRoute(loc);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      body: Row(children: [
        // ── Collapsible sidebar ────────────────────────────────────────────
        AppSidebar(
          pendingApprovals: pendingApprovals,
          unreadAlerts:     unreadAlerts,
          pendingOrders:    pendingOrders,
        ),

        // ── Content column (topbar + page content) ─────────────────────────
        Expanded(child: Column(children: [
          // Sticky topbar
          AppTopbar(
            title:        title,
            unreadAlerts: unreadAlerts,
            onRefresh:    onRefresh,
            langNotifier: langNotifier,
            currentLang:  currentLang,
          ),
          // Page content — scrolls independently
          Expanded(child: ColoredBox(
            color: const Color(0xFFF8F9FB),
            child: child,
          )),
        ])),
      ]),
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
    backgroundColor: const Color(0xFFF8F9FB),
    body: Row(children: [
      NavigationRail(
        backgroundColor:       const Color(0xFF0F172A),
        selectedIndex:         selectedIndex,
        onDestinationSelected: onDestinationSelected,
        labelType:             NavigationRailLabelType.all,
        selectedIconTheme:     const IconThemeData(color: Color(0xFFF59E0B)),
        unselectedIconTheme:   const IconThemeData(color: Color(0xFF64748B)),
        selectedLabelTextStyle: const TextStyle(
            color: Color(0xFFF59E0B), fontWeight: FontWeight.w600, fontSize: 11),
        unselectedLabelTextStyle: const TextStyle(
            color: Color(0xFF64748B), fontSize: 11),
        indicatorColor: const Color(0xFF1E293B),
        destinations:   railItems,
        leading: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 12),
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Center(child: Text('🐓',
                style: TextStyle(fontSize: 18))),
          ),
        ),
      ),
      Container(width: 1, color: const Color(0xFF1E293B)),
      Expanded(child: ClipRect(child: child)),
    ]),
  );
}