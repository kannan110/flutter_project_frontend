import 'package:flutter/material.dart';
import '../../../core/widgets/extensions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});
  @override
  ConsumerState<ExpensesScreen> createState() => _State();
}

class _State extends ConsumerState<ExpensesScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _expenses = [];
  String? _shiftId;
  bool _loading = true;
  double get _total => _expenses.fold(0, (s, e) => s + ((e['amount'] as num?)?.toDouble() ?? 0));

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final agentId = ref.read(appUserProvider).valueOrNull?.agentId;
    if (agentId == null) { setState(() => _loading = false); return; }
    final shift = await _client.from('delivery_shifts').select('id').eq('delivery_agent_id', agentId).eq('status', 'open').maybeSingle();
    if (shift == null) { setState(() => _loading = false); return; }
    final sid = shift['id'] as String;
    final e = List<Map<String, dynamic>>.from(await _client.from('delivery_expenses').select('*').eq('shift_id', sid).order('created_at', ascending: false));
    if (mounted) setState(() { _shiftId = sid; _expenses = e; _loading = false; });
  }

  Future<void> _addExpense() async {
    if (_shiftId == null) { showError(context, 'No active shift'); return; }
    final traderId = ref.read(appUserProvider).valueOrNull?.traderId;
    final amtCtrl  = TextEditingController();
    final notesCtrl = TextEditingController();
    String type = 'fuel';
    final result = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true, useRootNavigator: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: StatefulBuilder(builder: (ctx2, ss) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Add Expense', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: type,
            decoration: const InputDecoration(labelText: 'Expense Type', filled: true, fillColor: Color(0xFFF3F4F6),
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide.none)),
            items: const [
              DropdownMenuItem(value: 'fuel',    child: Text('Fuel')),
              DropdownMenuItem(value: 'toll',    child: Text('Toll')),
              DropdownMenuItem(value: 'food',    child: Text('Food')),
              DropdownMenuItem(value: 'vehicle', child: Text('Vehicle Repair')),
              DropdownMenuItem(value: 'other',   child: Text('Other')),
            ],
            onChanged: (v) => ss(() => type = v!),
          ),
          const SizedBox(height: 12),
          TextField(controller: amtCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount (₹)', filled: true, fillColor: Color(0xFFF3F4F6),
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide.none))),
          const SizedBox(height: 12),
          TextField(controller: notesCtrl,
              decoration: const InputDecoration(labelText: 'Notes (optional)', filled: true, fillColor: Color(0xFFF3F4F6),
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide.none))),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () async {
              final amt = double.tryParse(amtCtrl.text);
              if (amt == null || amt <= 0) return;
              await _client.from('delivery_expenses').insert({
                'shift_id': _shiftId, 'trader_id': traderId,
                'expense_type': type, 'amount': amt,
                'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
              });
              if (ctx.mounted) Navigator.of(ctx, rootNavigator: true).pop(true);
            },
            child: const Text('Add Expense'),
          ),
        ])),
      ),
    );
    if (result == true) { _load(); showSuccess(context, 'Expense added'); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Expenses'), actions: [
      IconButton(icon: const Icon(Icons.add), onPressed: _addExpense),
    ]),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _shiftId == null
            ? const EmptyState(icon: Icons.receipt_outlined, message: 'No active shift', sub: 'Open a shift to track expenses')
            : Column(children: [
                Container(
                  padding: const EdgeInsets.all(16), color: Colors.white,
                  child: Row(children: [
                    const Icon(Icons.receipt_outlined, color: AppTheme.primary),
                    const SizedBox(width: 12),
                    const Text('Today\'s Total', style: TextStyle(fontSize: 14)),
                    const Spacer(),
                    Text('₹${_total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.red)),
                  ]),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _expenses.isEmpty
                      ? const EmptyState(icon: Icons.receipt_long_outlined, message: 'No expenses yet')
                      : ListView.separated(
                          itemCount: _expenses.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final e = _expenses[i];
                            final icons = {'fuel': Icons.local_gas_station_outlined, 'toll': Icons.toll_outlined, 'food': Icons.fastfood_outlined, 'vehicle': Icons.build_outlined};
                            return ListTile(
                              leading: Container(width: 38, height: 38,
                                decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), shape: BoxShape.circle),
                                child: Icon(icons[e['expense_type']] ?? Icons.receipt_outlined, size: 18, color: Colors.red)),
                              title: Text((e['expense_type'] as String).capitalize(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                              subtitle: e['notes'] != null ? Text(e['notes'] as String, style: const TextStyle(fontSize: 11)) : null,
                              trailing: Text('₹${(e['amount'] as num).toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.red)),
                            );
                          },
                        ),
                ),
              ]),
    floatingActionButton: _shiftId != null ? FloatingActionButton.extended(
      onPressed: _addExpense,
      backgroundColor: AppTheme.primary,
      icon: const Icon(Icons.add, color: Colors.white),
      label: const Text('Add Expense', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
    ) : null,
  );
}


