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
import '../../../shared/widgets/tables/app_table.dart';

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
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = context.isDesktop;

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
          flex: 3,
          cellBuilder: (r) {
            final blocked = r['is_blocked'] as bool? ?? false;
            final active = r['is_active'] as bool? ?? true;
            return Row(children: [
              // Avatar circle
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: blocked
                      ? Colors.red.withValues(alpha: 0.1)
                      : kPrimary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Center(
                    child: Text(
                  (r['shop_name'] as String? ?? '?')[0].toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: blocked ? Colors.red : kPrimary,
                  ),
                )),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(
                r['shop_name'] as String? ?? '—',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? kTextMain : kTextSub,
                ),
                overflow: TextOverflow.ellipsis,
              )),
            ]);
          },
        ),
        AppTableColumn(
          label: 'Owner',
          flex: 2,
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
          flex: 2,
          cellBuilder: (r) => Text(
            r['address'] as String? ?? '—',
            style: const TextStyle(fontSize: 12, color: kTextHint),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        AppTableColumn(
          label: 'Risk',
          width: 90,
          alignment: Alignment.center,
          cellBuilder: (r) {
            final risk = r['risk_level'] as String? ?? 'low';
            final blocked = r['is_blocked'] as bool? ?? false;
            final active = r['is_active'] as bool? ?? true;
            if (blocked) {
              return const StatusChip(
                  label: 'Blocked',
                  color: Colors.red,
                  size: StatusChipSize.small);
            }
            if (!active) {
              return const StatusChip(
                  label: 'Inactive',
                  color: Colors.grey,
                  size: StatusChipSize.small);
            }
            if (risk == 'high') {
              return const StatusChip(
                  label: 'High Risk',
                  color: Colors.red,
                  size: StatusChipSize.small);
            }
            if (risk == 'medium') {
              return const StatusChip(
                  label: 'Med Risk',
                  color: Colors.orange,
                  size: StatusChipSize.small);
            }
            return const SizedBox.shrink();
          },
        ),
        AppTableColumn(
          label: '',
          width: 40,
          alignment: Alignment.center,
          cellBuilder: (_) =>
              const Icon(Icons.chevron_right, size: 16, color: kTextHint),
        ),
      ],
      rows: _filtered,
      onRowTap: (r) => context.push(R.retailerDetailPath(r['id'])),
      desktopPadding: const EdgeInsets.symmetric(horizontal: 16),
      rowDecoration: (r) {
        final blocked = r['is_blocked'] as bool? ?? false;
        final risk = r['risk_level'] as String? ?? 'low';
        Color? tint;
        if (blocked) {
          tint = Colors.red.withValues(alpha: 0.03);
        } else if (risk == 'high') tint = Colors.orange.withValues(alpha: 0.03);
        return BoxDecoration(
          color: tint ?? Colors.transparent,
          border: const Border(bottom: BorderSide(color: kBorder, width: 0.5)),
        );
      },
      emptyWidget: const AsyncStateView(
        loading: false,
        empty: true,
        emptyIcon: Icons.store_outlined,
        emptyMessage: 'No retailers found',
        child: SizedBox.shrink(),
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
