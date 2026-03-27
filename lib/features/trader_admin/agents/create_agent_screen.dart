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
  final _password  = TextEditingController();
  final _vehicleNo = TextEditingController();
  String _vehicleType = 'two_wheeler';
  bool _submitting = false;
  bool _obscure = true;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _password, _vehicleNo]) c.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final traderId = ref.read(appUserProvider).valueOrNull?.traderId!;

      // 1. Create auth user
      final res = await Supabase.instance.client.auth.admin.createUser(
        AdminUserAttributes(
          email: _email.text.trim(),
          password: _password.text,
          emailConfirm: true,
        ),
      );
      final authUserId = res.user?.id;
      if (authUserId == null) throw Exception('Failed to create user account');

      // 2. Insert delivery_agents row
      final agent = await Supabase.instance.client.from('delivery_agents').insert({
        'trader_id':    traderId,
        'auth_user_id': authUserId,
        'name':         _name.text.trim(),
        'phone':        _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'vehicle_no':   _vehicleNo.text.trim().isEmpty ? null : _vehicleNo.text.trim(),
        'vehicle_type': _vehicleType,
        'is_active':    true,
      }).select().single();

      // 3. Insert user_role
      await Supabase.instance.client.from('user_roles').insert({
        'user_id':   authUserId,
        'trader_id': traderId,
        'role':      'delivery_staff',
        'is_active': true,
      });

      if (mounted) {
        showSuccess(context, 'Agent ${_name.text.trim()} created. Login: ${_email.text.trim()}');
        context.go(Routes.agents);
      }
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
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
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.07),
                borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.primary.withOpacity(0.2))),
            child: const Row(children: [
              Icon(Icons.info_outline, color: AppTheme.primary, size: 16),
              SizedBox(width: 8),
              Expanded(child: Text('This will create a login account for the agent. Share the email & password with them.',
                  style: TextStyle(fontSize: 12, color: AppTheme.primary))),
            ]),
          ),
          const SectionHeader('AGENT DETAILS'),
          TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Full Name *'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
          const SizedBox(height: 12),
          TextFormField(controller: _phone, keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone Number')),
          const SizedBox(height: 16),
          const SectionHeader('VEHICLE'),
          TextFormField(controller: _vehicleNo, decoration: const InputDecoration(labelText: 'Vehicle Number')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _vehicleType,
            decoration: const InputDecoration(labelText: 'Vehicle Type'),
            items: const [
              DropdownMenuItem(value: 'two_wheeler',  child: Text('Two Wheeler')),
              DropdownMenuItem(value: 'auto',         child: Text('Auto')),
              DropdownMenuItem(value: 'mini_truck',   child: Text('Mini Truck')),
              DropdownMenuItem(value: 'truck',        child: Text('Truck')),
            ],
            onChanged: (v) => setState(() => _vehicleType = v!),
          ),
          const SizedBox(height: 16),
          const SectionHeader('LOGIN CREDENTIALS'),
          TextFormField(controller: _email, keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email Address *'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
          const SizedBox(height: 12),
          TextFormField(
            controller: _password, obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Password *',
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
          ),
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Create Agent'),
          ),
        ]),
      ),
    );
  }
}
