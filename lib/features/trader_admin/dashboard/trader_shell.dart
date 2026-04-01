import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';

class TraderShell extends ConsumerWidget {
  const TraderShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = GoRouterState.of(context).matchedLocation;

    // ── Tab index ─────────────────────────────────────────────────
    int idx = 0;
    if (loc.startsWith('/t/order'))      idx = 1;
    else if (loc.startsWith('/t/dispatch')) idx = 2;
    else if (loc.startsWith('/t/approval')) idx = 3;
    else if (!loc.startsWith('/t/dashboard')) idx = 4;

    // Sub-screens that are NOT top-level tabs — they get a back button
    // These are pushed via context.push() so canPop() is true
    final isSubScreen =
        loc.startsWith('/t/orders/create') ||
        loc.startsWith('/t/orders/') ||          // order detail
        loc.startsWith('/t/dispatch/batch/') ||   // batch detail
        loc.startsWith('/t/approvals/') ||        // approval detail
        loc.startsWith('/t/invoices/') ||         // invoice detail
        loc.startsWith('/t/ledger/') ||           // retailer ledger
        loc.startsWith('/t/retailers/create') ||
        loc.startsWith('/t/retailers/') ||        // retailer detail
        loc.startsWith('/t/agents/create') ||
        loc.startsWith('/t/agents/') ||           // agent detail
        loc.startsWith('/t/shifts/');             // shift detail

    if (isSubScreen) {
      // Sub-screen: wrap in WillPopScope so Android back button works,
      // and show bottom nav so user can still jump to a tab
      return Scaffold(
        body: child,
        bottomNavigationBar: _buildBottomNav(context, idx),
      );
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: _buildBottomNav(context, idx),
    );
  }

  BottomNavigationBar _buildBottomNav(BuildContext context, int idx) =>
      BottomNavigationBar(
        currentIndex: idx,
        onTap: (i) => context.go(
            [R.dashboard, R.orders, R.dispatch, R.approvals, R.settings][i]),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard),
              label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.shopping_bag_outlined),
              activeIcon: Icon(Icons.shopping_bag),
              label: 'Orders'),
          BottomNavigationBarItem(
              icon: Icon(Icons.local_shipping_outlined),
              activeIcon: Icon(Icons.local_shipping),
              label: 'Dispatch'),
          BottomNavigationBarItem(
              icon: Icon(Icons.fact_check_outlined),
              activeIcon: Icon(Icons.fact_check),
              label: 'Approve'),
          BottomNavigationBarItem(
              icon: Icon(Icons.more_horiz),
              label: 'More'),
        ],
      );
}
