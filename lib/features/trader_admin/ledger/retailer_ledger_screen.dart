import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class RetailerLedgerScreen extends ConsumerStatefulWidget {
  const RetailerLedgerScreen({super.key, required this.retailerId});

  final String retailerId;

  @override ConsumerState<RetailerLedgerScreen> createState() => _S();
}

class _S extends ConsumerState<RetailerLedgerScreen> {
  final _c = Supabase.instance.client;
  Map<String, dynamic>? _retailer;
  List<Map<String, dynamic>> _entries = [];
  double _outstanding = 0;
  bool _loading = true;

  @override void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await _c.from('retailers').select(
          'id,shop_name,owner_name,credit_limit')
          .eq('id', widget.retailerId)
          .maybeSingle();
      // ledger_entries columns: id, entry_type, amount, payment_mode, description, entry_date, created_at
      final e = await _c.from('ledger_entries').select(
          'id,entry_type,amount,payment_mode,description,entry_date,created_at')
          .eq('retailer_id', widget.retailerId).order(
          'entry_date', ascending: false)
          .order('created_at', ascending: false)
          .limit(100);
      double out = 0;
      try {
        final res = await _c.rpc('get_retailer_outstanding',
            params: {'p_retailer_id': widget.retailerId});
        out = (res as num?)?.toDouble() ?? 0;
      } catch (_) {}
      if (mounted) setState(() {
        _retailer = r;
        _entries = List<Map<String, dynamic>>.from(e);
        _outstanding = out;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _recordPayment() async {
    final amtCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String mode = 'cash';
    final tid = ref
        .read(appUserProvider)
        .valueOrNull
        ?.traderId;
    final uid = ref
        .read(appUserProvider)
        .valueOrNull
        ?.userId;

    await showModalBottomSheet(context: context,
        isScrollControlled: true,
        useRootNavigator: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) =>
            Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery
                    .of(ctx)
                    .viewInsets
                    .bottom + 20),
                child: StatefulBuilder(builder: (_, ss) =>
                    Column(mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Record Payment — ${_retailer?['shop_name'] ??
                              ''}', style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                          Text('Outstanding: ${Fmt.amount(_outstanding)}',
                              style: TextStyle(fontSize: 12,
                                  color: _outstanding > 0
                                      ? Colors.orange
                                      : Colors.green,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 14),
                          TextField(controller: amtCtrl,
                              keyboardType: const TextInputType
                                  .numberWithOptions(decimal: true),
                              autofocus: true,
                              decoration: const InputDecoration(
                                  labelText: 'Amount (₹) *', prefixText: '₹')),
                          const SizedBox(height: 10),
                          SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(
                                    value: 'cash', label: Text('Cash')),
                                ButtonSegment(value: 'upi', label: Text('UPI')),
                                ButtonSegment(
                                    value: 'bank', label: Text('Bank'))
                              ],
                              selected: {mode},
                              onSelectionChanged: (s) =>
                                  ss(() => mode = s.first)),
                          const SizedBox(height: 10),
                          TextField(controller: descCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Notes (optional)')),
                          const SizedBox(height: 16),
                          ElevatedButton(onPressed: () async {
                            final amt = double.tryParse(amtCtrl.text.trim());
                            if (amt == null || amt <= 0) return;
                            Navigator.of(ctx, rootNavigator: true).pop();
                            try {
                              // record_payment(p_trader_id, p_retailer_id, p_amount, p_payment_mode, p_invoice_id, p_order_id, p_description, p_recorded_by)
                              await _c.rpc('record_payment', params: {
                                'p_trader_id': tid,
                                'p_retailer_id': widget.retailerId,
                                'p_amount': amt,
                                'p_payment_mode': mode,
                                'p_description': descCtrl.text
                                    .trim()
                                    .isEmpty ? 'Payment via $mode' : descCtrl
                                    .text.trim(),
                                'p_recorded_by': uid,
                              });
                              _load();
                              if (mounted) showSuccess(
                                  context, 'Payment recorded ✓');
                            } catch (e) {
                              if (mounted) showError(context, e.toString());
                            }
                          }, child: const Text('Record Payment')),
                        ]))));

        amtCtrl.dispose();
    descCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingList());
    return Scaffold(
      appBar: AppBar(
          title: Text(_retailer?['shop_name'] as String? ?? 'Ledger'),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load)
          ]),
      body: Column(children: [
        Container(color: Colors.white, padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Outstanding',
                    style: TextStyle(fontSize: 11, color: kTextHint)),
                Text(Fmt.amount(_outstanding), style: TextStyle(fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: _outstanding > 0 ? Colors.orange.shade700 : Colors
                        .green)),
              ])),
              ElevatedButton.icon(onPressed: _recordPayment,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Payment'),
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 40))),
            ])),
        const Divider(height: 1),
        Expanded(child: _entries.isEmpty ? const EmptyState(
            icon: Icons.receipt_long_outlined, message: 'No transactions')
            : ListView.separated(itemCount: _entries.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final e = _entries[i];
              final isDebit = e['entry_type'] == 'debit';
              final amt = (e['amount'] as num).toDouble();
              final date = DateTime.tryParse(
                  e['entry_date'] as String? ?? '') ?? DateTime.now();
              return ListTile(
                leading: Container(width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                        color: (isDebit ? Colors.red : Colors.green)
                            .withOpacity(0.1), shape: BoxShape.circle),
                    child: Icon(
                        isDebit ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 16, color: isDebit ? Colors.red : Colors.green)),
                title: Text(e['description'] as String? ??
                    (isDebit ? 'Purchase' : 'Payment'),
                    style: const TextStyle(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                subtitle: Text(DateFormat('d MMM y').format(date),
                    style: const TextStyle(fontSize: 11, color: kTextHint)),
                trailing: Text('${isDebit ? '+' : '−'}${Fmt.amount(amt)}',
                    style: TextStyle(fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: isDebit ? Colors.red : Colors.green)),
              );
            })),
      ]),
    );
  }
}
