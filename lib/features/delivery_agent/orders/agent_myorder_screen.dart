import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

// Agent-facing "My Orders" — tracks every order this agent has created via
// the pre-shift Pending Order screen, across its full lifecycle:
//   pending    -> "Pending"    (awaiting trader review)
//   confirmed  -> "Approved"   (trader approved; stays visible here until
//                                a trader assigns it to a batch)
//   cancelled  -> "Cancelled"  (trader rejected; kept for the agent's own
//                                record — never silently disappears)
//   assigned / out_for_delivery / picked_up / delivered / invoiced
//              -> "Assigned"   (now in the normal delivery pipeline — this
//                                screen shows it briefly with a link to
//                                Deliveries rather than tracking it forever)
//
// This screen does not duplicate any business logic — it only reads
// orders.status, which already reflects every transition correctly via
// existing functions (confirm_retailer_order, the generic cancel update,
// add_order_to_batch). No new status, no new table.
class AgentMyOrdersScreen extends ConsumerStatefulWidget {
  const AgentMyOrdersScreen({super.key});

  @override
  ConsumerState<AgentMyOrdersScreen> createState() => _S();
}

enum _Bucket { pending, approved, cancelled, assigned }

class _S extends ConsumerState<AgentMyOrdersScreen> {
  final _c = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _orders = [];
  _Bucket? _filter; // null = show all
  final _searchCtrl = TextEditingController();
  String _searchQ = '';

  static const _assignedStatuses = {
    'assigned',
    'out_for_delivery',
    'picked_up',
    'delivered',
    'invoiced'
  };

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() {
      if (mounted) setState(() => _searchQ = _searchCtrl.text.trim().toLowerCase());
    });
  }
  @override void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    final agentId = ref.read(appUserProvider).valueOrNull?.agentId;
    if (agentId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      final rows = await _c
          .from('orders')
          .select('id,status,total_quantity,estimated_birds,total_amount,'
          'final_price,order_date,notes,retailers(shop_name),'
          'order_items(master_products(name))')
          .eq('created_by_agent_id', agentId)
          .order('created_at', ascending: false)
          .limit(100);
      if (!mounted) return;
      setState(() {
        _orders = List<Map<String, dynamic>>.from(rows as List? ?? []);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  _Bucket _bucketOf(String status) {
    if (status == 'pending') return _Bucket.pending;
    if (status == 'confirmed') return _Bucket.approved;
    if (status == 'cancelled') return _Bucket.cancelled;
    return _Bucket.assigned; // anything past confirmed is in the pipeline
  }

  String _label(_Bucket b) => switch (b) {
    _Bucket.pending => 'Pending',
    _Bucket.approved => 'Approved',
    _Bucket.cancelled => 'Cancelled',
    _Bucket.assigned => 'Assigned',
  };

  Color _color(_Bucket b) => switch (b) {
    _Bucket.pending => Colors.orange,
    _Bucket.approved => Colors.green,
    _Bucket.cancelled => kError,
    _Bucket.assigned => Colors.blue,
  };

  IconData _icon(_Bucket b) => switch (b) {
    _Bucket.pending => Icons.pending_outlined,
    _Bucket.approved => Icons.check_circle_outline,
    _Bucket.cancelled => Icons.cancel_outlined,
    _Bucket.assigned => Icons.local_shipping_outlined,
  };

  List<Map<String, dynamic>> get _filtered {
    final base = _filter == null
        ? _orders
        : _orders.where(
            (o) => _bucketOf(o['status'] as String? ?? 'pending') == _filter)
            .toList();
    if (_searchQ.isEmpty) return base;
    return base.where((o) {
      final r = o['retailer'] as Map<String,dynamic>? ??
                o['retailers'] as Map<String,dynamic>?;
      return (r?['shop_name'] as String? ?? '').toLowerCase().contains(_searchQ) ||
             (o['id'] as String? ?? '').toLowerCase().contains(_searchQ);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final counts = <_Bucket, int>{for (final b in _Bucket.values) b: 0};
    for (final o in _orders) {
      counts[_bucketOf(o['status'] as String? ?? 'pending')] =
          (counts[_bucketOf(o['status'] as String? ?? 'pending')] ?? 0) + 1;
    }

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
          backgroundColor: kPrimary,
          foregroundColor: Colors.white,
          leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                if (context.canPop())
                  context.pop();
                else
                  context.go(R.agentHome);
              }),
          title: const Text('📋 My Orders'),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load)
          ]),
      body: _loading
          ? const LoadingList()
          : Column(children: [
        // Filter chips with live counts
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _chip(null, 'All', _orders.length, kTextHint),
              const SizedBox(width: 8),
              for (final b in _Bucket.values) ...[
                _chip(b, _label(b), counts[b] ?? 0, _color(b)),
                const SizedBox(width: 8),
              ],
            ]),
          ),
        ),

        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: AppSearchBar(
            controller: _searchCtrl,
            hint: 'Search by shop name…',
            onChanged: (_) {},
            onClear: () { _searchCtrl.clear(); },
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _filtered.isEmpty
              ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child:
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.inbox_outlined,
                      size: 48,
                      color: kTextHint.withValues(alpha: 0.5)),
                  const SizedBox(height: 12),
                  Text(
                      _filter == null
                          ? 'No orders created yet.'
                          : 'No ${_label(_filter!).toLowerCase()} orders.',
                      style: const TextStyle(color: kTextHint)),
                ]),
              ))
              : RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, kBottomNavClearance),
              itemCount: _filtered.length,
              itemBuilder: (_, i) => _orderCard(_filtered[i]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _chip(_Bucket? b, String label, int count, Color c) {
    final selected = _filter == b;
    return GestureDetector(
      onTap: () => setState(() => _filter = b),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: selected ? c.withValues(alpha: 0.12) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: selected ? c : Colors.grey.shade300,
                width: selected ? 1.5 : 1)),
        child: Text('$label ($count)',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? c : kTextHint)),
      ),
    );
  }

  Widget _orderCard(Map<String, dynamic> o) {
    final status = o['status'] as String? ?? 'pending';
    final bucket = _bucketOf(status);
    final shopName =
        (o['retailers'] as Map<String, dynamic>?)?['shop_name'] as String? ??
            '—';
    final birds = (o['estimated_birds'] as num?)?.toInt();
    final weight = (o['total_quantity'] as num?)?.toDouble() ?? 0;
    final amount = (o['total_amount'] as num?)?.toDouble() ?? 0;
    final notes = o['notes'] as String?;
    final c = _color(bucket);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border: Border.all(color: c.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(_icon(bucket), size: 18, color: c),
          const SizedBox(width: 8),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(shopName,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                // ── Product chip (display-only) ──────────────────────────
                Builder(builder: (_) {
                  final items = (o['order_items'] as List?)?.cast<Map<String,dynamic>>() ?? [];
                  final names = items
                      .map((i) => (i['master_products'] as Map?)?['name'] as String? ?? '')
                      .where((n) => n.isNotEmpty).toSet().toList();
                  final lbl = names.isEmpty ? '' : names.length == 1 ? names.first : 'Multi-product';
                  if (lbl.isEmpty) return const SizedBox.shrink();
                  final pc = lbl.toLowerCase().contains('country') ? const Color(0xFF6D4C41)
                      : lbl.toLowerCase().contains('quail') ? Colors.purple
                      : lbl.toLowerCase().contains('multi') ? Colors.indigo
                      : const Color(0xFF00796B);
                  return Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                          color: pc.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: pc.withValues(alpha: 0.3))),
                      child: Text(lbl,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: pc)),
                    ),
                  );
                }),
              ])),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: c, borderRadius: BorderRadius.circular(6)),
              child: Text(_label(bucket),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 8),
        Text(
            '${birds != null ? '$birds birds · ' : ''}${weight.toStringAsFixed(1)} kg'
                '${amount > 0 ? ' · ${Fmt.amount(amount)}' : ''}',
            style: const TextStyle(fontSize: 12, color: kTextSub)),
        if (bucket == _Bucket.cancelled && notes != null && notes.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: kError.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text('Reason: $notes',
                      style: TextStyle(
                          fontSize: 11,
                          color: kError.withValues(alpha: 0.85))))),
        if (bucket == _Bucket.approved)
          Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  'Waiting for trader to assign this to a delivery batch.',
                  style: TextStyle(fontSize: 11, color: kTextHint))),
        if (bucket == _Bucket.assigned)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: GestureDetector(
                  onTap: () => context.go(R.agentDeliveries),
                  child: Row(children: [
                    Text('View in Deliveries',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.blue.shade700)),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward,
                        size: 12, color: Colors.blue.shade700),
                  ]))),
      ]),
    );
  }
}