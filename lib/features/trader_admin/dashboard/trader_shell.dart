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
// Tablet  → NavigationRail (navy bg, gold active)
// Desktop → DesktopShell (navy sidebar + white topbar)
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
          onTap: (i) {
            if (i == 4) {
              // Phase 2: More tab → bottom sheet with full navigation grid
              _showMoreSheet(context);
            } else {
              context.go(
                [R.dashboard, R.orders, R.dispatch, R.approvals, R.settings][i],
              );
            }
          },
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

  static void _showMoreSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _MoreSheet(),
    );
  }
}

// ── More Bottom Sheet ─────────────────────────────────────────────────────────
// Phase 2: replaces the direct Settings navigation from the More tab
class _MoreSheet extends StatelessWidget {
  const _MoreSheet();

  @override
  Widget build(BuildContext context) {
    const items = [
      _MoreItem(Icons.account_balance_wallet_rounded, 'Ledger',        Color(0xFF00081E), R.ledger),
      _MoreItem(Icons.inventory_2_rounded,            'Stock',         Color(0xFF0D9488), R.stock),
      _MoreItem(Icons.bar_chart_rounded,              'Analytics',     Color(0xFF7C3AED), R.analytics),
      _MoreItem(Icons.storefront_rounded,             'Retailers',     Color(0xFF0284C7), R.retailers),
      _MoreItem(Icons.directions_bike_rounded,        'Agents',        Color(0xFF57534E), R.agents),
      _MoreItem(Icons.map_rounded,                    'Delivery Areas',Color(0xFFB45309), R.areaManagement),
      _MoreItem(Icons.assignment_return_rounded,      'Returns',       Color(0xFFDC2626), R.returns),
      _MoreItem(Icons.receipt_long_rounded,           'Invoices',      Color(0xFFB45309), R.invoices),
      _MoreItem(Icons.price_change_rounded,           'Rates',         Color(0xFF059669), R.rates),
      _MoreItem(Icons.inventory_rounded,              'Crates',        Color(0xFF7C3AED), R.crates),
      _MoreItem(Icons.schedule_rounded,               'Shifts',        Color(0xFF475569), R.shifts),
      _MoreItem(Icons.rule_rounded,                   'Pricing',       Color(0xFF0369A1), R.pricing),
      _MoreItem(Icons.balance_rounded,                'Cash Recon',    Color(0xFF059669), R.cashRecon),
      _MoreItem(Icons.today_rounded,                  'Day Closure',   Color(0xFFDC2626), R.dayClosure),
      _MoreItem(Icons.trending_up_rounded,            'P&L',           Color(0xFF1B5E20), R.pnlStatement),
      _MoreItem(Icons.water_drop_rounded,             'Cash Flow',     Color(0xFF0369A1), R.cashFlowStatement),
      _MoreItem(Icons.summarize_rounded,              'Reports',       Color(0xFF00081E), R.reportsHome),
      _MoreItem(Icons.settings_rounded,               'Settings',      Color(0xFF475569), R.settings),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle bar
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 4),
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Row(children: [
            const Text('Quick Navigation',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                    color: kNavy)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, size: 20, color: kTextHint),
              onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ]),
        ),
        const Divider(height: 1),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.0,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) => _MoreTile(item: items[i]),
        ),
      ]),
    );
  }
}

class _MoreItem {
  const _MoreItem(this.icon, this.label, this.color, this.route);
  final IconData icon;
  final String   label;
  final Color    color;
  final String   route;
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({required this.item});
  final _MoreItem item;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () {
      Navigator.of(context, rootNavigator: true).pop();
      context.go(item.route);
    },
    borderRadius: BorderRadius.circular(12),
    child: Container(
      decoration: BoxDecoration(
        color: item.color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: item.color.withValues(alpha: 0.15)),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(item.icon, color: item.color, size: 22),
        const SizedBox(height: 4),
        Text(item.label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: item.color)),
      ]),
    ),
  );
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
    const _NavItemData(
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
    const _NavItemData(
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
    const _NavItemData(
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