import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DISPATCH — Area-based workflow
//
// Mental model: "Which delivery person is taking which orders" — not batches.
// Batch creation/reuse is fully invisible, handled entirely by the
// `assign_orders_to_agent` RPC (the ONLY batch-creation path in the app —
// the old manual "New Batch" button has been removed; agent_assistance_
// hub_screen.dart's Assign Order sheet now calls the same RPC instead of its
// own manual batch insert — see that file's _assignOrderWithNewBatch).
//
// Pending tab: confirmed orders grouped by Delivery Area (operational,
// independent of pricing Zone). Whole-area assign, partial (expand + uncheck),
// mixed-area (expand several, select across), and single-customer Quick
// Assign are all backed by the same cart + the same RPC call.
//
// Live tab: existing batch monitor (same visual language as before), now
// just for batches already open — status in (assigned, picked_up,
// out_for_delivery). Completed/Cancelled history moved to a secondary
// "History" entry point (not a primary tab) so it isn't lost.
// ─────────────────────────────────────────────────────────────────────────────

class DispatchScreen extends ConsumerStatefulWidget {
  const DispatchScreen({super.key});
  @override
  ConsumerState<DispatchScreen> createState() => _S();
}

class _S extends ConsumerState<DispatchScreen> with SingleTickerProviderStateMixin {
  final _c = Supabase.instance.client;
  late TabController _tab;
  Timer? _autoRefresh;

  bool _loading = true;
  List<Map<String, dynamic>> _confirmedOrders = [];
  List<Map<String, dynamic>> _liveBatches = [];
  List<Map<String, dynamic>> _agents = [];
  Map<String, Map<String, dynamic>> _agentOpenBatch = {}; // agent_id -> {orders,birds,weight}

  int _pendingCount = 0; // stuck-delivery badge, unrelated to this redesign
  String? _lastError;    // surfaced visibly instead of silently blanking the screen

  // ── Cart / selection state ────────────────────────────────────────────────
  final Set<String> _cart = {};                 // selected order ids
  final Set<String?> _expanded = {};             // expanded area keys (null = Unassigned)
  Map<String, dynamic>? _pinnedAgent;            // "active" agent for continuous loading
  final _searchCtrl = TextEditingController();
  String _search = '';
  final Map<String?, String> _areaLocalSearch = {}; // per-expanded-area search, keyed by area id

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _searchCtrl.addListener(() => setState(() => _search = _searchCtrl.text.trim().toLowerCase()));
    _load();
    _autoRefresh = Timer.periodic(const Duration(seconds: 7), (_) => _silentRefresh());
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    _tab.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    await _fetchAll();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _silentRefresh() async {
    await _fetchAll();
    final stillConfirmed = _confirmedOrders.map((o) => o['id'] as String).toSet();
    _cart.removeWhere((id) => !stillConfirmed.contains(id));
    if (mounted) setState(() {});
  }

  Future<void> _fetchAll() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    try {
      final orders = await _c.from('orders')
          .select('id,estimated_birds,total_quantity,total_amount,final_amount,created_at,'
          'retailers(id,shop_name,area_id,areas(area_name))')
          .eq('trader_id', tid).eq('status', 'confirmed')
          .order('created_at');

      // Batches fetched with only a 1-level embed (matches the proven pattern
      // in batch_detail_screen.dart, which never nests more than 2 levels in
      // a single call). Deliveries and challans are fetched separately and
      // merged client-side — a 3-level triple-embed in one call is fragile
      // and, if it errors, was silently discarding the orders query above too
      // (both lived under the same try/catch). Isolating each query means a
      // failure in one no longer blanks out everything else.
      final batches = await _c.from('delivery_batches')
          .select('id,status,total_birds,total_weight,created_at,vehicle_no,delivery_agent_id,'
          'delivery_agents(id,name,vehicle_no,phone)')
          .eq('trader_id', tid)
          .inFilter('status', ['assigned', 'picked_up', 'out_for_delivery'])
          .order('created_at', ascending: false);

      final batchIds = List<Map<String, dynamic>>.from(batches as List? ?? [])
          .map((b) => b['id'] as String).toList();

      List<Map<String, dynamic>> allDeliveries = [];
      List<Map<String, dynamic>> allChallans = [];
      if (batchIds.isNotEmpty) {
        try {
          final d = await _c.from('deliveries')
              .select('id,status,batch_id,orders(estimated_birds,total_quantity,retailers(shop_name))')
              .inFilter('batch_id', batchIds);
          allDeliveries = List<Map<String, dynamic>>.from(d as List? ?? []);
        } catch (e) {
          debugPrint('Dispatch: deliveries fetch failed: $e');
        }
        try {
          final c = await _c.from('delivery_challans')
              .select('id,batch_id,dc_number,net_weight,bird_count,dc_photo_url')
              .inFilter('batch_id', batchIds);
          allChallans = List<Map<String, dynamic>>.from(c as List? ?? []);
        } catch (e) {
          debugPrint('Dispatch: challans fetch failed: $e');
        }
      }
      for (final b in List<Map<String, dynamic>>.from(batches as List? ?? [])) {
        final bid = b['id'] as String;
        b['deliveries'] = allDeliveries.where((d) => d['batch_id'] == bid).toList();
        b['delivery_challans'] = allChallans.where((c) => c['batch_id'] == bid).toList();
      }

      final agents = await _c.from('delivery_agents')
          .select('id,name,vehicle_no,phone')
          .eq('trader_id', tid).eq('is_active', true).order('name');

      int pending = 0;
      try {
        final cutoff = DateTime.now().subtract(const Duration(hours: 4)).toIso8601String();
        final stuck = await _c.from('deliveries').select('id')
            .eq('trader_id', tid).eq('status', 'out_for_delivery').lt('assigned_at', cutoff);
        pending = (stuck as List).length;
      } catch (_) {}

      final agentBatch = <String, Map<String, dynamic>>{};
      for (final b in List<Map<String, dynamic>>.from(batches as List? ?? [])) {
        final aid = b['delivery_agent_id'] as String?;
        if (aid == null || agentBatch.containsKey(aid)) continue;
        final activeDeliveries = (b['deliveries'] as List? ?? [])
            .where((d) => d['status'] != 'cancelled').toList();
        agentBatch[aid] = {
          'orders': activeDeliveries.length,
          'birds': (b['total_birds'] as num?)?.toInt() ?? 0,
          'weight': (b['total_weight'] as num?)?.toDouble() ?? 0.0,
        };
      }

      if (mounted) {
        setState(() {
          _confirmedOrders = List<Map<String, dynamic>>.from(orders as List? ?? []);
          _liveBatches = List<Map<String, dynamic>>.from(batches as List? ?? []);
          _agents = List<Map<String, dynamic>>.from(agents as List? ?? []);
          _agentOpenBatch = agentBatch;
          _pendingCount = pending;
          _lastError = null;
        });
      }
    } catch (e) {
      debugPrint('Dispatch: fetchAll failed: $e');
      if (mounted) setState(() => _lastError = e.toString());
    }
  }

  String _initial(String name) => name.trim().isEmpty ? '?' : name.trim().substring(0, 1).toUpperCase();

  double _amt(Map<String, dynamic> o) =>
      ((o['total_amount'] ?? o['final_amount']) as num?)?.toDouble() ?? 0.0;

  List<_AreaGroup> get _areaGroups {
    final map = <String?, _AreaGroup>{};
    for (final o in _confirmedOrders) {
      final r = o['retailers'] as Map<String, dynamic>?;
      final areaId = r?['area_id'] as String?;
      final areaName = (r?['areas'] as Map?)?['area_name'] as String? ?? 'Unassigned';
      final g = map.putIfAbsent(areaId, () => _AreaGroup(id: areaId, name: areaName, orders: []));
      g.orders.add(o);
    }
    final list = map.values.toList();
    list.sort((a, b) {
      if (a.id == null) return -1;
      if (b.id == null) return 1;
      return b.orders.length.compareTo(a.orders.length);
    });
    return list;
  }

  Future<void> _assignArea(_AreaGroup g) async {
    _cart.addAll(g.orders.map((o) => o['id'] as String));
    setState(() {});
    await _confirmAssignment();
  }

  Future<void> _quickAssign(Map<String, dynamic> order) async {
    final agent = _pinnedAgent ?? await _pickAgent();
    if (agent == null || !mounted) return;
    if (_pinnedAgent == null) setState(() => _pinnedAgent = agent);
    await _runAssign([order['id'] as String], agent);
  }

  Future<void> _confirmAssignment() async {
    if (_cart.isEmpty) return;
    final agent = _pinnedAgent ?? await _pickAgent();
    if (agent == null || !mounted) return;
    if (_pinnedAgent == null) setState(() => _pinnedAgent = agent);
    await _runAssign(_cart.toList(), agent);
  }

  Future<void> _runAssign(List<String> orderIds, Map<String, dynamic> agent) async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    try {
      final res = await _c.rpc('assign_orders_to_agent', params: {
        'p_trader_id': tid,
        'p_agent_id': agent['id'],
        'p_order_ids': orderIds,
      });
      final added = (res as Map?)?['added_count'] ?? orderIds.length;
      setState(() => _cart.removeWhere(orderIds.contains));
      if (mounted) {
        showSuccess(context, '✓ $added order(s) → ${agent['name']}');
      }
      _silentRefresh();
    } catch (e) {
      if (mounted) showError(context, e.toString());
    }
  }

  Future<Map<String, dynamic>?> _pickAgent() async {
    if (_agents.isEmpty) {
      if (mounted) showError(context, 'No active delivery agents. Add agents first.');
      return null;
    }
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
        decoration: const BoxDecoration(
            color: kSurface, borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusCard))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 38, height: 4,
              decoration: BoxDecoration(color: kBorderLight, borderRadius: BorderRadius.circular(2))),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Who is taking these orders?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kNavy)),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.all(12),
              itemCount: _agents.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final a = _agents[i];
                final ob = _agentOpenBatch[a['id']];
                return InkWell(
                  borderRadius: BorderRadius.circular(kRadiusCard),
                  onTap: () => Navigator.of(ctx, rootNavigator: true).pop(a),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: kBgPage,
                        borderRadius: BorderRadius.circular(kRadiusCard),
                        border: Border.all(color: kBorderLight)),
                    child: Row(children: [
                      CircleAvatar(
                          radius: 26,
                          backgroundColor: kPrimary.withValues(alpha: 0.1),
                          child: Text(_initial(a['name'] as String),
                              style: const TextStyle(fontWeight: FontWeight.w800, color: kPrimary, fontSize: 18))),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(a['name'] as String,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                          Text(a['vehicle_no'] as String? ?? '—',
                              style: const TextStyle(fontSize: 12, color: kTextSub)),
                          const SizedBox(height: 4),
                          Text(
                              ob == null
                                  ? 'No open batch — a new one starts silently'
                                  : '${ob['orders']} orders · ${ob['birds']} birds · '
                                  '${(ob['weight'] as double).toStringAsFixed(0)} kg loaded',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: ob == null ? kTextHint : kPrimary,
                                  fontWeight: FontWeight.w600)),
                        ]),
                      ),
                      const Icon(Icons.chevron_right, color: kTextHint),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  // Search-filtered view: an order matches if its shop name or area name
  // contains the query; a group with zero matching orders is hidden entirely.
  List<_AreaGroup> get _filteredAreaGroups {
    if (_search.isEmpty) return _areaGroups;
    return _areaGroups
        .map((g) {
      final matches = g.orders.where((o) {
        final shop = ((o['retailers'] as Map?)?['shop_name'] as String? ?? '').toLowerCase();
        return shop.contains(_search) || g.name.toLowerCase().contains(_search);
      }).toList();
      return _AreaGroup(id: g.id, name: g.name, orders: matches);
    })
        .where((g) => g.orders.isNotEmpty)
        .toList();
  }

  void _selectAllVisible(List<_AreaGroup> groups) {
    setState(() => _cart.addAll(groups.expand((g) => g.orders).map((o) => o['id'] as String)));
  }

  void _clearCart() => setState(() => _cart.clear());

  List<Map<String, dynamic>> get _cartOrders =>
      _confirmedOrders.where((o) => _cart.contains(o['id'])).toList();
  int get _cartBirds => _cartOrders.fold(0, (s, o) => s + ((o['estimated_birds'] as num?)?.toInt() ?? 0));
  double get _cartWeight => _cartOrders.fold(0.0, (s, o) => s + ((o['total_quantity'] as num?)?.toDouble() ?? 0));
  double get _cartAmount => _cartOrders.fold(0.0, (s, o) => s + _amt(o));

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kBgPage,
    appBar: AppBar(
      backgroundColor: kSurface,
      title: const Text('Dispatch'),
      actions: [
        if (_pendingCount > 0)
          IconButton(
              icon: Badge(
                  label: Text('$_pendingCount'),
                  backgroundColor: Colors.red,
                  child: const Icon(Icons.warning_amber_outlined)),
              tooltip: 'Pending Operations',
              onPressed: () => context.push(R.pendingOps)),
        IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Completed / Cancelled History',
            onPressed: () => context.push(R.dispatchHistory)),
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ],
      bottom: TabBar(controller: _tab, tabs: [
        Tab(child: _tabLabel('Pending', _confirmedOrders.length)),
        Tab(child: _tabLabel('Live', _liveBatches.length)),
      ], labelColor: kPrimary, unselectedLabelColor: kTextHint, indicatorColor: kPrimary),
    ),
    body: _loading
        ? const LoadingList()
        : _lastError != null
        ? Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 40, color: kError),
          const SizedBox(height: 12),
          const Text('Could not load Dispatch',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(_lastError!,
              style: const TextStyle(fontSize: 12, color: kTextHint),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _load, child: const Text('Retry')),
        ]),
      ),
    )
        : TabBarView(controller: _tab, children: [_pendingTab(), _liveTab()]),
  );

  Widget _tabLabel(String label, int count) => Row(mainAxisSize: MainAxisSize.min, children: [
    Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
    if (count > 0) ...[
      const SizedBox(width: 5),
      Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(8)),
          child: Text('$count',
              style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w800))),
    ],
  ]);

  Widget _pendingTab() {
    final groups = _filteredAreaGroups;
    final hasUnassigned = groups.any((g) => g.id == null);
    return Column(children: [
      Container(
        color: kSurface,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Column(children: [
          AppSearchBar(
            controller: _searchCtrl,
            hint: 'Search customer or area…',
            onClear: () { _searchCtrl.clear(); setState(() => _search = ''); },
          ),
          const SizedBox(height: 8),
          Row(children: [
            Text('${_cart.length} selected · ${groups.fold(0, (s, g) => s + g.orders.length)} shown',
                style: const TextStyle(fontSize: 12, color: kTextSub, fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton(onPressed: () => _selectAllVisible(groups), child: const Text('Select all shown')),
            TextButton(onPressed: _clearCart, child: const Text('Clear')),
          ]),
        ]),
      ),
      const Divider(height: 1),
      if (hasUnassigned) _unassignedBanner(),
      if (_pinnedAgent != null) _pinnedAgentBar(),
      Expanded(
        child: groups.isEmpty
            ? EmptyState(
            icon: Icons.local_shipping_outlined,
            message: _search.isNotEmpty ? 'No matches for "$_search"' : 'No confirmed orders waiting',
            sub: _search.isNotEmpty
                ? 'Try a different customer or area name.'
                : 'New confirmed orders will appear here automatically, grouped by Delivery Area.')
            : RefreshIndicator(
          onRefresh: _load,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
            itemCount: groups.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _areaCard(groups[i]),
          ),
        ),
      ),
      if (_cart.isNotEmpty) _cartBar(),
    ]);
  }

  Widget _unassignedBanner() => Container(
    width: double.infinity,
    color: Colors.orange.withValues(alpha: 0.08),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(children: [
      Icon(Icons.help_outline, color: Colors.orange.shade800, size: 18),
      const SizedBox(width: 8),
      const Expanded(
          child: Text('Some retailers have no Delivery Area yet',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kNavy))),
      TextButton(
          onPressed: () => context.push(R.bulkAreaAssign),
          child: const Text('Tag Areas')),
    ]),
  );

  Widget _pinnedAgentBar() => Container(
    width: double.infinity,
    color: kPrimary.withValues(alpha: 0.06),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(children: [
      CircleAvatar(
          radius: 14,
          backgroundColor: kPrimary,
          child: Text(_initial(_pinnedAgent!['name'] as String),
              style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w800))),
      const SizedBox(width: 8),
      Expanded(
          child: Text('Continue with ${_pinnedAgent!['name']}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kNavy))),
      TextButton(
          onPressed: () async {
            final a = await _pickAgent();
            if (a != null) setState(() => _pinnedAgent = a);
          },
          child: const Text('Change Delivery Agent')),
    ]),
  );

  Widget _areaCard(_AreaGroup g) {
    final expanded = _expanded.contains(g.id);
    final birds = g.orders.fold(0, (s, o) => s + ((o['estimated_birds'] as num?)?.toInt() ?? 0));
    final weight = g.orders.fold(0.0, (s, o) => s + ((o['total_quantity'] as num?)?.toDouble() ?? 0));
    final amount = g.orders.fold(0.0, (s, o) => s + _amt(o));
    final isUnassigned = g.id == null;

    return WhiteCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => setState(
                  () => expanded ? _expanded.remove(g.id) : _expanded.add(g.id)),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                  color: (isUnassigned ? Colors.orange : kPrimary).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(kRadiusInner)),
              child: Icon(isUnassigned ? Icons.help_outline : Icons.map_outlined,
                  color: isUnassigned ? Colors.orange.shade700 : kPrimary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                Text('${g.orders.length} orders · $birds birds · ${weight.toStringAsFixed(0)} kg · ${Fmt.amount(amount)}',
                    style: const TextStyle(fontSize: 12, color: kTextSub)),
              ]),
            ),
            Icon(expanded ? Icons.expand_less : Icons.expand_more, color: kTextHint),
          ]),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 40, width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _assignArea(g),
            icon: const Icon(Icons.local_shipping_outlined, size: 16),
            label: Text(_pinnedAgent != null
                ? 'Assign to ${_pinnedAgent!['name']}'
                : 'Assign ${g.name}'),
            style: OutlinedButton.styleFrom(foregroundColor: kPrimary, side: const BorderSide(color: kPrimary)),
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 8),
          _areaExpandedSection(g),
        ],
      ]),
    );
  }

  // Local (per-area) search + select-all/deselect-all + bounded scroll list.
  // Built as its own method since areas commonly hold 20+ customers — a flat
  // inline list of that size inside the page-level ListView is unusable
  // without its own search and its own scroll boundary.
  Widget _areaExpandedSection(_AreaGroup g) {
    final query = (_areaLocalSearch[g.id] ?? '').toLowerCase();
    final visible = query.isEmpty
        ? g.orders
        : g.orders.where((o) {
      final shop = ((o['retailers'] as Map?)?['shop_name'] as String? ?? '').toLowerCase();
      return shop.contains(query);
    }).toList();
    final visibleIds = visible.map((o) => o['id'] as String).toSet();
    final selectedInVisible = visibleIds.where(_cart.contains).length;
    final allVisibleSelected = visible.isNotEmpty && selectedInVisible == visible.length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (g.orders.length > 6)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextField(
            key: ValueKey('area_search_${g.id}'),
            onChanged: (v) => setState(() => _areaLocalSearch[g.id] = v),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search within ${g.name}…',
              hintStyle: const TextStyle(fontSize: 12, color: kTextHint),
              prefixIcon: const Icon(Icons.search, size: 18, color: kTextHint),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      Row(children: [
        Text('$selectedInVisible of ${visible.length} selected',
            style: const TextStyle(fontSize: 11, color: kTextSub, fontWeight: FontWeight.w600)),
        const Spacer(),
        TextButton(
          onPressed: visible.isEmpty
              ? null
              : () => setState(() {
            if (allVisibleSelected) {
              _cart.removeWhere(visibleIds.contains);
            } else {
              _cart.addAll(visibleIds);
            }
          }),
          child: Text(allVisibleSelected ? 'Deselect All' : 'Select All',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ]),
      if (visible.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('No customers match your search.',
              style: TextStyle(fontSize: 12, color: kTextHint)),
        )
      else
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: ListView.builder(
            shrinkWrap: true,
            physics: const ClampingScrollPhysics(),
            itemCount: visible.length,
            itemBuilder: (_, i) {
              final o = visible[i];
              final id = o['id'] as String;
              final r = o['retailers'] as Map<String, dynamic>?;
              final sel = _cart.contains(id);
              return CheckboxListTile(
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                value: sel,
                onChanged: (_) => setState(() => sel ? _cart.remove(id) : _cart.add(id)),
                title: Text(r?['shop_name'] as String? ?? '—',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text(
                    '${o['estimated_birds'] ?? 0} birds · ${((o['total_quantity'] as num?)?.toStringAsFixed(0)) ?? '—'} kg',
                    style: const TextStyle(fontSize: 11, color: kTextHint)),
                secondary: IconButton(
                    tooltip: 'Quick Assign',
                    icon: const Icon(Icons.bolt, color: kPrimary),
                    onPressed: () => _quickAssign(o)),
              );
            },
          ),
        ),
    ]);
  }

  Widget _cartBar() => Container(
    padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).padding.bottom + 10),
    decoration: BoxDecoration(
      color: kSurface,
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, -3))],
    ),
    child: Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_cart.length} orders selected',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          Text('$_cartBirds birds · ${_cartWeight.toStringAsFixed(0)} kg · ${Fmt.amount(_cartAmount)}',
              style: const TextStyle(fontSize: 11, color: kTextSub)),
        ]),
      ),
      const SizedBox(width: 12),
      ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 0, maxWidth: 200),
        child: ElevatedButton(
          onPressed: _confirmAssignment,
          child: Text(_pinnedAgent != null ? 'Assign to ${_pinnedAgent!['name']}' : 'Confirm Assignment',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    ]),
  );

  Widget _liveTab() {
    if (_liveBatches.isEmpty) {
      return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: [
        const EmptyState(icon: Icons.local_shipping_outlined, message: 'No live deliveries'),
        if (_pendingCount == 0)
          Container(
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0284C7).withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.25)),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline, color: Color(0xFF0284C7), size: 18),
              SizedBox(width: 10),
              Expanded(
                  child: Text(
                      'Assign orders from the Pending tab — a batch opens automatically the moment you assign.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF0284C7), height: 1.5))),
            ]),
          ),
      ]);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: _liveBatches.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final b = _liveBatches[i];
          final deliveries = (b['deliveries'] as List? ?? []).where((d) => d['status'] != 'cancelled');
          final challans = (b['delivery_challans'] as List? ?? []);
          final birds = challans.isNotEmpty
              ? challans.fold(0, (s, c) => s + ((c['bird_count'] as num?)?.toInt() ?? 0))
              : deliveries.fold(0, (s, d) => s + (((d['orders'] as Map?)?['estimated_birds'] as num?)?.toInt() ?? 0));
          final weight = challans.isNotEmpty
              ? challans.fold(0.0, (s, c) => s + ((c['net_weight'] as num?)?.toDouble() ?? 0))
              : deliveries.fold(0.0, (s, d) => s + (((d['orders'] as Map?)?['total_quantity'] as num?)?.toDouble() ?? 0));
          return _LiveBatchCard(
            batch: b, birds: birds, weight: weight, orders: deliveries.length,
            onTap: () => context.push(R.batchDetailPath(b['id'])),
          );
        },
      ),
    );
  }
}

class _AreaGroup {
  _AreaGroup({required this.id, required this.name, required this.orders});
  final String? id;
  final String name;
  final List<Map<String, dynamic>> orders;
}

class _LiveBatchCard extends StatelessWidget {
  const _LiveBatchCard({
    required this.batch, required this.birds, required this.weight,
    required this.orders, required this.onTap,
  });
  final Map<String, dynamic> batch;
  final int birds;
  final double weight;
  final int orders;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = batch['delivery_agents'] as Map<String, dynamic>?;
    final status = batch['status'] as String? ?? 'assigned';
    final date = DateTime.tryParse(batch['created_at'] as String? ?? '');
    final Color sc = switch (status) {
      'assigned' => Colors.blue,
      'picked_up' => Colors.indigo,
      'out_for_delivery' => kPrimary,
      _ => Colors.grey,
    };
    final IconData si = switch (status) {
      'assigned' => Icons.assignment_outlined,
      'picked_up' => Icons.agriculture_outlined,
      'out_for_delivery' => Icons.local_shipping,
      _ => Icons.circle_outlined,
    };
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: sc.withValues(alpha: 0.4), width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: sc.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(si, color: sc, size: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a?['name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                Text(a?['vehicle_no'] as String? ?? '—', style: const TextStyle(fontSize: 11, color: kTextSub)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              StatusBadge(status, SC.order(status), small: true),
              if (date != null) ...[
                const SizedBox(height: 3),
                Text(DateFormat('d MMM · h:mm a').format(date.toLocal()),
                    style: const TextStyle(fontSize: 10, color: kTextHint)),
              ],
            ]),
          ]),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _kpi('Orders', '$orders', Colors.blue)),
            Expanded(child: _kpi('Birds', '$birds', kPrimary)),
            Expanded(child: _kpi('Weight', '${weight.toStringAsFixed(1)} kg', Colors.teal)),
          ]),
        ]),
      ),
    );
  }

  Widget _kpi(String l, String v, Color c) => Column(children: [
    Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c)),
    Text(l, style: const TextStyle(fontSize: 9, color: kTextHint)),
  ]);
}