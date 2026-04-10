import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/providers/session_provider.dart';
import '../../core/theme/app_theme.dart';

/// Shown to traders whose account is pending super admin approval
class PendingApprovalScreen extends ConsumerWidget {
  const PendingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(appUserProvider).valueOrNull;
    final isRejected   = user?.approvalStatus == 'rejected';
    final isEnterprise = user?.approvalStatus == 'enterprise_contact';

    return Scaffold(
      backgroundColor: kBgGrey,
      body: SafeArea(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const SizedBox(height: 40),
          // Logo
          Container(width: 70, height: 70,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF1B6B3A), Color(0xFF2E8B57)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(18)),
            child: const Center(child: Text('🐓', style: TextStyle(fontSize: 34)))),
          const SizedBox(height: 16),
          Text(user?.companyName ?? 'Rooster Trader',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kPrimary)),
          const SizedBox(height: 32),

          // Status card
          Container(
            width: double.infinity, padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 16, offset: const Offset(0, 4))]),
            child: Column(children: [
              Icon(
                isRejected   ? Icons.cancel_outlined
                : isEnterprise ? Icons.business_center_outlined
                : Icons.hourglass_top_rounded,
                size: 56,
                color: isRejected ? Colors.red : isEnterprise ? Colors.purple : Colors.orange),
              const SizedBox(height: 16),
              Text(
                isRejected   ? 'Registration Rejected'
                : isEnterprise ? 'Enterprise Plan Needed'
                : 'Waiting for Approval',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Text(
                isRejected
                    ? 'Your registration was not approved.\nPlease contact support for details.'
                : isEnterprise
                    ? 'Your business needs our Enterprise plan.\nOur team will contact you shortly.'
                : 'Your company is registered!\n\nOur team will review and activate\nyour account within 24 hours.\n\nYou will receive a call or message\nto confirm.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: kTextSub, height: 1.6)),

              if (!isRejected && !isEnterprise) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green.shade200)),
                  child: Column(children: [
                    const Text('Your Company Code', style: TextStyle(fontSize: 11, color: kTextSub)),
                    const SizedBox(height: 4),
                    Text(user?.companyCode ?? '—',
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: kPrimary,
                            letterSpacing: 2)),
                    const SizedBox(height: 4),
                    const Text('Share this with your delivery agents so they can join your company',
                        style: TextStyle(fontSize: 11, color: kTextSub), textAlign: TextAlign.center),
                  ])),
              ],

              if (isEnterprise) ...[
                const SizedBox(height: 20),
                Container(padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    const Icon(Icons.phone_outlined, color: Colors.purple, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(child: Text('Our team will call you within 2 business days.',
                        style: TextStyle(color: Colors.purple, fontSize: 13))),
                  ])),
              ],
            ])),
          const Spacer(),

          // Check status button
          OutlinedButton.icon(
            onPressed: () => ref.read(appUserProvider.notifier).reload(),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Check Status', style: TextStyle(fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                side: const BorderSide(color: kPrimary))),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => ref.read(appUserProvider.notifier).signOut(),
            child: const Text('Sign Out', style: TextStyle(color: kTextSub))),
          const SizedBox(height: 8),
        ]))));
  }
}
