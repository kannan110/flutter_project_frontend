import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';

class CashReconciliationScreen extends ConsumerStatefulWidget {
  const CashReconciliationScreen({super.key});
  @override ConsumerState<CashReconciliationScreen> createState() => _S();
}
class _S extends ConsumerState<CashReconciliationScreen> {
  final _c = Supabase.instance.client;
  List<Map<String,dynamic>> _pendingShifts = [];
  List<Map<String,dynamic>> _history = [];
  bool _loading = true;
  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null || !mounted) return;
    if (mounted) setState(() => _loading = true);
    try {
      final closed = await _c.from('delivery_shifts')
          .select('id,total_cash_collected,shift_start_at,delivery_agents(id,name)')
          .eq('trader_id', tid).eq('status', 'closed')
          .order('shift_start_at', ascending: false);
      final reconShiftIds = Set<String>.from(
          (await _c.from('cash_reconciliation').select('shift_id').eq('trader_id', tid))
              .map((r) => r['shift_id'] as String? ?? '').where((s) => s.isNotEmpty));
      final hist = await _c.from('cash_reconciliation')
          .select('id,recon_date,expected_cash_total,cash_handed_in,discrepancy_amount,status,reconciled_at,delivery_agents(name)')
          .eq('trader_id', tid).order('reconciled_at', ascending: false).limit(30);
      if (!mounted) return;
      if (mounted) setState(() {
        _pendingShifts = List<Map<String,dynamic>>.from(closed).where((s) => !reconShiftIds.contains(s['id'])).toList();
        _history = List<Map<String,dynamic>>.from(hist);
        _loading = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _reconcile(Map<String,dynamic> shift) async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    final uid = ref.read(appUserProvider).valueOrNull?.userId;
    final a = shift['delivery_agents'] as Map<String,dynamic>?;
    final expected = (shift['total_cash_collected'] as num?)?.toDouble() ?? 0;
    final cashCtrl  = TextEditingController(text: expected.toStringAsFixed(2));
    final notesCtrl = TextEditingController();

    await showModalBottomSheet(context: context, isScrollControlled: true, useRootNavigator: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Reconcile — ${a?['name'] ?? '—'}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Expected from app: ${Fmt.amount(expected)}', style: const TextStyle(fontSize: 12, color: kTextSub)),
              const SizedBox(height: 12),
              TextField(controller: cashCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), autofocus: true,
                  decoration: const InputDecoration(labelText: 'Cash actually handed in (₹) *', prefixText: '₹')),
              const SizedBox(height: 10),
              TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes (optional)')),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () async {
                final amt = double.tryParse(cashCtrl.text);
                if (amt == null) return;
                Navigator.of(ctx, rootNavigator: true).pop();
                try {
                  await _c.rpc('perform_cash_reconciliation', params: {
                    'p_trader_id': tid, 'p_shift_id': shift['id'],
                    'p_cash_handed_in': amt, 'p_reconciled_by': uid,
                    'p_notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                  });
                  _load();
                  if (mounted) showSuccess(context, 'Reconciled ✓');
                } catch (e) { if (mounted) showError(context, e.toString()); }
              }, child: const Text('Submit Reconciliation')),
            ])));
    cashCtrl.dispose(); notesCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kBgPage,
    appBar: AppBar(
        backgroundColor: kSurface,
        title: const Text('Cash Reconciliation'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
    body: _loading ? const LoadingList() : ListView(padding: const EdgeInsets.all(16), children: [
      if (_pendingShifts.isEmpty) Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.shade200)),
          child: const Row(children: [Icon(Icons.check_circle, color: Colors.green, size: 22), SizedBox(width: 10), Text('All shifts reconciled ✓', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w700))]))
      else ...[
        const SectionHeader('PENDING RECONCILIATION'),
        ..._pendingShifts.map((s) {
          final a = s['delivery_agents'] as Map<String,dynamic>?;
          final exp = (s['total_cash_collected'] as num?)?.toDouble() ?? 0;
          final date = DateTime.tryParse(s['shift_start_at'] as String? ?? '');
          return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.shade200, width: 1.5)),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a?['name'] as String? ?? '—', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  Text('Expected: ${Fmt.amount(exp)}', style: const TextStyle(fontSize: 12, color: kTextSub)),
                  if (date != null) Text(DateFormat('d MMM y').format(date), style: const TextStyle(fontSize: 11, color: kTextHint)),
                ])),
                ElevatedButton(onPressed: () => _reconcile(s),
                    style: ElevatedButton.styleFrom(minimumSize: const Size(80, 36)),
                    child: const Text('Reconcile', style: TextStyle(fontSize: 12))),
              ]));
        }),
      ],
      if (_history.isNotEmpty) ...[
        const SizedBox(height: 8),
        const SectionHeader('HISTORY'),
        ..._history.map((h) {
          final a = h['delivery_agents'] as Map<String,dynamic>?;
          final exp = (h['expected_cash_total'] as num?)?.toDouble() ?? 0;
          final actual = (h['cash_handed_in'] as num?)?.toDouble() ?? 0;
          final disc = (h['discrepancy_amount'] as num?)?.toDouble() ?? 0;
          final date = DateTime.tryParse(h['reconciled_at'] as String? ?? '');
          return Container(margin: const EdgeInsets.only(bottom: 8), child: WhiteCard(padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a?['name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  if (date != null) Text(DateFormat('d MMM y').format(date), style: const TextStyle(fontSize: 11, color: kTextHint)),
                  Text('Expected: ${Fmt.amount(exp)}', style: const TextStyle(fontSize: 11, color: kTextSub)),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(Fmt.amount(actual), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  Text(
                      disc.abs() < 0.01 ? 'Exact ✓'
                          : disc > 0 ? '+${Fmt.amount(disc.abs())} excess'
                          : '${Fmt.amount(disc.abs())} short',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                          color: disc.abs() < 0.01 ? Colors.green : disc > 0 ? Colors.blue : Colors.red)),
                ]),
              ])));
        }),
      ],
    ]),
  );
}