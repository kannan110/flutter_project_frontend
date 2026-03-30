import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class AgentHomeScreen extends ConsumerStatefulWidget {
  const AgentHomeScreen({super.key});
  @override
  ConsumerState<AgentHomeScreen> createState() => _AgentHomeScreenState();
}

class _AgentHomeScreenState extends ConsumerState<AgentHomeScreen> {
  final _client = Supabase.instance.client;
  Map<String, dynamic>? _openShift;
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _activeBatches = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final user = ref.read(appUserProvider).valueOrNull;
    final agentId = user?.agentId;
    if (agentId == null) { setState(() => _loading = false); return; }

    final shift = await _client.from('delivery_shifts')
        .select('*').eq('delivery_agent_id', agentId).eq('status', 'open').maybeSingle();
    final summary = await _client.rpc('get_agent_summary', params: {'p_agent_id': agentId});
    final batches = shift != null ? List<Map<String, dynamic>>.from(
      await _client.from('delivery_batches')
          .select('*, delivery_challans(dc_number)')
          .eq('delivery_agent_id', agentId)
          .inFilter('status', ['assigned', 'picked_up', 'out_for_delivery'])
          .order('created_at')) : <Map<String, dynamic>>[];

    if (mounted) setState(() {
      _openShift   = shift;
      _summary     = summary != null ? Map<String, dynamic>.from(summary as Map) : {};
      _activeBatches = batches;
      _loading     = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(appUserProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppTheme.bgGrey,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(user?.companyName ?? 'Rooster Trader', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const Text('Delivery Agent', style: TextStyle(fontSize: 11, color: Color(0xFF9E9E9E))),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                // Shift status banner
                _ShiftBanner(shift: _openShift, onAction: () {
                  context.go(_openShift == null ? Routes.agentShiftOpen : Routes.agentShiftClose);
                }),
                const SizedBox(height: 16),

                // Today stats
                if (_openShift != null) ...[
                  const SectionHeader("TODAY'S STATS"),
                  GridView.count(
                    crossAxisCount: 2, shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.6,
                    children: [
                      _StatTile('Assigned',  '${_summary?['today_assigned'] ?? 0}',   Icons.assignment_outlined,  Colors.blue),
                      _StatTile('Delivered', '${_summary?['today_delivered'] ?? 0}',  Icons.check_circle_outline, Colors.green),
                      _StatTile('Weight',    '${((_summary?['today_weight'] as num?)?.toDouble() ?? 0).toStringAsFixed(1)} kg', Icons.scale_outlined, AppTheme.primary),
                      _StatTile('Cash',      AmountText.format((_summary?['today_cash'] as num?)?.toDouble() ?? 0), Icons.currency_rupee, Colors.orange),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // Active batches
                if (_activeBatches.isNotEmpty) ...[
                  const SectionHeader('ACTIVE BATCHES'),
                  ..._activeBatches.map((b) => _BatchTile(b, onTap: () {
                    final status = b['status'] as String? ?? 'assigned';
                    if (status == 'assigned') {
                      context.go(Routes.agentBatchPickupPath(b['id'] as String));
                    } else {
                      context.go(Routes.agentDeliveries);
                    }
                  })),
                  const SizedBox(height: 16),
                ],

                // Quick actions
                if (_openShift != null) ...[
                  const SectionHeader('QUICK ACTIONS'),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _QuickAction(Icons.delivery_dining_outlined, 'My Deliveries', () => context.go(Routes.agentDeliveries)),
                    _QuickAction(Icons.receipt_outlined, 'Expenses', () => context.go(Routes.agentExpenses)),
                    _QuickAction(Icons.lock_clock_outlined, 'Close Shift', () => context.go(Routes.agentShiftClose)),
                  ]),
                ],
              ]),
            ),
    );
  }
}

class _ShiftBanner extends StatelessWidget {
  const _ShiftBanner({required this.shift, required this.onAction});
  final Map<String, dynamic>? shift;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final hasShift = shift != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasShift ? AppTheme.primary : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Icon(hasShift ? Icons.directions_bike_outlined : Icons.power_settings_new_outlined,
            color: hasShift ? Colors.white : Colors.grey, size: 32),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(hasShift ? 'Shift Active' : 'No Active Shift',
              style: TextStyle(color: hasShift ? Colors.white : Colors.grey.shade700, fontSize: 16, fontWeight: FontWeight.w700)),
          Text(hasShift ? 'Birds loaded: ${shift!['opening_bird_count']}' : 'Start your shift to begin deliveries',
              style: TextStyle(color: hasShift ? Colors.white70 : Colors.grey.shade500, fontSize: 12)),
        ])),
        ElevatedButton(
          onPressed: onAction,
          style: ElevatedButton.styleFrom(
            backgroundColor: hasShift ? Colors.white : AppTheme.primary,
            foregroundColor: hasShift ? AppTheme.primary : Colors.white,
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            elevation: 0,
          ),
          child: Text(hasShift ? 'Close' : 'Start', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ),
      ]),
    );
  }
}

class _BatchTile extends StatelessWidget {
  const _BatchTile(this.batch, {required this.onTap});
  final Map<String, dynamic> batch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = batch['status'] as String? ?? 'assigned';
    final challans = batch['delivery_challans'] as List? ?? [];
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.local_shipping_outlined, color: AppTheme.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${batch['total_orders']} orders · ${(batch['total_weight'] as num?)?.toStringAsFixed(1) ?? 0} kg',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            Text(
              status == 'assigned' ? 'Tap to record farm pickup' : 'In progress',
              style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)),
            ),
          ])),
          StatusBadge(status.replaceAll('_', ' '), StatusColors.order(status)),
        ]),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(this.label, this.value, this.icon, this.color);
  final String label, value; final IconData icon; final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: const Border.fromBorderSide(BorderSide(color: Color(0xFFEEEEEE)))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 20),
      const Spacer(),
      Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E))),
    ]),
  );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction(this.icon, this.label, this.onTap);
  final IconData icon; final String label; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(20),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.07), borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: AppTheme.primary),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primary)),
      ]),
    ),
  );
}
