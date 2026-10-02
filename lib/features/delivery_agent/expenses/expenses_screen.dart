import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});
  @override ConsumerState<ExpensesScreen> createState() => _S();
}
class _S extends ConsumerState<ExpensesScreen> {
  final _c = Supabase.instance.client;
  List<Map<String,dynamic>> _expenses = [];
  Map<String,dynamic>? _activeShift;
  bool _loading = true;
  double _total = 0;
  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final agentId = ref.read(appUserProvider).valueOrNull?.agentId;
    if (agentId == null || !mounted) return;
    if (mounted) setState(() => _loading = true);
    try {
      final shift = await _c.from('delivery_shifts').select('id,total_expenses').eq('delivery_agent_id', agentId).eq('status','open').maybeSingle();
      List<Map<String,dynamic>> exps = [];
      if (shift != null) {
        // delivery_expenses: shift_id, trader_id, expense_type, amount, notes, created_at
        // NO agent_id, NO expense_date columns
        exps = List<Map<String,dynamic>>.from(await _c.from('delivery_expenses')
            .select('id,expense_type,amount,notes,created_at').eq('shift_id', shift['id']).order('created_at', ascending: false));
      }
      final total = exps.fold(0.0, (s, e) => s + ((e['amount'] as num?)?.toDouble() ?? 0));
      if (!mounted) return;
      if (mounted) setState(() { _activeShift = shift; _expenses = exps; _total = total; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _add() async {
    if (_activeShift == null) { showError(context, 'Open a shift first'); return; }
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    final amtCtrl = TextEditingController(); final notesCtrl = TextEditingController();
    String type = 'fuel';

    await showModalBottomSheet(context: context, isScrollControlled: true, useRootNavigator: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: StatefulBuilder(builder: (_, ss) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Add Expense', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value:'fuel',  icon: Icon(Icons.local_gas_station,size:14), label: Text('Fuel')),
                    ButtonSegment(value:'toll',  icon: Icon(Icons.toll,size:14), label: Text('Toll')),
                    ButtonSegment(value:'food',  icon: Icon(Icons.fastfood,size:14), label: Text('Food')),
                    ButtonSegment(value:'other', icon: Icon(Icons.more_horiz,size:14), label: Text('Other')),
                  ],
                  selected: {type}, onSelectionChanged: (s) => ss(() => type = s.first)),
              const SizedBox(height: 10),
              TextField(
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => FocusScope.of(context).nextFocus(),controller: amtCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), autofocus: true,
                  decoration: const InputDecoration(labelText: 'Amount (₹) *', prefixText: '₹')),
              const SizedBox(height: 8),
              TextField(
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => FocusScope.of(context).unfocus(),controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes (optional)')),
              const SizedBox(height: 14),
              ElevatedButton(onPressed: () async {
                final amt = double.tryParse(amtCtrl.text.trim());
                if (amt == null || amt <= 0) return;
                Navigator.of(ctx, rootNavigator: true).pop();
                try {
                  // delivery_expenses columns: shift_id, trader_id, expense_type, amount, notes
                  await _c.from('delivery_expenses').insert({
                    'shift_id': _activeShift!['id'], 'trader_id': tid,
                    'expense_type': type, 'amount': amt,
                    'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                  });
                  _load();
                  if (mounted) showSuccess(context, 'Expense recorded ✓');
                } catch (e) { if (mounted) showError(context, e.toString()); }
              }, child: const Text('Add Expense')),
            ]))));
    // controllers are ephemeral locals — GC handles disposal
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kBgPage,
    appBar: AppBar(
        backgroundColor: kNavy, foregroundColor: Colors.white,
        title: const Text('Expenses', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)]),
    // Reserve space so FAB clears the AgentShell glass bottom nav
    bottomNavigationBar: const SizedBox(height: 80),
    floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: const Color(0xFFD97706),
        icon: const Icon(Icons.add), label: const Text('Add Expense', style: TextStyle(fontWeight: FontWeight.w800))),
    body: _loading ? const LoadingList() : Column(children: [
      Container(
          decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [kNavy, kNavyMid], begin: Alignment.topLeft, end: Alignment.bottomRight)),
          padding: const EdgeInsets.all(20), child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('TODAY\'S EXPENSES', style: TextStyle(fontSize: 10, color: Color(0xFFB4C6F4), fontWeight: FontWeight.w800, letterSpacing: 0.6)),
          const SizedBox(height: 4),
          Text(Fmt.amount(_total), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFFFCD34D))),
        ])),
        if (_activeShift == null) const Text('Open a shift first', style: TextStyle(fontSize: 11, color: kTextHint)),
      ])),
      const Divider(height: 1),
      Expanded(child: _expenses.isEmpty ? const EmptyState(icon: Icons.receipt_outlined, message: 'No expenses')
          : ListView.separated(padding: const EdgeInsets.fromLTRB(14, 14, 14, 100), itemCount: _expenses.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final e = _expenses[i];
            final type = e['expense_type'] as String? ?? 'other';
            final date = DateTime.tryParse(e['created_at'] as String? ?? '');
            final amt  = (e['amount'] as num).toDouble();
            return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard), border: Border.all(color: kBorderLight), boxShadow: kCardShadow),
                child: Row(children: [
                  Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(kRadiusChip)),
                      child: Icon(_icon(type), color: const Color(0xFFD97706), size: 20)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(type.toUpperCase(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: kNavy)),
                    if (e['notes'] != null) Text(e['notes'] as String, style: const TextStyle(fontSize: 11, color: kTextSub)),
                    if (date != null) Text(DateFormat('h:mm a').format(date), style: const TextStyle(fontSize: 10, color: kTextHint)),
                  ])),
                  Text(Fmt.amount(amt), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFFD97706))),
                ]));
          })),
    ]),
  );

  IconData _icon(String t) => switch(t) {
    'fuel'    => Icons.local_gas_station_outlined,
    'toll'    => Icons.toll_outlined,
    'food'    => Icons.fastfood_outlined,
    'vehicle' => Icons.car_repair_outlined,
    _         => Icons.receipt_outlined,
  };
}