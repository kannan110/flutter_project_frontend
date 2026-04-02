import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override ConsumerState<LoginScreen> createState() => _LoginState();
}

class _LoginState extends ConsumerState<LoginScreen> with TickerProviderStateMixin {
  late final TabController _tab;
  final _siEmail  = TextEditingController();
  final _siPass   = TextEditingController();
  final _suEmail  = TextEditingController();
  final _suPass   = TextEditingController();
  final _suPassC  = TextEditingController();
  bool _busy = false, _siHide = true, _suHide = true;
  String? _err;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() { if (mounted) setState(() => _err = null); });
  }

  @override
  void dispose() {
    _tab.dispose();
    _siEmail.dispose(); _siPass.dispose();
    _suEmail.dispose(); _suPass.dispose(); _suPassC.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_siEmail.text.trim().isEmpty || _siPass.text.isEmpty) {
      if (mounted) setState(() => _err = 'Enter email and password'); return;
    }
    if (mounted) setState(() { _busy = true; _err = null; });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _siEmail.text.trim(), password: _siPass.text);
    } on AuthException catch (e) {
      if (mounted) setState(() { _err = _friendlyErr(e.message); _busy = false; });
    } catch (_) {
      if (mounted) setState(() { _err = 'Connection failed. Check internet.'; _busy = false; });
    }
  }

  Future<void> _signUp() async {
    final email = _suEmail.text.trim();
    final pass  = _suPass.text;
    if (email.isEmpty) { if (mounted) setState(() => _err = 'Enter email'); return; }
    if (pass.length < 6) { if (mounted) setState(() => _err = 'Password must be 6+ characters'); return; }
    if (pass != _suPassC.text) { if (mounted) setState(() => _err = 'Passwords do not match'); return; }
    if (mounted) setState(() { _busy = true; _err = null; });
    try {
      final res = await Supabase.instance.client.auth.signUp(email: email, password: pass);
      if (mounted) {
        _busy = false;
        if (res.user != null) {
          // Account created — go to sign in tab
          showSuccess(context, 'Account created! Go to Sign In tab and sign in.');
          _tab.animateTo(0);
          _siEmail.text = email;
          if (mounted) setState(() {});
        } else {
          // User exists but unconfirmed — try to sign in directly
          if (mounted) setState(() => _err =
            'Account may already exist. Try Sign In with the same email and password.');
        }
      }
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('rate limit') || msg.contains('too many') || msg.contains('over_email_send_rate_limit')) {
        // Rate limited — account may already exist, guide user to sign in
        if (mounted) setState(() {
          _err = 'Sign-up limit reached for this email.\n\n'
              'If you already signed up before, go to Sign In tab and use the same email and password.\n\n'
              'Tamil: இந்த மின்னஞ்சல் Sign Up வரம்பை தாண்டியது. ஏற்கெனவே Sign Up செய்திருந்தால், Sign In tab இல் உள்நுழையவும்.';
          _busy = false;
        });
      } else {
        if (mounted) setState(() { _err = _friendlyErr(e.message); _busy = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _err = 'Connection failed. Check internet.'; _busy = false; });
    }
  }

  String _friendlyErr(String m) {
    final lower = m.toLowerCase();
    if (lower.contains('rate limit') || lower.contains('too many') || lower.contains('over_email'))
      return 'Too many attempts. Wait a few minutes, or try Sign In if you already have an account.';
    if (lower.contains('already registered') || lower.contains('already exists'))
      return 'Email already registered. Use Sign In tab.';
    if (lower.contains('invalid login') || lower.contains('credentials') || lower.contains('invalid_credentials'))
      return 'Wrong email or password. Check and try again.';
    if (lower.contains('email not confirmed'))
      return 'Email not confirmed. Ask admin or try Sign In directly.';
    if (lower.contains('network') || lower.contains('connection'))
      return 'Connection error. Check your internet.';
    return m;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgGrey,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(children: [
            const SizedBox(height: 40),

            // ── Logo ──────────────────────────────────────────────
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1B6B3A), Color(0xFF2E8B57)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: kPrimary.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
              ),
              child: const Center(child: Text('🐓', style: TextStyle(fontSize: 38))),
            ),
            const SizedBox(height: 12),
            const Text('Rooster Trader', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: kTextMain)),
            const Text('Poultry Trading Platform', style: TextStyle(fontSize: 12, color: kTextHint)),
            const SizedBox(height: 28),

            // ── Tab Card ──────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 20, offset: const Offset(0, 4))],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Tab Bar
                Material(
                  color: const Color(0xFFF5F7F5),
                  child: TabBar(
                    controller: _tab,
                    dividerColor: Colors.transparent,
                    indicator: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(0)),
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: Colors.white,
                    unselectedLabelColor: kTextSub,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                    tabs: const [Tab(text: 'Sign In'), Tab(text: 'Sign Up')],
                  ),
                ),

                // Error banner
                if (_err != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    color: const Color(0xFFFFF3F3),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: kError, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_err!, style: const TextStyle(color: kError, fontSize: 12))),
                    ]),
                  ),

                // Tab Views
                SizedBox(
                  height: 260,
                  child: TabBarView(
                    controller: _tab,
                    children: [
                      // Sign In
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                        child: Column(children: [
                          TextField(
                            controller: _siEmail,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email_outlined, size: 20, color: kPrimary)),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _siPass,
                            obscureText: _siHide,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _signIn(),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline, size: 20, color: kPrimary),
                              suffixIcon: IconButton(
                                icon: Icon(_siHide ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18, color: kTextHint),
                                onPressed: () => setState(() => _siHide = !_siHide))),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity, height: 48,
                            child: ElevatedButton(
                              onPressed: _busy ? null : _signIn,
                              child: _busy
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                                  : const Text('Sign In', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ]),
                      ),

                      // Sign Up
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                        child: Column(children: [
                          const Text(
                            'Delivery agents: create account here, then link below',
                            style: TextStyle(fontSize: 11, color: kTextHint),
                            textAlign: TextAlign.center),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _suEmail,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email_outlined, size: 20, color: kPrimary)),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _suPass,
                            obscureText: _suHide,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'Password (min 6 chars)',
                              prefixIcon: const Icon(Icons.lock_outline, size: 20, color: kPrimary),
                              suffixIcon: IconButton(
                                icon: Icon(_suHide ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18, color: kTextHint),
                                onPressed: () => setState(() => _suHide = !_suHide))),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _suPassC,
                            obscureText: true,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _signUp(),
                            decoration: const InputDecoration(
                              labelText: 'Confirm Password',
                              prefixIcon: Icon(Icons.lock_outline, size: 20, color: kPrimary)),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity, height: 44,
                            child: ElevatedButton(
                              onPressed: _busy ? null : _signUp,
                              child: _busy
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                                  : const Text('Create Account', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ]),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),

            // ── Delivery Agent Section ────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kPrimary.withValues(alpha: 0.2)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.delivery_dining_outlined, color: kPrimary, size: 20),
                  SizedBox(width: 8),
                  Text('Delivery Agent?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: kPrimary)),
                ]),
                const SizedBox(height: 10),
                // Steps
                _step('1', 'Admin adds your name in the Agents screen'),
                _step('2', 'Sign Up above with your email (only once)'),
                _step('3', 'Get Company Code from your admin (e.g. RT001)'),
                _step('4', 'Tap button below → enter code + your name'),
                _step('5', 'After linking, use Sign In every day'),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => context.go(R.agentLink),
                    icon: const Icon(Icons.link, size: 18),
                    label: const Text('Link My Agent Account', style: TextStyle(fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: kPrimary, width: 1.5),
                      minimumSize: const Size(double.infinity, 46)),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }

  Widget _step(String n, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 20, height: 20, margin: const EdgeInsets.only(right: 8, top: 1),
        decoration: BoxDecoration(color: kPrimary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
        child: Center(child: Text(n, style: const TextStyle(fontSize: 10, color: kPrimary, fontWeight: FontWeight.w800))),
      ),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: kTextMain, height: 1.4))),
    ]),
  );
}
