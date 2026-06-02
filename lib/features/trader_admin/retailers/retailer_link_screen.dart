import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RETAILER LINK SCREEN
// Shown after OTP login when the user has role=retailer_user but no retailer_id.
// Retailer enters the 6-character invite code given by their supplier (trader).
// ─────────────────────────────────────────────────────────────────────────────
class RetailerLinkScreen extends ConsumerStatefulWidget {
  const RetailerLinkScreen({super.key});
  @override ConsumerState<RetailerLinkScreen> createState() => _RLS();
}

class _RLS extends ConsumerState<RetailerLinkScreen> {
  final _c        = Supabase.instance.client;
  final _codeCtrl = TextEditingController();
  bool _loading   = false;
  String? _error;
  String? _success;

  Future<void> _claimInvite() async {
    final code  = _codeCtrl.text.trim().toUpperCase();
    final phone = _c.auth.currentUser?.phone ?? '';

    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-character code from your supplier');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      final uid = _c.auth.currentUser?.id;
      if (uid == null) throw Exception('Not logged in');

      final result = await _c.rpc('claim_retailer_invite', params: {
        'p_invite_code': code,
        'p_phone':       phone,
        'p_user_id':     uid,
      }).timeout(const Duration(seconds: 12));

      final data = result as Map<String,dynamic>;
      if (data['success'] == true) {
        setState(() => _success = 'Linked to ${data['shop_name']}!');
        // Reload session so retailer_id gets resolved
        await ref.read(appUserProvider.notifier).reload();
        if (mounted) context.go(R.retailerHome);
      }
    } catch (e) {
      setState(() => _error = e.toString()
          .replaceAll('Exception: ', '')
          .replaceAll('PostgrestException: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: kBgPage,
      body: SafeArea(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 40),

                    // Logo / icon
                    Center(child: Container(
                        width: 80, height: 80,
                        decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [kNavy, kNavyMid], begin: Alignment.topLeft, end: Alignment.bottomRight),
                            shape: BoxShape.circle,
                            boxShadow: kCardShadow),
                        child: const Icon(Icons.store_outlined, size: 38, color: kGoldLight))),

                    const SizedBox(height: 24),

                    const Center(child: Text('Enter Supplier Code',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: kNavy))),

                    const SizedBox(height: 8),

                    Center(child: Text(
                        'Your supplier (trader) will share a 6-character code with you.\n'
                            'Enter it below to link your account.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13, color: kTextSub, height: 1.4))),

                    const SizedBox(height: 40),

                    // Code input
                    TextField(
                        controller: _codeCtrl,
                        maxLength: 6,
                        textCapitalization: TextCapitalization.characters,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 28, fontWeight: FontWeight.w900,
                            letterSpacing: 8),
                        decoration: InputDecoration(
                            counterText: '',
                            hintText: 'XXXXXX',
                            hintStyle: const TextStyle(letterSpacing: 8, color: kTextHint),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(kRadiusCard),
                                borderSide: const BorderSide(color: kBorderLight)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(kRadiusCard),
                                borderSide: const BorderSide(color: kNavy, width: 2))),
                        onChanged: (v) {
                          setState(() => _error = null);
                          if (v.length == 6) _claimInvite();
                        }),

                    const SizedBox(height: 16),

                    if (_error != null) Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: kErrorBg,
                            borderRadius: BorderRadius.circular(kRadiusCard),
                            border: Border.all(color: kError.withValues(alpha: 0.3))),
                        child: Row(children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 16),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_error!,
                              style: const TextStyle(color: Colors.red, fontSize: 12))),
                        ])),

                    if (_success != null) Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: kSuccess.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(kRadiusCard),
                            border: Border.all(color: kSuccess.withValues(alpha: 0.25))),
                        child: Row(children: [
                          const Icon(Icons.check_circle_outline, color: Colors.green, size: 16),
                          const SizedBox(width: 8),
                          Text(_success!, style: const TextStyle(color: Colors.green, fontSize: 12)),
                        ])),

                    const SizedBox(height: 24),

                    ElevatedButton(
                        onPressed: _loading ? null : _claimInvite,
                        style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 52),
                            backgroundColor: kPrimary),
                        child: _loading
                            ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('Link Account',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),

                    const Spacer(),

                    // Help text
                    Center(child: Column(children: [
                      const Text("Don't have a code?",
                          style: TextStyle(fontSize: 12, color: kTextHint)),
                      const SizedBox(height: 4),
                      const Text(
                          'Contact your poultry supplier and ask them to share your invite code from Rooster Trader.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: kTextHint)),
                      const SizedBox(height: 16),
                      TextButton(
                          onPressed: () async {
                            await _c.auth.signOut();
                            if (mounted) context.go(R.login);
                          },
                          child: const Text('Sign out',
                              style: TextStyle(color: kTextHint, fontSize: 12))),
                    ])),
                  ]))));
}