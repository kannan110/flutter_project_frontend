import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rooster_trader/features/trader_admin/agents/hub/entry_mode_selector.dart' show EntryModeSelector;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../../core/providers/session_provider.dart';
import '../../../../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TRADER REASSIGN SCREEN
//
// Allows the trader to reassign one or more pending deliveries to another agent.
// Two modes depending on delivery status:
//   • 'assigned' (pre-pickup) → calls change_batch_agent (moves whole batch)
//   • 'out_for_delivery' (in-transit) → calls reassign_delivery (single delivery)
//
// Full audit trail: delivery_assignment_history + operation_log written by RPCs.
// ─────────────────────────────────────────────────────────────────────────────

class TraderReassignScreen extends ConsumerStatefulWidget {
  const TraderReassignScreen({
    super.key,
    required this.agentId,
    required this.agentName,
    required this.pendingList,
  });

  final String agentId;
  final String agentName;
  final List<Map<String, dynamic>> pendingList;

  @override
  ConsumerState<TraderReassignScreen> createState() =>
      _TraderReassignScreenState();
}

class _TraderReassignScreenState
    extends ConsumerState<TraderReassignScreen> {
  final _c = Supabase.instance.client;
  final _reasonCtrl = TextEditingController();

  // Selected deliveries to reassign
  final Set<String> _selectedIds = {};

  // Target agent
  Map<String, dynamic>? _targetAgent;
  List<Map<String, dynamic>> _otherAgents = [];

  String _entryMode = 'present';
  bool _loading     = true;
  bool _submitting  = false;

  @override
  void initState() {
    super.initState();
    _loadAgents();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAgents() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    try {
      final res = await _c
          .from('delivery_agents')
          .select('id,name,vehicle_no,phone')
          .eq('trader_id', tid)
          .eq('is_active', true)
          .neq('id', widget.agentId)
          .order('name');
      if (mounted) {
        setState(() {
          _otherAgents =
          List<Map<String, dynamic>>.from(res as List? ?? []);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showError(context, e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  // Selected deliveries split by status
  List<Map<String, dynamic>> get _selected => widget.pendingList
      .where((d) => _selectedIds.contains(d['id'] as String))
      .toList();

  bool get _hasPrePickup => _selected
      .any((d) => (d['status'] as String?) == 'assigned');

  bool get _hasInTransit => _selected
      .any((d) => (d['status'] as String?) == 'out_for_delivery');

  // Pre-pickup deliveries share batches — collect unique batch ids
  Set<String> get _selectedBatchIds => _selected
      .where((d) => (d['status'] as String?) == 'assigned')
      .map((d) => d['batch_id'] as String)
      .toSet();

  Future<void> _submit() async {
    if (_selectedIds.isEmpty) {
      showError(context, 'Select at least one delivery to reassign.');
      return;
    }
    if (_targetAgent == null) {
      showError(context, 'Select the agent to reassign to.');
      return;
    }

    final user = ref.read(appUserProvider).valueOrNull;
    if (user?.traderId == null) return;

    final toName   = _targetAgent!['name'] as String;
    final reason   = _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim();
    final inTransit = _selected
        .where((d) => (d['status'] as String?) == 'out_for_delivery')
        .toList();
    final batchIds = _selectedBatchIds;

    final summary = StringBuffer();
    summary.write('Reassign to $toName?\n\n');
    if (batchIds.isNotEmpty) {
      summary.write('${batchIds.length} batch(es) — pre-pickup\n');
    }
    if (inTransit.isNotEmpty) {
      summary.write('${inTransit.length} delivery(s) — in transit\n');
    }
    if (reason != null) summary.write('\nReason: $reason');

    final ok = await confirmDialog(
      context,
      title: 'Confirm Reassignment',
      message: summary.toString(),
      confirmText: 'Reassign',
      confirmColor: Colors.purple,
    );
    if (!ok || !mounted) return;

    setState(() => _submitting = true);
    int done   = 0;
    int errors = 0;

    try {
      // Pre-pickup: use change_batch_agent (batch level)
      for (final batchId in batchIds) {
        try {
          await _c.rpc('change_batch_agent', params: {
            'p_batch_id':     batchId,
            'p_new_agent_id': _targetAgent!['id'],
            'p_trader_id':    user!.traderId,
            'p_actor_id':     user.userId,
            'p_entry_mode':   _entryMode,
            'p_reason':       reason,
          });
          done++;
        } catch (e) {
          errors++;
          if (mounted) {
            showError(context,
                'Batch reassign failed: ${e.toString().replaceAll('Exception: ', '')}');
          }
        }
      }

      // In-transit: use reassign_delivery (single delivery)
      for (final d in inTransit) {
        try {
          await _c.rpc('reassign_delivery', params: {
            'p_delivery_id':  d['id'],
            'p_new_agent_id': _targetAgent!['id'],
            'p_trader_id':    user!.traderId,
            'p_actor_id':     user.userId,
            'p_entry_mode':   _entryMode,
            'p_reason':       reason,
          });
          done++;
        } catch (e) {
          errors++;
          if (mounted) {
            final shop = d['shop_name'] as String? ?? '—';
            showError(context,
                'Reassign failed for $shop: '
                    '${e.toString().replaceAll('Exception: ', '')}');
          }
        }
      }

      if (!mounted) return;
      if (done > 0) {
        showSuccess(
          context,
          '✅ $done item(s) reassigned to $toName'
              '${errors > 0 ? '\n⚠ $errors item(s) failed' : ''}',
        );
        if (context.canPop()) context.pop();
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kNavy,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : null,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Reassign Orders',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800,
                    color: Colors.white)),
            Text('From: ${widget.agentName}',
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFFB4C6F4))),
          ],
        ),
      ),
      body: _loading
          ? const LoadingList()
          : ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [

          // ── Entry mode ───────────────────────────────────────────────
          _card(
            title: 'How Did Agent Report?',
            icon: Icons.support_agent_rounded,
            iconColor: Colors.orange,
            child: EntryModeSelector(
              value: _entryMode,
              onChanged: (v) => setState(() => _entryMode = v),
            ),
          ),
          const SizedBox(height: 12),

          // ── Select deliveries ────────────────────────────────────────
          _card(
            title: 'Select Deliveries to Reassign',
            icon: Icons.list_alt_rounded,
            iconColor: kNavy,
            child: Column(children: [
              // Select all toggle
              Row(children: [
                Checkbox(
                  value: _selectedIds.length == widget.pendingList.length,
                  tristate: _selectedIds.isNotEmpty &&
                      _selectedIds.length < widget.pendingList.length,
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selectedIds.addAll(
                          widget.pendingList.map((d) => d['id'] as String));
                    } else {
                      _selectedIds.clear();
                    }
                  }),
                ),
                const Text('Select All',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
              const Divider(height: 1),
              const SizedBox(height: 6),
              ...widget.pendingList.map((d) {
                final id      = d['id'] as String;
                final shop    = d['shop_name'] as String? ?? '—';
                final status  = d['status'] as String? ?? '';
                final birds   = (d['estimated_birds'] as num?)?.toInt() ?? 0;
                final weight  = (d['total_quantity'] as num?)?.toDouble() ?? 0;
                final sel     = _selectedIds.contains(id);
                final statusColor = status == 'out_for_delivery'
                    ? kNavy : status == 'picked_up'
                    ? Colors.blue : Colors.orange;

                return GestureDetector(
                  onTap: () => setState(() {
                    if (sel) {
                      _selectedIds.remove(id);
                    } else {
                      _selectedIds.add(id);
                    }
                  }),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: sel
                          ? Colors.purple.withValues(alpha: 0.07)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(kRadiusInner),
                      border: Border.all(
                        color: sel ? Colors.purple : kBorderLight,
                        width: sel ? 1.5 : 1,
                      ),
                    ),
                    child: Row(children: [
                      Checkbox(
                        value: sel,
                        activeColor: Colors.purple,
                        onChanged: (_) => setState(() {
                          if (sel) {
                            _selectedIds.remove(id);
                          } else {
                            _selectedIds.add(id);
                          }
                        }),
                      ),
                      Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(shop, style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                            Text('$birds birds · '
                                '${weight.toStringAsFixed(1)} kg',
                                style: const TextStyle(
                                    fontSize: 11, color: kTextHint)),
                          ])),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          status == 'out_for_delivery'
                              ? 'In transit' : status,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: statusColor),
                        ),
                      ),
                    ]),
                  ),
                );
              }),
            ]),
          ),
          const SizedBox(height: 12),

          // ── Status legend ────────────────────────────────────────────
          if (_hasPrePickup || _hasInTransit)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(kRadiusCard),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('REASSIGNMENT METHODS',
                        style: TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w800,
                            color: Colors.blue, letterSpacing: 0.6)),
                    const SizedBox(height: 8),
                    if (_hasPrePickup)
                      _legendRow(Icons.assignment_outlined,
                          Colors.orange,
                          'Pre-pickup (assigned)',
                          'Entire batch moved to new agent before pickup'),
                    if (_hasInTransit)
                      _legendRow(Icons.local_shipping_outlined,
                          kNavy,
                          'In transit (out_for_delivery)',
                          'Individual delivery reassigned — audit trail written'),
                  ]),
            ),
          const SizedBox(height: 12),

          // ── Target agent ─────────────────────────────────────────────
          _card(
            title: 'Reassign To',
            icon: Icons.person_outlined,
            iconColor: Colors.purple,
            child: _otherAgents.isEmpty
                ? const Text(
              'No other active agents found.',
              style: TextStyle(color: kTextHint, fontSize: 12),
            )
                : Column(children: _otherAgents.map((a) {
              final sel = _targetAgent?['id'] == a['id'];
              return GestureDetector(
                onTap: () =>
                    setState(() => _targetAgent = sel ? null : a),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: sel
                        ? Colors.purple.withValues(alpha: 0.08)
                        : Colors.white,
                    borderRadius:
                    BorderRadius.circular(kRadiusInner),
                    border: Border.all(
                      color: sel ? Colors.purple : kBorderLight,
                      width: sel ? 1.5 : 1,
                    ),
                  ),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.purple
                          .withValues(alpha: 0.12),
                      child: Text(
                        (a['name'] as String)[0].toUpperCase(),
                        style: const TextStyle(
                            color: Colors.purple,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          Text(a['name'] as String,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                          Text(
                              a['vehicle_no'] as String? ?? '—',
                              style: const TextStyle(
                                  fontSize: 11, color: kTextHint)),
                        ])),
                    if (sel)
                      const Icon(Icons.check_circle,
                          color: Colors.purple, size: 20),
                  ]),
                ),
              );
            }).toList()),
          ),
          const SizedBox(height: 12),

          // ── Reason ───────────────────────────────────────────────────
          TextField(
            controller: _reasonCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              alignLabelWithHint: true,
              hintText:
              'e.g. Agent unavailable, area reassignment…',
            ),
          ),
          const SizedBox(height: 24),

          // ── Submit ───────────────────────────────────────────────────
          ElevatedButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.swap_horiz_rounded, size: 20),
            label: Text(
              _selectedIds.isEmpty
                  ? 'Select deliveries above'
                  : _targetAgent == null
                  ? 'Select target agent above'
                  : 'Reassign ${_selectedIds.length} delivery(s)'
                  ' to ${_targetAgent!['name']}',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800,
                  color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kRadiusBtn)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({
    required String title,
    required IconData icon,
    required Color iconColor,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(color: kBorderLight),
        boxShadow: kCardShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 14),
        child,
      ]),
    );
  }

  Widget _legendRow(IconData icon, Color color, String label, String sub) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11,
                    fontWeight: FontWeight.w700, color: color)),
                Text(sub, style: const TextStyle(
                    fontSize: 10, color: kTextHint)),
              ])),
        ]),
      );
}