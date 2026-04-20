import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class ShiftDetailScreen extends ConsumerStatefulWidget {
  const ShiftDetailScreen({super.key, required this.id});
  final String id;
  @override ConsumerState<ShiftDetailScreen> createState() => _S();
}
class _S extends ConsumerState<ShiftDetailScreen> {
  final _c = Supabase.instance.client;
  Map<String,dynamic>? _summary;
  bool _loading = true, _submitting = false;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (!mounted) return;
    if (mounted) setState(() => _loading = true);
    try {
      final res = await _c.rpc('get_shift_summary', params: {'p_shift_id': widget.id});
      if (!mounted) return;
      if (mounted) setState(() { _summary = res != null ? Map<String,dynamic>.from(((res as Map?)?.cast<String,dynamic>()) ?? {}) : null; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approveShift() async {
    final ok = await confirmDialog(context, title: 'Approve Shift', message: 'Approve this shift? This confirms all deliveries and cash are verified.', confirmText: 'Approve', confirmColor: kPrimary);
    if (!ok || !mounted) return;
    if (mounted) setState(() => _submitting = true);
    try {
      await _c.from('delivery_shifts').update({
        'shift_approval_status': 'approved',
        'shift_approval_notes': 'Approved by trader admin',
      }).eq('id', widget.id);
      _load();
      if (mounted) showSuccess(context, 'Shift approved ✓');
    } catch (e) { if (mounted) showError(context, e.toString()); }
    finally { if (mounted) setState(() => _submitting = false); }
  }

  Future<void> _rejectShift() async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Reject Shift'),
      content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Reason *'), autofocus: true),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(onPressed: () { if (ctrl.text.trim().isNotEmpty) Navigator.pop(ctx, ctrl.text.trim()); }, child: const Text('Reject'))],
    ));
    ctrl.dispose();
    if (reason == null || !mounted) return;
    if (mounted) setState(() => _submitting = true);
    try {
      await _c.from('delivery_shifts').update({'shift_approval_status': 'rejected', 'shift_approval_notes': reason}).eq('id', widget.id);
      _load();
      if (mounted) showSuccess(context, 'Shift rejected');
    } catch (e) { if (mounted) showError(context, e.toString()); }
    finally { if (mounted) setState(() => _submitting = false); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingList());
    if (_summary == null) return Scaffold(appBar: AppBar(title: const Text('Shift Detail')), body: const Center(child: Text('No data')));

    final shift      = _summary!['shift']     as Map<String,dynamic>?;
    final totals     = _summary!['totals']    as Map<String,dynamic>?;
    final deliveries = (_summary!['deliveries'] as List? ?? []).cast<Map<String,dynamic>>();
    final challans   = (_summary!['challans']   as List? ?? []).cast<Map<String,dynamic>>();
    final shiftStatus = shift?['status'] as String? ?? 'open';
    final approvalStatus = shift?['shift_approval_status'] as String? ?? 'pending';

    return Scaffold(
      appBar: AppBar(title: Text(shift?['agent_name'] as String? ?? 'Shift Detail'),
          actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: ListView(padding: const EdgeInsets.all(16), children: [

        // ── Status header ────────────────────────────────────────────
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(
            color: shiftStatus == 'closed' ? Colors.green.shade600 : kPrimary, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(shiftStatus == 'closed' ? Icons.check_circle_outline : Icons.access_time_outlined, color: Colors.white, size: 26),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(shift?['agent_name'] as String? ?? '—', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
              Text('${shift?['vehicle_no'] ?? ''}  |  Shift ${shiftStatus.toUpperCase()}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ])),
            if (approvalStatus != 'pending') StatusBadge(approvalStatus, approvalStatus == 'approved' ? Colors.green.shade300 : Colors.red.shade300),
          ])),
        const SizedBox(height: 12),

        // ── Odometer & Distance ─────────────────────────────────────
        _buildOdometerSection(shift),
        const SizedBox(height: 10),

        // ── DC / Purchase Summary ────────────────────────────────────
        if (challans.isNotEmpty) WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader('DELIVERY CHALLANS (FARM PURCHASE)'),
          ...challans.map((ch) {
            final date = DateTime.tryParse(ch['dc_date'] as String? ?? '');
            return ListTile(dense: true,
              leading: const Icon(Icons.receipt_long_outlined, color: kPrimary, size: 20),
              title: Text('${ch['dc_number']} — ${ch['farmer_name'] ?? '—'}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text('${ch['bird_count'] ?? 0} birds · ${(ch['net_weight'] as num?)?.toStringAsFixed(1) ?? 0} kg · ${ch['crates_count'] ?? 0} crates', style: const TextStyle(fontSize: 11)),
              trailing: date != null ? Text(DateFormat('d MMM').format(date), style: const TextStyle(fontSize: 11, color: kTextHint)) : null,
            );
          }),
          Divider(height: 12),
          _trow('Total DC Birds', '${totals?['total_dc_birds'] ?? 0} birds'),
          _trow('Total DC Weight', '${(totals?['total_dc_weight'] as num?)?.toStringAsFixed(1) ?? 0} kg'),
        ])),
        const SizedBox(height: 10),

        // ── Delivery summary ─────────────────────────────────────────
        WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader('DELIVERY SUMMARY'),
          Row(children: [
            _sbox('Delivered', '${totals?['deliveries_count'] ?? 0}', kPrimary),
            _sbox('Birds', '${totals?['total_birds'] ?? 0}', Colors.blue),
            _sbox('Weight', '${(totals?['total_weight_kg'] as num?)?.toStringAsFixed(1) ?? 0} kg', Colors.teal),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _sbox('Dead', '${totals?['total_mortality'] ?? 0}', Colors.red),
            _sbox('Returns', '${totals?['total_returned'] ?? 0}', Colors.purple),
            _sbox('Crates Pending', '${totals?['pending_crates'] ?? 0}', Colors.orange),
          ]),
        ])),
        const SizedBox(height: 10),

        // ── Cash summary ──────────────────────────────────────────────
        WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader('CASH & PAYMENT'),
          _trow('Total Collected', Fmt.amount((totals?['total_collected'] as num?)?.toDouble() ?? 0), color: kPrimary),
          _trow('Cash', Fmt.amount((totals?['cash_collected'] as num?)?.toDouble() ?? 0)),
          _trow('UPI', Fmt.amount((totals?['upi_collected'] as num?)?.toDouble() ?? 0)),
          _trow('Expenses', Fmt.amount((totals?['total_expenses'] as num?)?.toDouble() ?? 0), color: Colors.red),
          const Divider(height: 12),
          _trow('Net Cash to Hand', Fmt.amount((totals?['net_cash'] as num?)?.toDouble() ?? 0), color: kPrimary, bold: true),
        ])),
        const SizedBox(height: 10),

        // ── Per-delivery breakdown ────────────────────────────────────
        if (deliveries.isNotEmpty) ...[
          const SectionHeader('PER DELIVERY BREAKDOWN'),
          ...deliveries.map((d) {
            final status    = d['status'] as String? ?? '—';
            final approved  = d['approval_status'] as String? ?? 'pending';
            final birds     = d['delivered_bird_count'] as int? ?? 0;
            final weight    = (d['delivered_total_weight'] as num?)?.toDouble() ?? 0;
            final collected = (d['collected_amount'] as num?)?.toDouble() ?? 0;
            final mortality = d['mortality_birds'] as int? ?? 0;
            return Container(margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.fromLTRB(12,10,12,4), child: Row(children: [
                  Expanded(child: Text(d['shop_name'] as String? ?? '—', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                  StatusBadge(status, SC.order(status), small: true),
                  const SizedBox(width: 4),
                  StatusBadge(approved, approved == 'approved' ? Colors.green : Colors.orange, small: true),
                ])),
                Padding(padding: const EdgeInsets.fromLTRB(12,0,12,8), child: Row(children: [
                  Text('$birds birds · ${weight.toStringAsFixed(1)} kg', style: const TextStyle(fontSize: 11, color: kTextSub)),
                  const Spacer(),
                  if (mortality > 0) Text('💀 $mortality  ', style: const TextStyle(fontSize: 11, color: Colors.red)),
                  Text(Fmt.amount(collected), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kPrimary)),
                ])),
                // Mortality & delivery proof photos — tap to expand
                if (d['mortality_proof_url'] != null || d['delivery_photo_url'] != null)
                  Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: Row(children: [
                      if (d['mortality_proof_url'] != null)
                        _miniPhotoTile('Mortality Proof', d['mortality_proof_url'] as String, Colors.red),
                      if (d['mortality_proof_url'] != null && d['delivery_photo_url'] != null)
                        const SizedBox(width: 8),
                      if (d['delivery_photo_url'] != null)
                        _miniPhotoTile('Delivery Proof', d['delivery_photo_url'] as String, Colors.blue),
                    ]))
                else
                  const SizedBox(height: 2),
              ]));
          }),
        ],
        const SizedBox(height: 16),

        // ── Approval actions ──────────────────────────────────────────
        if (shiftStatus == 'closed' && approvalStatus == 'pending') ...[
          Container(padding: const EdgeInsets.all(14), margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.shade200)),
            child: const Row(children: [
              Icon(Icons.pending_actions_outlined, color: Colors.orange, size: 20), SizedBox(width: 8),
              Expanded(child: Text('Review all deliveries above, then approve or reject this shift.', style: TextStyle(fontSize: 13, color: Colors.orange, fontWeight: FontWeight.w600))),
            ])),
          ElevatedButton.icon(
            onPressed: _submitting ? null : _approveShift,
            icon: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check_circle_outline),
            label: const Text('Approve Shift ✓'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _submitting ? null : _rejectShift,
            icon: const Icon(Icons.cancel_outlined, size: 18),
            label: const Text('Reject / Flag Discrepancy'),
            style: OutlinedButton.styleFrom(foregroundColor: kError, side: const BorderSide(color: kError)),
          ),
        ] else if (approvalStatus == 'approved') Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.shade200)),
          child: const Row(children: [
            Icon(Icons.check_circle, color: Colors.green, size: 22), SizedBox(width: 10),
            Text('Shift Approved ✓', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.green)),
          ])),
        const SizedBox(height: 20),
      ]),
    );
  }

  // ── ODOMETER SECTION ─────────────────────────────────────────────
  Widget _buildOdometerSection(Map<String,dynamic>? shift) {
    if (shift == null) return const SizedBox.shrink();

    final odoStart    = (shift['odometer_start']       as num?)?.toDouble();
    final odoEnd      = (shift['odometer_end']         as num?)?.toDouble();
    final distKm      = odoEnd != null && odoStart != null
        ? (odoEnd - odoStart).abs() : (shift['distance_km'] as num?)?.toDouble() ?? 0;
    final startPhoto  = shift['odometer_start_photo']  as String?;
    final endPhoto    = shift['odometer_end_photo']    as String?;
    final hasAnyData  = odoStart != null || odoEnd != null || startPhoto != null || endPhoto != null;

    if (!hasAnyData) return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
      child: const Row(children: [
        Icon(Icons.speed_outlined, size: 16, color: kTextHint), SizedBox(width: 8),
        Text('No odometer data recorded for this shift',
            style: TextStyle(fontSize: 12, color: kTextHint)),
      ]));

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.teal.shade200, width: 1.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
              color: Colors.teal.shade600,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13))),
          child: Row(children: [
            const Icon(Icons.speed_outlined, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            const Expanded(child: Text('Odometer & Distance',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))),
            if (distKm > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8)),
                child: Text('${distKm.toStringAsFixed(0)} km travelled',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800))),
          ])),

        Padding(padding: const EdgeInsets.all(14), child: Column(children: [
          // Odometer readings row
          Row(children: [
            _odoStat('Start Reading',
                odoStart != null ? '${odoStart.toStringAsFixed(0)} km' : 'Not recorded',
                Colors.blue),
            Container(width: 1, height: 40, color: kBorder, margin: const EdgeInsets.symmetric(horizontal: 12)),
            _odoStat('End Reading',
                odoEnd != null ? '${odoEnd.toStringAsFixed(0)} km' : 'Not recorded',
                Colors.teal),
            Container(width: 1, height: 40, color: kBorder, margin: const EdgeInsets.symmetric(horizontal: 12)),
            _odoStat('Distance',
                distKm > 0 ? '${distKm.toStringAsFixed(0)} km' : '—',
                distKm > 0 ? Colors.green : kTextHint),
          ]),
          const SizedBox(height: 14),

          // Photo tiles
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (startPhoto != null)
              Expanded(child: _odoPhotoTile('Start Odometer', startPhoto, Colors.blue))
            else
              Expanded(child: _odoMissingTile('Start Odometer', Colors.blue)),
            const SizedBox(width: 10),
            if (endPhoto != null)
              Expanded(child: _odoPhotoTile('End Odometer', endPhoto, Colors.teal))
            else
              Expanded(child: _odoMissingTile('End Odometer', Colors.teal)),
          ]),
        ])),
      ]));
  }

  Widget _odoStat(String label, String value, Color c) =>
    Expanded(child: Column(children: [
      Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: c),
          textAlign: TextAlign.center),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(fontSize: 9, color: kTextHint),
          textAlign: TextAlign.center),
    ]));

  Widget _odoPhotoTile(String label, String url, Color c) =>
    GestureDetector(
      onTap: () => _showFullImage(context, url, label),
      child: Container(
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.withValues(alpha: 0.3))),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
                color: c.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(9))),
            child: Row(children: [
              Icon(Icons.speed_outlined, size: 13, color: c), const SizedBox(width: 4),
              Expanded(child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c))),
              Icon(Icons.open_in_full, size: 12, color: c.withValues(alpha: 0.6)),
            ])),
          ClipRRect(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(9)),
            child: Image.network(url,
              width: double.infinity, height: 130, fit: BoxFit.cover,
              loadingBuilder: (ctx, child, prog) => prog == null ? child
                  : Container(height: 130, color: c.withValues(alpha: 0.05),
                      child: Center(child: CircularProgressIndicator(color: c, strokeWidth: 2))),
              errorBuilder: (_, __, ___) => Container(
                height: 100, color: c.withValues(alpha: 0.05),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.broken_image_outlined, size: 28, color: c.withValues(alpha: 0.4)),
                  const SizedBox(height: 4),
                  Text('Failed to load', style: TextStyle(fontSize: 10, color: c.withValues(alpha: 0.5))),
                ])),
            )),
        ])));

  Widget _odoMissingTile(String label, Color c) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid)),
    child: Column(children: [
      Icon(Icons.photo_camera_outlined, size: 28, color: Colors.grey.shade400),
      const SizedBox(height: 6),
      Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: kTextSub)),
      const SizedBox(height: 2),
      const Text('Not captured', style: TextStyle(fontSize: 10, color: kTextHint)),
    ]));

  void _showFullImage(BuildContext context, String url, String title) {
    showDialog(
      context: context, useRootNavigator: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black, insetPadding: EdgeInsets.zero,
        child: Stack(children: [
          InteractiveViewer(
            child: Center(child: Image.network(url, fit: BoxFit.contain,
                loadingBuilder: (_, child, prog) => prog == null ? child
                    : const Center(child: CircularProgressIndicator(color: Colors.white)),
                errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image, color: Colors.white, size: 64))))),
          Positioned(top: 16, left: 16, child: Text(title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 4)]))),
          Positioned(top: 8, right: 8, child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(ctx, rootNavigator: true).pop())),
        ])));
  }

  // Mini photo thumbnail for delivery rows in shift detail
  Widget _miniPhotoTile(String label, String url, Color c) =>
    Expanded(child: GestureDetector(
      onTap: () => _showFullImage(context, url, label),
      child: Container(
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.withValues(alpha: 0.3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
                color: c.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(7))),
            child: Row(children: [
              Icon(label.contains('Mortality') ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                  size: 11, color: c),
              const SizedBox(width: 4),
              Expanded(child: Text(label,
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: c),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
              Icon(Icons.open_in_full, size: 10, color: c.withValues(alpha: 0.6)),
            ])),
          ClipRRect(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(7)),
            child: Image.network(url,
              width: double.infinity, height: 90, fit: BoxFit.cover,
              loadingBuilder: (ctx, child, prog) => prog == null ? child
                  : Container(height: 90, color: c.withValues(alpha: 0.05),
                      child: Center(child: CircularProgressIndicator(color: c, strokeWidth: 2))),
              errorBuilder: (_, __, ___) => Container(
                height: 70, color: c.withValues(alpha: 0.05),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.broken_image_outlined, size: 22, color: c.withValues(alpha: 0.4)),
                  Text('Load failed', style: TextStyle(fontSize: 9, color: c.withValues(alpha: 0.5))),
                ])),
            )),
        ]))));


  Widget _trow(String l, String v, {Color? color, bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Expanded(child: Text(l, style: const TextStyle(fontSize: 13, color: kTextSub))),
      Text(v, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color ?? kTextMain)),
    ]));

  Widget _sbox(String label, String value, Color color) => Expanded(child: Column(children: [
    Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
    Text(label, style: const TextStyle(fontSize: 10, color: kTextHint), textAlign: TextAlign.center),
  ]));
}
