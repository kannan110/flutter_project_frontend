import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';

class RetailerLedgerScreen extends ConsumerStatefulWidget {
  const RetailerLedgerScreen({super.key, required this.retailerId});
  final String retailerId;
  @override
  ConsumerState<RetailerLedgerScreen> createState() => _RetailerLedgerScreenState();
}

class _RetailerLedgerScreenState extends ConsumerState<RetailerLedgerScreen> {
  final _client = Supabase.instance.client;
  Map<String, dynamic>? _retailer;
  List<Map<String, dynamic>> _entries = [];
  double _outstanding = 0;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await _client.from('retailers').select('*').eq('id', widget.retailerId).maybeSingle();
    final e = List<Map<String, dynamic>>.from(
      await _client.from('ledger_entries').select('*').eq('retailer_id', widget.retailerId)
          .order('entry_date', ascending: false).order('created_at', ascending: false));
    final out = await _client.rpc('get_retailer_outstanding', params: {'p_retailer_id': widget.retailerId});
    if (mounted) setState(() { _retailer = r; _entries = e; _outstanding = (out as num?)?.toDouble() ?? 0; _loading = false; });
  }

  Future<void> _recordPayment() async {
    final traderId = ref.read(appUserProvider).valueOrNull?.traderId;
    if (traderId == null) return;
    final amtCtrl  = TextEditingController();
    String mode    = 'cash';
    final result = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true, useRootNavigator: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: StatefulBuilder(builder: (ctx2, ss) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Record Payment', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          TextField(controller: amtCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount (₹)', filled: true, fillColor: Color(0xFFF3F4F6),
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide.none))),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'cash', label: Text('Cash')),
              ButtonSegment(value: 'upi',  label: Text('UPI')),
              ButtonSegment(value: 'bank', label: Text('Bank')),
            ],
            selected: {mode},
            onSelectionChanged: (s) => ss(() => mode = s.first),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () async {
              final amt = double.tryParse(amtCtrl.text);
              if (amt == null || amt <= 0) return;
              await _client.from('ledger_entries').insert({
                'trader_id': traderId, 'retailer_id': widget.retailerId,
                'entry_type': 'credit', 'amount': amt, 'payment_mode': mode,
                'source_type': 'payment', 'entry_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
                'description': 'Payment received via $mode',
              });
              if (ctx.mounted) Navigator.of(ctx, rootNavigator: true).pop(true);
            },
            child: const Text('Record Payment'),
          ),
        ])),
      ),
    );
    if (result == true) { _load(); showSuccess(context, 'Payment recorded'); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: Text(_retailer?['shop_name'] ?? 'Ledger')),
      body: Column(children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Outstanding Balance', style: TextStyle(fontSize: 12, color: Color(0xFF9E9E9E))),
              const SizedBox(height: 4),
              Text(AmountText.format(_outstanding),
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700,
                      color: _outstanding > 0 ? Colors.orange.shade700 : Colors.green)),
            ])),
            ElevatedButton.icon(
              onPressed: _recordPayment,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Record Payment'),
              style: ElevatedButton.styleFrom(minimumSize: const Size(0, 40)),
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: _entries.isEmpty
              ? const EmptyState(icon: Icons.receipt_long_outlined, message: 'No transactions yet')
              : ListView.separated(
                  itemCount: _entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final e = _entries[i];
                    final isDebit  = e['entry_type'] == 'debit';
                    final amount   = (e['amount'] as num).toDouble();
                    final date     = DateTime.tryParse(e['entry_date'] as String? ?? '') ?? DateTime.now();
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      leading: Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(
                          color: (isDebit ? Colors.red : Colors.green).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(isDebit ? Icons.arrow_upward : Icons.arrow_downward,
                            size: 18, color: isDebit ? Colors.red : Colors.green),
                      ),
                      title: Text(e['description'] as String? ?? (isDebit ? 'Purchase' : 'Payment'),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      subtitle: Text(DateFormat('d MMM y').format(date),
                          style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E))),
                      trailing: Text(
                        '${isDebit ? '+' : '-'}${AmountText.format(amount)}',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                            color: isDebit ? Colors.red : Colors.green),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
