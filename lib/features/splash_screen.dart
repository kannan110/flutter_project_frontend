import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/providers/session_provider.dart';
import '../core/router/app_router.dart';
import '../core/theme/app_theme.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(appUserProvider);

    return session.when(
      loading: () => _splash(),
      error: (e, st) {
        // Show error with retry — never loop silently
        return Scaffold(
          backgroundColor: kPrimary,
          body: Center(child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('🐓', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 20),
              const Text('Rooster Trader',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  const Icon(Icons.error_outline, color: Colors.white, size: 32),
                  const SizedBox(height: 10),
                  const Text('Login Error', style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(
                    e.toString()
                        .replaceAll('Exception: ', '')
                        .replaceAll('PostgrestException(message: ', '')
                        .replaceAll(')', ''),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)),
                ])),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
                onPressed: () async {
                  await ref.read(appUserProvider.notifier).reload();
                },
                icon: const Icon(Icons.refresh, color: kPrimary),
                label: const Text('Retry', style: TextStyle(color: kPrimary, fontWeight: FontWeight.w700))),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () async {
                  await ref.read(appUserProvider.notifier).signOut();
                  if (context.mounted) context.go(R.login);
                },
                child: const Text('Sign Out & Try Again',
                    style: TextStyle(color: Colors.white70, fontSize: 13))),
            ]))));
      },
      data: (user) {
        // Redirect on next frame
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          if (user == null) {
            context.go(R.login);
          } else if (user.isSuperAdmin) {
            context.go(R.superAdmin);
          } else if (user.isDeliveryAgent) {
            context.go(R.agentHome);
          } else if (user.isUnlinked) {
            context.go(R.traderSetup);
          } else {
            context.go(R.dashboard);
          }
        });
        return _splash();
      },
    );
  }

  Widget _splash() => Scaffold(
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
      const SizedBox(width: 24, height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white60)),
    ])));
}
