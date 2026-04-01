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
  final _c        = Supabase.instance.client;
  final _odoEnd   = TextEditingController();
  final _birds    = TextEditingController(text: '0');
  final _weight   = TextEditingController(text: '0');
  final _expenses = TextEditingController(text: '0');
  bool _loading = false, _checking = true;
  Map<String,dynamic>? _shift;
  Map<String,dynamic>? _summary; // shift summary for review

  @override void initState() { super.initState(); _loadShift(); }
  @override void dispose()   { _odoEnd.dispose(); _birds.dispose(); _weight.dispose(); _expenses.dispose(); super.dispose(); }

  Future<void> _loadShift() async {
    final agentId = ref.read(appUserProvider).valueOrNull?.agentId;
    if (agentId == null) { if (mounted) setState(() => _checking = false); return; }
    try {
      final s = await _c.from('delivery_shifts')
          .select('id,status,odometer_start,shift_start_at,total_cash_collected,total_deliveries')
          .eq('delivery_agent_id', agentId)
          .eq('status', 'open')
          .maybeSingle();

      // FIX: Load shift summary — pending deliveries count
      Map<String,dynamic>? summary;
      if (s != null) {
        final pending = await _c.from('deliveries')
            .select('id')
            .eq('delivery_agent_id', agentId)
            .inFilter('status', ['assigned', 'picked_up', 'out_for_delivery']);
        summary = {'pending_count': (pending as List).length};
      }

      if (mounted) setState(() { _shift = s; _summary = summary; _checking = false; });
    } catch (_) { if (mounted) setState(() => _checking = false); }
  }

  Future<void> _close() async {
    if (_odoEnd.text.trim().isEmpty) { showError(context, 'Enter odometer end reading'); return; }
    if (_shift == null)              { showError(context, 'No active shift found'); return; }

    final pending = (_summary?['pending_count'] as int?) ?? 0;
    String msg = 'Close shift?';
    if (pending > 0) {
      msg = '⚠ $pending deliveries are still pending.\n\nAre you sure you want to close the shift?';
    }

    final ok = await confirmDialog(context,
        title: 'Close Shift',
        message: msg,
        confirmText: 'Close Shift',
        confirmColor: pending > 0 ? Colors.orange : kPrimary);
    if (!ok) return;

    if (mounted) setState(() => _loading = true);
    try {
      await _c.rpc('close_delivery_shift', params: {
        'p_shift_id':            _shift!['id'],
        'p_odometer_end':        double.tryParse(_odoEnd.text.trim()) ?? 0,
        'p_odometer_end_photo':  null,
        'p_closing_bird_count':  int.tryParse(_birds.text.trim())   ?? 0,
        'p_closing_weight':      double.tryParse(_weight.text.trim()) ?? 0,
        'p_expenses':            double.tryParse(_expenses.text.trim()) ?? 0,
      });
      if (mounted) { showSuccess(context, 'Shift closed ✓'); context.go(R.agentHome); }
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Close Shift')),
    body: _checking ? const LoadingList() :
      _shift == null
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.info_outline, size: 48, color: kTextHint),
              const SizedBox(height: 12),
              const Text('No active shift found.', style: TextStyle(color: kTextSub)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () => context.go(R.agentHome), child: const Text('Go to Home')),
            ]))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // Shift info card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: kPrimary.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kPrimary.withValues(alpha: 0.2))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Shift opened at odometer: ${_shift!['odometer_start'] ?? '—'} km',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kPrimary)),
                    const SizedBox(height: 4),
                    if (_shift!['total_cash_collected'] != null)
                      Text('Cash collected: ${Fmt.amount((_shift!['total_cash_collected'] as num).toDouble())}',
                          style: const TextStyle(fontSize: 12, color: kTextSub)),
                    if (_shift!['total_deliveries'] != null)
                      Text('Deliveries done: ${_shift!['total_deliveries']}',
                          style: const TextStyle(fontSize: 12, color: kTextSub)),
                  ])),

                // Pending deliveries warning
                if ((_summary?['pending_count'] ?? 0) > 0) Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange.shade200)),
                    child: Row(children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        '${_summary!['pending_count']} deliveries still pending. '
                        'Complete them before closing if possible.',
                        style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w600))),
                      TextButton(
                        onPressed: () => context.go(R.agentDeliveries),
                        child: const Text('View →')),
                    ])),
                ),
                const SizedBox(height: 20),

                const SectionHeader('ODOMETER END'),
                TextField(
                  controller: _odoEnd,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: const InputDecoration(
                      labelText: 'End Reading (km) *', suffixText: 'km')),
                const SizedBox(height: 16),

                const SectionHeader('CLOSING STOCK (UNSOLD BIRDS)'),
                Row(children: [
                  Expanded(child: TextField(
                    controller: _birds,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Remaining birds', suffixText: 'birds'))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(
                    controller: _weight,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Remaining weight (kg)', suffixText: 'kg'))),
                ]),
                const SizedBox(height: 16),

                const SectionHeader('EXPENSES'),
                TextField(
                  controller: _expenses,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Fuel, toll, misc (₹)', prefixText: '₹')),
                const SizedBox(height: 28),

                ElevatedButton.icon(
                  onPressed: _loading ? null : _close,
                  icon: _loading
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.lock_outline, size: 18),
                  label: const Text('Close Shift', style: TextStyle(fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(backgroundColor: kError)),
              ])),
  );
}
