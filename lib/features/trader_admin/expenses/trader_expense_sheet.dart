import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SHARED DELETE FLOW — used by both the Recent Expenses list and the View
// All list, so there's exactly one confirmation dialog / RPC call site
// rather than duplicating it in two widgets.
//
// Soft-deletes via the delete_trader_expense RPC (requires a reason,
// writes an audit row, re-triggers Batch Costing recalculation) — nothing
// here is a raw table delete.
// ─────────────────────────────────────────────────────────────────────────────
Future<bool> confirmAndDeleteTraderExpense(
    BuildContext context, WidgetRef ref, Map<String, dynamic> expense) async {
  final reasonCtrl = TextEditingController();
  final label = (expense['label'] as String?) ??
      (expense['notes'] as String?) ??
      (expense['category'] as String? ?? 'this expense');
  final amountText = Fmt.amount((expense['amount'] as num).toDouble());

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) {
      String? error;
      return StatefulBuilder(builder: (dialogCtx, setDialogState) {
        return AlertDialog(
          title: const Text('Delete this expense?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$label — $amountText',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 4),
            const Text('This cannot be undone from here. Reports, P&L, Dashboard and '
                'Costing will update immediately.',
                style: TextStyle(fontSize: 12, color: kTextSub)),
            const SizedBox(height: 14),
            TextField(
              controller: reasonCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Reason for deletion (required)',
                hintText: 'e.g. Duplicate entry',
                errorText: error,
                isDense: true,
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (reasonCtrl.text.trim().isEmpty) {
                  setDialogState(() => error = 'Please enter a reason');
                  return;
                }
                Navigator.pop(dialogCtx, true);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700)),
            ),
          ],
        );
      });
    },
  );

  if (confirmed != true) {
    reasonCtrl.dispose();
    return false;
  }

  final reason = reasonCtrl.text.trim();
  reasonCtrl.dispose();

  try {
    final user = ref.read(appUserProvider).valueOrNull;
    await Supabase.instance.client.rpc('delete_trader_expense', params: {
      'p_expense_id': expense['id'],
      'p_deleted_by': user?.userId,
      'p_delete_reason': reason,
    });
    if (context.mounted) showSuccess(context, 'Expense deleted ✓');
    return true;
  } catch (e) {
    if (context.mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    return false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TRADER DAILY EXPENSE SHEET
//
// Records ad-hoc trader-level expenses (Labour, Loading, Office, Vehicle, Other)
// into trader_daily_expenses table.
//
// These are DISTINCT from delivery-agent shift expenses (fuel, toll, allowance)
// which live in delivery_expenses. Trader expenses are overhead costs that
// affect Net Profit but are not tied to a specific agent shift.
//
// Examples: Labour wages, loading crew payment, office rent, misc daily costs.
//
// Called from the Business Health card's "Add Expense" button.
// ─────────────────────────────────────────────────────────────────────────────

Future<bool> showTraderExpenseSheet(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context:          context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor:  Colors.transparent,
    builder:          (_) => const _TraderExpenseSheet(),
  );
  return result ?? false;
}

class _TraderExpenseSheet extends ConsumerStatefulWidget {
  const _TraderExpenseSheet();
  @override
  ConsumerState<_TraderExpenseSheet> createState() => _TraderExpenseSheetState();
}

class _TraderExpenseSheetState extends ConsumerState<_TraderExpenseSheet> {
  final _c       = Supabase.instance.client;
  final _amtCtrl = TextEditingController();
  final _lblCtrl = TextEditingController();

  String  _category   = 'labour';
  String? _paymentMode; // 'cash' | 'upi' | 'bank' | null (unspecified)
  bool    _submitting  = false;
  bool    _loadingRecent = true;
  // Business Date — defaults to today, editable, never future. Lets the
  // trader record expenses from a few days ago (e.g. catching up on 3-5
  // days of pending entries) so they land on the correct day in P&L and
  // Batch Cost Allocation instead of always being stamped with today.
  DateTime _expenseDate = DateTime.now();

  // Accumulated entries in this session (shown as chips before close)
  final List<Map<String, dynamic>> _added = [];

  // Recent expenses for this trader — lets the trader tap one to edit it
  // (fix a wrong amount/category/date/etc.) instead of only ever adding.
  List<Map<String, dynamic>> _recent = [];

  static const _categories = [
    ('labour',  '👷 Labour',      Colors.blue),
    ('loading', '📦 Loading',     Colors.teal),
    ('office',  '🏢 Office',      Colors.indigo),
    ('vehicle', '🔧 Vehicle',     Colors.red),
    ('other',   '📋 Other',       Colors.grey),
  ];

  static const _paymentModes = [
    ('cash', '💵 Cash'),
    ('upi',  '📱 UPI'),
    ('bank', '🏦 Bank'),
  ];

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    final user = ref.read(appUserProvider).valueOrNull;
    if (user == null) { setState(() => _loadingRecent = false); return; }
    try {
      final r = await _c
          .from('trader_daily_expenses')
          .select('id,expense_date,category,label,notes,amount,payment_mode')
          .eq('trader_id', user.traderId as Object)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false)
          .limit(6);
      if (mounted) {
        setState(() {
          _recent = List<Map<String, dynamic>>.from(r as List? ?? []);
          _loadingRecent = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingRecent = false);
    }
  }

  @override
  void dispose() {
    _amtCtrl.dispose();
    _lblCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amt = double.tryParse(_amtCtrl.text.trim()) ?? 0;
    if (amt <= 0) { showError(context, 'Enter a valid amount'); return; }

    final user = ref.read(appUserProvider).valueOrNull;
    if (user == null) return;

    setState(() => _submitting = true);
    try {
      await _c.from('trader_daily_expenses').insert({
        'trader_id':    user.traderId,
        'expense_date': DateFormat('yyyy-MM-dd').format(_expenseDate),
        'category':     _category,
        'label':        _lblCtrl.text.trim().isEmpty ? null : _lblCtrl.text.trim(),
        'amount':       amt,
        'payment_mode': _paymentMode,
        'created_by':   user.userId,
      });

      setState(() {
        _added.add({'category': _category, 'amount': amt, 'label': _lblCtrl.text.trim()});
        _amtCtrl.clear();
        _lblCtrl.clear();
        _submitting = false;
      });
      _loadRecent();
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        showError(context, e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    // FIX: the sheet's content (category grid + fields + Recent Expenses)
    // had no height cap or scroll wrapper, so it overflowed the screen
    // once more than a couple of recent expenses were shown (rendered as
    // Flutter's "BOTTOM OVERFLOWED" debug banner). Capping height and
    // wrapping in a SingleChildScrollView fixes that without changing any
    // of the existing content/behavior.
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        decoration: const BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handle
                Center(child: Container(width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Row(children: [
                  const Icon(Icons.add_business_outlined, size: 20, color: kNavy),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Add Trader Expense',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: kNavy))),
                  GestureDetector(
                    onTap: () => Navigator.pop(context, _added.isNotEmpty),
                    child: const Icon(Icons.close, size: 20, color: kTextSub),
                  ),
                ]),
                const SizedBox(height: 4),
                const Text('Labour, loading crew, office costs, vehicle repairs, etc.',
                    style: TextStyle(fontSize: 11, color: kTextSub)),
                const SizedBox(height: 16),

                // Category grid
                Wrap(spacing: 8, runSpacing: 8,
                    children: _categories.map((cat) {
                      final selected = _category == cat.$1;
                      return GestureDetector(
                        onTap: () => setState(() => _category = cat.$1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: selected ? cat.$3.withValues(alpha: 0.12) : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(kRadiusChip),
                            border: Border.all(color: selected ? cat.$3 : Colors.grey.shade300,
                                width: selected ? 1.5 : 1),
                          ),
                          child: Text(cat.$2,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                                  color: selected ? cat.$3 : kTextSub)),
                        ),
                      );
                    }).toList()),
                const SizedBox(height: 12),

                // Payment mode (optional)
                Wrap(spacing: 8, runSpacing: 8,
                    children: _paymentModes.map((pm) {
                      final selected = _paymentMode == pm.$1;
                      return GestureDetector(
                        onTap: () => setState(() => _paymentMode = selected ? null : pm.$1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: selected ? kNavy.withValues(alpha: 0.10) : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(kRadiusChip),
                            border: Border.all(color: selected ? kNavy : Colors.grey.shade300,
                                width: selected ? 1.5 : 1),
                          ),
                          child: Text(pm.$2,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                                  color: selected ? kNavy : kTextSub)),
                        ),
                      );
                    }).toList()),
                const SizedBox(height: 16),

                // Label (optional)
                TextField(
                  controller: _lblCtrl,
                  decoration: InputDecoration(
                    labelText: 'Description (optional)',
                    hintText: 'e.g. Labour charges, Loading crew payment',
                    filled: true, fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 10),

                // Business Date — defaults to today, editable, never future.
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _expenseDate,
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setState(() => _expenseDate = picked);
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Business Date',
                      prefixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
                      filled: true, fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    child: Text(DateFormat('d MMM yyyy').format(_expenseDate)),
                  ),
                ),

                // Amount + submit
                Row(children: [
                  Expanded(child: TextField(
                    controller: _amtCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Amount (₹)',
                      prefixText: '₹ ',
                      filled: true, fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  )),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kNavy,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _submitting
                          ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Add', style: TextStyle(fontWeight: FontWeight.w800,
                          color: Colors.white, fontSize: 14)),
                    ),
                  ),
                ]),

                // Session summary
                if (_added.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: kSuccess.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kSuccess.withValues(alpha: 0.25)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Added this session',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kSuccess)),
                      const SizedBox(height: 6),
                      ..._added.map((e) {
                        final cat = _categories.firstWhere((c) => c.$1 == e['category'],
                            orElse: () => ('other', '📋 Other', Colors.grey));
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(children: [
                            Text(cat.$2, style: const TextStyle(fontSize: 11)),
                            const SizedBox(width: 6),
                            if ((e['label'] as String).isNotEmpty)
                              Expanded(child: Text(e['label'] as String,
                                  style: const TextStyle(fontSize: 11, color: kTextSub),
                                  overflow: TextOverflow.ellipsis)),
                            const Spacer(),
                            Text(Fmt.amount(e['amount'] as double),
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                                    color: kSuccess)),
                          ]),
                        );
                      }),
                      const Divider(height: 12),
                      Row(children: [
                        const Expanded(child: Text('Total',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                        Text(Fmt.amount(_added.fold<double>(0, (s, e) => s + (e['amount'] as double))),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: kSuccess)),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kSuccess,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Done', style: TextStyle(color: Colors.white,
                        fontWeight: FontWeight.w800, fontSize: 14)),
                  ),
                ],

                // Recent expenses — tap to fix a wrong amount/category/date/etc.
                if (!_loadingRecent && _recent.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Text('RECENT EXPENSES',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kTextSub,
                          letterSpacing: 0.5)),
                  const SizedBox(height: 6),
                  ..._recent.take(5).map((e) {
                    final cat = _categories.firstWhere((c) => c.$1 == e['category'],
                        orElse: () => ('other', '📋 Other', Colors.grey));
                    final label = (e['label'] as String?) ?? (e['notes'] as String?) ?? '';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        // Tapping the label/date/amount area opens Edit — kept
                        // as its own hit region, separate from the delete icon,
                        // so the two actions can never both fire from one tap.
                        Expanded(
                          child: InkWell(
                            onTap: () => _openEditDialog(e),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(children: [
                                Text(cat.$2, style: const TextStyle(fontSize: 12)),
                                const SizedBox(width: 8),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(label.isNotEmpty ? label : cat.$1,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis),
                                  Text(DateFormat('d MMM').format(DateTime.parse(e['expense_date'] as String)),
                                      style: const TextStyle(fontSize: 10, color: kTextHint)),
                                ])),
                                Text(Fmt.amount((e['amount'] as num).toDouble()),
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                                const SizedBox(width: 6),
                                const Icon(Icons.edit_outlined, size: 15, color: kTextHint),
                              ]),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () async {
                            final deleted = await confirmAndDeleteTraderExpense(context, ref, e);
                            if (deleted) _loadRecent();
                          },
                          icon: const Icon(Icons.delete_outline, size: 17, color: Colors.redAccent),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      ]),
                    );
                  }),
                  const SizedBox(height: 4),
                  Center(
                    child: TextButton(
                      onPressed: _openAllExpenses,
                      child: const Text('View All →',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kNavy)),
                    ),
                  ),
                ],
              ]),
        ),
      ),
    );
  }

  Future<void> _openAllExpenses() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AllExpensesSheet(),
    );
    if (saved == true) _loadRecent();
  }

  Future<void> _openEditDialog(Map<String, dynamic> expense) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditExpenseSheet(expense: expense),
    );
    if (saved == true) _loadRecent();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EDIT EXPENSE SHEET
//
// Edits an existing trader_daily_expenses row in place via the
// edit_trader_expense RPC. A reason is required for every edit — this is
// what gets written to trader_expense_audit_log alongside the old/new
// value snapshot, so every correction stays traceable.
// ─────────────────────────────────────────────────────────────────────────────

class _EditExpenseSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> expense;
  const _EditExpenseSheet({required this.expense});
  @override
  ConsumerState<_EditExpenseSheet> createState() => _EditExpenseSheetState();
}

class _EditExpenseSheetState extends ConsumerState<_EditExpenseSheet> {
  final _c         = Supabase.instance.client;
  late final _amtCtrl    = TextEditingController(text: '${widget.expense['amount']}');
  late final _lblCtrl    = TextEditingController(text: (widget.expense['label'] as String?) ?? '');
  late final _notesCtrl  = TextEditingController(text: (widget.expense['notes'] as String?) ?? '');
  final _reasonCtrl = TextEditingController();

  late String  _category    = (widget.expense['category'] as String?) ?? 'other';
  late String? _paymentMode = widget.expense['payment_mode'] as String?;
  late DateTime _expenseDate = DateTime.parse(widget.expense['expense_date'] as String);
  bool _submitting = false;

  static const _categories = [
    ('labour',  '👷 Labour',      Colors.blue),
    ('loading', '📦 Loading',     Colors.teal),
    ('office',  '🏢 Office',      Colors.indigo),
    ('vehicle', '🔧 Vehicle',     Colors.red),
    ('other',   '📋 Other',       Colors.grey),
  ];

  static const _paymentModes = [
    ('cash', '💵 Cash'),
    ('upi',  '📱 UPI'),
    ('bank', '🏦 Bank'),
  ];

  @override
  void dispose() {
    _amtCtrl.dispose();
    _lblCtrl.dispose();
    _notesCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amt = double.tryParse(_amtCtrl.text.trim()) ?? 0;
    if (amt <= 0) { showError(context, 'Enter a valid amount'); return; }
    if (_reasonCtrl.text.trim().isEmpty) {
      showError(context, 'Please enter a reason for this correction');
      return;
    }

    final user = ref.read(appUserProvider).valueOrNull;
    setState(() => _submitting = true);
    try {
      await _c.rpc('edit_trader_expense', params: {
        'p_expense_id':   widget.expense['id'],
        'p_amount':       amt,
        'p_category':     _category,
        'p_expense_date': DateFormat('yyyy-MM-dd').format(_expenseDate),
        'p_label':        _lblCtrl.text.trim().isEmpty ? null : _lblCtrl.text.trim(),
        'p_notes':        _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'p_payment_mode': _paymentMode,
        'p_edited_by':    user?.userId,
        'p_edit_reason':  _reasonCtrl.text.trim(),
      });
      if (mounted) {
        showSuccess(context, 'Expense updated ✓');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        showError(context, e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      decoration: const BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(children: [
                const Icon(Icons.edit_outlined, size: 20, color: kNavy),
                const SizedBox(width: 8),
                const Expanded(child: Text('Edit Expense',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: kNavy))),
                GestureDetector(
                  onTap: () => Navigator.pop(context, false),
                  child: const Icon(Icons.close, size: 20, color: kTextSub),
                ),
              ]),
              const SizedBox(height: 16),

              Wrap(spacing: 8, runSpacing: 8,
                  children: _categories.map((cat) {
                    final selected = _category == cat.$1;
                    return GestureDetector(
                      onTap: () => setState(() => _category = cat.$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected ? cat.$3.withValues(alpha: 0.12) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(kRadiusChip),
                          border: Border.all(color: selected ? cat.$3 : Colors.grey.shade300,
                              width: selected ? 1.5 : 1),
                        ),
                        child: Text(cat.$2,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                                color: selected ? cat.$3 : kTextSub)),
                      ),
                    );
                  }).toList()),
              const SizedBox(height: 12),

              Wrap(spacing: 8, runSpacing: 8,
                  children: _paymentModes.map((pm) {
                    final selected = _paymentMode == pm.$1;
                    return GestureDetector(
                      onTap: () => setState(() => _paymentMode = selected ? null : pm.$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected ? kNavy.withValues(alpha: 0.10) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(kRadiusChip),
                          border: Border.all(color: selected ? kNavy : Colors.grey.shade300,
                              width: selected ? 1.5 : 1),
                        ),
                        child: Text(pm.$2,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                                color: selected ? kNavy : kTextSub)),
                      ),
                    );
                  }).toList()),
              const SizedBox(height: 16),

              TextField(
                controller: _lblCtrl,
                decoration: InputDecoration(
                  labelText: 'Description (optional)',
                  filled: true, fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 10),

              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _expenseDate,
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _expenseDate = picked);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Business Date',
                    prefixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
                    filled: true, fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  child: Text(DateFormat('d MMM yyyy').format(_expenseDate)),
                ),
              ),
              const SizedBox(height: 10),

              TextField(
                controller: _amtCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount (₹)',
                  prefixText: '₹ ',
                  filled: true, fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 10),

              TextField(
                controller: _notesCtrl,
                decoration: InputDecoration(
                  labelText: 'Notes (optional)',
                  filled: true, fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 10),

              TextField(
                controller: _reasonCtrl,
                decoration: InputDecoration(
                  labelText: 'Reason for correction (required)',
                  hintText: 'e.g. Wrong amount entered',
                  filled: true, fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.amber.shade300)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.amber.shade300)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),

              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kNavy,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _submitting
                      ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Save Correction', style: TextStyle(fontWeight: FontWeight.w800,
                      color: Colors.white, fontSize: 14)),
                ),
              ),
            ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ALL EXPENSES SHEET ("View All")
//
// Full, searchable/filterable, paginated history of trader_daily_expenses —
// the "Recent Expenses" list on the Add sheet only ever showed the latest
// few entries with no way to reach older ones. This is read-only listing
// (no new calculations, no backend changes) that reuses the existing
// _EditExpenseSheet for editing, so Add/Edit behavior is untouched.
// ─────────────────────────────────────────────────────────────────────────────

class _AllExpensesSheet extends ConsumerStatefulWidget {
  const _AllExpensesSheet();
  @override
  ConsumerState<_AllExpensesSheet> createState() => _AllExpensesSheetState();
}

class _AllExpensesSheetState extends ConsumerState<_AllExpensesSheet> {
  final _c = Supabase.instance.client;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  String? _categoryFilter; // null = All
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  List<Map<String, dynamic>> _items = [];

  static const _pageSize = 25;

  static const _categories = [
    ('labour',  '👷 Labour',      Colors.blue),
    ('loading', '📦 Loading',     Colors.teal),
    ('office',  '🏢 Office',      Colors.indigo),
    ('vehicle', '🔧 Vehicle',     Colors.red),
    ('other',   '📋 Other',       Colors.grey),
  ];

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _load(reset: true));
  }

  Future<void> _load({bool reset = false}) async {
    final user = ref.read(appUserProvider).valueOrNull;
    if (user == null) return;

    if (reset) {
      setState(() { _loading = true; _items = []; _hasMore = true; });
    } else {
      if (_loadingMore || !_hasMore) return;
      setState(() => _loadingMore = true);
    }

    try {
      var q = _c
          .from('trader_daily_expenses')
          .select('id,expense_date,category,label,notes,amount,payment_mode')
          .eq('trader_id', user.traderId as Object)
          .isFilter('deleted_at', null);
      if (_categoryFilter != null) q = q.eq('category', _categoryFilter!);
      final term = _searchCtrl.text.trim();
      if (term.isNotEmpty) q = q.or('label.ilike.%$term%,notes.ilike.%$term%');

      final from = reset ? 0 : _items.length;
      final r = await q
          .order('expense_date', ascending: false)
          .order('created_at', ascending: false)
          .range(from, from + _pageSize - 1);

      final list = List<Map<String, dynamic>>.from(r as List? ?? []);
      if (mounted) {
        setState(() {
          _items.addAll(list);
          _hasMore = list.length == _pageSize;
          _loading = false;
          _loadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _loading = false; _loadingMore = false; });
        showError(context, e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  Future<void> _openEdit(Map<String, dynamic> expense) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditExpenseSheet(expense: expense),
    );
    if (saved == true) _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200) _load();
            return false;
          },
          child: Container(
            decoration: const BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(children: [
                const Icon(Icons.receipt_long_outlined, size: 20, color: kNavy),
                const SizedBox(width: 8),
                const Expanded(child: Text('All Expenses',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: kNavy))),
                GestureDetector(
                  onTap: () => Navigator.pop(context, false),
                  child: const Icon(Icons.close, size: 20, color: kTextSub),
                ),
              ]),
              const SizedBox(height: 12),

              TextField(
                controller: _searchCtrl,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search description or notes',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  filled: true, fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
              const SizedBox(height: 10),

              SizedBox(
                height: 34,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  _filterChip('All', null),
                  ..._categories.map((c) => _filterChip(c.$2, c.$1)),
                ]),
              ),
              const SizedBox(height: 10),
              const Divider(height: 1),

              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _items.isEmpty
                    ? const Center(child: Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Text('No expenses found', style: TextStyle(color: kTextHint))))
                    : ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _items.length + (_hasMore ? 1 : 0),
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    if (i >= _items.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))),
                      );
                    }
                    final e = _items[i];
                    final cat = _categories.firstWhere((c) => c.$1 == e['category'],
                        orElse: () => ('other', '📋 Other', Colors.grey));
                    final label = (e['label'] as String?) ?? (e['notes'] as String?) ?? '';
                    return Row(children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _openEdit(e),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(children: [
                              Text(cat.$2, style: const TextStyle(fontSize: 14)),
                              const SizedBox(width: 10),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(label.isNotEmpty ? label : cat.$1,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis),
                                Text(
                                  DateFormat('d MMM yyyy').format(DateTime.parse(e['expense_date'] as String))
                                      + ((e['payment_mode'] as String?) != null ? ' · ${e['payment_mode']}' : ''),
                                  style: const TextStyle(fontSize: 11, color: kTextHint),
                                ),
                              ])),
                              Text(Fmt.amount((e['amount'] as num).toDouble()),
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                              const SizedBox(width: 6),
                              const Icon(Icons.edit_outlined, size: 15, color: kTextHint),
                            ]),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () async {
                          final deleted = await confirmAndDeleteTraderExpense(context, ref, e);
                          if (deleted) _load(reset: true);
                        },
                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                        visualDensity: VisualDensity.compact,
                      ),
                    ]);
                  },
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _filterChip(String label, String? value) {
    final selected = _categoryFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          setState(() => _categoryFilter = value);
          _load(reset: true);
        },
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? kNavy.withValues(alpha: 0.10) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(kRadiusChip),
            border: Border.all(color: selected ? kNavy : Colors.grey.shade300,
                width: selected ? 1.5 : 1),
          ),
          child: Text(label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                  color: selected ? kNavy : kTextSub)),
        ),
      ),
    );
  }
}