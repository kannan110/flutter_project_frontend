import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_theme.dart';
import 'entry_mode_selector.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TRADER ADD EXPENSE SHEET
//
// Bottom sheet for adding an expense on behalf of an agent.
// Direct INSERT to delivery_expenses with:
//   • entered_by_actor_type = 'trader'
//   • entered_by_actor_id   = trader's userId
//
// This matches the pattern already used by _AddExpenseTile in shift_ops_panel.dart
// but with a full type selection grid and multiple expense support.
// Requires an open shift — shift_id is passed in.
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showTraderAddExpenseSheet(
    BuildContext context, {
      required String agentId,
      required String agentName,
      required String shiftId,
      required String traderId,
      required VoidCallback onDone,
    }) async {
  await showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddExpenseSheet(
      agentId:   agentId,
      agentName: agentName,
      shiftId:   shiftId,
      traderId:  traderId,
      onDone:    onDone,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class _AddExpenseSheet extends ConsumerStatefulWidget {
  const _AddExpenseSheet({
    required this.agentId,
    required this.agentName,
    required this.shiftId,
    required this.traderId,
    required this.onDone,
  });

  final String agentId;
  final String agentName;
  final String shiftId;
  final String traderId;
  final VoidCallback onDone;

  @override
  ConsumerState<_AddExpenseSheet> createState() =>
      _AddExpenseSheetState();
}

class _AddExpenseSheetState extends ConsumerState<_AddExpenseSheet> {
  final _c        = Supabase.instance.client;
  final _amtCtrl  = TextEditingController();
  final _noteCtrl = TextEditingController();

  String _expType   = 'fuel';
  String _entryMode = 'called';
  bool   _submitting = false;

  // Accumulated expenses in this session before closing sheet
  final List<Map<String, dynamic>> _added = [];

  static const Map<String, _ExpTypeData> _types = {
    'fuel':      _ExpTypeData('⛽ Fuel',      Icons.local_gas_station_outlined, Color(0xFFD97706)),
    'toll':      _ExpTypeData('🚧 Toll',      Icons.toll_outlined,              Colors.indigo),
    'allowance': _ExpTypeData('💰 Allowance', Icons.card_giftcard_outlined,     Colors.green),
    'vehicle':   _ExpTypeData('🔧 Vehicle',   Icons.car_repair_outlined,        Colors.red),
    'loading':   _ExpTypeData('📦 Loading',   Icons.forklift,                   Colors.blue),
    'food':      _ExpTypeData('🍽 Food',       Icons.fastfood_outlined,          Colors.orange),
    'other':     _ExpTypeData('📋 Misc',       Icons.more_horiz_rounded,         Colors.grey),
  };

  @override
  void dispose() {
    _amtCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amt = double.tryParse(_amtCtrl.text.trim()) ?? 0;
    if (amt <= 0) { showError(context, 'Enter a valid amount'); return; }

    final user = ref.read(appUserProvider).valueOrNull;
    if (user == null) return;

    setState(() => _submitting = true);
    try {
      await _c.from('delivery_expenses').insert({
        'shift_id':             widget.shiftId,
        'trader_id':            widget.traderId,
        'agent_id':             widget.agentId,
        'expense_type':         _expType,
        'amount':               amt,
        'notes':                _noteCtrl.text.trim().isEmpty
            ? null : _noteCtrl.text.trim(),
        'entered_by_actor_type': 'trader',
        'entered_by_actor_id':   user.userId,
      });

      if (mounted) {
        final typeData = _types[_expType]!;
        setState(() {
          _added.add({
            'type':   _expType,
            'label':  typeData.label,
            'amount': amt,
            'notes':  _noteCtrl.text.trim(),
          });
          _amtCtrl.clear();
          _noteCtrl.clear();
        });
        showSuccess(context, '✓ ${typeData.label} added for ${widget.agentName}');
        widget.onDone();
      }
    } catch (e) {
      if (mounted) {
        showError(context,
            e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: kBgPage,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: kBorderLight,
                  borderRadius: BorderRadius.circular(2)),
            )),
            const SizedBox(height: 16),

            // Header
            Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFD97706).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.receipt_outlined,
                    color: Color(0xFFD97706), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Add Expense',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    Text('For ${widget.agentName}',
                        style: const TextStyle(
                            fontSize: 12, color: kTextHint)),
                  ])),
            ]),
            const SizedBox(height: 20),

            // Entry mode
            const Text('HOW DID AGENT REPORT?',
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w800,
                    color: kTextHint, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            EntryModeSelector(
              value: _entryMode,
              onChanged: (v) => setState(() => _entryMode = v),
            ),
            const SizedBox(height: 16),

            // Previously added this session
            if (_added.isNotEmpty) ...[
              const Text('ADDED THIS SESSION',
                  style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w800,
                      color: kTextHint, letterSpacing: 0.8)),
              const SizedBox(height: 8),
              ..._added.map((e) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(kRadiusInner),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(children: [
                  const Icon(Icons.check_circle_outline,
                      color: Colors.green, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    '${e['label']} — ${Fmt.amount((e['amount'] as double))}'
                        '${(e['notes'] as String).isNotEmpty ? ' · ${e['notes']}' : ''}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  )),
                ]),
              )),
              const Divider(height: 20),
            ],

            // Expense type grid
            const Text('EXPENSE TYPE',
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w800,
                    color: kTextHint, letterSpacing: 0.8)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _types.entries.map((e) {
                final sel  = _expType == e.key;
                final data = e.value;
                return GestureDetector(
                  onTap: () => setState(() => _expType = e.key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel
                          ? data.color.withValues(alpha: 0.12)
                          : kSurface,
                      borderRadius: BorderRadius.circular(kRadiusChip),
                      border: Border.all(
                        color: sel ? data.color : kBorderLight,
                        width: sel ? 1.5 : 1,
                      ),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(data.icon, size: 16,
                              color: sel ? data.color : kTextHint),
                          const SizedBox(width: 6),
                          Text(data.label,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: sel ? data.color : kTextSub)),
                        ]),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Amount + notes
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _amtCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  autofocus: true,
                  decoration: const InputDecoration(
                      labelText: 'Amount (₹) *', prefixText: '₹'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _noteCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Notes (optional)'),
                ),
              ),
            ]),
            const SizedBox(height: 20),

            // Add button
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add_rounded, size: 22),
                label: const Text('Add Expense',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800,
                        color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(kRadiusBtn)),
                ),
              ),
            ),

            if (_added.isNotEmpty) ...[
              const SizedBox(height: 10),
              TextButton(
                onPressed: () =>
                    Navigator.of(context, rootNavigator: true).pop(),
                child: Text(
                  'Done — ${_added.length} expense(s) added',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: kNavy),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ExpTypeData {
  const _ExpTypeData(this.label, this.icon, this.color);
  final String  label;
  final IconData icon;
  final Color   color;
}