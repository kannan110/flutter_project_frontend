import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class RetailersScreen extends ConsumerStatefulWidget {
  const RetailersScreen({super.key});
  @override ConsumerState<RetailersScreen> createState() => _S();
}

class _S extends ConsumerState<RetailersScreen> {
  final _c          = Supabase.instance.client;
  final _searchCtrl = TextEditingController();
  List<Map<String,dynamic>> _list     = [];
  List<Map<String,dynamic>> _filtered = [];
  bool _loading = true;

  @override void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => _applySearch(_searchCtrl.text));
  }
  @override void dispose() { _searchCtrl.dispose(); super.dispose(); }

  void _applySearch(String q) {
    if (!mounted) return;
    if (q.trim().isEmpty) { setState(() => _filtered = List.from(_list)); return; }
    final lower = q.toLowerCase();
    setState(() => _filtered = _list.where((r) =>
      (r['shop_name']  as String? ?? '').toLowerCase().contains(lower) ||
      (r['owner_name'] as String? ?? '').toLowerCase().contains(lower) ||
      (r['phone']      as String? ?? '').toLowerCase().contains(lower) ||
      (r['address']    as String? ?? '').toLowerCase().contains(lower)
    ).toList());
  }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    if (mounted) setState(() => _loading = true);
    try {
      final data = await _c.from('retailers')
          .select('id,shop_name,owner_name,phone,address,risk_level,is_active,is_blocked')
          .eq('trader_id', tid).order('shop_name');
      if (mounted) setState(() {
        _list     = List<Map<String,dynamic>>.from(data);
        _filtered = List.from(_list);
        _loading  = false;
      });
      _applySearch(_searchCtrl.text);
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Retailers'),
      actions: [
        IconButton(icon: const Icon(Icons.refresh_outlined), onPressed: _load),
      ]),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => context.push(R.retailerCreate),
      icon: const Icon(Icons.add),
      label: const Text('Add Retailer')),
    body: Column(children: [
      // Search bar
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: AppSearchBar(
          controller: _searchCtrl,
          hint: 'Search by name, phone, address...',
          onChanged: _applySearch,
          onClear: () { _searchCtrl.clear(); _applySearch(''); })),

      // Result count when searching
      if (_searchCtrl.text.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 4),
          child: Align(alignment: Alignment.centerLeft,
            child: Text(
              _filtered.isEmpty ? 'No results' : '${_filtered.length} retailer${_filtered.length == 1 ? '' : 's'} found',
              style: const TextStyle(fontSize: 12, color: kTextSub)))),

      Expanded(child: _loading
        ? const LoadingList()
        : _list.isEmpty
            ? EmptyState(
                icon: Icons.store_outlined,
                message: 'No retailers yet',
                sub: 'Add your first retailer to get started',
                onAction: () => context.push(R.retailerCreate),
                actionLabel: 'Add Retailer')
            : _filtered.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off_outlined,
                    message: 'No retailers match',
                    sub: 'Try a different name or phone number')
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final r       = _filtered[i];
                        final risk    = r['risk_level'] as String? ?? 'low';
                        final blocked = r['is_blocked'] as bool? ?? false;
                        final active  = r['is_active']  as bool? ?? true;

                        return InkWell(
                          onTap: () => context.push(R.retailerDetailPath(r['id'])),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: blocked ? Colors.red.shade200
                                     : risk == 'high' ? Colors.orange.shade200
                                     : kBorder),
                              boxShadow: [BoxShadow(
                                color: Colors.black.withValues(alpha: 0.025),
                                blurRadius: 6, offset: const Offset(0, 1))]),
                            child: Row(children: [
                              // Avatar
                              Container(
                                width: 46, height: 46,
                                decoration: BoxDecoration(
                                  color: blocked
                                      ? Colors.red.withValues(alpha: 0.1)
                                      : kPrimary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12)),
                                child: Center(child: Text(
                                  (r['shop_name'] as String? ?? '?')[0].toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w900,
                                    color: blocked ? Colors.red : kPrimary)))),
                              const SizedBox(width: 14),
                              Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Expanded(child: Text(
                                    r['shop_name'] as String,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700, fontSize: 15,
                                      color: active ? kTextMain : kTextSub))),
                                  if (blocked) const StatusBadge('blocked', Colors.red, small: true)
                                  else if (!active) const StatusBadge('inactive', Colors.grey, small: true),
                                ]),
                                if (r['owner_name'] != null) ...[
                                  const SizedBox(height: 2),
                                  Text(r['owner_name'] as String,
                                      style: const TextStyle(fontSize: 13, color: kTextSub,
                                          fontWeight: FontWeight.w500)),
                                ],
                                if (r['phone'] != null) ...[
                                  const SizedBox(height: 1),
                                  Row(children: [
                                    const Icon(Icons.phone_outlined, size: 11, color: kTextHint),
                                    const SizedBox(width: 4),
                                    Text(r['phone'] as String,
                                        style: const TextStyle(fontSize: 12, color: kTextHint)),
                                  ]),
                                ],
                                if (r['address'] != null) ...[
                                  const SizedBox(height: 1),
                                  Text(r['address'] as String,
                                      style: const TextStyle(fontSize: 11, color: kTextHint),
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                ],
                              ])),
                              const SizedBox(width: 8),
                              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                if (risk == 'high')
                                  const StatusBadge('High Risk', Colors.red, small: true)
                                else if (risk == 'medium')
                                  const StatusBadge('Med Risk', Colors.orange, small: true),
                                const SizedBox(height: 6),
                                const Icon(Icons.chevron_right, color: kTextHint, size: 20),
                              ]),
                            ])));
                      }))),
    ]));
}
