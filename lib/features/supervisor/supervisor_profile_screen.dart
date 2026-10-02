import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';

class SupervisorProfileScreen extends ConsumerWidget {
  const SupervisorProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(appUserProvider).valueOrNull;
    final email = ref.watch(supabaseProvider).auth.currentUser?.email ?? '—';

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(backgroundColor: kSurface, title: const Text('Profile')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: kBorderLight), boxShadow: kCardShadow),
          child: Column(children: [
            CircleAvatar(radius: 32, backgroundColor: kNavy.withValues(alpha: 0.1),
                child: const Icon(Icons.person, size: 32, color: kNavy)),
            const SizedBox(height: 12),
            Text(user?.companyName ?? 'Supervisor', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            const Text('Supervisor / Collection Agent', style: TextStyle(fontSize: 12, color: kTextSub)),
          ]),
        ),
        const SizedBox(height: 16),
        WhiteCard(child: Column(children: [
          _row('Email', email),
          const Divider(height: 20),
          _row('Company', user?.companyName ?? '—'),
        ])),
        const SizedBox(height: 24),
        SizedBox(height: 52, child: OutlinedButton.icon(
          onPressed: () async {
            final ok = await confirmDialog(context, title: 'Sign Out', message: 'Sign out of your supervisor account?', confirmText: 'Sign Out');
            if (ok) {
              await ref.read(appUserProvider.notifier).signOut();
              if (context.mounted) context.go(R.login);
            }
          },
          icon: const Icon(Icons.logout, size: 18, color: kError),
          label: const Text('Sign Out', style: TextStyle(color: kError, fontWeight: FontWeight.w700)),
          style: OutlinedButton.styleFrom(side: const BorderSide(color: kError)),
        )),
      ]),
    );
  }

  Widget _row(String label, String value) => Row(children: [
    Text(label, style: const TextStyle(fontSize: 13, color: kTextSub)),
    const Spacer(),
    Flexible(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700), textAlign: TextAlign.right)),
  ]);
}