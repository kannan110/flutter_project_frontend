import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';

class AgentLinkScreen extends StatefulWidget {
  const AgentLinkScreen({super.key});
  @override State<AgentLinkScreen> createState() => _AgentLinkState();
}

class _AgentLinkState extends State<AgentLinkScreen> {
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _c = Supabase.instance.client;
  bool _linking = false, _checking = false;
  String? _err, _traderName;

  @override void dispose() { _codeCtrl.dispose(); _nameCtrl.dispose(); super.dispose(); }

  bool get _isSignedIn => _c.auth.currentUser != null;
  String get _email    => _c.auth.currentUser?.email ?? '';

  Future<void> _checkCode() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() { _checking = true; _traderName = null; _err = null; });
    try {
      final res = await _c.rpc('get_trader_by_code', params: {'p_company_code': code});
      if (mounted) setState(() {
        _traderName = (res != null && res['found'] == true) ? res['company_name'] as String? : null;
        _err = _traderName == null ? 'Code "$code" not found. Ask your admin.' : null;
        _checking = false;
      });
    } catch (_) { if (mounted) setState(() { _err = 'Network error. Try again.'; _checking = false; }); }
  }

  Future<void> _link() async {
    if (!_isSignedIn) { setState(() => _err = 'Not signed in. Go back and sign in first.'); return; }
    if (_codeCtrl.text.trim().isEmpty) { setState(() => _err = 'Enter company code'); return; }
    if (_nameCtrl.text.trim().isEmpty) { setState(() => _err = 'Enter your name'); return; }
    setState(() { _linking = true; _err = null; });
    try {
      await _c.rpc('link_agent_by_company_code', params: {
        'p_company_code': _codeCtrl.text.trim().toUpperCase(),
        'p_agent_name':   _nameCtrl.text.trim(),
        'p_user_id':      _c.auth.currentUser!.id,
      });
      if (mounted) {
        showSuccess(context, 'Linked! You can now use the delivery app ✓');
        context.go(R.agentHome);
      }
    } catch (e) {
      String msg = e.toString();
      if (msg.contains('No pending agent record') || msg.contains('name')) {
        msg = 'Name not matched.\n\nYou entered: "${_nameCtrl.text.trim()}"\nAsk admin what name they entered — must match exactly.';
      } else if (msg.contains('Company code') || msg.contains('not found')) {
        msg = 'Company code not found.';
      }
      if (mounted) setState(() { _err = msg.replaceAll('Exception: ','').replaceAll('PostgrestException(message: ',''); _linking = false; });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Link Agent Account')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

        // ── What is this ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade200)),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('What is account linking?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.blue)),
            SizedBox(height: 6),
            Text(
              'Your admin added your name in the delivery agents list.\n'
              'This screen connects your email login to that profile.\n'
              'Do this ONCE — after that, just sign in normally.',
              style: TextStyle(fontSize: 12, color: Colors.blue, height: 1.5)),
          ]),
        ),
        const SizedBox(height: 16),

        // ── Signed-in status ──────────────────────────────────────
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
                    const Text('Go back → Sign Up first, then come here.', style: TextStyle(fontSize: 11, color: Colors.orange)),
                  ])),
            if (!_isSignedIn)
              TextButton(onPressed: () => context.go(R.login), child: const Text('← Sign Up')),
          ]),
        ),
        const SizedBox(height: 16),

        // ── Error ─────────────────────────────────────────────────
        if (_err != null)
          Container(
            padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(color: const Color(0xFFFFF3F3), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade200)),
            child: Text(_err!, style: const TextStyle(color: kError, fontSize: 13, height: 1.4)),
          ),

        // ── Company Code ──────────────────────────────────────────
        const Text('Company Code', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kTextHint, letterSpacing: 0.5)),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: TextField(
            controller: _codeCtrl,
            enabled: _isSignedIn,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: 'e.g. RT001',
              prefixIcon: Icon(Icons.qr_code, size: 18, color: kPrimary)),
            onChanged: (_) => setState(() { _traderName = null; _err = null; }),
          )),
          const SizedBox(width: 8),
          SizedBox(height: 52, child: ElevatedButton(
            onPressed: (!_isSignedIn || _checking) ? null : _checkCode,
            child: _checking
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Check'),
          )),
        ]),
        if (_traderName != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.shade200)),
            child: Row(children: [
              Icon(Icons.check_circle, color: Colors.green.shade600, size: 16),
              const SizedBox(width: 8),
              Text('Found: $_traderName', style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w700)),
            ]),
          ),
        ],
        const SizedBox(height: 16),

        // ── Name ──────────────────────────────────────────────────
        const Text('Your Name', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kTextHint, letterSpacing: 0.5)),
        const SizedBox(height: 6),
        TextField(
          controller: _nameCtrl,
          enabled: _isSignedIn,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Enter your name exactly as admin typed it',
            prefixIcon: Icon(Icons.person_outline, size: 20, color: kPrimary)),
        ),
        const SizedBox(height: 6),
        const Text(
          'Important: spelling and capitals must match exactly what admin entered.',
          style: TextStyle(fontSize: 11, color: kTextHint)),
        const SizedBox(height: 24),

        // ── Link Button ───────────────────────────────────────────
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: (!_isSignedIn || _linking) ? null : _link,
            icon: _linking
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.link, size: 20),
            label: Text(
              _isSignedIn ? 'Link My Account' : 'Sign In First to Enable',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 12),
        Center(child: TextButton(
          onPressed: () => context.go(R.login),
          child: const Text('← Back to Login', style: TextStyle(color: kTextSub)),
        )),
      ]),
    ),
  );
}
