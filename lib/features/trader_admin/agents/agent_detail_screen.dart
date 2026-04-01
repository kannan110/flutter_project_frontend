import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class AgentDetailScreen extends ConsumerStatefulWidget {
  const AgentDetailScreen({super.key, required this.id});
  final String id;
  @override ConsumerState<AgentDetailScreen> createState() => _S();
}
class _S extends ConsumerState<AgentDetailScreen> {
  final _c = Supabase.instance.client;
  Map<String,dynamic>? _agent;
  Map<String,dynamic>? _summary;
  bool _loading = true;
  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final a = await _c.from('delivery_agents').select('*').eq('id', widget.id).maybeSingle();
    Map<String,dynamic>? s;
    try {
      final res = await _c.rpc('get_agent_summary', params: {'p_agent_id': widget.id});
      s = res != null ? Map<String,dynamic>.from(((res as Map?)?.cast<String,dynamic>()) ?? {}) : null;
    } catch (_) {}
    if (mounted) setState(() { _agent = a; _summary = s; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingList());
    if (_agent == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Not found')));
    final a = _agent!;
    final linked = a['auth_user_id'] != null;
    final active = a['is_active'] as bool? ?? true;

    return Scaffold(
      appBar: AppBar(title: Text(a['name'] as String), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(
            color: linked ? Colors.green.shade50 : Colors.orange.shade50, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: linked ? Colors.green.shade200 : Colors.orange.shade200)),
          child: Row(children: [
            Icon(linked ? Icons.check_circle : Icons.link_off, color: linked ? Colors.green.shade600 : Colors.orange.shade700, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(linked ? 'Account Linked' : 'Account Not Linked', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: linked ? Colors.green.shade700 : Colors.orange.shade800)),
              Text(linked ? 'Agent can log in with email & password' : 'Share Company Code so agent can link their account', style: TextStyle(fontSize: 11, color: linked ? Colors.green.shade600 : Colors.orange.shade700)),
            ])),
          ])),
        const SizedBox(height: 14),
        WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader('DETAILS'),
          InfoRow('Name', a['name'] as String),
          if (a['phone'] != null) InfoRow('Phone', a['phone'] as String),
          if (a['vehicle_no'] != null) InfoRow('Vehicle', a['vehicle_no'] as String),
          InfoRow('Type', (a['vehicle_type'] as String? ?? '').replaceAll('_', ' ').toUpperCase()),
          InfoRow('Status', active ? 'Active' : 'Inactive', valueColor: active ? kPrimary : Colors.red),
        ])),
        if (_summary != null) ...[const SizedBox(height: 12),
          WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionHeader('PERFORMANCE'),
            InfoRow('Total Deliveries', '${_summary!['total_deliveries'] ?? 0}'),
            InfoRow('Total Weight', Fmt.kg((_summary!['total_weight'] as num?)?.toDouble() ?? 0)),
            InfoRow('Total Collected', Fmt.amount((_summary!['total_collected'] as num?)?.toDouble() ?? 0)),
          ]))],
      ]),
    );
  }
}
