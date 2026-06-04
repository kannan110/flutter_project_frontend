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
  final _shopName    = TextEditingController();
  final _shopTamil   = TextEditingController();
  final _ownerName   = TextEditingController();
  final _phone       = TextEditingController();
  final _address     = TextEditingController();
  final _city        = TextEditingController();
  final _creditLimit = TextEditingController(text: '100000');

  // Opening balance — for migrating retailers from a previous system
  final _openingBalance = TextEditingController(text: '0');
  final _openingNote    = TextEditingController();
  DateTime _openingDate = DateTime.now();
  bool _showOpeningBalance = false;   // collapsed by default

  bool _submitting = false;

  @override
  void dispose() {
    _shopName.dispose(); _shopTamil.dispose(); _ownerName.dispose();
    _phone.dispose(); _address.dispose(); _city.dispose();
    _creditLimit.dispose(); _openingBalance.dispose(); _openingNote.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (mounted) setState(() => _submitting = true);
    try {
      // Step 1: Insert the retailer record
      final result = await _c.from('retailers').insert({
        'trader_id':       tid,
        'shop_name':       _shopName.text.trim(),
        'shop_name_tamil': _shopTamil.text.trim().isEmpty ? null : _shopTamil.text.trim(),
        'owner_name':      _ownerName.text.trim().isEmpty ? null : _ownerName.text.trim(),
        'phone':           _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'address':         _address.text.trim().isEmpty ? null : _address.text.trim(),
        'city':            _city.text.trim().isEmpty ? null : _city.text.trim(),
        'credit_limit':    double.tryParse(_creditLimit.text.trim()) ?? 100000,
        'is_active':       true,
      }).select('id').single();

      final retailerId = result['id'] as String;

      // Step 2: Set opening balance if provided
      final obAmount = double.tryParse(_openingBalance.text.trim()) ?? 0;
      if (_showOpeningBalance && obAmount > 0) {
        await _c.rpc('set_retailer_opening_balance', params: {
          'p_retailer_id': retailerId,
          'p_amount':      obAmount,
          'p_as_of_date':  '${_openingDate.year}-'
              '${_openingDate.month.toString().padLeft(2,'0')}-'
              '${_openingDate.day.toString().padLeft(2,'0')}',
          'p_note': _openingNote.text.trim().isEmpty
              ? 'Opening balance (migration)'
              : _openingNote.text.trim(),
        });
      }

      if (mounted) {
        showSuccess(context, '${_shopName.text.trim()} added ✓');
        if (context.canPop()) context.pop(); else context.go(R.retailers);
      }
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      backgroundColor: kBgPage,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(backgroundColor: kSurface, title: const Text('Add Retailer')),
      body: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset + 80),
          child: Form(key: _form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SectionHeader('SHOP DETAILS'),
            TextFormField(controller: _shopName, textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Shop Name (English) *', prefixIcon: Icon(Icons.store_outlined, size: 20)),
                validator: (v) => v!.trim().isEmpty ? 'Required' : null),
            const SizedBox(height: 12),
            TextFormField(controller: _shopTamil,
                decoration: const InputDecoration(labelText: 'கடை பெயர் (Tamil — optional)', prefixIcon: Icon(Icons.translate_outlined, size: 20))),
            const SizedBox(height: 12),
            TextFormField(controller: _ownerName, textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Owner Name', prefixIcon: Icon(Icons.person_outline, size: 20))),
            const SizedBox(height: 12),
            TextFormField(controller: _phone, keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone', prefixIcon: Icon(Icons.phone_outlined, size: 20))),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextFormField(controller: _address, maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Address', alignLabelWithHint: true))),
              const SizedBox(width: 12),
              Expanded(child: TextFormField(controller: _city,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'City', prefixIcon: Icon(Icons.location_city_outlined, size: 18)))),
            ]),
            const SizedBox(height: 20),
            const SectionHeader('CREDIT LIMIT'),
            TextFormField(controller: _creditLimit,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Credit Limit (₹)',
                    prefixText: '₹',
                    helperText: 'Default ₹1,00,000')),
            const SizedBox(height: 24),

            // ── Opening Balance (Migration) ─────────────────────────────
            // Collapsible — only shown when migrating from another system
            GestureDetector(
              onTap: () => setState(() => _showOpeningBalance = !_showOpeningBalance),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _showOpeningBalance
                      ? Colors.orange.shade50
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _showOpeningBalance
                        ? Colors.orange.shade300
                        : Colors.grey.shade300,
                  ),
                ),
                child: Row(children: [
                  Icon(Icons.account_balance_wallet_outlined,
                      size: 18,
                      color: _showOpeningBalance ? Colors.orange : kTextSub),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Opening Balance (Migration)',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700,
                                color: _showOpeningBalance ? Colors.orange.shade800 : kTextSub)),
                        const Text(
                            'Only use when migrating from another system',
                            style: TextStyle(fontSize: 10, color: kTextHint)),
                      ])),
                  Icon(_showOpeningBalance
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                      size: 18, color: kTextSub),
                ]),
              ),
            ),

            if (_showOpeningBalance) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Info banner
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.info_outline, size: 16, color: Colors.orange),
                      const SizedBox(width: 8),
                      const Expanded(child: Text(
                        'This adds the retailer\'s current unpaid amount '
                            'from your previous records. It will appear as '
                            '"Opening Balance" in their ledger and count toward '
                            'their outstanding amount.',
                        style: TextStyle(fontSize: 11, color: Colors.orange),
                      )),
                    ]),
                  ),

                  // Amount field
                  TextFormField(
                    controller: _openingBalance,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Outstanding Amount (₹) *',
                      prefixText: '₹',
                      helperText: 'Amount this retailer currently owes you',
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    validator: (v) {
                      if (!_showOpeningBalance) return null;
                      final n = double.tryParse(v ?? '');
                      if (n == null || n < 0) return 'Enter a valid amount';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // As-of date
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _openingDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null && mounted) {
                        setState(() => _openingDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade400),
                      ),
                      child: Row(children: [
                        const Icon(Icons.calendar_today_outlined,
                            size: 16, color: kTextSub),
                        const SizedBox(width: 10),
                        Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('As of Date',
                                  style: TextStyle(fontSize: 11, color: kTextSub)),
                              Text(
                                  '${_openingDate.day} '
                                      '${['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][_openingDate.month-1]} '
                                      '${_openingDate.year}',
                                  style: const TextStyle(
                                      fontSize: 14, fontWeight: FontWeight.w600)),
                            ])),
                        const Icon(Icons.arrow_drop_down, color: kTextSub),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Note / Reference
                  TextFormField(
                    controller: _openingNote,
                    decoration: const InputDecoration(
                      labelText: 'Note / Reference (optional)',
                      hintText: 'e.g. Balance from previous system as of Jan 2025',
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                ]),
              ),
            ],

            const SizedBox(height: 28),
            ElevatedButton(
                onPressed: _submitting ? null : _save,
                child: _submitting
                    ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Add Retailer')),
          ]))),
    );
  }
}