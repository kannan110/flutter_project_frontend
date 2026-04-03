import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
  List<Map<String,dynamic>> _activeBatches = [];
  List<Map<String,dynamic>> _challans = [];
  bool _loading = true;
  Timer? _timer;

  @override void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) { if (mounted) _load(); });
  }
  @override void dispose() { _timer?.cancel(); super.dispose(); }

  Future<void> _load() async {
    final user = ref.read(appUserProvider).valueOrNull;
    if (user == null) return;
    if (user.agentId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      // ── BUG FIX 1: Shift query ─────────────────────────────────
      // .maybeSingle() on shift — was previously in Future.wait which
      // caused type mismatch. Now sequential with proper null handling.
      Map<String,dynamic>? shift;
      try {
        shift = await _c
            .from('delivery_shifts')
            .select('id,status,odometer_start,shift_start_at,total_cash_collected')
            .eq('delivery_agent_id', user.agentId!)
            .eq('status', 'open')
            .maybeSingle();
      } catch (_) { shift = null; }

      // ── BUG FIX 2: Batch query ─────────────────────────────────
      // .not('status','in','(completed,cancelled)') was wrong PostgREST syntax.
      // Correct approach: fetch all batches for agent, then filter in Dart.
      // Also added .neq() chain as alternative.
      List<Map<String,dynamic>> batches = [];
      try {
        final rawBatches = await _c
            .from('delivery_batches')
            .select('id,status,total_orders,total_birds,total_weight,vehicle_no,'
                    'deliveries(id,status,orders(estimated_birds,total_quantity,retailers(shop_name,address)))')
            .eq('delivery_agent_id', user.agentId!)
            .order('created_at', ascending: false)
            .limit(20);

        // Filter out completed/cancelled in Dart — avoids PostgREST .not() syntax issues
        batches = (rawBatches as List)
            .cast<Map<String,dynamic>>()
            .where((b) {
              final s = b['status'] as String? ?? '';
              return s != 'completed' && s != 'cancelled';
            })
            .toList();
      } catch (_) { batches = []; }

      // ── Summary (non-fatal) ────────────────────────────────────
      Map<String,dynamic>? summary;
      try {
        final res = await _c
            .rpc('get_agent_summary', params: {'p_agent_id': user.agentId})
            .timeout(const Duration(seconds: 8));
        summary = res as Map<String,dynamic>?;
      } catch (_) { summary = null; }

      // ── DCs for active batches ─────────────────────────────────
      List<Map<String,dynamic>> challans = [];
      if (batches.isNotEmpty) {
        try {
          final batchIds = batches.map((b) => b['id'] as String).toList();
          final chRes = await _c
              .from('delivery_challans')
              .select('dc_number,dc_date,farmer_name,bird_count,net_weight,crates_count,source_type')
              .inFilter('batch_id', batchIds)
              .order('created_at', ascending: false);
          challans = List<Map<String,dynamic>>.from(chRes as List? ?? []);
        } catch (_) { challans = []; }
      }

      if (!mounted) return;
      setState(() {
        _summary       = summary;
        _activeShift   = shift;
        _activeBatches = batches;
        _challans      = challans;
        _loading       = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(appUserProvider).valueOrNull;

    // Not linked
    if (!_loading && user != null && user.agentId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Delivery App')),
        body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.link_off, size: 64, color: kTextHint),
            const SizedBox(height: 16),
            const Text('Account Not Linked', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text(
              'Your email is not linked to a delivery agent profile.\n\nAsk admin to add you in Agents, then use "Link Agent Account".',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: kTextSub, height: 1.5)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.go(R.agentLink),
              icon: const Icon(Icons.link),
              label: const Text('Link Agent Account')),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => ref.read(appUserProvider.notifier).signOut(),
              child: const Text('Sign Out', style: TextStyle(color: kTextSub))),
          ],
        ))));
    }

    final hasShift      = _activeShift != null;
    final s             = _summary ?? {};
    final todayDeliveries = (s['today_deliveries']   as num?)?.toInt()    ?? 0;
    final todayCollected  = (s['today_collected']    as num?)?.toDouble() ?? 0;
    final pendingCount    = (s['pending_deliveries'] as num?)?.toInt()    ?? 0;

    // DC totals across all active batches
    final int totalDcBirds   = _challans.fold(0,   (sum, c) => sum + ((c['bird_count']  as num?)?.toInt()    ?? 0));
    final double totalDcWeight = _challans.fold(0.0, (sum, c) => sum + ((c['net_weight'] as num?)?.toDouble() ?? 0));

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Delivery App', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          Text('Hello, ${user?.companyName ?? 'Agent'}',
              style: const TextStyle(fontSize: 11, color: kTextHint, fontWeight: FontWeight.w400)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(
            icon: const Icon(Icons.logout_outlined, size: 20),
            onPressed: () async {
              final ok = await confirmDialog(context,
                  title: 'Sign Out', message: 'Sign out from Rooster Trader?');
              if (ok && mounted) ref.read(appUserProvider.notifier).signOut();
            }),
        ],
      ),
      body: _loading
          ? const LoadingList()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [

                // ── Shift card ───────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: hasShift ? kPrimary : Colors.grey.shade700,
                      borderRadius: BorderRadius.circular(14)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(hasShift ? Icons.radio_button_on : Icons.radio_button_off,
                          color: hasShift ? const Color(0xFF90EE90) : Colors.grey.shade400,
                          size: 14),
                      const SizedBox(width: 6),
                      Text(hasShift ? 'SHIFT ACTIVE' : 'NO ACTIVE SHIFT',
                          style: const TextStyle(color: Colors.white70, fontSize: 11,
                              fontWeight: FontWeight.w700, letterSpacing: 1)),
                      const Spacer(),
                      if (!hasShift)
                        ElevatedButton(
                          onPressed: () => context.go(R.shiftOpen),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: kPrimary,
                              minimumSize: const Size(0, 32)),
                          child: const Text('Open Shift',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)))
                      else
                        OutlinedButton(
                          onPressed: () => context.go(R.shiftClose),
                          style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.white70),
                              foregroundColor: Colors.white,
                              minimumSize: const Size(0, 32)),
                          child: const Text('Close Shift', style: TextStyle(fontSize: 12))),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      _shiftStat('Deliveries',   '$todayDeliveries',            const Color(0xFFB3E5FC)),
                      _shiftStat('Collected',    Fmt.amount(todayCollected),    const Color(0xFFA5D6A7)),
                      _shiftStat('Pending',      '$pendingCount',
                          pendingCount > 0 ? const Color(0xFFFFCC80) : const Color(0xFFB3E5FC)),
                    ]),
                  ])),
                const SizedBox(height: 14),

                // No shift warning when batches exist
                if (!hasShift && _activeBatches.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _alertTile(
                        '⚠️ You have batches but no open shift. Open a shift first.',
                        Colors.orange, Icons.warning_amber_rounded,
                        onTap: () => context.go(R.shiftOpen))),

                // ── Today's DCs ──────────────────────────────────
                if (_challans.isNotEmpty) ...[
                  const SectionHeader("TODAY'S FARM PICKUPS (DCs)"),
                  WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Totals
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                          color: kPrimary.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(8)),
                      child: Row(children: [
                        _miniStat('Total Birds',  '$totalDcBirds',                        kPrimary),
                        _miniStat('Total Weight', '${totalDcWeight.toStringAsFixed(1)} kg', Colors.teal),
                        _miniStat('DCs',          '${_challans.length}',                   Colors.blue),
                      ])),
                    ..._challans.map((ch) {
                      final birds  = (ch['bird_count']  as num?)?.toInt()    ?? 0;
                      final weight = (ch['net_weight']  as num?)?.toDouble() ?? 0;
                      final crates = (ch['crates_count'] as num?)?.toInt()   ?? 0;
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.receipt_long_outlined, color: kPrimary, size: 20),
                        title: Text('${ch['dc_number'] ?? '—'} — ${ch['farmer_name'] ?? '—'}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: Text('$birds birds · ${weight.toStringAsFixed(1)} kg · $crates crates',
                            style: const TextStyle(fontSize: 11, color: kTextSub)));
                    }),
                  ])),
                  const SizedBox(height: 12),
                ],

                // ── Active batches ───────────────────────────────
                if (_activeBatches.isNotEmpty) ...[
                  const SectionHeader('ACTIVE BATCHES'),
                  ..._activeBatches.map((b) => _batchCard(b)),
                  const SizedBox(height: 4),
                ],

                // Empty state when no batches
                if (_activeBatches.isEmpty && !_loading)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200)),
                    child: const Column(children: [
                      Icon(Icons.inbox_outlined, size: 40, color: kTextHint),
                      SizedBox(height: 8),
                      Text('No active batches', style: TextStyle(fontWeight: FontWeight.w700, color: kTextSub)),
                      Text('Waiting for admin to assign a batch', style: TextStyle(fontSize: 12, color: kTextHint)),
                    ])),

                const SizedBox(height: 12),
                // ── Quick actions ────────────────────────────────
                Row(children: [
                  _qaBtn(Icons.list_outlined,    'All Deliveries', Colors.blue,   () => context.go(R.agentDeliveries)),
                  const SizedBox(width: 10),
                  _qaBtn(Icons.receipt_outlined, 'Expenses',       Colors.orange, () => context.go(R.agentExpenses)),
                ]),
              ])),
    );
  }

  Widget _batchCard(Map<String,dynamic> b) {
    final deliveries = (b['deliveries'] as List? ?? []).cast<Map<String,dynamic>>();
    final status     = b['status'] as String? ?? 'assigned';
    final doneCount  = deliveries.where((d) => d['status'] == 'delivered').length;
    final totalCount = deliveries.where((d) => d['status'] != 'cancelled').length;

    final int totalBirds = deliveries
        .where((d) => d['status'] != 'cancelled')
        .fold(0, (sum, d) {
          final o = d['orders'] as Map<String,dynamic>?;
          return sum + ((o?['estimated_birds'] as num?)?.toInt() ?? 0);
        });
    final double totalWeight = deliveries
        .where((d) => d['status'] != 'cancelled')
        .fold(0.0, (sum, d) {
          final o = d['orders'] as Map<String,dynamic>?;
          return sum + ((o?['total_quantity'] as num?)?.toDouble() ?? 0);
        });
    // Remaining (not yet delivered)
    final int remainBirds = deliveries
        .where((d) => !['delivered','cancelled'].contains(d['status']))
        .fold(0, (sum, d) {
          final o = d['orders'] as Map<String,dynamic>?;
          return sum + ((o?['estimated_birds'] as num?)?.toInt() ?? 0);
        });
    final double remainWeight = deliveries
        .where((d) => !['delivered','cancelled'].contains(d['status']))
        .fold(0.0, (sum, d) {
          final o = d['orders'] as Map<String,dynamic>?;
          return sum + ((o?['total_quantity'] as num?)?.toDouble() ?? 0);
        });

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          StatusBadge(status, SC.order(status)),
          const Spacer(),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('$doneCount / $totalCount delivered',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kTextSub)),
            if (remainBirds > 0)
              Text('Pending: $remainBirds birds · ${remainWeight.toStringAsFixed(0)} kg',
                  style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w600))
            else if (totalBirds > 0)
              Text('Done: $totalBirds birds · ${totalWeight.toStringAsFixed(0)} kg',
                  style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600)),
          ]),
        ]),
        const SizedBox(height: 8),
        ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(
            value: totalCount > 0 ? doneCount / totalCount : 0,
            backgroundColor: Colors.grey.shade200, color: kPrimary, minHeight: 6)),
        const SizedBox(height: 10),
        // Delivery list
        ...deliveries.where((d) => d['status'] != 'cancelled').map((d) {
          final o      = d['orders'] as Map<String,dynamic>?;
          final r      = o?['retailers'] as Map<String,dynamic>?;
          final dStat  = d['status'] as String? ?? '';
          final birds  = (o?['estimated_birds'] as num?)?.toInt()    ?? 0;
          final weight = (o?['total_quantity']  as num?)?.toDouble() ?? 0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Icon(_dIcon(dStat), size: 14, color: _dColor(dStat)),
              const SizedBox(width: 6),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r?['shop_name'] as String? ?? '—',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                if (birds > 0 || weight > 0)
                  Text('$birds birds · ${weight.toStringAsFixed(1)} kg',
                      style: const TextStyle(fontSize: 10, color: kTextHint)),
              ])),
              StatusBadge(dStat, SC.order(dStat), small: true),
              if (dStat == 'out_for_delivery') ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => context.push(R.deliveryDonePath(d['id'])),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: kPrimary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6)),
                    child: const Text('Complete',
                        style: TextStyle(fontSize: 10, color: kPrimary, fontWeight: FontWeight.w700)))),
              ],
            ]));
        }),
        const SizedBox(height: 8),
        Row(children: [
          if (status == 'picked_up' || status == 'out_for_delivery' || status == 'assigned') ...[
            Expanded(child: OutlinedButton.icon(
                onPressed: () => context.push(R.batchPickupPath(b['id'])),
                icon: const Icon(Icons.add_circle_outline, size: 16),
                label: Text(status == 'assigned' ? 'Add DC & Pickup' : '+ Add DC',
                    style: const TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)))),
            const SizedBox(width: 8),
            OutlinedButton.icon(
                onPressed: () => context.push(R.dcViewPath(b['id'])),
                icon: const Icon(Icons.visibility_outlined, size: 14),
                label: const Text('DCs', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36))),
            const SizedBox(width: 8),
          ],
          if (status != 'assigned')
            Expanded(child: ElevatedButton(
                onPressed: () => context.go(R.agentDeliveries),
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 36)),
                child: const Text('Go to Deliveries', style: TextStyle(fontSize: 12)))),
        ]),
      ])));
  }

  Widget _alertTile(String msg, Color c, IconData icon, {VoidCallback? onTap}) =>
      GestureDetector(onTap: onTap, child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: c.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.withValues(alpha: 0.3))),
          child: Row(children: [
            Icon(icon, color: c, size: 18), const SizedBox(width: 8),
            Expanded(child: Text(msg, style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600))),
            if (onTap != null) Icon(Icons.chevron_right, color: c, size: 16),
          ])));

  Widget _miniStat(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: c)),
    Text(l, style: const TextStyle(fontSize: 9, color: kTextHint), textAlign: TextAlign.center),
  ]));

  Widget _shiftStat(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c)),
    const SizedBox(height: 2),
    Text(l, style: const TextStyle(fontSize: 10, color: Colors.white70), textAlign: TextAlign.center),
  ]));

  Widget _qaBtn(IconData icon, String label, Color color, VoidCallback onTap) =>
    Expanded(child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.2))),
        child: Column(children: [
          Icon(icon, size: 24, color: color), const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
              textAlign: TextAlign.center),
        ]))));

  IconData _dIcon(String s) => switch(s) {
    'delivered'        => Icons.check_circle_outline,
    'out_for_delivery' => Icons.local_shipping_outlined,
    _                  => Icons.radio_button_unchecked
  };
  Color _dColor(String s) => switch(s) {
    'delivered'        => Colors.green,
    'out_for_delivery' => Colors.blue,
    _                  => Colors.grey
  };
}
