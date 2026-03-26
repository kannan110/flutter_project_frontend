import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';

class AgentShell extends StatelessWidget {
  const AgentShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    int selectedIndex = 0;
    if (loc.startsWith('/agent/deliveries')) selectedIndex = 1;
    if (loc.startsWith('/agent/expenses'))   selectedIndex = 2;
    if (loc.startsWith('/agent/shift/close')) selectedIndex = 3;

    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedIndex,
        onTap: (i) {
          switch (i) {
            case 0: context.go(Routes.agentHome); break;
            case 1: context.go(Routes.agentDeliveries); break;
            case 2: context.go(Routes.agentExpenses); break;
            case 3: context.go(Routes.agentShiftClose); break;
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.delivery_dining_outlined), activeIcon: Icon(Icons.delivery_dining), label: 'Deliveries'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_outlined), activeIcon: Icon(Icons.receipt), label: 'Expenses'),
          BottomNavigationBarItem(icon: Icon(Icons.lock_clock_outlined), activeIcon: Icon(Icons.lock_clock), label: 'Close Shift'),
        ],
      ),
    );
  }
}
