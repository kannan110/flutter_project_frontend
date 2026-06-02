import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../navigation/app_sidebar.dart';
import '../navigation/app_topbar.dart';

// ── Topbar height ─────────────────────────────────────────────────────────
const double kTopbarHeight = 64.0;

// ── DesktopShell ──────────────────────────────────────────────────────────
// Navy sidebar + white topbar + content area
//
//   ┌──────────────────────────────────────────────────────┐
//   │ Navy Topbar (64px)                                   │
//   ├──────────────┬───────────────────────────────────────┤
//   │              │                                       │
//   │ Navy Sidebar │  Content (kBgPage background)         │
//   │ (256px)      │                                       │
//   │              │                                       │
//   └──────────────┴───────────────────────────────────────┘
//
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

  final Widget   child;
  final int      pendingApprovals;
  final int      unreadAlerts;
  final int      pendingOrders;
  final VoidCallback?          onRefresh;
  final StateController<String>? langNotifier;
  final String?  currentLang;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc   = GoRouterState.of(context).matchedLocation;
    final title = topbarTitleForRoute(loc);

    return Scaffold(
      backgroundColor: kBgPage,
      body: Row(
        children: [
          // ── Navy sidebar ──────────────────────────────────────────────
          AppSidebar(
            pendingApprovals: pendingApprovals,
            unreadAlerts:     unreadAlerts,
            pendingOrders:    pendingOrders,
          ),

          // ── Content column ────────────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                // Topbar
                AppTopbar(
                  title:        title,
                  unreadAlerts: unreadAlerts,
                  onRefresh:    onRefresh,
                  langNotifier: langNotifier,
                  currentLang:  currentLang,
                ),
                // Content
                Expanded(child: ClipRect(child: child)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── TabletShell ────────────────────────────────────────────────────────────
// NavigationRail using Navy colours, consistent with sidebar
class TabletShell extends ConsumerWidget {
  const TabletShell({
    super.key,
    required this.child,
    required this.railItems,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final Widget   child;
  final List<NavigationRailDestination> railItems;
  final int      selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: kBgPage,
      body: Row(
        children: [
          // Navy NavigationRail
          NavigationRail(
            backgroundColor:      kNavy,
            selectedIndex:        selectedIndex,
            onDestinationSelected: onDestinationSelected,
            labelType:            NavigationRailLabelType.all,
            selectedIconTheme:    const IconThemeData(color: kGoldLight),
            unselectedIconTheme:  const IconThemeData(color: kNavyLight),
            selectedLabelTextStyle: const TextStyle(
              color:      kGoldLight,
              fontWeight: FontWeight.w700,
              fontSize:   11,
            ),
            unselectedLabelTextStyle: const TextStyle(
              color:    kSidebarText,
              fontSize: 11,
            ),
            indicatorColor: kNavyMid,
            destinations:   railItems,
            leading: Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 12),
              child: Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [kGold, kGoldLight],
                    begin: Alignment.topLeft,
                    end:   Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Center(
                  child: Text('🐓', style: TextStyle(fontSize: 20)),
                ),
              ),
            ),
          ),
          // Right divider
          Container(width: 1, color: kGold.withValues(alpha: 0.2)),
          // Content
          Expanded(child: ClipRect(child: child)),
        ],
      ),
    );
  }
}