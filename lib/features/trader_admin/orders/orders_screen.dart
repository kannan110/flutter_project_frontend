import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _S();
}

class _S extends ConsumerState<OrdersScreen> {
  final _c = Supabase.instance.client;
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  String _filter = 'all';

  static const _statuses = [
    'all',
    'pending',
    'confirmed',
    'assigned',
    'out_for_delivery',
    'delivered',
    'invoiced',
    'closed',
    'cancelled'
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => _applySearch(_searchCtrl.text));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _applySearch(String q) {
    if (!mounted) return;
    if (q.trim().isEmpty) {
      setState(() => _filtered = List.from(_orders));
      return;
    }
    final lower = q.toLowerCase();
    setState(() => _filtered = _orders.where((o) {
          final r = o['retailers'] as Map<String, dynamic>?;
          return (r?['shop_name'] as String? ?? '')
                  .toLowerCase()
                  .contains(lower) ||
              (o['id'] as String? ?? '').toLowerCase().contains(lower);
        }).toList());
  }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    if (mounted) setState(() => _loading = true);
    try {
      var q = _c
          .from('orders')
          .select(
              'id,status,estimated_birds,total_quantity,total_amount,created_at,order_date,retailers(shop_name)') // U9 FIX: added total_quantity
          .eq('trader_id', tid);
      if (_filter != 'all') q = q.eq('status', _filter);
      final data = await q.order('created_at', ascending: false).limit(300);
      if (mounted)
        setState(() {
          _orders = List<Map<String, dynamic>>.from(data);
          _filtered = List.from(_orders);
          _loading = false;
        });
      _applySearch(_searchCtrl.text);
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      debugPrint('Orders load error: $e'); // ← add this
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Orders'), actions: [
        IconButton(icon: const Icon(Icons.refresh_outlined), onPressed: _load),
      ]),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push(R.orderCreate),
          icon: const Icon(Icons.add),
          label: const Text('New Order')),
      body: Column(children: [
        // Search bar
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: AppSearchBar(
                controller: _searchCtrl,
                hint: 'Search by shop name...',
                onChanged: _applySearch,
                onClear: () {
                  _searchCtrl.clear();
                  _applySearch('');
                })),

        // Status filter chips
        SizedBox(
            height: 50,
            child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                itemCount: _statuses.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final s = _statuses[i];
                  final isSelected = _filter == s;
                  return GestureDetector(
                      onTap: () {
                        setState(() => _filter = s);
                        _load();
                      },
                      child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                              color: isSelected ? kPrimary : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: isSelected ? kPrimary : kBorder,
                                  width: isSelected ? 0 : 1)),
                          child: Text(
                              s == 'all'
                                  ? 'All'
                                  : s
                                      .replaceAll('_', ' ')
                                      .split(' ')
                                      .map((w) =>
                                          w[0].toUpperCase() + w.substring(1))
                                      .join(' '),
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color:
                                      isSelected ? Colors.white : kTextSub))));
                })),

        // Count & divider
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Row(children: [
              Text(
                  _searchCtrl.text.isEmpty
                      ? '${_filtered.length} orders'
                      : '${_filtered.length} of ${_orders.length} orders',
                  style: const TextStyle(fontSize: 12, color: kTextSub)),
            ])),

        const Divider(height: 1),

        // List
        Expanded(
            child: _loading
                ? const LoadingList()
                : _orders.isEmpty
                    ? EmptyState(
                        icon: Icons.shopping_bag_outlined,
                        message: 'No orders yet',
                        sub: _filter != 'all'
                            ? 'No ${_filter.replaceAll("_", " ")} orders'
                            : null,
                        onAction: () => context.push(R.orderCreate),
                        actionLabel: 'New Order')
                    : _filtered.isEmpty
                        ? const EmptyState(
                            icon: Icons.search_off_outlined,
                            message: 'No orders match',
                            sub: 'Try a different search term')
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 8, 16, 100),
                                itemCount: _filtered.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (_, i) {
                                  final o = _filtered[i];
                                  final r =
                                      o['retailers'] as Map<String, dynamic>?;
                                  final status =
                                      o['status'] as String? ?? 'pending';
                                  final date = DateTime.tryParse(
                                      o['created_at'] as String? ?? '');
                                  final amt =
                                      (o['total_amount'] as num?)?.toDouble() ??
                                          0;
                                  final birds =
                                      (o['estimated_birds'] as num?)?.toInt() ??
                                          0;
                                  // U9 FIX: total_quantity is the weight in kg — primary billing field
                                  final weight = (o['total_quantity'] as num?)
                                          ?.toDouble() ??
                                      0;
                                  final sc = SC.order(status);

                                  return InkWell(
                                      onTap: () => context
                                          .push(R.orderDetailPath(o['id'])),
                                      borderRadius: BorderRadius.circular(14),
                                      child: Container(
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              border:
                                                  Border.all(color: kBorder),
                                              boxShadow: [
                                                BoxShadow(
                                                    color: Colors.black
                                                        .withValues(
                                                            alpha: 0.025),
                                                    blurRadius: 6,
                                                    offset: const Offset(0, 1))
                                              ]),
                                          child: Row(children: [
                                            // Status dot
                                            Container(
                                                width: 4,
                                                height: 52,
                                                decoration: BoxDecoration(
                                                    color: sc,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            2))),
                                            const SizedBox(width: 12),
                                            Expanded(
                                                child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                  Text(
                                                      r?['shop_name']
                                                              as String? ??
                                                          '—',
                                                      style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          fontSize: 15,
                                                          color: kTextMain)),
                                                  const SizedBox(height: 5),
                                                  Row(children: [
                                                    StatusBadge(status, sc,
                                                        small: true),
                                                    const SizedBox(width: 10),
                                                    if (birds > 0) ...[
                                                      const Icon(
                                                          Icons
                                                              .egg_alt_outlined,
                                                          size: 12,
                                                          color: kTextHint),
                                                      const SizedBox(width: 3),
                                                      Text('$birds birds',
                                                          style: const TextStyle(
                                                              fontSize: 12,
                                                              color:
                                                                  kTextHint)),
                                                      const SizedBox(width: 6),
                                                    ],
                                                    // U9 FIX: Show total_quantity (weight in kg) on list card.
                                                    // Weight is primary billing unit; traders scan this first.
                                                    if (weight > 0) ...[
                                                      const Icon(
                                                          Icons.scale_outlined,
                                                          size: 12,
                                                          color: kTextHint),
                                                      const SizedBox(width: 3),
                                                      Text(Fmt.kg(weight),
                                                          style: const TextStyle(
                                                              fontSize: 12,
                                                              color:
                                                                  kTextHint)),
                                                      const SizedBox(width: 6),
                                                    ],
                                                    if (date != null)
                                                      Text(
                                                          DateFormat('d MMM')
                                                              .format(date),
                                                          style: const TextStyle(
                                                              fontSize: 12,
                                                              color:
                                                                  kTextHint)),
                                                  ]),
                                                ])),
                                            const SizedBox(width: 8),
                                            Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  if (amt > 0)
                                                    Text(Fmt.amount(amt),
                                                        style: const TextStyle(
                                                            fontSize: 15,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color: kTextMain)),
                                                  const SizedBox(height: 4),
                                                  const Icon(
                                                      Icons.chevron_right,
                                                      color: kTextHint,
                                                      size: 20),
                                                ]),
                                          ])));
                                }))),
      ]));
}
