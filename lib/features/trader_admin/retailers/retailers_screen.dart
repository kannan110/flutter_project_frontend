import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/responsive_layout.dart';
import '../../../shared/widgets/common/async_state_view.dart';
import '../../../shared/widgets/common/status_chip.dart';
import '../../../shared/widgets/filters/search_bar.dart' hide ListToolbar;
import '../../../shared/widgets/tables/app_table.dart';

class RetailersScreen extends ConsumerStatefulWidget {
  const RetailersScreen({super.key});
  @override
  ConsumerState<RetailersScreen> createState() => _S();
}

class _S extends ConsumerState<RetailersScreen> {
  final _c          = Supabase.instance.client;
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _list     = [];
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
    if (q.trim().isEmpty) { setState(() => _filtered = List.from(_list)); return; }
    final lower = q.toLowerCase();
    setState(() => _filtered = _list.where((r) =>
    (r['shop_name']  as String? ?? '').toLowerCase().contains(lower) ||
        (r['owner_name'] as String? ?? '').toLowerCase().contains(lower) ||
        (r['phone']      as String? ?? '').toLowerCase().contains(lower) ||
        (r['address']    as String? ?? '').toLowerCase().contains(lower),
    ).toList());
  }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final data = await _c.from('retailers')
          .select('id,shop_name,owner_name,phone,address,risk_level,is_active,is_blocked')
          .eq('trader_id', tid)
          .order('shop_name');
      if (!mounted) return;
      setState(() {
        _list     = List<Map<String, dynamic>>.from(data);
        _filtered = List.from(_list);
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
        title: const Text('Retailers'),
        actions: [IconButton(icon: const Icon(Icons.refresh_outlined), onPressed: _load)],
      ),

      toolbar: ListToolbar(
        searchController: _searchCtrl,
        searchHint:       'Search by name, phone, address…',
        onSearch:         _applySearch,
        onClearSearch:    () { _searchCtrl.clear(); _applySearch(''); },
        primaryLabel:     'Add Retailer',
        primaryIcon:      Icons.add_rounded,
        onPrimary:        () => context.push(R.retailerCreate),
        secondaryActions: isDesktop
            ? [IconButton(
            icon: const Icon(Icons.refresh_outlined),
            onPressed: _load, tooltip: 'Refresh')]
            : null,
      ),

      fab: isDesktop ? null : FloatingActionButton.extended(
        onPressed: () => context.push(R.retailerCreate),
        icon:      const Icon(Icons.add),
        label:     const Text('Add Retailer'),
      ),

      content: AsyncStateView(
        loading:      _loading,
        error:        _error,
        empty:        _filtered.isEmpty && !_loading,
        emptyIcon:    Icons.store_outlined,
        emptyMessage: _list.isEmpty ? 'No retailers yet' : 'No retailers match',
        emptySub:     _list.isEmpty ? 'Add your first retailer to get started' : null,
        onAction:     _list.isEmpty ? () => context.push(R.retailerCreate) : null,
        actionLabel:  'Add Retailer',
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
          label: 'Shop Name',
          flex:  3,
          cellBuilder: (r) {
            final blocked = r['is_blocked'] as bool? ?? false;
            final active  = r['is_active']  as bool? ?? true;
            return Row(children: [
              // Avatar circle
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: blocked
                      ? Colors.red.withValues(alpha: 0.1)
                      : kPrimary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Center(child: Text(
                  (r['shop_name'] as String? ?? '?')[0].toUpperCase(),
                  style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800,
                    color: blocked ? Colors.red : kPrimary,
                  ),
                )),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(
                r['shop_name'] as String? ?? '—',
                style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600,
                  color: active ? kTextMain : kTextSub,
                ),
                overflow: TextOverflow.ellipsis,
              )),
            ]);
          },
        ),
        AppTableColumn(
          label: 'Owner',
          flex:  2,
          cellBuilder: (r) => Text(
            r['owner_name'] as String? ?? '—',
            style: const TextStyle(fontSize: 13, color: kTextSub),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        AppTableColumn(
          label: 'Phone',
          width: 130,
          cellBuilder: (r) => Text(
            r['phone'] as String? ?? '—',
            style: const TextStyle(fontSize: 13, color: kTextSub),
          ),
        ),
        AppTableColumn(
          label: 'Address',
          flex:  2,
          cellBuilder: (r) => Text(
            r['address'] as String? ?? '—',
            style: const TextStyle(fontSize: 12, color: kTextHint),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        AppTableColumn(
          label:     'Risk',
          width:     90,
          alignment: Alignment.center,
          cellBuilder: (r) {
            final risk    = r['risk_level'] as String? ?? 'low';
            final blocked = r['is_blocked'] as bool? ?? false;
            final active  = r['is_active']  as bool? ?? true;
            if (blocked) return const StatusChip(label: 'Blocked', color: Colors.red, size: StatusChipSize.small);
            if (!active) return const StatusChip(label: 'Inactive', color: Colors.grey, size: StatusChipSize.small);
            if (risk == 'high')   return const StatusChip(label: 'High Risk', color: Colors.red, size: StatusChipSize.small);
            if (risk == 'medium') return const StatusChip(label: 'Med Risk', color: Colors.orange, size: StatusChipSize.small);
            return const SizedBox.shrink();
          },
        ),
        AppTableColumn(
          label:     '',
          width:     40,
          alignment: Alignment.center,
          cellBuilder: (_) => const Icon(Icons.chevron_right, size: 16, color: kTextHint),
        ),
      ],
      rows:     _filtered,
      onRowTap: (r) => context.push(R.retailerDetailPath(r['id'])),
      desktopPadding: const EdgeInsets.symmetric(horizontal: 16),
      rowDecoration: (r) {
        final blocked = r['is_blocked'] as bool? ?? false;
        final risk    = r['risk_level'] as String? ?? 'low';
        Color? tint;
        if (blocked)          tint = Colors.red.withValues(alpha: 0.03);
        else if (risk == 'high') tint = Colors.orange.withValues(alpha: 0.03);
        return BoxDecoration(
          color:  tint ?? Colors.transparent,
          border: const Border(bottom: BorderSide(color: kBorder, width: 0.5)),
        );
      },
      emptyWidget: AsyncStateView(
        loading: false, empty: true,
        emptyIcon: Icons.store_outlined,
        emptyMessage: 'No retailers found',
        child: const SizedBox.shrink(),
      ),
      footerWidget: Text(
        '${_filtered.length} retailers',
        style: const TextStyle(fontSize: 12, color: kTextHint),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ── Mobile card list ──────────────────────────────────────────────────────

  Widget _buildMobileList() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding:          const EdgeInsets.fromLTRB(16, 4, 16, 100),
        itemCount:        _filtered.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder:      (_, i)  => _RetailerCard(retailer: _filtered[i]),
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
    final risk    = retailer['risk_level'] as String? ?? 'low';
    final blocked = retailer['is_blocked'] as bool? ?? false;
    final active  = retailer['is_active']  as bool? ?? true;

    return InkWell(
      onTap:        () => context.push(R.retailerDetailPath(retailer['id'])),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: blocked ? Colors.red.shade200
                : risk == 'high' ? Colors.orange.shade200
                : kBorder,
          ),
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 6, offset: const Offset(0, 1),
          )],
        ),
        child: Row(children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              color: blocked
                  ? Colors.red.withValues(alpha: 0.1)
                  : kPrimary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: Text(
              (retailer['shop_name'] as String? ?? '?')[0].toUpperCase(),
              style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w900,
                color: blocked ? Colors.red : kPrimary,
              ),
            )),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(
                retailer['shop_name'] as String? ?? '—',
                style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 15,
                  color: active ? kTextMain : kTextSub,
                ),
              )),
              if (blocked) const StatusChip(label: 'blocked', color: Colors.red, size: StatusChipSize.small)
              else if (!active) const StatusChip(label: 'inactive', color: Colors.grey, size: StatusChipSize.small),
            ]),
            if (retailer['owner_name'] != null) ...[
              const SizedBox(height: 2),
              Text(retailer['owner_name'] as String,
                  style: const TextStyle(fontSize: 13, color: kTextSub, fontWeight: FontWeight.w500)),
            ],
            if (retailer['phone'] != null) ...[
              const SizedBox(height: 1),
              Row(children: [
                const Icon(Icons.phone_outlined, size: 11, color: kTextHint),
                const SizedBox(width: 4),
                Text(retailer['phone'] as String,
                    style: const TextStyle(fontSize: 12, color: kTextHint)),
              ]),
            ],
          ])),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (risk == 'high')
              const StatusChip(label: 'High Risk', color: Colors.red, size: StatusChipSize.small)
            else if (risk == 'medium')
              const StatusChip(label: 'Med Risk', color: Colors.orange, size: StatusChipSize.small),
            const SizedBox(height: 6),
            const Icon(Icons.chevron_right, color: kTextHint, size: 20),
          ]),
        ]),
      ),
    );
  }
}