import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/responsive_layout.dart';

class CreateRetailerScreen extends ConsumerStatefulWidget {
  const CreateRetailerScreen({super.key});
  @override ConsumerState<CreateRetailerScreen> createState() => _S();
}
class _S extends ConsumerState<CreateRetailerScreen> {
  final _c = Supabase.instance.client;
  final _form = GlobalKey<FormState>();
  final _shopName   = TextEditingController();
  final _shopTamil  = TextEditingController();
  final _ownerName  = TextEditingController();
  final _phone      = TextEditingController();
  final _address    = TextEditingController();
  final _city       = TextEditingController();
  final _creditLimit = TextEditingController(text: '100000');
  bool _submitting = false;
  @override void dispose() {
    _shopName.dispose(); _shopTamil.dispose(); _ownerName.dispose();
    _phone.dispose(); _address.dispose(); _city.dispose(); _creditLimit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (mounted) setState(() => _submitting = true);
    try {
      // retailers columns: trader_id, shop_name, owner_name, phone, address, credit_limit, is_active
      await _c.from('retailers').insert({
        'trader_id':       tid,
        'shop_name':       _shopName.text.trim(),
        'shop_name_tamil': _shopTamil.text.trim().isEmpty ? null : _shopTamil.text.trim(),
        'owner_name':      _ownerName.text.trim().isEmpty ? null : _ownerName.text.trim(),
        'phone':           _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'address':         _address.text.trim().isEmpty ? null : _address.text.trim(),
        'city':            _city.text.trim().isEmpty ? null : _city.text.trim(),
        'credit_limit':    double.tryParse(_creditLimit.text.trim()) ?? 100000,
        'is_active':       true,
      });
      if (mounted) { showSuccess(context, '${_shopName.text.trim()} added ✓'); if (context.canPop()) context.pop(); else context.go(R.retailers); }
    } catch (e) { if (mounted) showError(context, e.toString()); }
    finally { if (mounted) setState(() => _submitting = false); }
  }

  // ── Shared form fields widget ─────────────────────────────────────────────
  Widget _buildFormFields() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    const SectionHeader('SHOP DETAILS'),
    TextFormField(controller: _shopName, textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Shop Name (English) *', prefixIcon: Icon(Icons.store_outlined, size: 20)),
        validator: (v) => v!.trim().isEmpty ? 'Required' : null,
        onChanged: (_) => setState(() {})),
    const SizedBox(height: 12),
    TextFormField(controller: _shopTamil,
        decoration: const InputDecoration(labelText: 'கடை பெயர் (Tamil — optional)', prefixIcon: Icon(Icons.translate_outlined, size: 20)),
        onChanged: (_) => setState(() {})),
    const SizedBox(height: 12),
    TextFormField(controller: _ownerName, textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Owner Name', prefixIcon: Icon(Icons.person_outline, size: 20)),
        onChanged: (_) => setState(() {})),
    const SizedBox(height: 12),
    TextFormField(controller: _phone, keyboardType: TextInputType.phone,
        decoration: const InputDecoration(labelText: 'Phone', prefixIcon: Icon(Icons.phone_outlined, size: 20)),
        onChanged: (_) => setState(() {})),
    const SizedBox(height: 12),
    Row(children: [
      Expanded(child: TextFormField(controller: _address, maxLines: 2,
          decoration: const InputDecoration(labelText: 'Address', alignLabelWithHint: true),
          onChanged: (_) => setState(() {}))),
      const SizedBox(width: 12),
      Expanded(child: TextFormField(controller: _city,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'City', prefixIcon: Icon(Icons.location_city_outlined, size: 18)),
          onChanged: (_) => setState(() {}))),
    ]),
    const SizedBox(height: 20),
    const SectionHeader('CREDIT LIMIT'),
    TextFormField(controller: _creditLimit, keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Credit Limit (₹)', prefixText: '₹', helperText: 'Default ₹1,00,000')),
  ]);

  @override
  Widget build(BuildContext context) {
    final isDesktop = context.isDesktop;

    if (!isDesktop) {
      return Scaffold(
        backgroundColor: kBgPage,
        appBar: AppBar(backgroundColor: kSurface, title: const Text('Add Retailer')),
        body: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20,20,20,40),
            child: Form(key: _form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _buildFormFields(),
              const SizedBox(height: 28),
              ElevatedButton(onPressed: _submitting ? null : _save,
                  child: _submitting ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Add Retailer')),
            ]))),
      );
    }

    // ── Desktop 2-column ──────────────────────────────────────────────────
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: const Text('Add Retailer'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go(R.retailers),
        ),
      ),
      body: Form(
        key: _form,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Left: form ────────────────────────────────────────────────
          Expanded(
            flex: 6,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 24, 16, 40),
              child: _buildFormFields(),
            ),
          ),
          Container(width: 1, color: kBorderLight),
          // ── Right: preview + submit ───────────────────────────────────
          SizedBox(
            width: 300,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 24, 40),
              children: [
                const Text('PREVIEW', style: TextStyle(fontSize: 11,
                    fontWeight: FontWeight.w800, color: kNavy, letterSpacing: 0.8)),
                const SizedBox(height: 12),
                // Preview card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: kSurface,
                      borderRadius: BorderRadius.circular(kRadiusCard),
                      border: Border.all(color: kBorderLight)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(width: 40, height: 40,
                          decoration: BoxDecoration(color: kNavy.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10)),
                          child: Center(child: Text(
                              _shopName.text.isNotEmpty
                                  ? _shopName.text.trim()[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: kNavy)))),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                            _shopName.text.trim().isEmpty ? 'Shop Name' : _shopName.text.trim(),
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                                color: _shopName.text.isEmpty ? kTextHint : kNavy),
                            overflow: TextOverflow.ellipsis),
                        if (_shopTamil.text.isNotEmpty)
                          Text(_shopTamil.text, style: const TextStyle(fontSize: 12, color: kTextSub)),
                      ])),
                    ]),
                    if (_ownerName.text.isNotEmpty) ...[ const SizedBox(height: 8),
                      Row(children: [
                        const Icon(Icons.person_outline, size: 14, color: kTextHint),
                        const SizedBox(width: 6),
                        Expanded(child: Text(_ownerName.text, style: const TextStyle(fontSize: 12, color: kTextSub))),
                      ])],
                    if (_phone.text.isNotEmpty) ...[ const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.phone_outlined, size: 14, color: kTextHint),
                        const SizedBox(width: 6),
                        Text(_phone.text, style: const TextStyle(fontSize: 12, color: kTextSub)),
                      ])],
                    if (_address.text.isNotEmpty || _city.text.isNotEmpty) ...[ const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.location_on_outlined, size: 14, color: kTextHint),
                        const SizedBox(width: 6),
                        Expanded(child: Text(
                            [_address.text.trim(), _city.text.trim()].where((s) => s.isNotEmpty).join(', '),
                            style: const TextStyle(fontSize: 12, color: kTextSub))),
                      ])],
                    const SizedBox(height: 12),
                    Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.green.shade200)),
                        child: Row(children: [
                          const Icon(Icons.account_balance_wallet_outlined, size: 14, color: Colors.green),
                          const SizedBox(width: 6),
                          Text('Credit limit: ₹${_creditLimit.text.isEmpty ? "1,00,000" : _creditLimit.text}',
                              style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600)),
                        ])),
                  ]),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                    onPressed: _submitting ? null : _save,
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                    child: _submitting
                        ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Add Retailer',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}