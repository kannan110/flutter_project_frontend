import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class CreateRetailerScreen extends ConsumerStatefulWidget {
  const CreateRetailerScreen({super.key});
  @override ConsumerState<CreateRetailerScreen> createState() => _S();
}
class _S extends ConsumerState<CreateRetailerScreen> {
  final _c = Supabase.instance.client;
  final _form = GlobalKey<FormState>();
  final _shopName = TextEditingController();
  final _ownerName = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _creditLimit = TextEditingController(text: '100000');
  bool _submitting = false;
  @override void dispose() { _shopName.dispose(); _ownerName.dispose(); _phone.dispose(); _address.dispose(); _creditLimit.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    setState(() => _submitting = true);
    try {
      // retailers columns: trader_id, shop_name, owner_name, phone, address, credit_limit, is_active
      await _c.from('retailers').insert({
        'trader_id': tid,
        'shop_name': _shopName.text.trim(),
        'owner_name': _ownerName.text.trim().isEmpty ? null : _ownerName.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
        'credit_limit': double.tryParse(_creditLimit.text.trim()) ?? 100000,
        'is_active': true,
      });
      if (mounted) { showSuccess(context, '${_shopName.text.trim()} added ✓'); context.go(R.retailers); }
    } catch (e) { if (mounted) showError(context, e.toString()); }
    finally { if (mounted) setState(() => _submitting = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Add Retailer')),
    body: SingleChildScrollView(padding: const EdgeInsets.all(20),
      child: Form(key: _form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionHeader('SHOP DETAILS'),
        TextFormField(controller: _shopName, textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Shop Name *', prefixIcon: Icon(Icons.store_outlined, size: 20)),
            validator: (v) => v!.trim().isEmpty ? 'Required' : null),
        const SizedBox(height: 12),
        TextFormField(controller: _ownerName, textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Owner Name', prefixIcon: Icon(Icons.person_outline, size: 20))),
        const SizedBox(height: 12),
        TextFormField(controller: _phone, keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone', prefixIcon: Icon(Icons.phone_outlined, size: 20))),
        const SizedBox(height: 12),
        TextFormField(controller: _address, maxLines: 2, decoration: const InputDecoration(labelText: 'Address', alignLabelWithHint: true)),
        const SizedBox(height: 20),
        const SectionHeader('CREDIT LIMIT'),
        TextFormField(controller: _creditLimit, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Credit Limit (₹)', prefixText: '₹', helperText: 'Default ₹1,00,000')),
        const SizedBox(height: 28),
        ElevatedButton(onPressed: _submitting ? null : _save,
            child: _submitting ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Add Retailer')),
      ]))),
  );
}
