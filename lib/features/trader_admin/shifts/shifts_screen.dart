import 'package:flutter/material.dart';
import '../../../core/router/app_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';

final _shiftsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, traderId) async {
  if (traderId.isEmpty) return <Map<String, dynamic>>[];
  return List<Map<String, dynamic>>.from(
    await Supabase.instance.client.from('delivery_shifts')
        .select('*, delivery_agents(id,name,phone)')
        .eq('trader_id', traderId)
        .order('shift_start_at', ascending: false)
        .limit(50),
  );
});

class ShiftsScreen extends ConsumerWidget {
  const ShiftsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(appUserProvider);
    if (userAsync.isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final traderId = userAsync.valueOrNull?.traderId ?? '';
    final async = traderId.isNotEmpty
        ? ref.watch(_shiftsProvider(traderId))
        : const AsyncValue<List<Map<String, dynamic>>>.data([]);

    return Scaffold(
      appBar: AppBar(title: const Text('Agent Shifts')),
      body: async.when(
        loading: () => const LoadingList(),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (shifts) {
          if (shifts.isEmpty) {
            return const EmptyState(icon: Icons.schedule_outlined, message: 'No shifts yet');
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(_shiftsProvider(traderId).future),
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: shifts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final s      = shifts[i];
                final agent  = s['delivery_agents'] as Map<String, dynamic>?;
                final status = s['status'] as String? ?? 'open';
                final approval = s['shift_approval_status'] as String? ?? 'pending';
                final start  = DateTime.tryParse(s['shift_start_at'] as String? ?? '') ?? DateTime.now();
                final totalOrders = s['total_orders'] as int? ?? 0;
                final totalWt     = (s['total_weight_kg'] as num?)?.toDouble() ?? 0;

                return InkWell(
                  onTap: () => context.go(Routes.shiftDetailPath(s['id'] as String)),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: const Border.fromBorderSide(BorderSide(color: Color(0xFFEEEEEE))),
                    ),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(agent?['name'] as String? ?? 'Unknown',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        Text(DateFormat('d MMM y, HH:mm').format(start),
                            style: const TextStyle(fontSize: 12, color: Color(0xFF9E9E9E))),
                        if (status == 'closed')
                          Text('$totalOrders orders · ${totalWt.toStringAsFixed(1)} kg',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF757575))),
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        StatusBadge(status, StatusColors.shift(status)),
                        if (status == 'closed' && approval == 'pending')
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: StatusBadge('Needs Review', Colors.orange),
                          ),
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
