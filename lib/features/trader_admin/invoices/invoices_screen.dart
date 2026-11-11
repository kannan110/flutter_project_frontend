import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/responsive_layout.dart';
import '../../../shared/widgets/cards/metric_card.dart';
import '../../../shared/widgets/common/async_state_view.dart';
import '../../../shared/widgets/common/status_chip.dart';
import '../../../shared/widgets/filters/search_bar.dart';
import '../../../shared/widgets/tables/app_table.dart' hide ListToolbar;
import '../../../shared/widgets/web/web.dart';

class InvoicesScreen extends ConsumerStatefulWidget {
  const InvoicesScreen({super.key});
  @override
  ConsumerState<InvoicesScreen> createState() => _S();
}

class _S extends ConsumerState<InvoicesScreen> {
  final _c          = Supabase.instance.client;
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _list     = [];
  List<Map<String, dynamic>> _filtered = [];
  bool    _loading        = true;
  String? _error;
  double  _totalRevenue   = 0;
  double  _totalOutstanding = 0;

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
    if (q.trim().isEmpty) { setState(() => _filtered = List.from(_list)); return; }
    final lower = q.toLowerCase();
    setState(() => _filtered = _list.where((inv) {
      final r = inv['retailers'] as Map<String, dynamic>?;
      return (r?['shop_name']       as String? ?? '').toLowerCase().contains(lower) ||
          (inv['invoice_number'] as String? ?? '').toLowerCase().contains(lower);
    }).toList());
  }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null || !mounted) return;
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final data = await _c.from('invoices')
          .select('id,invoice_number,invoice_date,total_amount,collected_amount,'
          'balance_amount,status,bird_count,quantity_kg,price_per_kg,'
          'retailers(shop_name)')
          .eq('trader_id', tid)
          // Latest invoice number first (INV-YYYYMM-NNNNN sorts by text).
          .order('invoice_number', ascending: false)
          .limit(200);
      if (!mounted) return;
      final list = List<Map<String, dynamic>>.from(data);
      double rev = 0, out = 0;
      for (final inv in list) {
        // Cancelled invoices must not contribute to revenue/outstanding —
        // matches "Reports should use only the active (approved) invoice."
        if (inv['status'] == 'cancelled') continue;
        rev += (inv['total_amount']   as num?)?.toDouble() ?? 0;
        out += (inv['balance_amount'] as num?)?.toDouble() ?? 0;
      }
      setState(() {
        _list             = list;
        _filtered         = List.from(_list);
        _totalRevenue     = rev;
        _totalOutstanding = out;
        _loading          = false;
      });
      _applySearch(_searchCtrl.text);
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = context.isDesktop;
    if (isDesktop) return _buildWebPage();

    return ListScreenScaffold(
      appBar: isDesktop ? null : AppBar(
        title: const Text('Invoices'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),

      toolbar: ListToolbar(
        searchController: _searchCtrl,
        searchHint:       'Search by retailer or invoice number…',
        onSearch:         _applySearch,
        onClearSearch:    () { _searchCtrl.clear(); _applySearch(''); },
        secondaryActions: isDesktop
            ? [IconButton(icon: const Icon(Icons.refresh_outlined), onPressed: _load, tooltip: 'Refresh')]
            : null,
      ),

      // Summary strip — revenue and outstanding
      summaryStrip: MetricStrip(
        metrics: [
          MetricCard(
            label: 'Total Revenue',
            value: Fmt.amount(_totalRevenue),
            color: kPrimary,
            icon:  Icons.trending_up_rounded,
          ),
          MetricCard(
            label: 'Outstanding',
            value: Fmt.amount(_totalOutstanding),
            color: _totalOutstanding > 0 ? Colors.orange : Colors.green,
            icon:  Icons.account_balance_wallet_outlined,
          ),
          MetricCard(
            label: 'Invoices',
            value: '${_filtered.length}',
            icon:  Icons.receipt_long_outlined,
          ),
        ],
      ),

      content: AsyncStateView(
        loading:      _loading,
        error:        _error,
        empty:        _filtered.isEmpty && !_loading,
        emptyIcon:    Icons.receipt_long_outlined,
        emptyMessage: _list.isEmpty ? 'No invoices yet' : 'No invoices match',
        onRetry:      _load,
        child: ResponsiveLayout(
          mobile:  (_) => _buildMobileList(),
        ),
      ),
    );
  }

  // ── Web page (desktop) ────────────────────────────────────────────────────

  static const _webTabs = ['all', 'due', 'paid', 'cancelled'];
  String _webTab = 'all';
  String _sortKey = 'date';
  bool _sortAsc = false;
  bool _dense = true;
  int _page = 0;
  int _rowsPerPage = 25;

  static const _webColumns = [
    WebColumn('Invoice #', width: 130, sortKey: 'number'),
    WebColumn('Date', width: 120, sortKey: 'date'),
    WebColumn('Retailer', flex: 3, sortKey: 'retailer'),
    WebColumn('Birds', width: 90, sortKey: 'birds', align: TextAlign.right),
    WebColumn('Qty', width: 110, sortKey: 'kg', align: TextAlign.right),
    WebColumn('Total', width: 130, sortKey: 'total', align: TextAlign.right),
    WebColumn('Balance', width: 130, sortKey: 'balance', align: TextAlign.right),
    WebColumn('Status', width: 140, align: TextAlign.center),
    WebColumn('Action', width: 80, align: TextAlign.center),
  ];

  bool _isCancelled(Map<String, dynamic> i) => i['status'] == 'cancelled';
  double _bal(Map<String, dynamic> i) => _isCancelled(i)
      ? 0 : (i['balance_amount'] as num?)?.toDouble() ?? 0;

  bool _inTab(Map<String, dynamic> i, String t) => switch (t) {
    'due'       => !_isCancelled(i) && _bal(i) > 0,
    'paid'      => !_isCancelled(i) && _bal(i) <= 0,
    'cancelled' => _isCancelled(i),
    _           => true,
  };

  Comparable<Object> _sortValue(Map<String, dynamic> i) {
    switch (_sortKey) {
      case 'number':
        return i['invoice_number'] as String? ?? '';
      case 'date':
        return i['invoice_date'] as String? ?? '';
      case 'retailer':
        return ((i['retailers'] as Map?)?['shop_name'] as String? ?? '')
            .toLowerCase();
      case 'birds':
        return (i['bird_count'] as num?) ?? 0;
      case 'kg':
        return (i['quantity_kg'] as num?) ?? 0;
      case 'total':
        return (i['total_amount'] as num?) ?? 0;
      case 'balance':
        return _bal(i);
      default:
        return i['invoice_date'] as String? ?? '';
    }
  }

  Widget _webCell(Map<String, dynamic> inv, int col) {
    final cancelled = _isCancelled(inv);
    switch (col) {
      case 0:
        return Text(inv['invoice_number'] as String? ?? '—',
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600,
                color: WebColors.text1));
      case 1:
        final d = DateTime.tryParse(inv['invoice_date'] as String? ?? '');
        return Text(d != null ? DateFormat('d MMM y').format(d) : '—',
            style: const TextStyle(fontSize: 13, color: WebColors.text2));
      case 2:
        final name = (inv['retailers'] as Map?)?['shop_name'] as String? ?? '—';
        return Text(name, maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600,
                color: cancelled ? WebColors.text3 : WebColors.text1));
      case 3:
        return Text('${inv['bird_count'] ?? 0}',
            style: const TextStyle(fontSize: 13.5, color: WebColors.text2));
      case 4:
        return Text(
            '${(inv['quantity_kg'] as num?)?.toStringAsFixed(1) ?? '0'} kg',
            style: const TextStyle(fontSize: 13.5, color: WebColors.text2));
      case 5:
        return Text(
            Fmt.amount((inv['total_amount'] as num?)?.toDouble() ?? 0),
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700,
                color: cancelled ? WebColors.text3 : WebColors.text1,
                decoration: cancelled ? TextDecoration.lineThrough : null));
      case 6:
        final bal = _bal(inv);
        return Text(bal > 0 ? Fmt.amount(bal) : '—',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700,
                color: bal > 0 ? WebColors.warning : WebColors.text3));
      case 7:
        final status = inv['status'] as String? ?? 'draft';
        final label = status.replaceAll('_', ' ');
        return WebLabel(label[0].toUpperCase() + label.substring(1),
            color: cancelled ? WebColors.text3 : SC.order(status));
      default:
        return WebIconButton(
          icon: Icons.visibility_outlined,
          tooltip: 'View details',
          size: 32,
          outlined: false,
          onTap: () => context.push(R.invoiceDetailPath(inv['id'])),
        );
    }
  }


  Widget _buildWebPage() {
    final rows = _filtered.where((i) => _inTab(i, _webTab)).toList()
      ..sort((a, b) {
        final c = Comparable.compare(_sortValue(a), _sortValue(b));
        return _sortAsc ? c : -c;
      });
    final lastPage = rows.isEmpty ? 0 : (rows.length - 1) ~/ _rowsPerPage;
    final page = _page.clamp(0, lastPage);
    final pageRows =
        rows.skip(page * _rowsPerPage).take(_rowsPerPage).toList();
    final collected = _list.where((i) => !_isCancelled(i)).fold<double>(0,
        (s, i) => s + ((i['collected_amount'] as num?)?.toDouble() ?? 0));

    return WebPage(
      header: PageBreadcrumbsHeader(
        title: 'Invoices',
        subtitle: 'Every bill raised, what was collected and what is due',
        crumbs: const [Crumb('Dashboard', R.dashboard), Crumb('Invoices')],
        action: WebIconButton(icon: Icons.refresh_rounded,
            tooltip: 'Refresh', onTap: _load),
      ),
      children: [
        WebKpiRow(children: [
          WebKpiCard(label: 'Total Revenue', value: Fmt.amount(_totalRevenue),
              icon: Icons.trending_up_rounded, color: WebColors.navy),
          WebKpiCard(label: 'Collected', value: Fmt.amount(collected),
              icon: Icons.payments_outlined, color: WebColors.success),
          WebKpiCard(label: 'Outstanding',
              value: Fmt.amount(_totalOutstanding),
              icon: Icons.account_balance_wallet_outlined,
              color: _totalOutstanding > 0
                  ? WebColors.warning : WebColors.success),
          WebKpiCard(label: 'Invoices', value: '${_filtered.length}',
              sub: 'latest 200 loaded',
              icon: Icons.receipt_long_outlined, color: WebColors.gold),
        ]),
        const SizedBox(height: WebSpace.lg),
        WebListCard(children: [
          WebListTabs(
            tabs: [
              WebTab('All', count: _filtered.length),
              WebTab('Due', count: _filtered.where((i) => _inTab(i, 'due')).length,
                  color: WebColors.warning),
              WebTab('Paid', count: _filtered.where((i) => _inTab(i, 'paid')).length,
                  color: WebColors.success),
              WebTab('Cancelled',
                  count: _filtered.where((i) => _inTab(i, 'cancelled')).length,
                  color: WebColors.text3),
            ],
            selected: _webTabs.indexOf(_webTab),
            onChanged: (i) => setState(() { _webTab = _webTabs[i]; _page = 0; }),
          ),
          WebListToolbar(
            search: WebSearchField(
              controller: _searchCtrl,
              hint: 'Search by retailer or invoice number…',
              debounce: const Duration(milliseconds: 250),
              onChanged: (v) { _applySearch(v); setState(() => _page = 0); },
            ),
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
              onRowTap: (inv) => context.push(R.invoiceDetailPath(inv['id'])),
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
              emptyText: _list.isEmpty ? 'No invoices yet' : 'No invoices match',
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

  // ── Mobile list ───────────────────────────────────────────────────────────

  Widget _buildMobileList() {
    return RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          padding:          const EdgeInsets.fromLTRB(14, 14, 14, kBottomNavClearance),
          itemCount:        _filtered.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder:      (_, i)  => SerialNumbered(
              serial: i + 1, child: _InvoiceCard(invoice: _filtered[i])),
        ));
  }
}

// ── Mobile invoice card ───────────────────────────────────────────────────────

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.invoice});
  final Map<String, dynamic> invoice;

  @override
  Widget build(BuildContext context) {
    final r       = invoice['retailers'] as Map<String, dynamic>?;
    final date    = DateTime.tryParse(invoice['invoice_date'] as String? ?? '');
    final status  = invoice['status']        as String? ?? 'draft';
    final isCancelled = status == 'cancelled';
    final total   = (invoice['total_amount']   as num?)?.toDouble() ?? 0;
    final balance = isCancelled ? 0.0 : (invoice['balance_amount'] as num?)?.toDouble() ?? 0;

    return InkWell(
      onTap:        () => context.push(R.invoiceDetailPath(invoice['id'])),
      borderRadius: BorderRadius.circular(kRadiusCard),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isCancelled ? const Color(0xFFF5F5F5) : kSurface,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border: Border.all(
              color: isCancelled
                  ? kBorderLight
                  : balance > 0
                  ? Colors.orange.withValues(alpha: 0.35)
                  : kBorderLight,
              width: balance > 0 && !isCancelled ? 1.5 : 0.8),
          boxShadow: isCancelled ? null : kCardShadow,
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(invoice['invoice_number'] as String? ?? '—',
                style: const TextStyle(fontSize: 11, color: kTextHint, fontWeight: FontWeight.w600)),
            Text(r?['shop_name'] as String? ?? '—',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                    color: isCancelled ? kTextHint : kNavy)),
            if (date != null)
              Text(DateFormat('d MMM y').format(date),
                  style: const TextStyle(fontSize: 11, color: kTextHint)),
            Text(
              '${invoice['bird_count'] ?? 0} birds · '
                  '${(invoice['quantity_kg'] as num?)?.toStringAsFixed(1) ?? 0} kg',
              style: const TextStyle(fontSize: 11, color: kTextSub),
            ),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(Fmt.amount(total),
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w900,
                    color: isCancelled ? kTextHint : kNavy,
                    decoration: isCancelled ? TextDecoration.lineThrough : null)),
            if (balance > 0)
              Text('Due: ${Fmt.amount(balance)}',
                  style: const TextStyle(
                      fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w600)),
            isCancelled
                ? const StatusChip(label: 'cancelled', color: kTextHint, size: StatusChipSize.small)
                : StatusChip.order(status, size: StatusChipSize.small),
          ]),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, color: kTextHint, size: 18),
        ]),
      ),
    );
  }
}