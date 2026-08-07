import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';

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

  String _category   = 'labour';
  bool   _submitting = false;
  // Business Date — defaults to today, editable, never future. Lets the
  // trader record expenses from a few days ago (e.g. catching up on 3-5
  // days of pending entries) so they land on the correct day in P&L and
  // Batch Cost Allocation instead of always being stamped with today.
  DateTime _expenseDate = DateTime.now();

  // Accumulated entries in this session (shown as chips before close)
  final List<Map<String, dynamic>> _added = [];

  static const _categories = [
    ('labour',  '👷 Labour',      Colors.blue),
    ('loading', '📦 Loading',     Colors.teal),
    ('office',  '🏢 Office',      Colors.indigo),
    ('vehicle', '🔧 Vehicle',     Colors.red),
    ('other',   '📋 Other',       Colors.grey),
  ];

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
        'created_by':   user.userId,
      });

      setState(() {
        _added.add({'category': _category, 'amount': amt, 'label': _lblCtrl.text.trim()});
        _amtCtrl.clear();
        _lblCtrl.clear();
        _submitting = false;
      });
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
          ]),
    );
  }
}