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
  final _c = Supabase.instance.client;
  final _rateCtrl   = TextEditingController();
  final _weightCtrl = TextEditingController(); // manual weight
  final _birdsCtrl  = TextEditingController(); // manual birds
  final _notesCtrl  = TextEditingController();
  final _rejectCtrl = TextEditingController();

  Map<String,dynamic>? _delivery;
  bool _loading = true, _submitting = false;
  DateTime _invoiceDate = DateTime.now();

  @override void initState() { super.initState(); _load(); }
  @override void dispose() {
    _rateCtrl.dispose(); _weightCtrl.dispose(); _birdsCtrl.dispose();
    _notesCtrl.dispose(); _rejectCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await _c.from('deliveries')
          .select('*,orders(retailers(shop_name,owner_name,phone),order_items(rate_per_kg,total_weight,bird_count),total_quantity,estimated_birds),delivery_agents(name)')
          .eq('id', widget.id)
          .maybeSingle();
      if (!mounted) return;
      if (d != null) {
        // Pre-fill rate
        final items = (d['orders']?['order_items'] as List? ?? []);
        final orderRate = items.isNotEmpty ? (items.first['rate_per_kg'] as num?)?.toDouble() ?? 0 : 0;
        final existRate = (d['final_rate'] as num?)?.toDouble() ?? 0;
        _rateCtrl.text = (existRate > 0 ? existRate : orderRate > 0 ? orderRate : 0.0).toStringAsFixed(2).replaceAll('.00', '');

        // Pre-fill weight from delivery (if completed by agent)
        final dWeight = ((d['received_total_weight'] ?? d['delivered_total_weight']) as num?)?.toDouble() ?? 0;
        final oWeight = (d['orders']?['total_quantity'] as num?)?.toDouble() ?? 0; // order estimate
        final weight  = dWeight > 0 ? dWeight : oWeight;
        if (weight > 0) _weightCtrl.text = weight.toStringAsFixed(2);

        // Pre-fill birds
        final dBirds = ((d['received_bird_count'] ?? d['delivered_bird_count']) as num?)?.toInt() ?? 0;
        final oBirds = (d['orders']?['estimated_birds'] as int?) ?? 0;
        final birds  = dBirds > 0 ? dBirds : oBirds;
        if (birds > 0) _birdsCtrl.text = '$birds';

        // Invoice date from delivery
        final delivAt = d['delivered_at'] as String?;
        if (delivAt != null) {
          final p = DateTime.tryParse(delivAt);
          if (p != null) _invoiceDate = p;
        }
      }
      setState(() { _delivery = d; _loading = false; });
    } catch (e) { if (mounted) setState(() => _loading = false); }
  }

  double get _weight => double.tryParse(_weightCtrl.text.trim()) ?? 0;
  double get _rate   => double.tryParse(_rateCtrl.text.trim()) ?? 0;
  int    get _birds  => int.tryParse(_birdsCtrl.text.trim()) ?? 0;
  double get _calc   => _weight * _rate;

  // Weight from delivery (what agent recorded)
  double get _agentWeight {
    if (_delivery == null) return 0;
    return (((_delivery!['received_total_weight'] ?? _delivery!['delivered_total_weight'])) as num?)?.toDouble() ?? 0;
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _invoiceDate,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now());
    if (d != null && mounted) if (mounted) setState(() => _invoiceDate = d);
  }

  Future<void> _approve() async {
    if (_rate <= 0) { showError(context, 'Enter rate per kg'); return; }
    if (_weight <= 0) { showError(context, 'Enter weight in kg — this is needed to calculate the bill'); return; }

    final ok = await confirmDialog(context,
      title: 'Approve Delivery',
      message: '${_weight.toStringAsFixed(2)} kg × ₹${_rate.toStringAsFixed(2)}/kg\n'
               '= ${Fmt.amount(_calc)}\n\n'
               'Bill Date: ${DateFormat('d MMM y').format(_invoiceDate)}\n\n'
               'Ledger will be updated.',
      confirmText: 'Approve & Create Bill',
      confirmColor: kPrimary);
    if (!ok) return;

    setState(() => _submitting = true);
    try {
      await _c.rpc('approve_delivery_and_order', params: {
        'p_delivery_id':    widget.id,
        'p_final_rate':     _rate,
        'p_approved_by':    ref.read(appUserProvider).valueOrNull?.userId,
        'p_approval_notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'p_invoice_date':   _invoiceDate.toIso8601String().split('T')[0],
        'p_weight_kg':      _weight,
        'p_bird_count':     _birds > 0 ? _birds : null,
      });
      if (mounted) { showSuccess(context, 'Approved! Bill created ✓'); context.go(R.approvals); }
    } catch (e) {
      if (mounted) showError(context, e.toString()
          .replaceAll('Exception: ', '')
          .replaceAll('PostgrestException(message: ', ''));
    } finally { if (mounted) setState(() => _submitting = false); }
  }

  Future<void> _reject() async {
    if (_rejectCtrl.text.trim().isEmpty) { showError(context, 'Enter reason for rejection'); return; }
    final ok = await confirmDialog(context, title: 'Reject', message: 'Reject this delivery?');
    if (!ok) return;
    if (mounted) setState(() => _submitting = true);
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

    final o = _delivery!['orders'] as Map<String,dynamic>?;
    final r = o?['retailers']     as Map<String,dynamic>?;
    final a = _delivery!['delivery_agents'] as Map<String,dynamic>?;
    final collected = (_delivery!['collected_amount'] as num?)?.toDouble() ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Approve Delivery'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [

        // ── Customer card ──────────────────────────────────────────
        WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r?['shop_name'] as String? ?? '—',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          if (r?['owner_name'] != null)
            Text(r!['owner_name'] as String, style: const TextStyle(fontSize: 13, color: kTextSub)),
          if (a != null) ...[const SizedBox(height: 4),
            Row(children: [const Icon(Icons.delivery_dining, size: 13, color: kTextHint), const SizedBox(width: 4),
              Text('Agent: ${a['name']}', style: const TextStyle(fontSize: 12, color: kTextHint))])],
        ])),
        const SizedBox(height: 12),

        // ── Weight & Birds ─────────────────────────────────────────
        WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Delivery Details', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            if (_agentWeight > 0)
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                child: Text('Agent recorded: ${_agentWeight.toStringAsFixed(2)} kg',
                    style: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 10),

          // Weight field — required for invoice
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Weight (kg) *', style: TextStyle(fontSize: 11, color: kTextHint, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              TextField(
                controller: _weightCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  hintText: 'e.g. 250.0',
                  suffixText: 'kg',
                  filled: true, fillColor: const Color(0xFFF3F4F6),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ])),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Birds (optional)', style: TextStyle(fontSize: 11, color: kTextHint, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              TextField(
                controller: _birdsCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'e.g. 150',
                  suffixText: 'birds',
                  filled: true, fillColor: const Color(0xFFF3F4F6),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
            ])),
          ]),

          if (_agentWeight == 0) ...[
            const SizedBox(height: 6),
            const Row(children: [
              Icon(Icons.info_outline, size: 12, color: Colors.orange),
              SizedBox(width: 4),
              Expanded(child: Text('Agent did not record weight. Enter the actual weight above to generate bill.',
                  style: TextStyle(fontSize: 11, color: Colors.orange))),
            ]),
          ],

          if (collected > 0) ...[
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Cash collected by agent:', style: TextStyle(fontSize: 12, color: kTextSub)),
              Text(Fmt.amount(collected), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.green)),
            ]),
          ],
        ])),
        const SizedBox(height: 12),

        // ── Rate & Calculation ─────────────────────────────────────
        WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Rate & Bill Calculation', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),

          // Rate
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Rate per kg (₹) *', style: TextStyle(fontSize: 11, color: kTextHint, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            TextField(
              controller: _rateCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: 'e.g. 200',
                prefixText: '₹',
                suffixText: '/kg',
                filled: true, fillColor: const Color(0xFFF3F4F6),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kPrimary, width: 1.5)),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ]),

          // Live calculation box
          if (_weight > 0 && _rate > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: kPrimary.withOpacity(0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kPrimary.withOpacity(0.2))),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('${_weight.toStringAsFixed(2)} kg  ×  ₹${_rateCtrl.text}/kg',
                      style: const TextStyle(fontSize: 12, color: kTextSub)),
                  Text(Fmt.amount(_calc),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: kPrimary)),
                ]),
                if (collected > 0) ...[
                  const Divider(height: 14),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Collected', style: TextStyle(fontSize: 11, color: kTextSub)),
                    Text(Fmt.amount(collected), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green)),
                  ]),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Balance', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    Text(Fmt.amount(_calc - collected),
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
                            color: (_calc - collected) > 0 ? Colors.orange : Colors.green)),
                  ]),
                ],
              ]),
            ),
          ],

          // Invoice Date
          const SizedBox(height: 12),
          const Text('Invoice Date', style: TextStyle(fontSize: 11, color: kTextHint, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.calendar_today_outlined, size: 16, color: kPrimary),
                const SizedBox(width: 10),
                Text(DateFormat('d MMMM y').format(_invoiceDate),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const Spacer(),
                const Text('Change', style: TextStyle(fontSize: 12, color: kPrimary, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),

          // Notes
          const SizedBox(height: 12),
          TextField(controller: _notesCtrl,
              decoration: const InputDecoration(labelText: 'Notes (optional)')),
        ])),
        const SizedBox(height: 20),

        // ── Approve ────────────────────────────────────────────────
        SizedBox(height: 52, child: ElevatedButton.icon(
          onPressed: _submitting ? null : _approve,
          icon: _submitting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check_circle_outline, size: 20),
          label: const Text('Approve & Create Bill', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        )),
        const SizedBox(height: 12),

        // ── Reject (collapsible) ───────────────────────────────────
        ExpansionTile(
          title: const Text('Reject Delivery', style: TextStyle(color: kError, fontWeight: FontWeight.w600)),
          leading: const Icon(Icons.cancel_outlined, color: kError, size: 20),
          children: [Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: _rejectCtrl, maxLines: 2,
                decoration: const InputDecoration(labelText: 'Reason for rejection *', alignLabelWithHint: true)),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _submitting ? null : _reject,
              style: OutlinedButton.styleFrom(foregroundColor: kError, side: const BorderSide(color: kError)),
              child: const Text('Reject Delivery')),
          ]))],
        ),
        const SizedBox(height: 20),
      ]),
    );
  }
}
