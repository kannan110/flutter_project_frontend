import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class ShiftCloseScreen extends ConsumerStatefulWidget {
  const ShiftCloseScreen({super.key});
  @override ConsumerState<ShiftCloseScreen> createState() => _S();
}
class _S extends ConsumerState<ShiftCloseScreen> {
  final _c = Supabase.instance.client;
  final _odoEnd  = TextEditingController();
  final _birds   = TextEditingController(text: '0');
  final _weight  = TextEditingController(text: '0');
  final _expenses = TextEditingController(text: '0');
  bool _loading = false;
  Map<String,dynamic>? _shift;
  // FIX Bug #6: track pending deliveries before allowing close
  List<Map<String,dynamic>> _pendingDeliveries = [];
  bool _checkingPending = false;

  @override void initState() { super.initState(); _loadShift(); }
  @override void dispose() { _odoEnd.dispose(); _birds.dispose(); _weight.dispose(); _expenses.dispose(); super.dispose(); }

  Future<void> _loadShift() async {
    final agentId = ref.read(appUserProvider).valueOrNull?.agentId;
    if (agentId == null) return;
    setState(() => _checkingPending = true);
    final s = await _c.from('delivery_shifts').select('*').eq('delivery_agent_id', agentId).eq('status','open').maybeSingle();
    if (mounted) {
      setState(() { _shift = s; });
      if (s != null) await _loadPendingDeliveries(agentId, s['id'] as String);
    }
  }

  // FIX Bug #6: fetch deliveries in this shift that are not yet completed
  Future<void> _loadPendingDeliveries(String agentId, String shiftId) async {
    try {
      final pending = await _c.from('deliveries')
          .select('id, status, orders(retailers(shop_name))')
          .eq('delivery_agent_id', agentId)
          .not('status', 'in', '(delivered,cancelled,returned)')
          .order('created_at');
      if (mounted) setState(() {
        _pendingDeliveries = List<Map<String,dynamic>>.from(pending);
        _checkingPending = false;
      });
    } catch (_) {
      if (mounted) setState(() => _checkingPending = false);
    }
  }

  Future<void> _close() async {
    if (_odoEnd.text.trim().isEmpty) { showError(context, 'Enter odometer end reading'); return; }
    if (_shift == null) { showError(context, 'No active shift found'); return; }

    // FIX Bug #6: warn if there are pending deliveries (TOS rule: "Cannot close shift with incomplete deliveries")
    if (_pendingDeliveries.isNotEmpty) {
      final force = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Incomplete Deliveries'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_pendingDeliveries.length} delivery(ies) are still pending:', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          ..._pendingDeliveries.take(5).map((d) {
            final o = d['orders'] as Map<String,dynamic>?;
            final r = o?['retailers'] as Map<String,dynamic>?;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                const Icon(Icons.warning_amber, size: 14, color: Colors.orange),
                const SizedBox(width: 6),
                Expanded(child: Text(r?['shop_name'] as String? ?? '—', style: const TextStyle(fontSize: 12))),
                StatusBadge(d['status'] as String? ?? '—', Colors.orange, small: true),
              ]),
            );
          }),
          if (_pendingDeliveries.length > 5)
            Text('...and ${_pendingDeliveries.length - 5} more.', style: const TextStyle(fontSize: 12, color: kTextSub)),
          const SizedBox(height: 10),
          const Text('Are you sure you want to close the shift anyway? Your admin will be notified.', style: TextStyle(fontSize: 12, color: kTextSub)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: kError),
            child: const Text('Force Close'),
          ),
        ],
      )) ?? false;
      if (!force) return;
    } else {
      final ok = await confirmDialog(context, title: 'Close Shift', message: 'Close shift? All deliveries are complete.', confirmText: 'Close Shift', confirmColor: kPrimary);
      if (!ok) return;
    }

    setState(() => _loading = true);
    try {
      await _c.rpc('close_delivery_shift', params: {
        'p_shift_id': _shift!['id'],
        'p_odometer_end': double.tryParse(_odoEnd.text) ?? 0,
        'p_odometer_end_photo': null,
        'p_closing_bird_count': int.tryParse(_birds.text) ?? 0,
        'p_closing_weight': double.tryParse(_weight.text) ?? 0,
        'p_expenses': double.tryParse(_expenses.text) ?? 0,
      });
      if (mounted) { showSuccess(context, 'Shift closed ✓'); context.go(R.agentHome); }
    } catch (e) { if (mounted) showError(context, e.toString()); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Close Shift')),
    body: _shift == null
        ? const Center(child: Text('No active shift found.', style: TextStyle(color: kTextSub)))
        : SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: kPrimary.withOpacity(0.07), borderRadius: BorderRadius.circular(12), border: Border.all(color: kPrimary.withOpacity(0.2))),
              child: Text('Shift started at odometer: ${_shift!['odometer_start'] ?? '—'} km', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kPrimary))),
            const SizedBox(height: 12),

            // FIX Bug #6: show pending deliveries warning before close
            if (_checkingPending)
              const Padding(padding: EdgeInsets.only(bottom: 12), child: LinearProgressIndicator())
            else if (_pendingDeliveries.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.shade300)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.warning_amber_outlined, color: Colors.orange, size: 18),
                    const SizedBox(width: 8),
                    Text('${_pendingDeliveries.length} Incomplete Delivery(ies)', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.orange)),
                  ]),
                  const SizedBox(height: 6),
                  ..._pendingDeliveries.take(3).map((d) {
                    final o = d['orders'] as Map<String,dynamic>?;
                    final r = o?['retailers'] as Map<String,dynamic>?;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text('• ${r?['shop_name'] ?? '—'}  (${d['status']})', style: const TextStyle(fontSize: 12, color: Colors.orange)),
                    );
                  }),
                  const SizedBox(height: 4),
                  const Text('Complete these before closing the shift.', style: TextStyle(fontSize: 11, color: Colors.orange)),
                ]),
              )
            else
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.green.shade200)),
                child: const Row(children: [
                  Icon(Icons.check_circle_outline, color: Colors.green, size: 16),
                  SizedBox(width: 8),
                  Text('All deliveries complete ✓', style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600)),
                ]),
              ),

            const SectionHeader('ODOMETER END'),
            TextField(controller: _odoEnd, keyboardType: TextInputType.number, autofocus: true, decoration: const InputDecoration(labelText: 'End Reading (km) *', suffixText: 'km')),
            const SizedBox(height: 16),
            const SectionHeader('CLOSING STOCK (UNSOLD)'),
            Row(children: [
              Expanded(child: TextField(controller: _birds, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Birds remaining'))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _weight, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Weight (kg)'))),
            ]),
            const SizedBox(height: 16),
            const SectionHeader('TOTAL EXPENSES'),
            TextField(controller: _expenses, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Fuel, toll, misc (₹)', prefixText: '₹')),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: _loading ? null : _close,
              icon: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.lock_outline, size: 18),
              label: const Text('Close Shift'),
              style: ElevatedButton.styleFrom(backgroundColor: kError),
            ),
          ])),
  );
}
