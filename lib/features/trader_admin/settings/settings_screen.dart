import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/responsive_layout.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Widget _buildScaffold(BuildContext context, WidgetRef ref) {
    final user = ref.watch(appUserProvider).valueOrNull;

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: const Text('More'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [

          // ── Profile card — navy gradient ───────────────────────────────
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [kNavy, kNavyMid],
                begin:  Alignment.topLeft,
                end:    Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(kRadiusHero),
            ),
            padding: const EdgeInsets.all(22),
            child: Row(children: [
              // Avatar with gold ring
              Container(
                width: 58, height: 58,
                decoration: BoxDecoration(
                  shape:  BoxShape.circle,
                  border: Border.all(color: kGoldLight, width: 2),
                ),
                padding: const EdgeInsets.all(2),
                child: CircleAvatar(
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  child: Text(
                    _initials(user?.companyName),
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w900,
                        color: kGoldLight),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user?.companyName ?? 'Rooster Trader',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w900,
                            color: Colors.white)),
                    const SizedBox(height: 2),
                    Text(user?.role.label ?? '—',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFFB4C6F4),
                            fontWeight: FontWeight.w600)),
                  ])),
            ]),
          ),

          // ── Company code card ─────────────────────────────────────────
          if (user?.companyCode != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color:        kSurface,
                borderRadius: BorderRadius.circular(kRadiusCard),
                border:       Border.all(color: kBorderLight),
                boxShadow:    kCardShadow,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color:        kNavy.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(kRadiusChip),
                  ),
                  child: const Icon(Icons.qr_code_rounded,
                      color: kNavy, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Company Code',
                          style: TextStyle(fontSize: 11, color: kTextHint,
                              fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                      Text(user!.companyCode!,
                          style: const TextStyle(fontSize: 24,
                              fontWeight: FontWeight.w900, color: kNavy,
                              letterSpacing: 3)),
                    ])),
                const Text('Share with agents',
                    style: TextStyle(fontSize: 10, color: kTextHint)),
              ]),
            ),

          // ── OPERATIONS section ─────────────────────────────────────────
          _sectionLabel('OPERATIONS'),
          _menuCard(context, [
            _item(context, Icons.analytics_outlined,         'Analytics',            R.analytics),
            _item(context, Icons.summarize_outlined,         'Reports & Analytics',  R.reportsHub),
            _item(context, Icons.shopping_cart_outlined,     'Purchase Management',  R.purchase),
            _item(context, Icons.receipt_long_outlined,      'Daily Report',         R.dailyReport),
            _item(context, Icons.calendar_month_outlined,    'Daily Stock Snapshots',R.dailyStock),
            _item(context, Icons.account_balance_outlined,   'Cash Reconciliation',  R.cashRecon),
            _item(context, Icons.lock_clock_outlined,        'Day Closure',          R.dayClosure),
          ]),

          const SizedBox(height: 12),
          _sectionLabel('CATALOGUE'),
          _menuCard(context, [
            _item(context, Icons.store_outlined,             'Retailers',            R.retailers),
            _item(context, Icons.delivery_dining_outlined,   'Delivery Agents',      R.agents),
            _item(context, Icons.manage_accounts_outlined,   'User Management',      R.userMgmt),
            _item(context, Icons.price_change_outlined,      'Rates',                R.rates),
            _item(context, Icons.rule_outlined,              'Pricing Rules',        R.pricing),
            _item(context, Icons.receipt_long_outlined,       'Expense Rules',        R.expenseRules),
          ]),

          const SizedBox(height: 12),
          _sectionLabel('INVENTORY'),
          _menuCard(context, [
            _item(context, Icons.inventory_outlined,         'Stock',                R.stock),
            _item(context, Icons.inventory_2_outlined,       'Crates',               R.crates),
            _item(context, Icons.assignment_return_outlined, 'Returns',              R.returns),
          ]),

          const SizedBox(height: 12),
          _sectionLabel('REPORTS'),
          _menuCard(context, [
            _item(context, Icons.receipt_long_outlined,          'Invoices', R.invoices),
            _item(context, Icons.account_balance_wallet_outlined,'Ledger',   R.ledger),
            _item(context, Icons.schedule_outlined,              'Shifts',   R.shifts),
            _item(context, Icons.warning_amber_outlined,         'Alerts',   R.alerts),
          ]),

          const SizedBox(height: 24),

          // ── Sign out ──────────────────────────────────────────────────
          InkWell(
            onTap: () async {
              final ok = await confirmDialog(context,
                  title:   'Sign Out',
                  message: 'Sign out of Rooster Trader?');
              if (ok && context.mounted)
                ref.read(appUserProvider.notifier).signOut();
            },
            borderRadius: BorderRadius.circular(kRadiusCard),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color:        kSurface,
                borderRadius: BorderRadius.circular(kRadiusCard),
                border:       Border.all(color: kError.withValues(alpha: 0.3)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout_rounded, color: kError, size: 20),
                  SizedBox(width: 10),
                  Text('Sign Out',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                          color: kError)),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
          const Center(
            child: Text('Rooster Trader PTOS v2.0',
                style: TextStyle(fontSize: 11, color: kTextHint)),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(label,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900,
            color: kTextHint, letterSpacing: 0.8)),
  );

  Widget _menuCard(BuildContext context, List<Widget> items) => Container(
    margin:  const EdgeInsets.only(bottom: 4),
    decoration: BoxDecoration(
      color:        kSurface,
      borderRadius: BorderRadius.circular(kRadiusCard),
      border:       Border.all(color: kBorderLight),
      boxShadow:    kCardShadow,
    ),
    child: Column(children: items),
  );

  Widget _item(BuildContext ctx, IconData icon, String label, String route) {
    final isLast = false; // divider handled by container
    return InkWell(
      onTap:        () => ctx.go(route),
      borderRadius: BorderRadius.circular(kRadiusCard),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color:        kNavy.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(kRadiusInner),
            ),
            child: Icon(icon, size: 18, color: kNavy),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                  color: kTextMain))),
          const Icon(Icons.chevron_right_rounded, size: 18, color: kTextHint),
        ]),
      ),
    );
  }

  String _initials(String? name) {
    if (name == null || name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    return parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : name[0].toUpperCase();
  }
  @override
  Widget build(BuildContext context, WidgetRef ref) => ResponsiveLayout(
    mobile:  (_) => _buildScaffold(context, ref),
    desktop: (_) => _buildScaffold(context, ref),
  );

}