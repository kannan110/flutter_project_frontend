import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';

class InvoiceDetailScreen extends ConsumerStatefulWidget {
  const InvoiceDetailScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends ConsumerState<InvoiceDetailScreen> {
  Map<String, dynamic>? _inv;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final d = await Supabase.instance.client
        .from('invoices').select('*, retailers(*), orders(*)')
        .eq('id', widget.id).maybeSingle();
    if (mounted) setState(() { _inv = d; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_inv == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Not found')));

    final retailer  = _inv!['retailers'] as Map<String, dynamic>?;
    final amount    = (_inv!['total_amount']     as num?)?.toDouble() ?? 0;
    final collected = (_inv!['collected_amount'] as num?)?.toDouble() ?? 0;
    final balance   = (_inv!['balance_amount']   as num?)?.toDouble() ?? 0;
    final status    = _inv!['status'] as String? ?? 'draft';
    final date      = DateTime.tryParse(_inv!['invoice_date'] as String? ?? '') ?? DateTime.now();
    final qtyKg     = (_inv!['quantity_kg']  as num?)?.toDouble();
    final priceKg   = (_inv!['price_per_kg'] as num?)?.toDouble();

    return Scaffold(
      appBar: AppBar(title: Text(_inv!['invoice_number'] as String? ?? 'Invoice')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
              border: const Border.fromBorderSide(BorderSide(color: Color(0xFFEEEEEE)))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            StatusBadge(status, StatusColors.approval(status)),
            const SizedBox(height: 12),
            Text(retailer?['shop_name'] as String? ?? 'Unknown',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            InfoRow('Invoice #', _inv!['invoice_number'] as String? ?? 'N/A'),
            InfoRow('Date',      DateFormat('d MMM y').format(date)),
            InfoRow('Weight',    qtyKg  != null ? '${qtyKg.toStringAsFixed(2)} kg'        : 'N/A'),
            InfoRow('Rate',      priceKg != null ? 'Rs.${priceKg.toStringAsFixed(2)}/kg'  : 'N/A'),
            const Divider(height: 24),
            InfoRow('Total',     AmountText.format(amount),    valueColor: AppTheme.primary),
            InfoRow('Collected', AmountText.format(collected), valueColor: Colors.green),
            InfoRow('Balance',   AmountText.format(balance),   valueColor: balance > 0 ? Colors.orange : Colors.green),
          ]),
        ),
      ]),
    );
  }
}
