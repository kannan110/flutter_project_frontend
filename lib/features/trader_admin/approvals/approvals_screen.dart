import 'dart:async';

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
import '../../../shared/widgets/filters/search_bar.dart' hide ListToolbar;
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
  bool    _approvingAll = false;
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
          'partial_count,is_partial_delivery,retailers(shop_name),'
          'order_items(master_products(name))),'
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

  // ── Approve All ───────────────────────────────────────────────────────────
  // Reuses the EXISTING single-order lifecycle: every order is approved via
  // the same `approve_delivery_and_order` RPC used by ApprovalDetailScreen,
  // called once per eligible pending delivery, sequentially. No new approval
  // logic, no new validations, no rate resolution logic — same automatic
  // rate resolution the RPC already falls back to when no manual per-item
  // rate override is supplied (i.e. exactly what happens today for any order
  // approved without editing the rate fields).
  //
  // Sequential, not a single wrapping transaction: each order commits (or
  // fails) independently, so one bad order cannot roll back others already
  // approved, and progress can be reported incrementally. See chat for the
  // full audit of why this is preferred over parallel/batched execution.
  Future<void> _approveAll() async {
    if (_items.isEmpty || _approvingAll) return;

    final ok = await confirmDialog(
      context,
      title: 'Approve All Orders',
      message: 'Approve all pending orders?\n\n'
          'Pending: ${_items.length} orders\n\n'
          'This will approve all eligible pending orders using the same '
          'process as approving one at a time. Orders needing a custom rate '
          'will use automatic rate resolution.',
      confirmText: 'Approve All',
      confirmColor: kPrimary,
    );
    if (!ok || !mounted) return;

    // Snapshot the current list so the run operates on a fixed, known set —
    // re-fetching the "pending" query mid-run could otherwise pick up orders
    // that arrived after the user confirmed.
    final toApprove = List<Map<String, dynamic>>.from(_items);
    final userId = ref.read(appUserProvider).valueOrNull?.userId;

    int approved = 0;
    int failed = 0;
    final failures = <Map<String, String>>[]; // {retailer, error}
    final invoiceDate = DateTime.now().toIso8601String().split('T')[0];

    setState(() => _approvingAll = true);

    // Non-dismissible progress dialog, updated in place as each order settles.
    late StateSetter progressSetState;
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        progressSetState = setDialogState;
        final total = toApprove.length;
        final done = approved + failed;
        return AlertDialog(
          title: const Text('Approving Orders…'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: total == 0 ? 0 : done / total),
              const SizedBox(height: 12),
              Text('Approved: $approved   ·   Failed: $failed   ·   $done / $total'),
            ],
          ),
        );
      }),
    ));

    for (final delivery in toApprove) {
      final deliveryId = delivery['id'] as String;
      final order = delivery['orders'] as Map<String, dynamic>?;
      final retailer = order?['retailers'] as Map<String, dynamic>?;
      final shopName = retailer?['shop_name'] as String? ?? 'Unknown retailer';

      try {
        // Same RPC, same shape as ApprovalDetailScreen._approve(), with no
        // manual rate override — matches the RPC's own automatic-resolution
        // default path (identical to a single-/multi-product order approved
        // without touching the rate fields).
        await _c.rpc('approve_delivery_and_order', params: {
          'p_delivery_id': deliveryId,
          'p_final_rate': null,
          'p_final_amount': null,
          'p_approved_by': userId,
          'p_approval_notes': 'Bulk approved via Approve All',
          'p_invoice_date': invoiceDate,
        });
        approved++;
      } catch (e) {
        failed++;
        failures.add({
          'retailer': shopName,
          'error': e
              .toString()
              .replaceAll('Exception: ', '')
              .replaceAll('PostgrestException(message: ', ''),
        });
      }
      if (mounted) progressSetState(() {});
    }

    if (mounted) Navigator.of(context, rootNavigator: true).pop(); // close progress dialog
    setState(() => _approvingAll = false);
    await _load(); // refresh the pending list

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve All — Complete'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Approved: $approved', style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('Failed: $failed',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: failed > 0 ? kError : null)),
              if (failures.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Failed orders (review individually):',
                    style: TextStyle(fontSize: 12, color: kTextHint)),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView(
                    shrinkWrap: true,
                    children: failures
                        .map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('• ${f['retailer']}: ${f['error']}',
                          style: const TextStyle(fontSize: 12)),
                    ))
                        .toList(),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
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
          if (_items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: OutlinedButton.icon(
                onPressed: _approvingAll ? null : _approveAll,
                icon: const Icon(Icons.done_all_rounded, size: 16),
                label: const Text('Approve All'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kPrimary,
                  side: BorderSide(color: kPrimary),
                ),
              ),
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
            final o   = d['orders']     as Map<String, dynamic>?;
            final r   = o?['retailers'] as Map<String, dynamic>?;
            final lbl = _ApprovalCard._productLabel(d);
            final c   = _ApprovalCard._productColor(lbl);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(r?['shop_name'] as String? ?? '—',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                if (lbl.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: c.withValues(alpha: 0.3))),
                    child: Text(lbl,
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: c)),
                  ),
              ],
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
        padding:          const EdgeInsets.fromLTRB(16, 16, 16, kBottomNavClearance),
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

  // ── Product helpers (display-only) ────────────────────────────────────────
  static String _productLabel(Map<String, dynamic> delivery) {
    final o     = delivery['orders'] as Map<String, dynamic>?;
    final items = (o?['order_items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
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
    if (l.contains('country')) return const Color(0xFF6D4C41);
    if (l.contains('quail'))   return Colors.purple;
    if (l.contains('multi'))   return Colors.indigo;
    return const Color(0xFF00796B); // broiler
  }

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
  @override
  Widget build(BuildContext context) {
    final o           = item['orders']          as Map<String, dynamic>?;
    final r           = o?['retailers']         as Map<String, dynamic>?;
    final a           = item['delivery_agents'] as Map<String, dynamic>?;
    final w           = ((item['received_total_weight'] ?? item['delivered_total_weight']) as num?)
        ?.toDouble() ?? 0;
    final birds       = (item['delivered_bird_count'] as num?)?.toInt() ?? 0;
    final isPartial   = item['is_partial_delivery'] == true;
    final cash        = (item['collected_amount']     as num?)?.toDouble() ?? 0;
    final deliveredAt = DateTime.tryParse(item['delivered_at'] as String? ?? '');
    final totalBirds  = (o?['estimated_birds']  as num?)?.toInt() ?? 0;
    final fulfilledB  = (o?['fulfilled_birds']  as num?)?.toInt() ?? 0;
    final pct         = totalBirds > 0 ? (fulfilledB / totalBirds).clamp(0.0, 1.0) : 1.0;
    final attempt     = (o?['partial_count'] as num?)?.toInt() ?? 1;
    final shopName    = r?['shop_name'] as String? ?? '—';
    final agentName   = a?['name']     as String? ?? '—';

    return InkWell(
      onTap: () => context.push(R.approvalDetailPath(item['id'])),
      borderRadius: BorderRadius.circular(kRadiusCard),
      child: Container(
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border: Border.all(
              color: Colors.orange.withValues(alpha: 0.4), width: 1.5),
          boxShadow: kCardShadow,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.04),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(kRadiusCard)),
              border: Border(bottom: BorderSide(color: kBorderLight.withValues(alpha: 0.5))),
            ),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFFEA580C), Color(0xFFF97316)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(child: Text(
                  shopName.isNotEmpty ? shopName[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white),
                )),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(shopName, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                        color: kNavy, letterSpacing: -0.3)),
                const SizedBox(height: 2),
                // ── Product chip (display-only) ───────────────────────────
                Builder(builder: (_) {
                  final lbl = _productLabel(item);
                  if (lbl.isEmpty) return const SizedBox.shrink();
                  final c = _productColor(lbl);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: c.withValues(alpha: 0.3))),
                    child: Text(lbl,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c)),
                  );
                }),
                Text('Agent: $agentName', style: const TextStyle(
                    fontSize: 11, color: kTextHint, fontWeight: FontWeight.w600)),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(kRadiusChip),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: const Text('REVIEW', style: TextStyle(fontSize: 9,
                      fontWeight: FontWeight.w900, color: Colors.orange, letterSpacing: 0.5)),
                ),
                if (isPartial) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.deepOrange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4)),
                    child: Text('Partial #$attempt', style: const TextStyle(fontSize: 9,
                        fontWeight: FontWeight.w800, color: Colors.deepOrange)),
                  ),
                ],
              ]),
            ]),
          ),
          // Stats
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: [
              _chip('${w.toStringAsFixed(1)} kg', Icons.scale_outlined, Colors.teal),
              if (birds > 0) ...[const SizedBox(width: 8),
                _chip('$birds birds', Icons.egg_alt_outlined, kNavy)],
              if (cash > 0) ...[const SizedBox(width: 8),
                _chip(Fmt.amount(cash), Icons.payments_outlined, Colors.green)],
              const Spacer(),
              if (deliveredAt != null)
                Text(DateFormat('d MMM, h:mm a').format(deliveredAt.toLocal()),
                    style: const TextStyle(fontSize: 10, color: kTextHint)),
            ]),
          ),
          if (isPartial) Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Fulfilled: $fulfilledB / $totalBirds birds',
                    style: const TextStyle(fontSize: 11, color: kTextSub, fontWeight: FontWeight.w600)),
                Text('${(pct * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.orange)),
              ]),
              const SizedBox(height: 4),
              ClipRRect(borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: pct, minHeight: 6,
                      backgroundColor: Colors.orange.withValues(alpha: 0.15),
                      valueColor: const AlwaysStoppedAnimation(Colors.orange))),
            ]),
          ),
          const SizedBox(height: 14),
        ]),
      ),
    );
  }
}