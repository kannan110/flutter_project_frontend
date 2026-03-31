import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';

class InvoiceDetailScreen extends StatefulWidget {
  const InvoiceDetailScreen({super.key, required this.id});
  final String id;
  @override State<InvoiceDetailScreen> createState() => _S();
}
class _S extends State<InvoiceDetailScreen> {
  final _c = Supabase.instance.client;
  Map<String,dynamic>? _inv;
  bool _loading = true;
  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    // invoices: total_amount, quantity_kg, bird_count, price_per_kg, balance_amount, collected_amount
    final inv = await _c.from('invoices')
        .select('*,retailers(shop_name,owner_name,phone,address)')
        .eq('id', widget.id).maybeSingle();
    if (mounted) setState(() { _inv = inv; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingList());
    if (_inv == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Not found')));
    final inv = _inv!;
    final r = inv['retailers'] as Map<String,dynamic>?;
    final date = DateTime.tryParse(inv['invoice_date'] as String? ?? '');
    final status = inv['status'] as String? ?? 'draft';

    return Scaffold(
      appBar: AppBar(title: Text(inv['invoice_number'] as String? ?? 'Invoice'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('INVOICE', style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w700, letterSpacing: 1)),
              Text(inv['invoice_number'] as String? ?? '—', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
            const SizedBox(height: 10),
            Text(r?['shop_name'] as String? ?? '—', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
            if (r?['owner_name'] != null) Text(r!['owner_name'] as String, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            if (date != null) Text(DateFormat('d MMMM y').format(date), style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ])),
        const SizedBox(height: 12),
        WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader('INVOICE DETAILS'),
          InfoRow('Birds', '${inv['bird_count'] ?? 0}'),
          InfoRow('Weight', '${(inv['quantity_kg'] as num?)?.toStringAsFixed(2) ?? 0} kg'),
          InfoRow('Rate', '₹${(inv['price_per_kg'] as num?)?.toStringAsFixed(2) ?? 0}/kg'),
          const Divider(height: 18),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Total Amount', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            Text(Fmt.amount((inv['total_amount'] as num?)?.toDouble() ?? 0), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kPrimary)),
          ]),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Collected', style: TextStyle(fontSize: 13, color: kTextSub)),
            Text(Fmt.amount((inv['collected_amount'] as num?)?.toDouble() ?? 0), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.green)),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Balance', style: TextStyle(fontSize: 13, color: kTextSub)),
            Text(Fmt.amount((inv['balance_amount'] as num?)?.toDouble() ?? 0), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ((inv['balance_amount'] as num?)?.toDouble() ?? 0) > 0 ? Colors.orange : Colors.green)),
          ]),
          const SizedBox(height: 8),
          StatusBadge(status, SC.order(status)),
        ])),
      ]),
    );
  }
}
