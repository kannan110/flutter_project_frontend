import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';

/// ═══════════════════════════════════════════════════════════════════
/// LOGIN SCREEN — Three clear paths:
///   1. I am a Trader   → register company OR sign in
///   2. I am a Delivery Agent → sign in + link
///   3. Already have account → sign in
/// ═══════════════════════════════════════════════════════════════════
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _S();
}

class _S extends ConsumerState<LoginScreen> {
  // 0 = role picker, 1 = trader signin, 2 = trader signup, 3 = agent signin
  int _step = 0;

  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _hidePass = true;
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _reset() => setState(() {
        _step = 0;
        _err = null;
        _agentSignUpMode = false;
        _emailCtrl.clear();
        _passCtrl.clear();
        _confirmCtrl.clear();
      });

  Future<void> _signIn() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (email.isEmpty) {
      setState(() => _err = 'Email required');
      return;
    }
    if (pass.length < 6) {
      setState(() => _err = 'Password must be 6+ characters');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await Supabase.instance.client.auth
          .signInWithPassword(email: email, password: pass);
    } on AuthException catch (e) {
      if (mounted)
        setState(() {
          _err = _friendly(e.message);
          _busy = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _err = 'Connection failed. Check internet.';
          _busy = false;
        });
    }
  }

  String _friendly(String m) {
    final l = m.toLowerCase();
    if (l.contains('invalid') || l.contains('credentials'))
      return 'Wrong email or password. Try again.';
    if (l.contains('rate') || l.contains('too many'))
      return 'Too many attempts. Wait 1 minute.';
    if (l.contains('network') || l.contains('connection'))
      return 'No internet. Check your connection.';
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
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF1B6B3A), Color(0xFF2E8B57)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                          color: kPrimary.withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 6))
                    ]),
                child: const Center(
                    child: Text('🐓', style: TextStyle(fontSize: 38)))),
            const SizedBox(height: 12),
            const Text('Rooster Trader',
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: kTextMain)),
            const Text('Poultry Trading App',
                style: TextStyle(fontSize: 13, color: kTextHint)),
            const SizedBox(height: 32),

            // Content by step
            if (_step == 0)
              _buildRolePicker()
            else if (_step == 1)
              _buildSignIn(
                  title: 'Trader Sign In',
                  hint: 'Sign in to your trader account')
            else if (_step == 2)
              _buildTraderRegister()
            else
              _buildAgentSection(),

            const SizedBox(height: 30),
          ]),
        )));
  }

  // ── Step 0: Who are you? ───────────────────────────────────────────────────
  Widget _buildRolePicker() => Column(children: [
        const Text('Who are you?',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800, color: kTextMain)),
        const SizedBox(height: 6),
        const Text('Select your role to get started',
            style: TextStyle(fontSize: 14, color: kTextSub)),
        const SizedBox(height: 28),

        // Trader card
        _roleCard(
            icon: '🏪',
            title: 'I am a Trader',
            subtitle:
                'I run a poultry trading business\nI manage orders, agents & deliveries',
            color: kPrimary,
            onTap: () => setState(() {
                  _step = 1;
                  _err = null;
                })),
        const SizedBox(height: 16),

        // Delivery agent card
        _roleCard(
            icon: '🚚',
            title: 'I am a Delivery Agent',
            subtitle:
                'I deliver chicken to shops\nI use the app during my shift',
            color: Colors.blue.shade700,
            onTap: () => setState(() {
                  _step = 3;
                  _err = null;
                })),
        const SizedBox(height: 28),

        // Already have account
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('Already signed in before? ',
              style: TextStyle(fontSize: 13, color: kTextSub)),
          GestureDetector(
              onTap: () => setState(() {
                    _step = 1;
                    _err = null;
                  }),
              child: const Text('Sign In',
                  style: TextStyle(
                      fontSize: 13,
                      color: kPrimary,
                      fontWeight: FontWeight.w800))),
        ]),
      ]);

  Widget _roleCard({
    required String icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
          onTap: onTap,
          child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: color.withValues(alpha: 0.3), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 12,
                        offset: const Offset(0, 3))
                  ]),
              child: Row(children: [
                Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14)),
                    child: Center(
                        child:
                            Text(icon, style: const TextStyle(fontSize: 28)))),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(title,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: color)),
                      const SizedBox(height: 4),
                      Text(subtitle,
                          style: const TextStyle(
                              fontSize: 12, color: kTextSub, height: 1.4)),
                    ])),
                Icon(Icons.arrow_forward_ios, size: 14, color: color),
              ])));

  // ── Sign In form (shared for trader + agent) ───────────────────────────────
  Widget _buildSignIn({required String title, required String hint}) =>
      _card(children: [
        _backBtn(),
        const SizedBox(height: 4),
        Text(title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(hint, style: const TextStyle(fontSize: 12, color: kTextSub)),
        const SizedBox(height: 20),
        if (_err != null) _errBox(_err!),
        _emailField(),
        const SizedBox(height: 12),
        _passField(),
        const SizedBox(height: 20),
        _submitBtn('Sign In', _signIn),
        const SizedBox(height: 16),
        if (_step == 1) ...[
          const Divider(),
          const SizedBox(height: 12),
          const Text('New trader? Create your account',
              style: TextStyle(fontSize: 13, color: kTextSub),
              textAlign: TextAlign.center),
          const SizedBox(height: 10),
          OutlinedButton.icon(
              onPressed: () => setState(() {
                    _step = 2;
                    _err = null;
                  }),
              icon: const Icon(Icons.add_business_outlined, size: 18),
              label: const Text('Register My Company',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  side: const BorderSide(color: kPrimary, width: 1.5))),
        ],
      ]);

  // ── Trader Register (step 2) ───────────────────────────────────────────────
  Widget _buildTraderRegister() {
    // Delegates to TraderRegisterFlow — separate widget for cleanliness
    return _TraderRegisterCard(
        onBack: () => setState(() {
              _step = 1;
              _err = null;
            }));
  }

  // ── Delivery Agent section (step 3) ───────────────────────────────────────
  // Sub-mode: false = sign in, true = sign up
  bool _agentSignUpMode = false;

  Widget _buildAgentSection() {
    if (_agentSignUpMode) return _buildAgentSignUp();
    return _buildAgentSignIn();
  }

  Widget _buildAgentSignIn() => _card(children: [
        _backBtn(),
        const SizedBox(height: 4),
        Row(children: [
          const Icon(Icons.delivery_dining, color: kPrimary, size: 22),
          const SizedBox(width: 8),
          const Text('Delivery Agent',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 4),
        const Text('Sign in with your registered email and password.',
            style: TextStyle(fontSize: 12, color: kTextSub)),
        const SizedBox(height: 20),
        if (_err != null) _errBox(_err!),
        _emailField(),
        const SizedBox(height: 12),
        _passField(),
        const SizedBox(height: 20),
        _submitBtn('Sign In', _signIn),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 12),

        // ── New agent path ──────────────────────────────────────────────
        Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.person_add_outlined, size: 16, color: Colors.blue),
                SizedBox(width: 6),
                Text('First time here?',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.blue,
                        fontSize: 13)),
              ]),
              const SizedBox(height: 10),
              const Text(
                  '① Admin adds your name in the Agents screen\n'
                  '② Create your account here (one time only)\n'
                  '③ Link your name using the Company Code',
                  style:
                      TextStyle(fontSize: 12, color: Colors.blue, height: 1.7)),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                    child: ElevatedButton.icon(
                        onPressed: () => setState(() {
                              _agentSignUpMode = true;
                              _err = null;
                            }),
                        icon: const Icon(Icons.person_add, size: 16),
                        label: const Text('Create Account',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            minimumSize: const Size(0, 44)))),
                const SizedBox(width: 10),
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: () => context.go(R.agentLink),
                        icon: const Icon(Icons.link, size: 16),
                        label: const Text('Link Account',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.blue),
                            foregroundColor: Colors.blue,
                            minimumSize: const Size(0, 44)))),
              ]),
            ])),
      ]);

  Widget _buildAgentSignUp() => _card(children: [
        // Back to sign in
        GestureDetector(
            onTap: () => setState(() {
                  _agentSignUpMode = false;
                  _err = null;
                }),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.arrow_back_ios, size: 14, color: kTextSub),
              Text('Back to Sign In',
                  style: TextStyle(fontSize: 13, color: kTextSub)),
            ])),
        const SizedBox(height: 16),
        const Row(children: [
          Icon(Icons.person_add, color: kPrimary, size: 22),
          SizedBox(width: 8),
          Text('Create Agent Account',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 4),
        const Text('Create your login account (do this only once).',
            style: TextStyle(fontSize: 12, color: kTextSub)),
        const SizedBox(height: 20),

        // Steps
        Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade200)),
            child: const Text(
                '📋 After creating your account:\n'
                'Tap "Link Account" → enter Company Code + your name '
                'to connect to your trader company.',
                style:
                    TextStyle(fontSize: 12, color: Colors.brown, height: 1.5))),
        const SizedBox(height: 16),

        if (_err != null) _errBox(_err!),

        _emailField(),
        const SizedBox(height: 12),
        _passField(),
        const SizedBox(height: 12),

        // Confirm password
        TextField(
            controller: _confirmCtrl,
            obscureText: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
                labelText: 'Confirm Password',
                prefixIcon:
                    Icon(Icons.lock_outline, size: 20, color: kPrimary)),
            onSubmitted: (_) => _agentSignUpSubmit()),
        const SizedBox(height: 20),

        _submitBtn('Create My Account', _agentSignUpSubmit),
        const SizedBox(height: 10),
        Center(
            child: Text('Min 6 characters for password',
                style: TextStyle(fontSize: 11, color: kTextHint))),
      ]);

  Future<void> _agentSignUpSubmit() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (email.isEmpty) {
      setState(() => _err = 'Enter your email address');
      return;
    }
    if (pass.length < 6) {
      setState(() => _err = 'Password must be at least 6 characters');
      return;
    }
    if (_confirmCtrl.text != pass) {
      setState(() => _err = 'Passwords do not match');
      return;
    }

    if (mounted)
      setState(() {
        _busy = true;
        _err = null;
      });
    try {
      final res = await Supabase.instance.client.auth
          .signUp(email: email, password: pass);
      if (!mounted) return;
      if (res.user != null) {
        // Success — now go to link screen directly
        if (mounted) {
          showSuccess(context, 'Account created! Now link your agent name.');
          setState(() {
            _agentSignUpMode = false;
            _busy = false;
          });
          // Navigate to link screen with a short delay
          await Future.delayed(const Duration(milliseconds: 600));
          if (mounted) context.go(R.agentLink);
        }
      } else {
        setState(() {
          _err = 'Account may already exist. Try Sign In instead.';
          _busy = false;
        });
      }
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('rate limit') ||
          msg.contains('too many') ||
          msg.contains('over_email')) {
        // Likely already signed up — try signing in and redirect to link
        try {
          await Supabase.instance.client.auth
              .signInWithPassword(email: email, password: pass);
          if (mounted) {
            showSuccess(context, 'Account found! Now link your agent name.');
            setState(() {
              _busy = false;
            });
            context.go(R.agentLink);
          }
        } catch (_) {
          if (mounted)
            setState(() {
              _err =
                  'Account may already exist. Try sign in or wait a moment and retry.';
              _busy = false;
            });
        }
      } else if (msg.contains('already registered') ||
          msg.contains('already exists')) {
        setState(() {
          _err = 'Email already registered. Go back and Sign In instead.';
          _busy = false;
        });
      } else {
        setState(() {
          _err = e.message;
          _busy = false;
        });
      }
    } catch (_) {
      if (mounted)
        setState(() {
          _err = 'Connection failed. Check your internet.';
          _busy = false;
        });
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  Widget _card({required List<Widget> children}) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 4))
          ]),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: children));

  Widget _backBtn() => GestureDetector(
      onTap: _reset,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.arrow_back_ios, size: 14, color: kTextSub),
        const Text('Back', style: TextStyle(fontSize: 13, color: kTextSub)),
      ]));

  Widget _errBox(String msg) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.shade200)),
      child: Row(children: [
        const Icon(Icons.error_outline, color: kError, size: 16),
        const SizedBox(width: 8),
        Expanded(
            child:
                Text(msg, style: const TextStyle(color: kError, fontSize: 12))),
      ]));

  Widget _emailField() => TextField(
      controller: _emailCtrl,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(
          labelText: 'Email address',
          prefixIcon: Icon(Icons.email_outlined, size: 20, color: kPrimary)));

  Widget _passField() => TextField(
      controller: _passCtrl,
      obscureText: _hidePass,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _signIn(),
      decoration: InputDecoration(
          labelText: 'Password',
          prefixIcon: const Icon(Icons.lock_outline, size: 20, color: kPrimary),
          suffixIcon: IconButton(
              icon: Icon(
                  _hidePass
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                  color: kTextHint),
              onPressed: () => setState(() => _hidePass = !_hidePass))));

  Widget _submitBtn(String label, VoidCallback onTap) => SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
          onPressed: _busy ? null : onTap,
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white))
              : Text(label,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700))));
}

// ═══════════════════════════════════════════════════════════════════
// Trader Registration Sub-Widget
// ═══════════════════════════════════════════════════════════════════
class _TraderRegisterCard extends StatefulWidget {
  const _TraderRegisterCard({required this.onBack});

  final VoidCallback onBack;

  @override
  State<_TraderRegisterCard> createState() => _TRS();
}

class _TRS extends State<_TraderRegisterCard> {
  // Auth
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  // Company
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _personCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();

  int _page = 0; // 0=account, 1=company, 2=plan
  bool _busy = false;
  bool _hidePass = true;
  String? _err;
  String? _newUserId;
  String? _newUserEmail;
  Map<String, dynamic>? _selPlan;
  List<Map<String, dynamic>> _plans = [];

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _phoneCtrl.dispose();
    _personCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPlans() async {
    try {
      final res = await Supabase.instance.client
          .from('subscription_plans')
          .select(
              'id,name,duration_days,base_price,max_orders,max_retailers,max_agents,features')
          .eq('is_active', true)
          .order('base_price');
      if (mounted)
        setState(
            () => _plans = List<Map<String, dynamic>>.from(res as List? ?? []));
    } catch (_) {}
  }

  // Step 1: Create auth account
  // Uses GoTrue signUp first; falls back to direct DB creation on rate limit
  Future<void> _createAccount() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    final pass = _passCtrl.text;
    if (email.isEmpty) {
      setState(() => _err = 'Enter your email');
      return;
    }
    if (pass.length < 6) {
      setState(() => _err = 'Password must be 6+ characters');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });

    String? uid;

    try {
      // Try normal GoTrue signup first
      final res = await Supabase.instance.client.auth
          .signUp(email: email, password: pass);
      uid = res.user?.id;
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      final isRateLimit = m.contains('rate') ||
          m.contains('too many') ||
          m.contains('over_email');
      final isExists = m.contains('already') || m.contains('exists');

      if (isRateLimit || isExists) {
        // Try signing in — user may already exist
        try {
          final res2 = await Supabase.instance.client.auth
              .signInWithPassword(email: email, password: pass);
          uid = res2.user?.id;
        } catch (_) {}

        // If still no uid AND it was a rate limit, use direct DB creation (bypasses email)
        if (uid == null && isRateLimit) {
          try {
            final dbRes = await Supabase.instance.client
                .rpc('create_auth_user_direct', params: {
              'p_email': email,
              'p_password': pass,
            });
            final result = dbRes as Map<String, dynamic>;
            if (result['success'] == true) {
              uid = result['user_id'] as String?;
              // Now sign in with the newly created account
              if (uid != null) {
                try {
                  final signInRes = await Supabase.instance.client.auth
                      .signInWithPassword(email: email, password: pass);
                  uid = signInRes.user?.id ?? uid;
                } catch (_) {}
              }
            }
          } catch (dbErr) {
            if (mounted)
              setState(() {
                _err =
                    'Signup rate limit hit. Please wait 1 minute and try again.';
                _busy = false;
              });
            return;
          }
        }
      } else if (mounted) {
        setState(() {
          _err = m.contains('invalid') ? 'Invalid email format.' : e.message;
          _busy = false;
        });
        return;
      }
    } catch (_) {
      if (mounted)
        setState(() {
          _err = 'Connection failed. Check internet.';
          _busy = false;
        });
      return;
    }

    if (uid == null) {
      if (mounted)
        setState(() {
          _err = 'Account creation failed. Try again.';
          _busy = false;
        });
      return;
    }
    if (mounted)
      setState(() {
        _newUserId = uid;
        _newUserEmail = email;
        _page = 1;
        _busy = false;
      });
  }

  // Step 2+3: Create trader
  Future<void> _createTrader() async {
    final name = _nameCtrl.text.trim();
    final code = _codeCtrl.text.trim().toUpperCase();
    if (name.isEmpty) {
      setState(() => _err = 'Enter your company name');
      return;
    }
    if (code.length < 3) {
      setState(() => _err = 'Code must be at least 3 characters');
      return;
    }
    if (_newUserId == null) {
      setState(() => _err = 'Session lost. Go back and try again.');
      return;
    }

    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final res =
          await Supabase.instance.client.rpc('complete_trader_signup', params: {
        'p_user_id': _newUserId,
        'p_company_name': name,
        'p_company_code': code,
        'p_phone':
            _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        'p_contact_name':
            _personCtrl.text.trim().isEmpty ? null : _personCtrl.text.trim(),
        'p_city': _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
        'p_plan_id': _selPlan?['id'],
      });
      if (mounted) {
        // Auto sign in — session_provider will detect pending_approval and redirect
        if (Supabase.instance.client.auth.currentUser == null) {
          await Supabase.instance.client.auth.signInWithPassword(
              email: _newUserEmail!, password: _passCtrl.text);
        } else {
          // Already signed in from step 1 — just reload session
          // Router will see pending_approval and show correct screen
        }
        // Done — router handles redirect to pending screen
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _err = e
              .toString()
              .replaceAll('Exception: ', '')
              .replaceAll('PostgrestException(message: ', '')
              .replaceAll(')', '');
          _busy = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 4))
          ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
            onTap: widget.onBack,
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.arrow_back_ios, size: 14, color: kTextSub),
              Text('Back', style: TextStyle(fontSize: 13, color: kTextSub)),
            ])),
        const SizedBox(height: 12),

        // Step indicator
        Row(
            children: List.generate(
                3,
                (i) => Expanded(
                        child: Row(children: [
                      Expanded(
                          child: Container(
                              height: 4,
                              decoration: BoxDecoration(
                                  color: i <= _page ? kPrimary : kBorder,
                                  borderRadius: BorderRadius.circular(2)))),
                      if (i < 2) const SizedBox(width: 4),
                    ])))),
        const SizedBox(height: 16),

        if (_page == 0)
          ..._accountStep()
        else if (_page == 1)
          ..._companyStep()
        else
          ..._planStep(),
      ]));

  // Account step
  List<Widget> _accountStep() => [
        const Text('Create Account',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Step 1 of 3 — Your login email and password',
            style: TextStyle(fontSize: 12, color: kTextSub)),
        const SizedBox(height: 20),
        if (_err != null) _errBox(),
        TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
                labelText: 'Email address *',
                prefixIcon:
                    Icon(Icons.email_outlined, size: 20, color: kPrimary))),
        const SizedBox(height: 12),
        TextField(
            controller: _passCtrl,
            obscureText: _hidePass,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _createAccount(),
            decoration: InputDecoration(
                labelText: 'Password (min 6 chars) *',
                prefixIcon:
                    const Icon(Icons.lock_outline, size: 20, color: kPrimary),
                suffixIcon: IconButton(
                    icon: Icon(
                        _hidePass
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 18,
                        color: kTextHint),
                    onPressed: () => setState(() => _hidePass = !_hidePass)))),
        const SizedBox(height: 6),
        const Text('💡 Remember this — you will use it every day to sign in.',
            style: TextStyle(fontSize: 11, color: kTextSub)),
        const SizedBox(height: 20),
        _btn('Next: Company Details →', _createAccount),
      ];

  // Company step
  List<Widget> _companyStep() => [
        const Text('Your Company',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Step 2 of 3 — Your trading business details',
            style: TextStyle(fontSize: 12, color: kTextSub)),
        const SizedBox(height: 20),
        if (_err != null) _errBox(),
        TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
                labelText: 'Company / Shop Name *',
                hintText: 'e.g. Selvan Chicken Traders',
                prefixIcon:
                    Icon(Icons.business_outlined, size: 20, color: kPrimary))),
        const SizedBox(height: 12),
        TextField(
            controller: _codeCtrl,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
                labelText: 'Company Code * (min 3 chars)',
                hintText: 'e.g. SCT001',
                prefixIcon: Icon(Icons.tag, size: 20, color: kPrimary),
                helperText: 'Agents use this code to join your company'),
            onChanged: (v) {
              final u = v.toUpperCase().replaceAll(' ', '');
              if (v != u)
                _codeCtrl.value = TextEditingValue(
                    text: u,
                    selection: TextSelection.collapsed(offset: u.length));
            }),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                      labelText: 'Phone',
                      prefixIcon: Icon(Icons.phone_outlined,
                          size: 20, color: kPrimary)))),
          const SizedBox(width: 12),
          Expanded(
              child: TextField(
                  controller: _cityCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                      labelText: 'City',
                      prefixIcon: Icon(Icons.location_city_outlined,
                          size: 20, color: kPrimary)))),
        ]),
        const SizedBox(height: 20),
        _btn(
            'Next: Choose Plan →',
            () => setState(() {
                  _page = 2;
                  _err = null;
                })),
      ];

  // Plan step
  List<Widget> _planStep() => [
        const Text('Choose Plan',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Step 3 of 3 — All plans start with a 30-day free trial',
            style: TextStyle(fontSize: 12, color: kTextSub)),
        const SizedBox(height: 16),
        if (_err != null) _errBox(),
        ..._plans.map((p) {
          final price = (p['base_price'] as num?)?.toInt() ?? 0;
          final days = (p['duration_days'] as num?)?.toInt() ?? 30;
          final features = p['features'] as Map? ?? {};
          final isSelected = _selPlan?['id'] == p['id'];
          final isFree = price == 0;
          final isPremium = (p['name'] as String).toLowerCase() == 'premium';

          return GestureDetector(
              onTap: isPremium ? null : () => setState(() => _selPlan = p),
              child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: isPremium
                          ? Colors.purple.shade50
                          : (isSelected
                              ? kPrimary.withValues(alpha: 0.08)
                              : Colors.white),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: isPremium
                              ? Colors.purple.shade300
                              : isSelected
                                  ? kPrimary
                                  : kBorder,
                          width: isSelected || isPremium ? 2 : 1)),
                  child: Row(children: [
                    if (isSelected && !isPremium)
                      const Icon(Icons.check_circle, color: kPrimary, size: 20)
                    else if (isPremium)
                      const Icon(Icons.star_rounded,
                          color: Colors.purple, size: 20)
                    else
                      const Icon(Icons.circle_outlined,
                          color: kBorder, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Row(children: [
                            Text(p['name'] as String,
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: isPremium
                                        ? Colors.purple
                                        : (isSelected ? kPrimary : kTextMain))),
                            if (isFree)
                              Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: Colors.green,
                                      borderRadius: BorderRadius.circular(4)),
                                  child: const Text('FREE',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800))),
                          ]),
                          const SizedBox(height: 3),
                          if (isPremium)
                            const Text(
                                'Contact us for custom pricing & unlimited scale',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.purple))
                          else
                            Text(
                                isFree
                                    ? '30 days free, no credit card needed'
                                    : '₹$price for $days days',
                                style: const TextStyle(
                                    fontSize: 11, color: kTextSub)),
                          const SizedBox(height: 4),
                          Wrap(spacing: 8, children: [
                            if (features['dc_upload'] == true)
                              _featureChip('📸 DC Upload'),
                            if (features['loss_tracking'] == true)
                              _featureChip('⚖️ Loss Track'),
                            _featureChip(
                                '📊 ${features['reports'] ?? 'basic'} reports'),
                          ]),
                        ])),
                    if (isPremium)
                      OutlinedButton(
                          onPressed: () {},
                          style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.purple,
                              side: const BorderSide(color: Colors.purple),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6)),
                          child: const Text('Contact',
                              style: TextStyle(fontSize: 11))),
                  ])));
        }),
        const SizedBox(height: 20),
        _btn('✅ Register My Company', _createTrader),
        const SizedBox(height: 8),
        const Text(
            'Your account will be reviewed by admin. You can use the app during the free trial.',
            style: TextStyle(fontSize: 11, color: kTextSub),
            textAlign: TextAlign.center),
      ];

  Widget _featureChip(String label) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: kPrimary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(4)),
      child: Text(label,
          style: const TextStyle(
              fontSize: 9, color: kPrimary, fontWeight: FontWeight.w600)));

  Widget _errBox() => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        const Icon(Icons.error_outline, color: kError, size: 16),
        const SizedBox(width: 8),
        Expanded(
            child: Text(_err!,
                style: const TextStyle(color: kError, fontSize: 12))),
      ]));

  Widget _btn(String label, VoidCallback onTap) => SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
          onPressed: _busy ? null : onTap,
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white))
              : Text(label,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700))));
}
