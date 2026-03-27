import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class RetailerDetailScreen extends ConsumerStatefulWidget {
  const RetailerDetailScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<RetailerDetailScreen> createState() => _RetailerDetailScreenState();
}

class _RetailerDetailScreenState extends ConsumerState<RetailerDetailScreen> {
  final _client = Supabase.instance.client;
  Map<String, dynamic>? _retailer;
  double _outstanding = 0;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await _client.from('retailers').select('*').eq('id', widget.id).maybeSingle();
    final out = await _client.rpc('get_retailer_outstanding', params: {'p_retailer_id': widget.id});
    if (mounted) setState(() { _retailer = r; _outstanding = (out as num?)?.toDouble() ?? 0; _loading = false; });
  }

  Future<void> _whatsapp() async {
    final phone = _retailer?['phone'] as String?;
    if (phone == null) { showError(context, 'No phone number'); return; }
    final clean = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final number = clean.startsWith('91') ? clean : '91$clean';
    final msg = Uri.encodeComponent(
      'Dear ${_retailer!['owner_name'] ?? _retailer!['shop_name']},\n\nYour outstanding balance with Rooster Trader is ₹${_outstanding.toStringAsFixed(2)}.\n\nPlease clear your dues at the earliest.\n\nThank you.');
    final url = Uri.parse('https://wa.me/$number?text=$msg');
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
    else if (mounted) showError(context, 'Could not open WhatsApp');
  }

  Future<void> _toggleBlock() async {
    final isBlocked = _retailer?['is_blocked'] as bool? ?? false;
    final confirmed = await confirmDialog(context,
      title: isBlocked ? 'Unblock Retailer' : 'Block Retailer',
      message: isBlocked ? 'Allow this retailer to place orders?' : 'Block this retailer from placing orders?',
      confirmText: isBlocked ? 'Unblock' : 'Block',
      confirmColor: isBlocked ? AppTheme.primary : AppTheme.errorRed);
    if (!confirmed) return;
    await _client.from('retailers').update({'is_blocked': !isBlocked}).eq('id', widget.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_retailer == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Not found')));
    final isBlocked = _retailer!['is_blocked'] as bool? ?? false;
    final limit = (_retailer!['credit_limit'] as num?)?.toDouble() ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(_retailer!['shop_name'] as String),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Outstanding card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [AppTheme.primary, AppTheme.primary.withOpacity(0.8)]),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Outstanding Balance', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 6),
            Text(AmountText.format(_outstanding),
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: limit > 0 ? (_outstanding / limit).clamp(0.0, 1.0) : 0,
                minHeight: 6, backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation<Color>(
                    _outstanding > limit * 0.9 ? Colors.red.shade300 : Colors.white),
              ),
            ),
            const SizedBox(height: 6),
            Text('Credit limit: ${AmountText.format(limit)}',
                style: const TextStyle(color: Colors.white60, fontSize: 11)),
          ]),
        ),
        const SizedBox(height: 16),

        // Actions
        Row(children: [
          Expanded(child: _ActionBtn(Icons.account_balance_wallet_outlined, 'View Ledger', () => context.go('/ledger/${widget.id}'))),
          const SizedBox(width: 10),
          Expanded(child: _ActionBtn(Icons.chat_outlined, 'WhatsApp', _whatsapp, color: const Color(0xFF25D366))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _ActionBtn(Icons.shopping_cart_outlined, 'Orders', () => context.go(Routes.orders))),
          const SizedBox(width: 10),
          Expanded(child: _ActionBtn(
            isBlocked ? Icons.lock_open_outlined : Icons.block_outlined,
            isBlocked ? 'Unblock' : 'Block',
            _toggleBlock,
            color: isBlocked ? AppTheme.primary : AppTheme.errorRed,
          )),
        ]),
        const SizedBox(height: 20),

        // Details
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
              border: const Border.fromBorderSide(BorderSide(color: Color(0xFFEEEEEE)))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionHeader('RETAILER DETAILS'),
            InfoRow('Shop Name',    _retailer!['shop_name'] as String),
            if (_retailer!['shop_name_tamil'] != null) InfoRow('Tamil Name', _retailer!['shop_name_tamil'] as String),
            if (_retailer!['owner_name'] != null)    InfoRow('Owner',     _retailer!['owner_name'] as String),
            if (_retailer!['phone'] != null)         InfoRow('Phone',     _retailer!['phone'] as String),
            if (_retailer!['city'] != null)          InfoRow('City',      _retailer!['city'] as String),
            if (_retailer!['address'] != null)       InfoRow('Address',   _retailer!['address'] as String),
            InfoRow('Status',       isBlocked ? 'Blocked' : 'Active', valueColor: isBlocked ? Colors.red : Colors.green),
            InfoRow('Registration', _retailer!['registration_mode'] as String? ?? 'trader_created'),
          ]),
        ),
      ]),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn(this.icon, this.label, this.onTap, {this.color = AppTheme.primary});
  final IconData icon; final String label; final VoidCallback onTap; final Color color;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ]),
    ),
  );
}
