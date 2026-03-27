import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class ApprovalDetailScreen extends ConsumerStatefulWidget {
  const ApprovalDetailScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<ApprovalDetailScreen> createState() => _ApprovalDetailScreenState();
}

class _ApprovalDetailScreenState extends ConsumerState<ApprovalDetailScreen> {
  final _client = Supabase.instance.client;
  Map<String, dynamic>? _delivery;
  bool _loading = true;
  bool _submitting = false;

  final _rateCtrl   = TextEditingController();
  final _notesCtrl  = TextEditingController();
  final _rejectCtrl = TextEditingController();
  double _calculatedAmount = 0;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _rateCtrl.dispose(); _notesCtrl.dispose(); _rejectCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    final data = await _client.from('deliveries')
        .select('*, orders(*, retailers(*), master_products(*), order_items(*)), delivery_agents(*), delivery_shifts(*)')
        .eq('id', widget.id).maybeSingle();
    if (mounted) {
      setState(() { _delivery = data; _loading = false; });
      // Pre-fill rate from order_items
      if (data != null) {
        final order = data['orders'] as Map<String, dynamic>?;
        final items = order?['order_items'] as List? ?? [];
        if (items.isNotEmpty) {
          final rate = (items.first['rate_per_kg'] as num?)?.toDouble() ?? 0;
          _rateCtrl.text = rate > 0 ? rate.toStringAsFixed(2) : '';
          _calcAmount();
        }
      }
    }
  }

  void _calcAmount() {
    if (_delivery == null) return;
    final weight = ((_delivery!['delivered_total_weight'] ?? _delivery!['received_total_weight']) as num?)?.toDouble() ?? 0;
    final rate   = double.tryParse(_rateCtrl.text) ?? 0;
    setState(() => _calculatedAmount = weight * rate);
  }

  Future<void> _approve() async {
    final rate = double.tryParse(_rateCtrl.text);
    if (rate == null || rate <= 0) { showError(context, 'Enter valid final rate'); return; }
    if (_calculatedAmount <= 0) { showError(context, 'Amount must be > 0'); return; }
    final confirmed = await confirmDialog(context,
      title: 'Approve Delivery',
      message: 'Approve at ₹${rate.toStringAsFixed(2)}/kg = ₹${_calculatedAmount.toStringAsFixed(2)}?',
      confirmText: 'Approve', confirmColor: AppTheme.primary);
    if (!confirmed) return;
    setState(() => _submitting = true);
    try {
      final userId = ref.read(appUserProvider).valueOrNull?.userId;
      await _client.rpc('approve_delivery_and_order', params: {
        'p_delivery_id': widget.id, 'p_final_rate': rate,
        'p_final_amount': _calculatedAmount, 'p_approved_by': userId,
        'p_approval_notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      });
      if (mounted) {
        showSuccess(context, 'Delivery approved — invoice created');
        context.go(Routes.approvals);
      }
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _reject() async {
    if (_rejectCtrl.text.trim().isEmpty) { showError(context, 'Enter rejection reason'); return; }
    final confirmed = await confirmDialog(context, title: 'Reject Delivery', message: 'Reject this delivery?', confirmText: 'Reject');
    if (!confirmed) return;
    setState(() => _submitting = true);
    try {
      final userId = ref.read(appUserProvider).valueOrNull?.userId;
      await _client.from('deliveries').update({
        'approval_status': 'rejected',
        'rejected_at': DateTime.now().toIso8601String(),
        'rejected_by': userId, 'rejection_reason': _rejectCtrl.text.trim(),
      }).eq('id', widget.id);
      await _client.from('orders').update({'approval_status': 'rejected'}).eq('id', _delivery!['order_id']);
      if (mounted) { showSuccess(context, 'Delivery rejected'); context.go(Routes.approvals); }
    } catch (e) {
      if (mounted) showError(context, e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_delivery == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Not found')));

    final order    = _delivery!['orders'] as Map<String, dynamic>?;
    final retailer = order?['retailers'] as Map<String, dynamic>?;
    final product  = order?['master_products'] as Map<String, dynamic>?;
    final agent    = _delivery!['delivery_agents'] as Map<String, dynamic>?;
    final weight   = ((_delivery!['delivered_total_weight'] ?? _delivery!['received_total_weight']) as num?)?.toDouble() ?? 0;
    final birds    = _delivery!['delivered_bird_count'] ?? _delivery!['birds_delivered'] ?? 0;
    final mortality = (_delivery!['mortality_count'] as num?)?.toInt() ?? 0;
    final collected = (_delivery!['collected_amount'] as num?)?.toDouble() ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Approve Delivery')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: const Border.fromBorderSide(BorderSide(color: Color(0xFFEEEEEE)))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(retailer?['shop_name'] ?? '—', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            if (retailer?['owner_name'] != null) Text(retailer!['owner_name'] as String, style: const TextStyle(fontSize: 13, color: Color(0xFF757575))),
            const SizedBox(height: 10),
            Row(children: [
              _Chip(Icons.person_outline, agent?['name'] ?? '—'),
              const SizedBox(width: 8),
              _Chip(Icons.set_meal_outlined, product?['name'] ?? '—'),
            ]),
          ]),
        ),
        const SizedBox(height: 12),

        // Delivery summary
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: const Border.fromBorderSide(BorderSide(color: Color(0xFFEEEEEE)))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionHeader('DELIVERY SUMMARY'),
            InfoRow('Birds Delivered', '$birds'),
            InfoRow('Weight',          '${weight.toStringAsFixed(2)} kg'),
            InfoRow('Mortality',       '$mortality birds', valueColor: mortality > 0 ? Colors.red : null),
            InfoRow('Cash Collected',  '₹${collected.toStringAsFixed(2)}', valueColor: Colors.green),
            if ((_delivery!['delivery_notes'] as String?)?.isNotEmpty == true)
              InfoRow('Notes', _delivery!['delivery_notes'] as String),
          ]),
        ),
        const SizedBox(height: 12),

        // Rate & amount entry
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.primary.withOpacity(0.3))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionHeader('SET FINAL RATE'),
            const Text('Enter the final approved rate for this delivery:', style: TextStyle(fontSize: 13, color: Color(0xFF757575))),
            const SizedBox(height: 12),
            TextFormField(
              controller: _rateCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Rate per kg (₹)', prefixIcon: Icon(Icons.currency_rupee, size: 18)),
              onChanged: (_) => _calcAmount(),
            ),
            const SizedBox(height: 12),
            if (_calculatedAmount > 0)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.07), borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('${weight.toStringAsFixed(2)} kg × ₹${_rateCtrl.text}', style: const TextStyle(fontSize: 13, color: Color(0xFF757575))),
                  Text('₹${_calculatedAmount.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                ]),
              ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(labelText: 'Approval notes (optional)'),
            ),
          ]),
        ),
        const SizedBox(height: 20),

        ElevatedButton.icon(
          onPressed: _submitting ? null : _approve,
          icon: const Icon(Icons.check_circle_outline),
          label: _submitting
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Approve & Create Invoice'),
        ),
        const SizedBox(height: 12),

        // Reject section
        ExpansionTile(
          title: const Text('Reject Delivery', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500, fontSize: 14)),
          leading: const Icon(Icons.cancel_outlined, color: Colors.red, size: 20),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextFormField(
                  controller: _rejectCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Rejection reason *', alignLabelWithHint: true),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _submitting ? null : _reject,
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                  child: const Text('Reject Delivery'),
                ),
              ]),
            ),
          ],
        ),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.icon, this.label);
  final IconData icon; final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: const Color(0xFF757575)),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF757575))),
    ]),
  );
}
