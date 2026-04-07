import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/providers/session_provider.dart';
import '../../core/theme/app_theme.dart';

/// Shown when a user is signed in but not yet linked to any trader company.
/// They can create a new company or join an existing one.
class TraderSetupScreen extends ConsumerStatefulWidget {
  const TraderSetupScreen({super.key});
  @override ConsumerState<TraderSetupScreen> createState() => _S();
}

class _S extends ConsumerState<TraderSetupScreen> {
  final _coName   = TextEditingController();
  final _coCode   = TextEditingController();
  final _coPhone  = TextEditingController();
  final _coCity   = TextEditingController();
  final _coPerson = TextEditingController();
  final _joinCode = TextEditingController();

  bool _busy     = false;
  bool _createNew = true;
  String? _err;

  @override void dispose() {
    _coName.dispose(); _coCode.dispose(); _coPhone.dispose();
    _coCity.dispose(); _coPerson.dispose(); _joinCode.dispose();
    super.dispose();
  }

  Future<void> _createTrader() async {
    final name = _coName.text.trim();
    final code = _coCode.text.trim().toUpperCase();
    if (name.isEmpty) { setState(() => _err = 'Enter company name'); return; }
    if (code.length < 3) { setState(() => _err = 'Code must be at least 3 characters'); return; }
    setState(() { _busy = true; _err = null; });
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      await Supabase.instance.client.rpc('register_new_trader', params: {
        'p_user_id':        userId,
        'p_company_name':   name,
        'p_company_code':   code,
        'p_contact_person': _coPerson.text.trim().isEmpty ? null : _coPerson.text.trim(),
        'p_phone':          _coPhone.text.trim().isEmpty  ? null : _coPhone.text.trim(),
        'p_city':           _coCity.text.trim().isEmpty   ? null : _coCity.text.trim(),
      });
      if (mounted) {
        showSuccess(context, '✅ "$name" created! Loading dashboard...');
        await ref.read(appUserProvider.notifier).reload();
      }
    } catch (e) {
      if (mounted) setState(() {
        _err = e.toString().replaceAll('Exception: ', '').replaceAll('PostgrestException(message: ', '').replaceAll(')', '');
        _busy = false;
      });
    }
  }

  Future<void> _joinTrader() async {
    final code = _joinCode.text.trim().toUpperCase();
    if (code.isEmpty) { setState(() => _err = 'Enter company code'); return; }
    setState(() { _busy = true; _err = null; });
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      final res = await Supabase.instance.client.rpc('join_trader_as_admin', params: {
        'p_user_id': userId, 'p_company_code': code,
      });
      final result = res as Map<String,dynamic>;
      if (mounted) {
        showSuccess(context, '✅ Joined "${result['company_name']}"! Loading dashboard...');
        await ref.read(appUserProvider.notifier).reload();
      }
    } catch (e) {
      if (mounted) setState(() {
        _err = e.toString().replaceAll('Exception: ', '').replaceAll('PostgrestException(message: ', '').replaceAll(')', '');
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kBgGrey,
    appBar: AppBar(
      title: const Text('Company Setup'),
      actions: [TextButton(
        onPressed: () async {
          await ref.read(appUserProvider.notifier).signOut();
        },
        child: const Text('Sign Out', style: TextStyle(color: kError)))],
    ),
    body: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(children: [
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: kPrimary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kPrimary.withValues(alpha: 0.2))),
        child: const Column(children: [
          Icon(Icons.business_outlined, size: 40, color: kPrimary),
          SizedBox(height: 8),
          Text('Almost there!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          SizedBox(height: 4),
          Text('Your account is ready. Now set up your trading company.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: kTextSub)),
        ])),
      const SizedBox(height: 20),

      // Toggle
      Row(children: [
        Expanded(child: GestureDetector(
          onTap: () => setState(() { _createNew = true; _err = null; }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
                color: _createNew ? kPrimary : Colors.grey.shade100,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(10))),
            child: Column(children: [
              Icon(Icons.add_business_outlined, color: _createNew ? Colors.white : kTextSub),
              const SizedBox(height: 4),
              Text('New Company', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                  color: _createNew ? Colors.white : kTextSub)),
            ])))),
        Expanded(child: GestureDetector(
          onTap: () => setState(() { _createNew = false; _err = null; }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
                color: !_createNew ? kPrimary : Colors.grey.shade100,
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(10))),
            child: Column(children: [
              Icon(Icons.group_add_outlined, color: !_createNew ? Colors.white : kTextSub),
              const SizedBox(height: 4),
              Text('Join Existing', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                  color: !_createNew ? Colors.white : kTextSub)),
            ])))),
      ]),
      const SizedBox(height: 20),

      if (_err != null) Container(
        width: double.infinity, margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
        child: Text(_err!, style: const TextStyle(color: kError, fontSize: 13))),

      if (_createNew) ...[
        TextFormField(controller: _coName, textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Company Name *',
                prefixIcon: Icon(Icons.business_outlined, size: 18, color: kPrimary))),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextFormField(controller: _coCode,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Company Code *',
                  hintText: 'e.g. TC001',
                  prefixIcon: Icon(Icons.tag, size: 18, color: kPrimary)),
              onChanged: (v) {
                final u = v.toUpperCase().replaceAll(' ', '');
                if (v != u) _coCode.value = TextEditingValue(
                    text: u, selection: TextSelection.collapsed(offset: u.length));
              })),
          const SizedBox(width: 10),
          Expanded(child: TextFormField(controller: _coPhone, keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone',
                  prefixIcon: Icon(Icons.phone_outlined, size: 18, color: kPrimary)))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextFormField(controller: _coPerson,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Contact Person',
                  prefixIcon: Icon(Icons.person_outline, size: 18, color: kPrimary)))),
          const SizedBox(width: 10),
          Expanded(child: TextFormField(controller: _coCity,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'City',
                  prefixIcon: Icon(Icons.location_city_outlined, size: 18, color: kPrimary)))),
        ]),
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, height: 50,
          child: ElevatedButton.icon(
            onPressed: _busy ? null : _createTrader,
            icon: _busy
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.add_business),
            label: const Text('Create Company', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))),
      ] else ...[
        Container(padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
            child: const Text('Get the Company Code from the existing admin and enter it below.',
                style: TextStyle(fontSize: 12, color: Colors.blue))),
        const SizedBox(height: 14),
        TextFormField(controller: _joinCode, textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Company Code *',
                hintText: 'e.g. TC001',
                prefixIcon: Icon(Icons.tag, size: 18, color: kPrimary)),
            onChanged: (v) {
              final u = v.toUpperCase().replaceAll(' ', '');
              if (v != u) _joinCode.value = TextEditingValue(
                  text: u, selection: TextSelection.collapsed(offset: u.length));
            }),
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, height: 50,
          child: ElevatedButton.icon(
            onPressed: _busy ? null : _joinTrader,
            icon: _busy
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.group_add),
            label: const Text('Join Company', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))),
      ],
    ])),
  );
}
