import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import 'collect_cash_sheet.dart';

/// Customer Ledger — READ ONLY for supervisors. Same ledger_entries
/// query shape as trader_admin/ledger/retailer_ledger_screen.dart, minus
/// every write action (no record/edit/delete) except Collect Cash, which
/// is an explicitly allowed permission and goes through the identical
/// record_payment RPC via collect_cash_sheet.dart.
class SupervisorCustomerLedgerScreen extends ConsumerStatefulWidget {
  const SupervisorCustomerLedgerScreen({super.key, required this.retailerId});
  final String retailerId;
  @override ConsumerState<SupervisorCustomerLedgerScreen> createState() => _S();
}

class _S extends ConsumerState<SupervisorCustomerLedgerScreen> {
  final _c = Supabase.instance.client;
  Map<String, dynamic>? _retailer;
  List<Map<String, dynamic>> _entries = [];
  double _outstanding = 0;
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final r = await _c.from('retailers')
          .select('id,shop_name,owner_name,phone,outstanding_balance')
          .eq('id', widget.retailerId).maybeSingle();

      final e = await _c.from('ledger_entries')
          .select('id,entry_type,amount,payment_mode,description,entry_date,created_at')
          .eq('retailer_id', widget.retailerId)
          .order('entry_date', ascending: false).order('created_at', ascending: false)
          .limit(200);

      if (mounted) setState(() {
        _retailer = r;
        _entries = List<Map<String, dynamic>>.from(e as List? ?? []);
        _outstanding = (r?['outstanding_balance'] as num?)?.toDouble() ?? 0;
        _loading = false;
      });
    } catch (ex) {
      if (mounted) { setState(() => _loading = false); showError(context, ex.toString()); }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(backgroundColor: kSurface,
          title: Text(_retailer?['shop_name'] as String? ?? 'Customer Ledger')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [kNavy, kNavyMid],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(kRadiusCard),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('OUTSTANDING BALANCE',
                  style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
              const SizedBox(height: 4),
              Text(Fmt.amount(_outstanding),
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white)),
            ]),
          ),
          const SizedBox(height: 16),
          const Text('READ ONLY — Customer Ledger', style: TextStyle(fontSize: 11, color: kTextHint, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
          const SizedBox(height: 8),
          if (_entries.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 30),
                child: Center(child: Text('No entries yet.', style: TextStyle(color: kTextHint)))),
          ..._entries.map((e) {
            final isCredit = e['entry_type'] == 'credit';
            final amt = (e['amount'] as num?)?.toDouble() ?? 0;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(color: kBorderLight)),
              child: Row(children: [
                Icon(isCredit ? Icons.arrow_downward : Icons.arrow_upward,
                    size: 18, color: isCredit ? Colors.green : Colors.red),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e['description'] as String? ?? (isCredit ? 'Payment' : 'Charge'),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  Text(DateFormat('d MMM yyyy').format(DateTime.parse(e['entry_date'] as String)),
                      style: const TextStyle(fontSize: 11, color: kTextHint)),
                  if (e['payment_mode'] != null)
                    Text((e['payment_mode'] as String).toUpperCase(), style: const TextStyle(fontSize: 10, color: kTextHint)),
                ])),
                Text('${isCredit ? '−' : '+'}${Fmt.amount(amt)}',
                    style: TextStyle(fontWeight: FontWeight.w800,
                        color: isCredit ? Colors.green.shade700 : Colors.red.shade700)),
              ]),
            );
          }),
        ]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await showCollectCashSheet(context, ref, retailerId: widget.retailerId);
          _load();
        },
        icon: const Icon(Icons.payments_outlined),
        label: const Text('Collect Cash'),
        backgroundColor: kPrimary,
      ),
    );
  }
}