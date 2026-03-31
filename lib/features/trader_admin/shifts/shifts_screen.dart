import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class ShiftsScreen extends ConsumerStatefulWidget {
  const ShiftsScreen({super.key});
  @override ConsumerState<ShiftsScreen> createState() => _S();
}
class _S extends ConsumerState<ShiftsScreen> {
  final _c = Supabase.instance.client;
  List<Map<String,dynamic>> _shifts = [];
  bool _loading = true;
  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    setState(() => _loading = true);
    try {
      // delivery_shifts: id,status,shift_start_at,total_cash_collected,total_orders,total_birds_delivered
      final data = await _c.from('delivery_shifts')
          .select('id,status,shift_start_at,total_cash_collected,total_orders,delivery_agents(name)')
          .eq('trader_id', tid).order('shift_start_at', ascending: false).limit(100);
      if (mounted) setState(() { _shifts = List<Map<String,dynamic>>.from(data); _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Delivery Shifts'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
    body: _loading ? const LoadingList() : _shifts.isEmpty ? const EmptyState(icon: Icons.schedule_outlined, message: 'No shifts yet')
        : RefreshIndicator(onRefresh: _load, child: ListView.separated(
            padding: const EdgeInsets.all(16), itemCount: _shifts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final s = _shifts[i];
              final a = s['delivery_agents'] as Map<String,dynamic>?;
              final status = s['status'] as String? ?? 'open';
              final date = DateTime.tryParse(s['shift_start_at'] as String? ?? '');
              return InkWell(
                onTap: () => context.go(R.shiftDetailPath(s['id'])),
                borderRadius: BorderRadius.circular(12),
                child: WhiteCard(child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a?['name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    if (date != null) Text(DateFormat('d MMM y, h:mm a').format(date), style: const TextStyle(fontSize: 11, color: kTextHint)),
                    Text('${s['total_orders'] ?? 0} orders · ${Fmt.amount((s['total_cash_collected'] as num?)?.toDouble() ?? 0)} collected', style: const TextStyle(fontSize: 11, color: kTextSub)),
                  ])),
                  StatusBadge(status, SC.shift(status)),
                  const SizedBox(width: 4), const Icon(Icons.chevron_right, color: kTextHint, size: 18),
                ])),
              );
            })),
  );
}
