import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class CreateAgentScreen extends ConsumerStatefulWidget {
  const CreateAgentScreen({super.key});
  @override ConsumerState<CreateAgentScreen> createState() => _S();
}
class _S extends ConsumerState<CreateAgentScreen> {
  final _c = Supabase.instance.client;
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _vehicle = TextEditingController();
  // vehicle_type CHECK: two_wheeler, auto, mini_truck, truck
  String _vehicleType = 'two_wheeler';
  bool _submitting = false;
  @override void dispose() { _name.dispose(); _phone.dispose(); _vehicle.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (mounted) setState(() => _submitting = true);
    try {
      // delivery_agents: trader_id, name, phone, vehicle_no, vehicle_type, is_active
      // auth_user_id is intentionally NULL — agent links it themselves
      await _c.from('delivery_agents').insert({
        'trader_id': tid, 'name': _name.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'vehicle_no': _vehicle.text.trim().isEmpty ? null : _vehicle.text.trim(),
        'vehicle_type': _vehicleType, 'is_active': true,
      });
      if (mounted) { showSuccess(context, 'Agent added! Share your Company Code with them.'); if (context.canPop()) context.pop(); else context.go(R.agents); }
    } catch (e) { if (mounted) showError(context, e.toString()); }
    finally { if (mounted) setState(() => _submitting = false); }
  }

  @override
  Widget build(BuildContext context) {
    final code = ref.watch(appUserProvider).valueOrNull?.companyCode ?? '—';
    return Scaffold(
      appBar: AppBar(title: const Text('Add Delivery Agent')),
      body: SingleChildScrollView(padding: const EdgeInsets.all(20),
        child: Form(key: _form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.shade100)),
            child: Text('① Fill agent name, phone & vehicle and save.\n② Share Company Code with agent: $code\n③ Agent opens app → Login → "Link Agent Account" → enters code + their name.\n④ Agent linked and can log in.', style: TextStyle(fontSize: 12, color: Colors.blue.shade800, height: 1.5))),
          const SizedBox(height: 20),
          const SectionHeader('AGENT DETAILS'),
          TextFormField(controller: _name, textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Full Name *', prefixIcon: Icon(Icons.person_outline, size: 20), helperText: 'Agent must enter this exact name when linking'),
              validator: (v) => v!.trim().isEmpty ? 'Name required' : null),
          const SizedBox(height: 12),
          TextFormField(controller: _phone, keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone', prefixIcon: Icon(Icons.phone_outlined, size: 20))),
          const SizedBox(height: 20),
          const SectionHeader('VEHICLE'),
          TextFormField(controller: _vehicle, textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Vehicle Number', prefixIcon: Icon(Icons.directions_car_outlined, size: 20))),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value:'two_wheeler', icon: Icon(Icons.two_wheeler, size: 14), label: Text('2-Wheeler')),
              ButtonSegment(value:'auto', icon: Icon(Icons.electric_rickshaw, size: 14), label: Text('Auto')),
              ButtonSegment(value:'mini_truck', icon: Icon(Icons.local_shipping, size: 14), label: Text('Mini Truck')),
            ],
            selected: {_vehicleType}, onSelectionChanged: (s) => setState(() => _vehicleType = s.first)),
          const SizedBox(height: 28),
          ElevatedButton(onPressed: _submitting ? null : _save,
              child: _submitting ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Add Agent')),
        ]))),
    );
  }
}
