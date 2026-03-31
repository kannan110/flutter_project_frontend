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
    int idx = 0;
    if (loc.startsWith('/t/order'))         idx = 1;
    else if (loc.startsWith('/t/dispatch')) idx = 2;
    else if (loc.startsWith('/t/approval')) idx = 3;
    else if (idx == 0 && !loc.startsWith('/t/dashboard')) idx = 4;
    if (loc.startsWith('/t/invoices') || loc.startsWith('/t/ledger') ||
        loc.startsWith('/t/retailers') || loc.startsWith('/t/agents') ||
        loc.startsWith('/t/rates') || loc.startsWith('/t/shifts') ||
        loc.startsWith('/t/crates') || loc.startsWith('/t/analytics') ||
        loc.startsWith('/t/settings') || loc.startsWith('/t/returns') ||
        loc.startsWith('/t/stock') || loc.startsWith('/t/pricing') ||
        loc.startsWith('/t/reconciliation') || loc.startsWith('/t/day-closure') ||
        loc.startsWith('/t/alerts') || loc.startsWith('/t/reports')) idx = 4;

    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: idx,
        onTap: (i) => context.go([R.dashboard, R.orders, R.dispatch, R.approvals, R.settings][i]),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.shopping_bag_outlined), activeIcon: Icon(Icons.shopping_bag), label: 'Orders'),
          BottomNavigationBarItem(icon: Icon(Icons.local_shipping_outlined), activeIcon: Icon(Icons.local_shipping), label: 'Dispatch'),
          BottomNavigationBarItem(icon: Icon(Icons.fact_check_outlined), activeIcon: Icon(Icons.fact_check), label: 'Approve'),
          BottomNavigationBarItem(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }
}