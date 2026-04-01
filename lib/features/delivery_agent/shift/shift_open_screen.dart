import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class ShiftOpenScreen extends ConsumerStatefulWidget {
  const ShiftOpenScreen({super.key});
  @override ConsumerState<ShiftOpenScreen> createState() => _S();
}

class _S extends ConsumerState<ShiftOpenScreen> {
  final _c   = Supabase.instance.client;
  final _odo = TextEditingController();
  bool _loading = false, _checking = true;
  Map<String,dynamic>? _existing;

  @override void initState() { super.initState(); _check(); }
  @override void dispose()   { _odo.dispose(); super.dispose(); }

  Future<void> _check() async {
    final agentId = ref.read(appUserProvider).valueOrNull?.agentId;
    if (agentId == null) {
      if (mounted) setState(() => _checking = false);
      return;
    }
    try {
      // FIX: same fix as home screen — separate query, no Future.wait type issues
      final s = await _c
          .from('delivery_shifts')
          .select('id,status,odometer_start,shift_start_at,total_cash_collected,total_deliveries')
          .eq('delivery_agent_id', agentId)
          .eq('status', 'open')
          .maybeSingle();
      if (mounted) setState(() { _existing = s; _checking = false; });
    } catch (e) {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _open() async {
    if (_odo.text.trim().isEmpty) { showError(context, 'Enter odometer reading'); return; }
    final user = ref.read(appUserProvider).valueOrNull;
    if (user?.agentId == null) {
      showError(context, 'Agent not linked. Please link your account first.');
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      await _c.from('delivery_shifts').insert({
        'trader_id':         user!.traderId,
        'delivery_agent_id': user.agentId,
        'status':            'open',
        'odometer_start':    double.tryParse(_odo.text.trim()) ?? 0,
        'shift_start_at':    DateTime.now().toIso8601String(),
      });
      if (mounted) {
        showSuccess(context, 'Shift opened ✓ — start delivering!');
        // FIX: go to home so home screen re-fetches and shows the shift
        context.go(R.agentHome);
      }
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      if (msg.contains('duplicate') || msg.contains('already')) {
        // Shift already exists — just go home
        if (mounted) {
          showSuccess(context, 'Shift already open. Taking you back.');
          context.go(R.agentHome);
        }
      } else {
        if (mounted) showError(context, msg);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Open Shift')),
    body: _checking
        ? const LoadingList()
        : _existing != null
            // ── Already open ──────────────────────────────────────
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.green.shade200)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Row(children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 22),
                        SizedBox(width: 10),
                        Text('Shift Already Open',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.green)),
                      ]),
                      const SizedBox(height: 10),
                      _infoRow('Odometer start', '${_existing!['odometer_start'] ?? '—'} km'),
                      if ((_existing!['total_deliveries'] as int? ?? 0) > 0)
                        _infoRow('Deliveries done', '${_existing!['total_deliveries']}'),
                      if ((_existing!['total_cash_collected'] as num? ?? 0) > 0)
                        _infoRow('Cash collected', Fmt.amount((_existing!['total_cash_collected'] as num).toDouble())),
                    ])),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => context.go(R.agentHome),
                    icon: const Icon(Icons.home_outlined),
                    label: const Text('Go to Home', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => context.go(R.shiftClose),
                    icon: const Icon(Icons.lock_outline, size: 18),
                    label: const Text('Close This Shift'),
                    style: OutlinedButton.styleFrom(foregroundColor: kError, side: const BorderSide(color: kError))),
                ]))
            // ── Open new shift ────────────────────────────────────
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Icon(Icons.directions_car_outlined, size: 60, color: kPrimary),
                  const SizedBox(height: 16),
                  const Text('Start Your Shift',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  const Text('Record your odometer before starting deliveries.',
                      style: TextStyle(fontSize: 13, color: kTextSub), textAlign: TextAlign.center),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _odo,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    decoration: const InputDecoration(
                        labelText: 'Odometer Reading (km) *',
                        prefixIcon: Icon(Icons.speed_outlined, size: 20),
                        suffixText: 'km')),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _loading ? null : _open,
                    child: _loading
                        ? const SizedBox(width: 22, height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Open Shift', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                ])),
  );

  Widget _infoRow(String l, String v) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(children: [
      Text('$l: ', style: const TextStyle(fontSize: 12, color: kTextSub)),
      Text(v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
    ]));
}
