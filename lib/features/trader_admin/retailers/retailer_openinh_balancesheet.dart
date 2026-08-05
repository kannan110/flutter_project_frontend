import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RETAILER OPENING BALANCE SHEET
//
// Bottom sheet for setting/editing a retailer's pre-Rooster opening balance.
// Extracted out of RetailerDetailScreen, which previously rendered this form
// inline in the page (pushing/overlapping other content). Now follows the
// same showModalBottomSheet pattern used elsewhere in trader_admin, e.g.
// trader_addexpense_sheet.dart.
//
// Calls set_retailer_opening_balance RPC directly. The RPC (fixed separately)
// never deletes ledger_entries — it posts append-only compensating entries —
// so this sheet just needs to call it and refresh on success.
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showRetailerOpeningBalanceSheet(
    BuildContext context, {
      required String retailerId,
      required String shopName,
      required double currentAmount,
      required String? currentDate,
      required String? currentNote,
      required VoidCallback onSaved,
    }) async {
  await showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _OpeningBalanceSheet(
      retailerId: retailerId,
      shopName: shopName,
      currentAmount: currentAmount,
      currentDate: currentDate,
      currentNote: currentNote,
      onSaved: onSaved,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class _OpeningBalanceSheet extends ConsumerStatefulWidget {
  const _OpeningBalanceSheet({
    required this.retailerId,
    required this.shopName,
    required this.currentAmount,
    required this.currentDate,
    required this.currentNote,
    required this.onSaved,
  });

  final String retailerId;
  final String shopName;
  final double currentAmount;
  final String? currentDate;
  final String? currentNote;
  final VoidCallback onSaved;

  @override
  ConsumerState<_OpeningBalanceSheet> createState() =>
      _OpeningBalanceSheetState();
}

class _OpeningBalanceSheetState extends ConsumerState<_OpeningBalanceSheet> {
  final _c = Supabase.instance.client;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _noteCtrl;
  late DateTime _date;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(
        text: widget.currentAmount > 0
            ? widget.currentAmount.toStringAsFixed(0)
            : '0');
    _noteCtrl = TextEditingController(text: widget.currentNote ?? '');
    _date = DateTime.tryParse(widget.currentDate ?? '') ?? DateTime.now();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amt = double.tryParse(_amountCtrl.text.trim()) ?? -1;
    if (amt < 0) {
      showError(context, 'Enter a valid amount (0 or greater)');
      return;
    }
    setState(() => _saving = true);
    try {
      await _c.rpc('set_retailer_opening_balance', params: {
        'p_retailer_id': widget.retailerId,
        'p_amount': amt,
        'p_as_of_date': '${_date.year}-'
            '${_date.month.toString().padLeft(2, '0')}-'
            '${_date.day.toString().padLeft(2, '0')}',
        'p_note': _noteCtrl.text.trim().isEmpty
            ? 'Opening balance (migration)'
            : _noteCtrl.text.trim(),
      });
      if (mounted) {
        showSuccess(context, 'Opening balance saved ✓');
        widget.onSaved();
        Navigator.of(context, rootNavigator: true).pop();
      }
    } catch (e) {
      if (mounted) {
        showError(
            context,
            e.toString()
                .replaceAll('Exception: ', '')
                .replaceAll('PostgrestException: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
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
            Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: kBorderLight,
                      borderRadius: BorderRadius.circular(2)),
                )),
            const SizedBox(height: 16),

            // Header
            Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.account_balance_wallet_outlined,
                    color: Colors.orange, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Opening Balance',
                          style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      Text('For ${widget.shopName}',
                          style: const TextStyle(fontSize: 12, color: kTextHint)),
                    ],
                  )),
              IconButton(
                onPressed: () =>
                    Navigator.of(context, rootNavigator: true).pop(),
                icon: const Icon(Icons.close, size: 20),
              ),
            ]),
            const SizedBox(height: 8),

            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8)),
              child: const Row(children: [
                Icon(Icons.info_outline, size: 14, color: Colors.orange),
                SizedBox(width: 8),
                Expanded(
                    child: Text(
                      'This sets the amount owed before joining Rooster. '
                          'It posts as "Opening Balance" in the ledger.',
                      style: TextStyle(fontSize: 11, color: Colors.orange),
                    )),
              ]),
            ),

            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Outstanding Amount (₹)',
                  prefixText: '₹',
                  filled: true,
                  fillColor: Colors.white),
            ),
            const SizedBox(height: 10),

            // Date picker
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (picked != null && mounted) setState(() => _date = picked);
              },
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade400)),
                child: Row(children: [
                  const Icon(Icons.calendar_today_outlined,
                      size: 16, color: kTextSub),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('As of Date',
                              style: TextStyle(fontSize: 11, color: kTextSub)),
                          Text(
                              '${_date.day} '
                                  '${[
                                'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                                'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
                              ][_date.month - 1]} '
                                  '${_date.year}',
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                        ],
                      )),
                  const Icon(Icons.arrow_drop_down, color: kTextSub),
                ]),
              ),
            ),
            const SizedBox(height: 10),

            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                  labelText: 'Note / Reference (optional)',
                  filled: true,
                  fillColor: Colors.white),
            ),
            const SizedBox(height: 20),

            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(kRadiusBtn))),
                child: _saving
                    ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                    : const Text('Save Opening Balance',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}