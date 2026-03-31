import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class AgentsScreen extends ConsumerStatefulWidget {
  const AgentsScreen({super.key});
  @override ConsumerState<AgentsScreen> createState() => _S();
}
class _S extends ConsumerState<AgentsScreen> {
  final _c = Supabase.instance.client;
  List<Map<String,dynamic>> _agents = [];
  bool _loading = true;
  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    setState(() => _loading = true);
    try {
      // delivery_agents: id,trader_id,auth_user_id,name,phone,vehicle_no,vehicle_type,is_active
      final data = await _c.from('delivery_agents').select('id,name,phone,vehicle_no,vehicle_type,is_active,auth_user_id').eq('trader_id', tid).order('name');
      if (mounted) setState(() { _agents = List<Map<String,dynamic>>.from(data); _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final companyCode = ref.watch(appUserProvider).valueOrNull?.companyCode ?? '—';
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery Agents'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => context.go(R.agentCreate), icon: const Icon(Icons.person_add_outlined), label: const Text('Add Agent')),
      body: Column(children: [
        Container(margin: const EdgeInsets.fromLTRB(16, 12, 16, 0), padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: kPrimary.withOpacity(0.07), borderRadius: BorderRadius.circular(10), border: Border.all(color: kPrimary.withOpacity(0.2))),
          child: Row(children: [
            const Icon(Icons.qr_code, color: kPrimary, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Share Company Code with agents to link their account', style: TextStyle(fontSize: 11, color: kTextSub)),
              Text(companyCode, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: kPrimary, letterSpacing: 2)),
            ])),
          ])),
        Expanded(child: _loading ? const LoadingList() : _agents.isEmpty
            ? EmptyState(icon: Icons.delivery_dining_outlined, message: 'No agents yet', sub: 'Add agent, then share Company Code so they can link their app account', onAction: () => context.go(R.agentCreate), actionLabel: 'Add Agent')
            : RefreshIndicator(onRefresh: _load, child: ListView.separated(
                padding: const EdgeInsets.all(16), itemCount: _agents.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final a = _agents[i];
                  final linked = a['auth_user_id'] != null;
                  final active = a['is_active'] as bool? ?? true;
                  return InkWell(
                    onTap: () => context.go(R.agentDetailPath(a['id'])),
                    borderRadius: BorderRadius.circular(12),
                    child: WhiteCard(child: Row(children: [
                      Container(width: 44, height: 44, decoration: BoxDecoration(color: linked ? kPrimary.withOpacity(0.1) : Colors.grey.shade100, shape: BoxShape.circle),
                          child: Icon(linked ? Icons.delivery_dining : Icons.person_add_outlined, color: linked ? kPrimary : Colors.grey.shade400, size: 22)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(a['name'] as String, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          if (!active) ...[const SizedBox(width: 6), const StatusBadge('inactive', Colors.grey, small: true)],
                          if (!linked) ...[const SizedBox(width: 6), const StatusBadge('not linked', Colors.orange, small: true)],
                        ]),
                        Text([a['phone'], a['vehicle_no']].where((v) => v != null).join(' · '), style: const TextStyle(fontSize: 12, color: kTextSub)),
                        if (!linked) const Text('Agent needs to link account in app', style: TextStyle(fontSize: 10, color: Colors.orange)),
                      ])),
                      const Icon(Icons.chevron_right, color: kTextHint, size: 18),
                    ])),
                  );
                }))),
      ]),
    );
  }
}
