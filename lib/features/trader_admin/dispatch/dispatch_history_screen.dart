import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DISPATCH HISTORY — Completed / Cancelled batches.
//
// Moved out of the primary Dispatch screen (now just Pending/Live, per the
// approved Area-based workflow) into its own secondary screen so this
// capability isn't lost. Uses the same rolling-window + "Load More" pattern
// as before to avoid loading years of history at once.
// ─────────────────────────────────────────────────────────────────────────────

class DispatchHistoryScreen extends ConsumerStatefulWidget {
  const DispatchHistoryScreen({super.key});
  @override
  ConsumerState<DispatchHistoryScreen> createState() => _S();
}

class _S extends ConsumerState<DispatchHistoryScreen> with SingleTickerProviderStateMixin {
  final _c = Supabase.instance.client;
  late TabController _tab;
  bool _loading = true;
  int _daysBack = 14;
  List<Map<String, dynamic>> _all = [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    if (mounted) setState(() => _loading = true);
    try {
      final cutoff = DateTime.now().subtract(Duration(days: _daysBack)).toIso8601String().split('T')[0];
      final data = await _c.from('delivery_batches')
          .select('id,status,total_birds,total_weight,created_at,vehicle_no,'
              'delivery_agents(id,name,vehicle_no),'
              'deliveries(id,status)')
          .eq('trader_id', tid)
          .inFilter('status', ['completed', 'cancelled'])
          .gte('created_at', cutoff)
          .order('created_at', ascending: false)
          .limit(300);
      if (mounted) {
        setState(() {
          _all = List<Map<String, dynamic>>.from(data as List? ?? []);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final completed = _all.where((b) => b['status'] == 'completed').toList();
    final cancelled = _all.where((b) => b['status'] == 'cancelled').toList();
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: const Text('Dispatch History'),
        bottom: TabBar(controller: _tab, tabs: [
          Tab(text: 'Completed (${completed.length})'),
          Tab(text: 'Cancelled (${cancelled.length})'),
        ], labelColor: kPrimary, unselectedLabelColor: kTextHint, indicatorColor: kPrimary),
      ),
      body: _loading
          ? const LoadingList()
          : TabBarView(controller: _tab, children: [
              _list(completed, 'No completed batches in last $_daysBack days'),
              _list(cancelled, 'No cancelled batches in last $_daysBack days'),
            ]),
    );
  }

  Widget _list(List<Map<String, dynamic>> list, String emptyMsg) {
    if (list.isEmpty) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        EmptyState(icon: Icons.check_circle_outline, message: emptyMsg),
      ]);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: list.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          if (i == list.length) {
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: OutlinedButton.icon(
                onPressed: () { setState(() => _daysBack += 14); _load(); },
                icon: const Icon(Icons.expand_more, size: 18),
                label: Text('Load Earlier — showing last $_daysBack days', style: const TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 44), foregroundColor: kPrimary),
              ),
            );
          }
          final b = list[i];
          final a = b['delivery_agents'] as Map<String, dynamic>?;
          final date = DateTime.tryParse(b['created_at'] as String? ?? '');
          final deliveries = (b['deliveries'] as List? ?? []).where((d) => d['status'] != 'cancelled').length;
          return GestureDetector(
            onTap: () => context.push(R.batchDetailPath(b['id'])),
            child: WhiteCard(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a?['name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    Text('$deliveries orders · ${(b['total_birds'] ?? 0)} birds · '
                        '${((b['total_weight'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} kg',
                        style: const TextStyle(fontSize: 12, color: kTextSub)),
                  ]),
                ),
                if (date != null)
                  Text(DateFormat('d MMM').format(date.toLocal()),
                      style: const TextStyle(fontSize: 11, color: kTextHint)),
              ]),
            ),
          );
        },
      ),
    );
  }
}
