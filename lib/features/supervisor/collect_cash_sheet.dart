import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/providers/session_provider.dart';
import '../../core/theme/app_theme.dart';
import 'package:rooster_trader/core/util/number_input.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Collect Cash — Supervisor version.
//
// Deliberately the SAME record_payment RPC, SAME params, SAME Business
// Date / Cash-UPI-Bank / optional-remarks logic as the trader-admin
// Collect Payment sheet in retailer_ledger_screen.dart — not a
// reimplementation. The only difference is p_recorded_by is the
// supervisor's own auth user id, and p_trader_id comes from the
// supervisor's own session rather than a trader-admin session. Because
// this calls the exact same RPC that already writes to ledger_entries,
// the entry is visible in the Trader's Customer Ledger immediately with
// no extra plumbing.
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showCollectCashSheet(
    BuildContext context,
    WidgetRef ref, {
      required String retailerId,
    }) async {
  final c = Supabase.instance.client;
  final user = ref.read(appUserProvider).valueOrNull;
  final tid = user?.traderId;
  final uid = user?.userId;

  Map<String, dynamic>? retailer;
  try {
    retailer = await c.from('retailers')
        .select('shop_name,outstanding_balance')
        .eq('id', retailerId).maybeSingle();
  } catch (_) {}

  final shopName = retailer?['shop_name'] as String? ?? 'Customer';
  final outstanding = (retailer?['outstanding_balance'] as num?)?.toDouble() ?? 0;

  final amtCtrl  = TextEditingController();
  final descCtrl = TextEditingController();
  final manualDocCtrl = TextEditingController();
  String mode = 'cash';
  DateTime entryDate = DateTime.now();

  // Doc No preview (CSH-YYYYMM-XXXXX) — record_payment assigns the real
  // number on save; this only shows what it will most likely be.
  Future<String?> previewDocNo(DateTime d) async {
    try {
      return await c.rpc('preview_cash_collection_doc_no', params: {
        'p_trader_id': tid,
        'p_date': DateFormat('yyyy-MM-dd').format(d),
      }) as String?;
    } catch (_) {
      return null;
    }
  }
  String? docNo = await previewDocNo(entryDate);

  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context, isScrollControlled: true, useRootNavigator: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: StatefulBuilder(builder: (_, ss) => Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Collect Cash — $shopName', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          Text('Outstanding: ${Fmt.amount(outstanding)}',
              style: TextStyle(fontSize: 12, color: outstanding > 0 ? Colors.orange : Colors.green, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Doc No (auto)',
                  prefixIcon: Icon(Icons.tag, size: 18)),
              child: Text(docNo ?? 'Assigned on save',
                  style: TextStyle(fontWeight: FontWeight.w700,
                      color: docNo == null ? kTextHint : kNavy)),
            )),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: manualDocCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Man. Doc No (optional)'))),
          ]),
          const SizedBox(height: 10),
          TextField(controller: amtCtrl, inputFormatters: moneyInputFormatters, keyboardType: const TextInputType.numberWithOptions(decimal: true), autofocus: true,
              decoration: const InputDecoration(labelText: 'Amount received (₹) *', prefixText: '₹')),
          const SizedBox(height: 10),
          SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'cash', label: Text('Cash')),
                ButtonSegment(value: 'upi', label: Text('UPI')), ButtonSegment(value: 'bank', label: Text('Bank'))],
              selected: {mode}, onSelectionChanged: (s) => ss(() => mode = s.first)),
          const SizedBox(height: 10),
          // Business Date — defaults to today, editable, never future.
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: ctx, initialDate: entryDate,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                ss(() => entryDate = picked);
                final n = await previewDocNo(picked);
                ss(() => docNo = n);
              }
            },
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Business Date',
                  prefixIcon: Icon(Icons.calendar_today_outlined, size: 18)),
              child: Text(DateFormat('d MMM yyyy').format(entryDate)),
            ),
          ),
          const SizedBox(height: 10),
          TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Remarks (optional)')),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () async {
              final amt = double.tryParse(amtCtrl.text.trim());
              if (amt == null || amt <= 0) return;
              if (tid == null || uid == null) return;
              Navigator.of(ctx, rootNavigator: true).pop();
              try {
                final entryId = await c.rpc('record_payment', params: {
                  'p_trader_id': tid, 'p_retailer_id': retailerId,
                  'p_amount': amt, 'p_payment_mode': mode,
                  'p_description': descCtrl.text.trim().isEmpty ? 'Payment via $mode' : descCtrl.text.trim(),
                  'p_recorded_by': uid,
                  'p_entry_date': DateFormat('yyyy-MM-dd').format(entryDate),
                  'p_assign_doc_no': true,
                  if (manualDocCtrl.text.trim().isNotEmpty)
                    'p_manual_doc_no': manualDocCtrl.text.trim(),
                });
                String? savedDoc;
                try {
                  final row = await c.from('ledger_entries')
                      .select('doc_no').eq('id', entryId as String).maybeSingle();
                  savedDoc = row?['doc_no'] as String?;
                } catch (_) {}
                if (context.mounted) {
                  showSuccess(context,
                      'Payment recorded ✓${savedDoc != null ? '\nDoc No: $savedDoc' : ''}');
                }
              } catch (e) {
                if (context.mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
              }
            },
            child: const Text('Record Payment'),
          ),
        ]))),
  );
}