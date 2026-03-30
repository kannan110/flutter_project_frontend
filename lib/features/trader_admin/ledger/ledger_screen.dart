import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

// Outstanding per retailer
final _ledgerProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, traderId) async {
  if (traderId.isEmpty) return <Map<String, dynamic>>[];
  final retailers = List<Map<String, dynamic>>.from(
    await Supabase.instance.client.from('retailers').select('id,shop_name,owner_name,phone,credit_limit')
        .eq('trader_id', traderId).eq('is_active', true).order('shop_name'));
  final result = <Map<String, dynamic>>[];
  for (final r in retailers) {
    final outstanding = await Supabase.instance.client
        .rpc('get_retailer_outstanding', params: {'p_retailer_id': r['id']});
    result.add({...r, 'outstanding': (outstanding as num?)?.toDouble() ?? 0});
  }
  result.sort((a, b) => (b['outstanding'] as double).compareTo(a['outstanding'] as double));
  return result;
});

class LedgerScreen extends ConsumerWidget {
  const LedgerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(appUserProvider);
    if (userAsync.isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final traderId = userAsync.valueOrNull?.traderId ?? '';
    final async    = traderId.isNotEmpty ? ref.watch(_ledgerProvider(traderId)) : const AsyncValue<List<Map<String,dynamic>>>.data([]);

    return Scaffold(
      appBar: AppBar(title: const Text('Ledger')),
      body: async.when(
        loading: () => const LoadingList(),
        error:   (e, _) => Center(child: Text('Error: $e')),
        data:    (retailers) {
          final totalOutstanding = retailers.fold<double>(0, (s, r) => s + (r['outstanding'] as double));
          return Column(children: [
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Icon(Icons.account_balance_wallet_outlined, color: Colors.white, size: 28),
                const SizedBox(width: 14),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Total Outstanding', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  Text(AmountText.format(totalOutstanding),
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                ]),
              ]),
            ),
            Expanded(
              child: retailers.isEmpty
                  ? const EmptyState(icon: Icons.account_balance_wallet_outlined, message: 'No retailers yet')
                  : RefreshIndicator(
                      onRefresh: () => ref.refresh(_ledgerProvider(traderId).future),
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: retailers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final r = retailers[i];
                          final outstanding = r['outstanding'] as double;
                          final limit = (r['credit_limit'] as num?)?.toDouble() ?? 0;
                          final pct = limit > 0 ? (outstanding / limit).clamp(0.0, 1.0) : 0.0;
                          return InkWell(
                            onTap: () => context.go(Routes.retailerLedgerPath(r['id'] as String)),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white, borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: outstanding > limit * 0.9 ? Colors.red.shade200 : const Color(0xFFEEEEEE)),
                              ),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Expanded(child: Text(r['shop_name'] as String, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                                  Text(AmountText.format(outstanding),
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                                          color: outstanding > 0 ? Colors.orange.shade700 : Colors.green)),
                                ]),
                                if (r['owner_name'] != null) ...[
                                  const SizedBox(height: 2),
                                  Text(r['owner_name'] as String, style: const TextStyle(fontSize: 12, color: Color(0xFF9E9E9E))),
                                ],
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: pct, minHeight: 5,
                                    backgroundColor: Colors.grey.shade100,
                                    valueColor: AlwaysStoppedAnimation<Color>(pct > 0.9 ? Colors.red : pct > 0.7 ? Colors.orange : AppTheme.primary),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text('${(pct * 100).toStringAsFixed(0)}% of ₹${(limit/1000).toStringAsFixed(0)}K limit',
                                    style: const TextStyle(fontSize: 10, color: Color(0xFF9E9E9E))),
                              ]),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ]);
        },
      ),
    );
  }
}
