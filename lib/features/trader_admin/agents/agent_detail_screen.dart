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
  List<Map<String,dynamic>> _recentShifts = [];
  bool _loading = true, _toggling = false;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      // Agent details
      final a = await _c.from('delivery_agents').select('*').eq('id', widget.id).maybeSingle();

      // Performance summary
      Map<String,dynamic>? s;
      try {
        final res = await _c.rpc('get_agent_summary', params: {'p_agent_id': widget.id});
        s = res != null ? Map<String,dynamic>.from((res as Map).cast<String,dynamic>()) : null;
      } catch (_) {}

      // Recent shifts (last 10)
      List<Map<String,dynamic>> shifts = [];
      try {
        final sh = await _c.from('delivery_shifts')
            .select('id,status,shift_start_at,shift_end_at,total_cash_collected,total_orders,total_birds_delivered')
            .eq('delivery_agent_id', widget.id)
            .order('shift_start_at', ascending: false)
            .limit(8);
        shifts = List<Map<String,dynamic>>.from(sh);
      } catch (_) {}

      if (!mounted) return;
      setState(() { _agent = a; _summary = s; _recentShifts = shifts; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleActive() async {
    final current = _agent?['is_active'] as bool? ?? true;
    final action  = current ? 'deactivate' : 'activate';
    final ok = await confirmDialog(context,
        title: '${action[0].toUpperCase()}${action.substring(1)} Agent',
        message: '${action[0].toUpperCase()}${action.substring(1)} ${_agent?['name']}?\n\n'
            '${current ? 'They will not be able to receive deliveries.' : 'They can receive deliveries again.'}',
        confirmText: current ? 'Deactivate' : 'Activate',
        confirmColor: current ? Colors.red : Colors.green);
    if (!ok || !mounted) return;
    setState(() => _toggling = true);
    try {
      await _c.from('delivery_agents')
          .update({'is_active': !current})
          .eq('id', widget.id);
      showSuccess(context, '${current ? 'Deactivated' : 'Activated'} ✓');
      _load();
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<void> _editAgent() async {
    final nameCtrl    = TextEditingController(text: _agent?['name']);
    final phoneCtrl   = TextEditingController(text: _agent?['phone']);
    final vehicleCtrl = TextEditingController(text: _agent?['vehicle_no']);
    String vehicleType = _agent?['vehicle_type'] as String? ?? 'two_wheeler';

    await showModalBottomSheet(
      context: context, isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            left: 20, right: 20, top: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Edit Agent', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name *')),
          const SizedBox(height: 10),
          TextField(controller: phoneCtrl, keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone')),
          const SizedBox(height: 10),
          TextField(controller: vehicleCtrl, decoration: const InputDecoration(labelText: 'Vehicle No')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: vehicleType,
            decoration: const InputDecoration(labelText: 'Vehicle Type'),
            items: const [
              DropdownMenuItem(value: 'two_wheeler', child: Text('Two Wheeler')),
              DropdownMenuItem(value: 'auto',        child: Text('Auto')),
              DropdownMenuItem(value: 'mini_truck',  child: Text('Mini Truck')),
              DropdownMenuItem(value: 'truck',       child: Text('Truck')),
            ],
            onChanged: (v) => ss(() => vehicleType = v!)),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              try {
                await _c.from('delivery_agents').update({
                  'name':         nameCtrl.text.trim(),
                  'phone':        phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                  'vehicle_no':   vehicleCtrl.text.trim().isEmpty ? null : vehicleCtrl.text.trim(),
                  'vehicle_type': vehicleType,
                }).eq('id', widget.id);
                if (mounted) { showSuccess(context, 'Agent updated ✓'); _load(); }
              } catch (e) {
                if (mounted) showError(context, e.toString());
              }
            },
            child: const Text('Save')),
        ]))));
    nameCtrl.dispose(); phoneCtrl.dispose(); vehicleCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingList());
    if (_agent == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Not found')));
    final a = _agent!;
    final linked  = a['auth_user_id'] != null;
    final active  = a['is_active'] as bool? ?? true;
    final online  = a['is_online']  as bool? ?? false;
    final s = _summary;

    return Scaffold(
      appBar: AppBar(
        title: Text(a['name'] as String),
        actions: [
          IconButton(icon: const Icon(Icons.edit_outlined), onPressed: _editAgent),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [

        // ── Status card ───────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: active ? kPrimary : Colors.grey.shade700,
              borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            CircleAvatar(radius: 28,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              child: Text(
                (a['name'] as String).isNotEmpty ? (a['name'] as String)[0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white))),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a['name'] as String,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
              if (a['vehicle_no'] != null)
                Text(a['vehicle_no'] as String,
                    style: const TextStyle(fontSize: 12, color: Colors.white70)),
              Row(children: [
                Container(width: 7, height: 7,
                    decoration: BoxDecoration(
                        color: online ? const Color(0xFF90EE90) : Colors.white38,
                        shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(online ? 'Online' : active ? 'Active' : 'Inactive',
                    style: const TextStyle(fontSize: 11, color: Colors.white70)),
              ]),
            ])),
            _toggling
                ? const SizedBox(width: 24, height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : OutlinedButton(
                    onPressed: _toggleActive,
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white60), foregroundColor: Colors.white,
                        minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 14)),
                    child: Text(active ? 'Deactivate' : 'Activate',
                        style: const TextStyle(fontSize: 11))),
          ])),
        const SizedBox(height: 14),

        // ── Link status ───────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: linked ? Colors.green.shade50 : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: linked ? Colors.green.shade200 : Colors.orange.shade200)),
          child: Row(children: [
            Icon(linked ? Icons.check_circle : Icons.link_off,
                color: linked ? Colors.green.shade600 : Colors.orange.shade700, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(linked ? 'Account Linked' : 'Account Not Linked',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                      color: linked ? Colors.green.shade700 : Colors.orange.shade800)),
              Text(linked
                  ? 'Agent can log in with email and password'
                  : 'Share company code with agent to link account',
                  style: TextStyle(fontSize: 11, color: linked ? Colors.green.shade600 : Colors.orange.shade700)),
            ])),
          ])),
        const SizedBox(height: 14),

        // ── Details ───────────────────────────────────────────────
        WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader('DETAILS'),
          InfoRow('Phone',   a['phone']        as String? ?? '--'),
          InfoRow('Vehicle', a['vehicle_no']   as String? ?? '--'),
          InfoRow('Type',    (a['vehicle_type'] as String? ?? '').replaceAll('_', ' ').toUpperCase()),
          InfoRow('Joined',  a['created_at'] != null
              ? DateFormat('d MMM y').format(DateTime.parse(a['created_at'] as String)) : '--'),
        ])),
        const SizedBox(height: 14),

        // ── Performance stats ─────────────────────────────────────
        if (s != null) ...[
          const SectionHeader('PERFORMANCE'),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kBorder)),
            child: Column(children: [
              Row(children: [
                _stat('Today\nDeliveries', '${s['today_assigned'] ?? 0}',   kPrimary),
                _stat('Today\nDone',       '${s['today_delivered'] ?? 0}',   Colors.green),
                _stat('Today\nCash',       Fmt.amount((s['today_cash'] as num?)?.toDouble() ?? 0), Colors.teal),
                _stat('Today\nWeight',     Fmt.kg((s['today_weight'] as num?)?.toDouble() ?? 0), Colors.blue),
              ]),
              const Divider(height: 18),
              Row(children: [
                _stat('Total\nDeliveries', '${s['total_delivered'] ?? 0}',   kPrimary),
                _stat('Total\nWeight',     Fmt.kg((s['total_weight'] as num?)?.toDouble() ?? 0), Colors.blue),
                _stat('Total\nCash',       Fmt.amount((s['total_collected'] as num?)?.toDouble() ?? 0), Colors.green),
                _stat('Mortality\nTotal',  '${s['total_mortality'] ?? 0}',   Colors.red),
              ]),
            ])),
          const SizedBox(height: 14),
        ],

        // ── Recent shifts ─────────────────────────────────────────
        if (_recentShifts.isNotEmpty) ...[
          const SectionHeader('RECENT SHIFTS'),
          ..._recentShifts.map((sh) {
            final st      = sh['status'] as String? ?? 'open';
            final startAt = DateTime.tryParse(sh['shift_start_at'] as String? ?? '');
            final endAt   = DateTime.tryParse(sh['shift_end_at']   as String? ?? '');
            final cash    = (sh['total_cash_collected'] as num?)?.toDouble() ?? 0;
            final birds   = (sh['total_birds_delivered'] as num?)?.toInt() ?? 0;
            final orders  = (sh['total_orders'] as num?)?.toInt() ?? 0;
            Duration? dur;
            if (startAt != null && endAt != null) dur = endAt.difference(startAt);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kBorder)),
              child: Row(children: [
                Icon(st == 'open' ? Icons.play_circle_outline : Icons.check_circle_outline,
                    color: st == 'open' ? kPrimary : Colors.grey, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (startAt != null) Text(DateFormat('d MMM y, h:mm a').format(startAt),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  Row(children: [
                    if (dur != null) Text('${dur.inHours}h ${dur.inMinutes.remainder(60)}m',
                        style: const TextStyle(fontSize: 10, color: kTextHint)),
                    if (dur != null) const Text('  |  ', style: TextStyle(fontSize: 10, color: kBorder)),
                    Text('$orders orders · $birds birds',
                        style: const TextStyle(fontSize: 10, color: kTextSub)),
                  ]),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(Fmt.amount(cash),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.green)),
                  StatusBadge(st, SC.shift(st), small: true),
                ]),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => context.push(R.shiftDetailPath(sh['id'] as String)),
                  child: const Icon(Icons.chevron_right, color: kTextHint, size: 18)),
              ]));
          }),
          const SizedBox(height: 8),
        ],

        const SizedBox(height: 12),
      ]));
  }

  Widget _stat(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: c),
        textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
    const SizedBox(height: 2),
    Text(l, style: const TextStyle(fontSize: 9, color: kTextHint),
        textAlign: TextAlign.center),
  ]));
}
