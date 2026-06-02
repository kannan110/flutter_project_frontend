import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/desktop_shell.dart';
import '../../../shared/layouts/responsive_layout.dart';
import '../../../shared/navigation/navigation_model.dart';

// ── ShellBadges ─────────────────────────────────────────────────────────────
// Public class — other screens write badge counts via shellBadgesProvider
class ShellBadges {
  const ShellBadges({
    this.pendingApprovals = 0,
    this.unreadAlerts     = 0,
    this.pendingOrders    = 0,
  });
  final int pendingApprovals;
  final int unreadAlerts;
  final int pendingOrders;

  ShellBadges copyWith({
    int? pendingApprovals,
    int? unreadAlerts,
    int? pendingOrders,
  }) => ShellBadges(
    pendingApprovals: pendingApprovals ?? this.pendingApprovals,
    unreadAlerts:     unreadAlerts     ?? this.unreadAlerts,
    pendingOrders:    pendingOrders    ?? this.pendingOrders,
  );
}

final shellBadgesProvider =
StateProvider<ShellBadges>((_) => const ShellBadges());

// ── TraderShell ──────────────────────────────────────────────────────────────
// Mobile  → premium glass BottomNav (cream bg, gold active, large radius)
// Tablet  → NavigationRail (navy bg, gold active)  ← unchanged
// Desktop → DesktopShell (navy sidebar + white topbar) ← unchanged
class TraderShell extends ConsumerWidget {
  const TraderShell({super.key, required this.child});
  final Widget child;

  // Preserved exactly — same routing logic
  static int _tabIndex(String loc) {
    if (loc.startsWith('/t/order'))    return 1;
    if (loc.startsWith('/t/dispatch')) return 2;
    if (loc.startsWith('/t/approval')) return 3;
    if (loc.startsWith('/t/dashboard'))return 0;
    return 4;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc    = GoRouterState.of(context).matchedLocation;
    final badges = ref.watch(shellBadgesProvider);

    return ResponsiveLayout(
      // ── MOBILE ────────────────────────────────────────────────────────
      mobile: (_) => Scaffold(
        backgroundColor: kBgPage,
        extendBody:      true,   // content goes under glass nav
        body:            child,
        bottomNavigationBar: _GlassBottomNav(
          currentIndex: _tabIndex(loc),
          badges:       badges,
          onTap: (i) => context.go(
            [R.dashboard, R.orders, R.dispatch, R.approvals, R.settings][i],
          ),
        ),
      ),

      // ── TABLET ────────────────────────────────────────────────────────
      tablet: (_) {
        final railNavItems = TraderNavigation.railItems(
          pendingApprovals: badges.pendingApprovals,
          unreadAlerts:     badges.unreadAlerts,
          pendingOrders:    badges.pendingOrders,
        );
        final selectedIndex =
        traderRailIndex(loc, railNavItems).clamp(0, railNavItems.length - 1);

        final railDestinations = railNavItems.map((item) {
          final hasBadge = (item.badge ?? 0) > 0;
          Widget icon = hasBadge
              ? Badge(
              label: Text('${item.badge}',
                  style: const TextStyle(
                      fontSize: 10, color: Colors.white,
                      fontWeight: FontWeight.w700)),
              backgroundColor: kError,
              child: Icon(item.icon))
              : Icon(item.icon);
          Widget activeIcon = hasBadge
              ? Badge(
              label: Text('${item.badge}',
                  style: const TextStyle(
                      fontSize: 10, color: Colors.white,
                      fontWeight: FontWeight.w700)),
              backgroundColor: kGold,
              child: Icon(item.activeIcon))
              : Icon(item.activeIcon);
          return NavigationRailDestination(
              icon: icon, selectedIcon: activeIcon, label: Text(item.label));
        }).toList();

        return TabletShell(
          railItems:             railDestinations,
          selectedIndex:         selectedIndex,
          onDestinationSelected: (i) => context.go(railNavItems[i].route),
          child:                 child,
        );
      },

      // ── DESKTOP ───────────────────────────────────────────────────────
      desktop: (_) => DesktopShell(
        pendingApprovals: badges.pendingApprovals,
        unreadAlerts:     badges.unreadAlerts,
        pendingOrders:    badges.pendingOrders,
        child:            child,
      ),
    );
  }
}

// ── Glass Bottom Nav ─────────────────────────────────────────────────────────
// Matches reference: glass blur, 28px top radius, gold active bg pill
class _GlassBottomNav extends StatelessWidget {
  const _GlassBottomNav({
    required this.currentIndex,
    required this.badges,
    required this.onTap,
  });
  final int          currentIndex;
  final ShellBadges  badges;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final items = _navItems(badges);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color:  Colors.white.withValues(alpha: 0.88),
            border: Border(
                top: BorderSide(color: kBorderLight.withValues(alpha: 0.5))),
          ),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: SafeArea(
            top: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(items.length, (i) {
                final item    = items[i];
                final active  = i == currentIndex;
                return _NavItem(
                  icon:     active ? item.activeIcon : item.icon,
                  label:    item.label,
                  badge:    item.badge,
                  isActive: active,
                  onTap:    () => onTap(i),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  List<_NavItemData> _navItems(ShellBadges b) => [
    _NavItemData(
      icon:       Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label:      'HOME',
    ),
    _NavItemData(
      icon:       Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long_rounded,
      label:      'ORDERS',
      badge:      b.pendingOrders > 0 ? b.pendingOrders : null,
    ),
    _NavItemData(
      icon:       Icons.local_shipping_outlined,
      activeIcon: Icons.local_shipping_rounded,
      label:      'DISPATCH',
    ),
    _NavItemData(
      icon:       Icons.verified_user_outlined,
      activeIcon: Icons.verified_user_rounded,
      label:      'APPROVE',
      badge:      b.pendingApprovals > 0 ? b.pendingApprovals : null,
    ),
    _NavItemData(
      icon:       Icons.menu_rounded,
      activeIcon: Icons.menu_rounded,
      label:      'MORE',
    ),
  ];
}

class _NavItemData {
  const _NavItemData({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.badge,
  });
  final IconData icon;
  final IconData activeIcon;
  final String   label;
  final int?     badge;
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.badge,
  });
  final IconData icon;
  final String   label;
  final bool     isActive;
  final VoidCallback onTap;
  final int?     badge;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap:     onTap,
      behavior:  HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Active: gold pill bg. Inactive: transparent
          Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isActive
                      ? kGoldBg
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  size:  22,
                  color: isActive ? kWarning : kTextHint,
                ),
              ),
              // Badge dot
              if (badge != null)
                Positioned(
                  right: 6, top: 4,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color:        kError,
                      borderRadius: BorderRadius.circular(99),
                      border:       Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Text(
                      badge! > 99 ? '99+' : '$badge',
                      style: const TextStyle(
                          fontSize: 8, fontWeight: FontWeight.w800,
                          color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize:      9,
              fontWeight:    FontWeight.w800,
              letterSpacing: 0.6,
              color:         isActive ? kWarning : kTextHint,
            ),
          ),
        ]),
      ),
    );
  }
}