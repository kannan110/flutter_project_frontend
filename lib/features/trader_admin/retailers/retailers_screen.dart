import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

final _retailersProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, traderId) async {
  if (traderId.isEmpty) return <Map<String, dynamic>>[];
  return List<Map<String, dynamic>>.from(
    await Supabase.instance.client.from('retailers')
        .select('*')
        .eq('trader_id', traderId)
        .order('shop_name'),
  );
});

class RetailersScreen extends ConsumerStatefulWidget {
  const RetailersScreen({super.key});
  @override
  ConsumerState<RetailersScreen> createState() => _RetailersScreenState();
}

class _RetailersScreenState extends ConsumerState<RetailersScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(appUserProvider);
    if (userAsync.isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final traderId = userAsync.valueOrNull?.traderId ?? '';
    final async    = traderId.isNotEmpty ? ref.watch(_retailersProvider(traderId)) : const AsyncValue<List<Map<String, dynamic>>>.data([]);

    return Scaffold(
      appBar: AppBar(title: const Text('Retailers')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search retailers…',
              prefixIcon: Icon(Icons.search, size: 20),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _search = v.toLowerCase()),
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const LoadingList(),
            error:   (e, _) => Center(child: Text('Error: $e')),
            data:    (all) {
              final list = _search.isEmpty
                  ? all
                  : all.where((r) =>
                      (r['shop_name'] as String).toLowerCase().contains(_search) ||
                      ((r['owner_name'] as String?) ?? '').toLowerCase().contains(_search) ||
                      ((r['phone'] as String?) ?? '').contains(_search)).toList();

              if (list.isEmpty) return const EmptyState(icon: Icons.store_outlined, message: 'No retailers found');

              return RefreshIndicator(
                onRefresh: () => ref.refresh(_retailersProvider(traderId).future),
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _RetailerCard(list[i]),
                ),
              );
            },
          ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go(Routes.retailerCreate),
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Retailer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _RetailerCard extends StatelessWidget {
  const _RetailerCard(this.retailer);
  final Map<String, dynamic> retailer;

  @override
  Widget build(BuildContext context) {
    final approval = retailer['approval_status'] as String? ?? 'approved';
    final isBlocked = retailer['is_blocked'] as bool? ?? false;
    return InkWell(
      onTap: () => context.go(Routes.retailerDetailPath(retailer['id'] as String)),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isBlocked ? Colors.red.shade200 : const Color(0xFFEEEEEE)),
        ),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                (retailer['shop_name'] as String).substring(0, 1).toUpperCase(),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.primary),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(retailer['shop_name'] as String,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            if (retailer['owner_name'] != null)
              Text(retailer['owner_name'] as String,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF757575))),
            if (retailer['phone'] != null)
              Text(retailer['phone'] as String,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF9E9E9E))),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (isBlocked)
              const StatusBadge('Blocked', Colors.red)
            else if (approval == 'pending')
              const StatusBadge('Pending', Colors.orange)
            else
              const StatusBadge('Active', Colors.green),
            const SizedBox(height: 4),
            Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 18),
          ]),
        ]),
      ),
    );
  }
}
