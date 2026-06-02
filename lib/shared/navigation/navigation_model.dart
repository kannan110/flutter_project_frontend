import 'package:flutter/material.dart';
import '../../core/router/app_router.dart';

// ── NavItem ───────────────────────────────────────────────────────────────────

class NavItem {
  const NavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.route,
    this.badge,
  });

  final String   label;
  final IconData icon;
  final IconData activeIcon;
  final String   route;

  /// Optional live count badge (e.g. pending approvals).
  /// Null = no badge. 0 = badge hidden. >0 = badge shown.
  final int? badge;

  NavItem copyWithBadge(int? badge) => NavItem(
    label:      label,
    icon:       icon,
    activeIcon: activeIcon,
    route:      route,
    badge:      badge,
  );
}

// ── NavSection ────────────────────────────────────────────────────────────────

class NavSection {
  const NavSection({required this.title, required this.items});
  final String?    title; // null = no section header (first section)
  final List<NavItem> items;
}

// ── Static nav definitions ────────────────────────────────────────────────────

class TraderNavigation {
  TraderNavigation._();

  // Bottom nav items (mobile — 5 tabs, matches existing TraderShell exactly)
  static const List<NavItem> bottomNavItems = [
    NavItem(
      label:      'Home',
      icon:       Icons.dashboard_outlined,
      activeIcon: Icons.dashboard,
      route:      '/t/dashboard',
    ),
    NavItem(
      label:      'Orders',
      icon:       Icons.shopping_bag_outlined,
      activeIcon: Icons.shopping_bag,
      route:      '/t/orders',
    ),
    NavItem(
      label:      'Dispatch',
      icon:       Icons.local_shipping_outlined,
      activeIcon: Icons.local_shipping,
      route:      '/t/dispatch',
    ),
    NavItem(
      label:      'Approve',
      icon:       Icons.fact_check_outlined,
      activeIcon: Icons.fact_check,
      route:      '/t/approvals',
    ),
    NavItem(
      label:      'More',
      icon:       Icons.more_horiz,
      activeIcon: Icons.more_horiz,
      route:      '/t/settings',
    ),
  ];

  // Full sidebar sections (desktop / tablet)
  static List<NavSection> sidebarSections({
    int pendingApprovals = 0,
    int unreadAlerts     = 0,
    int pendingOrders    = 0,
  }) =>
      [
        // ── Primary ─────────────────────────────────────────────────────────
        NavSection(
          title: null,
          items: [
            NavItem(
              label:      'Dashboard',
              icon:       Icons.dashboard_outlined,
              activeIcon: Icons.dashboard_rounded,
              route:      R.dashboard,
            ),
          ],
        ),

        // ── Operations ──────────────────────────────────────────────────────
        NavSection(
          title: 'OPERATIONS',
          items: [
            NavItem(
              label:      'Orders',
              icon:       Icons.shopping_bag_outlined,
              activeIcon: Icons.shopping_bag_rounded,
              route:      R.orders,
              badge:      pendingOrders > 0 ? pendingOrders : null,
            ),
            NavItem(
              label:      'Dispatch',
              icon:       Icons.local_shipping_outlined,
              activeIcon: Icons.local_shipping_rounded,
              route:      R.dispatch,
            ),
            NavItem(
              label:      'Approvals',
              icon:       Icons.fact_check_outlined,
              activeIcon: Icons.fact_check_rounded,
              route:      R.approvals,
              badge:      pendingApprovals > 0 ? pendingApprovals : null,
            ),
            NavItem(
              label:      'Stock',
              icon:       Icons.inventory_2_outlined,
              activeIcon: Icons.inventory_2_rounded,
              route:      R.stock,
            ),
            NavItem(
              label:      'Returns',
              icon:       Icons.assignment_return_outlined,
              activeIcon: Icons.assignment_return_rounded,
              route:      R.returns,
            ),
          ],
        ),

        // ── Finance ─────────────────────────────────────────────────────────
        NavSection(
          title: 'FINANCE',
          items: [
            NavItem(
              label:      'Ledger',
              icon:       Icons.account_balance_wallet_outlined,
              activeIcon: Icons.account_balance_wallet_rounded,
              route:      R.ledger,
            ),
            NavItem(
              label:      'Invoices',
              icon:       Icons.receipt_long_outlined,
              activeIcon: Icons.receipt_long_rounded,
              route:      R.invoices,
            ),
            NavItem(
              label:      'Rates',
              icon:       Icons.price_change_outlined,
              activeIcon: Icons.price_change_rounded,
              route:      R.rates,
            ),
            NavItem(
              label:      'Reconciliation',
              icon:       Icons.balance_outlined,
              activeIcon: Icons.balance_rounded,
              route:      R.cashRecon,
            ),
            NavItem(
              label:      'Day Closure',
              icon:       Icons.today_outlined,
              activeIcon: Icons.today_rounded,
              route:      R.dayClosure,
            ),
          ],
        ),

        // ── People ──────────────────────────────────────────────────────────
        NavSection(
          title: 'PEOPLE',
          items: [
            NavItem(
              label:      'Retailers',
              icon:       Icons.storefront_outlined,
              activeIcon: Icons.storefront_rounded,
              route:      R.retailers,
            ),
            NavItem(
              label:      'Agents',
              icon:       Icons.directions_bike_outlined,
              activeIcon: Icons.directions_bike_rounded,
              route:      R.agents,
            ),
            NavItem(
              label:      'User Management',
              icon:       Icons.manage_accounts_outlined,
              activeIcon: Icons.manage_accounts_rounded,
              route:      R.userMgmt,
            ),
          ],
        ),

        // ── Tracking ────────────────────────────────────────────────────────
        NavSection(
          title: 'TRACKING',
          items: [
            NavItem(
              label:      'Crates',
              icon:       Icons.inventory_outlined,
              activeIcon: Icons.inventory_rounded,
              route:      R.crates,
            ),
            NavItem(
              label:      'Shifts',
              icon:       Icons.schedule_outlined,
              activeIcon: Icons.schedule_rounded,
              route:      R.shifts,
            ),
            NavItem(
              label:      'Pricing Rules',
              icon:       Icons.rule_outlined,
              activeIcon: Icons.rule_rounded,
              route:      R.pricing,
            ),
          ],
        ),

        // ── Insights ────────────────────────────────────────────────────────
        NavSection(
          title: 'INSIGHTS',
          items: [
            NavItem(
              label:      'Analytics',
              icon:       Icons.bar_chart_outlined,
              activeIcon: Icons.bar_chart_rounded,
              route:      R.analytics,
            ),
            NavItem(
              label:      'Reports',
              icon:       Icons.summarize_outlined,
              activeIcon: Icons.summarize_rounded,
              route:      R.reportsHub,
            ),
            NavItem(
              label:      'Alerts',
              icon:       Icons.notifications_outlined,
              activeIcon: Icons.notifications_rounded,
              route:      R.alerts,
              badge:      unreadAlerts > 0 ? unreadAlerts : null,
            ),
          ],
        ),

        // ── Config ──────────────────────────────────────────────────────────
        NavSection(
          title: 'ACCOUNT',
          items: [
            NavItem(
              label:      'Settings',
              icon:       Icons.settings_outlined,
              activeIcon: Icons.settings_rounded,
              route:      R.settings,
            ),
            NavItem(
              label:      'Purchase',
              icon:       Icons.workspace_premium_outlined,
              activeIcon: Icons.workspace_premium_rounded,
              route:      R.purchase,
            ),
          ],
        ),
      ];

  // NavigationRail items (tablet — subset of sidebar sections, flat list)
  static List<NavItem> railItems({
    int pendingApprovals = 0,
    int unreadAlerts     = 0,
    int pendingOrders    = 0,
  }) =>
      [
        NavItem(
          label:      'Home',
          icon:       Icons.dashboard_outlined,
          activeIcon: Icons.dashboard_rounded,
          route:      R.dashboard,
        ),
        NavItem(
          label:      'Orders',
          icon:       Icons.shopping_bag_outlined,
          activeIcon: Icons.shopping_bag_rounded,
          route:      R.orders,
          badge:      pendingOrders > 0 ? pendingOrders : null,
        ),
        NavItem(
          label:      'Dispatch',
          icon:       Icons.local_shipping_outlined,
          activeIcon: Icons.local_shipping_rounded,
          route:      R.dispatch,
        ),
        NavItem(
          label:      'Approve',
          icon:       Icons.fact_check_outlined,
          activeIcon: Icons.fact_check_rounded,
          route:      R.approvals,
          badge:      pendingApprovals > 0 ? pendingApprovals : null,
        ),
        NavItem(
          label:      'Stock',
          icon:       Icons.inventory_2_outlined,
          activeIcon: Icons.inventory_2_rounded,
          route:      R.stock,
        ),
        NavItem(
          label:      'Ledger',
          icon:       Icons.account_balance_wallet_outlined,
          activeIcon: Icons.account_balance_wallet_rounded,
          route:      R.ledger,
        ),
        NavItem(
          label:      'Retailers',
          icon:       Icons.storefront_outlined,
          activeIcon: Icons.storefront_rounded,
          route:      R.retailers,
        ),
        NavItem(
          label:      'Agents',
          icon:       Icons.directions_bike_outlined,
          activeIcon: Icons.directions_bike_rounded,
          route:      R.agents,
        ),
        NavItem(
          label:      'Reports',
          icon:       Icons.summarize_outlined,
          activeIcon: Icons.summarize_rounded,
          route:      R.reportsHub,
        ),
        NavItem(
          label:      'Alerts',
          icon:       Icons.notifications_outlined,
          activeIcon: Icons.notifications_rounded,
          route:      R.alerts,
          badge:      unreadAlerts > 0 ? unreadAlerts : null,
        ),
        NavItem(
          label:      'Settings',
          icon:       Icons.settings_outlined,
          activeIcon: Icons.settings_rounded,
          route:      R.settings,
        ),
      ];
}

// ── Route → tab index helper ──────────────────────────────────────────────────
//
// Matches the existing TraderShell tab logic exactly so switching between
// mobile/tablet/desktop produces the same selected index.
//
int traderBottomNavIndex(String loc) {
  if (loc.startsWith('/t/order'))    return 1;
  if (loc.startsWith('/t/dispatch')) return 2;
  if (loc.startsWith('/t/approval')) return 3;
  if (loc.startsWith('/t/dashboard')) return 0;
  return 4; // "More" / settings catch-all
}

// Returns the rail index for a given location, or -1 if no match.
int traderRailIndex(String loc, List<NavItem> items) {
  for (int i = 0; i < items.length; i++) {
    if (loc.startsWith(items[i].route)) return i;
  }
  return 0;
}

// Returns the sidebar route that best matches loc, or the dashboard route.
String? activeSidebarRoute(String loc, List<NavSection> sections) {
  String? best;
  int     bestLen = 0;
  for (final section in sections) {
    for (final item in section.items) {
      if (loc.startsWith(item.route) && item.route.length > bestLen) {
        best    = item.route;
        bestLen = item.route.length;
      }
    }
  }
  return best;
}