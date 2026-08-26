import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/responsive_layout.dart';

class RetailerLedgerScreen extends ConsumerStatefulWidget {
  const RetailerLedgerScreen({super.key, required this.retailerId});
  final String retailerId;
  @override ConsumerState<RetailerLedgerScreen> createState() => _S();
}
class _S extends ConsumerState<RetailerLedgerScreen> {
  final _c = Supabase.instance.client;
  Map<String,dynamic>? _retailer;
  List<Map<String,dynamic>> _entries = [];
  Set<String> _reversedIds = {};
  double _outstanding = 0, _totalDebit = 0, _totalCredit = 0;
  bool _loading = true;
  String _filter = 'all'; // all, debit, credit
  DateTime? _fromDate, _toDate;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final r = await _c.from('retailers')
          .select('id,shop_name,owner_name,phone,credit_limit').eq('id', widget.retailerId).maybeSingle();

      var q = _c.from('ledger_entries')
          .select('id,entry_type,amount,payment_mode,description,entry_date,created_at,source_type')
          .eq('retailer_id', widget.retailerId);
      if (_filter == 'debit')  q = q.eq('entry_type', 'debit');
      if (_filter == 'credit') q = q.eq('entry_type', 'credit');
      if (_fromDate != null) q = q.gte('entry_date', _fromDate!.toIso8601String().split('T')[0]);
      if (_toDate   != null) q = q.lte('entry_date', _toDate!.toIso8601String().split('T')[0]);

      final e = await q.order('entry_date', ascending: false).order('created_at', ascending: false).limit(200);
      final rawEntries = List<Map<String,dynamic>>.from(e);

      // Which credits have already been reversed/edited — used both to
      // hide the Edit/Remove affordance on entries that can't be touched
      // again, AND (ROOT CAUSE FIX, Cash Collection Edit/Remove reporting
      // audit) to hide the now-superseded original entry itself, and any
      // payment_reversal row, from the customer-facing ledger view —
      // only the latest effective collection should ever be shown here.
      final reversedRows = await _c.from('retailer_payment_audit_log')
          .select('original_entry_id').eq('retailer_id', widget.retailerId);
      final reversedIds = List<Map<String,dynamic>>.from(reversedRows)
          .map((r) => r['original_entry_id'] as String).toSet();

      final entries = rawEntries.where((x) =>
      x['source_type'] != 'payment_reversal' &&
          !(x['entry_type'] == 'credit' && reversedIds.contains(x['id']))
      ).toList();

      // Compute totals from ALL entries (not filtered) for outstanding —
      // this signed debit-credit sum must NOT exclude reversals/originals,
      // it already nets them correctly and must stay that way.
      final all = List<Map<String,dynamic>>.from(await _c.from('ledger_entries')
          .select('entry_type,amount').eq('retailer_id', widget.retailerId));
      double debit = 0, credit = 0;
      for (final x in all) {
        if (x['entry_type'] == 'debit')  debit  += (x['amount'] as num).toDouble();
        if (x['entry_type'] == 'credit') credit += (x['amount'] as num).toDouble();
      }
      // Filtered totals — from the already-cleaned `entries` list, so
      // superseded/removed collections never inflate these either.
      double fd = 0, fc = 0;
      for (final x in entries) {
        if (x['entry_type'] == 'debit')  fd += (x['amount'] as num).toDouble();
        if (x['entry_type'] == 'credit') fc += (x['amount'] as num).toDouble();
      }

      if (mounted) setState(() { _retailer = r; _entries = entries; _reversedIds = reversedIds; _outstanding = debit - credit; _totalDebit = fd; _totalCredit = fc; _loading = false; });
    } catch (e) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _recordPayment() async {
    final amtCtrl  = TextEditingController();
    final descCtrl = TextEditingController();
    String mode = 'cash';
    DateTime entryDate = DateTime.now();
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    final uid = ref.read(appUserProvider).valueOrNull?.userId;

    await showModalBottomSheet(context: context, isScrollControlled: true, useRootNavigator: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: StatefulBuilder(builder: (_, ss) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Collect Payment — ${_retailer?['shop_name'] ?? ''}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              Text('Outstanding: ${Fmt.amount(_outstanding)}', style: TextStyle(fontSize: 12, color: _outstanding > 0 ? Colors.orange : Colors.green, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              TextField(controller: amtCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), autofocus: true,
                  decoration: const InputDecoration(labelText: 'Amount received (₹) *', prefixText: '₹')),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                  segments: const [ButtonSegment(value:'cash',label:Text('Cash')), ButtonSegment(value:'upi',label:Text('UPI')), ButtonSegment(value:'bank',label:Text('Bank'))],
                  selected: {mode}, onSelectionChanged: (s) => ss(() => mode = s.first)),
              const SizedBox(height: 10),
              // Business Date — defaults to today, editable, never future —
              // lets the trader record a payment collected a few days ago
              // (e.g. entering 3-5 days of pending cash collections on a
              // catch-up day) so it lands on the correct day everywhere
              // downstream (Customer Ledger, P&L, Cash Flow) instead of
              // always being stamped with today's date.
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: entryDate,
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) ss(() => entryDate = picked);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Business Date',
                      prefixIcon: Icon(Icons.calendar_today_outlined, size: 18)),
                  child: Text(DateFormat('d MMM yyyy').format(entryDate)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Reference / Notes (optional)')),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () async {
                final amt = double.tryParse(amtCtrl.text.trim());
                if (amt == null || amt <= 0) return;
                Navigator.of(ctx, rootNavigator: true).pop();
                try {
                  await _c.rpc('record_payment', params: {
                    'p_trader_id': tid, 'p_retailer_id': widget.retailerId,
                    'p_amount': amt, 'p_payment_mode': mode,
                    'p_description': descCtrl.text.trim().isEmpty ? 'Payment via $mode' : descCtrl.text.trim(),
                    'p_recorded_by': uid,
                    'p_entry_date': DateFormat('yyyy-MM-dd').format(entryDate),
                  });
                  _load(); if (mounted) showSuccess(context, 'Payment recorded ✓');
                } catch (e) { if (mounted) showError(context, e.toString()); }
              }, child: const Text('Record Payment')),
            ]))));
    // controllers are ephemeral locals — GC handles disposal
  }

  Future<void> _confirmAndReverseCollection(Map<String, dynamic> entry) async {
    final reasonCtrl = TextEditingController();
    final amt = Fmt.amount((entry['amount'] as num).toDouble());

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        String? error;
        return StatefulBuilder(builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            title: const Text('Remove this collection?'),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$amt — ${entry['description'] ?? 'Payment'}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 6),
              const Text(
                'This posts a reversal entry dated today — the original stays '
                    'in the ledger for audit. Outstanding, Customer Ledger and '
                    'reports update immediately.',
                style: TextStyle(fontSize: 12, color: kTextSub),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: reasonCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Reason (required)',
                  hintText: 'e.g. Recorded by mistake',
                  errorText: error,
                  isDense: true,
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
              TextButton(
                onPressed: () {
                  if (reasonCtrl.text.trim().isEmpty) {
                    setDialogState(() => error = 'Please enter a reason');
                    return;
                  }
                  Navigator.pop(dialogCtx, true);
                },
                child: const Text('Remove', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700)),
              ),
            ],
          );
        });
      },
    );
    if (confirmed != true) return;

    final reason = reasonCtrl.text.trim();
    final uid = ref.read(appUserProvider).valueOrNull?.userId;
    try {
      await _c.rpc('reverse_collection', params: {
        'p_entry_id': entry['id'],
        'p_reason': reason,
        'p_reversed_by': uid,
      });
      if (mounted) { showSuccess(context, 'Collection removed ✓'); _load(); }
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _openEditCollection(Map<String, dynamic> entry) async {
    final amtCtrl = TextEditingController(text: '${entry['amount']}');
    final descCtrl = TextEditingController(text: entry['description'] as String? ?? '');
    final reasonCtrl = TextEditingController();
    String mode = entry['payment_mode'] as String? ?? 'cash';
    DateTime entryDate = DateTime.tryParse(entry['entry_date'] as String? ?? '') ?? DateTime.now();
    final uid = ref.read(appUserProvider).valueOrNull?.userId;

    await showModalBottomSheet(
      context: context, isScrollControlled: true, useRootNavigator: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: StatefulBuilder(builder: (_, ss) => SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Edit Collection', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text(
              'This reverses the original entry and records a corrected one — '
                  'the original stays in the ledger for audit.',
              style: TextStyle(fontSize: 12, color: kTextSub),
            ),
            const SizedBox(height: 14),
            TextField(controller: amtCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount (₹) *', prefixText: '₹')),
            const SizedBox(height: 10),
            SegmentedButton<String>(
                segments: const [ButtonSegment(value: 'cash', label: Text('Cash')),
                  ButtonSegment(value: 'upi', label: Text('UPI')), ButtonSegment(value: 'bank', label: Text('Bank'))],
                selected: {mode}, onSelectionChanged: (s) => ss(() => mode = s.first)),
            const SizedBox(height: 10),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: ctx, initialDate: entryDate,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now(),
                );
                if (picked != null) ss(() => entryDate = picked);
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Business Date',
                    prefixIcon: Icon(Icons.calendar_today_outlined, size: 18)),
                child: Text(DateFormat('d MMM yyyy').format(entryDate)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Reference / Notes (optional)')),
            const SizedBox(height: 10),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Reason for correction (required)',
                hintText: 'e.g. Wrong amount entered',
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                final amt = double.tryParse(amtCtrl.text.trim());
                if (amt == null || amt <= 0) { showError(ctx, 'Enter a valid amount'); return; }
                if (reasonCtrl.text.trim().isEmpty) { showError(ctx, 'Please enter a reason'); return; }
                Navigator.of(ctx, rootNavigator: true).pop();
                try {
                  await _c.rpc('edit_collection', params: {
                    'p_entry_id': entry['id'],
                    'p_new_amount': amt,
                    'p_new_entry_date': DateFormat('yyyy-MM-dd').format(entryDate),
                    'p_new_payment_mode': mode,
                    'p_new_description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                    'p_edited_by': uid,
                    'p_reason': reasonCtrl.text.trim(),
                  });
                  if (mounted) { showSuccess(context, 'Collection updated ✓'); _load(); }
                } catch (e) {
                  if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
                }
              },
              child: const Text('Save Correction'),
            ),
          ]),
        )),
      ),
    );
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(context: context,
        firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now(),
        initialDateRange: _fromDate != null && _toDate != null ? DateTimeRange(start: _fromDate!, end: _toDate!) : null);
    if (range != null) { if (mounted) setState(() { _fromDate = range.start; _toDate = range.end; }); _load(); }
  }

  Widget _buildScaffold(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingList());
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: Text(_retailer?['shop_name'] as String? ?? 'Ledger'),
        actions: [
          IconButton(icon: const Icon(Icons.date_range_outlined), onPressed: _pickDateRange, tooltip: 'Filter by date'),
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: Column(children: [

        // Summary header — navy gradient
        Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [kNavy, kNavyMid],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(children: [
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('OUTSTANDING', style: TextStyle(fontSize: 10, color: Color(0xFFB4C6F4),
                      fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                  const SizedBox(height: 4),
                  Text(Fmt.amount(_outstanding), style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900,
                      color: _outstanding > 0 ? kGoldLight : const Color(0xFF86EFAC))),
                ])),
                ElevatedButton.icon(
                    onPressed: _recordPayment,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Collect'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kGold,
                      foregroundColor: kNavy,
                      minimumSize: const Size(0, 42),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusChip)),
                    )),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: _statBox('Total Billed', Fmt.amount(_totalDebit), Colors.red)),
                const SizedBox(width: 10),
                Expanded(child: _statBox('Total Received', Fmt.amount(_totalCredit), Colors.green)),
              ]),
              if (_fromDate != null) ...[const SizedBox(height: 12),
                Container(padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(kRadiusInner)),
                    child: Row(children: [
                      const Icon(Icons.date_range, size: 14, color: Color(0xFFB4C6F4)),
                      const SizedBox(width: 6),
                      Text('${DateFormat('d MMM').format(_fromDate!)} – ${DateFormat('d MMM y').format(_toDate!)}', style: const TextStyle(fontSize: 11, color: Color(0xFFB4C6F4), fontWeight: FontWeight.w600)),
                      const Spacer(),
                      GestureDetector(onTap: () { if (mounted) setState(() { _fromDate = null; _toDate = null; }); _load(); },
                          child: const Icon(Icons.close, size: 14, color: Color(0xFFB4C6F4))),
                    ])),
              ],
            ])),

        // Filter tabs
        Container(
            color: Colors.white, padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: SegmentedButton<String>(
                segments: const [ButtonSegment(value:'all',label:Text('All')), ButtonSegment(value:'debit',label:Text('Purchases')), ButtonSegment(value:'credit',label:Text('Payments'))],
                selected: {_filter}, onSelectionChanged: (s) { if (mounted) setState(() => _filter = s.first); _load(); })),
        const Divider(height: 1),

        // Transactions list
        Expanded(child: _entries.isEmpty
            ? const EmptyState(icon: Icons.receipt_long_outlined, message: 'No transactions', sub: 'Transactions appear here after orders and payments')
            : ListView.separated(
            padding: const EdgeInsets.all(16), itemCount: _entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, i) {
              final e = _entries[i];
              final isDebit = e['entry_type'] == 'debit';
              final amt  = (e['amount'] as num).toDouble();
              final date = DateTime.tryParse(e['entry_date'] as String? ?? '') ?? DateTime.now();
              // Only a genuine, not-yet-reversed collection can be
              // edited/removed — never a purchase/debit line, and never
              // something already corrected once (prevents double
              // reversal at the UI level too, on top of the RPC guard).
              final canEditDelete = !isDebit
                  && e['source_type'] == 'payment'
                  && !_reversedIds.contains(e['id']);
              return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
                  child: Row(children: [
                    Container(width: 38, height: 38,
                        decoration: BoxDecoration(color: (isDebit ? Colors.red : Colors.green).withValues(alpha: 0.1), shape: BoxShape.circle),
                        child: Icon(isDebit ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                            size: 18, color: isDebit ? Colors.red : Colors.green)),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e['description'] as String? ?? (isDebit ? 'Purchase' : 'Payment'),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Row(children: [
                        Text(DateFormat('d MMM y').format(date), style: const TextStyle(fontSize: 10, color: kTextHint)),
                        if (e['payment_mode'] != null) ...[
                          const Text(' · ', style: TextStyle(fontSize: 10, color: kTextHint)),
                          Text((e['payment_mode'] as String).toUpperCase(), style: const TextStyle(fontSize: 10, color: kTextHint)),
                        ],
                      ]),
                    ])),
                    Text('${isDebit ? '+' : '−'}${Fmt.amount(amt)}',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: isDebit ? Colors.red : Colors.green)),
                    if (canEditDelete) ...[
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 16, color: kTextHint),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _openEditCollection(e),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _confirmAndReverseCollection(e),
                      ),
                    ],
                  ]));
            })),
      ]),
    );
  }

  Widget _statBox(String l, String v, Color c) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(kRadiusInner)),
      child: Column(children: [
        Text(v, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
        Text(l, style: const TextStyle(fontSize: 10, color: Color(0xFFB4C6F4), fontWeight: FontWeight.w700)),
      ]));
  @override
  Widget build(BuildContext context) => ResponsiveLayout(
    mobile:  (_) => _buildScaffold(context),
    desktop: (_) => _buildScaffold(context),
  );

}