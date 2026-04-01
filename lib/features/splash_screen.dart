import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/providers/session_provider.dart';
import '../core/router/app_router.dart';
import '../core/theme/app_theme.dart';

/// Splash screen — waits for session to resolve then auto-redirects.
/// Router already handles redirect logic; this just shows a clean splash
/// while appUserProvider is in loading state.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch session — when it resolves, router redirects automatically
    final session = ref.watch(appUserProvider);

    // If loaded, router will redirect; nothing to do here
    if (!session.isLoading) {
      // Trigger navigation on next frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final user = session.valueOrNull;
        if (context.mounted) {
          if (user == null) {
            context.go(R.login);
          } else if (user.isDeliveryAgent) {
            context.go(R.agentHome);
          } else {
            context.go(R.dashboard);
          }
        }
      });
    }

    return Scaffold(
      backgroundColor: kPrimary,
      body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 90, height: 90,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(24)),
          child: const Center(child: Text('🐓', style: TextStyle(fontSize: 48)))),
        const SizedBox(height: 20),
        const Text('Rooster Trader',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white)),
        const Text('Poultry Trading Platform',
            style: TextStyle(fontSize: 13, color: Colors.white60)),
        const SizedBox(height: 40),
        const SizedBox(
          width: 24, height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white60)),
      ])),
    );
  }
}
