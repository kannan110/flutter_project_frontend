import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class CreateAgentScreen extends ConsumerStatefulWidget {
  const CreateAgentScreen({super.key});
  @override
  ConsumerState<CreateAgentScreen> createState() => _CreateAgentScreenState();
}

class _CreateAgentScreenState extends ConsumerState<CreateAgentScreen> {
  final _formKey   = GlobalKey<FormState>();
  final _name      = TextEditingController();
  final _phone     = TextEditingController();
  final _email     = TextEditingController();
  final _vehicleNo = TextEditingController();
  String _vehicleType = 'two_wheeler';
  bool _submitting = false;

  // Step mode: first create agent record (step 1), then optionally link auth account (step 2)
  bool _agentCreated = false;
  String? _createdAgentId;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _vehicleNo]) c.dispose();
    super.dispose();
  }

  Future<void> _createAgentRecord() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final user = ref.read(appUserProvider).valueOrNull;
      final traderId = user?.traderId;
      if (traderId == null) throw Exception('Trader not found');

      final agent = await Supabase.instance.client.from('delivery_agents').insert({
        'trader_id':    traderId,
        'auth_user_id': null, // will be linked when agent logs in
        'name':         _name.text.trim(),
        'phone':        _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'vehicle_no':   _vehicleNo.text.trim().isEmpty ? null : _vehicleNo.text.trim(),
        'vehicle_type': _vehicleType,
        'is_active':    true,
      }).select().single();

      setState(() {
        _agentCreated   = true;
        _createdAgentId = agent['id'] as String;
      });
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _linkAuthAccount() async {
    if (_email.text.trim().isEmpty) {
      showError(context, 'Enter the agent email to link account');
      return;
    }
    setState(() => _submitting = true);
    try {
      final user = ref.read(appUserProvider).valueOrNull;
      final traderId = user?.traderId;

      // Look up the auth user by email in user_roles to see if they exist
      // The agent needs to sign up themselves OR the admin creates via Supabase dashboard
      // Here we look for an existing auth user linked to this trader
      final existingRole = await Supabase.instance.client
          .from('user_roles')
          .select('user_id')
          .eq('trader_id', traderId!)
          .eq('role', 'delivery_staff')
          .limit(50);

      // For now, create a pending link — agent will complete registration themselves
      // This is the safe approach that doesn't require service role key
      showSuccess(context,
        'Agent "${_name.text}" created!\n\n'
        'To give them app access:\n'
        '1. Ask agent to download app\n'
        '2. Their email: ${_email.text.trim()}\n'
        '3. Create their account in Supabase Auth dashboard\n'
        '4. Then link using the agent detail screen');

      if (mounted) context.go(Routes.agents);
    } catch (e) {
      if (mounted) showError(context, e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Delivery Agent')),
      body: Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.07),
                borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.primary.withOpacity(0.2))),
            child: const Row(children: [
              Icon(Icons.info_outline, color: AppTheme.primary, size: 16), SizedBox(width: 8),
              Expanded(child: Text(
                'Add the agent record here. To give them app login access, create their account in Supabase Auth dashboard and link it to this agent.',
                style: TextStyle(fontSize: 12, color: AppTheme.primary))),
            ]),
          ),

          const SectionHeader('AGENT DETAILS'),
          TextFormField(controller: _name,
            decoration: const InputDecoration(labelText: 'Full Name *', prefixIcon: Icon(Icons.person_outline, size: 18)),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
          const SizedBox(height: 12),
          TextFormField(controller: _phone, keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone Number', prefixIcon: Icon(Icons.phone_outlined, size: 18))),
          const SizedBox(height: 16),

          const SectionHeader('VEHICLE'),
          Row(children: [
            Expanded(child: TextFormField(controller: _vehicleNo,
                decoration: const InputDecoration(labelText: 'Vehicle Number'))),
            const SizedBox(width: 12),
            Expanded(child: DropdownButtonFormField<String>(
              value: _vehicleType,
              decoration: const InputDecoration(labelText: 'Type'),
              items: const [
                DropdownMenuItem(value: 'two_wheeler', child: Text('Two Wheeler')),
                DropdownMenuItem(value: 'auto',        child: Text('Auto')),
                DropdownMenuItem(value: 'mini_truck',  child: Text('Mini Truck')),
                DropdownMenuItem(value: 'truck',       child: Text('Truck')),
              ],
              onChanged: (v) => setState(() => _vehicleType = v!),
            )),
          ]),
          const SizedBox(height: 16),

          const SectionHeader('APP LOGIN (OPTIONAL)'),
          TextFormField(controller: _email, keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Agent Email (for app login)',
              prefixIcon: Icon(Icons.email_outlined, size: 18),
              helperText: 'Leave blank to add login later',
            )),
          const SizedBox(height: 28),

          ElevatedButton(
            onPressed: _submitting ? null : _createAgentRecord,
            child: _submitting
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Create Agent'),
          ),
        ]),
      ),
    );
  }
}
