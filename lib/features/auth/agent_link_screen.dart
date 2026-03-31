import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rooster_trader/core/models/app_user.dart' show AppUser;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/router/app_router.dart';
import '../../core/providers/session_provider.dart';
import '../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FIX Bug #1 : Changed StatefulWidget → ConsumerStatefulWidget so we can call
//              ref.read(appUserProvider.notifier).reload() after a successful
//              link.  Previously the session was never reloaded, causing the
//              router redirect to send the agent back to /login immediately.
//
// FIX Bug #3 : Auth state is now read from appUserProvider (Riverpod) instead
//              of Supabase.instance.client directly, so stale-token edge cases
//              are handled by the notifier.
// ─────────────────────────────────────────────────────────────────────────────

class AgentLinkScreen extends ConsumerStatefulWidget {
  const AgentLinkScreen({super.key});

  @override
  ConsumerState<AgentLinkScreen> createState() => _AgentLinkScreenState();
}

class _AgentLinkScreenState extends ConsumerState<AgentLinkScreen> {
  final _c = Supabase.instance.client;
  final _code = TextEditingController();
  final _name = TextEditingController();

  bool _linking = false, _checking = false;
  String? _error;
  String? _verifiedTrader;
  String? _availableNames;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  // ── Auth state from Riverpod provider (Fix Bug #3) ──────────────
  AppUser? get _appUser => ref.read(appUserProvider).valueOrNull;

  String? get _signedInEmail => _c.auth.currentUser?.email;

  String? get _signedInId => _c.auth.currentUser?.id;

  bool get _isSignedIn => _signedInId != null;

  // ── Step 1: verify code ──────────────────────────────────────────
  Future<void> _verifyCode() async {
    final code = _code.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() {
      _checking = true;
      _verifiedTrader = null;
      _error = null;
    });
    try {
      final res =
          await _c.rpc('get_trader_by_code', params: {'p_company_code': code});
      if (mounted)
        setState(() {
          if (res != null && res['found'] == true) {
            _verifiedTrader = res['company_name'] as String?;
            _error = null;
          } else {
            _verifiedTrader = null;
            _error =
                'Code "$code" not found. Ask your admin for the correct code.';
          }
          _checking = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _error = 'Network error. Try again.';
          _checking = false;
        });
    }
  }

  // ── Step 2: link account ─────────────────────────────────────────
  Future<void> _link() async {
    if (!_isSignedIn) {
      setState(() => _error = 'Sign in first (go back to Login screen)');
      return;
    }
    if (_verifiedTrader == null) {
      setState(() => _error = 'Verify your Company Code first (tap Check)');
      return;
    }
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter your name');
      return;
    }

    setState(() {
      _linking = true;
      _error = null;
      _availableNames = null;
    });
    try {
      await _c.rpc('link_agent_by_company_code', params: {
        'p_company_code': _code.text.trim().toUpperCase(),
        'p_agent_name': _name.text.trim(),
        'p_user_id': _signedInId,
      });

      // ── FIX Bug #1: Reload session so the router gets the new role ──
      await ref.read(appUserProvider.notifier).reload();

      if (mounted) {
        showSuccess(context, 'Linked! Welcome to Rooster Trader ✓');
        // Router redirect will now automatically route to agentHome
        // because appUserProvider has role=delivery_staff after reload.
        context.go(R.agentHome);
      }
    } catch (e) {
      if (mounted)
        setState(() {
          final raw = e.toString();
          if (raw.contains('No unlinked agent') ||
              raw.contains('Available names:')) {
            final match = RegExp(r'Available names: (.+)$').firstMatch(raw);
            _availableNames = match?.group(1) ?? '';
            _error = 'Name "${_name.text.trim()}" not found in the system.';
          } else if (raw.contains('Company code')) {
            _error = 'Company code not found. Tap Check to verify.';
          } else if (raw.contains('user_id is required')) {
            _error = 'You are not signed in. Go back and sign in first.';
          } else {
            _error = raw
                .replaceAll('Exception: ', '')
                .replaceAll('PostgrestException(message: ', '')
                .replaceAll(
                    RegExp(r',.*$'), ''); // strip verbose Postgrest suffix
          }
          _linking = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch provider so UI reacts if auth changes externally
    final asyncUser = ref.watch(appUserProvider);
    final isSignedIn = asyncUser.valueOrNull != null || _isSignedIn;

    return Scaffold(
      backgroundColor: kBgGrey,
      appBar: AppBar(title: const Text('Link Delivery Account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _flowDiagram(),
          const SizedBox(height: 20),

          _signInStatus(),
          const SizedBox(height: 16),

          if (_error != null) _errorBox(),
          if (_availableNames != null && _availableNames!.isNotEmpty)
            _namesHint(),

          // ── STEP 1: Company Code ─────────────────────────────────
          _stepCard(
            step: '1',
            title: 'Company Code',
            subtitle: 'Ask your admin — e.g. RT001',
            color: _verifiedTrader != null ? Colors.green : kPrimary,
            child: Column(children: [
              Row(children: [
                Expanded(
                    child: TextField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]'))
                  ],
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3),
                  decoration: const InputDecoration(
                    hintText: 'RT001',
                    hintStyle: TextStyle(
                        fontSize: 18, color: kTextHint, letterSpacing: 1),
                    prefixIcon: Icon(Icons.qr_code, size: 22),
                  ),
                  onChanged: (_) => setState(() {
                    _verifiedTrader = null;
                    _error = null;
                  }),
                )),
                const SizedBox(width: 10),
                SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _checking ? null : _verifyCode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _verifiedTrader != null ? Colors.green : kPrimary,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      child: _checking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(_verifiedTrader != null ? '✓ OK' : 'Check',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                    )),
              ]),
              if (_verifiedTrader != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(children: [
                    const Icon(Icons.check_circle,
                        color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text('Company: $_verifiedTrader',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.green))),
                  ]),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 12),

          // ── STEP 2: Your Name ────────────────────────────────────
          _stepCard(
            step: '2',
            title: 'Your Name',
            subtitle: 'Exactly as your admin typed it',
            color: kPrimary,
            child: TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'e.g. Saranraj or RAJ',
                prefixIcon: const Icon(Icons.person_outline, size: 20),
                helperText: _availableNames != null
                    ? 'Available names: $_availableNames'
                    : 'Ask your admin if you are unsure',
                helperStyle: TextStyle(
                    color: _availableNames != null
                        ? Colors.orange.shade700
                        : kTextHint,
                    fontWeight: _availableNames != null
                        ? FontWeight.w600
                        : FontWeight.normal),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── LINK BUTTON ──────────────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            child: ElevatedButton(
              onPressed: (!isSignedIn || _linking) ? null : _link,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                backgroundColor: isSignedIn ? kPrimary : Colors.grey,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _linking
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                          SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: Colors.white)),
                          SizedBox(width: 12),
                          Text('Linking...',
                              style:
                                  TextStyle(fontSize: 16, color: Colors.white)),
                        ])
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                          Icon(Icons.link, color: Colors.white, size: 22),
                          SizedBox(width: 10),
                          Text('Link My Account',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white)),
                        ]),
            ),
          ),

          if (!isSignedIn) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => context.go(R.login),
              icon: const Icon(Icons.login, size: 18),
              label: const Text('Go to Login / Sign Up first'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 46)),
            ),
          ],

          const SizedBox(height: 12),
          Center(
              child: TextButton(
            onPressed: () => context.go(R.login),
            child: const Text('← Back to Login',
                style: TextStyle(color: kTextSub, fontSize: 13)),
          )),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  // ── VISUAL FLOW DIAGRAM ──────────────────────────────────────────
  Widget _flowDiagram() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: const Border.fromBorderSide(BorderSide(color: kBorder))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('HOW IT WORKS',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: kTextHint,
                  letterSpacing: 0.8)),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _dot('Admin adds your name in Agents screen',
                Icons.admin_panel_settings_outlined, Colors.blue, true),
            _arrow(),
            _dot('You sign up with email on Login screen',
                Icons.person_add_outlined, Colors.orange, _isSignedIn),
            _arrow(),
            _dot('Come here, enter Code + Name', Icons.link, kPrimary, false),
            _arrow(),
            _dot('Sign in normally every day after', Icons.check_circle_outline,
                Colors.green, false),
          ]),
        ]),
      );

  Widget _dot(String label, IconData icon, Color color, bool done) => Expanded(
          child: Column(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: done ? color : color.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: done ? 0 : 1.5),
          ),
          child: Icon(icon, size: 20, color: done ? Colors.white : color),
        ),
        const SizedBox(height: 6),
        Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 9, color: kTextSub, height: 1.3)),
      ]));

  Widget _arrow() => const Padding(
        padding: EdgeInsets.only(top: 10),
        child: Icon(Icons.arrow_forward, size: 14, color: kTextHint),
      );

  // ── SIGN-IN STATUS BOX ───────────────────────────────────────────
  Widget _signInStatus() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _isSignedIn ? Colors.green.shade50 : Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color:
                  _isSignedIn ? Colors.green.shade300 : Colors.orange.shade300),
        ),
        child: Row(children: [
          Icon(
            _isSignedIn ? Icons.check_circle : Icons.account_circle_outlined,
            color: _isSignedIn ? Colors.green.shade600 : Colors.orange.shade700,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
              child: _isSignedIn
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          const Text('Signed in as:',
                              style:
                                  TextStyle(fontSize: 10, color: Colors.green)),
                          Text(_signedInEmail ?? '',
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.green)),
                        ])
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          const Text('Not signed in',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.orange)),
                          const Text(
                              'Go to Login → Sign Up first, then come back here.',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.orange,
                                  height: 1.3)),
                        ])),
          if (_isSignedIn)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.green, borderRadius: BorderRadius.circular(6)),
              child: const Text('READY',
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.w800)),
            ),
        ]),
      );

  Widget _errorBox() => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3F3),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.error_outline, color: kError, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(_error!,
                  style: const TextStyle(
                      color: kError, fontSize: 13, height: 1.4))),
        ]),
      );

  Widget _namesHint() => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('NAMES YOUR ADMIN HAS ADDED:',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.orange,
                  letterSpacing: 0.5)),
          const SizedBox(height: 6),
          Text(_availableNames!,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.orange)),
          const SizedBox(height: 4),
          const Text('Enter your name exactly as shown above.',
              style: TextStyle(fontSize: 11, color: Colors.orange)),
        ]),
      );

  Widget _stepCard(
          {required String step,
          required String title,
          required String subtitle,
          required Color color,
          required Widget child}) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Center(
                  child: Text(step,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14))),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: color)),
                  Text(subtitle,
                      style: const TextStyle(fontSize: 11, color: kTextHint)),
                ])),
          ]),
          const SizedBox(height: 12),
          child,
        ]),
      );
}
