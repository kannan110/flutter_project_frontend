import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';

// Mirrors agent_link_screen.dart exactly in structure — same two-field
// (company code + exact name) self-link pattern, targeting
// link_supervisor_by_company_code instead of link_agent_by_company_code.
// The RPC itself also enforces the Plug & Play module flag, so a clear,
// specific error surfaces here if the trader has the module turned off —
// "login is blocked" without this screen needing its own flag check.
class SupervisorLinkScreen extends ConsumerStatefulWidget {
  const SupervisorLinkScreen({super.key});
  @override ConsumerState<SupervisorLinkScreen> createState() => _SupervisorLinkState();
}

class _SupervisorLinkState extends ConsumerState<SupervisorLinkScreen> {
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _c        = Supabase.instance.client;

  bool _linking = false, _checking = false;
  String? _err, _traderName;

  @override void dispose() { _codeCtrl.dispose(); _nameCtrl.dispose(); super.dispose(); }

  bool   get _isSignedIn => _c.auth.currentUser != null;

  Future<void> _checkCode() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) { if (mounted) setState(() => _err = 'Enter company code'); return; }
    if (mounted) setState(() { _checking = true; _traderName = null; _err = null; });
    try {
      final res = await _c.rpc('get_trader_by_code', params: {'p_company_code': code});
      if (!mounted) return;
      if (res != null && res is Map && res['found'] == true) {
        setState(() { _traderName = res['company_name'] as String? ?? 'Found'; _checking = false; });
      } else {
        setState(() { _err = 'Code "$code" not found. Ask your trader for the correct code.'; _checking = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _err = 'Network error. Try again.'; _checking = false; });
    }
  }

  Future<void> _link() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    final name = _nameCtrl.text.trim();

    if (!_isSignedIn) { if (mounted) setState(() => _err = 'Not signed in. Go back and sign in first.'); return; }
    if (code.isEmpty) { if (mounted) setState(() => _err = 'Enter company code'); return; }
    if (name.isEmpty) { if (mounted) setState(() => _err = 'Enter your name exactly as your trader typed it'); return; }

    if (_traderName == null) {
      await _checkCode();
      if (_traderName == null) return;
    }

    if (mounted) setState(() { _linking = true; _err = null; });
    try {
      await _c.rpc('link_supervisor_by_company_code', params: {
        'p_company_code':     code,
        'p_supervisor_name':  name,
        'p_user_id':          _c.auth.currentUser!.id,
      });

      if (!mounted) return;
      await ref.read(appUserProvider.notifier).reload();

      if (mounted) {
        showSuccess(context, 'Account linked! Welcome ✓');
        context.go(R.supervisorHome);
      }
    } catch (e) {
      if (!mounted) return;
      String raw = e.toString()
          .replaceAll('Exception: ', '')
          .replaceAll('PostgrestException(message: ', '')
          .replaceAll(')', '');

      String msg;
      if (raw.contains('No unlinked supervisor')) {
        final available = raw.contains('Available names:')
            ? raw.split('Available names:').last.trim() : '';
        msg = 'Name "$name" not matched.\n\n'
            'Names available to link: ${available.isEmpty ? "none (ask your trader)" : available}\n\n'
            'Enter the exact name your trader used.';
      } else if (raw.contains('not enabled')) {
        msg = 'The Supervisor module is not enabled for this account yet. Ask your trader to contact support.';
      } else if (raw.contains('Company code') || raw.contains('not found')) {
        msg = 'Company code "$code" not found.';
      } else if (raw.contains('already linked') || raw.contains('already exists')) {
        msg = 'This account is already linked. Try signing in normally.';
      } else {
        msg = raw;
      }
      if (mounted) setState(() { _err = msg; _linking = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authUser = _c.auth.currentUser;
    final signedIn = authUser != null;

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(backgroundColor: kSurface, title: const Text('Link Supervisor Account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!signedIn) Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: kErrorBg, borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(color: kError.withValues(alpha: 0.3))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.error_outline, color: kError, size: 20),
                  SizedBox(width: 8),
                  Expanded(child: Text('Not signed in!',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kError))),
                ]),
                const SizedBox(height: 8),
                const Text('You must sign up or sign in first, then come back here to link.',
                    style: TextStyle(fontSize: 12, color: kError, height: 1.5)),
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: ElevatedButton.icon(
                    onPressed: () => context.go(R.login),
                    icon: const Icon(Icons.login, size: 18),
                    label: const Text('Go to Sign Up / Sign In'),
                    style: ElevatedButton.styleFrom(backgroundColor: kError))),
              ])),

          if (_err != null) Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: kErrorBg, borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(color: kError.withValues(alpha: 0.3))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.error_outline, color: kError, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(_err!, style: const TextStyle(color: kError, fontSize: 13, height: 1.5))),
                GestureDetector(onTap: () => setState(() => _err = null),
                    child: const Icon(Icons.close, color: kError, size: 18)),
              ])),

          const Text('COMPANY CODE',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kTextHint, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: TextField(
              controller: _codeCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                  hintText: 'e.g. RT001',
                  prefixIcon: const Icon(Icons.business_outlined, size: 18, color: kPrimary),
                  suffixIcon: _traderName != null
                      ? const Icon(Icons.check_circle, color: Colors.green, size: 20) : null),
              onChanged: (_) { if (mounted) setState(() { _traderName = null; _err = null; }); },
            )),
            const SizedBox(width: 8),
            SizedBox(height: 52, width: 100, child: ElevatedButton(
              onPressed: _checking || _codeCtrl.text.trim().isEmpty ? null : _checkCode,
              child: _checking
                  ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Verify'),
            )),
          ]),
          if (_traderName != null) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: kSuccess.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(kRadiusCard),
                      border: Border.all(color: kSuccess.withValues(alpha: 0.25))),
                  child: Row(children: [
                    Icon(Icons.check_circle, color: Colors.green.shade600, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text('✓ Found: $_traderName',
                        style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w700, fontSize: 13))),
                  ]))),
          const SizedBox(height: 16),

          const Text('YOUR NAME (as your trader typed it)',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kTextHint, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                hintText: 'Enter your exact name',
                prefixIcon: Icon(Icons.person_outline, size: 20, color: kPrimary)),
            onChanged: (_) { if (mounted) setState(() => _err = null); },
          ),
          const SizedBox(height: 6),
          Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.25))),
              child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 16),
                SizedBox(width: 8),
                Expanded(child: Text(
                    'Spelling must match EXACTLY what your trader entered — including capitals.',
                    style: TextStyle(fontSize: 12, color: Colors.orange, height: 1.4))),
              ])),
          const SizedBox(height: 24),

          SizedBox(height: 52, child: ElevatedButton.icon(
            onPressed: _linking ? null : _link,
            icon: _linking
                ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.link, size: 20),
            label: const Text('Link My Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          )),
          const SizedBox(height: 12),
          Center(child: TextButton(
              onPressed: () => context.go(R.login),
              child: const Text('← Back to Login', style: TextStyle(color: kTextSub)))),
          const SizedBox(height: 30),
        ]),
      ),
    );
  }
}