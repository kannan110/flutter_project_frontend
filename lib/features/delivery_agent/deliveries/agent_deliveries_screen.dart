import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/providers/ui_mode_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/responsive_layout.dart';

class AgentDeliveriesScreen extends ConsumerStatefulWidget {
  const AgentDeliveriesScreen({super.key});
  @override ConsumerState<AgentDeliveriesScreen> createState() => _S();
}

class _S extends ConsumerState<AgentDeliveriesScreen> {
  final _c = Supabase.instance.client;
  List<Map<String,dynamic>> _list = [];
  List<Map<String,dynamic>> _filtered = [];
  bool _loading = true;
  String _filter = 'active';
  final _searchCtrl = TextEditingController();

  void _applySearch(String q) {
    if (!mounted) return;
    final lower = q.trim().toLowerCase();
    setState(() => _filtered = lower.isEmpty
        ? List.from(_list)
        : _list.where((d) {
      final o = d['orders'] as Map<String,dynamic>?;
      final r = o?['retailers'] as Map<String,dynamic>?;
      return (r?['shop_name'] as String? ?? '').toLowerCase().contains(lower) ||
          (r?['address']   as String? ?? '').toLowerCase().contains(lower);
    }).toList());
  }

  @override void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => _applySearch(_searchCtrl.text));
  }
  @override void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    final agentId = ref.read(appUserProvider).valueOrNull?.agentId;
    if (agentId == null || !mounted) return;
    if (mounted) setState(() => _loading = true);
    try {
      var q = _c.from('deliveries')
          .select('id,status,collected_amount,payment_mode,delivered_at,'
          'delivered_bird_count,delivered_total_weight,'
          'dc_weight_kg,total_loss_kg,loss_percentage,is_high_loss,'
          'is_partial_delivery,partial_birds,partial_quantity,order_id,'
          'mortality_birds,approval_status,'
          'orders(id,estimated_birds,total_quantity,retailers(shop_name,address,phone),'
          'order_items(master_products(name)))')
          .eq('delivery_agent_id', agentId);

      if (_filter == 'active')
        q = q.inFilter('status', ['assigned', 'picked_up', 'out_for_delivery']);
      else if (_filter == 'done')
        q = q.eq('status', 'delivered');

      final data = await q.order('created_at', ascending: false).limit(100);
      if (!mounted) return;
      if (mounted) setState(() {
        _list    = List<Map<String,dynamic>>.from(data);
        _loading = false;
        _applySearch(_searchCtrl.text);
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markOutForDelivery(String deliveryId) async {
    final ok = await confirmDialog(context,
        title: 'Mark Out for Delivery',
        message: 'Confirm you are now heading to deliver this order?',
        confirmText: 'Yes, Start Delivery',
        confirmColor: Colors.teal);
    if (!ok || !mounted) return;
    try {
      await _c.from('deliveries')
          .update({'status': 'out_for_delivery'})
          .eq('id', deliveryId);
      if (mounted) {
        showSuccess(context, 'Marked as Out for Delivery ✓');
        _load();
      }
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildScaffold(BuildContext context) {
    final isSimple = ref.watch(uiModeProvider).isSimple;
    if (isSimple && !_loading) return _buildSimpleView();
    if (isSimple && _loading) return _buildSimpleLoading();

    return Scaffold(
      appBar: AppBar(
          title: const Text('My Deliveries'),
          actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: Column(children: [
        Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'active', label: Text('Active')),
                  ButtonSegment(value: 'done',   label: Text('Delivered')),
                  ButtonSegment(value: 'all',    label: Text('All')),
                ],
                selected: {_filter},
                onSelectionChanged: (s) { if (mounted) setState(() => _filter = s.first); _load(); })),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: AppSearchBar(
            controller: _searchCtrl,
            hint: 'Search by shop name…',
            onChanged: _applySearch,
            onClear: () { _searchCtrl.clear(); _applySearch(''); },
          ),
        ),
        const Divider(height: 1),
        Expanded(
            child: _loading
                ? const LoadingList()
                : _list.isEmpty
                ? EmptyState(
                icon: Icons.local_shipping_outlined,
                message: _filter == 'active' ? 'No active deliveries' : 'No deliveries found',
                sub: _filter == 'active' ? 'Admin needs to assign a batch to you' : null)
                : _filtered.isEmpty && _searchCtrl.text.isNotEmpty
                ? const EmptyState(icon: Icons.search_off_rounded, message: 'No deliveries match')
                : RefreshIndicator(
                onRefresh: _load,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, kBottomNavClearance),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _deliveryCard(_filtered[i]),
                ))),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // SIMPLE MODE — large cards, emoji-first, accessible
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildSimpleLoading() => Scaffold(
    appBar: AppBar(title: const Text('📦 Deliveries')),
    body: const Center(child: CircularProgressIndicator()),
  );

  Widget _buildSimpleView() {
    final simpleFilter = _filter == 'active' ? 'Active' : _filter == 'done' ? 'Delivered' : 'All';
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text('📦 $simpleFilter Deliveries',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            _simpleFilterChip('🟢 Active', 'active'),
            const SizedBox(width: 8),
            _simpleFilterChip('✅ Delivered', 'done'),
            const SizedBox(width: 8),
            _simpleFilterChip('📋 All', 'all'),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: _list.isEmpty
              ? Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('📭', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 12),
              Text(_filter == 'active' ? 'No active deliveries' : 'No deliveries found',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kTextSub)),
              const SizedBox(height: 8),
              Text('Waiting for admin to assign work',
                  style: const TextStyle(fontSize: 14, color: kTextHint)),
            ]),
          )
              : RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _list.length,
              itemBuilder: (_, i) => _simpleDeliveryCard(_list[i]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _simpleFilterChip(String label, String value) {
    final active = _filter == value;
    return GestureDetector(
      onTap: () { if (mounted) setState(() => _filter = value); _load(); },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: active ? kPrimary : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? kPrimary : Colors.grey.shade300, width: active ? 2 : 1),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                color: active ? Colors.white : kTextSub)),
      ),
    );
  }

  Widget _simpleDeliveryCard(Map<String, dynamic> d) {
    final o = d['orders'] as Map<String, dynamic>?;
    final r = o?['retailers'] as Map<String, dynamic>?;

    // ── Product helper (display-only, no logic) ───────────────────────────
    String productLabel() {
      final items = (o?['order_items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final names = items
          .map((i) => (i['master_products'] as Map?)?['name'] as String? ?? '')
          .where((n) => n.isNotEmpty).toSet().toList();
      if (names.isEmpty) return '';
      return names.length == 1 ? names.first : 'Multi-product';
    }
    Color productColor(String lbl) {
      final l = lbl.toLowerCase();
      if (l.contains('country')) return const Color(0xFF6D4C41);
      if (l.contains('quail'))   return Colors.purple;
      if (l.contains('multi'))   return Colors.indigo;
      return const Color(0xFF00796B);
    }
    final status = d['status'] as String? ?? '-';
    final isActive = ['assigned', 'picked_up', 'out_for_delivery'].contains(status);
    final isDelivered = status == 'delivered';
    final collected = (d['collected_amount'] as num?)?.toDouble() ?? 0;
    final delivBirds = (d['delivered_bird_count'] as num?)?.toInt() ?? 0;
    final delivWeight = (d['delivered_total_weight'] as num?)?.toDouble() ?? 0;
    final orderBirds = (o?['estimated_birds'] as num?)?.toInt() ?? 0;
    final orderWeight = (o?['total_quantity'] as num?)?.toDouble() ?? 0;
    final shopName = r?['shop_name'] as String? ?? '-';
    final address = r?['address'] as String?;

    String emoji;
    Color cardColor;
    if (isDelivered) {
      emoji = '✅';
      cardColor = const Color(0xFFF1F8E9);
    } else if (status == 'out_for_delivery') {
      emoji = '🚛';
      cardColor = const Color(0xFFE3F2FD);
    } else if (status == 'picked_up') {
      emoji = '📦';
      cardColor = const Color(0xFFFFF3E0);
    } else {
      emoji = '📋';
      cardColor = Colors.white;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isActive ? kPrimary.withValues(alpha: 0.3) : kBorder, width: isActive ? 2 : 1),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 24))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(shopName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              // ── Product chip (display-only) ─────────────────────────
              Builder(builder: (_) {
                final lbl = productLabel();
                if (lbl.isEmpty) return const SizedBox.shrink();
                final c = productColor(lbl);
                return Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: c.withValues(alpha: 0.35))),
                    child: Text(lbl,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c)),
                  ),
                );
              }),
              if (address != null)
                Text(address!, style: const TextStyle(fontSize: 12, color: kTextHint),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          _simpleStat(isDelivered ? '$delivBirds🐔' : '$orderBirds🐔', isDelivered ? 'Delivered' : 'Ordered'),
          const SizedBox(width: 6),
          _simpleStat(isDelivered ? '${delivWeight.toStringAsFixed(1)}kg' : '${orderWeight.toStringAsFixed(1)}kg', 'Weight'),
          const SizedBox(width: 6),
          if (collected > 0)
            _simpleStat('₹${collected.toStringAsFixed(0)}', 'Collected', color: Colors.green.shade700)
          else if (isActive)
            _simpleStat('Pending', 'Payment', color: Colors.orange),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDelivered ? Colors.green.shade100 : (isActive ? Colors.blue.shade100 : Colors.grey.shade100),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              isDelivered ? '✅ Delivered'
                  : status == 'out_for_delivery' ? '🚛 Out for delivery'
                  : status == 'picked_up' ? '📦 Picked up'
                  : '📋 Assigned',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                  color: isDelivered ? Colors.green.shade700
                      : isActive ? Colors.blue.shade700 : kTextSub),
            ),
          ),
          const Spacer(),
          if (status == 'out_for_delivery')
            SizedBox(
              height: 44,
              child: ElevatedButton.icon(
                onPressed: () => context.push(R.deliveryDonePath(d['id'])),
                icon: const Icon(Icons.check_circle_outline, size: 20),
                label: const Text('Mark Done', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            )
          // FIX P0: 'assigned' now also shows Start Delivery (same as picked_up).
          // Stock via transfer keeps delivery at 'assigned'; no DC required.
          else if (status == 'picked_up' || status == 'assigned')
            SizedBox(
              height: 44,
              child: ElevatedButton.icon(
                onPressed: () => _markOutForDelivery(d['id'] as String),
                icon: const Icon(Icons.local_shipping_outlined, size: 18),
                label: const Text('Start Delivery', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
        ]),
      ]),
    );
  }

  Widget _simpleStat(String value, String label, {Color? color}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(children: [
          Text(value,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color ?? kTextMain),
              textAlign: TextAlign.center),
          Text(label,
              style: const TextStyle(fontSize: 10, color: kTextHint),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // SMART MODE — original delivery card
  // ═══════════════════════════════════════════════════════════════════

  Widget _deliveryCard(Map<String,dynamic> d) {
    final o          = d['orders'] as Map<String,dynamic>?;
    final r          = o?['retailers'] as Map<String,dynamic>?;
    final status       = d['status'] as String? ?? '-';
    final isActive     = ['assigned', 'picked_up', 'out_for_delivery'].contains(status);
    final isDelivered  = status == 'delivered';
    final collected    = (d['collected_amount'] as num?)?.toDouble() ?? 0;
    final isHighLoss   = d['is_high_loss'] == true;
    final lossPct      = (d['loss_percentage'] as num?)?.toDouble() ?? 0;
    final approvalSt   = d['approval_status'] as String? ?? '';
    final delivBirds   = (d['delivered_bird_count'] as num?)?.toInt() ?? 0;
    final delivWeight  = (d['delivered_total_weight'] as num?)?.toDouble() ?? 0;
    final dcWt         = (d['dc_weight_kg'] as num?)?.toDouble() ?? 0;
    final orderBirds   = (o?['estimated_birds'] as num?)?.toInt() ?? 0;
    final orderWeight  = (o?['total_quantity']  as num?)?.toDouble() ?? 0;
    final showDelivered = isDelivered && delivBirds > 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isHighLoss ? Colors.orange.shade300
                  : isActive ? kPrimary.withValues(alpha: 0.3) : kBorder,
              width: isActive || isHighLoss ? 1.5 : 1)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(r?['shop_name'] as String? ?? '-',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
          StatusBadge(status, SC.order(status)),
        ]),

        if (r?['address'] != null) Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(children: [
              const Icon(Icons.location_on_outlined, size: 13, color: kTextHint),
              const SizedBox(width: 3),
              Expanded(child: Text(r!['address'] as String,
                  style: const TextStyle(fontSize: 11, color: kTextHint),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
            ])),

        if (r?['phone'] != null) Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(children: [
              const Icon(Icons.phone_outlined, size: 12, color: kTextHint),
              const SizedBox(width: 3),
              Text(r!['phone'] as String, style: const TextStyle(fontSize: 11, color: kTextHint)),
            ])),

        const SizedBox(height: 8),

        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.set_meal_outlined, size: 14, color: kPrimary),
              const SizedBox(width: 4),
              Text(
                  showDelivered ? '$delivBirds birds delivered' : '$orderBirds birds (est.)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: showDelivered ? kPrimary : kTextSub)),
            ]),
            Row(children: [
              const Icon(Icons.balance_outlined, size: 12, color: kTextHint),
              const SizedBox(width: 4),
              Text(
                  showDelivered
                      ? '${delivWeight.toStringAsFixed(1)} kg delivered'
                      : '${orderWeight.toStringAsFixed(1)} kg (est.)',
                  style: TextStyle(fontSize: 11, color: showDelivered ? kTextSub : kTextHint)),
            ]),
            if (dcWt > 0 && isDelivered)
              Text('DC: ${dcWt.toStringAsFixed(1)} kg loaded',
                  style: const TextStyle(fontSize: 10, color: kTextHint)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (collected > 0)
              Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.green.shade50, borderRadius: BorderRadius.circular(6)),
                  child: Row(children: [
                    const Icon(Icons.currency_rupee, size: 12, color: Colors.green),
                    Text(Fmt.amount(collected),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.green)),
                  ])),
            if (isHighLoss) const SizedBox(height: 4),
            if (isHighLoss) Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(6)),
                child: Text('⚠ Loss ${lossPct.toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.deepOrange))),
            if (isDelivered && !isHighLoss && lossPct > 0) const SizedBox(height: 4),
            if (isDelivered && !isHighLoss && lossPct > 0)
              Text('Loss: ${lossPct.toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 10, color: kTextHint)),
          ]),
        ]),

        if (isActive) ...[
          const SizedBox(height: 10),
          if (status == 'out_for_delivery')
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => context.push(R.deliveryDonePath(d['id'])),
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label: const Text('Complete Delivery',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              ),
            )
          else if (status == 'picked_up' || status == 'assigned')
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _markOutForDelivery(d['id'] as String),
                icon: const Icon(Icons.local_shipping_outlined, size: 16),
                label: const Text('Start Delivery',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 40),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              ),
            )
          else
            Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                    color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
                child: const Text('Awaiting action',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: kTextSub, fontWeight: FontWeight.w600))),
        ],

        if (isDelivered) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (d['is_partial_delivery'] == true) Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade300)),
                    child: Row(children: [
                      const Icon(Icons.splitscreen_outlined, size: 14, color: Colors.orange),
                      const SizedBox(width: 6),
                      Expanded(child: Text(
                          'Partial — ${(d['partial_birds'] as num?)?.toInt() ?? 0} birds · '
                              '${(d['partial_quantity'] as num?)?.toStringAsFixed(1) ?? '0'} kg remaining',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.orange))),
                    ]))),
            Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Expanded(child: OutlinedButton.icon(
                      onPressed: () {
                        final orderId = (d['order_id'] ?? (d['orders'] as Map?)?['id']) as String?;
                        if (orderId != null) context.push(R.deliveryHistoryPath(orderId));
                      },
                      icon: const Icon(Icons.history, size: 14),
                      label: const Text('View History', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)))),
                ])),
            Row(children: [
              Icon(approvalSt == 'approved' ? Icons.verified_outlined
                  : Icons.pending_outlined,
                  size: 13,
                  color: approvalSt == 'approved' ? Colors.green : Colors.orange),
              const SizedBox(width: 4),
              Text(approvalSt == 'approved' ? 'Approved ✓' : 'Pending approval',
                  style: TextStyle(fontSize: 11,
                      color: approvalSt == 'approved' ? Colors.green : Colors.orange)),
            ]),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => ResponsiveLayout(
    mobile:  (_) => _buildScaffold(context),
    desktop: (_) => _buildScaffold(context),
  );
}