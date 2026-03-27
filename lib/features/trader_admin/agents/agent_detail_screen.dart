import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';

class AgentDetailScreen extends ConsumerStatefulWidget {
  const AgentDetailScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<AgentDetailScreen> createState() => _AgentDetailScreenState();
}

class _AgentDetailScreenState extends ConsumerState<AgentDetailScreen> {
  final _client = Supabase.instance.client;
  Map<String, dynamic>? _agent;
  Map<String, dynamic>? _summary;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final a = await _client.from('delivery_agents').select('*').eq('id', widget.id).maybeSingle();
    final s = await _client.rpc('get_agent_summary', params: {'p_agent_id': widget.id});
    if (mounted) setState(() {
      _agent   = a;
      _summary = s != null ? Map<String, dynamic>.from(s as Map) : {};
      _loading = false;
    });
  }

  Future<void> _toggleActive() async {
    final current = _agent!['is_active'] as bool? ?? true;
    await _client.from('delivery_agents').update({'is_active': !current}).eq('id', widget.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_agent == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Agent not found')));
    final isOnline = _agent!['is_online'] as bool? ?? false;
    final isActive = _agent!['is_active'] as bool? ?? true;
    final s = _summary ?? {};

    return Scaffold(
      appBar: AppBar(title: Text(_agent!['name'] as String), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Profile card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
              border: const Border.fromBorderSide(BorderSide(color: Color(0xFFEEEEEE)))),
          child: Row(children: [
            Stack(children: [
              CircleAvatar(radius: 30, backgroundColor: AppTheme.primary.withOpacity(0.1),
                  child: Text((_agent!['name'] as String).substring(0,1).toUpperCase(),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppTheme.primary))),
              if (isOnline) Positioned(right: 0, bottom: 0,
                  child: Container(width: 14, height: 14,
                      decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)))),
            ]),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_agent!['name'] as String, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              if (_agent!['phone'] != null) Text(_agent!['phone'] as String, style: const TextStyle(fontSize: 13, color: Color(0xFF9E9E9E))),
              if (_agent!['vehicle_no'] != null)
                Text('${_agent!['vehicle_type']?.toString().replaceAll('_', ' ') ?? ''} · ${_agent!['vehicle_no']}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFFBDBDBD))),
            ])),
            Column(children: [
              StatusBadge(isOnline ? 'Online' : 'Offline', isOnline ? Colors.green : Colors.grey),
              const SizedBox(height: 6),
              StatusBadge(isActive ? 'Active' : 'Inactive', isActive ? AppTheme.primary : Colors.red),
            ]),
          ]),
        ),
        const SizedBox(height: 16),

        // Today stats
        const SectionHeader("TODAY'S PERFORMANCE"),
        GridView.count(
          crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.7,
          children: [
            _StatCard('Assigned',  '${s['today_assigned'] ?? 0}',  Icons.assignment_outlined,       Colors.blue),
            _StatCard('Delivered', '${s['today_delivered'] ?? 0}', Icons.check_circle_outline,      Colors.green),
            _StatCard('Weight',    '${((s['today_weight'] as num?)?.toDouble() ?? 0).toStringAsFixed(1)} kg', Icons.scale_outlined, AppTheme.primary),
            _StatCard('Cash',      AmountText.format((s['today_cash'] as num?)?.toDouble() ?? 0), Icons.currency_rupee, Colors.orange),
          ],
        ),
        const SizedBox(height: 16),

        // Lifetime stats
        const SectionHeader('LIFETIME STATS'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
              border: const Border.fromBorderSide(BorderSide(color: Color(0xFFEEEEEE)))),
          child: Column(children: [
            InfoRow('Total Delivered',  '${s['total_delivered'] ?? 0} deliveries'),
            InfoRow('Total Weight',     '${((s['total_weight'] as num?)?.toDouble() ?? 0).toStringAsFixed(1)} kg'),
            InfoRow('Total Mortality',  '${s['total_mortality'] ?? 0} birds'),
          ]),
        ),
        const SizedBox(height: 20),

        // Toggle active
        OutlinedButton.icon(
          onPressed: _toggleActive,
          icon: Icon(isActive ? Icons.person_off_outlined : Icons.person_outlined),
          label: Text(isActive ? 'Deactivate Agent' : 'Activate Agent'),
          style: OutlinedButton.styleFrom(
            foregroundColor: isActive ? Colors.red : AppTheme.primary,
            side: BorderSide(color: isActive ? Colors.red : AppTheme.primary),
          ),
        ),
      ]),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.label, this.value, this.icon, this.color);
  final String label, value; final IconData icon; final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: const Border.fromBorderSide(BorderSide(color: Color(0xFFEEEEEE)))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 20),
      const Spacer(),
      Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E))),
    ]),
  );
}
