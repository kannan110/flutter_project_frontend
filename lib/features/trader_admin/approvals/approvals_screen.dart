import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

final _approvalsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, traderId) async {
  return List<Map<String, dynamic>>.from(
    await Supabase.instance.client.from('deliveries')
        .select('*, orders(*, retailers(id,shop_name,owner_name,phone), master_products(id,name)), delivery_agents(id,name,phone)')
        .eq('trader_id', traderId).eq('status', 'delivered').eq('approval_status', 'pending')
        .order('delivered_at', ascending: false),
  );
});

class ApprovalsScreen extends ConsumerWidget {
  const ApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final traderId = ref.watch(appUserProvider).valueOrNull?.traderId ?? '';
    final async    = traderId.isNotEmpty ? ref.watch(_approvalsProvider(traderId)) : const AsyncValue<List<Map<String,dynamic>>>.data([]);

    return Scaffold(
      appBar: AppBar(title: const Text('Pending Approvals')),
      body: async.when(
        loading: () => const LoadingList(),
        error:   (e, _) => Center(child: Text('Error: $e')),
        data:    (items) {
          if (items.isEmpty) return const EmptyState(icon: Icons.approval_outlined, message: 'No pending approvals', sub: 'All deliveries have been processed');
          return RefreshIndicator(
            onRefresh: () => ref.refresh(_approvalsProvider(traderId).future),
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final d = items[i];
                final order    = d['orders'] as Map<String, dynamic>?;
                final retailer = order?['retailers'] as Map<String, dynamic>?;
                final agent    = d['delivery_agents'] as Map<String, dynamic>?;
                final weight   = (d['delivered_total_weight'] ?? d['received_total_weight'] as num?)?.toDouble() ?? 0;
                final date     = DateTime.tryParse(d['delivered_at'] as String? ?? '') ?? DateTime.now();
                return InkWell(
                  onTap: () => context.go('/approvals/${d['id']}'),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white, borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Icon(Icons.pending_actions, size: 16, color: Colors.orange),
                        const SizedBox(width: 6),
                        Expanded(child: Text(retailer?['shop_name'] ?? '—', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                        Text(DateFormat('d MMM').format(date), style: const TextStyle(fontSize: 12, color: Color(0xFF9E9E9E))),
                      ]),
                      const SizedBox(height: 6),
                      Row(children: [
                        Icon(Icons.person_outline, size: 13, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text('Agent: ${agent?['name'] ?? '—'}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        const SizedBox(width: 16),
                        Icon(Icons.scale_outlined, size: 13, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text('${weight.toStringAsFixed(2)} kg', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ]),
                      const SizedBox(height: 6),
                      const Text('Tap to review & approve', style: TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w500)),
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
