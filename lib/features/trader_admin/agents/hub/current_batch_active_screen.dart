import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_theme.dart';

// ══════════════════════════════════════════════════════════════════════════
// CURRENT BATCH ACTIVITIES — lets the trader undo a mistaken Quick Entry
// delivery while the batch/shift is still open and before it's approved or
// invoiced.
//
// Backend: undo_instant_delivery (new). Completed deliveries stay fully
// immutable — status, delivered_bird_count, delivered_total_weight are
// NEVER edited. Undo is recorded as a separate event (is_undone/undone_at/
// undo_reason flags) and stock is restored via a compensating
// 'delivery_reversed' stock_ledger entry, never a delete. After undo, the
// order returns to out_for_delivery so the SAME, unchanged Quick Entry flow
// can be used again for that customer.
// ══════════════════════════════════════════════════════════════════════════

class CurrentBatchActivitiesScreen extends ConsumerStatefulWidget {
  const CurrentBatchActivitiesScreen({
    super.key,
    required this.agentId,
    required this.agentName,
  });

  final String agentId;
  final String agentName;

  @override
  ConsumerState<CurrentBatchActivitiesScreen> createState() => _S();
}

class _S extends ConsumerState<CurrentBatchActivitiesScreen> {
  final _c = Supabase.instance.client;

  bool _loading = true;
  bool _noActiveBatch = false;
  String? _batchId;
  List<Map<String, dynamic>> _deliveries = [];
  String? _undoingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null || !mounted) return;
    setState(() => _loading = true);
    try {
      // The current (still-active) batch for this agent — same definition
      // of "active" already used elsewhere for batch pickup/DC flows.
      final batch = await _c
          .from('delivery_batches')
          .select('id')
          .eq('trader_id', tid)
          .eq('delivery_agent_id', widget.agentId)
          .inFilter('status', ['assigned', 'picked_up', 'out_for_delivery'])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;
      if (batch == null) {
        setState(() {
          _noActiveBatch = true;
          _batchId = null;
          _deliveries = [];
          _loading = false;
        });
        return;
      }

      final bid = batch['id'] as String;
      final rows = await _c
          .from('deliveries')
          .select(
          'id,order_id,delivered_at,delivered_bird_count,delivered_total_weight,'
              'collected_amount,mortality_birds,shrinkage_kg,approval_status,'
              'delivery_shift_id,'
              'retailers(shop_name),'
              'orders(is_partial_delivery,partial_count),'
              'delivery_shifts(status),'
              'invoices(id)')
          .eq('batch_id', bid)
          .eq('status', 'delivered')
          .eq('is_undone', false)
          .order('delivered_at', ascending: false)
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;
      setState(() {
        _batchId = bid;
        _noActiveBatch = false;
        _deliveries = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      showError(context, e.toString());
    }
  }

  // Mirrors the server-side preconditions in undo_instant_delivery — this
  // is UX only (hide the button rather than show-then-fail); the RPC is
  // the actual source of truth and re-checks everything itself.
  bool _canUndo(Map<String, dynamic> d) {
    if (d['approval_status'] == 'approved') return false;
    if (_invoiceList(d).isNotEmpty) return false;
    final shift = d['delivery_shifts'] as Map<String, dynamic>?;
    if (shift?['status'] != 'open') return false;
    if (((d['mortality_birds'] as num?) ?? 0) > 0) return false;
    if (((d['shrinkage_kg'] as num?) ?? 0) > 0) return false;
    final order = d['orders'] as Map<String, dynamic>?;
    if (order?['is_partial_delivery'] == true) return false;
    if (((order?['partial_count'] as num?) ?? 0) > 1) return false;
    return true;
  }

  List _invoiceList(Map<String, dynamic> d) {
    final raw = d['invoices'];
    if (raw is List) return raw;
    if (raw is Map) return [raw];
    return const [];
  }

  String _whyNotUndoable(Map<String, dynamic> d) {
    if (d['approval_status'] == 'approved') {
      return 'Already approved — use Invoice Correction';
    }
    if (_invoiceList(d).isNotEmpty) {
      return 'Invoice already generated — use Invoice Correction';
    }
    final shift = d['delivery_shifts'] as Map<String, dynamic>?;
    if (shift?['status'] != 'open') return 'Shift is closed';
    if (((d['mortality_birds'] as num?) ?? 0) > 0 ||
        ((d['shrinkage_kg'] as num?) ?? 0) > 0) {
      return 'Has mortality/shrinkage recorded';
    }
    final order = d['orders'] as Map<String, dynamic>?;
    if (order?['is_partial_delivery'] == true ||
        ((order?['partial_count'] as num?) ?? 0) > 1) {
      return 'Part of a partial-delivery chain';
    }
    return 'Cannot be undone';
  }

  Future<void> _undo(Map<String, dynamic> d) async {
    final reasonCtrl = TextEditingController();
    final birds = d['delivered_bird_count'] ?? 0;
    final kg = (d['delivered_total_weight'] as num?)?.toStringAsFixed(1) ?? '0';

    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusCard)),
        title: const Text('Undo Delivery', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This restores $birds birds / $kg kg back to stock and resets '
                  'the order so it can be delivered again with Quick Entry. '
                  'The original delivery record is kept for history and cannot '
                  'be edited.',
              style: const TextStyle(color: kTextSub, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                  labelText: 'Reason', border: OutlineInputBorder(), isDense: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c, rootNavigator: true).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(c, rootNavigator: true).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: kError),
            child: const Text('Undo Delivery'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final uid = ref.read(appUserProvider).valueOrNull?.userId;
    setState(() => _undoingId = d['id'] as String);
    try {
      await _c.rpc('undo_instant_delivery', params: {
        'p_delivery_id': d['id'],
        'p_actor_type': 'trader',
        'p_actor_id': uid,
        'p_reason': reasonCtrl.text.trim().isEmpty
            ? 'Mistaken Quick Entry'
            : reasonCtrl.text.trim(),
      }).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      showSuccess(context, 'Delivery undone — stock restored ✓');
      await _load();
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _undoingId = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kBgPage,
    appBar: AppBar(
      backgroundColor: kSurface,
      title: Text('Current Batch — ${widget.agentName}'),
    ),
    body: _loading
        ? const LoadingList()
        : _noActiveBatch
        ? const EmptyState(
        icon: Icons.inventory_2_outlined,
        message: 'No active batch for this agent')
        : _deliveries.isEmpty
        ? const EmptyState(
        icon: Icons.check_circle_outline,
        message: 'No deliveries yet in the current batch')
        : RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _deliveries.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _deliveryCard(_deliveries[i]),
      ),
    ),
  );

  Widget _deliveryCard(Map<String, dynamic> d) {
    final retailer = d['retailers'] as Map<String, dynamic>?;
    final date = DateTime.tryParse(d['delivered_at'] as String? ?? '');
    final canUndo = _canUndo(d);
    final isUndoing = _undoingId == d['id'];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard), boxShadow: kCardShadow),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(retailer?['shop_name'] as String? ?? '—',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
          Text(date != null ? DateFormat('h:mm a').format(date) : '—',
              style: const TextStyle(fontSize: 12, color: kTextHint)),
        ]),
        const SizedBox(height: 6),
        Text(
            '${d['delivered_bird_count'] ?? 0} birds · '
                '${(d['delivered_total_weight'] as num?)?.toStringAsFixed(1) ?? 0} kg'
                '${(d['collected_amount'] as num? ?? 0) > 0 ? ' · ${Fmt.amount((d['collected_amount'] as num).toDouble())} collected' : ''}',
            style: const TextStyle(fontSize: 13, color: kTextSub)),
        const SizedBox(height: 10),
        if (canUndo)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: isUndoing ? null : () => _undo(d),
              icon: isUndoing
                  ? const SizedBox(
                  width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.undo, size: 16, color: kError),
              label: Text(isUndoing ? 'Undoing…' : 'Undo Delivery',
                  style: const TextStyle(color: kError)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: kError)),
            ),
          )
        else
          Text(_whyNotUndoable(d),
              style: const TextStyle(fontSize: 11, color: kTextHint, fontStyle: FontStyle.italic)),
      ]),
    );
  }
}