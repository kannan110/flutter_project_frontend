import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/providers/session_provider.dart';
import '../../core/theme/app_theme.dart';

class SupervisorPaymentHistoryScreen extends ConsumerStatefulWidget {
  const SupervisorPaymentHistoryScreen({super.key});
  @override ConsumerState<SupervisorPaymentHistoryScreen> createState() => _S();
}

class _S extends ConsumerState<SupervisorPaymentHistoryScreen> {
  final _c = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _payments = [];
  DateTime? _from, _to;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final uid = ref.read(appUserProvider).valueOrNull?.userId;
    if (uid == null) { if (mounted) setState(() => _loading = false); return; }
    if (mounted) setState(() => _loading = true);
    try {
      var q = _c.from('ledger_entries')
          .select('id,amount,payment_mode,description,entry_date,created_at,retailer_id,retailers(shop_name)')
          .eq('recorded_by', uid).eq('entry_type', 'credit').eq('source_type', 'payment');
      if (_from != null) q = q.gte('entry_date', DateFormat('yyyy-MM-dd').format(_from!));
      if (_to   != null) q = q.lte('entry_date', DateFormat('yyyy-MM-dd').format(_to!));

      final r = await q.order('entry_date', ascending: false).order('created_at', ascending: false).limit(300);
      if (mounted) setState(() { _payments = List<Map<String, dynamic>>.from(r as List? ?? []); _loading = false; });
    } catch (e) {
      if (mounted) { setState(() => _loading = false); showError(context, e.toString()); }
    }
  }

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(context: context,
        firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now(),
        initialDateRange: _from != null && _to != null ? DateTimeRange(start: _from!, end: _to!) : null);
    if (range != null) { setState(() { _from = range.start; _to = range.end; }); _load(); }
  }

  @override
  Widget build(BuildContext context) {
    final total = _payments.fold<double>(0, (s, p) => s + ((p['amount'] as num?)?.toDouble() ?? 0));

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(backgroundColor: kSurface, title: const Text('Payment History'), actions: [
        IconButton(icon: const Icon(Icons.date_range_outlined), onPressed: _pickRange),
        if (_from != null) IconButton(icon: const Icon(Icons.close),
            onPressed: () { setState(() { _from = null; _to = null; }); _load(); }),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_from != null)
            Padding(padding: const EdgeInsets.only(bottom: 10),
                child: Text('${DateFormat('d MMM').format(_from!)} — ${DateFormat('d MMM yyyy').format(_to!)}',
                    style: const TextStyle(fontSize: 12, color: kTextSub, fontWeight: FontWeight.w600))),
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(color: kNavy.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(kRadiusCard)),
            child: Row(children: [
              const Text('Total', style: TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(Fmt.amount(total), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: kNavy)),
            ]),
          ),
          if (_payments.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 30),
                child: Center(child: Text('No payments recorded yet.', style: TextStyle(color: kTextHint)))),
          ..._payments.map((p) {
            final shop = (p['retailers'] as Map?)?['shop_name'] as String? ?? 'Customer';
            final amt = (p['amount'] as num?)?.toDouble() ?? 0;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(color: kBorderLight)),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(shop, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  Text(DateFormat('d MMM yyyy').format(DateTime.parse(p['entry_date'] as String)),
                      style: const TextStyle(fontSize: 11, color: kTextHint)),
                  Text((p['payment_mode'] as String? ?? '').toUpperCase(),
                      style: const TextStyle(fontSize: 10, color: kTextHint)),
                ])),
                Text(Fmt.amount(amt), style: TextStyle(fontWeight: FontWeight.w800, color: Colors.green.shade700)),
              ]),
            );
          }),
        ]),
      ),
    );
  }
}