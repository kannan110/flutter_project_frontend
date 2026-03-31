import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class AgentHomeScreen extends ConsumerStatefulWidget {
  const AgentHomeScreen({super.key});
  @override ConsumerState<AgentHomeScreen> createState() => _S();
}
class _S extends ConsumerState<AgentHomeScreen> {
  final _c = Supabase.instance.client;
  Map<String,dynamic>? _summary;
  Map<String,dynamic>? _activeShift;
  List<Map<String,dynamic>> _batches = [];
  bool _loading = true;
  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final user = ref.read(appUserProvider).valueOrNull;
    if (user?.agentId == null) {
      // FIX Bug #8: show error instead of silent blank screen
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final s = await _c.rpc('get_agent_summary', params: {'p_agent_id': user!.agentId});
      // delivery_shifts: status=open, no shift_date column — use shift_start_at
      final shift = await _c.from('delivery_shifts').select('*').eq('delivery_agent_id', user.agentId!).eq('status','open').maybeSingle();
      // delivery_batches: status not completed/cancelled
      final batches = await _c.from('delivery_batches')
          .select('id,status,total_orders,total_birds,deliveries(id,status,orders(retailers(shop_name)))')
          .eq('delivery_agent_id', user.agentId!).not('status','in','(completed,cancelled)').order('created_at', ascending: false);
      if (mounted) setState(() { _summary = s != null ? Map<String,dynamic>.from(s as Map) : null; _activeShift = shift; _batches = List<Map<String,dynamic>>.from(batches); _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(appUserProvider).valueOrNull;
    final hasShift = _activeShift != null;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Agent Dashboard', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          // FIX Bug #2: show agent's own name (agentName), not trader's company name
          Text('Hello, ${user?.agentName ?? user?.companyName ?? ''}!', style: const TextStyle(fontSize: 11, color: kTextSub, fontWeight: FontWeight.w400)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(icon: const Icon(Icons.logout_outlined), onPressed: () async {
            final ok = await confirmDialog(context, title: 'Sign Out', message: 'Sign out?');
            if (ok && context.mounted) ref.read(appUserProvider.notifier).signOut();
          }),
        ],
      ),
      body: _loading
          ? const LoadingList()
          // FIX Bug #8: show actionable error when agent profile not linked
          : (ref.watch(appUserProvider).valueOrNull?.agentId == null)
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.link_off, size: 56, color: Colors.orange),
                    const SizedBox(height: 16),
                    const Text('Agent Profile Not Linked', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    const Text('Your account is signed in but not linked to a delivery agent profile. Please contact your admin or re-link your account.', textAlign: TextAlign.center, style: TextStyle(color: kTextSub, fontSize: 13, height: 1.5)),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: () => context.go(R.agentLink),
                      icon: const Icon(Icons.link),
                      label: const Text('Link Agent Account'),
                    ),
                  ]),
                ))
              : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
        // Shift status
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(
            color: hasShift ? kPrimary.withOpacity(0.07) : Colors.orange.shade50, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: hasShift ? kPrimary.withOpacity(0.2) : Colors.orange.shade200)),
          child: Row(children: [
            Icon(hasShift ? Icons.play_circle_outline : Icons.warning_amber_outlined, color: hasShift ? kPrimary : Colors.orange.shade700, size: 24),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(hasShift ? 'Shift is Active' : 'No Active Shift', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: hasShift ? kPrimary : Colors.orange.shade800)),
              Text(hasShift ? 'Odometer: ${_activeShift!['odometer_start'] ?? '—'} km' : 'Open a shift before starting deliveries', style: TextStyle(fontSize: 11, color: hasShift ? kPrimary.withOpacity(0.7) : Colors.orange.shade700)),
            ])),
            if (!hasShift) ElevatedButton(onPressed: () => context.go(R.shiftOpen), style: ElevatedButton.styleFrom(minimumSize: const Size(0, 36), backgroundColor: Colors.orange), child: const Text('Open Shift', style: TextStyle(fontSize: 12))),
            if (hasShift) OutlinedButton(onPressed: () => context.go(R.shiftClose), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36), side: const BorderSide(color: kPrimary)), child: const Text('Close', style: TextStyle(fontSize: 12, color: kPrimary))),
          ])),
        const SizedBox(height: 16),
        if (_summary != null) ...[
          GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.5, children: [
            KpiCard('Today Deliveries', '${_summary!['today_deliveries'] ?? 0}', Icons.local_shipping_outlined, kPrimary),
            KpiCard('Cash Collected', Fmt.amount((_summary!['today_collected'] as num?)?.toDouble() ?? 0), Icons.currency_rupee, Colors.green),
            KpiCard('Pending', '${_summary!['pending_deliveries'] ?? 0}', Icons.pending_outlined, Colors.orange),
            KpiCard('Birds Today', '${_summary!['today_birds'] ?? 0}', Icons.countertops_outlined, Colors.blue),
          ]),
          const SizedBox(height: 16),
        ],
        if (_batches.isNotEmpty) ...[
          const SectionHeader('ACTIVE BATCHES'),
          ..._batches.map((b) {
            final deliveries = b['deliveries'] as List? ?? [];
            return Container(margin: const EdgeInsets.only(bottom: 10), child: WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [StatusBadge(b['status'] as String? ?? '—', SC.order(b['status'] as String? ?? ''), small: true), const Spacer(), Text('${b['total_orders'] ?? 0} orders · ${b['total_birds'] ?? 0} birds', style: const TextStyle(fontSize: 11, color: kTextSub))]),
              const SizedBox(height: 8),
              ...deliveries.take(3).map((d) {
                final o = d['orders'] as Map<String,dynamic>?; final r = o?['retailers'] as Map<String,dynamic>?;
                return Padding(padding: const EdgeInsets.only(bottom: 3), child: Row(children: [const Icon(Icons.store_outlined, size: 12, color: kTextHint), const SizedBox(width: 6), Expanded(child: Text(r?['shop_name'] as String? ?? '—', style: const TextStyle(fontSize: 12))), StatusBadge(d['status'] as String? ?? '—', SC.order(d['status'] as String? ?? ''), small: true)]));
              }),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: OutlinedButton(onPressed: () => context.go(R.batchPickupPath(b['id'])), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)), child: const Text('View Batch', style: TextStyle(fontSize: 12)))),
            ])));
          }),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: () => context.go(R.agentDeliveries), icon: const Icon(Icons.list_outlined, size: 18), label: const Text('All Deliveries')),
      ])),  // closes ListView children, ListView, RefreshIndicator (ternary branch)
    );
  }
}
