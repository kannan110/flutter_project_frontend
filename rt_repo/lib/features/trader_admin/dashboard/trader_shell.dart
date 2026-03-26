import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';
import '../../../core/providers/session_provider.dart';

class TraderShell extends ConsumerWidget {
  const TraderShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(appUserProvider).valueOrNull;
    final loc = GoRouterState.of(context).matchedLocation;

    int selectedIndex = 0;
    if (loc.startsWith('/orders'))   selectedIndex = 1;
    if (loc.startsWith('/dispatch')) selectedIndex = 2;
    if (loc.startsWith('/ledger'))   selectedIndex = 3;
    if (loc.startsWith('/retailers') || loc.startsWith('/agents') ||
        loc.startsWith('/rates') || loc.startsWith('/shifts') ||
        loc.startsWith('/crates') || loc.startsWith('/analytics') ||
        loc.startsWith('/settings') || loc.startsWith('/approvals') ||
        loc.startsWith('/invoices')) selectedIndex = 4;

    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedIndex,
        onTap: (i) {
          switch (i) {
            case 0: context.go(Routes.dashboard); break;
            case 1: context.go(Routes.orders); break;
            case 2: context.go(Routes.dispatch); break;
            case 3: context.go(Routes.ledger); break;
            case 4: context.go(Routes.settings); break;
          }
        },
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
          const BottomNavigationBarItem(icon: Icon(Icons.shopping_cart_outlined), activeIcon: Icon(Icons.shopping_cart), label: 'Orders'),
          const BottomNavigationBarItem(icon: Icon(Icons.local_shipping_outlined), activeIcon: Icon(Icons.local_shipping), label: 'Dispatch'),
          const BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_outlined), activeIcon: Icon(Icons.account_balance_wallet), label: 'Ledger'),
          BottomNavigationBarItem(
            icon: const Icon(Icons.more_horiz),
            label: user?.isTraderAdmin == true ? 'More' : 'More',
          ),
        ],
      ),
    );
  }
}
