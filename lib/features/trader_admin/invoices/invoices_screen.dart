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
  double _totalRevenue = 0, _totalOutstanding = 0;
  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null || !mounted) return;
    if (mounted) setState(() => _loading = true);
    try {
      final data = await _c.from('invoices')
          .select('id,invoice_number,invoice_date,total_amount,collected_amount,balance_amount,status,bird_count,quantity_kg,price_per_kg,retailers(shop_name)')
          .eq('trader_id', tid).order('invoice_date', ascending: false).limit(200);
      if (!mounted) return;
      final list = List<Map<String,dynamic>>.from(data);
      double rev = 0, out = 0;
      for (final inv in list) { rev += (inv['total_amount'] as num?)?.toDouble() ?? 0; out += (inv['balance_amount'] as num?)?.toDouble() ?? 0; }
      if (mounted) setState(() { _list = list; _totalRevenue = rev; _totalOutstanding = out; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Invoices'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
    body: _loading ? const LoadingList() : Column(children: [
      // Summary header
      Container(color: Colors.white, padding: const EdgeInsets.all(14), child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Total Revenue', style: TextStyle(fontSize: 11, color: kTextHint)),
          Text(Fmt.amount(_totalRevenue), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kPrimary)),
        ])),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const Text('Outstanding', style: TextStyle(fontSize: 11, color: kTextHint)),
          Text(Fmt.amount(_totalOutstanding), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _totalOutstanding > 0 ? Colors.orange : Colors.green)),
        ])),
      ])),
      const Divider(height: 1),
      Expanded(child: _list.isEmpty ? const EmptyState(icon: Icons.receipt_long_outlined, message: 'No invoices yet')
          : ListView.separated(padding: const EdgeInsets.all(14), itemCount: _list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final inv = _list[i];
                final r = inv['retailers'] as Map<String,dynamic>?;
                final date = DateTime.tryParse(inv['invoice_date'] as String? ?? '');
                final status = inv['status'] as String? ?? 'draft';
                final total   = (inv['total_amount']     as num?)?.toDouble() ?? 0;
                final balance = (inv['balance_amount']   as num?)?.toDouble() ?? 0;
                return InkWell(
                  onTap: () => context.push(R.invoiceDetailPath(inv['id'])),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: balance > 0 ? Colors.orange.shade200 : kBorder)),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(inv['invoice_number'] as String? ?? '—', style: const TextStyle(fontSize: 10, color: kTextHint)),
                        Text(r?['shop_name'] as String? ?? '—', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        if (date != null) Text(DateFormat('d MMM y').format(date), style: const TextStyle(fontSize: 11, color: kTextHint)),
                        Text('${inv['bird_count'] ?? 0} birds · ${(inv['quantity_kg'] as num?)?.toStringAsFixed(1) ?? 0} kg', style: const TextStyle(fontSize: 11, color: kTextSub)),
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(Fmt.amount(total), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kPrimary)),
                        if (balance > 0) Text('Due: ${Fmt.amount(balance)}', style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w600)),
                        StatusBadge(status, SC.order(status), small: true),
                      ]),
                      const SizedBox(width: 4), const Icon(Icons.chevron_right, color: kTextHint, size: 18),
                    ])),
                );
              })),
    ]),
  );
}
