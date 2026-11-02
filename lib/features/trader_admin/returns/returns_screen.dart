import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/responsive_layout.dart';
import '../../../shared/widgets/web/web.dart';
import 'return_create_screen.dart';

class ReturnsScreen extends ConsumerStatefulWidget {
  const ReturnsScreen({super.key});

  @override
  ConsumerState<ReturnsScreen> createState() => _S();
}

class _S extends ConsumerState<ReturnsScreen> {
  final _c = Supabase.instance.client;
  List<Map<String, dynamic>> _returns = [];
  List<Map<String, dynamic>> _filtered = [];
  final _searchCtrl = TextEditingController();

  void _applySearch(String q) {
    if (!mounted) return;
    final lower = q.trim().toLowerCase();
    setState(() => _filtered = lower.isEmpty
        ? List.from(_returns)
        : _returns.where((r) {
      final ret = r['retailers'] as Map<String,dynamic>?;
      final ag  = r['delivery_agents'] as Map<String,dynamic>?;
      return (ret?['shop_name'] as String? ?? '').toLowerCase().contains(lower) ||
          (ag?['name']       as String? ?? '').toLowerCase().contains(lower);
    }).toList());
  }

  // Stock summary from returns
  int _totalReturnedBirds = 0;
  double _totalReturnedKg = 0;
  bool _loading = true;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => _applySearch(_searchCtrl.text));
  }
  @override void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null || !mounted) return;
    if (mounted) setState(() => _loading = true);
    try {
      var q = _c
          .from('return_entries')
          .select(
          'id,return_type,return_date,bird_count,weight_kg,reason,status,stock_credited,created_at,'
              'retailers(shop_name),delivery_agents(name),master_products(name),'
              'credit_notes(id,credit_number,total_amount)')
          .eq('trader_id', tid);
      if (_filter != 'all') q = q.eq('status', _filter);
      final r = await q.order('created_at', ascending: false).limit(100);
      // Return stock summary from stock_ledger
      final sl = await _c
          .from('stock_ledger')
          .select('quantity_birds,quantity_kg')
          .eq('trader_id', tid)
          .eq('movement_type', 'returned_in');
      if (!mounted) return;
      int birds = 0;
      double kg = 0;
      for (final s in sl) {
        birds += (s['quantity_birds'] as num?)?.toInt() ?? 0;
        kg += (s['quantity_kg'] as num?)?.toDouble() ?? 0;
      }
      if (mounted) {
        setState(() {
          _returns = List<Map<String, dynamic>>.from(r);
          _applySearch(_searchCtrl.text);
          _totalReturnedBirds = birds;
          _totalReturnedKg = kg;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      showError(context, e.toString());
    }
  }

  Future<void> _openCreateReturn() async {
    final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const ReturnCreateScreen()));
    if (result == true) _load();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // WEB (desktop) — header, KPI row, status tabs, returns table.
  // ═══════════════════════════════════════════════════════════════════════
  static const _webStatuses = ['all', 'pending', 'processed'];
  bool _dense = true;
  int _page = 0;
  int _rowsPerPage = 25;

  Map<String, dynamic>? _creditNoteOf(Map<String, dynamic> r) {
    final raw = r['credit_notes'];
    if (raw is List && raw.isNotEmpty) {
      return Map<String, dynamic>.from(raw.first as Map);
    }
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  Widget _buildWeb() {
    final rows = _filtered;
    final lastPage = rows.isEmpty ? 0 : (rows.length - 1) ~/ _rowsPerPage;
    final page = _page.clamp(0, lastPage);
    final pageRows =
        rows.skip(page * _rowsPerPage).take(_rowsPerPage).toList();
    final pending = _returns.where((r) => r['status'] == 'pending').length;
    final credited = _returns.where((r) => r['stock_credited'] == true).length;

    return WebPage(
      header: PageBreadcrumbsHeader(
        title: 'Returns',
        subtitle: 'Customer and agent returns, stock credit and credit notes',
        crumbs: const [Crumb('Dashboard', R.dashboard), Crumb('Returns')],
        action: Row(mainAxisSize: MainAxisSize.min, children: [
          WebIconButton(icon: Icons.refresh_rounded, tooltip: 'Refresh',
              onTap: _load),
          const SizedBox(width: 8),
          WebButton(
            label: 'Process Return',
            icon: Icons.assignment_return_outlined,
            onPressed: _openCreateReturn,
          ),
        ]),
      ),
      children: [
        WebKpiRow(children: [
          WebKpiCard(label: 'Total Returned to Stock',
              value: '$_totalReturnedBirds birds',
              sub: '${_totalReturnedKg.toStringAsFixed(1)} kg · available for redelivery',
              icon: Icons.assignment_return_outlined, color: WebColors.navy),
          WebKpiCard(label: 'Returns Shown', value: '${_returns.length}',
              icon: Icons.list_alt_rounded, color: WebColors.info),
          WebKpiCard(label: 'Pending', value: '$pending',
              icon: Icons.hourglass_empty_rounded, color: WebColors.warning),
          WebKpiCard(label: 'Stock Updated', value: '$credited',
              icon: Icons.check_circle_outline, color: WebColors.success),
        ]),
        const SizedBox(height: WebSpace.lg),
        WebListCard(children: [
          WebListTabs(
            tabs: const [
              WebTab('All'),
              WebTab('Pending', color: WebColors.warning),
              WebTab('Processed', color: WebColors.success),
            ],
            selected: _webStatuses.indexOf(_filter),
            onChanged: (i) {
              setState(() { _filter = _webStatuses[i]; _page = 0; });
              _load();
            },
          ),
          WebListToolbar(
            search: WebSearchField(
              controller: _searchCtrl,
              hint: 'Search by shop or agent…',
              debounce: const Duration(milliseconds: 250),
              onChanged: (v) { _applySearch(v); setState(() => _page = 0); },
            ),
          ),
          WebDataTable<Map<String, dynamic>>(
            columns: const [
              WebColumn('Date', width: 115, minWidth: 105),
              WebColumn('Retailer', flex: 3, minWidth: 140),
              WebColumn('Agent', flex: 2, minWidth: 110),
              WebColumn('Product', flex: 2, minWidth: 110),
              WebColumn('Type', width: 130, minWidth: 115),
              WebColumn('Birds', width: 85, align: TextAlign.right, minWidth: 75),
              WebColumn('Weight', width: 105, align: TextAlign.right, minWidth: 95),
              WebColumn('Reason', flex: 2, minWidth: 120),
              WebColumn('Status', width: 190, minWidth: 175),
              WebColumn('Credit Note', width: 195, minWidth: 180),
            ],
            rows: pageRows,
            dense: _dense,
            loading: _loading,
            emptyText: _returns.isEmpty ? 'No returns recorded' : 'No results match',
            emptyAction: _returns.isEmpty
                ? WebButton(label: 'Process Return',
                    icon: Icons.assignment_return_outlined,
                    onPressed: _openCreateReturn)
                : null,
            cellBuilder: (r, col) {
              switch (col) {
                case 0:
                  final d = DateTime.tryParse(r['return_date'] as String? ?? '');
                  return Text(d != null ? DateFormat('d MMM y').format(d) : '—',
                      style: const TextStyle(fontSize: 13, color: WebColors.text2));
                case 1:
                  final name = (r['retailers'] as Map?)?['shop_name'] as String? ?? '—';
                  return Text(name, maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5,
                          fontWeight: FontWeight.w600, color: WebColors.text1));
                case 2:
                  return Text((r['delivery_agents'] as Map?)?['name'] as String? ?? '—',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: WebColors.text2));
                case 3:
                  return Text((r['master_products'] as Map?)?['name'] as String? ?? '—',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13,
                          fontWeight: FontWeight.w600, color: WebColors.text1));
                case 4:
                  final typeRaw = r['return_type'] as String? ?? '';
                  final typeLabel = switch (typeRaw) {
                    'same_batch' => 'Same Batch',
                    'old_stock'  => 'Old Stock',
                    _            => typeRaw.isEmpty ? '—' : typeRaw.replaceAll('_', ' '),
                  };
                  return WebLabel(typeLabel, color: WebColors.info);
                case 5:
                  return Text('${r['bird_count'] ?? 0}',
                      style: const TextStyle(fontSize: 13.5, color: WebColors.text2));
                case 6:
                  return Text('${(r['weight_kg'] as num?)?.toStringAsFixed(1) ?? 0} kg',
                      style: const TextStyle(fontSize: 13.5, color: WebColors.text2));
                case 7:
                  return Text(r['reason'] as String? ?? '—', maxLines: 1,
                      overflow: TextOverflow.ellipsis, style: WebText.caption);
                case 8:
                  final status = r['status'] as String? ?? 'pending';
                  final ok = status == 'processed';
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      WebLabel(
                        status.isNotEmpty
                            ? status[0].toUpperCase() + status.substring(1)
                            : '—',
                        color: ok ? WebColors.success : WebColors.warning,
                        dot: true,
                      ),
                      if (r['stock_credited'] == true) ...[
                        const SizedBox(width: 6),
                        const Flexible(
                          child: Text(
                            '· Stock ✓',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: WebColors.success,
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                default:
                  final cn = _creditNoteOf(r);
                  if (cn == null) return const Text('—', style: WebText.caption);
                  return MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => context.push(
                          R.creditNoteDetailPath(cn['id'] as String)),
                      child: Text.rich(
                        TextSpan(
                          text: cn['credit_number'] as String? ?? 'Credit Note',
                          style: const TextStyle(fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: WebColors.navy,
                              decoration: TextDecoration.underline),
                          children: [
                            TextSpan(
                              text: ' · ${Fmt.amount((cn['total_amount'] as num?)?.toDouble() ?? 0)}',
                              style: const TextStyle(fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: WebColors.success,
                                  decoration: TextDecoration.none),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  );
              }
            },
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

  @override
  Widget build(BuildContext context) => context.isDesktop ? _buildWeb() : Scaffold(
    backgroundColor: kBgPage,
    appBar: AppBar(
        backgroundColor: kSurface,
        title: const Text('Returns'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh_rounded), onPressed: _load)
        ]),
    // Reserve space so FAB clears the parent TraderShell glass bottom nav
    bottomNavigationBar: const SizedBox(height: kBottomNavClearance),
    floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateReturn,
        icon: const Icon(Icons.assignment_return_outlined),
        label: const Text('Process Return')),
    body: _loading
        ? const LoadingList()
        : Column(children: [
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: AppSearchBar(
          controller: _searchCtrl,
          hint: 'Search by shop or agent…',
          onChanged: _applySearch,
          onClear: () { _searchCtrl.clear(); _applySearch(''); },
        ),
      ),
      const Divider(height: 1),
      // Stock integration summary
      if (_totalReturnedBirds > 0)
        Container(
            decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [kNavy, kNavyMid],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight)),
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius:
                      BorderRadius.circular(kRadiusChip)),
                  child: const Icon(Icons.assignment_return_outlined,
                      color: Colors.white, size: 22)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('TOTAL RETURNED TO STOCK',
                            style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFFB4C6F4),
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6)),
                        Text(
                            '$_totalReturnedBirds birds · ${_totalReturnedKg.toStringAsFixed(1)} kg',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: kGoldLight)),
                        const Text('Available for redelivery',
                            style: TextStyle(
                                fontSize: 10, color: Color(0xFFB4C6F4))),
                      ])),
            ])),
      // Filter
      Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('All')),
                ButtonSegment(
                    value: 'pending', label: Text('Pending')),
                ButtonSegment(
                    value: 'processed', label: Text('Processed'))
              ],
              selected: {
                _filter
              },
              onSelectionChanged: (s) {
                if (mounted) setState(() => _filter = s.first);
                _load();
              })),
      const Divider(height: 1),
      Expanded(
          child: _returns.isEmpty
              ? const EmptyState(
              icon: Icons.assignment_return_outlined,
              message: 'No returns recorded')
              : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, kBottomNavClearance),
              itemCount: _filtered.length,
              separatorBuilder: (_, __) =>
              const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final r = _filtered[i];
                final retailer =
                r['retailers'] as Map<String, dynamic>?;
                final agent =
                r['delivery_agents'] as Map<String, dynamic>?;
                final product =
                r['master_products'] as Map<String, dynamic>?;
                final date = DateTime.tryParse(
                    r['return_date'] as String? ?? '');
                final status =
                    r['status'] as String? ?? 'pending';
                final credited =
                    r['stock_credited'] as bool? ?? false;
                // ★ NEW: reverse-embedded credit note (nested relationship
                // returns a List even though return_id is unique per note).
                final creditNotesRaw = r['credit_notes'];
                final creditNote = creditNotesRaw is List && creditNotesRaw.isNotEmpty
                    ? Map<String, dynamic>.from(creditNotesRaw.first as Map)
                    : (creditNotesRaw is Map ? Map<String, dynamic>.from(creditNotesRaw) : null);
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: kSurface,
                      borderRadius:
                      BorderRadius.circular(kRadiusCard),
                      boxShadow: kCardShadow,
                      border: Border.all(
                          color: status == 'processed'
                              ? Colors.green
                              .withValues(alpha: 0.3)
                              : Colors.orange
                              .withValues(alpha: 0.3),
                          width: 1.2)),
                  child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(
                                  retailer?['shop_name']
                                  as String? ??
                                      '—',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                      color: kNavy))),
                          StatusBadge(
                              status,
                              status == 'processed'
                                  ? Colors.green
                                  : Colors.orange),
                        ]),
                        const SizedBox(height: 6),
                        Row(children: [
                          const Icon(Icons.delivery_dining,
                              size: 13, color: kTextHint),
                          const SizedBox(width: 4),
                          Text(agent?['name'] as String? ?? '—',
                              style: const TextStyle(
                                  fontSize: 11, color: kTextSub)),
                          const SizedBox(width: 12),
                          StatusBadge(
                              r['return_type'] as String? ?? '—',
                              Colors.blue,
                              small: true),
                        ]),
                        const SizedBox(height: 6),
                        if (product?['name'] != null) ...[
                          const SizedBox(height: 4),
                          Text(product!['name'] as String,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: kNavy)),
                        ],
                        const SizedBox(height: 2),
                        Row(children: [
                          Text(
                              '${r['bird_count'] ?? 0} birds · ${(r['weight_kg'] as num?)?.toStringAsFixed(1) ?? 0} kg',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                          const Spacer(),
                          if (credited)
                            Row(children: [
                              Icon(Icons.check_circle,
                                  color: Colors.green.shade600,
                                  size: 14),
                              const SizedBox(width: 4),
                              Text('Stock Updated ✓',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color:
                                      Colors.green.shade700,
                                      fontWeight:
                                      FontWeight.w600))
                            ]),
                          if (date != null) ...[
                            const SizedBox(width: 8),
                            Text(DateFormat('d MMM').format(date),
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: kTextHint))
                          ],
                        ]),
                        if (r['reason'] != null)
                          Padding(
                              padding:
                              const EdgeInsets.only(top: 4),
                              child: Text(r['reason'] as String,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: kTextSub),
                                  maxLines: 2,
                                  overflow:
                                  TextOverflow.ellipsis)),
                        if (creditNote != null) ...[
                          const Divider(height: 14),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text(
                                'Credit: ${Fmt.amount((creditNote['total_amount'] as num?)?.toDouble() ?? 0)}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF6A1B9A))),
                            TextButton.icon(
                              onPressed: () => context.push(
                                  R.creditNoteDetailPath(creditNote['id'] as String)),
                              icon: const Icon(Icons.receipt_outlined, size: 14),
                              label: Text(creditNote['credit_number'] as String? ?? 'View Credit Note',
                                  style: const TextStyle(fontSize: 11)),
                            ),
                          ]),
                        ],
                      ]),
                );
              })),
    ]),
  );
}