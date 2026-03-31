import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class RetailerDetailScreen extends StatefulWidget {
  const RetailerDetailScreen({super.key, required this.id});
  final String id;
  @override State<RetailerDetailScreen> createState() => _S();
}
class _S extends State<RetailerDetailScreen> {
  final _c = Supabase.instance.client;
  Map<String,dynamic>? _r;
  bool _loading = true;
  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await _c.from('retailers').select('*').eq('id', widget.id).maybeSingle();
    if (mounted) setState(() { _r = r; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingList());
    if (_r == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Not found')));
    final r = _r!;
    return Scaffold(
      appBar: AppBar(title: Text(r['shop_name'] as String), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader('DETAILS'),
          InfoRow('Shop', r['shop_name'] as String),
          if (r['owner_name'] != null) InfoRow('Owner', r['owner_name'] as String),
          if (r['phone'] != null) InfoRow('Phone', r['phone'] as String),
          if (r['address'] != null) InfoRow('Address', r['address'] as String),
          InfoRow('Status', (r['is_active'] as bool? ?? true) ? 'Active' : 'Inactive', valueColor: (r['is_active'] as bool? ?? true) ? kPrimary : Colors.red),
          InfoRow('Credit Limit', Fmt.amount((r['credit_limit'] as num?)?.toDouble() ?? 0)),
          InfoRow('Risk Level', (r['risk_level'] as String? ?? 'low').toUpperCase()),
        ])),
        const SizedBox(height: 16),
        ElevatedButton.icon(onPressed: () => context.go(R.retailerLedgerPath(widget.id)), icon: const Icon(Icons.account_balance_wallet_outlined, size: 18), label: const Text('View Ledger')),
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: () => context.go(R.orderCreate), icon: const Icon(Icons.add_shopping_cart_outlined, size: 18), label: const Text('New Order')),
      ]),
    );
  }
}
