import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
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
    if (agentId == null) return;
    setState(() => _loading = true);
    try {
      // Find active shift for this agent
      final shift = await _c.from('delivery_shifts')
          .select('id,total_expenses,shift_start_at,trader_id')
          .eq('delivery_agent_id', agentId).eq('status','open')
          .maybeSingle();

      List<Map<String,dynamic>> exps = [];
      if (shift != null) {
        // delivery_expenses: shift_id, trader_id, expense_type, amount, notes
        // NO agent_id column, NO expense_date column
        exps = List<Map<String,dynamic>>.from(
          await _c.from('delivery_expenses')
            .select('id,expense_type,amount,notes,created_at')
            .eq('shift_id', shift['id'])
            .order('created_at', ascending: false));
      }
      final total = exps.fold(0.0, (s, e) => s + ((e['amount'] as num?)?.toDouble() ?? 0));
      if (mounted) setState(() { _activeShift = shift; _expenses = exps; _total = total; _loading = false; });
    } catch (e) {
      if (mounted) { showError(context, e.toString()); setState(() => _loading = false); }
    }
  }

  Future<void> _add() async {
    if (_activeShift == null) {
      showError(context, 'Open a shift first before recording expenses');
      return;
    }
    final tid    = _activeShift!['trader_id'] as String?;
    final shiftId = _activeShift!['id'] as String;
    final amtCtrl   = TextEditingController();
    final notesCtrl = TextEditingController();
    String type = 'fuel';

    await showModalBottomSheet(
      context: context, isScrollControlled: true, useRootNavigator: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: StatefulBuilder(builder: (_, ss) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Add Expense', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          // expense_type CHECK: fuel, toll, vehicle, food, other
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value:'fuel',    icon: Icon(Icons.local_gas_station, size: 14), label: Text('Fuel')),
              ButtonSegment(value:'toll',    icon: Icon(Icons.toll, size: 14),              label: Text('Toll')),
              ButtonSegment(value:'food',    icon: Icon(Icons.fastfood, size: 14),          label: Text('Food')),
              ButtonSegment(value:'vehicle', icon: Icon(Icons.build, size: 14),             label: Text('Vehicle')),
              ButtonSegment(value:'other',   icon: Icon(Icons.more_horiz, size: 14),        label: Text('Other')),
            ],
            selected: {type}, onSelectionChanged: (s) => ss(() => type = s.first)),
          const SizedBox(height: 10),
          TextField(controller: amtCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Amount (₹) *', prefixText: '₹')),
          const SizedBox(height: 8),
          TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes (optional)')),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: () async {
            final amt = double.tryParse(amtCtrl.text.trim());
            if (amt == null || amt <= 0) { showError(ctx, 'Enter a valid amount'); return; }
            Navigator.of(ctx, rootNavigator: true).pop();
            try {
              // Bug 2 fix: insert ONLY valid columns
              // delivery_expenses: shift_id, trader_id, expense_type, amount, notes
              await _c.from('delivery_expenses').insert({
                'shift_id':     shiftId,
                'trader_id':    tid,
                'expense_type': type,
                'amount':       amt,
                if (notesCtrl.text.trim().isNotEmpty) 'notes': notesCtrl.text.trim(),
              });
              _load();
              if (mounted) showSuccess(context, 'Expense recorded ✓');
            } catch (e) {
              if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
            }
          }, child: const Text('Save Expense')),
        ])),
      ),
    );
    amtCtrl.dispose(); notesCtrl.dispose();
  }

  IconData _icon(String t) => switch(t) {
    'fuel'    => Icons.local_gas_station_outlined,
    'toll'    => Icons.toll_outlined,
    'food'    => Icons.fastfood_outlined,
    'vehicle' => Icons.build_outlined,
    _         => Icons.receipt_outlined,
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Expenses'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
    floatingActionButton: FloatingActionButton.extended(
        onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add Expense')),
    body: _loading ? const LoadingList() : Column(children: [
      // Total header
      Container(
        color: Colors.white, padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("Today's Expenses", style: TextStyle(fontSize: 11, color: kTextHint)),
            Text(Fmt.amount(_total), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: kError)),
          ])),
          if (_activeShift == null) Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            const Text('No active shift', style: TextStyle(fontSize: 11, color: Colors.orange)),
          ]),
        ])),
      const Divider(height: 1),
      if (_activeShift == null) Expanded(child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.timer_off_outlined, size: 48, color: kTextHint),
        const SizedBox(height: 12),
        const Text('No active shift', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kTextSub)),
        const SizedBox(height: 6),
        const Text('Open a shift before recording expenses', style: TextStyle(fontSize: 12, color: kTextHint)),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: () => context.go(R.shiftOpen), child: const Text('Open Shift')),
      ])))
      else Expanded(child: _expenses.isEmpty
          ? const EmptyState(icon: Icons.receipt_outlined, message: 'No expenses yet', sub: 'Tap + to add fuel, toll or other expenses')
          : ListView.separated(
              padding: const EdgeInsets.all(16), itemCount: _expenses.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final e    = _expenses[i];
                final type = e['expense_type'] as String? ?? 'other';
                final date = DateTime.tryParse(e['created_at'] as String? ?? '');
                return WhiteCard(child: Row(children: [
                  Container(width: 40, height: 40,
                    decoration: BoxDecoration(color: kError.withOpacity(0.1), shape: BoxShape.circle),
                    child: Icon(_icon(type), color: kError, size: 20)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(type.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                    if (e['notes'] != null) Text(e['notes'] as String, style: const TextStyle(fontSize: 11, color: kTextSub)),
                    if (date != null) Text(DateFormat('h:mm a').format(date), style: const TextStyle(fontSize: 10, color: kTextHint)),
                  ])),
                  Text(Fmt.amount((e['amount'] as num).toDouble()), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kError)),
                ]));
              })),
    ]),
  );
}
