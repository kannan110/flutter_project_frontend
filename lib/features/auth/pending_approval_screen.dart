import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/session_provider.dart';
import '../../core/theme/app_theme.dart';

class PendingApprovalScreen extends ConsumerWidget {
  const PendingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user         = ref.watch(appUserProvider).valueOrNull;
    final isRejected   = user?.approvalStatus == 'rejected';
    final isEnterprise = user?.approvalStatus == 'enterprise_contact';

    return Scaffold(
      backgroundColor: kBgPage,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 52),

              // ── Brand ─────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [kNavy, kNavyMid],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(kRadiusHero),
                  boxShadow: [BoxShadow(
                      color: kNavy.withValues(alpha: 0.3),
                      blurRadius: 20, offset: const Offset(0, 6))],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      color:        Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(kRadiusChip),
                      border:       Border.all(color: kGoldLight.withValues(alpha: 0.4)),
                    ),
                    child: const Center(child: Text('🐓', style: TextStyle(fontSize: 28))),
                  ),
                  const SizedBox(width: 14),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('ROOSTER OS',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900,
                            color: kGoldLight, letterSpacing: 1.5)),
                    Text(user?.companyName ?? 'Smart Poultry Trading',
                        style: const TextStyle(fontSize: 12, color: Color(0xFFB4C6F4),
                            fontWeight: FontWeight.w600)),
                  ]),
                ]),
              ),

              const SizedBox(height: 36),

              // ── Status card ───────────────────────────────────────
              Container(
                width:      double.infinity,
                padding:    const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color:        kSurface,
                  borderRadius: BorderRadius.circular(kRadiusHero),
                  boxShadow:    kCardShadow,
                ),
                child: Column(children: [

                  // Icon
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      color: (isRejected ? kError
                          : isEnterprise ? Colors.purple
                          : Colors.orange).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isRejected   ? Icons.cancel_outlined
                          : isEnterprise ? Icons.business_center_outlined
                          : Icons.hourglass_top_rounded,
                      size:  40,
                      color: isRejected ? kError
                          : isEnterprise ? Colors.purple
                          : Colors.orange,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Title
                  Text(
                    isRejected   ? 'Registration Rejected'
                        : isEnterprise ? 'Enterprise Plan Needed'
                        : 'Waiting for Approval',
                    style: const TextStyle(fontSize: 22,
                        fontWeight: FontWeight.w900, color: kNavy),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),

                  // Message
                  Text(
                    isRejected
                        ? 'Your registration was not approved.\nPlease contact support for details.'
                        : isEnterprise
                        ? 'Your business needs our Enterprise plan.\nOur team will contact you shortly.'
                        : 'Your company is registered!\n\nOur team will review and activate\nyour account within 24 hours.\n\nYou will receive a call or message\nto confirm.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: kTextSub, height: 1.7),
                  ),

                  // Company code box (pending only)
                  if (!isRejected && !isEnterprise) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [kNavy, kNavyMid],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(kRadiusCard),
                      ),
                      child: Column(children: [
                        const Text('YOUR COMPANY CODE',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                                color: Color(0xFFB4C6F4), letterSpacing: 0.8)),
                        const SizedBox(height: 8),
                        Text(
                          user?.companyCode ?? '—',
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900,
                              color: kGoldLight, letterSpacing: 4),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Share this with your delivery agents\nso they can join your company',
                          style: TextStyle(fontSize: 11, color: Color(0xFFB4C6F4), height: 1.5),
                          textAlign: TextAlign.center,
                        ),
                      ]),
                    ),
                  ],

                  // Enterprise contact box
                  if (isEnterprise) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color:        Colors.purple.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(kRadiusCard),
                        border:       Border.all(color: Colors.purple.withValues(alpha: 0.2)),
                      ),
                      child: const Row(children: [
                        Icon(Icons.phone_outlined, color: Colors.purple, size: 20),
                        SizedBox(width: 12),
                        Expanded(child: Text(
                            'Our team will call you within 2 business days.',
                            style: TextStyle(color: Colors.purple, fontSize: 13,
                                fontWeight: FontWeight.w600))),
                      ]),
                    ),
                  ],
                ]),
              ),

              const SizedBox(height: 32),

              // ── Check status ──────────────────────────────────────
              OutlinedButton.icon(
                onPressed: () => ref.read(appUserProvider.notifier).reload(),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Check Status',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    side: const BorderSide(color: kNavy, width: 1.5)),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => ref.read(appUserProvider.notifier).signOut(),
                child: const Text('Sign Out',
                    style: TextStyle(color: kTextSub, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}