import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class RetailerDetailScreen extends ConsumerStatefulWidget {
  const RetailerDetailScreen({super.key, required this.id});
  final String id;
  @override ConsumerState<RetailerDetailScreen> createState() => _S();
}

class _S extends ConsumerState<RetailerDetailScreen> {
  final _c = Supabase.instance.client;
  Map<String,dynamic>? _r;
  bool _loading = true, _editing = false, _saving = false;

  // Edit controllers
  late TextEditingController _shopNameCtrl;
  late TextEditingController _ownerCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _creditCtrl;

  @override void initState() { super.initState(); _load(); }
  @override void dispose() {
    _shopNameCtrl.dispose(); _ownerCtrl.dispose();
    _phoneCtrl.dispose(); _addressCtrl.dispose(); _creditCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final r = await _c.from('retailers').select('*').eq('id', widget.id).maybeSingle();
      if (mounted) {
        _shopNameCtrl = TextEditingController(text: r?['shop_name'] as String? ?? '');
        _ownerCtrl    = TextEditingController(text: r?['owner_name'] as String? ?? '');
        _phoneCtrl    = TextEditingController(text: r?['phone'] as String? ?? '');
        _addressCtrl  = TextEditingController(text: r?['address'] as String? ?? '');
        _creditCtrl   = TextEditingController(text: '${(r?['credit_limit'] as num?)?.toInt() ?? 100000}');
        setState(() { _r = r; _loading = false; });
      }
    } catch (e) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _save() async {
    if (_shopNameCtrl.text.trim().isEmpty) { showError(context, 'Shop name required'); return; }
    if (mounted) setState(() => _saving = true);
    try {
      await _c.from('retailers').update({
        'shop_name':    _shopNameCtrl.text.trim(),
        'owner_name':   _ownerCtrl.text.trim().isEmpty ? null : _ownerCtrl.text.trim(),
        'phone':        _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        'address':      _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        'credit_limit': double.tryParse(_creditCtrl.text.trim()) ?? 100000,
      }).eq('id', widget.id);
      if (mounted) {
        showSuccess(context, 'Customer updated ✓');
        setState(() => _editing = false);
        _load();
      }
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    } finally { if (mounted) setState(() => _saving = false); }
  }

  Future<void> _toggleActive() async {
    final isActive = _r?['is_active'] as bool? ?? true;
    final ok = await confirmDialog(context,
        title: isActive ? 'Deactivate Customer' : 'Activate Customer',
        message: isActive
            ? 'This will hide ${_r?['shop_name']} from new orders.'
            : 'Reactivate ${_r?['shop_name']}?',
        confirmText: isActive ? 'Deactivate' : 'Activate',
        confirmColor: isActive ? Colors.red : kPrimary);
    if (!ok) return;
    try {
      await _c.from('retailers').update({'is_active': !isActive}).eq('id', widget.id);
      if (mounted) { showSuccess(context, isActive ? 'Deactivated' : 'Activated'); _load(); }
    } catch (e) { if (mounted) showError(context, e.toString()); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingList());
    if (_r == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Not found')));
    final r        = _r!;
    final isActive = r['is_active'] as bool? ?? true;

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit Customer' : (r['shop_name'] as String)),
        actions: [
          if (!_editing) ...[
            TextButton.icon(
              onPressed: () => setState(() => _editing = true),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit')),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          ] else ...[
            TextButton(
              onPressed: () => setState(() => _editing = false),
              child: const Text('Cancel', style: TextStyle(color: Colors.red))),
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save', style: TextStyle(fontWeight: FontWeight.w700))),
          ],
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [

        // Status badge
        if (!isActive) Container(
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade200)),
          child: const Row(children: [
            Icon(Icons.block, color: Colors.red, size: 16), SizedBox(width: 8),
            Text('This customer is deactivated', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 13)),
          ])),

        if (_editing) ...[
          // EDIT MODE
          const SectionHeader('SHOP DETAILS'),
          TextField(controller: _shopNameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Shop Name *')),
          const SizedBox(height: 10),
          TextField(controller: _ownerCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Owner Name')),
          const SizedBox(height: 10),
          TextField(controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone', prefixIcon: Icon(Icons.phone_outlined, size: 18))),
          const SizedBox(height: 10),
          TextField(controller: _addressCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Address', alignLabelWithHint: true)),
          const SizedBox(height: 16),
          const SectionHeader('CREDIT LIMIT'),
          TextField(controller: _creditCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Credit Limit (₹)', prefixText: '₹',
                  helperText: 'Maximum credit allowed for this customer')),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Text('Save Changes')),
        ] else ...[
          // VIEW MODE
          WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionHeader('CUSTOMER DETAILS'),
            InfoRow('Shop',         r['shop_name'] as String),
            if (r['owner_name'] != null) InfoRow('Owner', r['owner_name'] as String),
            if (r['phone'] != null) InfoRow('Phone', r['phone'] as String),
            if (r['address'] != null) InfoRow('Address', r['address'] as String),
            InfoRow('Status',       isActive ? 'Active' : 'Inactive',
                valueColor: isActive ? kPrimary : Colors.red),
            InfoRow('Credit Limit', Fmt.amount((r['credit_limit'] as num?)?.toDouble() ?? 0)),
            InfoRow('Risk Level',   (r['risk_level'] as String? ?? 'low').toUpperCase()),
          ])),
          const SizedBox(height: 16),

          // Quick actions
          ElevatedButton.icon(
            onPressed: () => context.push(R.retailerLedgerPath(widget.id)),
            icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
            label: const Text('View Ledger & Outstanding')),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => context.go(R.orderCreate),
            icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
            label: const Text('New Order')),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _toggleActive,
            icon: Icon(isActive ? Icons.block : Icons.check_circle_outline, size: 18),
            label: Text(isActive ? 'Deactivate Customer' : 'Reactivate Customer'),
            style: OutlinedButton.styleFrom(
                foregroundColor: isActive ? Colors.red : kPrimary,
                side: BorderSide(color: isActive ? Colors.red : kPrimary))),
        ],
        const SizedBox(height: 20),
      ]),
    );
  }
}
