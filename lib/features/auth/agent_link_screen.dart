import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';

// ─── FIX 1: Changed to ConsumerStatefulWidget so we can watch appUserProvider
//            and reload session after linking (blank screen bug was caused by
//            StatefulWidget not triggering session reload after RPC).
class AgentLinkScreen extends ConsumerStatefulWidget {
  const AgentLinkScreen({super.key});
  @override ConsumerState<AgentLinkScreen> createState() => _AgentLinkState();
}

class _AgentLinkState extends ConsumerState<AgentLinkScreen> {
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _c = Supabase.instance.client;
  bool _linking = false, _checking = false;
  String? _err, _traderName;
  String? _traderId; // FIX 2: store found trader_id from check step

  @override void dispose() { _codeCtrl.dispose(); _nameCtrl.dispose(); super.dispose(); }

  bool   get _isSignedIn => _c.auth.currentUser != null;
  String get _email      => _c.auth.currentUser?.email ?? '';

  Future<void> _checkCode() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) { if (mounted) setState(() => _err = 'Enter company code'); return; }
    if (mounted) setState(() { _checking = true; _traderName = null; _traderId = null; _err = null; });
    try {
      final res = await _c.rpc('get_trader_by_code', params: {'p_company_code': code});
      if (!mounted) return;
      // FIX 3: handle both Map result and null gracefully
      if (res != null && res is Map && res['found'] == true) {
        if (mounted) setState(() {
          _traderName = res['company_name'] as String? ?? 'Found';
          _traderId   = res['trader_id']   as String?;
          _checking   = false;
        });
      } else {
        if (mounted) setState(() {
          _err = 'Code "$code" not found. Ask your trader admin.';
          _checking = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _err = 'Network error. Check connection and try again.';
        _checking = false;
      });
    }
  }

  Future<void> _link() async {
    if (!_isSignedIn) {
      if (mounted) setState(() => _err = 'Not signed in. Go back → Sign In first.');
      return;
    }
    final code = _codeCtrl.text.trim().toUpperCase();
    final name = _nameCtrl.text.trim();
    if (code.isEmpty) { if (mounted) setState(() => _err = 'Enter company code'); return; }
    if (name.isEmpty) { if (mounted) setState(() => _err = 'Enter your name'); return; }

    // FIX 4: require code verification before linking
    if (_traderName == null) {
      await _checkCode();
      if (_traderName == null) return; // check failed
    }

    if (mounted) setState(() { _linking = true; _err = null; });
    try {
      await _c.rpc('link_agent_by_company_code', params: {
        'p_company_code': code,
        'p_agent_name':   name,
        'p_user_id':      _c.auth.currentUser!.id,
      });

      if (!mounted) return;

      // FIX 5: CRITICAL — reload session so appUserProvider gets the new
      // delivery_staff role + agentId. Without this the app stayed blank.
      await ref.read(appUserProvider.notifier).reload();

      if (mounted) {
        showSuccess(context, 'Account linked! Welcome to Rooster Trader ✓');
        // FIX 6: navigate after session reload, not before
        context.go(R.agentHome);
      }
    } catch (e) {
      if (!mounted) return;
      String msg = e.toString()
          .replaceAll('Exception: ', '')
          .replaceAll('PostgrestException(message: ', '')
          .replaceAll(')', '');
      if (msg.contains('No pending agent') || msg.contains('not found') || msg.contains('name')) {
        msg = 'Name not matched.\n\n'
            'You entered: "$name"\n\n'
            'Ask your admin what name they entered — must match exactly (including capital letters).';
      } else if (msg.contains('already linked') || msg.contains('already exists')) {
        msg = 'This account is already linked. Try signing in normally.';
      } else if (msg.contains('Company code')) {
        msg = 'Company code "$code" not found. Ask admin for the correct code.';
      }
      if (mounted) setState(() { _err = msg; _linking = false; });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Link Agent Account')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

        // ── Info banner ───────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade200)),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('One-time account setup', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.blue)),
            SizedBox(height: 6),
            Text(
              '1. Admin adds your name in Agents screen\n'
              '2. Sign Up with your email (once only)\n'
              '3. Get Company Code from your admin\n'
              '4. Enter code + your exact name below\n'
              '5. After linking, just Sign In every day',
              style: TextStyle(fontSize: 12, color: Colors.blue, height: 1.7)),
          ]),
        ),
        const SizedBox(height: 16),

        // ── Sign-in status ────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _isSignedIn ? Colors.green.shade50 : Colors.orange.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _isSignedIn ? Colors.green.shade300 : Colors.orange.shade300)),
          child: Row(children: [
            Icon(_isSignedIn ? Icons.check_circle_outline : Icons.warning_amber_outlined,
                color: _isSignedIn ? Colors.green.shade600 : Colors.orange.shade700, size: 20),
            const SizedBox(width: 10),
            Expanded(child: _isSignedIn
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Signed in as:', style: TextStyle(fontSize: 11, color: Colors.green)),
                    Text(_email, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.green)),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Not signed in!', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.orange)),
                    const Text('Tap Sign In below, then come back here.', style: TextStyle(fontSize: 11, color: Colors.orange)),
                  ])),
            if (!_isSignedIn)
              TextButton(
                onPressed: () => context.go(R.login),
                child: const Text('Sign In →')),
          ]),
        ),
        const SizedBox(height: 16),

        // ── Error banner ──────────────────────────────────────────
        if (_err != null) Container(
          padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3F3),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.red.shade200)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.error_outline, color: kError, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(_err!, style: const TextStyle(color: kError, fontSize: 13, height: 1.5))),
          ]),
        ),

        // ── Company Code ──────────────────────────────────────────
        const Text('COMPANY CODE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kTextHint, letterSpacing: 0.5)),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: TextField(
            controller: _codeCtrl,
            enabled: _isSignedIn,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: 'e.g. RT001',
              prefixIcon: Icon(Icons.business_outlined, size: 18, color: kPrimary)),
            onChanged: (_) { if (mounted) setState(() { _traderName = null; _traderId = null; _err = null; }); },
          )),
          const SizedBox(width: 8),
          SizedBox(height: 52, child: ElevatedButton(
            onPressed: (!_isSignedIn || _checking || _codeCtrl.text.trim().isEmpty) ? null : _checkCode,
            child: _checking
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Verify'),
          )),
        ]),

        // Code verified indicator
        if (_traderName != null) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade200)),
            child: Row(children: [
              Icon(Icons.check_circle, color: Colors.green.shade600, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text('✓ Trader found: $_traderName',
                  style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w700, fontSize: 13))),
            ]),
          ),
        ),
        const SizedBox(height: 16),

        // ── Agent Name ────────────────────────────────────────────
        const Text('YOUR NAME', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kTextHint, letterSpacing: 0.5)),
        const SizedBox(height: 6),
        TextField(
          controller: _nameCtrl,
          enabled: _isSignedIn,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Enter name exactly as admin typed it',
            prefixIcon: Icon(Icons.person_outline, size: 20, color: kPrimary)),
          onChanged: (_) { if (mounted) setState(() => _err = null); },
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.shade200)),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 16),
            SizedBox(width: 8),
            Expanded(child: Text(
              'Spelling and capitalisation must match exactly what admin entered in the Agents screen.',
              style: TextStyle(fontSize: 12, color: Colors.orange, height: 1.4))),
          ]),
        ),
        const SizedBox(height: 24),

        // ── Link Button ───────────────────────────────────────────
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: (!_isSignedIn || _linking) ? null : _link,
            icon: _linking
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.link, size: 20),
            label: Text(
              _isSignedIn ? 'Link My Account' : 'Sign In First',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 12),
        Center(child: TextButton(
          onPressed: () => context.go(R.login),
          child: const Text('← Back to Login', style: TextStyle(color: kTextSub)),
        )),
        const SizedBox(height: 30),
      ]),
    ),
  );
}
