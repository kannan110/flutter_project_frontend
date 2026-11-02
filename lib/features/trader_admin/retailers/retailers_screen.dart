import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/responsive_layout.dart';
import '../../../shared/widgets/common/async_state_view.dart';
import '../../../shared/widgets/tables/app_table.dart';
import '../../../shared/widgets/web/web.dart';

class RetailersScreen extends ConsumerStatefulWidget {
  const RetailersScreen({super.key});

  @override
  ConsumerState<RetailersScreen> createState() => _S();
}

class _S extends ConsumerState<RetailersScreen> {
  final _c = Supabase.instance.client;
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _list = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  String? _error;

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
      setState(() => _filtered = List.from(_list));
      return;
    }
    final lower = q.toLowerCase();
    setState(() => _filtered = _list
        .where(
          (r) =>
              (r['shop_name'] as String? ?? '').toLowerCase().contains(lower) ||
              (r['owner_name'] as String? ?? '')
                  .toLowerCase()
                  .contains(lower) ||
              (r['phone'] as String? ?? '').toLowerCase().contains(lower) ||
              (r['address'] as String? ?? '').toLowerCase().contains(lower),
        )
        .toList());
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
      final data = await _c
          .from('retailers')
          .select(
              'id,shop_name,owner_name,phone,address,risk_level,is_active,is_blocked')
          .eq('trader_id', tid)
          .order('shop_name');
      if (!mounted) return;
      setState(() {
        _list = List<Map<String, dynamic>>.from(data);
        _filtered = List.from(_list);
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

  @override
  Widget build(BuildContext context) {
    final isDesktop = context.isDesktop;
    if (isDesktop) return _buildWebPage();

    return ListScreenScaffold(
      appBar: isDesktop
          ? null
          : AppBar(
              title: const Text('Retailers'),
              actions: [
                IconButton(
                    icon: const Icon(Icons.refresh_outlined), onPressed: _load)
              ],
            ),
      toolbar: ListToolbar(
        searchController: _searchCtrl,
        searchHint: 'Search by name, phone, address…',
        onSearch: _applySearch,
        onClearSearch: () {
          _searchCtrl.clear();
          _applySearch('');
        },
        primaryLabel: 'Add Retailer',
        primaryIcon: Icons.add_rounded,
        onPrimary: () => context.push(R.retailerCreate),
        secondaryActions: isDesktop
            ? [
                IconButton(
                    icon: const Icon(Icons.refresh_outlined),
                    onPressed: _load,
                    tooltip: 'Refresh')
              ]
            : null,
      ),
      fab: isDesktop
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push(R.retailerCreate),
              icon: const Icon(Icons.add),
              label: const Text('Add Retailer'),
            ),
      content: AsyncStateView(
        loading: _loading,
        error: _error,
        empty: _filtered.isEmpty && !_loading,
        emptyIcon: Icons.store_outlined,
        emptyMessage: _list.isEmpty ? 'No retailers yet' : 'No retailers match',
        emptySub:
            _list.isEmpty ? 'Add your first retailer to get started' : null,
        onAction: _list.isEmpty ? () => context.push(R.retailerCreate) : null,
        actionLabel: 'Add Retailer',
        onRetry: _load,
        child: ResponsiveLayout(
          mobile: (_) => _buildMobileList(),
        ),
      ),
    );
  }

  // ── Web page (desktop) ────────────────────────────────────────────────────

  static const _webTabs = ['all', 'active', 'risk', 'blocked', 'inactive'];
  String _webTab = 'all';
  String _sortKey = 'shop';
  bool _sortAsc = true;
  bool _dense = true;
  int _page = 0;
  int _rowsPerPage = 25;

  static const _webColumns = [
    WebColumn('Shop Name', flex: 3, sortKey: 'shop'),
    WebColumn('Owner', flex: 2, sortKey: 'owner'),
    WebColumn('Phone', width: 150),
    WebColumn('Address', flex: 3),
    WebColumn('Status', width: 140, align: TextAlign.center),
    WebColumn('Action', width: 80, align: TextAlign.center),
  ];

  bool _blocked(Map<String, dynamic> r) => r['is_blocked'] as bool? ?? false;
  bool _active(Map<String, dynamic> r) => r['is_active'] as bool? ?? true;
  String _risk(Map<String, dynamic> r) => r['risk_level'] as String? ?? 'low';

  bool _inTab(Map<String, dynamic> r, String t) => switch (t) {
    'active'   => _active(r) && !_blocked(r),
    'risk'     => !_blocked(r) && (_risk(r) == 'high' || _risk(r) == 'medium'),
    'blocked'  => _blocked(r),
    'inactive' => !_active(r),
    _          => true,
  };

  Widget _webCell(Map<String, dynamic> r, int col) {
    switch (col) {
      case 0:
        final name = r['shop_name'] as String? ?? '—';
        return Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600,
                color: _active(r) ? WebColors.text1 : WebColors.text3));
      case 1:
        return Text(r['owner_name'] as String? ?? '—', maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5, color: WebColors.text2));
      case 2:
        return Text(r['phone'] as String? ?? '—',
            style: const TextStyle(fontSize: 13.5, color: WebColors.text2));
      case 3:
        return Text(r['address'] as String? ?? '—', maxLines: 1,
            overflow: TextOverflow.ellipsis, style: WebText.caption);
      case 4:
        if (_blocked(r)) {
          return const WebLabel('Blocked', color: WebColors.error, dot: true);
        }
        if (!_active(r)) {
          return const WebLabel('Inactive', color: WebColors.text3, dot: true);
        }
        if (_risk(r) == 'high') {
          return const WebLabel('High Risk', color: WebColors.error);
        }
        if (_risk(r) == 'medium') {
          return const WebLabel('Med Risk', color: WebColors.warning);
        }
        return const WebLabel('Active', color: WebColors.success, dot: true);
      default:
        return WebIconButton(
          icon: Icons.visibility_outlined,
          tooltip: 'View retailer',
          size: 32,
          outlined: false,
          onTap: () => context.push(R.retailerDetailPath(r['id'])),
        );
    }
  }

  Widget _buildWebPage() {
    int count(String t) => _filtered.where((r) => _inTab(r, t)).length;
    final rows = _filtered.where((r) => _inTab(r, _webTab)).toList()
      ..sort((a, b) {
        final k = _sortKey == 'owner' ? 'owner_name' : 'shop_name';
        final c = (a[k] as String? ?? '').toLowerCase()
            .compareTo((b[k] as String? ?? '').toLowerCase());
        return _sortAsc ? c : -c;
      });
    final lastPage = rows.isEmpty ? 0 : (rows.length - 1) ~/ _rowsPerPage;
    final page = _page.clamp(0, lastPage);
    final pageRows =
        rows.skip(page * _rowsPerPage).take(_rowsPerPage).toList();

    final activeAll = _list.where((r) => _inTab(r, 'active')).length;
    final riskAll = _list.where((r) => _inTab(r, 'risk')).length;
    final blockedAll = _list.where(_blocked).length;

    return WebPage(
      header: PageBreadcrumbsHeader(
        title: 'Retailers',
        subtitle: 'Your customers — contact details, status and risk',
        crumbs: const [Crumb('Dashboard', R.dashboard), Crumb('Retailers')],
        action: Row(mainAxisSize: MainAxisSize.min, children: [
          WebIconButton(icon: Icons.refresh_rounded, tooltip: 'Refresh',
              onTap: _load),
          const SizedBox(width: 8),
          WebButton(
            label: 'Add Retailer',
            icon: Icons.add_rounded,
            onPressed: () => context.push(R.retailerCreate),
          ),
        ]),
      ),
      children: [
        WebKpiRow(children: [
          WebKpiCard(label: 'Total Retailers', value: '${_list.length}',
              icon: Icons.storefront_outlined, color: WebColors.navy),
          WebKpiCard(label: 'Active', value: '$activeAll',
              icon: Icons.check_circle_outline, color: WebColors.success),
          WebKpiCard(label: 'High / Medium Risk', value: '$riskAll',
              icon: Icons.warning_amber_rounded, color: WebColors.warning),
          WebKpiCard(label: 'Blocked', value: '$blockedAll',
              icon: Icons.block_rounded, color: WebColors.error),
        ]),
        const SizedBox(height: WebSpace.lg),
        WebListCard(children: [
          WebListTabs(
            tabs: [
              WebTab('All', count: count('all')),
              WebTab('Active', count: count('active'), color: WebColors.success),
              WebTab('At Risk', count: count('risk'), color: WebColors.warning),
              WebTab('Blocked', count: count('blocked'), color: WebColors.error),
              WebTab('Inactive', count: count('inactive'), color: WebColors.text3),
            ],
            selected: _webTabs.indexOf(_webTab),
            onChanged: (i) => setState(() { _webTab = _webTabs[i]; _page = 0; }),
          ),
          WebListToolbar(
            search: WebSearchField(
              controller: _searchCtrl,
              hint: 'Search by name, phone, address…',
              debounce: const Duration(milliseconds: 250),
              onChanged: (v) { _applySearch(v); setState(() => _page = 0); },
            ),
            trailing: [
              Text('${rows.length} retailers', style: WebText.caption),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(WebSpace.xl),
              child: AsyncStateView(loading: false, error: _error,
                  onRetry: _load, child: const SizedBox.shrink()),
            )
          else
            WebDataTable<Map<String, dynamic>>(
              columns: _webColumns,
              rows: pageRows,
              cellBuilder: _webCell,
              onRowTap: (r) => context.push(R.retailerDetailPath(r['id'])),
              sortKey: _sortKey,
              sortAscending: _sortAsc,
              onSort: (k) => setState(() {
                if (_sortKey == k) {
                  _sortAsc = !_sortAsc;
                } else {
                  _sortKey = k;
                  _sortAsc = true;
                }
                _page = 0;
              }),
              dense: _dense,
              loading: _loading,
              emptyText: _list.isEmpty ? 'No retailers yet' : 'No retailers match',
              emptyAction: _list.isEmpty
                  ? WebButton(label: 'Add Retailer', icon: Icons.add_rounded,
                      onPressed: () => context.push(R.retailerCreate))
                  : null,
            ),
          WebTablePagination(
            page: page,
            rowsPerPage: _rowsPerPage,
            total: rows.length,
            onPage: (p) => setState(() => _page = p),
            onRowsPerPage: (n) => setState(() { _rowsPerPage = n; _page = 0; }),
            dense: _dense,
            onDense: (v) => setState(() => _dense = v),
          ),
        ]),
      ],
    );
  }

  // ── Mobile card list ──────────────────────────────────────────────────────

  Widget _buildMobileList() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        itemCount: _filtered.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _RetailerCard(retailer: _filtered[i]),
      ),
    );
  }
}

// ── Mobile retailer card ──────────────────────────────────────────────────────

class _RetailerCard extends StatelessWidget {
  const _RetailerCard({required this.retailer});

  final Map<String, dynamic> retailer;

  @override
  Widget build(BuildContext context) {
    final risk = retailer['risk_level'] as String? ?? 'low';
    final blocked = retailer['is_blocked'] as bool? ?? false;
    final active = retailer['is_active'] as bool? ?? true;
    final shopName = retailer['shop_name'] as String? ?? '—';
    final ownerName = retailer['owner_name'] as String?;
    final phone = retailer['phone'] as String?;
    final outstanding =
        (retailer['outstanding_balance'] as num?)?.toDouble() ?? 0;

    // Accent colour by risk/status
    final Color accent = blocked
        ? Colors.red
        : risk == 'high'
            ? Colors.orange
            : risk == 'medium'
                ? Colors.amber.shade700
                : kNavy;

    return InkWell(
      onTap: () => context.push(R.retailerDetailPath(retailer['id'])),
      borderRadius: BorderRadius.circular(kRadiusCard),
      child: Container(
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border: Border.all(
              color: blocked
                  ? Colors.red.withValues(alpha: 0.35)
                  : risk == 'high'
                      ? Colors.orange.withValues(alpha: 0.35)
                      : kBorderLight.withValues(alpha: 0.6)),
          boxShadow: kCardShadow,
        ),
        child: IntrinsicHeight(
          child: Row(children: [
            // Left accent bar
            Container(
              width: 4,
              height: double.infinity,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(kRadiusCard)),
              ),
            ),
            const SizedBox(width: 14),
          // Avatar
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: blocked
                    ? [Colors.red.shade700, Colors.red.shade600]
                    : [kNavy, kNavyMid],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
                child: Text(
              shopName.isNotEmpty ? shopName[0].toUpperCase() : '?',
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w900, color: kGoldLight),
            )),
          ),
          const SizedBox(width: 14),
          // Info
          Expanded(
              child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(shopName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            color: active ? kNavy : kTextSub,
                            letterSpacing: -0.2))),
                if (blocked)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6)),
                    child: const Text('BLOCKED',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: Colors.red,
                            letterSpacing: 0.4)),
                  )
                else if (!active)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: kBgPage, borderRadius: BorderRadius.circular(6)),
                    child: const Text('INACTIVE',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: kTextHint,
                            letterSpacing: 0.4)),
                  )
                else if (risk == 'high')
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6)),
                    child: const Text('HIGH RISK',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: Colors.orange,
                            letterSpacing: 0.4)),
                  ),
              ]),
              if (ownerName != null) ...[
                const SizedBox(height: 3),
                Text(ownerName,
                    style: const TextStyle(
                        fontSize: 12,
                        color: kTextSub,
                        fontWeight: FontWeight.w600)),
              ],
              if (phone != null) ...[
                const SizedBox(height: 2),
                Row(children: [
                  const Icon(Icons.phone_outlined, size: 11, color: kTextHint),
                  const SizedBox(width: 4),
                  Text(phone,
                      style: const TextStyle(fontSize: 11, color: kTextHint)),
                ]),
              ],
            ]),
          )),
          // Outstanding + arrow
          if (outstanding > 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(Fmt.amount(outstanding),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: outstanding > 50000 ? Colors.red : kNavy)),
                const Text('pending',
                    style: TextStyle(fontSize: 9, color: kTextHint)),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(Icons.chevron_right_rounded,
                color: accent.withValues(alpha: 0.5), size: 20),
          ),
        ]),
      ),
    ),
    );
  }
}
