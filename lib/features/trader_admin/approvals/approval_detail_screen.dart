import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class ApprovalDetailScreen extends ConsumerStatefulWidget {
  const ApprovalDetailScreen({super.key, required this.id});
  final String id;
  @override ConsumerState<ApprovalDetailScreen> createState() => _S();
}

class _S extends ConsumerState<ApprovalDetailScreen> {
  final _c          = Supabase.instance.client;
  final _rateCtrl   = TextEditingController();
  final _notesCtrl  = TextEditingController();
  final _rejectCtrl = TextEditingController();

  Map<String,dynamic>? _delivery;
  bool _loading = true, _submitting = false;

  // ✅ Editable invoice date — defaults to delivery date, fallback to today
  DateTime _invoiceDate = DateTime.now();
  bool _invoiceDateSet = false; // track if we loaded it from delivery

  @override void initState() { super.initState(); _load(); }
  @override void dispose()   { _rateCtrl.dispose(); _notesCtrl.dispose(); _rejectCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await _c.from('deliveries')
          .select('*,orders(retailers(shop_name,owner_name,phone),order_items(rate_per_kg)),delivery_agents(name)')
          .eq('id', widget.id).maybeSingle();
      if (mounted && d != null) {
        // Pre-fill rate
        final items = (d['orders']?['order_items'] as List? ?? []);
        double preRate = 0;
        if (items.isNotEmpty) preRate = (items.first['rate_per_kg'] as num?)?.toDouble() ?? 0;
        final existingRate = (d['final_rate'] as num?)?.toDouble() ?? 0;
        final useRate = existingRate > 0 ? existingRate : preRate;
        if (useRate > 0) _rateCtrl.text = useRate.toStringAsFixed(2);

        // ✅ Pre-fill invoice date from delivery date (if available)
        if (!_invoiceDateSet) {
          final deliveredAt = d['delivered_at'] as String?;
          if (deliveredAt != null) {
            final parsed = DateTime.tryParse(deliveredAt);
            if (parsed != null) {
              _invoiceDate = parsed;
              _invoiceDateSet = true;
            }
          }
          // If no delivered_at, keep today
        }

        setState(() { _delivery = d; _loading = false; });
      } else if (mounted) {
        setState(() => _loading = false);
      }
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  double get _rate   => double.tryParse(_rateCtrl.text.trim()) ?? 0;
  double get _weight => ((_delivery!['received_total_weight'] ?? _delivery!['delivered_total_weight']) as num?)?.toDouble() ?? 0;
  double get _calc   => _weight * _rate;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _invoiceDate,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
      helpText: 'Select Invoice Date',
    );
    if (picked != null) setState(() => _invoiceDate = picked);
  }

  Future<void> _approve() async {
    if (_rate <= 0) { showError(context, 'Enter rate per kg first'); return; }
    final ok = await confirmDialog(context,
        title: 'Approve Delivery',
        message: 'Rate: ₹${_rate.toStringAsFixed(2)}/kg\n'
            'Weight: ${_weight.toStringAsFixed(2)} kg\n'
            'Invoice Amount: ${Fmt.amount(_calc)}\n'
            'Invoice Date: ${DateFormat('d MMM y').format(_invoiceDate)}\n\n'
            'This will create the bill and update the ledger.',
        confirmText: 'Approve & Create Bill',
        confirmColor: kPrimary);
    if (!ok) return;
    setState(() => _submitting = true);
    try {
      // ✅ Pass p_invoice_date so the invoice uses the correct date
      await _c.rpc('approve_delivery_and_order', params: {
        'p_delivery_id':    widget.id,
        'p_final_rate':     _rate,
        'p_approved_by':    ref.read(appUserProvider).valueOrNull?.userId,
        'p_approval_notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'p_invoice_date':   _invoiceDate.toIso8601String().split('T')[0],
      });
      if (mounted) { showSuccess(context, 'Approved — Bill created ✓'); context.go(R.approvals); }
    } catch (e) {
      if (mounted) showError(context, e.toString()
          .replaceAll('Exception: ', '')
          .replaceAll('PostgrestException(message: ', ''));
    } finally { if (mounted) setState(() => _submitting = false); }
  }

  Future<void> _reject() async {
    if (_rejectCtrl.text.trim().isEmpty) { showError(context, 'Enter reason for rejection'); return; }
    final ok = await confirmDialog(context, title: 'Reject Delivery', message: 'Reject this delivery?');
    if (!ok) return;
    setState(() => _submitting = true);
    try {
      await _c.from('deliveries').update({
        'approval_status':  'rejected',
        'rejection_reason': _rejectCtrl.text.trim(),
        'rejected_by':      ref.read(appUserProvider).valueOrNull?.userId,
        'rejected_at':      DateTime.now().toIso8601String(),
      }).eq('id', widget.id);
      if (mounted) { showSuccess(context, 'Rejected'); context.go(R.approvals); }
    } catch (e) { if (mounted) showError(context, e.toString()); }
    finally { if (mounted) setState(() => _submitting = false); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingList());
    if (_delivery == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Not found')));

    final o         = _delivery!['orders']         as Map<String,dynamic>?;
    final r         = o?['retailers']              as Map<String,dynamic>?;
    final a         = _delivery!['delivery_agents'] as Map<String,dynamic>?;
    final birds     = (_delivery!['received_bird_count']   ?? _delivery!['delivered_bird_count']   ?? 0) as int;
    final mortality = (_delivery!['mortality_birds']       as num?)?.toInt() ?? 0;
    final rejected  = (_delivery!['rejected_birds']        as num?)?.toInt() ?? 0;
    final collected = (_delivery!['collected_amount']      as num?)?.toDouble() ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Approve Delivery')),
      body: ListView(padding: const EdgeInsets.all(16), children: [

        // ── Customer & Agent ───────────────────────────────────────
        WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r?['shop_name'] as String? ?? '—',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          if (r?['owner_name'] != null)
            Text(r!['owner_name'] as String, style: const TextStyle(fontSize: 13, color: kTextSub)),
          if (r?['phone'] != null)
            Text(r!['phone'] as String, style: const TextStyle(fontSize: 12, color: kTextHint)),
          if (a != null) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.delivery_dining, size: 14, color: kTextHint),
              const SizedBox(width: 4),
              Text('Agent: ${a['name']}', style: const TextStyle(fontSize: 12, color: kTextHint)),
            ]),
          ],
        ])),
        const SizedBox(height: 12),

        // ── Delivery numbers ───────────────────────────────────────
        WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader('DELIVERY DETAILS'),
          Row(children: [
            _box('Birds', '$birds', kPrimary),
            _box('Weight (kg)', _weight.toStringAsFixed(2), Colors.blue),
            _box('Collected', Fmt.amount(collected), Colors.green),
          ]),
          if (mortality > 0 || rejected > 0) ...[
            const SizedBox(height: 8),
            Row(children: [
              if (mortality > 0) _box('Dead birds', '$mortality', Colors.red),
              if (rejected > 0)  _box('Rejected', '$rejected', Colors.orange),
              const Expanded(child: SizedBox()),
            ]),
          ],
        ])),
        const SizedBox(height: 12),

        // ── Rate + Invoice Date ────────────────────────────────────
        WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader('SET RATE & BILL DATE'),

          // Rate field
          TextFormField(
            controller: _rateCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Rate per kg (₹) *',
              prefixText: '₹',
              prefixIcon: Icon(Icons.currency_rupee, size: 18),
              helperText: 'You can change this — overrides order rate',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),

          // ✅ Invoice date — editable
          const Text('Invoice Date', style: TextStyle(fontSize: 11, color: kTextHint, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.calendar_today_outlined, size: 18, color: kPrimary),
                const SizedBox(width: 10),
                Text(DateFormat('d MMMM y').format(_invoiceDate),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kTextMain)),
                const Spacer(),
                const Text('Change', style: TextStyle(fontSize: 12, color: kPrimary, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          if (!_invoiceDateSet)
            const Padding(padding: EdgeInsets.only(top: 4, left: 4),
                child: Text('Using today\'s date — change if delivery was earlier', style: TextStyle(fontSize: 11, color: Colors.orange))),

          // Calculation
          if (_rate > 0 && _weight > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: kPrimary.withOpacity(0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kPrimary.withOpacity(0.2)),
              ),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('${_weight.toStringAsFixed(2)} kg × ₹${_rate.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 12, color: kTextSub)),
                  Text(Fmt.amount(_calc),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: kPrimary)),
                ]),
                if (collected > 0) ...[
                  const Divider(height: 14),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Already collected', style: TextStyle(fontSize: 11, color: kTextSub)),
                    Text(Fmt.amount(collected),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.green)),
                  ]),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Balance to collect', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kTextMain)),
                    Text(Fmt.amount(_calc - collected),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                            color: (_calc - collected) > 0 ? Colors.orange : Colors.green)),
                  ]),
                ],
              ]),
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(controller: _notesCtrl, decoration: const InputDecoration(labelText: 'Notes (optional)')),
        ])),
        const SizedBox(height: 20),

        // ── Approve ────────────────────────────────────────────────
        ElevatedButton.icon(
          onPressed: _submitting ? null : _approve,
          icon: _submitting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check_circle_outline),
          label: const Text('Approve & Create Bill'),
        ),
        const SizedBox(height: 12),

        // ── Reject (collapsible) ───────────────────────────────────
        ExpansionTile(
          title: const Text('Reject Delivery',
              style: TextStyle(color: kError, fontWeight: FontWeight.w600, fontSize: 14)),
          leading: const Icon(Icons.cancel_outlined, color: kError, size: 20),
          children: [Padding(padding: const EdgeInsets.fromLTRB(16,0,16,16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextFormField(controller: _rejectCtrl, maxLines: 2,
                decoration: const InputDecoration(labelText: 'Reason *', alignLabelWithHint: true)),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _submitting ? null : _reject,
              style: OutlinedButton.styleFrom(foregroundColor: kError, side: const BorderSide(color: kError)),
              child: const Text('Reject Delivery'),
            ),
          ]))],
        ),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _box(String label, String value, Color color) => Expanded(child: Column(children: [
    Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
    const SizedBox(height: 2),
    Text(label, style: const TextStyle(fontSize: 10, color: kTextHint), textAlign: TextAlign.center),
  ]));
}
