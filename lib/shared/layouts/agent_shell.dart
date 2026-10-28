import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class AgentShell extends ConsumerWidget {
  const AgentShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = GoRouterState.of(context).matchedLocation;

    final isSubScreen = loc.startsWith('/a/batch/') ||
        loc.startsWith('/a/delivery/') ||
        loc.startsWith('/a/delivery-history/') ||
        loc == '/a/instant-order' ||
        loc.startsWith('/a/order/');

    int idx = 0;
    if (loc.startsWith('/a/deliveries') || loc.startsWith('/a/delivery')) {
      idx = 1;
    } else if (loc.startsWith('/a/expenses'))  idx = 2;
    else if (loc.startsWith('/a/shift'))     idx = 3;

    if (isSubScreen) return Scaffold(body: child);

    return Scaffold(
      extendBody: true,
      body:       child,
      bottomNavigationBar: _GlassAgentNav(currentIndex: idx, onTap: (i) {
        const routes = [R.agentHome, R.agentDeliveries, R.agentExpenses];
        if (i < routes.length) { context.go(routes[i]); return; }
        context.go(R.shiftOpen);
      }),
    );
  }
}

class _GlassAgentNav extends StatelessWidget {
  const _GlassAgentNav({required this.currentIndex, required this.onTap});
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _items = [
    (icon: Icons.home_outlined,         active: Icons.home_rounded,         label: 'HOME'),
    (icon: Icons.local_shipping_outlined,active: Icons.local_shipping_rounded,label: 'DELIVERIES'),
    (icon: Icons.receipt_outlined,       active: Icons.receipt_rounded,       label: 'EXPENSES'),
    (icon: Icons.schedule_outlined,      active: Icons.schedule_rounded,      label: 'SHIFT'),
  ];

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Container(
        decoration: BoxDecoration(
          color:  Colors.white.withValues(alpha: 0.88),
          border: Border(top: BorderSide(color: kBorderLight.withValues(alpha: 0.5))),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        child: SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_items.length, (i) {
              final item   = _items[i];
              final active = i == currentIndex;
              return GestureDetector(
                onTap:    () => onTap(i),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color:        active ? kGoldBg : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        active ? item.active : item.icon,
                        size:  22,
                        color: active ? kWarning : kTextHint,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(item.label,
                        style: TextStyle(
                            fontSize: 9, fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: active ? kWarning : kTextHint)),
                  ]),
                ),
              );
            }),
          ),
        ),
      ),
    ),
  );
}