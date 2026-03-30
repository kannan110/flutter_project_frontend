import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

final _dashProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, traderId) async {
  if (traderId.isEmpty) { print('[Dashboard] traderId is empty - skipping'); return {}; }
  // ignore: avoid_print
  print('[Dashboard] loading for traderId=$traderId');
  try {
    final res = await Supabase.instance.client
        .rpc('dashboard_summary', params: {'p_trader_id': traderId});
    // ignore: avoid_print
    print('[Dashboard] success: $res');
    return Map<String, dynamic>.from(res as Map);
  } catch (e, st) {
    // ignore: avoid_print
    print('[Dashboard] ERROR: $e');
    // ignore: avoid_print
    print('[Dashboard] stack: $st');
    rethrow;
  }
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(appUserProvider);

    // While session is still loading, show spinner — don't fire any RPC with empty traderId
    if (userAsync.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final user     = userAsync.valueOrNull;
    final traderId = user?.traderId ?? '';
    final dashAsync = traderId.isNotEmpty
        ? ref.watch(_dashProvider(traderId))
        : const AsyncValue<Map<String, dynamic>>.data({});

    return Scaffold(
      backgroundColor: AppTheme.bgGrey,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(user?.companyName ?? 'Rooster Trader', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          Text(DateFormat('EEEE, d MMM y').format(DateTime.now()),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: Color(0xFF9E9E9E))),
        ]),
        actions: [
          dashAsync.when(
            data: (d) {
              final n = (d['pending_approvals'] as num?)?.toInt() ?? 0;
              if (n == 0) return const SizedBox.shrink();
              return Stack(alignment: Alignment.topRight, children: [
                IconButton(icon: const Icon(Icons.approval_outlined), onPressed: () => context.go(Routes.approvals)),
                Positioned(top: 8, right: 8, child: Container(
                  width: 16, height: 16,
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  child: Center(child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700))),
                )),
              ]);
            },
            loading: () => const SizedBox.shrink(),
            error:   (_, __) => const SizedBox.shrink(),
          ),
          IconButton(icon: const Icon(Icons.settings_outlined), onPressed: () => context.go(Routes.settings)),
        ],
      ),
      body: dashAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_outlined, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text('Could not load dashboard', style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          TextButton(onPressed: () => ref.refresh(_dashProvider(traderId)), child: const Text('Retry')),
        ])),
        data: (d) => RefreshIndicator(
          onRefresh: () => ref.refresh(_dashProvider(traderId).future),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [
            // Today KPI row
            const SectionHeader("TODAY'S OVERVIEW"),
            GridView.count(
              crossAxisCount: 2, shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.55,
              children: [
                _KpiCard('Orders', '${d['today_orders'] ?? 0}', Icons.shopping_cart_outlined, Colors.blue.shade600),
                _KpiCard('Delivered', '${d['today_delivered'] ?? 0}', Icons.check_circle_outline, Colors.green.shade600),
                _KpiCard('Revenue', _fmtAmt(d['today_revenue']), Icons.currency_rupee, AppTheme.primary),
                _KpiCard('Mortality', '${d['today_mortality'] ?? 0}', Icons.warning_amber_outlined, Colors.red.shade600),
              ],
            ),
            const SizedBox(height: 20),

            // Alerts
            if ((d['pending_approvals'] as num? ?? 0) > 0)
              _AlertTile(Icons.pending_actions, '${d['pending_approvals']} deliveries pending approval', Colors.orange, () => context.go(Routes.approvals)),
            if ((d['pending_retailers'] as num? ?? 0) > 0)
              _AlertTile(Icons.store_outlined, '${d['pending_retailers']} retailers awaiting approval', Colors.blue, () => context.go(Routes.retailers)),
            if ((d['active_batches'] as num? ?? 0) > 0)
              _AlertTile(Icons.local_shipping_outlined, '${d['active_batches']} batches out for delivery', Colors.purple, () => context.go(Routes.dispatch)),

            const SizedBox(height: 20),
            const SectionHeader('QUICK ACTIONS'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _ActionChip('New Order',  Icons.add_shopping_cart,           () => context.go(Routes.orderCreate)),
              _ActionChip('Dispatch',   Icons.local_shipping_outlined,     () => context.go(Routes.dispatch)),
              _ActionChip('Approvals',  Icons.approval_outlined,           () => context.go(Routes.approvals)),
              _ActionChip('Set Rates',  Icons.price_change_outlined,       () => context.go(Routes.rates)),
              _ActionChip('Retailers',  Icons.store_outlined,              () => context.go(Routes.retailers)),
              _ActionChip('Analytics',  Icons.bar_chart_outlined,          () => context.go(Routes.analytics)),
              _ActionChip('Agents',     Icons.person_outlined,             () => context.go(Routes.agents)),
              _ActionChip('Crates',     Icons.inventory_2_outlined,        () => context.go(Routes.crates)),
            ]),
            const SizedBox(height: 20),

            const SectionHeader('BUSINESS HEALTH'),
            GridView.count(
              crossAxisCount: 2, shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.55,
              children: [
                _KpiCard('Outstanding', _fmtAmt(d['total_outstanding']), Icons.account_balance_wallet_outlined, Colors.orange.shade600),
                _KpiCard('Active Agents', '${d['active_agents'] ?? 0}', Icons.people_outlined, Colors.purple.shade600),
                _KpiCard('Online Now', '${d['online_agents'] ?? 0}', Icons.circle, Colors.green.shade600),
                _KpiCard('Retailers', '${d['total_retailers'] ?? 0}', Icons.storefront_outlined, Colors.teal.shade600),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  String _fmtAmt(dynamic v) {
    if (v == null) return '₹0';
    final n = (v as num).toDouble();
    if (n >= 100000) return '₹${(n / 100000).toStringAsFixed(1)}L';
    if (n >= 1000) return '₹${(n / 1000).toStringAsFixed(1)}K';
    return '₹${n.toStringAsFixed(0)}';
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard(this.label, this.value, this.icon, this.color);
  final String label, value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: const Border.fromBorderSide(BorderSide(color: Color(0xFFEEEEEE))),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 22),
      const Spacer(),
      Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E))),
    ]),
  );
}

class _AlertTile extends StatelessWidget {
  const _AlertTile(this.icon, this.msg, this.color, this.onTap);
  final IconData icon; final String msg; final Color color; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(msg, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w500))),
          Icon(Icons.chevron_right, color: color, size: 18),
        ]),
      ),
    ),
  );
}

class _ActionChip extends StatelessWidget {
  const _ActionChip(this.label, this.icon, this.onTap);
  final String label; final IconData icon; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(20),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: AppTheme.primary),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primary)),
      ]),
    ),
  );
}
