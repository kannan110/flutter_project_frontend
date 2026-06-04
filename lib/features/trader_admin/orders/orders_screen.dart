import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/responsive_layout.dart';
import '../../../shared/widgets/common/async_state_view.dart';
import '../../../shared/widgets/common/status_chip.dart';
import '../../../shared/widgets/filters/filter_bar.dart';
import '../../../shared/widgets/filters/search_bar.dart' hide ListToolbar;
import '../../../shared/widgets/tables/app_table.dart';

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
  String? _error;
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
    'cancelled',
  ];

  // ── Lifecycle ─────────────────────────────────────────────────────────────

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

  // ── Data ──────────────────────────────────────────────────────────────────

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
    if (mounted)
      setState(() {
        _loading = true;
        _error = null;
      });
    try {
      var q = _c
          .from('orders')
          .select(
              'id,status,estimated_birds,total_quantity,total_amount,created_at,order_date,retailers(shop_name)')
          .eq('trader_id', tid);
      if (_filter != 'all') q = q.eq('status', _filter);
      final data = await q.order('created_at', ascending: false).limit(300);
      if (!mounted) return;
      setState(() {
        _orders = List<Map<String, dynamic>>.from(data);
        _filtered = List.from(_orders);
        _loading = false;
      });
      _applySearch(_searchCtrl.text);
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDesktop = context.isDesktop;

    return ListScreenScaffold(
      // AppBar only shown on mobile/tablet — desktop topbar handles title
      appBar: isDesktop
          ? null
          : AppBar(
              title: const Text('Orders'),
              actions: [
                IconButton(
                    icon: const Icon(Icons.refresh_outlined), onPressed: _load)
              ],
            ),

      // Toolbar: search + new order button
      toolbar: ListToolbar(
        searchController: _searchCtrl,
        searchHint: 'Search by shop name or order ID…',
        onSearch: _applySearch,
        onClearSearch: () {
          _searchCtrl.clear();
          _applySearch('');
        },
        primaryLabel: 'New Order',
        primaryIcon: Icons.add_rounded,
        onPrimary: () => context.push(R.orderCreate),
        secondaryActions: isDesktop
            ? [
                IconButton(
                    icon: const Icon(Icons.refresh_outlined),
                    onPressed: _load,
                    tooltip: 'Refresh')
              ]
            : null,
      ),

      // Status filter chips
      filterBar: FilterBar<String>(
        options: _statuses,
        selected: _filter,
        onSelected: (s) {
          setState(() => _filter = s);
          _load();
        },
        labelBuilder: (s) => s == 'all' ? 'All' : _capitalize(s),
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      ),

      // FAB on mobile only — desktop has toolbar button
      fab: isDesktop
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push(R.orderCreate),
              icon: const Icon(Icons.add),
              label: const Text('New Order'),
            ),

      // Content
      content: AsyncStateView(
        loading: _loading,
        error: _error,
        empty: _filtered.isEmpty && !_loading,
        emptyIcon: Icons.shopping_bag_outlined,
        emptyMessage: _orders.isEmpty ? 'No orders yet' : 'No orders match',
        emptySub: _orders.isEmpty
            ? 'Create your first order to get started'
            : 'Try a different search or filter',
        onAction: _orders.isEmpty ? () => context.push(R.orderCreate) : null,
        actionLabel: 'New Order',
        onRetry: _load,
        child: ResponsiveLayout(
          mobile: (_) => _buildMobileList(),
          desktop: (_) => _buildDesktopTable(),
        ),
      ),
    );
  }

  // ── Desktop table ─────────────────────────────────────────────────────────

  Widget _buildDesktopTable() {
    return AppTable<Map<String, dynamic>>(
      columns: [
        AppTableColumn(
          label: 'Date',
          width: 100,
          cellBuilder: (o) {
            final date = DateTime.tryParse(o['created_at'] as String? ?? '');
            return Text(
              date != null ? DateFormat('d MMM y').format(date) : '—',
              style: const TextStyle(fontSize: 13, color: kTextSub),
            );
          },
        ),
        AppTableColumn(
          label: 'Retailer',
          flex: 3,
          cellBuilder: (o) {
            final r = o['retailers'] as Map<String, dynamic>?;
            return Text(
              r?['shop_name'] as String? ?? '—',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: kTextMain),
              overflow: TextOverflow.ellipsis,
            );
          },
        ),
        AppTableColumn(
          label: 'Birds',
          width: 80,
          alignment: Alignment.centerRight,
          cellBuilder: (o) {
            final birds = (o['estimated_birds'] as num?)?.toInt() ?? 0;
            return Text(
              birds > 0 ? '$birds' : '—',
              style: const TextStyle(fontSize: 13, color: kTextSub),
            );
          },
        ),
        AppTableColumn(
          label: 'Weight',
          width: 90,
          alignment: Alignment.centerRight,
          cellBuilder: (o) {
            final kg = (o['total_quantity'] as num?)?.toDouble() ?? 0;
            return Text(
              kg > 0 ? Fmt.kg(kg) : '—',
              style: const TextStyle(fontSize: 13, color: kTextSub),
            );
          },
        ),
        AppTableColumn(
          label: 'Amount',
          width: 110,
          alignment: Alignment.centerRight,
          cellBuilder: (o) {
            final amt = (o['total_amount'] as num?)?.toDouble() ?? 0;
            return Text(
              amt > 0 ? Fmt.amount(amt) : '—',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: kTextMain,
              ),
            );
          },
        ),
        AppTableColumn(
          label: 'Status',
          width: 130,
          alignment: Alignment.center,
          cellBuilder: (o) =>
              StatusChip.order(o['status'] as String? ?? 'pending'),
        ),
        AppTableColumn(
          label: '',
          width: 40,
          alignment: Alignment.center,
          cellBuilder: (_) =>
              const Icon(Icons.chevron_right, size: 16, color: kTextHint),
        ),
      ],
      rows: _filtered,
      onRowTap: (o) => context.push(R.orderDetailPath(o['id'])),
      desktopPadding: const EdgeInsets.symmetric(horizontal: 16),
      emptyWidget: AsyncStateView(
        loading: false,
        empty: true,
        emptyIcon: Icons.shopping_bag_outlined,
        emptyMessage: _orders.isEmpty ? 'No orders yet' : 'No orders match',
        onAction: _orders.isEmpty ? () => context.push(R.orderCreate) : null,
        actionLabel: 'New Order',
        child: const SizedBox.shrink(),
      ),
      footerWidget: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          '${_filtered.length} of ${_orders.length} orders',
          style: const TextStyle(fontSize: 12, color: kTextHint),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  // ── Mobile card list ──────────────────────────────────────────────────────

  Widget _buildMobileList() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: _filtered.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _OrderCard(order: _filtered[i]),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _capitalize(String s) => s
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

// ── Mobile order card ─────────────────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
  });

  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final retailer = order['retailers'] as Map<String, dynamic>?;
    final status = order['status'] as String? ?? 'pending';
    final date = DateTime.tryParse(order['created_at'] as String? ?? '');
    final amount = (order['total_amount'] as num?)?.toDouble() ?? 0;
    final birds = (order['estimated_birds'] as num?)?.toInt() ?? 0;
    final weight = (order['total_quantity'] as num?)?.toDouble() ?? 0;
    final statusColor = SC.order(status);
    final shopName = retailer?['shop_name'] as String? ?? 'Unknown Retailer';

    return InkWell(
      onTap: () => context.push(R.orderDetailPath(order['id'])),
      borderRadius: BorderRadius.circular(kRadiusCard),
      child: Container(
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border: Border.all(color: kBorderLight.withValues(alpha: 0.6)),
          boxShadow: kCardShadow,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Top: status accent bar + header ──────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.04),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(kRadiusCard)),
              border: Border(
                  bottom:
                      BorderSide(color: kBorderLight.withValues(alpha: 0.5))),
            ),
            child: Row(children: [
              // Avatar
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [kNavy, kNavyMid],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                    child: Text(
                  shopName.isNotEmpty ? shopName[0].toUpperCase() : '?',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: kGoldLight),
                )),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(shopName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: kNavy,
                            letterSpacing: -0.3)),
                    if (date != null)
                      Text(
                          DateFormat('d MMM y · h:mm a').format(date.toLocal()),
                          style: const TextStyle(
                              fontSize: 11,
                              color: kTextHint,
                              fontWeight: FontWeight.w500)),
                  ])),
              StatusChip.order(status, size: StatusChipSize.small),
            ]),
          ),

          // ── Bottom: stats row ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(children: [
              if (birds > 0)
                _stat(Icons.egg_alt_outlined, '$birds birds', kNavy),
              if (weight > 0) ...[
                const SizedBox(width: 14),
                _stat(Icons.scale_outlined, '${weight.toStringAsFixed(1)} kg',
                    Colors.teal),
              ],
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: kNavy,
                  borderRadius: BorderRadius.circular(kRadiusChip),
                ),
                child: Text(Fmt.amount(amount),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: kGoldLight)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _stat(IconData icon, String label, Color color) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color.withValues(alpha: 0.7)),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ]);
}
