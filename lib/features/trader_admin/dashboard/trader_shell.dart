import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';

class TraderShell extends StatelessWidget {
  const TraderShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    final idx = _indexFor(loc);
    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: idx,
        onTap: (i) {
          switch (i) {
            case 0: context.go(Routes.dashboard); break;
            case 1: context.go(Routes.orders);    break;
            case 2: context.go(Routes.dispatch);  break;
            case 3: context.go(Routes.ledger);    break;
            case 4: context.go(Routes.settings);  break;
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined),                  activeIcon: Icon(Icons.home),                  label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.shopping_cart_outlined),          activeIcon: Icon(Icons.shopping_cart),          label: 'Orders'),
          BottomNavigationBarItem(icon: Icon(Icons.local_shipping_outlined),         activeIcon: Icon(Icons.local_shipping),         label: 'Dispatch'),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_outlined), activeIcon: Icon(Icons.account_balance_wallet), label: 'Ledger'),
          BottomNavigationBarItem(icon: Icon(Icons.more_horiz_outlined),             activeIcon: Icon(Icons.more_horiz),             label: 'More'),
        ],
      ),
    );
  }

  int _indexFor(String loc) {
    if (loc.startsWith('/t/orders'))   return 1;
    if (loc.startsWith('/t/dispatch')) return 2;
    if (loc.startsWith('/t/ledger'))   return 3;
    if (loc == Routes.dashboard)       return 0;
    return 4; // approvals, invoices, agents, retailers, rates, shifts, crates, analytics, settings
  }
}
