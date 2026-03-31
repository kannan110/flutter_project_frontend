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
  Map<String,dynamic>? _shift;
  Map<String,dynamic>? _stockSummary;
  List<Map<String,dynamic>> _deliveries = [];
  List<Map<String,dynamic>> _challans   = [];
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final agentId = ref.read(appUserProvider).valueOrNull?.agentId;
    final tid     = ref.read(appUserProvider).valueOrNull?.traderId;
    if (agentId == null) return;
    setState(() => _loading = true);
    try {
      final shift = await _c.from('delivery_shifts')
          .select('*,delivery_agents(name)')
          .eq('delivery_agent_id', agentId)
          .eq('status','open')
          .maybeSingle();

      Map<String,dynamic>? stock;
      List<Map<String,dynamic>> challans = [];
      List<Map<String,dynamic>> deliveries = [];

      if (shift != null) {
        // Get shift stock summary
        try {
          final res = await _c.rpc('get_shift_stock_summary', params: {'p_shift_id': shift['id']});
          stock = res != null ? Map<String,dynamic>.from(res as Map) : null;
        } catch (_) {}

        // Get today's deliveries for this shift
        deliveries = List<Map<String,dynamic>>.from(
          await _c.from('deliveries')
              .select('id,status,delivery_shift_id,orders(estimated_birds,total_quantity,retailers(shop_name,address))')
              .eq('delivery_agent_id', agentId)
              .eq('delivery_shift_id', shift['id'])
              .order('created_at'));

        // Get DCs for batches in this shift
        challans = List<Map<String,dynamic>>.from(
          await _c.from('delivery_challans').select('*,delivery_batches!inner(shift_id)')
              .eq('delivery_batches.shift_id', shift['id'])
              .order('created_at', ascending: false));
      }

      if (mounted) setState(() {
        _shift = shift; _stockSummary = stock;
        _deliveries = deliveries; _challans = challans; _loading = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  // Add DC — find open batch for this agent
  Future<void> _addDC() async {
    final agentId = ref.read(appUserProvider).valueOrNull?.agentId;
    // Find active batch (not completed/cancelled)
    final batches = List<Map<String,dynamic>>.from(
      await _c.from('delivery_batches')
          .select('id,status,farm_name')
          .eq('delivery_agent_id', agentId!)
          .not('status','in','(completed,cancelled)')
          .order('created_at', ascending: false));

    if (!mounted) return;
    if (batches.isEmpty) {
      showError(context, 'No active batch found. Create a batch from Dispatch first.'); return;
    }
    // If one batch, go directly; if multiple, let agent pick
    String batchId;
    if (batches.length == 1) {
      batchId = batches.first['id'] as String;
    } else {
      String? picked;
      await showDialog(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Select Batch'),
        content: Column(mainAxisSize: MainAxisSize.min, children: batches.map((b) =>
          ListTile(title: Text(b['farm_name'] as String? ?? 'Batch'), subtitle: Text(b['status'] as String),
            onTap: () { picked = b['id'] as String; Navigator.pop(ctx); })
        ).toList()),
      ));
      if (picked == null) return;
      batchId = picked!;
    }
    if (mounted) context.go(R.batchPickupPath(batchId));
  }

  @override
  Widget build(BuildContext context) {
    final user    = ref.watch(appUserProvider).valueOrNull;
    final hasShift = _shift != null;
    final stock   = _stockSummary;
    final picked   = (stock?['total_picked_birds'] as num?)?.toInt() ?? 0;
    final delivered = (stock?['total_delivered_birds'] as num?)?.toInt() ?? 0;
    final mortality = (stock?['total_mortality'] as num?)?.toInt() ?? 0;
    final remaining = picked - delivered - mortality;
    final cash      = (stock?['total_cash'] as num?)?.toDouble() ?? 0;
    final pending   = (stock?['pending_deliveries'] as num?)?.toInt() ?? 0;
    final done      = (stock?['done_deliveries'] as num?)?.toInt() ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('My Deliveries', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          Text('Today', style: const TextStyle(fontSize: 11, color: kTextHint)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(icon: const Icon(Icons.logout_outlined), onPressed: () async {
            final ok = await confirmDialog(context, title: 'Sign Out', message: 'Sign out?');
            if (ok && mounted) ref.read(appUserProvider.notifier).signOut();
          }),
        ],
      ),
      body: _loading ? const LoadingList() : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(14), children: [

        // ── Shift Status Card ────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: hasShift ? kPrimary : Colors.orange,
            borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Icon(hasShift ? Icons.play_circle : Icons.warning_amber_rounded, color: Colors.white, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(hasShift ? 'Shift is Active' : 'No Active Shift',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              Text(hasShift ? 'Tap shift button to close when done' : 'Open shift before starting',
                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ])),
            if (!hasShift) ElevatedButton(
              onPressed: () => context.go(R.shiftOpen),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.orange, minimumSize: const Size(80, 34)),
              child: const Text('Open', style: TextStyle(fontWeight: FontWeight.w700))),
            if (hasShift) OutlinedButton(
              onPressed: () => context.go(R.shiftClose),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white), foregroundColor: Colors.white, minimumSize: const Size(60, 34)),
              child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w600))),
          ])),
        const SizedBox(height: 12),

        // ── Live Stock Tracker (only if shift is open) ──────────────
        if (hasShift && stock != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: const Border.fromBorderSide(BorderSide(color: kBorder))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.inventory_2_outlined, color: kPrimary, size: 18),
                SizedBox(width: 6),
                Text('Live Stock Tracker', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kPrimary)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                _stockBox('Picked Up', '$picked birds', kPrimary),
                _divider(),
                _stockBox('Delivered', '$delivered birds', Colors.green),
                _divider(),
                _stockBox('Remaining', '$remaining birds',
                    remaining == 0 ? Colors.grey : remaining < 50 ? Colors.orange : kPrimary),
              ]),
              if (mortality > 0 || cash > 0) ...[
                const Divider(height: 14),
                Row(children: [
                  if (mortality > 0) Expanded(child: _miniStat('Dead/Loss', '$mortality', Colors.red)),
                  Expanded(child: _miniStat('Cash Collected', Fmt.amount(cash), Colors.green)),
                  Expanded(child: _miniStat('Done / Pending', '$done / $pending', Colors.blue)),
                ]),
              ],
            ])),
          const SizedBox(height: 12),
        ],

        // ── Quick Actions (always visible) ──────────────────────────
        Row(children: [
          Expanded(child: _action(Icons.receipt_long_outlined, 'Add DC', 'Farm / Shop pickup', Colors.blue, _addDC)),
          const SizedBox(width: 10),
          Expanded(child: _action(Icons.local_shipping_outlined, 'Deliveries', 'Mark as delivered', kPrimary, () => context.go(R.agentDeliveries))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _action(Icons.receipt_outlined, 'Expenses', 'Fuel, toll, food', Colors.orange, () => context.go(R.agentExpenses))),
          const SizedBox(width: 10),
          Expanded(child: _action(Icons.schedule_outlined, 'Shift', hasShift ? 'Close shift' : 'Open shift', hasShift ? Colors.red : Colors.green, () => context.go(hasShift ? R.shiftClose : R.shiftOpen))),
        ]),
        const SizedBox(height: 14),

        // ── DC List ──────────────────────────────────────────────────
        if (hasShift) ...[
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Today\'s DCs', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            TextButton.icon(onPressed: _addDC, icon: const Icon(Icons.add, size: 16), label: const Text('Add DC')),
          ]),
          if (_challans.isEmpty) Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange.shade200)),
            child: const Row(children: [
              Icon(Icons.info_outline, color: Colors.orange, size: 16), SizedBox(width: 8),
              Expanded(child: Text('No DC yet. Add DC to record farm/shop pickup.', style: TextStyle(fontSize: 12, color: Colors.orange))),
            ]))
          else ..._challans.map((ch) => _dcCard(ch)),
          const SizedBox(height: 14),
        ],

        // ── Deliveries quick list ────────────────────────────────────
        if (_deliveries.isNotEmpty) ...[
          const Text('Today\'s Deliveries', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ..._deliveries.where((d) => !['cancelled'].contains(d['status'])).map((d) {
            final o = d['orders'] as Map<String,dynamic>?;
            final r = o?['retailers'] as Map<String,dynamic>?;
            final status = d['status'] as String? ?? 'assigned';
            final isActive = ['assigned','picked_up','out_for_delivery'].contains(status);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isActive ? kPrimary.withOpacity(0.3) : kBorder, width: isActive ? 1.5 : 1)),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r?['shop_name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  Text('${o?['estimated_birds'] ?? 0} birds · ${(o?['total_quantity'] as num?)?.toStringAsFixed(0) ?? 0} kg',
                      style: const TextStyle(fontSize: 11, color: kTextSub)),
                ])),
                StatusBadge(status, SC.order(status), small: true),
                if (isActive) ...[const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => context.go(R.deliveryDonePath(d['id'])),
                    style: ElevatedButton.styleFrom(minimumSize: const Size(0, 30), padding: const EdgeInsets.symmetric(horizontal: 10)),
                    child: const Text('Deliver', style: TextStyle(fontSize: 11))),
                ],
              ]),
            );
          }),
        ],
      ])),
    );
  }

  Widget _stockBox(String label, String value, Color color) => Expanded(child: Column(children: [
    Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
    const SizedBox(height: 2),
    Text(label, style: const TextStyle(fontSize: 10, color: kTextHint), textAlign: TextAlign.center),
  ]));

  Widget _divider() => Container(width: 1, height: 36, color: kBorder, margin: const EdgeInsets.symmetric(horizontal: 4));

  Widget _miniStat(String l, String v, Color c) => Column(children: [
    Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c)),
    Text(l, style: const TextStyle(fontSize: 10, color: kTextHint)),
  ]);

  Widget _action(IconData icon, String title, String sub, Color color, VoidCallback onTap) =>
    InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12),
      child: Container(padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.25))),
        child: Row(children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
            Text(sub, style: const TextStyle(fontSize: 10, color: kTextHint)),
          ])),
        ])));

  Widget _dcCard(Map<String,dynamic> ch) {
    final net = (ch['net_weight'] as num?)?.toDouble() ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: const Border.fromBorderSide(BorderSide(color: kBorder))),
      child: Row(children: [
        Container(width: 34, height: 34, decoration: BoxDecoration(color: kPrimary.withOpacity(0.1), shape: BoxShape.circle),
            child: const Icon(Icons.receipt_long_outlined, color: kPrimary, size: 16)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ch['dc_number'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          Text('${ch['farmer_name'] ?? '—'} · ${ch['bird_count'] ?? 0} birds · ${net.toStringAsFixed(0)} kg',
              style: const TextStyle(fontSize: 11, color: kTextSub)),
        ])),
        Text('${ch['crates_count'] ?? 0} crates', style: const TextStyle(fontSize: 10, color: kTextHint)),
      ]));
  }
}