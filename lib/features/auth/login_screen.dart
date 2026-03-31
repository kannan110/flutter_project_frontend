import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override ConsumerState<LoginScreen> createState() => _S();
}

class _S extends ConsumerState<LoginScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab;
  // Sign-in fields
  final _siEmail = TextEditingController();
  final _siPass  = TextEditingController();
  // Sign-up fields
  final _suEmail = TextEditingController();
  final _suPass  = TextEditingController();
  final _suPassC = TextEditingController();

  bool _loading = false, _siObscure = true, _suObscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() => setState(() => _error = null));
  }

  @override
  void dispose() {
    _siEmail.dispose(); _siPass.dispose();
    _suEmail.dispose(); _suPass.dispose(); _suPassC.dispose();
    _tab.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = _siEmail.text.trim();
    final pass  = _siPass.text;
    if (email.isEmpty || pass.isEmpty) { setState(() => _error = 'Enter email and password'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      await Supabase.instance.client.auth.signInWithPassword(email: email, password: pass);
      // session_provider handles routing automatically
    } on AuthException catch (e) {
      if (mounted) setState(() { _error = _cleanAuthError(e.message); _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = 'Connection error. Check internet.'; _loading = false; });
    }
  }

  Future<void> _signUp() async {
    final email = _suEmail.text.trim();
    final pass  = _suPass.text;
    final passC = _suPassC.text;
    if (email.isEmpty)   { setState(() => _error = 'Enter your email'); return; }
    if (pass.length < 6) { setState(() => _error = 'Password must be at least 6 characters'); return; }
    if (pass != passC)   { setState(() => _error = 'Passwords do not match'); return; }

    setState(() { _loading = true; _error = null; });
    try {
      final res = await Supabase.instance.client.auth.signUp(email: email, password: pass);
      if (mounted) {
        if (res.user != null) {
          // Account created — if delivery agent, go link; if trader, router handles it
          showSuccess(context, 'Account created ✓');
          setState(() { _loading = false; });
          // Switch to sign-in tab and pre-fill email
          _tab.animateTo(0);
          _siEmail.text = email;
        } else {
          setState(() {
            _error = 'Check your email for a confirmation link, then sign in here.';
            _loading = false;
          });
        }
      }
    } on AuthException catch (e) {
      if (mounted) setState(() { _error = _cleanAuthError(e.message); _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = 'Connection error.'; _loading = false; });
    }
  }

  String _cleanAuthError(String msg) {
    if (msg.toLowerCase().contains('rate limit') || msg.toLowerCase().contains('too many')) {
      return 'Too many attempts. Wait a few minutes and try again.';
    }
    if (msg.toLowerCase().contains('already registered')) {
      return 'Email already has an account. Use Sign In tab.';
    }
    if (msg.toLowerCase().contains('invalid login') || msg.toLowerCase().contains('invalid credentials')) {
      return 'Wrong email or password. Try again.';
    }
    return msg;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kBgGrey,
    body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Column(children: [

        // ── Logo ──────────────────────────────────────────────────
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF1B6B3A), Color(0xFF2E8B57)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: kPrimary.withOpacity(0.3), blurRadius: 18, offset: const Offset(0, 8))]),
          child: const Center(child: Text('🐓', style: TextStyle(fontSize: 36)))),
        const SizedBox(height: 14),
        const Text('Rooster Trader', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: kTextMain)),
        const Text('Poultry Trading Platform', style: TextStyle(fontSize: 11, color: kTextHint)),
        const SizedBox(height: 24),

        // ── Card with Tabs ────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, 4))]),
          child: Column(children: [
            // Tab bar
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: TabBar(
                controller: _tab,
                indicator: const BoxDecoration(color: kPrimary),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: kTextSub,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                tabs: const [Tab(text: 'Sign In'), Tab(text: 'Sign Up')],
              ),
            ),
            const Divider(height: 1),

            // Error
            if (_error != null) Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(color: const Color(0xFFFFF3F3), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade200)),
              child: Row(children: [const Icon(Icons.error_outline, color: kError, size: 16), const SizedBox(width: 8), Expanded(child: Text(_error!, style: const TextStyle(color: kError, fontSize: 12)))])),

            SizedBox(height: 280, child: TabBarView(controller: _tab, children: [

              // ── SIGN IN ──────────────────────────────────────────
              Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 20), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                TextFormField(controller: _siEmail, keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.next, autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined, size: 20))),
                const SizedBox(height: 12),
                TextFormField(controller: _siPass, obscureText: _siObscure, textInputAction: TextInputAction.done, onFieldSubmitted: (_) => _signIn(),
                    decoration: InputDecoration(
                      labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline, size: 20),
                      suffixIcon: IconButton(icon: Icon(_siObscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18), onPressed: () => setState(() => _siObscure = !_siObscure)))),
                const SizedBox(height: 20),
                SizedBox(width: double.infinity, child: ElevatedButton(
                    onPressed: _loading ? null : _signIn,
                    child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Text('Sign In'))),
              ])),

              // ── SIGN UP ──────────────────────────────────────────
              Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 20), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('Delivery agents: sign up here first, then link your profile below',
                    style: TextStyle(fontSize: 11, color: kTextHint), textAlign: TextAlign.center),
                const SizedBox(height: 10),
                TextFormField(controller: _suEmail, keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.next, autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined, size: 20))),
                const SizedBox(height: 8),
                TextFormField(controller: _suPass, obscureText: _suObscure, textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Password (min 6 chars)', prefixIcon: const Icon(Icons.lock_outline, size: 20),
                      suffixIcon: IconButton(icon: Icon(_suObscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18), onPressed: () => setState(() => _suObscure = !_suObscure)))),
                const SizedBox(height: 8),
                TextFormField(controller: _suPassC, obscureText: true, textInputAction: TextInputAction.done, onFieldSubmitted: (_) => _signUp(),
                    decoration: const InputDecoration(labelText: 'Confirm Password', prefixIcon: Icon(Icons.lock_outline, size: 20))),
                const SizedBox(height: 14),
                SizedBox(width: double.infinity, child: ElevatedButton(
                    onPressed: _loading ? null : _signUp,
                    child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Text('Create Account'))),
              ])),
            ])),
          ])),
        const SizedBox(height: 18),

        // ── Delivery Agent Link Box ───────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: kPrimary.withOpacity(0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kPrimary.withOpacity(0.2))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.delivery_dining, color: kPrimary, size: 22),
              SizedBox(width: 8),
              Text('Delivery Agent Login Guide', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: kPrimary)),
            ]),
            const SizedBox(height: 10),
            _agentStep('1', 'Admin adds your name in the Agents screen'),
            _agentStep('2', 'Sign Up above using your email (only once)'),
            _agentStep('3', 'Get Company Code from your admin (e.g. RT001)'),
            _agentStep('4', 'Tap "Link Account" below and enter your code + name'),
            _agentStep('5', 'After linking, Sign In normally every day'),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: () => context.go(R.agentLink),
              icon: const Icon(Icons.link, size: 18),
              label: const Text('Link My Agent Account', style: TextStyle(fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: kPrimary), minimumSize: const Size(0, 46)),
            )),
          ])),
        const SizedBox(height: 20),
        const Text('Rooster Trader PTOS v2.0', style: TextStyle(fontSize: 10, color: kTextHint)),
      ]))))),
  );

  Widget _agentStep(String n, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 20, height: 20, margin: const EdgeInsets.only(right: 8, top: 1),
        decoration: BoxDecoration(color: kPrimary.withOpacity(0.15), shape: BoxShape.circle),
        child: Center(child: Text(n, style: const TextStyle(fontSize: 10, color: kPrimary, fontWeight: FontWeight.w800)))),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: kTextMain, height: 1.4))),
    ]));
}
