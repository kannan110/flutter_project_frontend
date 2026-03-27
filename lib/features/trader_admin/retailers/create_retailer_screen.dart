import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class CreateRetailerScreen extends ConsumerStatefulWidget {
  const CreateRetailerScreen({super.key});
  @override
  ConsumerState<CreateRetailerScreen> createState() => _CreateRetailerScreenState();
}

class _CreateRetailerScreenState extends ConsumerState<CreateRetailerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _shopName      = TextEditingController();
  final _shopNameTamil = TextEditingController();
  final _ownerName     = TextEditingController();
  final _phone         = TextEditingController();
  final _address       = TextEditingController();
  final _city          = TextEditingController();
  final _creditLimit   = TextEditingController(text: '100000');
  bool _submitting = false;

  @override
  void dispose() {
    for (final c in [_shopName, _shopNameTamil, _ownerName, _phone, _address, _city, _creditLimit]) c.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final traderId = ref.read(appUserProvider).valueOrNull?.traderId!;
      await Supabase.instance.client.from('retailers').insert({
        'trader_id':       traderId,
        'shop_name':       _shopName.text.trim(),
        'shop_name_tamil': _shopNameTamil.text.trim().isEmpty ? null : _shopNameTamil.text.trim(),
        'owner_name':      _ownerName.text.trim().isEmpty ? null : _ownerName.text.trim(),
        'phone':           _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'address':         _address.text.trim().isEmpty ? null : _address.text.trim(),
        'city':            _city.text.trim().isEmpty ? null : _city.text.trim(),
        'credit_limit':    double.tryParse(_creditLimit.text) ?? 100000,
        'approval_status': 'approved',
        'registration_mode': 'trader_created',
      });
      if (mounted) { showSuccess(context, 'Retailer added'); context.go(Routes.retailers); }
    } catch (e) {
      if (mounted) showError(context, e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Retailer')),
      body: Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const SectionHeader('SHOP DETAILS'),
          TextFormField(controller: _shopName, decoration: const InputDecoration(labelText: 'Shop Name *'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
          const SizedBox(height: 12),
          TextFormField(controller: _shopNameTamil, decoration: const InputDecoration(labelText: 'Shop Name (Tamil)')),
          const SizedBox(height: 16),
          const SectionHeader('CONTACT'),
          TextFormField(controller: _ownerName, decoration: const InputDecoration(labelText: 'Owner Name')),
          const SizedBox(height: 12),
          TextFormField(controller: _phone, keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone Number')),
          const SizedBox(height: 16),
          const SectionHeader('ADDRESS'),
          TextFormField(controller: _address, maxLines: 2,
              decoration: const InputDecoration(labelText: 'Address', alignLabelWithHint: true)),
          const SizedBox(height: 12),
          TextFormField(controller: _city, decoration: const InputDecoration(labelText: 'City')),
          const SizedBox(height: 16),
          const SectionHeader('CREDIT'),
          TextFormField(
            controller: _creditLimit,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Credit Limit (₹)', prefixIcon: Icon(Icons.currency_rupee, size: 18)),
            validator: (v) => (double.tryParse(v ?? '') == null) ? 'Enter valid amount' : null,
          ),
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Add Retailer'),
          ),
        ]),
      ),
    );
  }
}
