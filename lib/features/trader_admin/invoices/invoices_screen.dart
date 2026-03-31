import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class InvoicesScreen extends ConsumerStatefulWidget {
  const InvoicesScreen({super.key});
  @override ConsumerState<InvoicesScreen> createState() => _S();
}
class _S extends ConsumerState<InvoicesScreen> {
  final _c = Supabase.instance.client;
  List<Map<String,dynamic>> _list = [];
  bool _loading = true;
  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    setState(() => _loading = true);
    try {
      // invoices columns: id,invoice_number,invoice_date,total_amount,status,bird_count,quantity_kg,price_per_kg
      final data = await _c.from('invoices')
          .select('id,invoice_number,invoice_date,total_amount,status,bird_count,quantity_kg,retailers(shop_name)')
          .eq('trader_id', tid).order('invoice_date', ascending: false).limit(200);
      if (mounted) setState(() { _list = List<Map<String,dynamic>>.from(data); _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Invoices'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
    body: _loading ? const LoadingList() : _list.isEmpty ? const EmptyState(icon: Icons.receipt_long_outlined, message: 'No invoices yet')
        : RefreshIndicator(onRefresh: _load, child: ListView.separated(
            padding: const EdgeInsets.all(16), itemCount: _list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final inv = _list[i];
              final r = inv['retailers'] as Map<String,dynamic>?;
              final date = DateTime.tryParse(inv['invoice_date'] as String? ?? '');
              final status = inv['status'] as String? ?? 'draft';
              return InkWell(
                onTap: () => context.go(R.invoiceDetailPath(inv['id'])),
                borderRadius: BorderRadius.circular(12),
                child: WhiteCard(child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(inv['invoice_number'] as String? ?? '—', style: const TextStyle(fontSize: 11, color: kTextHint)),
                    Text(r?['shop_name'] as String? ?? '—', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    if (date != null) Text(DateFormat('d MMM y').format(date), style: const TextStyle(fontSize: 11, color: kTextHint)),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(Fmt.amount((inv['total_amount'] as num?)?.toDouble() ?? 0), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kPrimary)),
                    StatusBadge(status, SC.order(status), small: true),
                  ]),
                  const SizedBox(width: 4), const Icon(Icons.chevron_right, color: kTextHint, size: 18),
                ])),
              );
            })),
  );
}
