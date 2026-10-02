import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';

/// Reached only when a supervisor is authenticated and linked, but their
/// trader's Supervisor module has since been turned off. Router redirect
/// sends any /s/* access attempt here instead of the dashboard — this is
/// the visible half of "Supervisor login is blocked" when OFF; the
/// invisible half is link_supervisor_by_company_code refusing to link a
/// NEW supervisor at all while the flag is off.
class SupervisorDisabledScreen extends ConsumerWidget {
  const SupervisorDisabledScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: kBgPage,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.lock_outline_rounded, size: 56, color: kTextHint),
              const SizedBox(height: 16),
              const Text('Supervisor Module Not Enabled',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: kNavy)),
              const SizedBox(height: 8),
              const Text(
                  'Your trader account does not currently have the Supervisor / Collection Agent module enabled. Ask your trader to contact support.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: kTextSub, height: 1.5)),
              const SizedBox(height: 24),
              SizedBox(width: double.infinity, height: 48, child: OutlinedButton.icon(
                onPressed: () async {
                  await ref.read(appUserProvider.notifier).signOut();
                  if (context.mounted) context.go(R.login);
                },
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Sign Out'),
              )),
            ]),
          ),
        ),
      ),
    );
  }
}