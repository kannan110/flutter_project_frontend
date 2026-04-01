import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class RetailersScreen extends ConsumerStatefulWidget {
  const RetailersScreen({super.key});
  @override ConsumerState<RetailersScreen> createState() => _S();
}
class _S extends ConsumerState<RetailersScreen> {
  final _c = Supabase.instance.client;
  List<Map<String,dynamic>> _list = [];
  bool _loading = true;
  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    if (mounted) setState(() => _loading = true);
    try {
      // retailers columns: id,shop_name,owner_name,phone,address,credit_limit,is_active,is_blocked,risk_level
      // NO outstanding_balance column — that's computed
      final data = await _c.from('retailers')
          .select('id,shop_name,owner_name,phone,address,risk_level,is_active,is_blocked')
          .eq('trader_id', tid).order('shop_name');
      if (mounted) setState(() { _list = List<Map<String,dynamic>>.from(data); _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Retailers'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
    floatingActionButton: FloatingActionButton.extended(onPressed: () => context.push(R.retailerCreate), icon: const Icon(Icons.add), label: const Text('Add Retailer')),
    body: _loading ? const LoadingList() : _list.isEmpty
        ? EmptyState(icon: Icons.store_outlined, message: 'No retailers yet', onAction: () => context.push(R.retailerCreate), actionLabel: 'Add Retailer')
        : RefreshIndicator(onRefresh: _load, child: ListView.separated(
            padding: const EdgeInsets.all(16), itemCount: _list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final r = _list[i];
              final risk = r['risk_level'] as String? ?? 'low';
              final blocked = r['is_blocked'] as bool? ?? false;
              return InkWell(
                onTap: () => context.push(R.retailerDetailPath(r['id'])),
                borderRadius: BorderRadius.circular(12),
                child: WhiteCard(child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(r['shop_name'] as String, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      if (blocked) ...[const SizedBox(width: 6), const StatusBadge('blocked', Colors.red, small: true)],
                    ]),
                    if (r['owner_name'] != null) Text(r['owner_name'] as String, style: const TextStyle(fontSize: 12, color: kTextSub)),
                    if (r['address'] != null) Text(r['address'] as String, style: const TextStyle(fontSize: 11, color: kTextHint), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ])),
                  if (risk == 'high') const StatusBadge('high risk', Colors.red, small: true)
                  else if (risk == 'medium') const StatusBadge('mid risk', Colors.orange, small: true),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, color: kTextHint, size: 18),
                ])),
              );
            })),
  );
}
