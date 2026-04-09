import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';

class AgentShell extends ConsumerWidget {
  const AgentShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = GoRouterState.of(context).matchedLocation;

    // Screens that are "sub-screens" — show back button, hide bottom nav
    final isSubScreen = loc.startsWith('/a/batch/') ||    // batch pickup + DC view
                        loc.startsWith('/a/delivery/') || // delivery complete
                        loc.startsWith('/a/order/');

    int idx = 0;
    if (loc.startsWith('/a/deliveries') || loc.startsWith('/a/delivery')) idx = 1;
    else if (loc.startsWith('/a/expenses'))  idx = 2;
    else if (loc.startsWith('/a/shift'))     idx = 3;

    if (isSubScreen) {
      // Sub-screen: no bottom nav, just show the child with its own AppBar back button
      return Scaffold(body: child);
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: idx,
        onTap: (i) => context.go([R.agentHome, R.agentDeliveries, R.agentExpenses, R.shiftOpen][i]),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.local_shipping_outlined), activeIcon: Icon(Icons.local_shipping), label: 'Deliveries'),
          BottomNavigationBarItem(
              icon: Icon(Icons.receipt_outlined), activeIcon: Icon(Icons.receipt), label: 'Expenses'),
          BottomNavigationBarItem(
              icon: Icon(Icons.schedule_outlined), activeIcon: Icon(Icons.schedule), label: 'Shift'),
        ],
      ),
    );
  }
}
