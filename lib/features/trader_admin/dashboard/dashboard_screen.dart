import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import 'dashboard_provider.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(appUserProvider).valueOrNull;
    final traderId = user?.traderId;
    final dashAsync = traderId != null
        ? ref.watch(dashboardSummaryProvider(traderId))
        : const AsyncValue<Map<String, dynamic>>.loading();

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user?.companyName ?? 'Rooster Trader'),
            Text(DateFormat('EEEE, d MMM').format(DateTime.now()),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400,
                    color: Colors.grey)),
          ],
        ),
        actions: [
          if (user?.canApprove == true)
            dashAsync.when(
              data: (d) {
                final count = (d['pending_approvals'] as num?)?.toInt() ?? 0;
                return count > 0
                    ? Badge(label: Text('$count'),
                        child: IconButton(
                          icon: const Icon(Icons.approval_outlined),
                          onPressed: () => context.go(Routes.approvals),
                        ))
                    : const SizedBox.shrink();
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.go(Routes.settings),
          ),
        ],
      ),
      body: dashAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (d) => RefreshIndicator(
          onRefresh: () => ref.refresh(
              dashboardSummaryProvider(traderId!).future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SectionLabel('Today\'s Overview'),
              const SizedBox(height: 10),
              _StatsGrid([
                _StatCard('Orders', '${d['today_orders'] ?? 0}', Icons.shopping_cart_outlined, Colors.blue),
                _StatCard('Delivered', '${d['today_delivered'] ?? 0}', Icons.check_circle_outline, Colors.green),
                _StatCard('Revenue', '₹${_fmt(d['today_revenue'])}', Icons.currency_rupee, AppTheme.primary),
                _StatCard('Mortality', '${d['today_mortality'] ?? 0}', Icons.warning_amber_outlined, Colors.red),
              ]),
              const SizedBox(height: 20),
              _SectionLabel('Quick Actions'),
              const SizedBox(height: 10),
              _QuickActions(user: user),
              const SizedBox(height: 20),
              _SectionLabel('Business Health'),
              const SizedBox(height: 10),
              _StatsGrid([
                _StatCard('Outstanding', '₹${_fmt(d['total_outstanding'])}', Icons.account_balance_wallet_outlined, Colors.orange),
                _StatCard('Active Agents', '${d['active_agents'] ?? 0}', Icons.person_outlined, Colors.purple),
                _StatCard('Online Now', '${d['online_agents'] ?? 0}', Icons.circle, Colors.green),
                _StatCard('Retailers', '${d['total_retailers'] ?? 0}', Icons.store_outlined, Colors.teal),
              ]),
              if ((d['pending_approvals'] as num?)?.toInt() != 0) ...[
                const SizedBox(height: 20),
                _AlertBanner(
                  icon: Icons.pending_actions,
                  message: '${d['pending_approvals']} deliveries pending approval',
                  color: Colors.orange,
                  onTap: () => context.go(Routes.approvals),
                ),
              ],
              if ((d['pending_retailers'] as num?)?.toInt() != 0) ...[
                const SizedBox(height: 8),
                _AlertBanner(
                  icon: Icons.store_outlined,
                  message: '${d['pending_retailers']} retailers waiting for approval',
                  color: Colors.blue,
                  onTap: () => context.go(Routes.retailers),
                ),
              ],
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(dynamic v) {
    if (v == null) return '0';
    final n = (v as num).toDouble();
    if (n >= 100000) return '${(n / 100000).toStringAsFixed(1)}L';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toStringAsFixed(0);
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
          color: Colors.grey));
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid(this.cards);
  final List<_StatCard> cards;
  @override
  Widget build(BuildContext context) => GridView.count(
    crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
    crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.6,
    children: cards,
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.label, this.value, this.icon, this.color);
  final String label, value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade100),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 22),
      const Spacer(),
      Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
    ]),
  );
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({this.user});
  final dynamic user;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8, runSpacing: 8,
    children: [
      _ActionChip('New Order', Icons.add_shopping_cart, () => context.go(Routes.orderCreate)),
      _ActionChip('Dispatch', Icons.local_shipping_outlined, () => context.go(Routes.dispatch)),
      _ActionChip('Approvals', Icons.approval_outlined, () => context.go(Routes.approvals)),
      _ActionChip('Ledger', Icons.account_balance_wallet_outlined, () => context.go(Routes.ledger)),
      _ActionChip('Set Rate', Icons.price_change_outlined, () => context.go(Routes.rates)),
      _ActionChip('Retailers', Icons.store_outlined, () => context.go(Routes.retailers)),
    ],
  );
}

class _ActionChip extends StatelessWidget {
  const _ActionChip(this.label, this.icon, this.onTap);
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(20),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: AppTheme.primary),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 13,
            fontWeight: FontWeight.w500, color: AppTheme.primary)),
      ]),
    ),
  );
}

class _AlertBanner extends StatelessWidget {
  const _AlertBanner({required this.icon, required this.message,
      required this.color, required this.onTap});
  final IconData icon;
  final String message;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(message,
            style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w500))),
        Icon(Icons.chevron_right, color: color),
      ]),
    ),
  );
}
