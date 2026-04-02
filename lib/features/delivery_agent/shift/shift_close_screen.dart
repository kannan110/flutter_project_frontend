import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class ShiftCloseScreen extends ConsumerStatefulWidget {
  const ShiftCloseScreen({super.key});
  @override ConsumerState<ShiftCloseScreen> createState() => _S();
}

class _S extends ConsumerState<ShiftCloseScreen> {
  final _c        = Supabase.instance.client;
  final _odoEnd   = TextEditingController();
  final _birds    = TextEditingController(text: '0');
  final _weight   = TextEditingController(text: '0');
  final _expenses = TextEditingController(text: '0');

  bool _loading = false, _checking = true, _uploading = false;
  Map<String,dynamic>? _shift;
  Map<String,dynamic>? _summary;
  File?   _odoEndPhoto;
  String? _odoEndPhotoUrl;
  final   _picker = ImagePicker();

  @override void initState() { super.initState(); _loadShift(); }
  @override void dispose()   {
    _odoEnd.dispose(); _birds.dispose(); _weight.dispose(); _expenses.dispose();
    super.dispose();
  }

  Future<void> _loadShift() async {
    final agentId = ref.read(appUserProvider).valueOrNull?.agentId;
    if (agentId == null) { if (mounted) setState(() => _checking = false); return; }
    try {
      // KEY FIX: query by delivery_agent_id (not user_id) — agent's UUID from delivery_agents table
      final s = await _c
          .from('delivery_shifts')
          .select('id,status,odometer_start,odometer_start_photo,shift_start_at,'
                  'total_cash_collected,total_orders,total_birds_delivered,'
                  'total_mortality,total_expenses,opening_bird_count')
          .eq('delivery_agent_id', agentId)
          .eq('status', 'open')
          .order('shift_start_at', ascending: false)
          .limit(1)
          .maybeSingle();

      Map<String,dynamic>? summary;
      if (s != null) {
        // Count pending deliveries for this specific shift
        final pending = await _c
            .from('deliveries')
            .select('id')
            .eq('delivery_shift_id', s['id'])
            .inFilter('status', ['assigned', 'picked_up', 'out_for_delivery']);
        final delivered = await _c
            .from('deliveries')
            .select('id,delivered_bird_count,delivered_total_weight,collected_amount,mortality_birds')
            .eq('delivery_shift_id', s['id'])
            .eq('status', 'delivered');
        final dList = List<Map<String,dynamic>>.from(delivered as List? ?? []);
        summary = {
          'pending_count':      (pending as List).length,
          'delivered_count':    dList.length,
          'total_birds':        dList.fold(0, (sum, d) => sum + ((d['delivered_bird_count'] as num?)?.toInt() ?? 0)),
          'total_weight':       dList.fold(0.0, (sum, d) => sum + ((d['delivered_total_weight'] as num?)?.toDouble() ?? 0)),
          'total_cash':         dList.fold(0.0, (sum, d) => sum + ((d['collected_amount'] as num?)?.toDouble() ?? 0)),
          'total_mortality':    dList.fold(0, (sum, d) => sum + ((d['mortality_birds'] as num?)?.toInt() ?? 0)),
        };
      }
      if (mounted) setState(() { _shift = s; _summary = summary; _checking = false; });
    } catch (e) {
      if (mounted) setState(() => _checking = false);
      // Don't show error — just show "no shift" state
    }
  }

  Future<void> _takeEndOdoPhoto() async {
    try {
      final picked = await _picker.pickImage(
          source: ImageSource.camera, imageQuality: 70, maxWidth: 1200);
      if (picked == null || !mounted) return;
      final file = File(picked.path);
      if (mounted) setState(() { _odoEndPhoto = file; _uploading = true; });
      try {
        final path = 'odometer/end_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await _c.storage.from('delivery-proofs').upload(path, file);
        final url = _c.storage.from('delivery-proofs').getPublicUrl(path);
        if (mounted) setState(() { _odoEndPhotoUrl = url; _uploading = false; });
      } catch (_) {
        if (mounted) setState(() => _uploading = false);
      }
    } catch (_) {}
  }

  Future<void> _close() async {
    if (_odoEnd.text.trim().isEmpty) { showError(context, 'Enter odometer end reading'); return; }
    if (_shift == null)              { showError(context, 'No active shift found. Pull to refresh.'); return; }

    final pending = (_summary?['pending_count'] as int?) ?? 0;
    String msg = 'Close your shift for today?\n\n'
        'Deliveries done: ${_summary?['delivered_count'] ?? 0}\n'
        'Birds delivered: ${_summary?['total_birds'] ?? 0}\n'
        'Cash collected: ${Fmt.amount((_summary?['total_cash'] as double?) ?? 0)}';

    if (pending > 0) {
      msg = '⚠ $pending deliveries still pending!\n\n'
            'Closing shift will NOT cancel them.\n'
            'Admin will need to handle them separately.';
    }

    final ok = await confirmDialog(context,
        title: 'Close Shift',
        message: msg,
        confirmText: 'Close Shift',
        confirmColor: pending > 0 ? Colors.orange : kPrimary);
    if (!ok) return;

    if (mounted) setState(() => _loading = true);
    try {
      await _c.rpc('close_delivery_shift', params: {
        'p_shift_id':            _shift!['id'],
        'p_odometer_end':        double.tryParse(_odoEnd.text.trim()) ?? 0,
        'p_odometer_end_photo':  _odoEndPhotoUrl,
        'p_closing_bird_count':  int.tryParse(_birds.text.trim())    ?? 0,
        'p_closing_weight':      double.tryParse(_weight.text.trim()) ?? 0,
        'p_expenses':            double.tryParse(_expenses.text.trim()) ?? 0,
      });
      if (mounted) {
        showSuccess(context, 'Shift closed ✓ — great work today!');
        context.go(R.agentHome);
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString()
            .replaceAll('Exception: ', '')
            .replaceAll('PostgrestException(message: ', '');
        showError(context, msg);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Close Shift'),
      actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadShift)]),
    body: _checking
        ? const LoadingList()
        : _shift == null
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.info_outline, size: 56, color: kTextHint),
                const SizedBox(height: 12),
                const Text('No active shift found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kTextSub)),
                const SizedBox(height: 6),
                const Text('You need an open shift to close one.',
                    style: TextStyle(fontSize: 13, color: kTextHint)),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                    onPressed: _loadShift,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry')),
                const SizedBox(height: 12),
                OutlinedButton(
                    onPressed: () => context.go(R.agentHome),
                    child: const Text('Go to Home')),
              ]))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

                  // ── Today's summary ───────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: kPrimary.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: kPrimary.withValues(alpha: 0.2))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Icon(Icons.radio_button_on, color: kPrimary, size: 14),
                        const SizedBox(width: 6),
                        const Text('SHIFT ACTIVE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                            color: kPrimary, letterSpacing: 1)),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        _stat('Deliveries', '${_summary?['delivered_count'] ?? 0}', kPrimary),
                        _stat('Birds', '${_summary?['total_birds'] ?? 0}', Colors.teal),
                        _stat('Cash', Fmt.amount((_summary?['total_cash'] as double?) ?? 0), Colors.green),
                        _stat('Mortality', '${_summary?['total_mortality'] ?? 0}',
                            (_summary?['total_mortality'] as int? ?? 0) > 0 ? Colors.red : kTextHint),
                      ]),
                      const SizedBox(height: 8),
                      Text('Start odometer: ${_shift!['odometer_start'] ?? '—'} km',
                          style: const TextStyle(fontSize: 12, color: kTextSub)),
                    ])),

                  // Pending deliveries warning
                  if ((_summary?['pending_count'] ?? 0) > 0) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange.shade200)),
                      child: Row(children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                            '${_summary!['pending_count']} deliveries still pending. '
                            'Try to complete them before closing.',
                            style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w600))),
                        TextButton(
                            onPressed: () => context.go(R.agentDeliveries),
                            child: const Text('View →')),
                      ])),
                  ],
                  const SizedBox(height: 20),

                  // ── Odometer end ──────────────────────────────────
                  const SectionHeader('ODOMETER END READING'),
                  TextField(
                    controller: _odoEnd,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    decoration: const InputDecoration(
                        labelText: 'End Reading (km) *',
                        prefixIcon: Icon(Icons.speed_outlined, size: 20),
                        suffixText: 'km')),
                  const SizedBox(height: 10),

                  // Odometer end photo
                  GestureDetector(
                    onTap: _uploading ? null : _takeEndOdoPhoto,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: _odoEndPhoto != null ? Colors.green.shade50 : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _odoEndPhoto != null
                              ? Colors.green.shade300 : Colors.grey.shade300)),
                      child: Row(children: [
                        if (_odoEndPhoto != null)
                          ClipRRect(borderRadius: BorderRadius.circular(6),
                              child: Image.file(_odoEndPhoto!, width: 48, height: 48, fit: BoxFit.cover))
                        else
                          const Icon(Icons.camera_alt_outlined, size: 36, color: kTextHint),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_odoEndPhoto != null ? 'End odometer photo captured' : 'Take End Odometer Photo',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                  color: _odoEndPhoto != null ? Colors.green : kTextSub)),
                          Text(_uploading ? 'Uploading...' : _odoEndPhotoUrl != null
                              ? '✓ Uploaded' : 'Optional — recommended for audit',
                              style: const TextStyle(fontSize: 11, color: kTextHint)),
                        ])),
                        if (_uploading)
                          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        else if (_odoEndPhotoUrl != null)
                          const Icon(Icons.check_circle, color: Colors.green, size: 20)
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: kPrimary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6)),
                            child: const Text('Capture',
                                style: TextStyle(fontSize: 12, color: kPrimary, fontWeight: FontWeight.w700))),
                      ])),
                  ),
                  const SizedBox(height: 16),

                  // ── Closing stock ──────────────────────────────────
                  const SectionHeader('UNSOLD BIRDS (RETURNING TO STOCK)'),
                  Row(children: [
                    Expanded(child: TextField(
                      controller: _birds,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Remaining birds', suffixText: 'birds'))),
                    const SizedBox(width: 12),
                    Expanded(child: TextField(
                      controller: _weight,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Weight (kg)', suffixText: 'kg'))),
                  ]),
                  const SizedBox(height: 16),

                  // ── Expenses ───────────────────────────────────────
                  const SectionHeader('EXPENSES (FUEL / TOLL / MISC)'),
                  TextField(
                    controller: _expenses,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Total Expenses (₹)', prefixText: '₹',
                        helperText: 'Enter diesel + toll + any other expenses')),
                  const SizedBox(height: 28),

                  ElevatedButton.icon(
                    onPressed: (_loading || _uploading) ? null : _close,
                    icon: _loading
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.lock_outline, size: 18),
                    label: const Text('Close Shift', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(backgroundColor: kError)),
                  const SizedBox(height: 20),
                ])),
  );

  Widget _stat(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c)),
    Text(l, style: const TextStyle(fontSize: 10, color: kTextHint), textAlign: TextAlign.center),
  ]));
}
