import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/responsive_layout.dart';

class UserManagementScreen extends ConsumerStatefulWidget {
  const UserManagementScreen({super.key});
  @override ConsumerState<UserManagementScreen> createState() => _S();
}

class _S extends ConsumerState<UserManagementScreen> {
  final _c = Supabase.instance.client;
  List<Map<String,dynamic>> _users = [];
  List<Map<String,dynamic>> _filtered = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  void _applySearch(String q) {
    if (!mounted) return;
    final lower = q.trim().toLowerCase();
    setState(() => _filtered = lower.isEmpty
        ? List.from(_users)
        : _users.where((u) =>
            (u['email'] as String? ?? '').toLowerCase().contains(lower) ||
            (u['role']  as String? ?? '').toLowerCase().contains(lower),
          ).toList());
  }

  @override void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => _applySearch(_searchCtrl.text));
  }
  @override void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    if (mounted) setState(() => _loading = true);
    try {
      final res = await _c.rpc('get_all_users_with_roles', params: {'p_trader_id': tid});
      if (!mounted) return;
      setState(() {
        _users   = List<Map<String,dynamic>>.from(res as List? ?? []);
        _loading = false;
        _applySearch(_searchCtrl.text);
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _assign(Map<String,dynamic> user) async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;

    String selectedRole = user['role'] as String? ?? 'delivery_staff';
    bool isActive = user['is_active'] as bool? ?? true;

    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) => AlertDialog(
          title: Text(user['email'] as String),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Role', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kTextSub)),
            const SizedBox(height: 8),
            // Role selector
            ...{
              'trader_admin':   ('👔 Trader Admin',   'Full access — manage orders, agents, reports'),
              'delivery_staff': ('🚛 Delivery Staff',  'Agent app — pickup, deliver, shift management'),
              'accountant':     ('📊 Accountant',      'View reports, approve invoices, manage ledger'),
              'supervisor':     ('🔍 Supervisor',      'View all operations, no financial access'),
            }.entries.map((e) => InkWell(
                onTap: () => setSt(() => selectedRole = e.key),
                child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: selectedRole == e.key ? kPrimary.withValues(alpha: 0.1) : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: selectedRole == e.key ? kPrimary : Colors.grey.shade200,
                            width: selectedRole == e.key ? 2 : 1)),
                    child: Row(children: [
                      if (selectedRole == e.key)
                        const Icon(Icons.check_circle, color: kPrimary, size: 18)
                      else
                        const Icon(Icons.radio_button_unchecked, color: kTextHint, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e.value.$1, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        Text(e.value.$2, style: const TextStyle(fontSize: 11, color: kTextSub)),
                      ])),
                    ]))),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Switch(value: isActive, onChanged: (v) => setSt(() => isActive = v)),
              const SizedBox(width: 8),
              Text(isActive ? 'Active — can log in' : 'Inactive — access blocked',
                  style: TextStyle(fontSize: 13,
                      color: isActive ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w600)),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(user['role_exists'] == true ? 'Update Role' : 'Assign Role')),
          ],
        )));

    if (ok != true || !mounted) return;

    try {
      await _c.rpc('assign_user_role', params: {
        'p_target_user_id': user['user_id'],
        'p_trader_id':      tid,
        'p_role':           selectedRole,
        'p_is_active':      isActive,
      });
      if (mounted) showSuccess(context, 'Role updated ✓ — ${user['email']}');
      _load();
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _remove(Map<String,dynamic> user) async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    final ok = await confirmDialog(context,
        title: 'Remove Access',
        message: 'Remove role for ${user['email']}?\n\nThey will no longer be able to log in.',
        confirmText: 'Remove', confirmColor: Colors.red);
    if (!ok || !mounted) return;
    try {
      await _c.rpc('remove_user_role', params: {
        'p_target_user_id': user['user_id'],
        'p_trader_id':      tid,
      });
      if (mounted) showSuccess(context, 'Access removed ✓');
      _load();
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  Widget _buildScaffold(BuildContext context) {
    final unassigned = _filtered.where((u) => u['role_exists'] != true).toList();
    final assigned   = _filtered.where((u) => u['role_exists'] == true).toList();

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: const Text('User Management'),
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      ),
      body: Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: AppSearchBar(
            controller: _searchCtrl,
            hint: 'Search by email or role…',
            onChanged: _applySearch,
            onClear: () { _searchCtrl.clear(); _applySearch(''); },
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _loading
          ? const LoadingList()
          : _users.isEmpty
          ? const EmptyState(icon: Icons.people_outline, message: 'No users found')
          : RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, kBottomNavClearance), children: [
            Container(
                padding: const EdgeInsets.all(18),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [kNavy, kNavyMid], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(kRadiusCard)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Icon(Icons.info_outline, color: kGoldLight, size: 18),
                    SizedBox(width: 8),
                    Text('How to add users', style: TextStyle(fontWeight: FontWeight.w800, color: kGoldLight)),
                  ]),
                  const SizedBox(height: 8),
                  const Text(
                      '1. Create the user in Supabase Dashboard → Authentication → Users\n'
                          '2. Come here and tap "Assign Role" on the new user\n'
                          '3. Select their role and tap Update\n\n'
                          'For delivery agents: they can self-register and link via company code RT001',
                      style: const TextStyle(fontSize: 12, color: Color(0xFFB4C6F4), height: 1.6)),
                ])),

            // ── Unassigned users (need attention) ───────────
            if (unassigned.isNotEmpty) ...[
              Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(kRadiusCard),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.3))),
                  child: Row(children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
                    const SizedBox(width: 8),
                    Text('${unassigned.length} user${unassigned.length > 1 ? 's' : ''} without a role — they cannot log in',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange)),
                  ])),
              const SizedBox(height: 10),
              ...unassigned.map((u) => _userCard(u, unassigned: true)),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
            ],

            // ── Assigned users ──────────────────────────────
            Text('ASSIGNED USERS (${assigned.length})',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    color: kTextHint, letterSpacing: 0.8)),
            const SizedBox(height: 10),
            ...assigned.map((u) => _userCard(u, unassigned: false)),
            const SizedBox(height: 20),
          ])),
        ),
      ]),
    );
  }

  Widget _userCard(Map<String,dynamic> u, {required bool unassigned}) {
    final role     = u['role'] as String?;
    final isActive = u['is_active'] as bool? ?? false;
    final email    = u['email'] as String? ?? '—';
    final created  = u['created_at'] as String?;

    final roleColor = switch (role) {
      'trader_admin'   => kPrimary,
      'delivery_staff' => Colors.teal,
      'accountant'     => Colors.purple,
      'supervisor'     => Colors.orange,
      _                => Colors.grey,
    };
    final roleLabel = switch (role) {
      'trader_admin'   => '👔 Trader Admin',
      'delivery_staff' => '🚛 Delivery Staff',
      'accountant'     => '📊 Accountant',
      'supervisor'     => '🔍 Supervisor',
      _                => '⚠️ No Role',
    };

    return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(kRadiusCard),
            border: Border.all(
                color: unassigned ? Colors.orange.withValues(alpha: 0.4) : kBorderLight,
                width: unassigned ? 1.5 : 0.8),
            boxShadow: kCardShadow),
        child: Row(children: [
          // Avatar
          Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                  color: unassigned ? Colors.orange.withValues(alpha: 0.1) : roleColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(kRadiusChip)),
              child: Center(child: Text(
                  email.isNotEmpty ? email[0].toUpperCase() : '?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                      color: unassigned ? Colors.orange : roleColor)))),
          const SizedBox(width: 12),
          // Info
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(email, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Row(children: [
              Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: roleColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(kRadiusChip)),
                  child: Text(roleLabel,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: roleColor))),
              if (!unassigned) ...[
                const SizedBox(width: 6),
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: isActive ? kSuccess.withValues(alpha: 0.08) : kError.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(kRadiusChip)),
                    child: Text(isActive ? 'Active' : 'Inactive',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                            color: isActive ? Colors.green : Colors.red))),
              ],
            ]),
            if (created != null) Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('Joined ${_fmtDate(created)}',
                    style: const TextStyle(fontSize: 10, color: kTextHint))),
          ])),
          // Actions
          Column(children: [
            ElevatedButton(
                onPressed: () => _assign(u),
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    backgroundColor: unassigned ? Colors.orange : kPrimary),
                child: Text(unassigned ? 'Assign Role' : 'Edit',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
            if (!unassigned) ...[
              const SizedBox(height: 4),
              TextButton(
                  onPressed: () => _remove(u),
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
                  child: const Text('Remove', style: TextStyle(fontSize: 11, color: Colors.red))),
            ],
          ]),
        ]));
  }

  String _fmtDate(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) { return iso; }
  }
  @override
  Widget build(BuildContext context) => ResponsiveLayout(
    mobile:  (_) => _buildScaffold(context),
    desktop: (_) => _buildScaffold(context),
  );

}