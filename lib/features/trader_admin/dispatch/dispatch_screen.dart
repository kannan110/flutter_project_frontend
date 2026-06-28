import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class DispatchScreen extends ConsumerStatefulWidget {
  const DispatchScreen({super.key});
  @override ConsumerState<DispatchScreen> createState() => _S();
}

class _S extends ConsumerState<DispatchScreen> with SingleTickerProviderStateMixin {
  final _c = Supabase.instance.client;
  List<Map<String,dynamic>> _all = [];
  String _searchQ = '';
  bool _loading = true;
  late TabController _tab;
  final _searchCtrl = TextEditingController();

  void _applySearch(String q) {
    if (!mounted) return;
    setState(() => _searchQ = q.trim().toLowerCase());
  }

  List<Map<String,dynamic>> _applyQ(List<Map<String,dynamic>> list) {
    if (_searchQ.isEmpty) return list;
    return list.where((b) {
      final a = b['delivery_agents'] as Map<String,dynamic>?;
      return (a?['name']       as String? ?? '').toLowerCase().contains(_searchQ) ||
             (b['vehicle_no'] as String? ?? '').toLowerCase().contains(_searchQ);
    }).toList();
  }
  // M5 FIX: Completed/cancelled batches use a rolling date window to avoid
  // loading hundreds of old records. "Load More" extends the window by 7 days.
  int _completedDaysBack = 7; // show last N days of completed/cancelled
  // Phase 4C: pending ops badge count (deliveries stuck > 4 hours)
  int _pendingCount = 0;

  static const _tabs = ['Today', 'Live', 'Completed', 'Cancelled'];

  @override void initState() {
    super.initState();
    _tab = TabController(length: _tabs.length, vsync: this, initialIndex: 0);
    _load();
    _searchCtrl.addListener(() => _applySearch(_searchCtrl.text));
  }
  @override void dispose() { _tab.dispose(); _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    if (mounted) setState(() => _loading = true);
    try {
      // M5 FIX: Active/today batches load without date filter (always small count).
      // Completed/cancelled use a rolling window (_completedDaysBack) with Load More.
      // This prevents loading years of history on every screen open.
      final cutoff = DateTime.now().subtract(Duration(days: _completedDaysBack));
      final cutoffStr = cutoff.toIso8601String().split('T')[0];

      final data = await _c.from('delivery_batches')
          .select('id,status,total_birds,total_weight,created_at,vehicle_no,'
          'delivery_agents(id,name,vehicle_no,phone),'
          'deliveries(id,status,delivered_total_weight,'
          'orders(estimated_birds,total_quantity,retailers(shop_name),'
          'order_items(master_products(name)))),'
          'delivery_challans(id,dc_number,net_weight,bird_count,dc_photo_url,farmer_name,created_at)')
          .eq('trader_id', tid)
          .or('status.in.(assigned,picked_up,out_for_delivery),'
          'created_at.gte.$cutoffStr')  // active always + recent completed
          .order('created_at', ascending: false)
          .limit(300);
      // Phase 4C: count deliveries stuck > 4h for pending badge
      int pending = 0;
      try {
        final cutoff = DateTime.now().subtract(const Duration(hours: 4)).toIso8601String();
        final stuck = await _c.from('deliveries')
            .select('id')
            .eq('trader_id', tid)
            .eq('status', 'out_for_delivery')
            .lt('assigned_at', cutoff);
        pending = (stuck as List).length;
      } catch (_) {}

      if (mounted) setState(() {
        _all = List<Map<String,dynamic>>.from(data);
        _pendingCount = pending;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Filter helpers ─────────────────────────────────────────────────────────
  bool _isToday(Map<String,dynamic> b) {
    final d = DateTime.tryParse(b['created_at'] as String? ?? '');
    if (d == null) return false;
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  List<Map<String,dynamic>> get _today     => _all.where(_isToday).toList();
  List<Map<String,dynamic>> get _live      => _all.where((b) {
    final s = b['status'] as String? ?? '';
    return ['assigned','picked_up','out_for_delivery'].contains(s);
  }).toList();
  List<Map<String,dynamic>> get _completed => _all.where((b) => b['status'] == 'completed').toList();
  List<Map<String,dynamic>> get _cancelled => _all.where((b) => b['status'] == 'cancelled').toList();

  List<Map<String,dynamic>> _listFor(int tab) => _applyQ(switch (tab) {
    0 => _today,
    1 => _live,
    2 => _completed,
    3 => _cancelled,
    _ => _all,
  });

  // ── Computed per batch ─────────────────────────────────────────────────────
  int    _orders(Map<String,dynamic> b) {
    final d = (b['deliveries'] as List? ?? []).where((d) => d['status'] != 'cancelled');
    return d.length;
  }
  int _birds(Map<String,dynamic> b) {
    final challans = (b['delivery_challans'] as List? ?? []);
    if (challans.isNotEmpty) {
      return challans.fold(0, (s, c) => s + ((c['bird_count'] as num?)?.toInt() ?? 0));
    }
    // Fallback: sum from orders
    return (b['deliveries'] as List? ?? []).fold(0, (s, d) {
      final o = d['orders'] as Map?;
      return s + ((o?['estimated_birds'] as num?)?.toInt() ?? 0);
    });
  }
  double _weight(Map<String,dynamic> b) {
    final challans = (b['delivery_challans'] as List? ?? []);
    if (challans.isNotEmpty) {
      return challans.fold(0.0, (s, c) => s + ((c['net_weight'] as num?)?.toDouble() ?? 0));
    }
    return (b['deliveries'] as List? ?? []).fold(0.0, (s, d) {
      final o = d['orders'] as Map?;
      return s + ((o?['total_quantity'] as num?)?.toDouble() ?? 0);
    });
  }

  Future<void> _createBatch() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    final agents = List<Map<String,dynamic>>.from(
        await _c.from('delivery_agents').select('id,name,vehicle_no')
            .eq('trader_id', tid).eq('is_active', true).order('name'));
    if (!mounted) return;
    if (agents.isEmpty) { showError(context, 'No active agents. Add agents first.'); return; }
    Map<String,dynamic>? sel;
    await showModalBottomSheet(
        context: context, useRootNavigator: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => ListView(shrinkWrap: true, padding: const EdgeInsets.all(20), children: [
          const Text('Select Agent', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ...agents.map((a) => ListTile(
              leading: const CircleAvatar(child: Icon(Icons.delivery_dining, size: 18)),
              title: Text(a['name'] as String),
              subtitle: Text(a['vehicle_no'] as String? ?? '—'),
              onTap: () { sel = a; Navigator.of(ctx, rootNavigator: true).pop(); })),
        ]));
    if (sel == null || !mounted) return;
    try {
      // I5 FIX: stamp vehicle_no from the selected agent onto the batch.
      // vehicle_no is set when the agent is created/updated in delivery_agents.
      // This makes it visible on the dispatch and batch detail screens.
      await _c.from('delivery_batches').insert({
        'trader_id':        tid,
        'delivery_agent_id': sel!['id'],
        'status':           'assigned',
        'vehicle_no':       sel!['vehicle_no'] as String?,
      });
      _load();
      if (mounted) showSuccess(context, 'Batch created ✓');
    } catch (e) { if (mounted) showError(context, e.toString()); }
  }

  // Shown on Live tab when empty — agents may still have an open shift
  // with all deliveries done but shift not yet closed.
  Widget _allDoneBanner() => Container(
    margin: const EdgeInsets.only(top: 16),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF0284C7).withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
          color: const Color(0xFF0284C7).withValues(alpha: 0.25)),
    ),
    child: Row(children: [
      const Icon(Icons.info_outline,
          color: Color(0xFF0284C7), size: 18),
      const SizedBox(width: 10),
      const Expanded(
        child: Text(
          'Agent may have finished all deliveries with shift still open.\n'
          'To assign new orders → Agent Hub → Assign Order.',
          style: TextStyle(
              fontSize: 12,
              color: Color(0xFF0284C7),
              height: 1.5),
        ),
      ),
    ]),
  );

  // Phase 4C: inline pending ops banner — scrolls inside the list, never blocks FAB
  Widget _pendingBanner() {
    if (_pendingCount == 0) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => context.push(R.pendingOps),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
            color: Colors.red.shade600,
            borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.warning_amber_outlined, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
                '$_pendingCount ${_pendingCount == 1 ? 'delivery' : 'deliveries'} '
                    'stuck over 4 hours — tap to resolve',
                style: const TextStyle(
                    fontSize: 13, color: Colors.white,
                    fontWeight: FontWeight.w700)),
          ),
          const Icon(Icons.chevron_right, color: Colors.white, size: 18),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
        backgroundColor: kSurface,
        title: const Text('Dispatch'),
        actions: [
          // Phase 4C: Pending Operations badge button — fixed 48px width, no overflow
          if (_pendingCount > 0)
            SizedBox(
              width: 48, height: 48,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.warning_amber_outlined),
                    tooltip: 'Pending Operations',
                    onPressed: () => context.push(R.pendingOps),
                  ),
                  Positioned(
                    top: 6, right: 4,
                    child: Container(
                      width: 16, height: 16,
                      decoration: const BoxDecoration(
                          color: Colors.red, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: Text('$_pendingCount',
                          style: const TextStyle(
                              fontSize: 9, color: Colors.white,
                              fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
            ),
          // ── NEW BATCH — primary CTA ──────────────────────────────────────
          // Placed in AppBar (not FAB) because TraderShell uses extendBody:true,
          // which causes inner-Scaffold FABs to render behind the glass nav bar.
          GestureDetector(
            onTap: _createBatch,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: kNavy,
                borderRadius: BorderRadius.circular(kRadiusChip),
                boxShadow: [
                  BoxShadow(
                    color: kNavy.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.add_rounded, color: kGoldLight, size: 18),
                const SizedBox(width: 6),
                const Text('New Batch',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: kGoldLight,
                        letterSpacing: 0.2)),
              ]),
            ),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: _tabs.asMap().entries.map((e) {
            final list  = _listFor(e.key);
            final badge = list.length;
            return Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(e.value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              if (badge > 0) ...[
                const SizedBox(width: 4),
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                        color: e.key == 1 ? kPrimary : Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(8)),
                    child: Text('$badge', style: const TextStyle(
                        fontSize: 9, color: Colors.white, fontWeight: FontWeight.w800))),
              ],
            ]));
          }).toList(),
          isScrollable: true,
          labelColor: kPrimary,
          unselectedLabelColor: kTextHint,
          indicatorColor: kPrimary,
        )),
    body: Column(children: [
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: AppSearchBar(
          controller: _searchCtrl,
          hint: 'Search by agent or vehicle…',
          onChanged: _applySearch,
          onClear: () { _searchCtrl.clear(); _applySearch(''); },
        ),
      ),
      const Divider(height: 1),
      Expanded(child: _loading ? const LoadingList() : TabBarView(
        controller: _tab,
        children: List.generate(_tabs.length, (i) {
          final list = _listFor(i);
          if (list.isEmpty) {
            final emptyWidget = EmptyState(
                icon: switch(i) {
                  0 => Icons.today_outlined,
                  1 => Icons.local_shipping_outlined,
                  2 => Icons.check_circle_outline,
                  _ => Icons.cancel_outlined,
                },
                message: switch(i) {
                  0 => 'No batches today',
                  1 => 'No live deliveries',
                  2 => 'No completed batches in last $_completedDaysBack days',
                  _ => 'No cancelled batches',
                });
            // When Live tab is empty: show pending ops banner OR
            // a hint that agents may have open shifts with all deliveries done
            if (i == 1) {
              final children = <Widget>[];
              if (_pendingCount > 0) children.add(_pendingBanner());
              children.add(emptyWidget);
              children.add(_allDoneBanner());
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: children,
              );
            }
            return emptyWidget;
          }
          // M5 FIX: Completed (2) and Cancelled (3) tabs show "Load More" footer
          final showLoadMore = i >= 2;
          // Phase 4C: show banner only on Live tab (tab 1) where stuck deliveries are visible
          final showBanner = i == 1 && _pendingCount > 0;
          final bannerOffset = showBanner ? 1 : 0;
          return RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: list.length + (showLoadMore ? 1 : 0) + bannerOffset,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, idx) {
                    // Item 0 on Live tab: pending ops banner
                    if (showBanner && idx == 0) return _pendingBanner();
                    final listIdx = idx - bannerOffset;
                    // Last item: Load More button for completed/cancelled tabs
                    if (showLoadMore && listIdx == list.length) {
                      return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: OutlinedButton.icon(
                              onPressed: () {
                                setState(() => _completedDaysBack += 14);
                                _load();
                              },
                              icon: const Icon(Icons.expand_more, size: 18),
                              label: Text('Load Earlier — showing last $_completedDaysBack days',
                                  style: const TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 44),
                                  foregroundColor: kPrimary)));
                    }
                    return _BatchCard(
                      batch: list[listIdx],
                      birds: _birds(list[listIdx]),
                      weight: _weight(list[listIdx]),
                      orders: _orders(list[listIdx]),
                      onTap: () => context.push(R.batchDetailPath(list[listIdx]['id'])),
                    );
                  }));
        })),
      ),
    ]),
  );
}

// ── Batch card ──────────────────────────────────────────────────────────────
class _BatchCard extends StatelessWidget {
  const _BatchCard({
    required this.batch,
    required this.birds,
    required this.weight,
    required this.orders,
    required this.onTap,
  });
  final Map<String,dynamic> batch;
  final int birds;
  final double weight;
  final int orders;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a       = batch['delivery_agents'] as Map<String,dynamic>?;
    final status  = batch['status'] as String? ?? 'assigned';
    final date    = DateTime.tryParse(batch['created_at'] as String? ?? '');
    final challans = (batch['delivery_challans'] as List? ?? []);
    final hasDcPhoto = challans.any((c) => c['dc_photo_url'] != null);
    final deliveries = batch['deliveries'] as List? ?? [];
    final deliveredCount = deliveries.where((d) => d['status'] == 'delivered').length;
    final totalCount     = deliveries.where((d) => d['status'] != 'cancelled').length;

    // Status color + icon
    final Color sc = switch(status) {
      'assigned'        => Colors.blue,
      'picked_up'       => Colors.indigo,
      'out_for_delivery'=> kPrimary,
      'completed'       => Colors.green,
      'cancelled'       => Colors.red,
      _                 => Colors.grey,
    };
    final IconData si = switch(status) {
      'assigned'         => Icons.assignment_outlined,
      'picked_up'        => Icons.agriculture_outlined,
      'out_for_delivery' => Icons.local_shipping,
      'completed'        => Icons.check_circle,
      'cancelled'        => Icons.cancel_outlined,
      _                  => Icons.circle_outlined,
    };

    final bool isLive = ['assigned','picked_up','out_for_delivery'].contains(status);

    return GestureDetector(
        onTap: onTap,
        child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: isLive ? sc.withValues(alpha: 0.4) : kBorder,
                    width: isLive ? 1.5 : 1),
                boxShadow: [BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6, offset: const Offset(0, 2))]),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // ── Row 1: Agent + Status + Date ───────────────────────
              Row(children: [
                Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(color: sc.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10)),
                    child: Icon(si, color: sc, size: 20)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a?['name'] as String? ?? '—',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  Text(a?['vehicle_no'] as String? ?? '—',
                      style: const TextStyle(fontSize: 11, color: kTextSub)),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  StatusBadge(status, SC.order(status), small: true),
                  if (date != null) ...[
                    const SizedBox(height: 3),
                    Text(DateFormat('d MMM · h:mm a').format(date.toLocal()),
                        style: const TextStyle(fontSize: 10, color: kTextHint)),
                  ],
                ]),
              ]),

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),

              // ── Row 2: Stats ────────────────────────────────────────
              Row(children: [
                _kpi(Icons.receipt_long_outlined, 'Orders', '$orders',          Colors.blue),
                _divider(),
                _kpi(Icons.egg_alt_outlined,       'Birds',  '$birds',           kPrimary),
                _divider(),
                _kpi(Icons.scale_outlined,         'Weight', '${weight.toStringAsFixed(1)} kg', Colors.teal),
                _divider(),
                _kpi(Icons.inventory_2_outlined,   'DCs',    '${challans.length}', Colors.purple),
              ]),

              // ── Row 3: Progress bar for live batches ────────────────
              if (isLive && totalCount > 0) ...[
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: LinearProgressIndicator(
                      value: totalCount > 0 ? deliveredCount / totalCount : 0,
                      backgroundColor: kBorder,
                      color: kPrimary,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3))),
                  const SizedBox(width: 8),
                  Text('$deliveredCount/$totalCount delivered',
                      style: const TextStyle(fontSize: 10, color: kTextSub, fontWeight: FontWeight.w600)),
                ]),
              ],

              // ── Row 4: Product + DC photo + shops ───────────────────
              if (challans.isNotEmpty || deliveries.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, children: [
                  // ── Product chip (display-only) ──────────────────────
                  Builder(builder: (_) {
                    final firstDel = deliveries.isNotEmpty ? deliveries.first : null;
                    final firstOrd = firstDel?['orders'] as Map<String,dynamic>?;
                    final items = (firstOrd?['order_items'] as List?)
                        ?.cast<Map<String,dynamic>>() ?? [];
                    final names = items
                        .map((i) => (i['master_products'] as Map?)?['name'] as String? ?? '')
                        .where((n) => n.isNotEmpty).toSet().toList();
                    final lbl = names.isEmpty ? '' : names.length == 1 ? names.first : 'Multi-product';
                    if (lbl.isEmpty) return const SizedBox.shrink();
                    final cl = lbl.toLowerCase().contains('country') ? const Color(0xFF6D4C41)
                        : lbl.toLowerCase().contains('quail') ? Colors.purple
                        : lbl.toLowerCase().contains('multi') ? Colors.indigo
                        : const Color(0xFF00796B);
                    return _chip(Icons.category_outlined, lbl, cl);
                  }),
                  if (hasDcPhoto) _chip(Icons.photo_outlined, 'DC Photo', Colors.green),
                  if (challans.isNotEmpty)
                    _chip(Icons.receipt_outlined, challans.first['dc_number'] as String? ?? 'DC', Colors.purple),
                  ...deliveries
                      .where((d) => d['status'] != 'cancelled')
                      .take(3)
                      .map((d) {
                    final r = (d['orders'] as Map?)?['retailers'] as Map?;
                    return _chip(Icons.store_outlined, r?['shop_name'] as String? ?? '—', kPrimary);
                  }),
                  if (deliveries.where((d) => d['status'] != 'cancelled').length > 3)
                    _chip(Icons.more_horiz, '+${deliveries.where((d) => d['status'] != 'cancelled').length - 3} more', kTextSub),
                ]),
              ],

              const SizedBox(height: 4),
              const Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text('Tap for details', style: TextStyle(fontSize: 10, color: kTextHint)),
                Icon(Icons.chevron_right, size: 14, color: kTextHint),
              ]),
            ])));
  }

  Widget _kpi(IconData ic, String l, String v, Color c) => Expanded(child: Column(children: [
    Icon(ic, size: 14, color: c),
    const SizedBox(height: 2),
    Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c)),
    Text(l, style: const TextStyle(fontSize: 9, color: kTextHint)),
  ]));

  Widget _divider() => Container(width: 1, height: 32, color: kBorder,
      margin: const EdgeInsets.symmetric(horizontal: 2));

  Widget _chip(IconData ic, String l, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: c.withValues(alpha: 0.2))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ic, size: 10, color: c), const SizedBox(width: 3),
        Text(l, style: TextStyle(fontSize: 9, color: c, fontWeight: FontWeight.w600)),
      ]));
}