import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';

class SupervisorShell extends ConsumerWidget {
  const SupervisorShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = GoRouterState.of(context).matchedLocation;

    final isSubScreen = loc.startsWith('/s/ledger/') || loc.startsWith('/s/collect/');

    int idx = 0;
    if (loc.startsWith('/s/retailers'))       idx = 1;
    else if (loc.startsWith('/s/history'))    idx = 2;
    else if (loc.startsWith('/s/summary'))    idx = 3;
    else if (loc.startsWith('/s/profile'))    idx = 4;

    if (isSubScreen) return Scaffold(body: child);

    return Scaffold(
      extendBody: true,
      body: child,
      bottomNavigationBar: _SupervisorGlassNav(
        currentIndex: idx,
        onTap: (i) {
          const routes = [
            R.supervisorHome, R.supervisorRetailers, R.supervisorPaymentHistory,
            R.supervisorCollectionSummary, R.supervisorProfile,
          ];
          context.go(routes[i]);
        },
      ),
    );
  }
}

class _SupervisorGlassNav extends StatelessWidget {
  const _SupervisorGlassNav({required this.currentIndex, required this.onTap});
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    const items = [
      (icon: Icons.home_outlined,          active: Icons.home_rounded,          label: 'HOME'),
      (icon: Icons.storefront_outlined,    active: Icons.storefront_rounded,    label: 'RETAILERS'),
      (icon: Icons.history_outlined,       active: Icons.history_rounded,       label: 'HISTORY'),
      (icon: Icons.summarize_outlined,     active: Icons.summarize_rounded,     label: 'SUMMARY'),
      (icon: Icons.person_outline_rounded, active: Icons.person_rounded,        label: 'PROFILE'),
    ];

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(kRadiusHero)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            border: Border(top: BorderSide(color: kBorderLight.withValues(alpha: 0.5))),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: SafeArea(
            top: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(items.length, (i) {
                final item   = items[i];
                final active = i == currentIndex;
                return GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: active ? kGoldLight.withValues(alpha: 0.18) : Colors.transparent,
                          borderRadius: BorderRadius.circular(kRadiusChip),
                        ),
                        child: Icon(active ? item.active : item.icon,
                            size: 21, color: active ? kNavy : kTextHint),
                      ),
                      Text(item.label, style: TextStyle(
                          fontSize: 8.5, fontWeight: FontWeight.w900,
                          color: active ? kNavy : kTextHint, letterSpacing: 0.3)),
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
}