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
          .order('invoice_date', ascending: false)
          .limit(200);
      if (!mounted) return;
      final list = List<Map<String, dynamic>>.from(data);
      double rev = 0, out = 0;
      for (final inv in list) {
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
          label: 'Invoice #',
          width: 120,
          cellBuilder: (inv) => Text(
            inv['invoice_number'] as String? ?? '—',
            style: const TextStyle(fontSize: 12, color: kTextSub),
          ),
        ),
        AppTableColumn(
          label: 'Date',
          width: 100,
          cellBuilder: (inv) {
            final date = DateTime.tryParse(inv['invoice_date'] as String? ?? '');
            return Text(
              date != null ? DateFormat('d MMM y').format(date) : '—',
              style: const TextStyle(fontSize: 13, color: kTextSub),
            );
          },
        ),
        AppTableColumn(
          label: 'Retailer',
          flex:  3,
          cellBuilder: (inv) {
            final r = inv['retailers'] as Map<String, dynamic>?;
            return Text(
              r?['shop_name'] as String? ?? '—',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            );
          },
        ),
        AppTableColumn(
          label:     'Birds',
          width:     70,
          alignment: Alignment.centerRight,
          cellBuilder: (inv) => Text(
            '${inv['bird_count'] ?? 0}',
            style: const TextStyle(fontSize: 13, color: kTextSub),
          ),
        ),
        AppTableColumn(
          label:     'Qty (kg)',
          width:     90,
          alignment: Alignment.centerRight,
          cellBuilder: (inv) => Text(
            '${(inv['quantity_kg'] as num?)?.toStringAsFixed(1) ?? '0'} kg',
            style: const TextStyle(fontSize: 13, color: kTextSub),
          ),
        ),
        AppTableColumn(
          label:     'Total',
          width:     110,
          alignment: Alignment.centerRight,
          cellBuilder: (inv) {
            final total = (inv['total_amount'] as num?)?.toDouble() ?? 0;
            return Text(
              Fmt.amount(total),
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: kPrimary),
            );
          },
        ),
        AppTableColumn(
          label:     'Balance',
          width:     110,
          alignment: Alignment.centerRight,
          cellBuilder: (inv) {
            final bal = (inv['balance_amount'] as num?)?.toDouble() ?? 0;
            return Text(
              bal > 0 ? Fmt.amount(bal) : '—',
              style: TextStyle(
                fontSize:   13,
                fontWeight: FontWeight.w600,
                color:      bal > 0 ? Colors.orange : kTextHint,
              ),
            );
          },
        ),
        AppTableColumn(
          label:     'Status',
          width:     100,
          alignment: Alignment.center,
          cellBuilder: (inv) =>
              StatusChip.order(inv['status'] as String? ?? 'draft',
                  size: StatusChipSize.small),
        ),
        AppTableColumn(
          label:     '',
          width:     40,
          alignment: Alignment.center,
          cellBuilder: (_) => const Icon(Icons.chevron_right, size: 16, color: kTextHint),
        ),
      ],
      rows:     _filtered,
      onRowTap: (inv) => context.push(R.invoiceDetailPath(inv['id'])),
      desktopPadding: const EdgeInsets.symmetric(horizontal: 16),
      rowDecoration: (inv) {
        final bal = (inv['balance_amount'] as num?)?.toDouble() ?? 0;
        return BoxDecoration(
          color:  bal > 0
              ? Colors.orange.withValues(alpha: 0.02)
              : Colors.transparent,
          border: const Border(bottom: BorderSide(color: kBorder, width: 0.5)),
        );
      },
      emptyWidget: AsyncStateView(
        loading: false, empty: true,
        emptyIcon: Icons.receipt_long_outlined,
        emptyMessage: 'No invoices found',
        child: const SizedBox.shrink(),
      ),
    );
  }

  // ── Mobile list ───────────────────────────────────────────────────────────

  Widget _buildMobileList() {
    return RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          padding:          const EdgeInsets.fromLTRB(14, 14, 14, kBottomNavClearance),
          itemCount:        _filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder:      (_, i)  => _InvoiceCard(invoice: _filtered[i]),
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
    final total   = (invoice['total_amount']   as num?)?.toDouble() ?? 0;
    final balance = (invoice['balance_amount'] as num?)?.toDouble() ?? 0;

    return InkWell(
      onTap:        () => context.push(R.invoiceDetailPath(invoice['id'])),
      borderRadius: BorderRadius.circular(kRadiusCard),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:        kSurface,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border: Border.all(
              color: balance > 0
                  ? Colors.orange.withValues(alpha: 0.35)
                  : kBorderLight,
              width: balance > 0 ? 1.5 : 0.8),
          boxShadow: kCardShadow,
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(invoice['invoice_number'] as String? ?? '—',
                style: const TextStyle(fontSize: 11, color: kTextHint, fontWeight: FontWeight.w600)),
            Text(r?['shop_name'] as String? ?? '—',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: kNavy)),
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
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w900, color: kNavy)),
            if (balance > 0)
              Text('Due: ${Fmt.amount(balance)}',
                  style: const TextStyle(
                      fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w600)),
            StatusChip.order(status, size: StatusChipSize.small),
          ]),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, color: kTextHint, size: 18),
        ]),
      ),
    );
  }
}