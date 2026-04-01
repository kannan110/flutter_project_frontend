import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(appUserProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(padding: const EdgeInsets.all(16), margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Container(width: 52, height: 52, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle), child: const Center(child: Text('🐓', style: TextStyle(fontSize: 26)))),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(user?.companyName ?? 'Rooster Trader', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
              Text(user?.role.label ?? '—', style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ])),
          ])),
        if (user?.companyCode != null) Container(margin: const EdgeInsets.only(bottom: 14), child: WhiteCard(child: Row(children: [
          const Icon(Icons.qr_code, color: kPrimary, size: 22), const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Company Code — share with delivery agents', style: TextStyle(fontSize: 11, color: kTextHint)),
            Text(user!.companyCode!, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: kPrimary, letterSpacing: 2)),
          ])),
        ]))),
        _section(context, 'OPERATIONS', [
          _tile(context, Icons.analytics_outlined, 'Analytics', R.analytics),
          _tile(context, Icons.receipt_long_outlined, 'Daily Report', R.dailyReport),
          _tile(context, Icons.account_balance_outlined, 'Cash Reconciliation', R.cashRecon),
          _tile(context, Icons.lock_clock_outlined, 'Day Closure', R.dayClosure),
        ]),
        const SizedBox(height: 8),
        _section(context, 'CATALOGUE', [
          _tile(context, Icons.store_outlined, 'Retailers', R.retailers),
          _tile(context, Icons.delivery_dining_outlined, 'Delivery Agents', R.agents),
          _tile(context, Icons.price_change_outlined, 'Rates', R.rates),
          _tile(context, Icons.rule_outlined, 'Pricing Rules', R.pricing),
        ]),
        const SizedBox(height: 8),
        _section(context, 'INVENTORY', [
          _tile(context, Icons.inventory_outlined, 'Stock', R.stock),
          _tile(context, Icons.inventory_2_outlined, 'Crates', R.crates),
          _tile(context, Icons.assignment_return_outlined, 'Returns', R.returns),
        ]),
        const SizedBox(height: 8),
        _section(context, 'REPORTS', [
          _tile(context, Icons.receipt_long_outlined, 'Invoices', R.invoices),
          _tile(context, Icons.account_balance_wallet_outlined, 'Ledger', R.ledger),
          _tile(context, Icons.schedule_outlined, 'Shifts', R.shifts),
          _tile(context, Icons.warning_amber_outlined, 'Alerts', R.alerts),
        ]),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () async {
            final ok = await confirmDialog(context, title: 'Sign Out', message: 'Sign out of Rooster Trader?');
            if (ok && context.mounted) ref.read(appUserProvider.notifier).signOut();
          },
          icon: const Icon(Icons.logout, size: 18),
          label: const Text('Sign Out'),
          style: OutlinedButton.styleFrom(foregroundColor: kError, side: const BorderSide(color: kError)),
        ),
        const SizedBox(height: 16),
        const Center(child: Text('Rooster Trader PTOS v2.0', style: TextStyle(fontSize: 11, color: kTextHint))),
      ]),
    );
  }

  Widget _section(BuildContext ctx, String title, List<Widget> tiles) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    SectionHeader(title),
    Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: const Border.fromBorderSide(BorderSide(color: kBorder))), child: Column(children: tiles)),
  ]);

  Widget _tile(BuildContext ctx, IconData icon, String label, String route) => InkWell(
    onTap: () => ctx.go(route), borderRadius: BorderRadius.circular(12),
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13), child: Row(children: [
      Icon(icon, size: 20, color: kPrimary), const SizedBox(width: 14),
      Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
      const Icon(Icons.chevron_right, size: 18, color: kTextHint),
    ])));
}
