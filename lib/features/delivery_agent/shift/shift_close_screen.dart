import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class ShiftCloseScreen extends ConsumerStatefulWidget {
  const ShiftCloseScreen({super.key});
  @override
  ConsumerState<ShiftCloseScreen> createState() => _ShiftCloseScreenState();
}

class _ShiftCloseScreenState extends ConsumerState<ShiftCloseScreen> {
  final _formKey        = GlobalKey<FormState>();
  final _closingBirds   = TextEditingController();
  final _closingWeight  = TextEditingController();
  final _odomEnd        = TextEditingController();
  bool _loading = true;
  bool _submitting = false;
  Map<String, dynamic>? _openShift;
  double _totalExpenses = 0;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _closingBirds.dispose(); _closingWeight.dispose(); _odomEnd.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final agentId = ref.read(appUserProvider).valueOrNull?.agentId;
    if (agentId == null) { setState(() => _loading = false); return; }
    final shift = await Supabase.instance.client.from('delivery_shifts')
        .select('*').eq('delivery_agent_id', agentId).eq('status', 'open').maybeSingle();
    double expenses = 0;
    if (shift != null) {
      final expRows = List<Map<String, dynamic>>.from(
        await Supabase.instance.client.from('delivery_expenses').select('amount').eq('shift_id', shift['id']));
      expenses = expRows.fold(0, (s, e) => s + ((e['amount'] as num?)?.toDouble() ?? 0));
    }
    if (mounted) setState(() { _openShift = shift; _totalExpenses = expenses; _loading = false; });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_openShift == null) { showError(context, 'No open shift found'); return; }
    setState(() => _submitting = true);
    try {
      final agentId = ref.read(appUserProvider).valueOrNull?.agentId;
      await Supabase.instance.client.rpc('close_delivery_shift', params: {
        'p_shift_id':           _openShift!['id'],
        'p_odometer_end':       double.tryParse(_odomEnd.text) ?? 0,
        'p_odometer_end_photo': '',
        'p_closing_bird_count': int.tryParse(_closingBirds.text) ?? 0,
        'p_closing_weight':     double.tryParse(_closingWeight.text) ?? 0,
        'p_expenses':           _totalExpenses,
      });
      await Supabase.instance.client.from('delivery_agents')
          .update({'is_online': false, 'last_seen_at': DateTime.now().toIso8601String()}).eq('id', agentId!);
      if (mounted) { showSuccess(context, 'Shift closed successfully'); context.go(Routes.agentHome); }
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: AppBar(title: const Text('Close Shift')), body: const Center(child: CircularProgressIndicator()));
    if (_openShift == null) return Scaffold(
      appBar: AppBar(title: const Text('Close Shift')),
      body: const EmptyState(icon: Icons.info_outline, message: 'No active shift', sub: 'Open a shift first from the home screen'),
    );

    final opening = (_openShift!['opening_bird_count'] as int?) ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Close Shift')),
      body: Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.07), borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.primary.withOpacity(0.2))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Shift Summary', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.primary)),
              const SizedBox(height: 8),
              Text('Opening birds: $opening', style: const TextStyle(fontSize: 13)),
              Text('Reconciliation: delivered + mortality + closing = $opening',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E))),
            ]),
          ),
          const SizedBox(height: 20),
          const SectionHeader('CLOSING DETAILS'),
          TextFormField(
            controller: _closingBirds, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Closing Bird Count (unsold / returned) *',
                prefixIcon: Icon(Icons.egg_outlined, size: 18)),
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _closingWeight, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Closing Weight (kg)', prefixIcon: Icon(Icons.scale_outlined, size: 18)),
          ),
          const SizedBox(height: 16),
          const SectionHeader('ODOMETER'),
          TextFormField(
            controller: _odomEnd, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Odometer End (km)', prefixIcon: Icon(Icons.speed_outlined, size: 18)),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Total Expenses', style: TextStyle(fontSize: 13)),
              Text('₹${_totalExpenses.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.red)),
            ]),
          ),
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: _submitting
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Close Shift'),
          ),
        ]),
      ),
    );
  }
}
