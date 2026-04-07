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

  // Sign In
  final _siEmail = TextEditingController();
  final _siPass  = TextEditingController();

  // Sign Up (auth only — step 1)
  final _suEmail = TextEditingController();
  final _suPass  = TextEditingController();
  final _suPassC = TextEditingController();

  // Trader setup (step 2 — shown after sign-up)
  final _coName  = TextEditingController(); // company name
  final _coCode  = TextEditingController(); // company code (unique)
  final _coPhone = TextEditingController();
  final _coCity  = TextEditingController();
  final _coPerson= TextEditingController(); // contact person name
  final _joinCode= TextEditingController(); // for "join existing trader"

  bool _busy    = false;
  bool _siHide  = true;
  bool _suHide  = true;
  String? _err;

  // After auth sign-up succeeds, we move to trader setup step
  bool _showTraderSetup = false;
  String? _newUserId;
  bool _createNew = true; // true = create new company, false = join existing

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
    _coName.dispose(); _coCode.dispose(); _coPhone.dispose();
    _coCity.dispose(); _coPerson.dispose(); _joinCode.dispose();
    super.dispose();
  }

  // ── Step 1: Sign In ────────────────────────────────────────────
  Future<void> _signIn() async {
    if (_siEmail.text.trim().isEmpty || _siPass.text.isEmpty) {
      setState(() => _err = 'Enter email and password'); return;
    }
    setState(() { _busy = true; _err = null; });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _siEmail.text.trim(), password: _siPass.text);
    } on AuthException catch (e) {
      if (mounted) setState(() { _err = _friendlyErr(e.message); _busy = false; });
    } catch (_) {
      if (mounted) setState(() { _err = 'Connection failed. Check internet.'; _busy = false; });
    }
  }

  // ── Step 1: Sign Up (create auth account only) ─────────────────
  Future<void> _signUp() async {
    final email = _suEmail.text.trim();
    final pass  = _suPass.text;
    if (email.isEmpty)       { setState(() => _err = 'Enter email'); return; }
    if (pass.length < 6)     { setState(() => _err = 'Password must be 6+ characters'); return; }
    if (pass != _suPassC.text) { setState(() => _err = 'Passwords do not match'); return; }

    setState(() { _busy = true; _err = null; });
    try {
      final res = await Supabase.instance.client.auth.signUp(
          email: email, password: pass);
      if (mounted) {
        _busy = false;
        if (res.user != null) {
          // Auth account created — move to trader setup
          setState(() {
            _newUserId       = res.user!.id;
            _showTraderSetup = true;
            _err             = null;
          });
        } else {
          setState(() => _err = 'Account may already exist. Try Sign In.');
        }
      }
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('rate limit') || msg.contains('too many') || msg.contains('over_email')) {
        // Rate limited: account likely exists — try signing in, then do trader setup
        setState(() { _busy = true; _err = null; });
        try {
          final res2 = await Supabase.instance.client.auth.signInWithPassword(
              email: email, password: pass);
          if (mounted && res2.user != null) {
            setState(() {
              _newUserId       = res2.user!.id;
              _showTraderSetup = true;
              _busy            = false;
              _err             = null;
            });
          }
        } catch (_) {
          if (mounted) setState(() {
            _err = 'Rate limited. If you already signed up, go to Sign In tab.';
            _busy = false;
          });
        }
      } else {
        if (mounted) setState(() { _err = _friendlyErr(e.message); _busy = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _err = 'Connection failed.'; _busy = false; });
    }
  }

  // ── Step 2a: Create NEW trader company ─────────────────────────
  Future<void> _createTrader() async {
    final name = _coName.text.trim();
    final code = _coCode.text.trim().toUpperCase();
    if (name.isEmpty) { setState(() => _err = 'Enter company name'); return; }
    if (code.isEmpty) { setState(() => _err = 'Enter company code (e.g. RT001)'); return; }
    if (code.length < 3) { setState(() => _err = 'Code must be at least 3 characters'); return; }

    setState(() { _busy = true; _err = null; });
    try {
      // If we have newUserId from sign-up, use it. Otherwise get current user.
      final userId = _newUserId ??
          Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        setState(() { _err = 'Not signed in. Go back and sign in first.'; _busy = false; });
        return;
      }

      final res = await Supabase.instance.client.rpc('register_new_trader', params: {
        'p_user_id':        userId,
        'p_company_name':   name,
        'p_company_code':   code,
        'p_contact_person': _coPerson.text.trim().isEmpty ? null : _coPerson.text.trim(),
        'p_phone':          _coPhone.text.trim().isEmpty  ? null : _coPhone.text.trim(),
        'p_city':           _coCity.text.trim().isEmpty   ? null : _coCity.text.trim(),
      });

      if (!mounted) return;
      final result = res as Map<String,dynamic>;
      if (result['success'] == true) {
        showSuccess(context,
          '✅ "${result['company_name']}" created!\n'
          'Company code: ${result['company_code']}\n'
          'Sign in now to access your dashboard.');
        // Sign in automatically if we have credentials
        if (_suEmail.text.isNotEmpty && _suPass.text.isNotEmpty) {
          await Supabase.instance.client.auth.signInWithPassword(
              email: _suEmail.text.trim(), password: _suPass.text);
        } else {
          setState(() { _showTraderSetup = false; _busy = false; });
          _tab.animateTo(0);
        }
      }
    } catch (e) {
      if (mounted) setState(() {
        _err = e.toString()
            .replaceAll('Exception: ', '')
            .replaceAll('PostgrestException(message: ', '')
            .replaceAll(')', '');
        _busy = false;
      });
    }
  }

  // ── Step 2b: Join EXISTING trader company ──────────────────────
  Future<void> _joinTrader() async {
    final code = _joinCode.text.trim().toUpperCase();
    if (code.isEmpty) { setState(() => _err = 'Enter company code'); return; }

    setState(() { _busy = true; _err = null; });
    try {
      final userId = _newUserId ??
          Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        setState(() { _err = 'Not signed in.'; _busy = false; });
        return;
      }

      final res = await Supabase.instance.client.rpc('join_trader_as_admin', params: {
        'p_user_id':      userId,
        'p_company_code': code,
      });

      if (!mounted) return;
      final result = res as Map<String,dynamic>;
      if (result['success'] == true) {
        showSuccess(context,
          '✅ Joined "${result['company_name']}" as Admin!\n'
          'Sign in now to access the dashboard.');
        if (_suEmail.text.isNotEmpty && _suPass.text.isNotEmpty) {
          await Supabase.instance.client.auth.signInWithPassword(
              email: _suEmail.text.trim(), password: _suPass.text);
        } else {
          setState(() { _showTraderSetup = false; _busy = false; });
          _tab.animateTo(0);
        }
      }
    } catch (e) {
      if (mounted) setState(() {
        _err = e.toString()
            .replaceAll('Exception: ', '')
            .replaceAll('PostgrestException(message: ', '')
            .replaceAll(')', '');
        _busy = false;
      });
    }
  }

  String _friendlyErr(String m) {
    final lower = m.toLowerCase();
    if (lower.contains('rate limit') || lower.contains('too many') || lower.contains('over_email'))
      return 'Too many attempts. Wait a minute or use Sign In if you already have an account.';
    if (lower.contains('already registered') || lower.contains('already exists'))
      return 'Email already registered. Use Sign In tab.';
    if (lower.contains('invalid login') || lower.contains('credentials') || lower.contains('invalid_credentials'))
      return 'Wrong email or password.';
    if (lower.contains('email not confirmed'))
      return 'Email not confirmed. Try Sign In directly.';
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

            // Logo
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF1B6B3A), Color(0xFF2E8B57)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: kPrimary.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
              ),
              child: const Center(child: Text('🐓', style: TextStyle(fontSize: 38)))),
            const SizedBox(height: 12),
            const Text('Rooster Trader', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: kTextMain)),
            const Text('Poultry Trading Platform', style: TextStyle(fontSize: 12, color: kTextHint)),
            const SizedBox(height: 28),

            // Main card
            _showTraderSetup ? _buildTraderSetupCard() : _buildAuthCard(),

            const SizedBox(height: 20),

            // Delivery agent section (always shown unless in trader setup)
            if (!_showTraderSetup) _buildAgentSection(),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }

  // ── Auth card (Sign In / Sign Up) ──────────────────────────────
  Widget _buildAuthCard() => Container(
    decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 20, offset: const Offset(0, 4))]),
    clipBehavior: Clip.antiAlias,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Material(
        color: const Color(0xFFF5F7F5),
        child: TabBar(
          controller: _tab, dividerColor: Colors.transparent,
          indicator: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(0)),
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: Colors.white, unselectedLabelColor: kTextSub,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          tabs: const [Tab(text: 'Sign In'), Tab(text: 'Sign Up')]),
      ),
      if (_err != null) Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: const Color(0xFFFFF3F3),
        child: Row(children: [
          const Icon(Icons.error_outline, color: kError, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(_err!, style: const TextStyle(color: kError, fontSize: 12))),
        ])),
      SizedBox(
        height: 280,
        child: TabBarView(controller: _tab, children: [
          // ── Sign In tab
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(children: [
              TextField(
                controller: _siEmail, keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next, autocorrect: false,
                decoration: const InputDecoration(labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined, size: 20, color: kPrimary))),
              const SizedBox(height: 12),
              TextField(
                controller: _siPass, obscureText: _siHide,
                textInputAction: TextInputAction.done, onSubmitted: (_) => _signIn(),
                decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline, size: 20, color: kPrimary),
                    suffixIcon: IconButton(
                        icon: Icon(_siHide ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            size: 18, color: kTextHint),
                        onPressed: () => setState(() => _siHide = !_siHide)))),
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, height: 48,
                child: ElevatedButton(
                  onPressed: _busy ? null : _signIn,
                  child: _busy
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : const Text('Sign In', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))),
              const SizedBox(height: 12),
              const Text('Sign in with your registered email & password.',
                  style: TextStyle(fontSize: 11, color: kTextHint), textAlign: TextAlign.center),
            ])),

          // ── Sign Up tab
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                child: const Text(
                  'Step 1 of 2 — Create your account. After this you\'ll set up your company.',
                  style: TextStyle(fontSize: 11, color: Colors.blue), textAlign: TextAlign.center)),
              const SizedBox(height: 12),
              TextField(
                controller: _suEmail, keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next, autocorrect: false,
                decoration: const InputDecoration(labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined, size: 20, color: kPrimary))),
              const SizedBox(height: 8),
              TextField(
                controller: _suPass, obscureText: _suHide,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                    labelText: 'Password (min 6 chars)',
                    prefixIcon: const Icon(Icons.lock_outline, size: 20, color: kPrimary),
                    suffixIcon: IconButton(
                        icon: Icon(_suHide ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            size: 18, color: kTextHint),
                        onPressed: () => setState(() => _suHide = !_suHide)))),
              const SizedBox(height: 8),
              TextField(
                controller: _suPassC, obscureText: true,
                textInputAction: TextInputAction.done, onSubmitted: (_) => _signUp(),
                decoration: const InputDecoration(labelText: 'Confirm Password',
                    prefixIcon: Icon(Icons.lock_outline, size: 20, color: kPrimary))),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, height: 44,
                child: ElevatedButton(
                  onPressed: _busy ? null : _signUp,
                  child: _busy
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : const Text('Next: Set Up Company →',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)))),
            ])),
        ])),
    ]));

  // ── Step 2: Trader setup card ──────────────────────────────────
  Widget _buildTraderSetupCard() => Container(
    decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 20, offset: const Offset(0, 4))]),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      // Header
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: kPrimary, borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
        child: Row(children: [
          const Icon(Icons.business, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Step 2 — Company Setup', style: TextStyle(color: Colors.white70, fontSize: 11)),
            Text('Set up your trading company', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
          ])),
          TextButton(
            onPressed: () => setState(() { _showTraderSetup = false; _err = null; }),
            child: const Text('← Back', style: TextStyle(color: Colors.white70, fontSize: 12))),
        ])),

      Padding(padding: const EdgeInsets.all(20), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Error
        if (_err != null) Container(
          width: double.infinity, margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            const Icon(Icons.error_outline, color: kError, size: 16), const SizedBox(width: 8),
            Expanded(child: Text(_err!, style: const TextStyle(color: kError, fontSize: 12))),
          ])),

        // Toggle: Create New vs Join Existing
        Row(children: [
          Expanded(child: GestureDetector(
            onTap: () => setState(() { _createNew = true; _err = null; }),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                  color: _createNew ? kPrimary : Colors.grey.shade100,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(10))),
              child: Column(children: [
                Icon(Icons.add_business_outlined, color: _createNew ? Colors.white : kTextSub, size: 20),
                const SizedBox(height: 4),
                Text('New Company', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                    color: _createNew ? Colors.white : kTextSub)),
              ])))),
          Expanded(child: GestureDetector(
            onTap: () => setState(() { _createNew = false; _err = null; }),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                  color: !_createNew ? kPrimary : Colors.grey.shade100,
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(10))),
              child: Column(children: [
                Icon(Icons.group_add_outlined, color: !_createNew ? Colors.white : kTextSub, size: 20),
                const SizedBox(height: 4),
                Text('Join Existing', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                    color: !_createNew ? Colors.white : kTextSub)),
              ])))),
        ]),
        const SizedBox(height: 20),

        if (_createNew) ...[
          // ── Create new company form ────────────────────────────
          TextField(
            controller: _coName, textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                labelText: 'Company Name *',
                hintText: 'e.g. Rooster Traders Pvt Ltd',
                prefixIcon: Icon(Icons.business_outlined, size: 18, color: kPrimary))),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(
              controller: _coCode, textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                  labelText: 'Company Code *',
                  hintText: 'e.g. RT001',
                  prefixIcon: Icon(Icons.tag, size: 18, color: kPrimary)),
              onChanged: (v) {
                // Auto uppercase
                final upper = v.toUpperCase().replaceAll(' ', '');
                if (v != upper) {
                  _coCode.value = TextEditingValue(
                      text: upper,
                      selection: TextSelection.collapsed(offset: upper.length));
                }
              })),
            const SizedBox(width: 10),
            Expanded(child: TextField(
              controller: _coPhone, keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: 'Phone',
                  prefixIcon: Icon(Icons.phone_outlined, size: 18, color: kPrimary)))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(
              controller: _coPerson, textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Contact Person',
                  prefixIcon: Icon(Icons.person_outline, size: 18, color: kPrimary)))),
            const SizedBox(width: 10),
            Expanded(child: TextField(
              controller: _coCity, textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'City',
                  prefixIcon: Icon(Icons.location_city_outlined, size: 18, color: kPrimary)))),
          ]),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200)),
            child: const Text(
              '💡 Company Code is shared with delivery agents and staff to join your company. '
              'Choose something short and memorable (e.g. RT001, CHICKEN2).',
              style: TextStyle(fontSize: 11, color: Colors.brown))),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, height: 50,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : _createTrader,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.add_business, size: 20),
              label: const Text('Create Company & Start',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))),
        ] else ...[
          // ── Join existing company form ─────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10)),
            child: const Text(
              'Get the Company Code from the existing admin and enter it below '
              'to join as a Trader Admin.',
              style: TextStyle(fontSize: 12, color: Colors.blue))),
          const SizedBox(height: 14),
          TextField(
            controller: _joinCode, textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
                labelText: 'Company Code *',
                hintText: 'e.g. RT001',
                prefixIcon: Icon(Icons.tag, size: 18, color: kPrimary)),
            onChanged: (v) {
              final upper = v.toUpperCase().replaceAll(' ', '');
              if (v != upper) {
                _joinCode.value = TextEditingValue(
                    text: upper,
                    selection: TextSelection.collapsed(offset: upper.length));
              }
            }),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, height: 50,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : _joinTrader,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.group_add, size: 20),
              label: const Text('Join Company',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))),
        ],
      ])),
    ]));

  // ── Delivery agent section ─────────────────────────────────────
  Widget _buildAgentSection() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
        color: kPrimary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kPrimary.withValues(alpha: 0.2))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        Icon(Icons.delivery_dining_outlined, color: kPrimary, size: 20),
        SizedBox(width: 8),
        Text('Delivery Agent?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: kPrimary)),
      ]),
      const SizedBox(height: 10),
      _step('1', 'Admin adds your name in the Agents screen'),
      _step('2', 'Sign Up above with your email'),
      _step('3', 'Get Company Code from your admin (e.g. RT001)'),
      _step('4', 'Tap button below → enter code + your name to link'),
      _step('5', 'After linking, just Sign In every day'),
      const SizedBox(height: 14),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => context.go(R.agentLink),
          icon: const Icon(Icons.link, size: 18),
          label: const Text('Link My Agent Account', style: TextStyle(fontWeight: FontWeight.w700)),
          style: OutlinedButton.styleFrom(
              side: const BorderSide(color: kPrimary, width: 1.5),
              minimumSize: const Size(double.infinity, 46)))),
    ]));

  Widget _step(String n, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 20, height: 20, margin: const EdgeInsets.only(right: 8, top: 1),
        decoration: BoxDecoration(
            color: kPrimary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
        child: Center(child: Text(n, style: const TextStyle(
            fontSize: 10, color: kPrimary, fontWeight: FontWeight.w800)))),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: kTextMain, height: 1.4))),
    ]));
}
