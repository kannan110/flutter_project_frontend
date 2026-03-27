import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class ShiftOpenScreen extends ConsumerStatefulWidget {
  const ShiftOpenScreen({super.key});
  @override
  ConsumerState<ShiftOpenScreen> createState() => _ShiftOpenScreenState();
}

class _ShiftOpenScreenState extends ConsumerState<ShiftOpenScreen> {
  final _formKey    = GlobalKey<FormState>();
  final _birdsCtrl  = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _odomCtrl   = TextEditingController();
  bool _submitting  = false;

  @override
  void dispose() { _birdsCtrl.dispose(); _weightCtrl.dispose(); _odomCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final user     = ref.read(appUserProvider).valueOrNull;
      final agentId  = user?.agentId;
      final traderId = user?.traderId;
      if (agentId == null || traderId == null) throw Exception('Agent profile not found');

      // Check no existing open shift
      final existing = await Supabase.instance.client.from('delivery_shifts')
          .select('id').eq('delivery_agent_id', agentId).eq('status', 'open').maybeSingle();
      if (existing != null) throw Exception('You already have an open shift');

      await Supabase.instance.client.from('delivery_shifts').insert({
        'delivery_agent_id':  agentId,
        'trader_id':          traderId,
        'shift_start_at':     DateTime.now().toIso8601String(),
        'opening_bird_count': int.tryParse(_birdsCtrl.text) ?? 0,
        'opening_weight':     double.tryParse(_weightCtrl.text) ?? 0,
        'odometer_start':     double.tryParse(_odomCtrl.text),
        'status':             'open',
      });

      // Mark agent as online
      await Supabase.instance.client.from('delivery_agents')
          .update({'is_online': true, 'last_seen_at': DateTime.now().toIso8601String()}).eq('id', agentId);

      if (mounted) { showSuccess(context, 'Shift started!'); context.go(Routes.agentHome); }
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Open Shift')),
    body: Form(
      key: _formKey,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Container(padding: const EdgeInsets.all(14), margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.07), borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.primary.withOpacity(0.2))),
          child: const Row(children: [
            Icon(Icons.info_outline, color: AppTheme.primary, size: 16), SizedBox(width: 8),
            Expanded(child: Text('Record how many birds and total weight you are loading from the farm.',
              style: TextStyle(fontSize: 12, color: AppTheme.primary))),
          ])),
        const SectionHeader('LOADING DETAILS'),
        TextFormField(controller: _birdsCtrl, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Opening Bird Count *', prefixIcon: Icon(Icons.egg_outlined, size: 18)),
          validator: (v) => (v == null || v.isEmpty) ? 'Required' : null),
        const SizedBox(height: 12),
        TextFormField(controller: _weightCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Opening Weight (kg)', prefixIcon: Icon(Icons.scale_outlined, size: 18))),
        const SizedBox(height: 16),
        const SectionHeader('VEHICLE'),
        TextFormField(controller: _odomCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Odometer Start (km)', prefixIcon: Icon(Icons.speed_outlined, size: 18))),
        const SizedBox(height: 28),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Start Shift'),
        ),
      ]),
    ),
  );
}
