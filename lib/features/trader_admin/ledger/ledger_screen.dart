import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/responsive_layout.dart';
import '../../../shared/widgets/cards/metric_card.dart';
import '../../../shared/widgets/common/async_state_view.dart';
import '../../../shared/widgets/filters/filter_bar.dart';
import '../../../shared/widgets/filters/search_bar.dart' hide ListToolbar;
import '../../../shared/widgets/tables/app_table.dart';
import '../../../shared/widgets/web/web.dart';

class LedgerScreen extends ConsumerStatefulWidget {
  const LedgerScreen({super.key});
  @override
  ConsumerState<LedgerScreen> createState() => _S();
}

class _S extends ConsumerState<LedgerScreen> {
  final _c          = Supabase.instance.client;
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _list = [];
  bool    _loading = true;
  String? _error;
  String  _filter  = 'all';

  static const _filters = ['all', 'over_limit', 'overdue', 'healthy'];

  double get _totalOutstanding =>
      _list.fold(0.0, (s, r) => s + ((r['outstanding_amount'] as num?)?.toDouble() ?? 0));

  List<Map<String, dynamic>> get _filtered {
    List<Map<String, dynamic>> base = _list;

    // Apply risk filter
    if (_filter != 'all') {
      base = base.where((r) {
        final rs = r['risk_status'] as String? ?? 'healthy';
        if (_filter == 'over_limit') return rs == 'over_limit' || rs == 'near_limit';
        if (_filter == 'overdue')    return rs == 'overdue_15d' || rs == 'overdue_30d';
        if (_filter == 'healthy')    return rs == 'healthy';
        return true;
      }).toList();
    }

    // Apply search
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return base;
    return base.where((r) =>
    (r['shop_name']  as String? ?? '').toLowerCase().contains(q) ||
        (r['owner_name'] as String? ?? '').toLowerCase().contains(q),
    ).toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final res = await _c.rpc('get_retailer_risk_summary',
          params: {'p_trader_id': tid});
      if (!mounted) return;
      setState(() {
        _list    = List<Map<String, dynamic>>.from(
            (res as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Color _riskColor(String? status) => switch (status) {
    'over_limit'  => Colors.red,
    'near_limit'  => Colors.orange,
    'overdue_15d' => Colors.deepOrange,
    'overdue_30d' => Colors.red,
    _             => Colors.green,
  };

  String _riskLabel(String? status) => switch (status) {
    'over_limit'  => 'Over Limit',
    'near_limit'  => 'Near Limit',
    'overdue_15d' => 'Overdue 15d',
    'overdue_30d' => 'Overdue 30d',
    _             => 'Healthy',
  };

  @override
  Widget build(BuildContext context) {
    final isDesktop  = context.isDesktop;
    final overLimit  = _list.where((r) => r['risk_status'] == 'over_limit').length;
    final nearLimit  = _list.where((r) => r['risk_status'] == 'near_limit').length;
    final overdue    = _list.where((r) {
      final s = r['risk_status'] as String? ?? '';
      return s == 'overdue_15d' || s == 'overdue_30d';
    }).length;
    final rows = _filtered;
    if (isDesktop) return _buildWebPage();

    return ListScreenScaffold(
      appBar: isDesktop ? null : AppBar(
        title: const Text('Ledger'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),

      toolbar: ListToolbar(
        searchController: _searchCtrl,
        searchHint:       'Search by retailer name…',
        onSearch:         (_) { if (mounted) setState(() {}); },
        onClearSearch:    () { _searchCtrl.clear(); if (mounted) setState(() {}); },
        secondaryActions: isDesktop
            ? [IconButton(icon: const Icon(Icons.refresh_outlined),
            onPressed: _load, tooltip: 'Refresh')]
            : null,
      ),

      summaryStrip: MetricStrip(
        metrics: [
          MetricCard(
            label: 'Total Outstanding',
            value: Fmt.amount(_totalOutstanding),
            color: _totalOutstanding > 0 ? Colors.orange : Colors.green,
            icon:  Icons.account_balance_wallet_outlined,
          ),
          MetricCard(
            label: 'Retailers',
            value: '${_list.length}',
            icon:  Icons.storefront_outlined,
          ),
          if (overLimit > 0)
            MetricCard(
              label: 'Over Limit',
              value: '$overLimit',
              color: Colors.red,
              icon:  Icons.warning_rounded,
            ),
          if (overdue > 0)
            MetricCard(
              label: 'Overdue',
              value: '$overdue',
              color: Colors.deepOrange,
              icon:  Icons.schedule_outlined,
            ),
        ],
      ),

      filterBar: FilterBar<String>(
        options:      _filters,
        selected:     _filter,
        onSelected:   (f) => setState(() => _filter = f),
        labelBuilder: (f) => switch (f) {
          'over_limit' => 'Over Limit',
          'overdue'    => 'Overdue',
          'healthy'    => 'Healthy',
          _            => 'All',
        },
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      ),

      content: AsyncStateView(
        loading:      _loading,
        error:        _error,
        empty:        rows.isEmpty && !_loading,
        emptyIcon:    Icons.account_balance_wallet_outlined,
        emptyMessage: _list.isEmpty ? 'No retailers found' : 'No retailers match filter',
        onRetry:      _load,
        child: ResponsiveLayout(
          mobile:  (_) => _buildMobileList(rows),
        ),
      ),
    );
  }

  // ── Web page (desktop) ────────────────────────────────────────────────────

  String _sortKey = 'outstanding';
  bool _sortAsc = false;
  bool _dense = true;
  int _page = 0;
  int _rowsPerPage = 25;

  static const _webColumns = [
    WebColumn('Retailer', flex: 3, sortKey: 'retailer'),
    WebColumn('Owner', flex: 2),
    WebColumn('Outstanding', width: 140, sortKey: 'outstanding',
        align: TextAlign.right),
    WebColumn('Credit Limit', width: 130, sortKey: 'limit',
        align: TextAlign.right),
    WebColumn('Credit Used', width: 160),
    WebColumn('Last Payment', width: 120, sortKey: 'days',
        align: TextAlign.right),
    WebColumn('Risk', width: 130, align: TextAlign.center),
    WebColumn('Action', width: 80, align: TextAlign.center),
  ];

  Comparable<Object> _sortValue(Map<String, dynamic> r) {
    switch (_sortKey) {
      case 'retailer':
        return (r['shop_name'] as String? ?? '').toLowerCase();
      case 'limit':
        return (r['credit_limit'] as num?) ?? 0;
      case 'days':
        return (r['days_since_payment'] as num?) ?? -1;
      default:
        return (r['outstanding_amount'] as num?) ?? 0;
    }
  }

  void _openLedger(Map<String, dynamic> r) =>
      context.push(R.retailerLedgerPath(r['retailer_id'] ?? r['id']));

  Widget _webCell(Map<String, dynamic> r, int col) {
    final amt = (r['outstanding_amount'] as num?)?.toDouble() ?? 0;
    final lim = (r['credit_limit'] as num?)?.toDouble() ?? 0;
    switch (col) {
      case 0:
        final name = r['shop_name'] as String? ?? '—';
        return Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: WebColors.text1));
      case 1:
        return Text(r['owner_name'] as String? ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: WebColors.text2));
      case 2:
        return Text(amt > 0 ? Fmt.amount(amt) : '—',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700,
                color: amt > 0 ? WebColors.warning : WebColors.text3));
      case 3:
        return Text(lim > 0 ? Fmt.amount(lim) : '—',
            style: const TextStyle(fontSize: 13.5, color: WebColors.text2));
      case 4:
        if (lim <= 0) return const Text('—', style: WebText.caption);
        final pct = (amt / lim).clamp(0.0, 1.0);
        final c = pct >= 1 ? WebColors.error
            : pct >= 0.8 ? WebColors.warning : WebColors.success;
        return Row(children: [
          Expanded(child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: pct, minHeight: 6,
                backgroundColor: WebColors.divider,
                valueColor: AlwaysStoppedAnimation(c)),
          )),
          const SizedBox(width: 8),
          SizedBox(width: 40, child: Text('${(amt / lim * 100).toStringAsFixed(0)}%',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                  color: c))),
        ]);
      case 5:
        final days = (r['days_since_payment'] as num?)?.toInt();
        return Text(days != null ? '${days}d ago' : '—',
            style: TextStyle(fontSize: 13,
                color: days != null && days > 30
                    ? WebColors.error : WebColors.text2));
      case 6:
        final s = r['risk_status'] as String? ?? 'healthy';
        return WebLabel(_riskLabel(s), color: _riskColor(s), dot: true);
      default:
        return WebIconButton(
          icon: Icons.visibility_outlined,
          tooltip: 'Open ledger',
          size: 32,
          outlined: false,
          onTap: () => _openLedger(r),
        );
    }
  }

  Widget _buildWebPage() {
    final overLimit = _list.where((r) => r['risk_status'] == 'over_limit').length;
    final nearLimit = _list.where((r) => r['risk_status'] == 'near_limit').length;
    final overdue = _list.where((r) {
      final s = r['risk_status'] as String? ?? '';
      return s == 'overdue_15d' || s == 'overdue_30d';
    }).length;
    final healthy = _list.where((r) =>
        (r['risk_status'] as String? ?? 'healthy') == 'healthy').length;
    final counts = {
      'all': _list.length,
      'over_limit': overLimit + nearLimit,
      'overdue': overdue,
      'healthy': healthy,
    };

    final rows = [..._filtered]..sort((a, b) {
      final c = Comparable.compare(_sortValue(a), _sortValue(b));
      return _sortAsc ? c : -c;
    });
    final lastPage = rows.isEmpty ? 0 : (rows.length - 1) ~/ _rowsPerPage;
    final page = _page.clamp(0, lastPage);
    final pageRows =
        rows.skip(page * _rowsPerPage).take(_rowsPerPage).toList();

    return WebPage(
      header: PageBreadcrumbsHeader(
        title: 'Ledger',
        subtitle: 'Outstanding balances and credit risk by retailer',
        crumbs: const [Crumb('Dashboard', R.dashboard), Crumb('Ledger')],
        action: WebIconButton(icon: Icons.refresh_rounded,
            tooltip: 'Refresh', onTap: _load),
      ),
      children: [
        WebKpiRow(children: [
          WebKpiCard(label: 'Total Outstanding',
              value: Fmt.amount(_totalOutstanding),
              icon: Icons.account_balance_wallet_outlined,
              color: _totalOutstanding > 0
                  ? WebColors.warning : WebColors.success),
          WebKpiCard(label: 'Retailers', value: '${_list.length}',
              icon: Icons.storefront_outlined, color: WebColors.navy),
          WebKpiCard(label: 'Over / Near Limit',
              value: '${overLimit + nearLimit}',
              sub: '$overLimit over · $nearLimit near',
              icon: Icons.warning_rounded, color: WebColors.error),
          WebKpiCard(label: 'Overdue', value: '$overdue',
              sub: '15+ days without payment',
              icon: Icons.schedule_outlined, color: WebColors.gold),
        ]),
        const SizedBox(height: WebSpace.lg),
        WebListCard(children: [
          WebListTabs(
            tabs: [
              for (final f in _filters)
                WebTab(switch (f) {
                  'over_limit' => 'Over Limit',
                  'overdue'    => 'Overdue',
                  'healthy'    => 'Healthy',
                  _            => 'All',
                }, count: counts[f], color: switch (f) {
                  'over_limit' => WebColors.error,
                  'overdue'    => WebColors.warning,
                  'healthy'    => WebColors.success,
                  _            => null,
                }),
            ],
            selected: _filters.indexOf(_filter),
            onChanged: (i) => setState(() {
              _filter = _filters[i];
              _page = 0;
            }),
          ),
          WebListToolbar(
            search: WebSearchField(
              controller: _searchCtrl,
              hint: 'Search by retailer name…',
              debounce: const Duration(milliseconds: 200),
              onChanged: (_) => setState(() => _page = 0),
            ),
            trailing: [
              Text('${rows.length} of ${_list.length} retailers',
                  style: WebText.caption),
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
              onRowTap: _openLedger,
              sortKey: _sortKey,
              sortAscending: _sortAsc,
              onSort: (k) => setState(() {
                if (_sortKey == k) {
                  _sortAsc = !_sortAsc;
                } else {
                  _sortKey = k;
                  _sortAsc = k == 'retailer';
                }
                _page = 0;
              }),
              dense: _dense,
              loading: _loading,
              emptyText: _list.isEmpty
                  ? 'No retailers found' : 'No retailers match filter',
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
      ],
    );
  }

  // ── Mobile list ───────────────────────────────────────────────────────────

  Widget _buildMobileList(List<Map<String, dynamic>> rows) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding:          const EdgeInsets.fromLTRB(16, 8, 16, kBottomNavClearance),
        itemCount:        rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder:      (_, i)  => _LedgerCard(
          item:       rows[i],
          riskColor:  _riskColor(rows[i]['risk_status'] as String?),
          riskLabel:  _riskLabel(rows[i]['risk_status'] as String?),
        ),
      ),
    );
  }
}

// ── Mobile ledger card ────────────────────────────────────────────────────────

class _LedgerCard extends StatelessWidget {
  const _LedgerCard({
    required this.item,
    required this.riskColor,
    required this.riskLabel,
  });
  final Map<String, dynamic> item;
  final Color riskColor;
  final String riskLabel;

  Widget _chip(String label, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
    child: Text(label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
  );

  @override
  Widget build(BuildContext context) {
    final amt    = (item['outstanding_amount'] as num?)?.toDouble() ?? 0;
    final limit  = (item['credit_limit']       as num?)?.toDouble() ?? 0;
    final days   = (item['days_since_payment'] as num?)?.toInt();
    final status = item['risk_status'] as String? ?? 'healthy';
    final isAtRisk = status != 'healthy';

    return InkWell(
      onTap: () => context.push(
          R.retailerLedgerPath(item['retailer_id'] ?? item['id'])),
      borderRadius: BorderRadius.circular(kRadiusCard),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:        kSurface,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border: Border.all(
              color: isAtRisk ? riskColor.withValues(alpha: 0.35) : kBorderLight,
              width: isAtRisk ? 1.5 : 0.8),
          boxShadow: kCardShadow,
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item['shop_name'] as String? ?? '—',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: kNavy)),
            if (item['owner_name'] != null) ...[
              const SizedBox(height: 2),
              Text(item['owner_name'] as String,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: kTextSub)),
            ],
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (isAtRisk) _chip(riskLabel, riskColor),
              if (days != null)
                Text('${days}d since payment',
                    style: TextStyle(
                      fontSize: 11,
                      color: days > 30 ? Colors.red : kTextSub,
                    )),
            ]),
          ])),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 90),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(Fmt.amount(amt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w900,
                    color: amt > 0 ? Colors.orange : Colors.green,
                  )),
              if (limit > 0)
                Text('Limit: ${Fmt.amount(limit)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: kTextHint)),
              const SizedBox(height: 4),
              const Icon(Icons.chevron_right, color: kTextHint, size: 18),
            ]),
          ),
        ]),
      ),
    );
  }
}