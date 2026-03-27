import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

final _agentsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, traderId) async {
  return List<Map<String, dynamic>>.from(
    await Supabase.instance.client.from('delivery_agents')
        .select('*').eq('trader_id', traderId).order('name'));
});

class AgentsScreen extends ConsumerWidget {
  const AgentsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final traderId = ref.watch(appUserProvider).valueOrNull?.traderId ?? '';
    final async    = traderId.isNotEmpty ? ref.watch(_agentsProvider(traderId)) : const AsyncValue<List<Map<String, dynamic>>>.data([]);
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery Agents')),
      body: async.when(
        loading: () => const LoadingList(),
        error:   (e, _) => Center(child: Text('Error: $e')),
        data:    (agents) {
          if (agents.isEmpty) return const EmptyState(icon: Icons.person_outlined, message: 'No agents yet', sub: 'Add agents to assign deliveries');
          return RefreshIndicator(
            onRefresh: () => ref.refresh(_agentsProvider(traderId).future),
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: agents.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final a = agents[i];
                final isOnline = a['is_online'] as bool? ?? false;
                return InkWell(
                  onTap: () => context.go('/agents/${a['id']}'),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                        border: const Border.fromBorderSide(BorderSide(color: Color(0xFFEEEEEE)))),
                    child: Row(children: [
                      Stack(children: [
                        CircleAvatar(backgroundColor: AppTheme.primary.withOpacity(0.1), radius: 22,
                            child: Text((a['name'] as String).substring(0,1).toUpperCase(),
                                style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700))),
                        if (isOnline) Positioned(right: 0, bottom: 0,
                            child: Container(width: 12, height: 12,
                                decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2)))),
                      ]),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(a['name'] as String, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        Text(a['phone'] as String? ?? '—', style: const TextStyle(fontSize: 12, color: Color(0xFF9E9E9E))),
                        if (a['vehicle_no'] != null)
                          Text(a['vehicle_no'] as String, style: const TextStyle(fontSize: 11, color: Color(0xFFBDBDBD))),
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        StatusBadge(isOnline ? 'Online' : 'Offline', isOnline ? Colors.green : Colors.grey),
                        const SizedBox(height: 4),
                        Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
                      ]),
                    ]),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go(Routes.agentCreate),
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.person_add_outlined, color: Colors.white),
        label: const Text('Add Agent', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
