import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

/// Mirrors create_agent_screen.dart's two-step "create unlinked row, then
/// share the company code" pattern — the supervisor links themselves via
/// supervisor_link_screen.dart exactly like a delivery agent does today.
/// Unlike delivery agents, this goes through an RPC (create_supervisor_
/// profile) rather than a raw insert, specifically so the Plug & Play
/// module flag is enforced server-side too — this screen also hides
/// itself entirely when the flag is off (see settings_screen.dart), so
/// reaching here with the module disabled should be rare, but the RPC
/// guard means it's never just a client-side illusion of being blocked.
class CreateSupervisorScreen extends ConsumerStatefulWidget {
  const CreateSupervisorScreen({super.key});
  @override ConsumerState<CreateSupervisorScreen> createState() => _S();
}

class _S extends ConsumerState<CreateSupervisorScreen> {
  final _c = Supabase.instance.client;
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  bool _submitting = false;

  List<Map<String, dynamic>> _retailers = [];
  final Set<String> _selectedRetailers = {};
  bool _loadingRetailers = true;

  @override void initState() { super.initState(); _loadRetailers(); }
  @override void dispose() { _name.dispose(); _mobile.dispose(); super.dispose(); }

  Future<void> _loadRetailers() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    try {
      final r = await _c.from('retailers').select('id,shop_name')
          .eq('trader_id', tid!).eq('is_active', true).order('shop_name').limit(5000);
      if (mounted) setState(() { _retailers = List<Map<String, dynamic>>.from(r as List? ?? []); _loadingRetailers = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingRetailers = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (mounted) setState(() => _submitting = true);
    try {
      final res = await _c.rpc('create_supervisor_profile', params: {
        'p_trader_id': tid,
        'p_name':      _name.text.trim(),
        'p_mobile':    _mobile.text.trim().isEmpty ? null : _mobile.text.trim(),
      });
      final newId = res is String ? res : res.toString();

      if (_selectedRetailers.isNotEmpty) {
        await _c.from('retailers')
            .update({'supervisor_id': newId})
            .inFilter('id', _selectedRetailers.toList());
      }

      if (mounted) {
        showSuccess(context, 'Supervisor added! Share your Company Code with them.');
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(R.userMgmt);
        }
      }
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = ref.watch(appUserProvider).valueOrNull?.companyCode ?? '—';
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(backgroundColor: kSurface, title: const Text('Add Supervisor')),
      body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
          child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [kNavy, kNavyMid],
                            begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(kRadiusCard)),
                    child: Text(
                        '① Fill supervisor name & mobile, pick assigned retailers, and save.\n'
                            '② Share Company Code with them: $code\n'
                            '③ They open the app → Login → "I am a Supervisor" → Sign Up → "Link Supervisor Account" → enter code + their name.\n'
                            '④ Linked and can log in.',
                        style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.5))),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Supervisor Name *'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _mobile,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Mobile'),
                ),
                const SizedBox(height: 20),
                const Text('ASSIGN RETAILERS (optional — can be changed later)',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kTextHint, letterSpacing: 0.5)),
                const SizedBox(height: 8),
                _loadingRetailers
                    ? const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
                    : Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  decoration: BoxDecoration(border: Border.all(color: kBorderLight), borderRadius: BorderRadius.circular(kRadiusCard)),
                  child: _retailers.isEmpty
                      ? const Padding(padding: EdgeInsets.all(16), child: Text('No retailers yet.', style: TextStyle(color: kTextHint)))
                      : ListView(shrinkWrap: true, children: _retailers.map((r) {
                    final id = r['id'] as String;
                    return CheckboxListTile(
                      dense: true,
                      value: _selectedRetailers.contains(id),
                      title: Text(r['shop_name'] as String? ?? '—', style: const TextStyle(fontSize: 13)),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selectedRetailers.add(id);
                        } else {
                          _selectedRetailers.remove(id);
                        }
                      }),
                    );
                  }).toList()),
                ),
                const SizedBox(height: 24),
                SizedBox(height: 52, child: ElevatedButton(
                  onPressed: _submitting ? null : _save,
                  child: _submitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save Supervisor', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                )),
              ]))),
    );
  }
}