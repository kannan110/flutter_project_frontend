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
  final _odoEnd = TextEditingController();
  final _birds = TextEditingController(text: '0');
  final _weight = TextEditingController(text: '0');
  final _expenses = TextEditingController(text: '0');
  bool _loading = false;
  Map<String,dynamic>? _shift;
  @override void initState() { super.initState(); _loadShift(); }
  @override void dispose() { _odoEnd.dispose(); _birds.dispose(); _weight.dispose(); _expenses.dispose(); super.dispose(); }

  Future<void> _loadShift() async {
    final agentId = ref.read(appUserProvider).valueOrNull?.agentId;
    if (agentId == null) return;
    final s = await _c.from('delivery_shifts').select('*').eq('delivery_agent_id', agentId).eq('status','open').maybeSingle();
    if (mounted) setState(() => _shift = s);
  }

  Future<void> _close() async {
    if (_odoEnd.text.trim().isEmpty) { showError(context, 'Enter odometer end reading'); return; }
    if (_shift == null) { showError(context, 'No active shift found'); return; }
    final ok = await confirmDialog(context, title: 'Close Shift', message: 'Close shift? Ensure all deliveries are complete.', confirmText: 'Close Shift', confirmColor: kPrimary);
    if (!ok) return;
    setState(() => _loading = true);
    try {
      // close_delivery_shift(p_shift_id, p_odometer_end, p_odometer_end_photo, p_closing_bird_count, p_closing_weight, p_expenses)
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
    body: _shift == null ? const Center(child: Text('No active shift found.', style: TextStyle(color: kTextSub)))
        : SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: kPrimary.withOpacity(0.07), borderRadius: BorderRadius.circular(12), border: Border.all(color: kPrimary.withOpacity(0.2))),
              child: Text('Shift started at odometer: ${_shift!['odometer_start'] ?? '—'} km', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kPrimary))),
            const SizedBox(height: 20),
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
            ElevatedButton.icon(onPressed: _loading ? null : _close,
              icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.lock_outline, size: 18),
              label: const Text('Close Shift'), style: ElevatedButton.styleFrom(backgroundColor: kError)),
          ])),
  );
}
