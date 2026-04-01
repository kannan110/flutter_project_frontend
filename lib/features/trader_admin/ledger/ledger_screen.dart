import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class LedgerScreen extends ConsumerStatefulWidget {
  const LedgerScreen({super.key});
  @override ConsumerState<LedgerScreen> createState() => _S();
}
class _S extends ConsumerState<LedgerScreen> {
  final _c = Supabase.instance.client;
  List<Map<String,dynamic>> _list = [];
  bool _loading = true;
  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    if (mounted) setState(() => _loading = true);
    try {
      // retailers columns: id, shop_name, owner_name, credit_limit (NOT outstanding_balance — no such column)
      // We get outstanding via get_retailer_outstanding RPC per retailer, but for list we just show retailers
      final data = await _c.from('retailers')
          .select('id,shop_name,owner_name,credit_limit,risk_level')
          .eq('trader_id', tid).eq('is_active', true).order('shop_name');
      if (mounted) setState(() { _list = List<Map<String,dynamic>>.from(data); _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ledger'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
    body: _loading ? const LoadingList() : _list.isEmpty ? const EmptyState(icon: Icons.account_balance_wallet_outlined, message: 'No retailers')
        : RefreshIndicator(onRefresh: _load, child: ListView.separated(
            padding: const EdgeInsets.all(16), itemCount: _list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final r = _list[i];
              final risk = r['risk_level'] as String? ?? 'low';
              return InkWell(
                onTap: () => context.push(R.retailerLedgerPath(r['id'])),
                borderRadius: BorderRadius.circular(12),
                child: WhiteCard(child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r['shop_name'] as String, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    if (r['owner_name'] != null) Text(r['owner_name'] as String, style: const TextStyle(fontSize: 12, color: kTextSub)),
                  ])),
                  if (risk == 'high') const StatusBadge('high risk', Colors.red, small: true)
                  else if (risk == 'medium') const StatusBadge('medium risk', Colors.orange, small: true),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, color: kTextHint, size: 18),
                ])),
              );
            })),
  );
}
