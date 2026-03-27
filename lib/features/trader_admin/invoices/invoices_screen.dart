import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';

final _invoicesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, traderId) async {
  return List<Map<String, dynamic>>.from(await Supabase.instance.client
      .from('invoices')
      .select('*, retailers(id,shop_name,owner_name)')
      .eq('trader_id', traderId)
      .order('invoice_date', ascending: false)
      .limit(100));
});

class InvoicesScreen extends ConsumerWidget {
  const InvoicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final traderId = ref.watch(appUserProvider).valueOrNull?.traderId ?? '';
    final async = traderId.isNotEmpty
        ? ref.watch(_invoicesProvider(traderId))
        : const AsyncValue<List<Map<String, dynamic>>>.data([]);
    return Scaffold(
      appBar: AppBar(title: const Text('Invoices')),
      body: async.when(
        loading: () => const LoadingList(),
        error: (e, _) => Center(child: Text('Error: \$e')),
        data: (invoices) {
          if (invoices.isEmpty)
            return const EmptyState(
                icon: Icons.receipt_long_outlined, message: 'No invoices yet');
          return RefreshIndicator(
            onRefresh: () => ref.refresh(_invoicesProvider(traderId).future),
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: invoices.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final inv = invoices[i];
                final retailer = inv['retailers'] as Map<String, dynamic>?;
                final status = inv['status'] as String? ?? 'draft';
                final amount = (inv['total_amount'] as num?)?.toDouble() ?? 0;
                final date =
                    DateTime.tryParse(inv['invoice_date'] as String? ?? '') ??
                        DateTime.now();
                return InkWell(
                  onTap: () => context.go('/invoices/${inv['id']}'),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: const Border.fromBorderSide(
                            BorderSide(color: Color(0xFFEEEEEE)))),
                    child: Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(inv['invoice_number'] as String? ?? '—',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primary)),
                            const SizedBox(height: 4),
                            Text(retailer?['shop_name'] as String? ?? '—',
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600)),
                            Text(DateFormat('d MMM y').format(date),
                                style: const TextStyle(
                                    fontSize: 11, color: Color(0xFF9E9E9E))),
                          ])),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(AmountText.format(amount),
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primary)),
                            const SizedBox(height: 4),
                            StatusBadge(status, StatusColors.approval(status)),
                          ]),
                    ]),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
