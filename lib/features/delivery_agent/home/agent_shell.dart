import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

// Phase 1 B-04: shift status provider so the Shift tab shows open/closed state
// Stores true when agent has an open shift, false otherwise
final agentShiftOpenProvider = StateProvider<bool>((ref) => false);

class AgentShell extends ConsumerWidget {
  const AgentShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = GoRouterState.of(context).matchedLocation;

    // Screens that are "sub-screens" — show back button, hide bottom nav
    final isSubScreen = loc.startsWith('/a/batch/') ||         // batch pickup + DC view
        loc.startsWith('/a/delivery/') ||      // delivery complete
        loc.startsWith('/a/delivery-history/') || // delivery history
        loc == '/a/instant-order' ||           // instant order
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
      bottomNavigationBar: _buildAgentNav(context, ref, idx),
    );
  }

  // Phase 1 B-04: shift-aware bottom nav — Shift tab shows green/grey dot
  BottomNavigationBar _buildAgentNav(BuildContext context, WidgetRef ref, int idx) {
    final shiftOpen = ref.watch(agentShiftOpenProvider);
    return BottomNavigationBar(
      currentIndex: idx,
      onTap: (i) {
        const routes = [R.agentHome, R.agentDeliveries, R.agentExpenses];
        if (i < routes.length) { context.go(routes[i]); return; }
        context.go(R.shiftOpen);
      },
      items: [
        const BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
        const BottomNavigationBarItem(
            icon: Icon(Icons.local_shipping_outlined), activeIcon: Icon(Icons.local_shipping), label: 'Deliveries'),
        const BottomNavigationBarItem(
            icon: Icon(Icons.receipt_outlined), activeIcon: Icon(Icons.receipt), label: 'Expenses'),
        // Shift tab: green dot when open, grey when closed
        BottomNavigationBarItem(
          icon: Stack(clipBehavior: Clip.none, children: [
            const Icon(Icons.schedule_outlined),
            Positioned(right: -2, top: -2,
              child: Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: shiftOpen ? const Color(0xFF22C55E) : Colors.grey.shade400,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
          ]),
          activeIcon: Stack(clipBehavior: Clip.none, children: [
            const Icon(Icons.schedule_rounded),
            Positioned(right: -2, top: -2,
              child: Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: shiftOpen ? const Color(0xFF22C55E) : Colors.grey.shade400,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
          ]),
          label: shiftOpen ? 'Shift ●' : 'Shift',
        ),
      ],
    );
  }
}