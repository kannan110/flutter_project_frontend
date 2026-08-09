import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:rooster_trader/features/trader_admin/retailers/retailer_openinh_balancesheet.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class RetailerDetailScreen extends ConsumerStatefulWidget {
  const RetailerDetailScreen({super.key, required this.id});

  final String id;

  @override ConsumerState<RetailerDetailScreen> createState() => _S();
}

class _S extends ConsumerState<RetailerDetailScreen> {
  final _c = Supabase.instance.client;
  Map<String, dynamic>? _r;
  bool _loading = true,
      _editing = false,
      _saving = false;

  // Edit controllers
  late TextEditingController _shopNameCtrl;
  late TextEditingController _ownerCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _creditCtrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _shopNameCtrl.dispose();
    _ownerCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _creditCtrl.dispose();
    super.dispose();
  }

  double _outstanding = 0;
  List<Map<String, dynamic>> _recentOrders = [];

  // Phase 1: opening balance state
  Map<String, dynamic>? _obInfo;         // from get_retailer_opening_balance

  // Phase 2: credit history state
  List<Map<String, dynamic>> _creditHistory = [];
  bool _loadingHistory = false;
  bool _historyLoaded  = false;   // lazy-load on first expand
  bool _showHistory    = false;

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait<dynamic>([
        _c.from('retailers')
            .select('*')
            .eq('id', widget.id)
            .maybeSingle(),

        _c.rpc('get_retailer_outstanding',
            params: {'p_retailer_id': widget.id}),

        _c.from('orders')
            .select(
            'id,status,estimated_birds,total_quantity,total_amount,created_at')
            .eq('retailer_id', widget.id)
            .order('created_at', ascending: false)
            .limit(5),

        // Phase 1: opening balance info
        _c.rpc('get_retailer_opening_balance',
            params: {'p_retailer_id': widget.id}),
      ]);

      final retailer = results[0] as Map<String, dynamic>?;
      final outstanding = results[1]; // refine based on your RPC return
      final orders = (results[2] as List)
          .cast<Map<String, dynamic>>();
      final r = results[0] as Map<String, dynamic>?;
      if (mounted) {
        _shopNameCtrl =
            TextEditingController(text: r?['shop_name'] as String? ?? '');
        _ownerCtrl =
            TextEditingController(text: r?['owner_name'] as String? ?? '');
        _phoneCtrl = TextEditingController(text: r?['phone'] as String? ?? '');
        _addressCtrl =
            TextEditingController(text: r?['address'] as String? ?? '');
        _creditCtrl = TextEditingController(
            text: '${(r?['credit_limit'] as num?)?.toInt() ?? 100000}');
        setState(() {
          _r = r;
          _outstanding = (results[1] as num?)?.toDouble() ?? 0;
          _recentOrders =
          List<Map<String, dynamic>>.from(results[2] as List? ?? []);
          // Phase 1: opening balance
          _obInfo = results[3] as Map<String, dynamic>?;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_shopNameCtrl.text
        .trim()
        .isEmpty) {
      showError(context, 'Shop name required');
      return;
    }
    if (mounted) setState(() => _saving = true);
    try {
      await _c.from('retailers').update({
        'shop_name': _shopNameCtrl.text.trim(),
        'owner_name': _ownerCtrl.text
            .trim()
            .isEmpty ? null : _ownerCtrl.text.trim(),
        'phone': _phoneCtrl.text
            .trim()
            .isEmpty ? null : _phoneCtrl.text.trim(),
        'address': _addressCtrl.text
            .trim()
            .isEmpty ? null : _addressCtrl.text.trim(),
        'credit_limit': double.tryParse(_creditCtrl.text.trim()) ?? 100000,
      }).eq('id', widget.id);
      if (mounted) {
        showSuccess(context, 'Customer updated ✓');
        setState(() => _editing = false);
        _load();
      }
    } catch (e) {
      if (mounted) showError(
          context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleActive() async {
    final isActive = _r?['is_active'] as bool? ?? true;
    final ok = await confirmDialog(context,
        title: isActive ? 'Deactivate Customer' : 'Activate Customer',
        message: isActive
            ? 'This will hide ${_r?['shop_name']} from new orders.'
            : 'Reactivate ${_r?['shop_name']}?',
        confirmText: isActive ? 'Deactivate' : 'Activate',
        confirmColor: isActive ? Colors.red : kPrimary);
    if (!ok) return;
    try {
      await _c.from('retailers').update({'is_active': !isActive}).eq(
          'id', widget.id);
      if (mounted) {
        showSuccess(context, isActive ? 'Deactivated' : 'Activated');
        _load();
      }
    } catch (e) {
      if (mounted) showError(context, e.toString());
    }
  }

  // Phase 2: lazy-load credit history when section is expanded
  Future<void> _loadCreditHistory() async {
    if (mounted) setState(() => _loadingHistory = true);
    try {
      final res = await _c.rpc('get_retailer_credit_history', params: {
        'p_retailer_id': widget.id,
        'p_limit':       50,
      });
      if (mounted) {
        setState(() {
          _creditHistory = List<Map<String, dynamic>>.from(res as List? ?? []);
          _historyLoaded = true;
          _loadingHistory = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  // Create retailer auth account using DB function ONLY.
  // CRITICAL: Never use auth.signUp() here — it hijacks trader's session
  // causing go_router crash: 'currentConfiguration.isNotEmpty'.
  Future<void> _createAppAccount(
      String retailerId, String phone, String shopName) async {
    final emailCtrl = TextEditingController(
        text: phone.isNotEmpty
            ? phone.replaceAll(' ', '').replaceAll('-', '') + '@rt.app'
            : '');
    final passCtrl = TextEditingController();
    bool busy = false;

    await showDialog(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => AlertDialog(
            title: const Text('Create App Account'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Create login for $shopName',
                  style: const TextStyle(fontSize: 12, color: kTextSub)),
              const SizedBox(height: 8),
              Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                  child: const Text('Retailer uses this email and password to log in.',
                      style: TextStyle(fontSize: 11, color: Colors.blue))),
              const SizedBox(height: 12),
              TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                      labelText: 'Email *', isDense: true)),
              const SizedBox(height: 8),
              TextField(
                  controller: passCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Password (min 6 chars)', isDense: true)),
              const SizedBox(height: 4),
              const Text('Share these credentials via WhatsApp.',
                  style: TextStyle(fontSize: 10, color: kTextHint)),
            ]),
            actions: [
              TextButton(
                  onPressed: busy ? null
                      : () => Navigator.of(ctx, rootNavigator: true).pop(),
                  child: const Text('Cancel')),
              ElevatedButton(
                  onPressed: busy ? null : () async {
                    final email = emailCtrl.text.trim();
                    final pass  = passCtrl.text.trim();
                    if (email.isEmpty || !email.contains('@')) {
                      showError(context, 'Enter a valid email'); return;
                    }
                    if (pass.length < 6) {
                      showError(context, 'Password must be at least 6 characters'); return;
                    }
                    ss(() => busy = true);
                    try {
                      // DB function only — trader session is NEVER touched
                      await _c.rpc('create_retailer_auth_account', params: {
                        'p_retailer_id': retailerId,
                        'p_email':       email,
                        'p_password':    pass,
                      });
                      _load();
                      Navigator.of(ctx, rootNavigator: true).pop();
                      if (mounted) {
                        showSuccess(context,
                            'Account created for $shopName!  '
                                'Share: Email: $email  Password: $pass  '
                                'Retailer opens app, taps Retailer Login, '
                                'signs in, then enters the invite code.');
                      }
                    } catch (e) {
                      ss(() => busy = false);
                      if (mounted) showError(context,
                          e.toString().replaceAll('Exception: ', '')
                              .replaceAll('PostgrestException: ', ''));
                    }
                  },
                  child: busy
                      ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Create Account')),
            ])));
  }
  Future<void> _generateInvite(String retailerId) async {
    try {
      final result = await _c.rpc('generate_retailer_invite',
          params: {'p_retailer_id': retailerId})
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      final data = result as Map<String,dynamic>;
      final code = data['invite_code'] as String;
      final phone = data['phone'] as String;
      // Show invite code in a dialog
      showDialog(
          context: context,
          useRootNavigator: true,
          builder: (ctx) => AlertDialog(
              title: const Text('Invite Code Generated'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Share this code with your retailer:',
                    style: TextStyle(fontSize: 12, color: kTextSub)),
                const SizedBox(height: 16),
                Container(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                    decoration: BoxDecoration(
                        color: kPrimary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12)),
                    child: Text(code,
                        style: const TextStyle(
                            fontSize: 32, fontWeight: FontWeight.w900,
                            letterSpacing: 8, color: kPrimary))),
                const SizedBox(height: 12),
                Text('Phone: $phone',
                    style: const TextStyle(fontSize: 12, color: kTextSub)),
                const SizedBox(height: 8),
                const Text(
                    'Retailer opens Rooster Trader app, logs in with OTP, then enters this code.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: kTextHint)),
                const SizedBox(height: 4),
                const Text('Code expires in 30 days.',
                    style: TextStyle(fontSize: 10, color: kTextHint)),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(),
                    child: const Text('Close')),
              ]));
      _load(); // Refresh to show app_enabled=true
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingList());
    if (_r == null) return Scaffold(
        appBar: AppBar(), body: const Center(child: Text('Not found')));
    final r = _r!;
    final isActive = r['is_active'] as bool? ?? true;

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: Text(_editing ? 'Edit Customer' : (r['shop_name'] as String)),
        actions: [
          if (!_editing) ...[
            TextButton.icon(
                onPressed: () => setState(() => _editing = true),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit')),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          ] else
            ...[
              TextButton(
                  onPressed: () => setState(() => _editing = false),
                  child: const Text(
                      'Cancel', style: TextStyle(color: Colors.red))),
              TextButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text(
                      'Save', style: TextStyle(fontWeight: FontWeight.w700))),
            ],
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, kBottomNavClearance), children: [
        Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
                color: (r['app_enabled'] as bool? ?? false)
                    ? Colors.green.shade50 : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: (r['app_enabled'] as bool? ?? false)
                        ? Colors.green.shade200 : Colors.grey.shade300)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.smartphone_outlined,
                    size: 16,
                    color: (r['app_enabled'] as bool? ?? false)
                        ? Colors.green : Colors.grey),
                const SizedBox(width: 8),
                Text((r['app_enabled'] as bool? ?? false)
                    ? 'App Access: Enabled' : 'App Access: Not Set Up',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800,
                        color: (r['app_enabled'] as bool? ?? false)
                            ? Colors.green : Colors.grey)),
              ]),
              const SizedBox(height: 4),
              Text(
                  (r['app_enabled'] as bool? ?? false)
                      ? 'This retailer can log in to the Rooster Trader retailer app.'
                      : 'Generate an invite code to let this retailer log in to the app.',
                  style: const TextStyle(fontSize: 11, color: kTextSub)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: ElevatedButton.icon(
                    onPressed: () => _createAppAccount(
                        r['id'] as String,
                        r['phone'] as String? ?? '',
                        r['shop_name'] as String? ?? ''),
                    icon: const Icon(Icons.person_add_outlined, size: 14),
                    label: const Text('Create App Account',
                        style: TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        backgroundColor: Colors.blue))),
                const SizedBox(width: 8),
                Expanded(child: ElevatedButton.icon(
                    onPressed: (r['phone'] as String?) == null ||
                        (r['phone'] as String? ?? '').isEmpty
                        ? null
                        : () => _generateInvite(r['id'] as String),
                    icon: const Icon(Icons.vpn_key_outlined, size: 14),
                    label: Text(
                        (r['app_enabled'] as bool? ?? false)
                            ? 'New Invite Code' : 'Generate Invite',
                        style: const TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        backgroundColor: kPrimary))),
              ]),
              if ((r['phone'] as String?) == null || (r['phone'] as String? ?? '').isEmpty)
                const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('Add a phone number first.',
                        style: TextStyle(fontSize: 10, color: Colors.orange))),
            ])),

        if (!isActive) Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade200)),
            child: const Row(children: [
              Icon(Icons.block, color: Colors.red, size: 16), SizedBox(width: 8),
              Text('This customer is deactivated', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 13)),
            ])),

        if (_editing) ...[
          const SectionHeader('SHOP DETAILS'),
          TextField(controller: _shopNameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Shop Name *')),
          const SizedBox(height: 10),
          TextField(controller: _ownerCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Owner Name')),
          const SizedBox(height: 10),
          TextField(controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone', prefixIcon: Icon(Icons.phone_outlined, size: 18))),
          const SizedBox(height: 10),
          TextField(controller: _addressCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Address', alignLabelWithHint: true)),
          const SizedBox(height: 16),
          const SectionHeader('CREDIT LIMIT'),
          TextField(controller: _creditCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Credit Limit (₹)', prefixText: '₹',
                  helperText: 'Maximum credit allowed for this customer')),
          const SizedBox(height: 24),
          ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Text('Save Changes')),
        ] else ...[
          WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionHeader('CUSTOMER DETAILS'),
            InfoRow('Shop', r['shop_name'] as String),
            if (r['owner_name'] != null) InfoRow('Owner', r['owner_name'] as String),
            if (r['phone'] != null) InfoRow('Phone', r['phone'] as String),
            if (r['address'] != null) InfoRow('Address', r['address'] as String),
            InfoRow('Status', isActive ? 'Active' : 'Inactive',
                valueColor: isActive ? kPrimary : Colors.red),
            InfoRow('Credit Limit', Fmt.amount((r['credit_limit'] as num?)?.toDouble() ?? 0)),
            InfoRow('Risk Level', (r['risk_level'] as String? ?? 'low').toUpperCase()),
          ])),
          const SizedBox(height: 16),

              () {
            final obAmt  = (_obInfo?['opening_balance'] as num?)?.toDouble() ?? 0;
            final obDate = _obInfo?['opening_balance_date'] as String?;
            final obNote = _obInfo?['opening_balance_note'] as String?;
            final hasEntry = _obInfo?['has_opening_entry'] as bool? ?? false;

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: obAmt > 0 ? Colors.orange.shade50 : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: obAmt > 0 ? Colors.orange.shade300 : Colors.grey.shade300,
                  width: obAmt > 0 ? 1.5 : 1,
                ),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                  child: Row(children: [
                    Icon(Icons.account_balance_wallet_outlined,
                        size: 16,
                        color: obAmt > 0 ? Colors.orange.shade700 : kTextSub),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Opening Balance',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                            color: obAmt > 0 ? Colors.orange.shade800 : kTextSub))),
                    // Opening Balance Enhancement: editing is always allowed,
                    // even after invoices/payments/ledger entries exist —
                    // the backend (set_retailer_opening_balance) now handles
                    // this safely via an append-only compensating entry, so
                    // the UI no longer needs to gate on invoice existence.
                    TextButton.icon(
                      onPressed: () => showRetailerOpeningBalanceSheet(
                        context,
                        retailerId: widget.id,
                        shopName: r['shop_name'] as String? ?? 'Customer',
                        currentAmount: obAmt,
                        currentDate: obDate,
                        currentNote: obNote,
                        onSaved: _load,
                      ),
                      icon: const Icon(Icons.edit_outlined, size: 14),
                      label: Text(obAmt > 0 ? 'Edit' : 'Set',
                          style: const TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.orange.shade700,
                          minimumSize: const Size(0, 30),
                          padding: const EdgeInsets.symmetric(horizontal: 8)),
                    ),
                  ]),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: obAmt > 0 ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(Fmt.amount(obAmt),
                          style: TextStyle(fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Colors.orange.shade700)),
                      if (obDate != null) ...[
                        const SizedBox(height: 2),
                        Text('As of $obDate',
                            style: const TextStyle(fontSize: 11, color: kTextSub)),
                      ],
                      if (obNote != null && obNote.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(obNote,
                            style: const TextStyle(fontSize: 11, color: kTextHint)),
                      ],
                    ],
                  ) : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('No opening balance set',
                          style: TextStyle(fontSize: 13, color: kTextSub)),
                      const SizedBox(height: 2),
                      const Text(
                        'Set this only if migrating from another system',
                        style: TextStyle(fontSize: 11, color: kTextHint),
                      ),
                    ],
                  ),
                ),
              ]),
            );
          }(),
          Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: _outstanding > 0 ? Colors.orange.shade50 : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _outstanding > 0 ? Colors.orange.shade300 : Colors.green.shade300,
                      width: 1.5)),
              child: Row(children: [
                Icon(_outstanding > 0 ? Icons.account_balance_wallet_outlined : Icons.check_circle_outline,
                    color: _outstanding > 0 ? Colors.orange : Colors.green, size: 22),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_outstanding > 0 ? 'Outstanding Balance' : 'No Outstanding',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                          color: _outstanding > 0 ? Colors.orange.shade700 : Colors.green.shade700)),
                  if (_outstanding > 0)
                    Text(Fmt.amount(_outstanding),
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.orange))
                  else
                    const Text('All dues cleared', style: TextStyle(fontSize: 12, color: Colors.green)),
                ])),
                TextButton(
                    onPressed: () => context.push(R.retailerLedgerPath(widget.id)),
                    child: const Text('Ledger')),
              ])),
          const SizedBox(height: 14),

          ElevatedButton.icon(
              onPressed: () => context.push(R.retailerLedgerPath(widget.id)),
              icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
              label: const Text('View Ledger & Outstanding')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
              onPressed: () => context.push(R.retailerStatementPath(widget.id)),
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('Account Statement')),
          const SizedBox(height: 10),
          OutlinedButton.icon(
              onPressed: () => context.go(R.orderCreate),
              icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
              label: const Text('New Order')),
          const SizedBox(height: 10),

          if (_recentOrders.isNotEmpty) ...[
            const SizedBox(height: 8),
            const SectionHeader('RECENT ORDERS'),
            ..._recentOrders.map((o) {
              final st = o['status'] as String? ?? 'pending';
              final birds = (o['estimated_birds'] as num?)?.toInt() ?? 0;
              final kg = (o['total_quantity'] as num?)?.toDouble() ?? 0;
              final amt = (o['total_amount'] as num?)?.toDouble() ?? 0;
              final date = DateTime.tryParse(o['created_at'] as String? ?? '');
              return InkWell(
                  onTap: () => context.push(R.orderDetailPath(o['id'] as String)),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: kBorder)),
                      child: Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('$birds birds · ${kg.toStringAsFixed(1)} kg',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          if (date != null)
                            Text(DateFormat('d MMM y').format(date),
                                style: const TextStyle(fontSize: 11, color: kTextHint)),
                        ])),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          StatusBadge(st, SC.order(st), small: true),
                          if (amt > 0) Text(Fmt.amount(amt),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kPrimary)),
                        ]),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right, size: 16, color: kTextHint),
                      ])));
            }),
          ],

          const SizedBox(height: 10),
          OutlinedButton.icon(
              onPressed: _toggleActive,
              icon: Icon(isActive ? Icons.block : Icons.check_circle_outline, size: 18),
              label: Text(isActive ? 'Deactivate Customer' : 'Reactivate Customer'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: isActive ? Colors.red : kPrimary,
                  side: BorderSide(color: isActive ? Colors.red : kPrimary))),

          const SizedBox(height: 16),
          GestureDetector(
            onTap: () {
              setState(() => _showHistory = !_showHistory);
              if (_showHistory && !_historyLoaded) _loadCreditHistory();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _showHistory ? const Color(0xFFF0F4FF) : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: _showHistory ? Colors.blue.shade200 : Colors.grey.shade300),
              ),
              child: Row(children: [
                Icon(Icons.history_rounded, size: 18,
                    color: _showHistory ? Colors.blue.shade700 : kTextSub),
                const SizedBox(width: 10),
                Expanded(child: Text('Credit & Account History',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                        color: _showHistory ? Colors.blue.shade700 : kTextSub))),
                Icon(_showHistory
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                    size: 18, color: kTextSub),
              ]),
            ),
          ),

          if (_showHistory) ...[
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: _loadingHistory
                  ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                  : _creditHistory.isEmpty
                  ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: Text('No credit changes recorded yet.',
                      style: TextStyle(fontSize: 13, color: kTextHint))))
                  : Column(children: _creditHistory.asMap().entries.map((e) {
                final i   = e.key;
                final row = e.value;
                final ct  = row['change_type'] as String? ?? '';
                final at  = DateTime.tryParse(
                    row['changed_at'] as String? ?? '');
                final who = row['changed_by_name'] as String? ?? 'System';

                String desc;
                Color  color;
                IconData icon;

                switch (ct) {
                  case 'credit_limit_change':
                    final old = (row['old_credit_limit'] as num?)?.toDouble() ?? 0;
                    final nw  = (row['new_credit_limit'] as num?)?.toDouble() ?? 0;
                    desc  = 'Credit limit: ${Fmt.amount(old)} → ${Fmt.amount(nw)}';
                    color = nw > old ? Colors.green : Colors.red;
                    icon  = nw > old ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;
                  case 'block':
                    desc  = 'Account blocked';
                    if (row['note'] != null) desc += ' — ${row['note']}';
                    color = Colors.red;
                    icon  = Icons.block_rounded;
                  case 'unblock':
                    desc  = 'Account unblocked';
                    color = Colors.green;
                    icon  = Icons.check_circle_outline_rounded;
                  case 'allow_credit_off':
                    desc  = 'Credit disabled';
                    color = Colors.orange;
                    icon  = Icons.credit_card_off_outlined;
                  case 'allow_credit_on':
                    desc  = 'Credit enabled';
                    color = Colors.blue;
                    icon  = Icons.credit_card_outlined;
                  case 'outstanding_adjustment':
                    final old = (row['old_outstanding'] as num?)?.toDouble() ?? 0;
                    final nw  = (row['new_outstanding'] as num?)?.toDouble() ?? 0;
                    desc  = 'Outstanding: ${Fmt.amount(old)} → ${Fmt.amount(nw)}';
                    color = Colors.orange.shade700;
                    icon  = Icons.account_balance_wallet_outlined;
                  case 'risk_level_change':
                    desc  = 'Risk: ${row['old_risk_level'] ?? '?'} → ${row['new_risk_level'] ?? '?'}';
                    color = Colors.purple;
                    icon  = Icons.warning_amber_rounded;
                  default:
                    desc  = ct.replaceAll('_', ' ');
                    color = kTextSub;
                    icon  = Icons.info_outline;
                }

                return Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    border: i < _creditHistory.length - 1
                        ? const Border(bottom: BorderSide(color: kBorder))
                        : null,
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          shape: BoxShape.circle),
                      child: Icon(icon, size: 14, color: color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(desc, style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(who,
                              style: const TextStyle(
                                  fontSize: 11, color: kTextHint)),
                        ])),
                    if (at != null)
                      Text(DateFormat('d MMM y\nh:mm a').format(at.toLocal()),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontSize: 10, color: kTextHint)),
                  ]),
                );
              }).toList()),
            ),
          ],
        ],
        const SizedBox(height: 20),
      ]),
    );
  }
}