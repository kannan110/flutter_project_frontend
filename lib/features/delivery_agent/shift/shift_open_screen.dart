import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class ShiftOpenScreen extends ConsumerStatefulWidget {
  const ShiftOpenScreen({super.key});
  @override ConsumerState<ShiftOpenScreen> createState() => _S();
}
class _S extends ConsumerState<ShiftOpenScreen> {
  final _c = Supabase.instance.client;
  final _odo = TextEditingController();
  bool _loading = false;
  Map<String,dynamic>? _existing;
  @override void initState() { super.initState(); _check(); }
  @override void dispose() { _odo.dispose(); super.dispose(); }

  Future<void> _check() async {
    final agentId = ref.read(appUserProvider).valueOrNull?.agentId;
    if (agentId == null) return;
    final s = await _c.from('delivery_shifts').select('*').eq('delivery_agent_id', agentId).eq('status','open').maybeSingle();
    if (mounted) setState(() => _existing = s);
  }

  Future<void> _open() async {
    if (_odo.text.trim().isEmpty) { showError(context, 'Enter odometer reading'); return; }
    final user = ref.read(appUserProvider).valueOrNull;
    if (mounted) setState(() => _loading = true);
    try {
      // delivery_shifts: trader_id, delivery_agent_id, status, odometer_start, shift_start_at
      // NO shift_date column — use shift_start_at timestamp
      await _c.from('delivery_shifts').insert({
        'trader_id': user?.traderId, 'delivery_agent_id': user?.agentId,
        'status': 'open', 'odometer_start': double.tryParse(_odo.text.trim()),
        'shift_start_at': DateTime.now().toIso8601String(),
      });
      if (mounted) { showSuccess(context, 'Shift opened ✓'); context.go(R.agentHome); }
    } catch (e) { if (mounted) showError(context, e.toString()); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Open Shift')),
    body: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_existing != null) ...[
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.shade200)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Shift Already Open', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.green)),
            Text('Started: Odometer ${_existing!['odometer_start'] ?? '—'} km', style: const TextStyle(fontSize: 12, color: kTextSub)),
            const SizedBox(height: 10),
            ElevatedButton(onPressed: () => context.go(R.shiftClose), child: const Text('Close Shift')),
          ])),
      ] else ...[
        const Icon(Icons.directions_car_outlined, size: 60, color: kPrimary),
        const SizedBox(height: 16),
        const Text('Start Your Shift', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kTextMain), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        const Text('Record odometer reading before starting deliveries.', style: TextStyle(fontSize: 13, color: kTextSub), textAlign: TextAlign.center),
        const SizedBox(height: 32),
        TextField(controller: _odo, keyboardType: TextInputType.number, autofocus: true, decoration: const InputDecoration(labelText: 'Odometer Reading (km) *', prefixIcon: Icon(Icons.speed_outlined, size: 20), suffixText: 'km')),
        const SizedBox(height: 24),
        ElevatedButton(onPressed: _loading ? null : _open,
            child: _loading ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Open Shift')),
      ],
    ])),
  );
}
