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
import '../../../shared/widgets/tables/app_table.dart';
import '../../../shared/widgets/web/web.dart';

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

  // Web table state
  Map<String, int> _counts = {};
  String _sortKey = 'date';
  bool _sortAsc = false;
  bool _dense = true;
  int _page = 0;
  int _rowsPerPage = 25;

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
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      var q = _c
          .from('orders')
          .select(
          'id,status,estimated_birds,total_quantity,total_amount,created_at,order_date,'
              'retailers(shop_name),'
              'order_items(master_products(name))')
          .eq('trader_id', tid);
      if (_filter != 'all') q = q.eq('status', _filter);
      final data = await q.order('created_at', ascending: false).limit(300);
      // Tab counts (web) — status column only, read-only
      final counts = <String, int>{};
      try {
        final st = await _c.from('orders').select('status')
            .eq('trader_id', tid).limit(10000);
        for (final r in st) {
          final s = r['status'] as String? ?? '';
          counts[s] = (counts[s] ?? 0) + 1;
          counts['all'] = (counts['all'] ?? 0) + 1;
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _orders = List<Map<String, dynamic>>.from(data);
        _filtered = List.from(_orders);
        _counts = counts;
        _page = 0;
        _loading = false;
      });
      _applySearch(_searchCtrl.text);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDesktop = context.isDesktop;
    if (isDesktop) return _buildWebPage();

    return ListScreenScaffold(
      // AppBar only shown on mobile/tablet — desktop topbar handles title
      appBar: isDesktop
          ? null
          : AppBar(
        title: const Text('Orders'),
        actions: [
          IconButton(
              icon: const Icon(Icons.storefront_outlined),
              tooltip: 'In-House Sale',
              onPressed: () => context.push(R.inHouseSale)),
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
              icon: const Icon(Icons.storefront_outlined),
              onPressed: () => context.push(R.inHouseSale),
              tooltip: 'In-House Sale'),
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
        ),
      ),
    );
  }

  // ── Web page (desktop) ────────────────────────────────────────────────────

  static const _webColumns = [
    WebColumn('Date & Time', width: 165, sortKey: 'date'),
    WebColumn('Retailer', flex: 3, sortKey: 'retailer'),
    WebColumn('Product', width: 120, sortKey: 'product'),
    WebColumn('Birds', width: 90, sortKey: 'birds', align: TextAlign.right),
    WebColumn('Weight', width: 110, sortKey: 'weight', align: TextAlign.right),
    WebColumn('Amount', width: 130, sortKey: 'amount', align: TextAlign.right),
    WebColumn('Status', width: 150, align: TextAlign.center),
    WebColumn('Action', width: 80, align: TextAlign.center),
  ];

  Comparable<Object> _sortValue(Map<String, dynamic> o) {
    switch (_sortKey) {
      case 'retailer':
        return ((o['retailers'] as Map?)?['shop_name'] as String? ?? '')
            .toLowerCase();
      case 'product':
        return _OrderCard._productLabel(o).toLowerCase();
      case 'birds':
        return (o['estimated_birds'] as num?) ?? 0;
      case 'weight':
        return (o['total_quantity'] as num?) ?? 0;
      case 'amount':
        return (o['total_amount'] as num?) ?? 0;
      case 'date':
      default:
        return o['created_at'] as String? ?? '';
    }
  }

  void _sort(String key) => setState(() {
    if (_sortKey == key) {
      _sortAsc = !_sortAsc;
    } else {
      _sortKey = key;
      _sortAsc = true;
    }
    _page = 0;
  });

  Widget _webCell(Map<String, dynamic> o, int col) {
    switch (col) {
      case 0:
        final date = DateTime.tryParse(o['created_at'] as String? ?? '');
        return Text(
          date != null ? DateFormat('d MMM y, h:mm a').format(date.toLocal()) : '—',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, color: WebColors.text2),
        );
      case 1:
        final r   = o['retailers'] as Map<String, dynamic>?;
        final name = r?['shop_name'] as String? ?? '—';
        return Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5,
                fontWeight: FontWeight.w600, color: WebColors.text1));
      case 2:
        final lbl = _OrderCard._productLabel(o);
        return lbl.isEmpty
            ? const Text('—', style: WebText.caption)
            : WebLabel(lbl, color: _OrderCard._productColor(lbl));
      case 3:
        final birds = (o['estimated_birds'] as num?)?.toInt() ?? 0;
        return Text(birds > 0 ? '$birds' : '—',
            style: const TextStyle(fontSize: 13.5, color: WebColors.text2));
      case 4:
        final kg = (o['total_quantity'] as num?)?.toDouble() ?? 0;
        return Text(kg > 0 ? Fmt.kg(kg) : '—',
            style: const TextStyle(fontSize: 13.5, color: WebColors.text2));
      case 5:
        final amt = (o['total_amount'] as num?)?.toDouble() ?? 0;
        return Text(amt > 0 ? Fmt.amount(amt) : '—',
            style: const TextStyle(fontSize: 13.5,
                fontWeight: FontWeight.w700, color: WebColors.text1));
      case 6:
        final s = o['status'] as String? ?? 'pending';
        return WebLabel(_capitalize(s), color: SC.order(s));
      default:
        return WebIconButton(
          icon: Icons.visibility_outlined,
          tooltip: 'View order',
          size: 32,
          outlined: false,
          onTap: () => context.push(R.orderDetailPath(o['id'])),
        );
    }
  }

  Widget _buildWebPage() {
    final rows = [..._filtered]..sort((a, b) {
      final c = Comparable.compare(_sortValue(a), _sortValue(b));
      return _sortAsc ? c : -c;
    });
    final lastPage = rows.isEmpty ? 0 : (rows.length - 1) ~/ _rowsPerPage;
    final page = _page.clamp(0, lastPage);
    final pageRows =
        rows.skip(page * _rowsPerPage).take(_rowsPerPage).toList();

    return ColoredBox(
      color: WebColors.pageBg,
      child: SingleChildScrollView(
        padding: WebSpace.page,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PageBreadcrumbsHeader(
              title: 'Orders',
              subtitle: 'Track and manage every customer order',
              crumbs: const [
                Crumb('Dashboard', R.dashboard),
                Crumb('Orders'),
              ],
              action: Row(mainAxisSize: MainAxisSize.min, children: [
                WebIconButton(
                    icon: Icons.refresh_rounded,
                    tooltip: 'Refresh',
                    onTap: _load),
                const SizedBox(width: 8),
                WebButton(
                  label: 'In-House Sale',
                  icon: Icons.storefront_outlined,
                  outlined: true,
                  onPressed: () => context.push(R.inHouseSale),
                ),
                const SizedBox(width: 8),
                WebButton(
                  label: 'New Order',
                  icon: Icons.add_rounded,
                  onPressed: () => context.push(R.orderCreate),
                ),
              ]),
            ),
            WebListCard(children: [
              WebListTabs(
                tabs: [
                  for (final s in _statuses)
                    WebTab(s == 'all' ? 'All' : _capitalize(s),
                        count: _counts.isEmpty ? null : (_counts[s] ?? 0),
                        color: s == 'all' ? null : SC.order(s)),
                ],
                selected: _statuses.indexOf(_filter),
                onChanged: (i) {
                  setState(() => _filter = _statuses[i]);
                  _load();
                },
              ),
              WebListToolbar(
                search: WebSearchField(
                  controller: _searchCtrl,
                  hint: 'Search by shop name or order ID…',
                  debounce: const Duration(milliseconds: 250),
                  onChanged: (v) {
                    _applySearch(v);
                    setState(() => _page = 0);
                  },
                ),
                trailing: [
                  Text('${_filtered.length} of ${_orders.length} orders',
                      style: WebText.caption),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(WebSpace.xl),
                  child: AsyncStateView(
                    loading: false,
                    error: _error,
                    onRetry: _load,
                    child: const SizedBox.shrink(),
                  ),
                )
              else
                WebDataTable<Map<String, dynamic>>(
                  columns: _webColumns,
                  rows: pageRows,
                  cellBuilder: _webCell,
                  onRowTap: (o) => context.push(R.orderDetailPath(o['id'])),
                  sortKey: _sortKey,
                  sortAscending: _sortAsc,
                  onSort: _sort,
                  dense: _dense,
                  loading: _loading,
                  emptyText:
                      _orders.isEmpty ? 'No orders yet' : 'No orders match',
                  emptyAction: _orders.isEmpty
                      ? WebButton(
                          label: 'New Order',
                          icon: Icons.add_rounded,
                          onPressed: () => context.push(R.orderCreate))
                      : null,
                ),
              WebTablePagination(
                page: page,
                rowsPerPage: _rowsPerPage,
                total: rows.length,
                onPage: (p) => setState(() => _page = p),
                onRowsPerPage: (n) =>
                    setState(() { _rowsPerPage = n; _page = 0; }),
                dense: _dense,
                onDense: (v) => setState(() => _dense = v),
              ),
            ]),
          ]),
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
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) => SerialNumbered(
            serial: i + 1, child: _OrderCard(order: _filtered[i])),
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

  // ── Product helpers (display-only, read-only) ─────────────────────────────
  static String _productLabel(Map<String, dynamic> o) {
    final items =
        (o['order_items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final names = items
        .map((i) => (i['master_products'] as Map?)?['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();
    if (names.isEmpty) return '';
    return names.length == 1 ? names.first : 'Multi-product';
  }

  static Color _productColor(String label) {
    final l = label.toLowerCase();
    if (l.contains('country')) return const Color(0xFF6D4C41); // brown
    if (l.contains('quail'))   return Colors.purple;
    if (l.contains('multi'))   return Colors.indigo;
    return const Color(0xFF00796B); // teal — broiler default
  }

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
                  gradient: const LinearGradient(
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
                        const SizedBox(height: 3),
                        Row(children: [
                          // ── Product chip (display-only, no logic change) ──────
                          Builder(builder: (_) {
                            final lbl = _productLabel(order);
                            if (lbl.isEmpty) return const SizedBox.shrink();
                            final c = _productColor(lbl);
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                  color: c.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                      color: c.withValues(alpha: 0.3))),
                              child: Text(lbl,
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: c)),
                            );
                          }),
                        ]),
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