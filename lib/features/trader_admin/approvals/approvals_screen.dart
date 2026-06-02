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
import '../../../shared/widgets/filters/search_bar.dart';
import '../../../shared/widgets/tables/app_table.dart';

class ApprovalsScreen extends ConsumerStatefulWidget {
  const ApprovalsScreen({super.key});
  @override
  ConsumerState<ApprovalsScreen> createState() => _S();
}

class _S extends ConsumerState<ApprovalsScreen> {
  final _c          = Supabase.instance.client;
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _items    = [];
  List<Map<String, dynamic>> _filtered = [];
  bool    _loading = true;
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
    if (q.trim().isEmpty) { setState(() => _filtered = List.from(_items)); return; }
    final lower = q.toLowerCase();
    setState(() => _filtered = _items.where((d) {
      final o = d['orders']          as Map<String, dynamic>?;
      final r = o?['retailers']      as Map<String, dynamic>?;
      final a = d['delivery_agents'] as Map<String, dynamic>?;
      return (r?['shop_name'] as String? ?? '').toLowerCase().contains(lower) ||
          (a?['name']      as String? ?? '').toLowerCase().contains(lower);
    }).toList());
  }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final data = await _c.from('deliveries')
          .select('id,delivered_total_weight,received_total_weight,collected_amount,'
          'delivered_bird_count,is_partial_delivery,delivered_at,created_at,'
          'orders(id,estimated_birds,total_quantity,fulfilled_birds,'
          'partial_count,is_partial_delivery,retailers(shop_name)),'
          'delivery_agents(name)')
          .eq('trader_id', tid)
          .eq('status', 'delivered')
          .eq('approval_status', 'pending')
          .order('delivered_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _items    = List<Map<String, dynamic>>.from(data);
        _filtered = List.from(_items);
        _loading  = false;
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
        backgroundColor: kSurface,
        title: Row(children: [
          const Text('Pending Approvals'),
          if (_items.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.orange, borderRadius: BorderRadius.circular(10)),
              child: Text('${_items.length}',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ],
        ]),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),

      toolbar: ListToolbar(
        searchController: _searchCtrl,
        searchHint:       'Search by retailer or agent…',
        onSearch:         _applySearch,
        onClearSearch:    () { _searchCtrl.clear(); _applySearch(''); },
        secondaryActions: [
          if (_items.isNotEmpty)
            Container(
              margin:  const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: Colors.orange, borderRadius: BorderRadius.circular(8)),
              child: Text('${_items.length} pending',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          if (isDesktop)
            IconButton(
                icon: const Icon(Icons.refresh_outlined),
                onPressed: _load,
                tooltip: 'Refresh'),
        ],
      ),

      content: AsyncStateView(
        loading:      _loading,
        error:        _error,
        empty:        _filtered.isEmpty && !_loading,
        emptyIcon:    Icons.fact_check_outlined,
        emptyMessage: _items.isEmpty ? 'No pending approvals' : 'No results match',
        emptySub:     _items.isEmpty ? 'Delivered orders appear here for review' : null,
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
          label: 'Delivered',
          width: 120,
          cellBuilder: (d) {
            final dt = DateTime.tryParse(d['delivered_at'] as String? ?? '');
            return Text(
              dt != null ? DateFormat('d MMM, h:mm a').format(dt) : '—',
              style: const TextStyle(fontSize: 12, color: kTextSub),
            );
          },
        ),
        AppTableColumn(
          label: 'Retailer',
          flex:  2,
          cellBuilder: (d) {
            final o = d['orders']     as Map<String, dynamic>?;
            final r = o?['retailers'] as Map<String, dynamic>?;
            return Text(
              r?['shop_name'] as String? ?? '—',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            );
          },
        ),
        AppTableColumn(
          label: 'Agent',
          flex:  2,
          cellBuilder: (d) {
            final a = d['delivery_agents'] as Map<String, dynamic>?;
            return Text(
              a?['name'] as String? ?? '—',
              style: const TextStyle(fontSize: 13, color: kTextSub),
              overflow: TextOverflow.ellipsis,
            );
          },
        ),
        AppTableColumn(
          label:     'Weight (kg)',
          width:     110,
          alignment: Alignment.centerRight,
          cellBuilder: (d) {
            final w = ((d['received_total_weight'] ?? d['delivered_total_weight']) as num?)
                ?.toDouble() ?? 0;
            return Text(
              w > 0 ? '${w.toStringAsFixed(1)} kg' : '—',
              style: const TextStyle(fontSize: 13, color: kTextSub),
            );
          },
        ),
        AppTableColumn(
          label:     'Birds',
          width:     70,
          alignment: Alignment.centerRight,
          cellBuilder: (d) {
            final b = (d['delivered_bird_count'] as num?)?.toInt() ?? 0;
            return Text(
              b > 0 ? '$b' : '—',
              style: const TextStyle(fontSize: 13, color: kTextSub),
            );
          },
        ),
        AppTableColumn(
          label:     'Cash',
          width:     100,
          alignment: Alignment.centerRight,
          cellBuilder: (d) {
            final cash = (d['collected_amount'] as num?)?.toDouble() ?? 0;
            return Text(
              cash > 0 ? Fmt.amount(cash) : '—',
              style: TextStyle(
                fontSize:   13,
                fontWeight: FontWeight.w600,
                color:      cash > 0 ? Colors.green.shade700 : kTextHint,
              ),
            );
          },
        ),
        AppTableColumn(
          label:     'Type',
          width:     90,
          alignment: Alignment.center,
          cellBuilder: (d) {
            final isPartial = d['is_partial_delivery'] == true;
            return StatusChip(
              label: isPartial ? 'Partial' : 'Full',
              color: isPartial ? Colors.orange : Colors.teal,
              size:  StatusChipSize.small,
            );
          },
        ),
        AppTableColumn(
          label:     '',
          width:     40,
          alignment: Alignment.center,
          cellBuilder: (_) =>
          const Icon(Icons.chevron_right, size: 16, color: kTextHint),
        ),
      ],
      rows:     _filtered,
      onRowTap: (d) => context.push(R.approvalDetailPath(d['id'])),
      desktopPadding: const EdgeInsets.symmetric(horizontal: 16),
      rowDecoration: (d) => BoxDecoration(
        border: const Border(bottom: BorderSide(color: kBorder, width: 0.5)),
        color:  Colors.orange.withValues(alpha: 0.02),
      ),
      emptyWidget: AsyncStateView(
        loading: false, empty: true,
        emptyIcon: Icons.fact_check_outlined,
        emptyMessage: 'No pending approvals',
        child: const SizedBox.shrink(),
      ),
    );
  }

  // ── Mobile card list ──────────────────────────────────────────────────────

  Widget _buildMobileList() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding:          const EdgeInsets.all(16),
        itemCount:        _filtered.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder:      (_, i)  => _ApprovalCard(item: _filtered[i]),
      ),
    );
  }
}

// ── Mobile approval card ──────────────────────────────────────────────────────

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({required this.item});
  final Map<String, dynamic> item;

  Widget _chip(String label, IconData icon, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: c),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c)),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final o          = item['orders']          as Map<String, dynamic>?;
    final r          = o?['retailers']         as Map<String, dynamic>?;
    final a          = item['delivery_agents'] as Map<String, dynamic>?;
    final w          = ((item['received_total_weight'] ?? item['delivered_total_weight']) as num?)
        ?.toDouble() ?? 0;
    final birds      = (item['delivered_bird_count'] as num?)?.toInt() ?? 0;
    final isPartial  = item['is_partial_delivery'] == true;
    final cash       = (item['collected_amount']    as num?)?.toDouble() ?? 0;
    final deliveredAt = DateTime.tryParse(item['delivered_at'] as String? ?? '');
    final totalBirds = (o?['estimated_birds'] as num?)?.toInt() ?? 0;
    final fulfilledB = (o?['fulfilled_birds']  as num?)?.toInt() ?? 0;
    final pct        = totalBirds > 0 ? (fulfilledB / totalBirds).clamp(0.0, 1.0) : 1.0;
    final attempt    = (o?['partial_count'] as num?)?.toInt() ?? 1;

    return InkWell(
      onTap: () => context.push(R.approvalDetailPath(item['id'])),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade200, width: 1.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r?['shop_name'] as String? ?? '—',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('Agent: ${a?['name'] ?? '—'}',
                  style: const TextStyle(fontSize: 12, color: kTextSub)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              StatusChip(label: 'review', color: Colors.orange),
              if (isPartial) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(4)),
                  child: Text('Partial #$attempt',
                      style: const TextStyle(
                          fontSize: 9, fontWeight: FontWeight.w800,
                          color: Colors.deepOrange)),
                ),
              ],
            ]),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: kTextHint, size: 18),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _chip('${w.toStringAsFixed(1)} kg', Icons.scale_outlined, Colors.teal),
            if (birds > 0) ...[const SizedBox(width: 6), _chip('$birds birds', Icons.numbers, Colors.blue)],
            if (cash > 0)  ...[const SizedBox(width: 6), _chip(Fmt.amount(cash), Icons.money_outlined, Colors.green)],
            if (deliveredAt != null) ...[
              const Spacer(),
              Text(DateFormat('d MMM, h:mm a').format(deliveredAt),
                  style: const TextStyle(fontSize: 10, color: kTextHint)),
            ],
          ]),
          if (isPartial) ...[
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Order: $fulfilledB / $totalBirds birds fulfilled',
                  style: const TextStyle(fontSize: 10, color: kTextSub)),
              Text('${(pct * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700, color: Colors.orange)),
            ]),
            const SizedBox(height: 3),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value:      pct, minHeight: 5,
                backgroundColor: Colors.orange.shade100,
                valueColor: const AlwaysStoppedAnimation(Colors.orange),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}