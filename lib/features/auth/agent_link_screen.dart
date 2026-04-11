import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';

class AgentLinkScreen extends ConsumerStatefulWidget {
  const AgentLinkScreen({super.key});
  @override ConsumerState<AgentLinkScreen> createState() => _AgentLinkState();
}

class _AgentLinkState extends ConsumerState<AgentLinkScreen> {
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _c        = Supabase.instance.client;

  bool _linking = false, _checking = false;
  bool _showTamil = false; // language toggle
  String? _err, _traderName;

  @override void dispose() { _codeCtrl.dispose(); _nameCtrl.dispose(); super.dispose(); }

  // FIX: read from Supabase directly — never rely on cached getter in build
  bool   get _isSignedIn => _c.auth.currentUser != null;
  String get _email      => _c.auth.currentUser?.email ?? '';

  // ── Tamil / English text ──────────────────────────────────────────
  String _t(String en, String ta) => _showTamil ? ta : en;

  Future<void> _checkCode() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      if (mounted) setState(() => _err = _t('Enter company code', 'கம்பெனி கோட் உள்ளிடவும்'));
      return;
    }
    if (mounted) setState(() { _checking = true; _traderName = null; _err = null; });
    try {
      final res = await _c.rpc('get_trader_by_code', params: {'p_company_code': code});
      if (!mounted) return;
      if (res != null && res is Map && res['found'] == true) {
        if (mounted) setState(() {
          _traderName = res['company_name'] as String? ?? 'Found';
          _checking   = false;
        });
      } else {
        if (mounted) setState(() {
          _err      = _t(
            'Code "$code" not found. Ask your admin for the correct code.',
            '"$code" கோட் கிடைக்கவில்லை. உங்கள் அட்மினிடம் சரியான கோட் கேளுங்கள்.');
          _checking = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() {
        _err      = _t('Network error. Try again.', 'நெட்வொர்க் பிழை. மீண்டும் முயற்சிக்கவும்.');
        _checking = false;
      });
    }
  }

  Future<void> _link() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    final name = _nameCtrl.text.trim();

    if (!_isSignedIn) {
      if (mounted) setState(() => _err = _t(
          'Not signed in. Go back and sign in first.',
          'உள்நுழையவில்லை. திரும்பி Sign In செய்யுங்கள்.'));
      return;
    }
    if (code.isEmpty) {
      if (mounted) setState(() => _err = _t('Enter company code', 'கம்பெனி கோட் உள்ளிடவும்'));
      return;
    }
    if (name.isEmpty) {
      if (mounted) setState(() => _err = _t(
          'Enter your name exactly as admin typed it',
          'அட்மின் தட்டச்சு செய்த பெயரை சரியாக உள்ளிடவும்'));
      return;
    }

    // Verify code first if not already verified
    if (_traderName == null) {
      await _checkCode();
      if (_traderName == null) return;
    }

    if (mounted) setState(() { _linking = true; _err = null; });
    try {
      await _c.rpc('link_agent_by_company_code', params: {
        'p_company_code': code,
        'p_agent_name':   name,
        'p_user_id':      _c.auth.currentUser!.id,
      });

      if (!mounted) return;
      // Reload session so appUserProvider gets delivery_staff role + agentId
      await ref.read(appUserProvider.notifier).reload();

      if (mounted) {
        showSuccess(context, _t(
            'Account linked! Welcome to Rooster Trader ✓',
            'அக்கவுண்ட் இணைக்கப்பட்டது! வரவேற்கிறோம் ✓'));
        context.go(R.agentHome);
      }
    } catch (e) {
      if (!mounted) return;
      String raw = e.toString()
          .replaceAll('Exception: ', '')
          .replaceAll('PostgrestException(message: ', '')
          .replaceAll(')', '');

      String msg;
      if (raw.contains('No unlinked agent')) {
        // Extract available names from error message
        final available = raw.contains('Available names:')
            ? raw.split('Available names:').last.trim()
            : '';
        msg = _t(
          'Name "$name" not matched.\n\n'
          'Names available to link: ${available.isEmpty ? "none (ask admin)" : available}\n\n'
          'Enter the exact name admin used.',
          'பெயர் "$name" பொருந்தவில்லை.\n\n'
          'இணைக்க கிடைக்கும் பெயர்கள்: ${available.isEmpty ? "யாரும் இல்லை (அட்மினிடம் கேளுங்கள்)" : available}\n\n'
          'அட்மின் பயன்படுத்திய சரியான பெயரை உள்ளிடவும்.');
      } else if (raw.contains('Company code') || raw.contains('not found')) {
        msg = _t(
          'Company code "$code" not found.',
          'கம்பெனி கோட் "$code" கிடைக்கவில்லை.');
      } else if (raw.contains('already linked') || raw.contains('already exists')) {
        msg = _t(
          'This account is already linked. Try signing in normally.',
          'இந்த அக்கவுண்ட் ஏற்கெனவே இணைக்கப்பட்டுள்ளது. Sign In செய்யுங்கள்.');
      } else {
        msg = raw;
      }
      if (mounted) setState(() { _err = msg; _linking = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    // FIX: rebuild when auth state changes — watch live
    final authUser = _c.auth.currentUser;
    final signedIn = authUser != null;
    final email    = authUser?.email ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(_t('Link Agent Account', 'ஏஜென்ட் அக்கவுண்ட் இணைக்கவும்')),
        actions: [
          // Language toggle
          TextButton(
            onPressed: () => setState(() { _showTamil = !_showTamil; }),
            child: Text(_showTamil ? 'EN' : 'தமிழ்',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

          // ── Steps banner ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_t('How to link your account:', 'உங்கள் அக்கவுண்டை எவ்வாறு இணைப்பது:'),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.blue)),
              const SizedBox(height: 8),
              _step('1', _t(
                  'Admin adds your name in the Agents screen',
                  'அட்மின் உங்கள் பெயரை Agents திரையில் சேர்க்கிறார்')),
              _step('2', _t(
                  'You sign up with your email (do this only once)',
                  'உங்கள் மின்னஞ்சலில் Sign Up செய்யுங்கள் (ஒரு முறை மட்டும்)')),
              _step('3', _t(
                  'Ask admin for the Company Code (e.g. RT001)',
                  'அட்மினிடம் Company Code கேளுங்கள் (எ.கா. RT001)')),
              _step('4', _t(
                  'Enter the code and your exact name below',
                  'கீழே கோட் மற்றும் உங்கள் சரியான பெயரை உள்ளிடவும்')),
              _step('5', _t(
                  'After linking, just Sign In every day',
                  'இணைத்த பிறகு, தினமும் Sign In மட்டும் செய்யுங்கள்')),
            ])),
          const SizedBox(height: 16),

          // ── Sign-in status ────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: signedIn ? Colors.green.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: signedIn ? Colors.green.shade300 : Colors.red.shade300)),
            child: signedIn
                ? Row(children: [
                    const Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_t('Signed in as:', 'உள்நுழைந்தீர்கள்:'),
                          style: const TextStyle(fontSize: 11, color: Colors.green)),
                      Text(email, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.green)),
                    ])),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Text(
                        _t('Not signed in!', 'உள்நுழையவில்லை!'),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.red))),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                      _t(
                        'You must sign up or sign in first.\n'
                        '1. Go back → Sign Up tab → create account with your email\n'
                        '2. Come back here to link',
                        'முதலில் Sign Up அல்லது Sign In செய்ய வேண்டும்.\n'
                        '1. திரும்பு → Sign Up tab → உங்கள் மின்னஞ்சலில் அக்கவுண்ட் உருவாக்கு\n'
                        '2. மீண்டும் இங்கு வந்து இணைக்கவும்'),
                      style: const TextStyle(fontSize: 12, color: Colors.red, height: 1.5)),
                    const SizedBox(height: 12),
                    SizedBox(width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => context.go(R.login),
                        icon: const Icon(Icons.login, size: 18),
                        label: Text(_t('Go to Sign Up / Sign In', 'Sign Up / Sign In க்கு செல்லுங்கள்')),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red))),
                  ])),
          const SizedBox(height: 16),

          // ── Error banner ──────────────────────────────────────────
          if (_err != null) Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade300)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.error_outline, color: kError, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(_err!, style: const TextStyle(color: kError, fontSize: 13, height: 1.5))),
              GestureDetector(
                onTap: () => setState(() => _err = null),
                child: const Icon(Icons.close, color: kError, size: 18)),
            ])),

          // ── Company Code ──────────────────────────────────────────
          Text(_t('COMPANY CODE', 'கம்பெனி கோட்'),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kTextHint, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: TextField(
              controller: _codeCtrl,
              // FIX: NEVER disable the field — always enabled regardless of sign-in state
              // was: enabled: _isSignedIn  <-- this was the bug causing uneditable field
              enabled: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: _t('e.g. RT001', 'எ.கா. RT001'),
                prefixIcon: const Icon(Icons.business_outlined, size: 18, color: kPrimary),
                // FIX: show green tick when verified
                suffixIcon: _traderName != null
                    ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                    : null),
              onChanged: (_) { if (mounted) setState(() { _traderName = null; _err = null; }); },
            )),
            const SizedBox(width: 8),
            SizedBox(height: 52, width: 104 ,child: ElevatedButton(
              onPressed: _checking || _codeCtrl.text.trim().isEmpty ? null : _checkCode,
              child: _checking
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_t('Verify', 'சரிபார்')),
            )),
          ]),

          // Verified company name
          if (_traderName != null) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200)),
              child: Row(children: [
                Icon(Icons.check_circle, color: Colors.green.shade600, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  '✓ ${_t("Found", "கிடைத்தது")}: $_traderName',
                  style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w700, fontSize: 13))),
              ]))),
          const SizedBox(height: 16),

          // ── Your Name ─────────────────────────────────────────────
          Text(_t('YOUR NAME (as admin typed it)', 'உங்கள் பெயர் (அட்மின் தட்டச்சு செய்தபடி)'),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kTextHint, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          TextField(
            controller: _nameCtrl,
            // FIX: always enabled
            enabled: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: _t('Enter your exact name', 'உங்கள் சரியான பெயரை உள்ளிடவும்'),
              prefixIcon: const Icon(Icons.person_outline, size: 20, color: kPrimary)),
            onChanged: (_) { if (mounted) setState(() => _err = null); },
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(
                _t(
                  'Spelling must match EXACTLY what admin entered — including capitals. '
                  'Example: If admin typed "RAM" then type "RAM" not "Ram" or "ram".',
                  'அட்மின் உள்ளிட்டதை EXACTLY போலவே பெயர் இருக்க வேண்டும். '
                  'உதாரணம்: அட்மின் "RAM" என்று தட்டினால் "RAM" என்று தட்டவும், "Ram" அல்ல.'),
                style: const TextStyle(fontSize: 12, color: Colors.orange, height: 1.4))),
            ])),

          // Sign-in required notice (only when not signed in)
          if (!signedIn) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10)),
              child: Text(
                _t(
                  '⚠️ Complete sign-up first, then come back to link.',
                  '⚠️ முதலில் Sign Up முடிக்கவும், பிறகு இங்கு திரும்பவும்.'),
                style: const TextStyle(fontSize: 12, color: kTextSub, fontStyle: FontStyle.italic))),
          ],
          const SizedBox(height: 24),

          // ── Link button ───────────────────────────────────────────
          SizedBox(height: 52, child: ElevatedButton.icon(
            onPressed: _linking ? null : _link,
            icon: _linking
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.link, size: 20),
            label: Text(
              _t('Link My Account', 'என் அக்கவுண்டை இணை'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          )),
          const SizedBox(height: 12),
          Center(child: TextButton(
            onPressed: () => context.go(R.login),
            child: Text(_t('← Back to Login', '← Login பக்கம் திரும்பு'),
                style: const TextStyle(color: kTextSub)))),
          const SizedBox(height: 30),
        ]),
      ),
    );
  }

  Widget _step(String n, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 20, height: 20, margin: const EdgeInsets.only(right: 8, top: 1),
          decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
          child: Center(child: Text(n, style: const TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.w800)))),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.blue, height: 1.4))),
    ]));
}
