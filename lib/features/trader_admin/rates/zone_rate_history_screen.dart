import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/layouts/responsive_layout.dart';
import '../../../shared/widgets/web/web.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ZONE RATE HISTORY
//
// Zone Rate is the only trader-facing pricing mechanism (Daily Rate UI
// removed). This screen is the trader's window into that history:
//   - No filters         -> latest rate per Zone + Product (a "current rates" view)
//   - Zone/Product filter -> full chronological history for that scope
//   - From/To Date        -> narrows the same history to a date range
//
// Previous Rate / Difference are computed server-side over each zone+product's
// COMPLETE history before any date-range filter is applied, so the oldest row
// inside a narrow date range still shows its true previous rate rather than
// appearing to be a fresh entry.
//
// Read-only. Every row shown here is immutable once its effective date is in
// the past (enforced server-side by trg_zone_rate_immutable /
// trg_zone_rate_immutable_delete) — there is no edit or delete action on
// this screen by design. To change a price, set a new Zone Rate from today;
// the old entry remains in history forever.
//
// Source: get_zone_rate_history_v3() RPC (additive — v2 untouched/unused here).
// ─────────────────────────────────────────────────────────────────────────────

class ZoneRateHistoryScreen extends ConsumerStatefulWidget {
  const ZoneRateHistoryScreen({super.key});

  @override
  ConsumerState<ZoneRateHistoryScreen> createState() => _S();
}

class _S extends ConsumerState<ZoneRateHistoryScreen> {
  final _c = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _zones = [];
  List<Map<String, dynamic>> _products = [];

  String? _zoneId;
  String? _productId;
  DateTime? _fromDate;
  DateTime? _toDate;
  String? _activeQuickFilter; // label of the selected quick filter chip, if any
  final _searchCtrl = TextEditingController();
  String _searchQ = '';

  @override
  void initState() {
    super.initState();
    _loadFilters();
    _load();
    _searchCtrl.addListener(()
      { if (mounted) setState(() => _searchQ = _searchCtrl.text.trim().toLowerCase()); });
  }
  @override void dispose() { _searchCtrl.dispose(); super.dispose(); }

  String? get _traderId => ref.read(appUserProvider).valueOrNull?.traderId;

  Future<void> _loadFilters() async {
    final tid = _traderId;
    if (tid == null) return;
    try {
      final zones = await _c
          .from('zones')
          .select('id, zone_name, zone_code')
          .eq('trader_id', tid)
          .eq('is_active', true)
          .order('zone_name');
      final products = await _c
          .from('master_products')
          .select('id, name')
          .isFilter('parent_product_id', null)
          .eq('is_active', true)
          .order('sort_order');
      if (!mounted) return;
      setState(() {
        _zones = (zones as List).cast<Map<String, dynamic>>();
        _products = (products as List).cast<Map<String, dynamic>>();
      });
    } catch (_) {
      // Filter dropdowns are non-critical — fail silently, history list
      // below still works without zone/product names to filter by.
    }
  }

  Future<void> _load() async {
    final tid = _traderId;
    if (tid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted)
      setState(() {
        _loading = true;
        _error = null;
      });
    try {
      final res = await _c.rpc('get_zone_rate_history_v3', params: {
        'p_trader_id': tid,
        'p_zone_id': _zoneId,
        'p_product_id': _productId,
        'p_from_date': _fromDate != null
            ? DateFormat('yyyy-MM-dd').format(_fromDate!)
            : null,
        'p_to_date':
        _toDate != null ? DateFormat('yyyy-MM-dd').format(_toDate!) : null,
        'p_limit': 200,
      });
      if (!mounted) return;
      setState(() {
        _rows = (res as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load rate history.';
        _loading = false;
      });
    }
  }

  bool get _isFiltered =>
      _zoneId != null ||
          _productId != null ||
          _fromDate != null ||
          _toDate != null;

  // ═══════════════════════════════════════════════════════════════════════
  // WEB (desktop) — filter card + history table. Read-only, same RPC.
  // ═══════════════════════════════════════════════════════════════════════
  bool _dense = true;

  Widget _buildWeb() {
    final visibleRows = _searchQ.isEmpty ? _rows : _rows.where((r) {
      final zone = r['zone_name'] as String? ?? '';
      final product = r['product_name'] as String? ?? '';
      return zone.toLowerCase().contains(_searchQ) ||
          product.toLowerCase().contains(_searchQ);
    }).toList();
    final current = _rows.where((r) =>
        r['is_active'] == true && r['is_latest'] == true).length;

    final filters = WebCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 12, runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center, children: [
          WebSearchField(
            controller: _searchCtrl,
            hint: 'Search by zone or product…',
            width: 280,
            debounce: const Duration(milliseconds: 150),
            onChanged: (q) {
              if (mounted) setState(() => _searchQ = q.toLowerCase());
            },
          ),
          SizedBox(width: 200, child: _dropdown(
              label: 'Zone',
              value: _zoneId,
              items: _zones.map((z) => DropdownMenuItem(
                  value: z['id'] as String,
                  child: Text(z['zone_name'] as String? ?? '—',
                      overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) { setState(() => _zoneId = v); _load(); })),
          SizedBox(width: 200, child: _dropdown(
              label: 'Product',
              value: _productId,
              items: _products.map((p) => DropdownMenuItem(
                  value: p['id'] as String,
                  child: Text(p['name'] as String? ?? '—',
                      overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) { setState(() => _productId = v); _load(); })),
          SizedBox(width: 170, child: _dateField(label: 'From Date',
              value: _fromDate, onTap: () => _pickDate(isFrom: true))),
          SizedBox(width: 170, child: _dateField(label: 'To Date',
              value: _toDate, onTap: () => _pickDate(isFrom: false))),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          WebSegmented<String>(
            options: const ['Today', 'Yesterday', 'Last 7 Days',
              'Last 30 Days', 'This Month'],
            selected: _activeQuickFilter,
            label: (s) => s,
            onChanged: _applyQuickFilter,
          ),
          const Spacer(),
          if (_isFiltered)
            WebButton(label: 'Clear filters', icon: Icons.close_rounded,
                outlined: true, color: WebColors.error,
                onPressed: _clearAllFilters),
        ]),
      ]),
    );

    return WebPage(
      header: PageBreadcrumbsHeader(
        title: 'Zone Rate History',
        subtitle: _isFiltered
            ? 'Full history for the selected filters'
            : 'Latest rate per zone and product',
        crumbs: const [Crumb('Dashboard', R.dashboard), Crumb('Rate History')],
        action: WebIconButton(icon: Icons.refresh_rounded,
            tooltip: 'Refresh', onTap: _load),
      ),
      children: [
        filters,
        const SizedBox(height: WebSpace.lg),
        WebListCard(children: [
          WebCardHeader(
            title: 'Rate History',
            subtitle: '${visibleRows.length} entr${visibleRows.length == 1 ? 'y' : 'ies'}'
                ' · $current current',
            icon: Icons.history_rounded,
            action: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('Dense', style: WebText.bodySub),
              Switch(value: _dense, activeTrackColor: WebColors.navy,
                  onChanged: (v) => setState(() => _dense = v)),
            ]),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(WebSpace.xl),
              child: Column(children: [
                Text(_error!, style: WebText.bodySub),
                const SizedBox(height: 12),
                WebButton(label: 'Retry', outlined: true, onPressed: _load),
              ]),
            )
          else
            WebDataTable<Map<String, dynamic>>(
              columns: const [
                WebColumn('Product', flex: 2),
                WebColumn('Zone', width: 130),
                WebColumn('Effective', width: 130),
                WebColumn('Previous', width: 110, align: TextAlign.right),
                WebColumn('Rate', width: 110, align: TextAlign.right),
                WebColumn('Change', width: 110, align: TextAlign.center),
                WebColumn('Updated By', flex: 2),
                WebColumn('Updated At', width: 140),
                WebColumn('Status', width: 120, align: TextAlign.center),
              ],
              rows: visibleRows,
              paginate: true,
              dense: _dense,
              loading: _loading,
              emptyText: _isFiltered
                  ? 'No rate history for this filter yet.'
                  : 'No zone rates set yet — set a rate from the Pricing Hub.',
              cellBuilder: (row, col) {
                final rate = (row['rate_per_kg'] as num?)?.toDouble() ?? 0;
                final prev = (row['prev_rate_per_kg'] as num?)?.toDouble();
                final diff = (row['difference'] as num?)?.toDouble() ?? 0;
                final isActive = row['is_active'] == true;
                final isLatest = isActive && row['is_latest'] == true;
                switch (col) {
                  case 0:
                    return Text(row['product_name'] as String? ?? '—',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: WebColors.text1));
                  case 1:
                    final code = row['zone_code'] as String?;
                    return Text('${row['zone_name'] ?? '—'}${code != null ? " ($code)" : ""}',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: WebColors.text2));
                  case 2:
                    final d = row['effective_date'] as String?;
                    return Text(d != null
                        ? DateFormat('d MMM yyyy').format(DateTime.parse(d))
                        : '—', style: const TextStyle(fontSize: 13,
                        color: WebColors.text2));
                  case 3:
                    return Text(prev != null ? '${Fmt.amount(prev)}/kg' : '—',
                        style: const TextStyle(fontSize: 13,
                            color: WebColors.text3,
                            decoration: TextDecoration.lineThrough));
                  case 4:
                    return Text('${Fmt.amount(rate)}/kg', style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800,
                        color: WebColors.navy));
                  case 5:
                    if (prev == null || diff == 0) {
                      return const Text('—', style: WebText.caption);
                    }
                    return WebLabel(
                        diff > 0 ? '+${Fmt.amount(diff)}'
                            : '-${Fmt.amount(diff.abs())}',
                        color: diff > 0 ? WebColors.success : WebColors.error,
                        icon: diff > 0 ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded);
                  case 6:
                    return Text(row['updated_by_email'] as String? ?? '—',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: WebColors.text2));
                  case 7:
                    final at = row['updated_at'] as String?;
                    return Text(at != null
                        ? DateFormat('d MMM, h:mm a').format(DateTime.parse(at).toLocal())
                        : '—', style: const TextStyle(fontSize: 12.5, color: WebColors.text3));
                  default:
                    return isLatest
                        ? const WebLabel('Current', color: WebColors.gold,
                            dot: true)
                        : isActive
                            ? const WebLabel('Active', color: WebColors.success)
                            : const WebLabel('Superseded',
                                color: WebColors.text3);
                }
              },
            ),
          const SizedBox(height: WebSpace.md),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (context.isDesktop) return _buildWeb();
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: const Text('Zone Rate History',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: Column(children: [
        _buildFilterBar(),
        const Divider(height: 1),
        Expanded(child: _buildBody()),
      ]),
    );
  }

  // ── Filter bar ──────────────────────────────────────────────────────────
  Widget _buildFilterBar() => Container(
      color: kSurface,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppSearchBar(
          controller: _searchCtrl,
          hint: 'Search by zone or product…',
          onChanged: (q) { if (mounted) setState(() => _searchQ = q.trim().toLowerCase()); },
          onClear: () { _searchCtrl.clear(); if (mounted) setState(() => _searchQ = ''); },
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
              child: _dropdown(
                  label: 'Zone',
                  value: _zoneId,
                  items: _zones
                      .map((z) => DropdownMenuItem(
                      value: z['id'] as String,
                      child: Text(z['zone_name'] as String? ?? '—',
                          overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _zoneId = v);
                    _load();
                  })),
          const SizedBox(width: 10),
          Expanded(
              child: _dropdown(
                  label: 'Product',
                  value: _productId,
                  items: _products
                      .map((p) => DropdownMenuItem(
                      value: p['id'] as String,
                      child: Text(p['name'] as String? ?? '—',
                          overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _productId = v);
                    _load();
                  })),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
              child: _dateField(
                  label: 'From Date',
                  value: _fromDate,
                  onTap: () => _pickDate(isFrom: true))),
          const SizedBox(width: 10),
          Expanded(
              child: _dateField(
                  label: 'To Date',
                  value: _toDate,
                  onTap: () => _pickDate(isFrom: false))),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          height: 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _quickFilterChip('Today'),
              _quickFilterChip('Yesterday'),
              _quickFilterChip('Last 7 Days'),
              _quickFilterChip('Last 30 Days'),
              _quickFilterChip('This Month'),
            ],
          ),
        ),
        if (_isFiltered) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _clearAllFilters,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.close_rounded, size: 14, color: kTextHint),
              const SizedBox(width: 4),
              Text('Clear filters',
                  style: TextStyle(
                      fontSize: 12,
                      color: kTextHint,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
      ]));

  void _clearAllFilters() {
    setState(() {
      _zoneId = null;
      _productId = null;
      _fromDate = null;
      _toDate = null;
      _activeQuickFilter = null;
    });
    _load();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = (isFrom ? _fromDate : _toDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
      } else {
        _toDate = picked;
      }
      _activeQuickFilter = null; // manual edit overrides any quick filter
    });
    _load();
  }

  Widget _dateField({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kRadiusChip),
              border: Border.all(color: kBorder)),
          child: Row(children: [
            const Icon(Icons.calendar_today_outlined,
                size: 14, color: kTextHint),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  value != null
                      ? DateFormat('d MMM yyyy').format(value)
                      : label,
                  style: TextStyle(
                      fontSize: 13,
                      color: value != null ? kNavy : kTextHint,
                      fontWeight:
                      value != null ? FontWeight.w700 : FontWeight.w500),
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
        ),
      );

  void _applyQuickFilter(String label) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime from;
    DateTime to = today;
    switch (label) {
      case 'Today':
        from = today;
        break;
      case 'Yesterday':
        from = today.subtract(const Duration(days: 1));
        to = from;
        break;
      case 'Last 7 Days':
        from = today.subtract(const Duration(days: 6));
        break;
      case 'Last 30 Days':
        from = today.subtract(const Duration(days: 29));
        break;
      case 'This Month':
        from = DateTime(today.year, today.month, 1);
        break;
      default:
        return;
    }
    setState(() {
      _fromDate = from;
      _toDate = to;
      _activeQuickFilter = label;
    });
    _load();
  }

  Widget _quickFilterChip(String label) {
    final isSel = _activeQuickFilter == label;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => _applyQuickFilter(label),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
              color: isSel ? kNavy : kBgGrey,
              borderRadius: BorderRadius.circular(kRadiusChip),
              border: Border.all(color: isSel ? kNavy : kBorderLight)),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isSel ? Colors.white : kTextSub)),
        ),
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) =>
      DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 12, color: kTextHint),
          isDense: true,
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kRadiusChip),
              borderSide: const BorderSide(color: kBorder)),
        ),
        items: [
          DropdownMenuItem(
              value: null,
              child: Text('All ${label}s',
                  style: const TextStyle(fontSize: 13, color: kTextSub))),
          ...items,
        ],
        onChanged: onChanged,
      );

  // ── Body ────────────────────────────────────────────────────────────────
  Widget _buildBody() {
    if (_loading) return const LoadingList();
    if (_error != null) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline, size: 40, color: kError),
                const SizedBox(height: 8),
                Text(_error!,
                    style: const TextStyle(fontSize: 13, color: kTextSub)),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _load, child: const Text('Retry')),
              ])));
    }
    if (_rows.isEmpty) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.history_rounded, size: 40, color: kTextHint),
                const SizedBox(height: 8),
                Text(
                    _isFiltered
                        ? 'No rate history for this filter yet.'
                        : 'No zone rates set yet.\nSet a rate from the Pricing Hub to get started.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: kTextSub)),
              ])));
    }

    final visibleRows = _searchQ.isEmpty ? _rows : _rows.where((r) {
      final zone    = r['zone_name']    as String? ?? '';
      final product = r['product_name'] as String? ?? '';
      return zone.toLowerCase().contains(_searchQ) ||
             product.toLowerCase().contains(_searchQ);
    }).toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, kBottomNavClearance),
        itemCount: visibleRows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _historyCard(visibleRows[i]),
      ),
    );
  }

  Widget _historyCard(Map<String, dynamic> row) {
    final zoneName = row['zone_name'] as String? ?? '—';
    final zoneCode = row['zone_code'] as String?;
    final productName = row['product_name'] as String? ?? '—';
    final rate = (row['rate_per_kg'] as num?)?.toDouble() ?? 0;
    final prevRate = (row['prev_rate_per_kg'] as num?)?.toDouble();
    final difference = (row['difference'] as num?)?.toDouble() ?? 0;
    final effDate = row['effective_date'] as String?;
    final isLatest = row['is_active'] == true && (row['is_latest'] == true);
    final isActive = row['is_active'] == true;
    final updatedByEmail = row['updated_by_email'] as String?;
    final updatedAt = row['updated_at'] as String?;

    final dateLabel = effDate != null
        ? DateFormat('d MMM yyyy').format(DateTime.parse(effDate))
        : '—';
    final updatedAtLabel = updatedAt != null
        ? DateFormat('d MMM, h:mm a')
        .format(DateTime.parse(updatedAt).toLocal())
        : null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(
            color: isLatest ? kGold.withValues(alpha: 0.5) : kBorderLight,
            width: isLatest ? 1.4 : 1),
        boxShadow: kCardShadow,
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: kNavy.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(kRadiusChip),
          ),
          child: const Icon(Icons.local_offer_outlined, size: 18, color: kNavy),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(
                    '$productName · $zoneName${zoneCode != null ? " ($zoneCode)" : ""}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: kNavy),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              if (isLatest)
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: kGold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6)),
                  child: const Text('CURRENT',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: kGold,
                          letterSpacing: 0.4)),
                ),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              if (prevRate != null) ...[
                Text('${Fmt.amount(prevRate)}/kg',
                    style: const TextStyle(
                        fontSize: 13,
                        color: kTextHint,
                        decoration: TextDecoration.lineThrough)),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward_rounded,
                    size: 12, color: kTextHint),
                const SizedBox(width: 6),
              ],
              Text('${Fmt.amount(rate)}/kg',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900, color: kNavy)),
              if (prevRate != null && difference != 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: (difference > 0 ? kSuccess : kError)
                          .withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(
                      difference > 0
                          ? '+${Fmt.amount(difference)}'
                          : '-${Fmt.amount(difference.abs())}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: difference > 0 ? kSuccess : kError)),
                ),
              ],
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.event_outlined, size: 12, color: kTextHint),
              const SizedBox(width: 3),
              Text('Effective $dateLabel',
                  style: const TextStyle(fontSize: 11, color: kTextHint)),
            ]),
            if (updatedByEmail != null || updatedAtLabel != null) ...[
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.person_outline_rounded,
                    size: 12, color: kTextHint),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                      [
                        if (updatedByEmail != null) updatedByEmail,
                        if (updatedAtLabel != null) updatedAtLabel,
                      ].join(' · '),
                      style: const TextStyle(fontSize: 11, color: kTextHint),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
            ],
            if (!isActive) ...[
              const SizedBox(height: 4),
              Text('Superseded',
                  style: TextStyle(
                      fontSize: 10,
                      color: kTextHint,
                      fontStyle: FontStyle.italic)),
            ],
          ]),
        ),
      ]),
    );
  }
}