import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import 'collect_cash_sheet.dart';

class SupervisorDashboardScreen extends ConsumerStatefulWidget {
  const SupervisorDashboardScreen({super.key});
  @override ConsumerState<SupervisorDashboardScreen> createState() => _S();
}

class _S extends ConsumerState<SupervisorDashboardScreen> {
  final _c = Supabase.instance.client;
  bool _loading = true;
  double _collectedToday = 0;
  int _customersCollectedToday = 0;
  int _pendingRetailers = 0;
  int _assignedCount = 0;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final user = ref.read(appUserProvider).valueOrNull;
    final supId = user?.supervisorId;
    if (supId == null) { if (mounted) setState(() => _loading = false); return; }
    if (mounted) setState(() => _loading = true);
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      final retailers = await _c.from('retailers')
          .select('id,outstanding_balance')
          .eq('supervisor_id', supId).eq('is_active', true);
      final rlist = List<Map<String, dynamic>>.from(retailers as List? ?? []);
      final pending = rlist.where((r) => ((r['outstanding_balance'] as num?) ?? 0) > 0).length;

      final payments = await _c.from('ledger_entries')
          .select('amount,retailer_id')
          .eq('recorded_by', user!.userId)
          .eq('entry_type', 'credit')
          .eq('source_type', 'payment')
          .eq('entry_date', today);
      final plist = List<Map<String, dynamic>>.from(payments as List? ?? []);
      final total = plist.fold<double>(0, (s, p) => s + ((p['amount'] as num?)?.toDouble() ?? 0));
      final distinctRetailers = plist.map((p) => p['retailer_id']).toSet().length;

      if (mounted) {
        setState(() {
        _assignedCount = rlist.length;
        _pendingRetailers = pending;
        _collectedToday = total;
        _customersCollectedToday = distinctRetailers;
        _loading = false;
      });
      }
    } catch (e) {
      if (mounted) { setState(() => _loading = false); showError(context, e.toString()); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(appUserProvider).valueOrNull;

    return Scaffold(
      backgroundColor: kBgPage,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 110), children: [
            Text('Hi, ${user?.companyName ?? 'Supervisor'}',
                style: const TextStyle(fontSize: 13, color: kTextSub)),
            const Text('Today\'s Collection',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: kNavy)),
            const SizedBox(height: 16),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [kNavy, kNavyMid],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(kRadiusHero),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('TOTAL CASH COLLECTED TODAY',
                    style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                const SizedBox(height: 6),
                Text(Fmt.amount(_collectedToday),
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white)),
              ]),
            ),
            const SizedBox(height: 14),

            Row(children: [
              Expanded(child: _statCard('Customers Collected', '$_customersCollectedToday', Icons.people_outline, Colors.green.shade700)),
              const SizedBox(width: 12),
              Expanded(child: _statCard('Pending Retailers', '$_pendingRetailers', Icons.error_outline, Colors.orange.shade700)),
            ]),
            const SizedBox(height: 12),
            _statCard('Assigned Retailers', '$_assignedCount', Icons.storefront_outlined, kNavy, wide: true),
            const SizedBox(height: 24),

            SizedBox(height: 56, child: ElevatedButton.icon(
              onPressed: () async {
                final picked = await context.push<String>(R.supervisorRetailers, extra: {'pickMode': true});
                if (picked != null && context.mounted) {
                  await showCollectCashSheet(context, ref, retailerId: picked);
                  _load();
                }
              },
              icon: const Icon(Icons.payments_outlined, size: 22),
              label: const Text('Collect Cash', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
            )),
          ]),
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color, {bool wide = false}) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard),
          border: Border.all(color: kBorderLight), boxShadow: kCardShadow),
      child: wide
          ? Row(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 13, color: kTextSub, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
      ])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: kTextSub, fontWeight: FontWeight.w600)),
      ]));
}