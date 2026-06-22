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
import '../../../shared/widgets/common/status_chip.dart';
import '../../../shared/widgets/filters/filter_bar.dart';
import '../../../shared/widgets/filters/search_bar.dart' hide ListToolbar;
import '../../../shared/widgets/tables/app_table.dart';

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
          desktop: (_) => _buildDesktopTable(rows),
        ),
      ),
    );
  }

  // ── Desktop table ─────────────────────────────────────────────────────────

  Widget _buildDesktopTable(List<Map<String, dynamic>> rows) {
    return AppTable<Map<String, dynamic>>(
      columns: [
        AppTableColumn(
          label: 'Retailer',
          flex:  3,
          cellBuilder: (r) => Text(
            r['shop_name'] as String? ?? '—',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        AppTableColumn(
          label:     'Outstanding',
          width:     130,
          alignment: Alignment.centerRight,
          cellBuilder: (r) {
            final amt = (r['outstanding_amount'] as num?)?.toDouble() ?? 0;
            return Text(
              amt > 0 ? Fmt.amount(amt) : '—',
              style: TextStyle(
                fontSize:   13,
                fontWeight: FontWeight.w700,
                color:      amt > 0 ? Colors.orange : kTextHint,
              ),
            );
          },
        ),
        AppTableColumn(
          label:     'Credit Limit',
          width:     120,
          alignment: Alignment.centerRight,
          cellBuilder: (r) {
            final lim = (r['credit_limit'] as num?)?.toDouble() ?? 0;
            return Text(
              lim > 0 ? Fmt.amount(lim) : '—',
              style: const TextStyle(fontSize: 13, color: kTextSub),
            );
          },
        ),
        AppTableColumn(
          label:     'Last Payment',
          width:     110,
          alignment: Alignment.centerRight,
          cellBuilder: (r) {
            final days = (r['days_since_payment'] as num?)?.toInt();
            return Text(
              days != null ? '${days}d ago' : '—',
              style: TextStyle(
                fontSize: 12,
                color:    days != null && days > 30 ? Colors.red : kTextSub,
              ),
            );
          },
        ),
        AppTableColumn(
          label:     'Risk',
          width:     110,
          alignment: Alignment.center,
          cellBuilder: (r) {
            final status = r['risk_status'] as String? ?? 'healthy';
            return StatusChip(
              label: _riskLabel(status),
              color: _riskColor(status),
              size:  StatusChipSize.small,
            );
          },
        ),
        AppTableColumn(
          label:     '',
          width:     40,
          alignment: Alignment.center,
          cellBuilder: (_) => const Icon(Icons.chevron_right, size: 16, color: kTextHint),
        ),
      ],
      rows:     rows,
      onRowTap: (r) => context.push(R.retailerLedgerPath(r['retailer_id'] ?? r['id'])),
      desktopPadding: const EdgeInsets.symmetric(horizontal: 16),
      rowDecoration: (r) {
        final status = r['risk_status'] as String? ?? 'healthy';
        Color? tint;
        if (status == 'over_limit' || status == 'overdue_30d')
          tint = Colors.red.withValues(alpha: 0.03);
        else if (status == 'near_limit' || status == 'overdue_15d')
          tint = Colors.orange.withValues(alpha: 0.03);
        return BoxDecoration(
          color:  tint ?? Colors.transparent,
          border: const Border(bottom: BorderSide(color: kBorder, width: 0.5)),
        );
      },
      emptyWidget: AsyncStateView(
        loading: false, empty: true,
        emptyIcon: Icons.account_balance_wallet_outlined,
        emptyMessage: 'No retailers found',
        child: const SizedBox.shrink(),
      ),
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
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: kNavy)),
            if (item['owner_name'] != null) ...[
              const SizedBox(height: 2),
              Text(item['owner_name'] as String,
                  style: const TextStyle(fontSize: 12, color: kTextSub)),
            ],
            const SizedBox(height: 6),
            Row(children: [
              if (isAtRisk) ...[_chip(riskLabel, riskColor), const SizedBox(width: 6)],
              if (days != null)
                Text('${days}d since payment',
                    style: TextStyle(
                      fontSize: 11,
                      color: days > 30 ? Colors.red : kTextSub,
                    )),
            ]),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(Fmt.amount(amt),
                style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w900,
                  color: amt > 0 ? Colors.orange : Colors.green,
                )),
            if (limit > 0)
              Text('Limit: ${Fmt.amount(limit)}',
                  style: const TextStyle(fontSize: 11, color: kTextHint)),
            const SizedBox(height: 4),
            const Icon(Icons.chevron_right, color: kTextHint, size: 18),
          ]),
        ]),
      ),
    );
  }
}