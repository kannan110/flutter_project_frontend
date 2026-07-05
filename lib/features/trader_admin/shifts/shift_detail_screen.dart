import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:rooster_trader/features/trader_admin/shifts/shift_Expense_validation_rule.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/responsive_layout.dart';
import 'shift_verification_screen.dart';

class ShiftDetailScreen extends ConsumerStatefulWidget {
  const ShiftDetailScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<ShiftDetailScreen> createState() => _S();
}

class _S extends ConsumerState<ShiftDetailScreen> {
  final _c = Supabase.instance.client;
  Map<String, dynamic>? _summary;
  bool _loading = true, _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    if (mounted) setState(() => _loading = true);
    try {
      final res =
      await _c.rpc('get_shift_summary', params: {'p_shift_id': widget.id});
      if (!mounted) return;
      final summary = res != null
          ? Map<String, dynamic>.from(
          ((res as Map?)?.cast<String, dynamic>()) ?? {})
          : null;
      if (mounted)
        setState(() {
          _summary = summary;
          _loading = false;
        });
      // Pre-load batch loss once we know the shift is closed
      final shiftStatus = summary?['shift']?['status'] as String?;
      if (shiftStatus == 'closed' && _batchLoss == null) {
        _loadBatchLoss();
      }
      _loadTransferHistory();
    } catch (e) {
      if (!mounted) return;
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic>? _batchLoss;

  Future<void> _loadBatchLoss() async {
    try {
      final res = await _c
          .rpc('get_batch_loss_summary', params: {'p_shift_id': widget.id});
      if (mounted)
        setState(() => _batchLoss = (res as Map?)?.cast<String, dynamic>());
    } catch (_) {}
  }

  // ── Transfer History — every bird_transfer touching this shift, either as
  // the sending or receiving leg. Scoped via stock_ledger.shift_id, since
  // bird_transfers itself is not shift-scoped (one transfer, two shifts).
  List<Map<String, dynamic>> _transferHistory = [];

  Future<void> _loadTransferHistory() async {
    try {
      final ledgerRows = await _c
          .from('stock_ledger')
          .select('reference_id')
          .eq('shift_id', widget.id)
          .eq('reference_type', 'bird_transfer');
      final transferIds = (ledgerRows as List)
          .map((r) => r['reference_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      if (transferIds.isEmpty) {
        if (mounted) setState(() => _transferHistory = []);
        return;
      }
      final res = await _c
          .from('bird_transfers')
          .select(
          'id,bird_count,weight_kg,created_at,transfer_reason,'
              'from_agent:delivery_agents!bird_transfers_from_agent_id_fkey(name),'
              'to_agent:delivery_agents!bird_transfers_to_agent_id_fkey(name)')
          .inFilter('id', transferIds)
          .order('created_at');
      if (mounted) {
        setState(() =>
        _transferHistory = List<Map<String, dynamic>>.from(res as List));
      }
    } catch (_) {}
  }

  Future<void> _approveShift() async {
    await _loadBatchLoss();
    if (!mounted) return;

    final bl     = _batchLoss;
    final totals = bl?['shift_totals'] as Map<String, dynamic>?;

    final dcBirds      = (totals?['total_dc_birds']           as num?)?.toInt()    ?? 0;
    final dcKg         = (totals?['total_dc_weight_kg']       as num?)?.toDouble() ?? 0;
    final delBirds     = (totals?['total_delivered_birds']    as num?)?.toInt()    ?? 0;
    final delKg        = (totals?['total_delivered_kg']       as num?)?.toDouble() ?? 0;
    final liveRetBirds = (totals?['shift_close_return_birds'] as num?)?.toInt()    ?? 0;
    final liveRetKg    = (totals?['shift_close_return_kg']    as num?)?.toDouble() ?? 0;
    final mortBirds    = (totals?['total_mortality_birds']    as num?)?.toInt()    ?? 0;
    final mortKg       = (totals?['total_mortality_kg']       as num?)?.toDouble() ?? 0;
    final delMortBirds = (totals?['delivery_mortality_birds'] as num?)?.toInt()    ?? 0;
    final delMortKg    = (totals?['delivery_mortality_kg']    as num?)?.toDouble() ?? 0;
    final retMortBirds = (totals?['return_mortality_birds']   as num?)?.toInt()    ?? 0;
    final retMortKg    = (totals?['return_mortality_kg']      as num?)?.toDouble() ?? 0;
    final transferInBirds  = (totals?['total_transferred_in_birds']  as num?)?.toInt()    ?? 0;
    final transferInKg     = (totals?['total_transferred_in_kg']     as num?)?.toDouble() ?? 0;
    final transferOutBirds = (totals?['total_transferred_out_birds'] as num?)?.toInt()    ?? 0;
    final transferOutKg    = (totals?['total_transferred_out_kg']    as num?)?.toDouble() ?? 0;
    final lossKg       = (totals?['unaccounted_loss_kg']      as num?)?.toDouble() ?? 0;
    final totalLossKg  = (totals?['total_loss_kg']            as num?)?.toDouble() ?? 0;
    final lossPct      = (dcKg + transferInKg) > 0 ? (lossKg / (dcKg + transferInKg) * 100) : 0.0;
    final hasDelMort   = delMortBirds > 0;
    final hasRetMort   = retMortBirds > 0;

    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
          contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          title: const Row(children: [
            Icon(Icons.fact_check_outlined, size: 18, color: kNavy),
            SizedBox(width: 8),
            Text('Approve Shift',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ]),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(kRadiusCard),
                      border: Border.all(color: kBorderLight)),
                  child: Column(children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        const Expanded(flex: 3, child: SizedBox()),
                        SizedBox(width: 80, child: Text('Birds',
                            textAlign: TextAlign.right,
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
                                color: kTextHint, letterSpacing: 0.5))),
                        SizedBox(width: 86, child: Text('Weight',
                            textAlign: TextAlign.right,
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
                                color: kTextHint, letterSpacing: 0.5))),
                      ]),
                    ),
                    _approvalReconRow('DC Loaded', dcBirds, dcKg,
                        Colors.blue, false, prefix: '+'),
                    if (transferInBirds > 0 || transferInKg > 0)
                      _approvalReconRow('Transfer In', transferInBirds, transferInKg,
                          Colors.green, false, prefix: '+'),
                    _approvalReconRow('Delivered', delBirds, delKg,
                        Colors.teal, false, prefix: '\u2212'),
                    if (transferOutBirds > 0 || transferOutKg > 0)
                      _approvalReconRow('Transfer Out', transferOutBirds, transferOutKg,
                          Colors.orange, false, prefix: '\u2212'),
                    if (liveRetBirds > 0 || liveRetKg > 0)
                      _approvalReconRow('Live Return (Stock Added)',
                          liveRetBirds, liveRetKg, Colors.indigo, false, prefix: '\u2212'),
                    if (hasDelMort && hasRetMort) ...[
                      _approvalReconRow('Delivery Mortality',
                          delMortBirds, delMortKg, Colors.red, false, prefix: '\u2212'),
                      _approvalReconRow('Dead Return (Mortality)',
                          retMortBirds, retMortKg, Colors.deepOrange, false, prefix: '\u2212'),
                    ] else if (hasRetMort)
                      _approvalReconRow('Dead Return (Mortality)',
                          retMortBirds, retMortKg, Colors.deepOrange, false, prefix: '\u2212')
                    else if (hasDelMort)
                        _approvalReconRow('Delivery Mortality',
                            delMortBirds, delMortKg, Colors.red, false, prefix: '\u2212'),
                    _approvalReconRow('Weight Variance', null, lossKg,
                        lossKg > 0 ? Colors.orange : Colors.green, lossKg > 0,
                        suffix: lossKg > 0 ? '  (${lossPct.toStringAsFixed(1)}%)' : null),
                    const Divider(height: 16, thickness: 1),
                    _approvalReconRow('Total Loss', null, totalLossKg,
                        totalLossKg > 0 ? Colors.red : Colors.green, totalLossKg > 0),
                  ]),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: totalLossKg > 0 ? Colors.orange.shade50 : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(kRadiusInner),
                    border: Border.all(color: totalLossKg > 0
                        ? Colors.orange.shade200 : Colors.green.shade200),
                  ),
                  child: Text(
                      totalLossKg > 0
                          ? 'Approving will:\n'
                          '\u2022 Record ${totalLossKg.toStringAsFixed(2)} kg total loss in audit log\n'
                          '\u2022 Classify: ${mortKg.toStringAsFixed(2)} kg mortality + '
                          '${lossKg.toStringAsFixed(2)} kg weight variance\n'
                          '\u2022 Reset agent stock to zero\n'
                          '\u2022 Mark shift as approved'
                          : 'No loss. All stock fully accounted for.\n'
                          'Approving will mark the shift as complete.',
                      style: TextStyle(
                          fontSize: 11, height: 1.5,
                          color: totalLossKg > 0
                              ? Colors.deepOrange : Colors.green.shade700)),
                ),
              ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
                child: const Text('Approve & Reset Stock')),
          ]),
    ) ?? false;

    if (!ok || !mounted) return;
    if (mounted) setState(() => _submitting = true);
    try {
      final user = ref.read(appUserProvider).valueOrNull;
      final result = await _c.rpc('approve_shift', params: {
        'p_shift_id':    widget.id,
        'p_approved_by': user?.userId,
        'p_notes':       'Approved by trader admin',
        'p_actor_type':  'trader',
        'p_entry_mode':  'system',
      });
      final r           = result as Map<String, dynamic>?;
      final resetBirds  = (r?['stock_reset_birds']   as num?)?.toInt()    ?? 0;
      final lossResult  = (r?['unaccounted_loss_kg'] as num?)?.toDouble() ?? 0;
      final mortResult  = (r?['total_mortality_kg']  as num?)?.toDouble() ?? 0;
      _load();
      if (mounted)
        showSuccess(context,
          'Shift approved \u2713\n'
              'Mortality: ${mortResult.toStringAsFixed(2)} kg\n'
              'Weight Variance: ${lossResult.toStringAsFixed(2)} kg\n'
              '${resetBirds > 0 ? 'Stock reset: $resetBirds birds' : 'Stock fully settled'}',
        );
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }


  // ── _approvalReconRow ─────────────────────────────────────────────────────
  // 3-column reconciliation row: label | birds | kg
  // Used in both the approval dialog and _buildBatchLossPanel.
  static Widget _approvalReconRow(
      String label,
      int?   birds,
      double kg,
      Color  c,
      bool   highlight, {
        String? prefix,
        String? suffix,
      }) {
    final String birdsStr = birds != null ? '${prefix ?? ""}$birds birds' : '';
    final String kgStr    =
        '${prefix ?? ""}${kg.toStringAsFixed(2)} kg${suffix ?? ""}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(
            flex: 3,
            child: Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: highlight ? c : kTextSub,
                    fontWeight:
                    highlight ? FontWeight.w700 : FontWeight.w400))),
        SizedBox(
            width: 80,
            child: Text(birdsStr,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: highlight ? c : kTextMain))),
        SizedBox(
            width: 86,
            child: Text(kgStr,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: highlight ? c : kTextMain))),
      ]),
    );
  }


  static Widget _approvalRow(String label, String value, bool isLoss) =>
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child:
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: isLoss ? Colors.red : const Color(0xFF424242))),
            Text(value,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isLoss ? Colors.red : const Color(0xFF212121))),
          ]));

  Future<void> _rejectShift() async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          title: const Text('Reject Shift'),
          content: TextField(
              controller: ctrl,
              decoration: const InputDecoration(labelText: 'Reason *'),
              autofocus: true),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () {
                  if (ctrl.text.trim().isNotEmpty)
                    Navigator.pop(ctx, ctrl.text.trim());
                },
                child: const Text('Reject'))
          ],
        ));
    ctrl.dispose();
    if (reason == null || !mounted) return;
    if (mounted) setState(() => _submitting = true);
    try {
      await _c.from('delivery_shifts').update({
        'shift_approval_status': 'rejected',
        'shift_approval_notes': reason
      }).eq('id', widget.id);
      _load();
      if (mounted) showSuccess(context, 'Shift rejected');
    } catch (e) {
      if (mounted) showError(context, e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _buildScaffold(BuildContext context) {
    if (_loading)
      return const Scaffold(backgroundColor: kBgPage, body: LoadingList());
    if (_summary == null)
      return Scaffold(
          backgroundColor: kBgPage,
          appBar: AppBar(
              backgroundColor: kSurface, title: const Text('Shift Detail')),
          body: const Center(child: Text('No data')));

    final shift = _summary!['shift'] as Map<String, dynamic>?;
    final totals = _summary!['totals'] as Map<String, dynamic>?;
    final deliveries =
    (_summary!['deliveries'] as List? ?? []).cast<Map<String, dynamic>>();
    final challans =
    (_summary!['challans'] as List? ?? []).cast<Map<String, dynamic>>();
    final shiftStatus = shift?['status'] as String? ?? 'open';
    final approvalStatus =
        shift?['shift_approval_status'] as String? ?? 'pending';

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
          backgroundColor: kSurface,
          title: Text(shift?['agent_name'] as String? ?? 'Shift Detail'),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load)
          ]),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            // ── Status header ────────────────────────────────────────────
            Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: shiftStatus == 'closed'
                        ? Colors.green.shade600
                        : kPrimary,
                    borderRadius: BorderRadius.circular(kRadiusCard)),
                child: Row(children: [
                  Icon(
                      shiftStatus == 'closed'
                          ? Icons.check_circle_outline
                          : Icons.access_time_outlined,
                      color: Colors.white,
                      size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(shift?['agent_name'] as String? ?? '—',
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white)),
                            Text(
                                '${shift?['vehicle_no'] ?? ''}  |  Shift ${shiftStatus.toUpperCase()}',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                          ])),
                  if (approvalStatus != 'pending')
                    StatusBadge(
                        approvalStatus,
                        approvalStatus == 'approved'
                            ? Colors.green.shade300
                            : Colors.red.shade300),
                ])),
            const SizedBox(height: 12),

            // ── Odometer & Distance ─────────────────────────────────────
            _buildOdometerSection(shift),
            const SizedBox(height: 10),

            // ── DC / Purchase Summary ────────────────────────────────────
            if (challans.isNotEmpty)
              WhiteCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeader('DELIVERY CHALLANS (FARM PURCHASE)'),
                        ...challans.map((ch) {
                          final date =
                          DateTime.tryParse(ch['dc_date'] as String? ?? '');
                          final photoUrl = ch['dc_photo_url'] as String?;
                          return ListTile(
                            dense: true,
                            leading: photoUrl != null && photoUrl.isNotEmpty
                                ? GestureDetector(
                                onTap: () => _showFullImage(
                                    context, photoUrl,
                                    'DC Photo — ${ch['dc_number']}'),
                                child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.network(
                                      photoUrl,
                                      width: 36, height: 36,
                                      fit: BoxFit.cover,
                                      loadingBuilder: (ctx, child, prog) =>
                                      prog == null
                                          ? child
                                          : Container(
                                          width: 36, height: 36,
                                          color: kPrimary.withValues(alpha: 0.08),
                                          child: const Center(
                                              child: SizedBox(
                                                  width: 14, height: 14,
                                                  child: CircularProgressIndicator(
                                                      strokeWidth: 2, color: kPrimary)))),
                                      errorBuilder: (_, __, ___) => Container(
                                          width: 36, height: 36,
                                          color: kPrimary.withValues(alpha: 0.08),
                                          child: const Icon(Icons.broken_image_outlined,
                                              size: 16, color: kPrimary)),
                                    )))
                                : const Icon(Icons.receipt_long_outlined,
                                color: kPrimary, size: 20),
                            title: Text(
                                '${ch['dc_number']} — ${ch['farmer_name'] ?? '—'}',
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600)),
                            subtitle: Text(
                                '${ch['bird_count'] ?? 0} birds · ${(ch['net_weight'] as num?)?.toStringAsFixed(1) ?? 0} kg · ${ch['crates_count'] ?? 0} crates',
                                style: const TextStyle(fontSize: 11)),
                            trailing: date != null
                                ? Text(DateFormat('d MMM').format(date),
                                style: const TextStyle(
                                    fontSize: 11, color: kTextHint))
                                : null,
                          );
                        }),
                        Divider(height: 12),
                        _trow('Total DC Birds',
                            '${totals?['total_dc_birds'] ?? 0} birds'),
                        _trow('Total DC Weight',
                            '${(totals?['total_dc_weight_kg'] as num?)?.toStringAsFixed(1) ?? 0} kg'),
                      ])),
            const SizedBox(height: 10),

            // ── Delivery summary ─────────────────────────────────────────
            WhiteCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader('DELIVERY SUMMARY'),
                      // Order status row
                      Builder(builder: (_) {
                        final osc = totals?['order_status_counts'] as Map?;
                        final total     = (osc?['total']     as num?)?.toInt() ?? 0;
                        final delivered = (osc?['delivered'] as num?)?.toInt() ?? 0;
                        final partial   = (osc?['partial']   as num?)?.toInt() ?? 0;
                        final pending   = (osc?['pending']   as num?)?.toInt() ?? 0;
                        final cancelled = (osc?['cancelled'] as num?)?.toInt() ?? 0;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Wrap(spacing: 8, runSpacing: 6, children: [
                            _statusPill('$total Orders', kPrimary),
                            _statusPill('$delivered Delivered', Colors.green),
                            if (partial > 0)
                              _statusPill('$partial Partial', Colors.orange),
                            if (pending > 0)
                              _statusPill('$pending Pending', Colors.amber.shade700),
                            if (cancelled > 0)
                              _statusPill('$cancelled Cancelled', Colors.red),
                          ]),
                        );
                      }),
                      // Main stat boxes
                      Row(children: [
                        _sbox('Delivered', '${totals?['deliveries_count'] ?? 0}',
                            kPrimary),
                        _sbox(
                            'Birds', '${totals?['total_birds'] ?? 0}', Colors.blue),
                        _sbox(
                            'Weight',
                            '${(totals?['total_weight_kg'] as num?)?.toStringAsFixed(1) ?? 0} kg',
                            Colors.teal),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        _sbox('Mortality',
                            '${totals?['total_mortality'] ?? 0}b  '
                                '${(totals?['total_mortality_kg'] as num?)?.toStringAsFixed(1) ?? '0'} kg',
                            Colors.red),
                        _sbox('Customer Returns',
                            '${totals?['total_returned'] ?? 0} b',
                            Colors.purple),
                        _sbox(
                            'Crates Pending',
                            '${(() { final g = (totals?['crates_given'] as num?)?.toInt() ?? 0; final b = (totals?['crates_back'] as num?)?.toInt() ?? 0; return (g - b).clamp(0, 9999); })()}',
                            Colors.orange),
                      ]),
                      // Live return row — shown when > 0 (shift-close return, NOT customer return)
                      Builder(builder: (_) {
                        final liveB  = (totals?['auto_returned_birds'] as num?)?.toInt()    ?? 0;
                        final liveKg = (totals?['auto_returned_kg']    as num?)?.toDouble() ?? 0;
                        if (liveB == 0 && liveKg == 0) return const SizedBox.shrink();
                        return Container(
                          margin: const EdgeInsets.only(top: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(kRadiusInner),
                            border: Border.all(color: Colors.indigo.shade200),
                          ),
                          child: Row(children: [
                            const Icon(Icons.undo_rounded, size: 14, color: Colors.indigo),
                            const SizedBox(width: 8),
                            Expanded(child: Text(
                              'Live Return to Stock (Shift End)',
                              style: TextStyle(fontSize: 11, color: Colors.indigo.shade700,
                                  fontWeight: FontWeight.w600),
                            )),
                            Text('$liveB birds  ·  ${liveKg.toStringAsFixed(1)} kg',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                                    color: Colors.indigo.shade700)),
                          ]),
                        );
                      }),
                    ])),
            const SizedBox(height: 10),

            // ── Cash & Payment summary ────────────────────────────────────
            WhiteCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader('CASH & PAYMENT'),
                      _trow(
                          'Total Collected',
                          Fmt.amount(
                              (totals?['total_collected'] as num?)?.toDouble() ??
                                  0),
                          color: kPrimary, bold: true),
                      const SizedBox(height: 4),
                      _trow(
                          'Cash',
                          Fmt.amount(
                              (totals?['cash_collected'] as num?)?.toDouble() ??
                                  0)),
                      _trow(
                          'UPI',
                          Fmt.amount(
                              (totals?['upi_collected'] as num?)?.toDouble() ?? 0)),
                      _trow(
                          'Credit',
                          Fmt.amount(
                              (totals?['credit_collected'] as num?)?.toDouble() ?? 0)),
                      _trow(
                          'Bank',
                          Fmt.amount(
                              (totals?['bank_collected'] as num?)?.toDouble() ?? 0)),
                      const Divider(height: 12),
                      _trow(
                          'Expenses',
                          Fmt.amount(
                              (totals?['total_expenses'] as num?)?.toDouble() ?? 0),
                          color: Colors.red),
                      const Divider(height: 12),
                      _trow(
                          'Net Cash to Hand',
                          Fmt.amount(
                              (totals?['net_cash'] as num?)?.toDouble() ?? 0),
                          color: kPrimary,
                          bold: true),
                    ])),
            const SizedBox(height: 10),

            // ── Product Movement ──────────────────────────────────────────
            // From stock_ledger per product — shows what was purchased, delivered, returned.
            // Answers: which product moved, how much, and what remains accounted.
            Builder(builder: (_) {
              final productSummary = (totals?['product_summary'] as List? ?? [])
                  .cast<Map<String, dynamic>>()
                  .where((p) =>
              (p['purchased_birds'] as int? ?? 0) > 0 ||
                  (p['delivered_birds'] as int? ?? 0) > 0 ||
                  (p['returned_birds']  as int? ?? 0) > 0 ||
                  (p['mortality_birds'] as int? ?? 0) > 0 ||
                  (p['transferred_out_birds'] as int? ?? 0) > 0 ||
                  (p['transferred_in_birds']  as int? ?? 0) > 0)
                  .toList();
              if (productSummary.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader('PRODUCT MOVEMENT'),
                  ...productSummary.map((p) {
                    final name    = p['product_name'] as String? ?? '';
                    final cat     = p['category']     as String? ?? '';
                    final pBirds  = (p['purchased_birds']  as num?)?.toInt()    ?? 0;
                    final pKg     = (p['purchased_kg']     as num?)?.toDouble() ?? 0;
                    final dBirds  = (p['delivered_birds']  as num?)?.toInt()    ?? 0;
                    final dKg     = (p['delivered_kg']     as num?)?.toDouble() ?? 0;
                    final rBirds  = (p['returned_birds']   as num?)?.toInt()    ?? 0;
                    final rKg     = (p['returned_kg']      as num?)?.toDouble() ?? 0;
                    final mBirds  = (p['mortality_birds']  as num?)?.toInt()    ?? 0;
                    final mKg     = (p['mortality_kg']     as num?)?.toDouble() ?? 0;
                    final toBirds = (p['transferred_out_birds'] as num?)?.toInt()    ?? 0;
                    final toKg    = (p['transferred_out_kg']    as num?)?.toDouble() ?? 0;
                    final tiBirds = (p['transferred_in_birds']  as num?)?.toInt()    ?? 0;
                    final tiKg    = (p['transferred_in_kg']     as num?)?.toDouble() ?? 0;
                    final color   = switch (cat) {
                      'broiler' => const Color(0xFF00796B),
                      'country' => const Color(0xFF6D4C41),
                      'quail'   => Colors.purple,
                      _         => Colors.indigo,
                    };
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(kRadiusCard),
                        border: Border.all(color: color.withValues(alpha: 0.3)),
                        boxShadow: kCardShadow,
                      ),
                      child: Column(children: [
                        // Product header
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.08),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                          ),
                          child: Row(children: [
                            Container(width: 10, height: 10,
                                decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Text(name, style: TextStyle(fontSize: 13,
                                fontWeight: FontWeight.w800, color: color)),
                            const Spacer(),
                            // Column headers
                            SizedBox(width: 68, child: Text('Birds',
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 9,
                                    fontWeight: FontWeight.w700, color: kTextHint))),
                            SizedBox(width: 72, child: Text('Weight',
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 9,
                                    fontWeight: FontWeight.w700, color: kTextHint))),
                          ]),
                        ),
                        // Movement rows
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                          child: Column(children: [
                            if (pBirds > 0 || pKg > 0)
                              _productMoveRow('Loaded', pBirds, pKg, Colors.blue, prefix: '+'),
                            if (tiBirds > 0 || tiKg > 0)
                              _productMoveRow('Transfer In', tiBirds, tiKg, Colors.green, prefix: '+'),
                            if (dBirds > 0 || dKg > 0)
                              _productMoveRow('Delivered', dBirds, dKg, Colors.teal, prefix: '−'),
                            if (toBirds > 0 || toKg > 0)
                              _productMoveRow('Transfer Out', toBirds, toKg, Colors.orange, prefix: '−'),
                            if (rBirds > 0 || rKg > 0)
                              _productMoveRow('Live Return', rBirds, rKg, Colors.indigo, prefix: '−'),
                            if (mBirds > 0 || mKg > 0)
                              _productMoveRow('Mortality', mBirds, mKg, Colors.red, prefix: '−'),
                          ]),
                        ),
                      ]),
                    );
                  }),
                  const SizedBox(height: 4),
                ],
              );
            }),

            // ── Transfer History ────────────────────────────────────────────
            // Every bird_transfer touching this shift, either as the sending
            // or receiving side. Sourced from bird_transfers, scoped via
            // stock_ledger.shift_id (see _loadTransferHistory).
            if (_transferHistory.isNotEmpty) ...[
              const SectionHeader('TRANSFER HISTORY'),
              ..._transferHistory.map((t) {
                final fromName = (t['from_agent'] as Map?)?['name'] as String? ?? '—';
                final toName   = (t['to_agent']   as Map?)?['name'] as String? ?? '—';
                final birds    = (t['bird_count'] as num?)?.toInt()    ?? 0;
                final kg       = (t['weight_kg']  as num?)?.toDouble() ?? 0;
                final createdAt = DateTime.tryParse(t['created_at'] as String? ?? '');
                final reason   = t['transfer_reason'] as String?;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(kRadiusCard),
                    border: Border.all(color: kBorderLight),
                    boxShadow: kCardShadow,
                  ),
                  child: Row(children: [
                    const Icon(Icons.swap_horiz_rounded,
                        size: 18, color: Colors.deepPurple),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text(fromName, style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700,
                                color: kTextMain)),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 6),
                              child: Icon(Icons.arrow_forward_rounded,
                                  size: 12, color: kTextHint),
                            ),
                            Text(toName, style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700,
                                color: kTextMain)),
                          ]),
                          const SizedBox(height: 2),
                          Text(
                              createdAt != null
                                  ? DateFormat('d MMM, h:mm a').format(createdAt)
                                  : '—',
                              style: const TextStyle(fontSize: 10, color: kTextHint)),
                          if (reason != null && reason.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(reason,
                                style: const TextStyle(fontSize: 10, color: kTextSub)),
                          ],
                        ],
                      ),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('$birds birds', style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700,
                          color: kTextMain)),
                      Text('${kg.toStringAsFixed(1)} kg', style: const TextStyle(
                          fontSize: 11, color: kTextSub)),
                    ]),
                  ]),
                );
              }),
              const SizedBox(height: 4),
            ],

            // ── Per-delivery breakdown ────────────────────────────────────
            if (deliveries.isNotEmpty) ...[
              const SectionHeader('PER DELIVERY BREAKDOWN'),
              ...deliveries.map((d) {
                final status = d['status'] as String? ?? '—';
                final approved = d['approval_status'] as String? ?? 'pending';
                final birds = d['delivered_bird_count'] as int? ?? 0;
                final weight =
                    (d['delivered_total_weight'] as num?)?.toDouble() ?? 0;
                final collected =
                    (d['collected_amount'] as num?)?.toDouble() ?? 0;
                final mortality = d['mortality_birds'] as int? ?? 0;
                return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(kRadiusCard),
                        border: Border.all(color: kBorderLight),
                        boxShadow: kCardShadow),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                              child: Row(children: [
                                Expanded(
                                    child: Text(
                                        d['shop_name'] as String? ?? '—',
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700))),
                                StatusBadge(status, SC.order(status),
                                    small: true),
                                const SizedBox(width: 4),
                                StatusBadge(
                                    approved,
                                    approved == 'approved'
                                        ? Colors.green
                                        : Colors.orange,
                                    small: true),
                              ])),
                          Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                              child: Row(children: [
                                Text(
                                    '$birds birds · ${weight.toStringAsFixed(1)} kg',
                                    style: const TextStyle(
                                        fontSize: 11, color: kTextSub)),
                                const Spacer(),
                                if (mortality > 0)
                                  Text('💀 $mortality  ',
                                      style: const TextStyle(
                                          fontSize: 11, color: Colors.red)),
                                Text(Fmt.amount(collected),
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: kPrimary)),
                              ])),
                          // Mortality & delivery proof photos — tap to expand
                          if (d['mortality_proof_url'] != null ||
                              d['delivery_photo_url'] != null)
                            Padding(
                                padding:
                                const EdgeInsets.fromLTRB(12, 0, 12, 10),
                                child: Row(children: [
                                  if (d['mortality_proof_url'] != null)
                                    _miniPhotoTile(
                                        'Mortality Proof',
                                        d['mortality_proof_url'] as String,
                                        Colors.red),
                                  if (d['mortality_proof_url'] != null &&
                                      d['delivery_photo_url'] != null)
                                    const SizedBox(width: 8),
                                  if (d['delivery_photo_url'] != null)
                                    _miniPhotoTile(
                                        'Delivery Proof',
                                        d['delivery_photo_url'] as String,
                                        Colors.blue),
                                ]))
                          else
                            const SizedBox(height: 2),
                        ]));
              }),
            ],
            const SizedBox(height: 16),

            // ── Phase 7: Expense Validation Panel ────────────────────────────────
            if (shiftStatus == 'closed') ...[
              const SectionHeader('EXPENSE VALIDATION'),
              ShiftExpenseValidationPanel(
                shiftId: widget.id,
                initialStatus: shift?['expense_validation_status'] as String?,
              ),
              const SizedBox(height: 12),
            ],

            // ── Approval actions ──────────────────────────────────────────
            // ── Batch Loss Summary panel ──────────────────────────────────────
            if (shiftStatus == 'closed') ...[
              const SectionHeader('BATCH-LEVEL LOSS CALCULATION'),
              _buildBatchLossPanel(),
              const SizedBox(height: 12),
            ],

            if (shiftStatus == 'closed' && approvalStatus == 'pending') ...[
              Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(kRadiusCard),
                      border: Border.all(color: Colors.orange.shade200)),
                  child: const Row(children: [
                    Icon(Icons.pending_actions_outlined,
                        color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                        child: Text(
                            'Review all deliveries above, then approve or reject this shift.',
                            style: TextStyle(
                                fontSize: 13,
                                color: Colors.orange,
                                fontWeight: FontWeight.w600))),
                  ])),
              // Phase 6: structured verification before approval
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context)
                    .push(
                  MaterialPageRoute(
                      builder: (_) =>
                          ShiftVerificationScreen(shiftId: widget.id)),
                )
                    .then((_) => _load()),
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: const Text('Review Deliveries Line-by-Line'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kNavy,
                  side: const BorderSide(color: kNavy),
                  minimumSize: const Size(double.infinity, 44),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: _submitting ? null : _approveShift,
                icon: _submitting
                    ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle_outline),
                label: const Text('Approve Shift ✓'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _submitting ? null : _rejectShift,
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Reject / Flag Discrepancy'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: kError,
                    side: const BorderSide(color: kError)),
              ),
            ] else if (approvalStatus == 'approved')
              Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(kRadiusCard),
                      border: Border.all(color: Colors.green.shade200)),
                  child: const Row(children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 22),
                    SizedBox(width: 10),
                    Text('Shift Approved ✓',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.green)),
                  ])),
            const SizedBox(height: 20),
          ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // DESKTOP LAYOUT — visual redesign only. Reads the exact same _summary /
  // _batchLoss / _transferHistory state already loaded by _load() /
  // _loadBatchLoss() / _loadTransferHistory() above; no new data fetching,
  // no new RPC calls, no changed business logic. Every action button below
  // calls the exact same _approveShift() / _rejectShift() / navigation used
  // by the mobile _buildScaffold(), which is completely untouched.
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildDesktopScaffold(BuildContext context) {
    if (_loading)
      return const Scaffold(backgroundColor: kBgPage, body: LoadingList());
    if (_summary == null)
      return Scaffold(
          backgroundColor: kBgPage,
          appBar: AppBar(
              backgroundColor: kSurface, title: const Text('Shift Approval')),
          body: const Center(child: Text('No data')));

    final shift = _summary!['shift'] as Map<String, dynamic>?;
    final totals = _summary!['totals'] as Map<String, dynamic>?;
    final deliveries =
    (_summary!['deliveries'] as List? ?? []).cast<Map<String, dynamic>>();
    final challans =
    (_summary!['challans'] as List? ?? []).cast<Map<String, dynamic>>();
    final shiftStatus = shift?['status'] as String? ?? 'open';
    final approvalStatus =
        shift?['shift_approval_status'] as String? ?? 'pending';

    // Read-only derived flags for badges/checklist — same values already
    // computed and displayed elsewhere on this screen (batch loss panel),
    // just surfaced here too for visibility. No new thresholds, no new logic.
    final btTotals =
    (_batchLoss?['shift_totals'] as Map?)?.cast<String, dynamic>();
    final bDcKg = (btTotals?['total_dc_weight_kg'] as num?)?.toDouble() ?? 0;
    final bTransferInKg =
        (btTotals?['total_transferred_in_kg'] as num?)?.toDouble() ?? 0;
    final bLossKg =
        (btTotals?['unaccounted_loss_kg'] as num?)?.toDouble() ?? 0;
    final bInbound = bDcKg + bTransferInKg;
    final bLossPct = bInbound > 0 ? (bLossKg / bInbound * 100) : 0.0;
    final isHighLoss = bLossPct >= 2;
    final expenseStatus = shift?['expense_validation_status'] as String?;
    final expensePending = expenseStatus != 'validated';
    final missingPhotoCount = challans
        .where((c) =>
    (c['dc_photo_url'] as String?) == null ||
        (c['dc_photo_url'] as String).isEmpty)
        .length;

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kSurface,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: kTextMain),
        title: Text(shift?['agent_name'] as String? ?? 'Shift Approval',
            style: const TextStyle(
                fontWeight: FontWeight.w800, fontSize: 16, color: kTextMain)),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _load)
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
          child: _desktopTopHeader(shift, shiftStatus, approvalStatus,
              isHighLoss, expensePending, missingPhotoCount),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
          child: _desktopKpiRow(shift, totals),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 7,
                  child: SingleChildScrollView(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _desktopProductMovement(totals),
                          const SizedBox(height: 16),
                          if (challans.isNotEmpty) ...[
                            _desktopChallans(challans, totals),
                            const SizedBox(height: 16),
                          ],
                          _desktopDeliverySummary(totals),
                          const SizedBox(height: 16),
                          if (_transferHistory.isNotEmpty) ...[
                            _desktopTransferHistory(),
                            const SizedBox(height: 16),
                          ],
                          if (deliveries.isNotEmpty) ...[
                            _desktopPerDeliveryBreakdown(deliveries),
                            const SizedBox(height: 16),
                          ],
                          if (shiftStatus == 'closed') ...[
                            _desktopSectionCard(
                              title: 'BATCH-LEVEL LOSS CALCULATION',
                              icon: Icons.calculate_outlined,
                              child: _buildBatchLossPanel(),
                            ),
                            const SizedBox(height: 16),
                            _desktopSectionCard(
                              title: 'EXPENSE VALIDATION',
                              icon: Icons.receipt_long_outlined,
                              child: ShiftExpenseValidationPanel(
                                shiftId: widget.id,
                                initialStatus: shift?['expense_validation_status']
                                as String?,
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          _desktopApprovalNotes(shift),
                          const SizedBox(height: 8),
                        ]),
                  ),
                ),
                const SizedBox(width: 24),
                SizedBox(
                  width: 360,
                  child: _desktopRightPanel(
                      context,
                      shift,
                      totals,
                      shiftStatus,
                      approvalStatus,
                      isHighLoss,
                      expensePending,
                      missingPhotoCount,
                      challans,
                      deliveries),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  // ── Top header ───────────────────────────────────────────────────────
  Widget _desktopTopHeader(
      Map<String, dynamic>? shift,
      String shiftStatus,
      String approvalStatus,
      bool isHighLoss,
      bool expensePending,
      int missingPhotoCount) {
    final startAt =
    DateTime.tryParse(shift?['shift_start_at'] as String? ?? '');
    final rawShiftId = (shift?['id'] as String?) ?? '';
    final shiftIdShort = rawShiftId.isEmpty
        ? '—'
        : rawShiftId.substring(0, rawShiftId.length < 8 ? rawShiftId.length : 8)
        .toUpperCase();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorderLight),
        boxShadow: kCardShadow,
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: kNavy.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.local_shipping_outlined,
              color: kNavy, size: 26),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shift?['agent_name'] as String? ?? '—',
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: kTextMain)),
                const SizedBox(height: 6),
                Wrap(
                    spacing: 14,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _headerMeta(Icons.local_shipping_outlined,
                          shift?['vehicle_no'] as String? ?? 'No vehicle'),
                      _headerMeta(Icons.tag_outlined, 'Shift $shiftIdShort'),
                      _headerMeta(
                          Icons.calendar_today_outlined,
                          startAt != null
                              ? DateFormat('d MMM yyyy').format(startAt)
                              : '—'),
                    ]),
              ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
            StatusBadge(shiftStatus == 'closed' ? 'SHIFT CLOSED' : 'SHIFT OPEN',
                shiftStatus == 'closed' ? Colors.green : kPrimary),
            if (approvalStatus != 'pending')
              StatusBadge(approvalStatus.toUpperCase(),
                  approvalStatus == 'approved' ? Colors.green : kError),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.end, children: [
            if (isHighLoss) _headerAlertChip('High Loss', Colors.red),
            if (expensePending && shiftStatus == 'closed')
              _headerAlertChip('Expense Pending', Colors.orange),
            if (missingPhotoCount > 0)
              _headerAlertChip(
                  '$missingPhotoCount DC Photo${missingPhotoCount > 1 ? 's' : ''} Missing',
                  Colors.amber.shade700),
          ]),
        ]),
      ]),
    );
  }

  Widget _headerMeta(IconData icon, String text) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: kTextHint),
        const SizedBox(width: 4),
        Text(text,
            style: const TextStyle(
                fontSize: 12.5, color: kTextSub, fontWeight: FontWeight.w600)),
      ]);

  Widget _headerAlertChip(String label, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: c.withValues(alpha: 0.3)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.warning_amber_rounded, size: 12, color: c),
      const SizedBox(width: 4),
      Text(label,
          style:
          TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c)),
    ]),
  );

  // ── KPI row ──────────────────────────────────────────────────────────
  Widget _desktopKpiRow(
      Map<String, dynamic>? shift, Map<String, dynamic>? totals) {
    final odoStart = (shift?['odometer_start'] as num?)?.toDouble();
    final odoEnd = (shift?['odometer_end'] as num?)?.toDouble();
    final distKm = odoEnd != null && odoStart != null
        ? (odoEnd - odoStart).abs()
        : (shift?['distance_km'] as num?)?.toDouble() ?? 0;
    final startPhoto = shift?['odometer_start_photo'] as String?;
    final endPhoto = shift?['odometer_end_photo'] as String?;
    final mortBirds = (totals?['total_mortality'] as num?)?.toInt() ?? 0;
    final mortKg = (totals?['total_mortality_kg'] as num?)?.toDouble() ?? 0;
    final netCash = (totals?['net_cash'] as num?)?.toDouble() ?? 0;
    final expenseStatus = shift?['expense_validation_status'] as String?;

    return Row(children: [
      Expanded(
          child:
          _desktopOdoKpi('Start Odometer', odoStart, startPhoto, Colors.blue)),
      const SizedBox(width: 14),
      Expanded(
          child:
          _desktopOdoKpi('End Odometer', odoEnd, endPhoto, Colors.teal)),
      const SizedBox(width: 14),
      Expanded(
          child: _desktopKpi('Distance Travelled', '${distKm.toStringAsFixed(0)} km',
              Icons.route_outlined, Colors.indigo)),
      const SizedBox(width: 14),
      Expanded(
          child: _desktopKpi(
              'Total Mortality',
              '$mortBirds birds',
              Icons.warning_amber_rounded,
              mortBirds > 0 ? Colors.red : Colors.green,
              sub: '${mortKg.toStringAsFixed(1)} kg')),
      const SizedBox(width: 14),
      Expanded(
          child: _desktopKpi('Net Cash to Hand', Fmt.amount(netCash),
              Icons.account_balance_wallet_outlined, kPrimary)),
      const SizedBox(width: 14),
      Expanded(
          child: _desktopKpi(
              'Expense Validation',
              expenseStatus == 'validated' ? 'Validated' : 'Pending',
              expenseStatus == 'validated'
                  ? Icons.check_circle_outline
                  : Icons.pending_outlined,
              expenseStatus == 'validated' ? Colors.green : Colors.orange)),
    ]);
  }

  Widget _desktopKpi(String label, String value, IconData icon, Color c,
      {String? sub}) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kBorderLight),
          boxShadow: kCardShadow,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 15, color: c),
            const SizedBox(width: 6),
            Expanded(
                child: Text(label.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: kTextHint,
                        letterSpacing: 0.4),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 10),
          Text(value,
              style:
              TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub, style: const TextStyle(fontSize: 11, color: kTextHint)),
          ],
        ]),
      );

  Widget _desktopOdoKpi(
      String label, double? reading, String? photoUrl, Color c) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kBorderLight),
          boxShadow: kCardShadow,
        ),
        child: Row(children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.speed_outlined, size: 14, color: c),
                    const SizedBox(width: 5),
                    Expanded(
                        child: Text(label.toUpperCase(),
                            style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: kTextHint,
                                letterSpacing: 0.4),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis)),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                      reading != null
                          ? '${reading.toStringAsFixed(0)} km'
                          : 'Not captured',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: reading != null ? c : kTextHint)),
                ]),
          ),
          const SizedBox(width: 8),
          if (photoUrl != null && photoUrl.isNotEmpty)
            GestureDetector(
              onTap: () => _showFullImage(context, photoUrl, label),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(photoUrl,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                        width: 44,
                        height: 44,
                        color: c.withValues(alpha: 0.08),
                        child:
                        Icon(Icons.broken_image_outlined, size: 18, color: c))),
              ),
            )
          else
            Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: kBgPage, borderRadius: BorderRadius.circular(8)),
                child:
                const Icon(Icons.no_photography_outlined, size: 18, color: kTextHint)),
        ]),
      );

  // ── Generic section card wrapper ────────────────────────────────────
  Widget _desktopSectionCard(
      {required String title,
        required IconData icon,
        required Widget child,
        Widget? trailing}) =>
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kBorderLight),
          boxShadow: kCardShadow,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 18, color: kNavy),
            const SizedBox(width: 8),
            Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: kTextMain,
                        letterSpacing: 0.3))),
            if (trailing != null) trailing,
          ]),
          const Divider(height: 20, thickness: 1),
          child,
        ]),
      );

  // ── Product Movement ────────────────────────────────────────────────
  Widget _desktopProductMovement(Map<String, dynamic>? totals) {
    final productSummary = (totals?['product_summary'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .where((p) =>
    (p['purchased_birds'] as int? ?? 0) > 0 ||
        (p['delivered_birds'] as int? ?? 0) > 0 ||
        (p['returned_birds'] as int? ?? 0) > 0 ||
        (p['mortality_birds'] as int? ?? 0) > 0 ||
        (p['transferred_out_birds'] as int? ?? 0) > 0 ||
        (p['transferred_in_birds'] as int? ?? 0) > 0)
        .toList();
    if (productSummary.isEmpty) return const SizedBox.shrink();

    return _desktopSectionCard(
      title: 'PRODUCT MOVEMENT',
      icon: Icons.inventory_2_outlined,
      child: Column(
          children: productSummary.map((p) {
            final name = p['product_name'] as String? ?? '';
            final cat = p['category'] as String? ?? '';
            final pBirds = (p['purchased_birds'] as num?)?.toInt() ?? 0;
            final pKg = (p['purchased_kg'] as num?)?.toDouble() ?? 0;
            final dBirds = (p['delivered_birds'] as num?)?.toInt() ?? 0;
            final dKg = (p['delivered_kg'] as num?)?.toDouble() ?? 0;
            final rBirds = (p['returned_birds'] as num?)?.toInt() ?? 0;
            final rKg = (p['returned_kg'] as num?)?.toDouble() ?? 0;
            final mBirds = (p['mortality_birds'] as num?)?.toInt() ?? 0;
            final mKg = (p['mortality_kg'] as num?)?.toDouble() ?? 0;
            final toBirds = (p['transferred_out_birds'] as num?)?.toInt() ?? 0;
            final toKg = (p['transferred_out_kg'] as num?)?.toDouble() ?? 0;
            final tiBirds = (p['transferred_in_birds'] as num?)?.toInt() ?? 0;
            final tiKg = (p['transferred_in_kg'] as num?)?.toDouble() ?? 0;
            final color = switch (cat) {
              'broiler' => const Color(0xFF00796B),
              'country' => const Color(0xFF6D4C41),
              'quail' => Colors.purple,
              _ => Colors.indigo,
            };
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: kBgPage,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: 0.25)),
              ),
              child: Column(children: [
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(11)),
                  ),
                  child: Row(children: [
                    Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    Text(name,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: color)),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Wrap(spacing: 28, runSpacing: 12, children: [
                    if (pBirds > 0 || pKg > 0)
                      _desktopMoveStat('Loaded', pBirds, pKg, Colors.blue, '+'),
                    if (tiBirds > 0 || tiKg > 0)
                      _desktopMoveStat(
                          'Transfer In', tiBirds, tiKg, Colors.green, '+'),
                    if (dBirds > 0 || dKg > 0)
                      _desktopMoveStat(
                          'Delivered', dBirds, dKg, Colors.teal, '−'),
                    if (toBirds > 0 || toKg > 0)
                      _desktopMoveStat(
                          'Transfer Out', toBirds, toKg, Colors.orange, '−'),
                    if (rBirds > 0 || rKg > 0)
                      _desktopMoveStat(
                          'Live Return', rBirds, rKg, Colors.indigo, '−'),
                    if (mBirds > 0 || mKg > 0)
                      _desktopMoveStat(
                          'Mortality', mBirds, mKg, Colors.red, '−'),
                  ]),
                ),
              ]),
            );
          }).toList()),
    );
  }

  Widget _desktopMoveStat(
      String label, int birds, double kg, Color c, String prefix) =>
      SizedBox(
        width: 150,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: kTextHint, fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text('$prefix$birds b',
              style:
              TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c)),
          Text('$prefix${kg.toStringAsFixed(1)} kg',
              style: TextStyle(fontSize: 12, color: c.withValues(alpha: 0.8))),
        ]),
      );

  // ── Delivery Challans (large thumbnails) ────────────────────────────
  Widget _desktopChallans(
      List<Map<String, dynamic>> challans, Map<String, dynamic>? totals) =>
      _desktopSectionCard(
        title: 'DELIVERY CHALLANS (FARM PURCHASE)',
        icon: Icons.receipt_long_outlined,
        trailing: Text(
            '${totals?['total_dc_birds'] ?? 0} birds · '
                '${(totals?['total_dc_weight_kg'] as num?)?.toStringAsFixed(1) ?? 0} kg',
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: kTextSub)),
        child: Column(
            children: challans.map((ch) {
              final date = DateTime.tryParse(ch['dc_date'] as String? ?? '');
              final photoUrl = ch['dc_photo_url'] as String?;
              final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kBgPage,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kBorderLight),
                ),
                child: Row(children: [
                  GestureDetector(
                    onTap: hasPhoto
                        ? () => _showFullImage(
                        context, photoUrl, 'DC Photo — ${ch['dc_number']}')
                        : null,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: hasPhoto
                          ? Image.network(photoUrl,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                          loadingBuilder: (ctx, child, prog) => prog == null
                              ? child
                              : Container(
                              width: 72,
                              height: 72,
                              color: kPrimary.withValues(alpha: 0.06),
                              child: const Center(
                                  child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: kPrimary)))),
                          errorBuilder: (_, __, ___) => Container(
                              width: 72,
                              height: 72,
                              color: kPrimary.withValues(alpha: 0.06),
                              child: const Icon(Icons.broken_image_outlined,
                                  size: 24, color: kPrimary)))
                          : Container(
                          width: 72,
                          height: 72,
                          color: kPrimary.withValues(alpha: 0.06),
                          child: const Icon(Icons.receipt_long_outlined,
                              size: 28, color: kPrimary)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${ch['dc_number']} — ${ch['farmer_name'] ?? '—'}',
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: kTextMain)),
                          const SizedBox(height: 4),
                          Text(
                              '${ch['bird_count'] ?? 0} birds · '
                                  '${(ch['net_weight'] as num?)?.toStringAsFixed(1) ?? 0} kg · '
                                  '${ch['crates_count'] ?? 0} crates',
                              style: const TextStyle(
                                  fontSize: 12, color: kTextSub)),
                        ]),
                  ),
                  if (date != null)
                    Text(DateFormat('d MMM').format(date),
                        style:
                        const TextStyle(fontSize: 12, color: kTextHint)),
                ]),
              );
            }).toList()),
      );

  // ── Delivery Summary ─────────────────────────────────────────────────
  Widget _desktopDeliverySummary(Map<String, dynamic>? totals) {
    final osc = totals?['order_status_counts'] as Map?;
    final total = (osc?['total'] as num?)?.toInt() ?? 0;
    final delivered = (osc?['delivered'] as num?)?.toInt() ?? 0;
    final partial = (osc?['partial'] as num?)?.toInt() ?? 0;
    final pending = (osc?['pending'] as num?)?.toInt() ?? 0;
    final cancelled = (osc?['cancelled'] as num?)?.toInt() ?? 0;
    final liveB = (totals?['auto_returned_birds'] as num?)?.toInt() ?? 0;
    final liveKg = (totals?['auto_returned_kg'] as num?)?.toDouble() ?? 0;

    return _desktopSectionCard(
      title: 'DELIVERY SUMMARY',
      icon: Icons.summarize_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          _statusPill('$total Orders', kPrimary),
          _statusPill('$delivered Delivered', Colors.green),
          if (partial > 0) _statusPill('$partial Partial', Colors.orange),
          if (pending > 0)
            _statusPill('$pending Pending', Colors.amber.shade700),
          if (cancelled > 0) _statusPill('$cancelled Cancelled', Colors.red),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
              child: _desktopStatBox(
                  'Delivered', '${totals?['deliveries_count'] ?? 0}', kPrimary)),
          Expanded(
              child: _desktopStatBox(
                  'Birds', '${totals?['total_birds'] ?? 0}', Colors.blue)),
          Expanded(
              child: _desktopStatBox(
                  'Weight',
                  '${(totals?['total_weight_kg'] as num?)?.toStringAsFixed(1) ?? 0} kg',
                  Colors.teal)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: _desktopStatBox(
                  'Mortality',
                  '${totals?['total_mortality'] ?? 0}b  '
                      '${(totals?['total_mortality_kg'] as num?)?.toStringAsFixed(1) ?? '0'} kg',
                  Colors.red)),
          Expanded(
              child: _desktopStatBox('Customer Returns',
                  '${totals?['total_returned'] ?? 0} b', Colors.purple)),
          Expanded(
              child: _desktopStatBox(
                  'Crates Pending',
                  '${(() {
                    final g = (totals?['crates_given'] as num?)?.toInt() ?? 0;
                    final b = (totals?['crates_back'] as num?)?.toInt() ?? 0;
                    return (g - b).clamp(0, 9999);
                  })()}',
                  Colors.orange)),
        ]),
        if (liveB > 0 || liveKg > 0) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.indigo.shade200),
            ),
            child: Row(children: [
              const Icon(Icons.undo_rounded, size: 16, color: Colors.indigo),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('Live Return to Stock (Shift End)',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.indigo.shade700,
                          fontWeight: FontWeight.w600))),
              Text('$liveB birds  ·  ${liveKg.toStringAsFixed(1)} kg',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.indigo.shade700)),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _desktopStatBox(String label, String value, Color c) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 4),
    padding: const EdgeInsets.symmetric(vertical: 14),
    decoration: BoxDecoration(
        color: c.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
    child: Column(children: [
      Text(value,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c)),
      const SizedBox(height: 3),
      Text(label,
          style: const TextStyle(
              fontSize: 10.5, color: kTextHint, fontWeight: FontWeight.w600)),
    ]),
  );

  // ── Transfer History ─────────────────────────────────────────────────
  Widget _desktopTransferHistory() => _desktopSectionCard(
    title: 'TRANSFER HISTORY',
    icon: Icons.swap_horiz_rounded,
    child: Column(
        children: _transferHistory.map((t) {
          final fromName = (t['from_agent'] as Map?)?['name'] as String? ?? '—';
          final toName = (t['to_agent'] as Map?)?['name'] as String? ?? '—';
          final birds = (t['bird_count'] as num?)?.toInt() ?? 0;
          final kg = (t['weight_kg'] as num?)?.toDouble() ?? 0;
          final createdAt = DateTime.tryParse(t['created_at'] as String? ?? '');
          final reason = t['transfer_reason'] as String?;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kBgPage,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kBorderLight),
            ),
            child: Row(children: [
              Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: Colors.deepPurple.withValues(alpha: 0.1),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.swap_horiz_rounded,
                      size: 18, color: Colors.deepPurple)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(fromName,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: kTextMain)),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(Icons.arrow_forward_rounded,
                              size: 13, color: kTextHint),
                        ),
                        Text(toName,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: kTextMain)),
                      ]),
                      const SizedBox(height: 3),
                      Text(
                          createdAt != null
                              ? DateFormat('d MMM, h:mm a').format(createdAt)
                              : '—',
                          style:
                          const TextStyle(fontSize: 11, color: kTextHint)),
                      if (reason != null && reason.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(reason,
                            style:
                            const TextStyle(fontSize: 11, color: kTextSub)),
                      ],
                    ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('$birds birds',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: kTextMain)),
                Text('${kg.toStringAsFixed(1)} kg',
                    style: const TextStyle(fontSize: 12, color: kTextSub)),
              ]),
            ]),
          );
        }).toList()),
  );

  // ── Per Delivery Breakdown ───────────────────────────────────────────
  Widget _desktopPerDeliveryBreakdown(List<Map<String, dynamic>> deliveries) =>
      _desktopSectionCard(
        title: 'PER DELIVERY BREAKDOWN',
        icon: Icons.list_alt_outlined,
        child: Column(
            children: deliveries.map((d) {
              final status = d['status'] as String? ?? '—';
              final approved = d['approval_status'] as String? ?? 'pending';
              final birds = d['delivered_bird_count'] as int? ?? 0;
              final weight =
                  (d['delivered_total_weight'] as num?)?.toDouble() ?? 0;
              final collected = (d['collected_amount'] as num?)?.toDouble() ?? 0;
              final mortality = d['mortality_birds'] as int? ?? 0;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: kBgPage,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kBorderLight),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(d['shop_name'] as String? ?? '—',
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: kTextMain))),
                        StatusBadge(status, SC.order(status), small: true),
                        const SizedBox(width: 6),
                        StatusBadge(
                            approved,
                            approved == 'approved'
                                ? Colors.green
                                : Colors.orange,
                            small: true),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Text('$birds birds · ${weight.toStringAsFixed(1)} kg',
                            style: const TextStyle(
                                fontSize: 12, color: kTextSub)),
                        const Spacer(),
                        if (mortality > 0)
                          Text('💀 $mortality  ',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.red)),
                        Text(Fmt.amount(collected),
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: kPrimary)),
                      ]),
                      if (d['mortality_proof_url'] != null ||
                          d['delivery_photo_url'] != null) ...[
                        const SizedBox(height: 10),
                        Row(children: [
                          if (d['mortality_proof_url'] != null)
                            _miniPhotoTile('Mortality Proof',
                                d['mortality_proof_url'] as String, Colors.red),
                          if (d['mortality_proof_url'] != null &&
                              d['delivery_photo_url'] != null)
                            const SizedBox(width: 8),
                          if (d['delivery_photo_url'] != null)
                            _miniPhotoTile('Delivery Proof',
                                d['delivery_photo_url'] as String, Colors.blue),
                        ]),
                      ],
                    ]),
              );
            }).toList()),
      );

  // ── Approval Notes (surfaces existing shift_approval_notes) ─────────
  Widget _desktopApprovalNotes(Map<String, dynamic>? shift) {
    final notes = shift?['shift_approval_notes'] as String?;
    if (notes == null || notes.trim().isEmpty) return const SizedBox.shrink();
    return _desktopSectionCard(
      title: 'APPROVAL NOTES',
      icon: Icons.sticky_note_2_outlined,
      child: Text(notes,
          style: const TextStyle(fontSize: 13, color: kTextSub, height: 1.5)),
    );
  }

  // ── Sticky right panel: Financial Reconciliation + Alerts + Checklist + Actions
  Widget _desktopRightPanel(
      BuildContext context,
      Map<String, dynamic>? shift,
      Map<String, dynamic>? totals,
      String shiftStatus,
      String approvalStatus,
      bool isHighLoss,
      bool expensePending,
      int missingPhotoCount,
      List<Map<String, dynamic>> challans,
      List<Map<String, dynamic>> deliveries) {
    final cash = (totals?['cash_collected'] as num?)?.toDouble() ?? 0;
    final upi = (totals?['upi_collected'] as num?)?.toDouble() ?? 0;
    final credit = (totals?['credit_collected'] as num?)?.toDouble() ?? 0;
    final bank = (totals?['bank_collected'] as num?)?.toDouble() ?? 0;
    final totalCollected = (totals?['total_collected'] as num?)?.toDouble() ?? 0;
    final expenses = (totals?['total_expenses'] as num?)?.toDouble() ?? 0;
    final netCash = (totals?['net_cash'] as num?)?.toDouble() ?? 0;

    return SingleChildScrollView(
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Financial Reconciliation ────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: kSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kBorderLight),
                boxShadow: kCardShadow,
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.account_balance_outlined, size: 18, color: kNavy),
                  SizedBox(width: 8),
                  Expanded(
                      child: Text('FINANCIAL RECONCILIATION',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: kTextMain,
                              letterSpacing: 0.3))),
                ]),
                const Divider(height: 20),
                _rpRow('Cash Collected', Fmt.amount(cash)),
                _rpRow('UPI Payments', Fmt.amount(upi)),
                _rpRow('Credit', Fmt.amount(credit)),
                _rpRow('Bank Transfer', Fmt.amount(bank)),
                const Divider(height: 20),
                _rpRow('Total Collected', Fmt.amount(totalCollected), bold: true),
                _rpRow('Shift Expenses', Fmt.amount(expenses), color: Colors.red),
                const Divider(height: 20),
                Row(children: [
                  const Expanded(
                      child: Text('NET CASH TO HAND',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: kTextMain,
                              letterSpacing: 0.3))),
                  Text(Fmt.amount(netCash),
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: kPrimary)),
                ]),
              ]),
            ),
            const SizedBox(height: 16),

            // ── Alerts ───────────────────────────────────────────────────
            if (isHighLoss || (expensePending && shiftStatus == 'closed') ||
                missingPhotoCount > 0) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 16, color: Colors.orange.shade800),
                        const SizedBox(width: 6),
                        Text('ALERTS',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.orange.shade800,
                                letterSpacing: 0.3)),
                      ]),
                      const SizedBox(height: 10),
                      if (isHighLoss)
                        _alertLine(
                            'Weight variance is above 2% — review batch loss before approving.'),
                      if (expensePending && shiftStatus == 'closed')
                        _alertLine('Expenses not yet validated for this shift.'),
                      if (missingPhotoCount > 0)
                        _alertLine(
                            '$missingPhotoCount delivery challan${missingPhotoCount > 1 ? 's' : ''} missing a photo.'),
                    ]),
              ),
              const SizedBox(height: 16),
            ],

            // ── Approval Checklist ───────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: kSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kBorderLight),
                boxShadow: kCardShadow,
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.checklist_rounded, size: 18, color: kNavy),
                  SizedBox(width: 8),
                  Expanded(
                      child: Text('APPROVAL CHECKLIST',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: kTextMain,
                              letterSpacing: 0.3))),
                ]),
                const Divider(height: 20),
                _checkRow('Delivery challans recorded', challans.isNotEmpty),
                _checkRow('DC photos captured',
                    missingPhotoCount == 0 && challans.isNotEmpty),
                _checkRow('Deliveries completed', deliveries.isNotEmpty),
                _checkRow('Expenses validated', !expensePending),
                _checkRow('Weight variance within range', !isHighLoss),
              ]),
            ),
            const SizedBox(height: 16),

            // ── Actions ──────────────────────────────────────────────────
            if (shiftStatus == 'closed' && approvalStatus == 'pending') ...[
              Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(kRadiusCard),
                      border: Border.all(color: Colors.orange.shade200)),
                  child: const Row(children: [
                    Icon(Icons.pending_actions_outlined,
                        color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                        child: Text(
                            'Review all deliveries above, then approve or reject this shift.',
                            style: TextStyle(
                                fontSize: 13,
                                color: Colors.orange,
                                fontWeight: FontWeight.w600))),
                  ])),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(
                    builder: (_) => ShiftVerificationScreen(shiftId: widget.id)))
                    .then((_) => _load()),
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: const Text('Review Deliveries Line-by-Line'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kNavy,
                  side: const BorderSide(color: kNavy),
                  minimumSize: const Size(double.infinity, 46),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: _submitting ? null : _approveShift,
                icon: _submitting
                    ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle_outline),
                label: const Text('Approve Shift'),
                style:
                ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _submitting ? null : _rejectShift,
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: const Text('Flag Discrepancy'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kError,
                  side: const BorderSide(color: kError),
                  minimumSize: const Size(double.infinity, 46),
                ),
              ),
            ] else if (approvalStatus == 'approved')
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: const Row(children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                      child: Text('Shift Approved ✓',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.green))),
                ]),
              )
            else if (approvalStatus != 'pending')
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: const Row(children: [
                    Icon(Icons.cancel, color: Colors.red, size: 22),
                    SizedBox(width: 10),
                    Expanded(
                        child: Text('Shift Flagged / Rejected',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.red))),
                  ]),
                ),
            const SizedBox(height: 8),
          ]),
    );
  }

  Widget _rpRow(String label, String value, {bool bold = false, Color? color}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(
              child:
              Text(label, style: const TextStyle(fontSize: 12.5, color: kTextSub))),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: color ?? kTextMain)),
        ]),
      );

  Widget _alertLine(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('•  ',
          style: TextStyle(
              fontSize: 12,
              color: Colors.orange.shade800,
              fontWeight: FontWeight.w800)),
      Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 12, color: Colors.orange.shade800, height: 1.4))),
    ]),
  );

  Widget _checkRow(String label, bool done) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 16, color: done ? Colors.green : kTextHint),
      const SizedBox(width: 8),
      Expanded(
          child: Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  color: done ? kTextMain : kTextSub,
                  fontWeight: done ? FontWeight.w600 : FontWeight.w400))),
    ]),
  );

  // ── ODOMETER SECTION ─────────────────────────────────────────────
  Widget _buildOdometerSection(Map<String, dynamic>? shift) {
    if (shift == null) return const SizedBox.shrink();

    final odoStart = (shift['odometer_start'] as num?)?.toDouble();
    final odoEnd = (shift['odometer_end'] as num?)?.toDouble();
    final distKm = odoEnd != null && odoStart != null
        ? (odoEnd - odoStart).abs()
        : (shift['distance_km'] as num?)?.toDouble() ?? 0;
    final startPhoto = shift['odometer_start_photo'] as String?;
    final endPhoto = shift['odometer_end_photo'] as String?;
    final hasAnyData = odoStart != null ||
        odoEnd != null ||
        startPhoto != null ||
        endPhoto != null;

    if (!hasAnyData)
      return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: kBorderLight),
              boxShadow: kCardShadow),
          child: const Row(children: [
            Icon(Icons.speed_outlined, size: 16, color: kTextHint),
            SizedBox(width: 8),
            Text('No odometer data recorded for this shift',
                style: TextStyle(fontSize: 12, color: kTextHint)),
          ]));

    return Container(
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(kRadiusCard),
            border: Border.all(color: Colors.teal.shade200, width: 1.5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                  color: Colors.teal.shade600,
                  borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(13))),
              child: Row(children: [
                const Icon(Icons.speed_outlined, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                    child: Text('Odometer & Distance',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13))),
                if (distKm > 0)
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(kRadiusInner)),
                      child: Text('${distKm.toStringAsFixed(0)} km travelled',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800))),
              ])),

          Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                // Odometer readings row
                Row(children: [
                  _odoStat(
                      'Start Reading',
                      odoStart != null
                          ? '${odoStart.toStringAsFixed(0)} km'
                          : 'Not recorded',
                      Colors.blue),
                  Container(
                      width: 1,
                      height: 40,
                      color: kBorder,
                      margin: const EdgeInsets.symmetric(horizontal: 12)),
                  _odoStat(
                      'End Reading',
                      odoEnd != null
                          ? '${odoEnd.toStringAsFixed(0)} km'
                          : 'Not recorded',
                      Colors.teal),
                  Container(
                      width: 1,
                      height: 40,
                      color: kBorder,
                      margin: const EdgeInsets.symmetric(horizontal: 12)),
                  _odoStat(
                      'Distance',
                      distKm > 0 ? '${distKm.toStringAsFixed(0)} km' : '—',
                      distKm > 0 ? Colors.green : kTextHint),
                ]),
                const SizedBox(height: 14),

                // Photo tiles
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (startPhoto != null)
                    Expanded(
                        child: _odoPhotoTile(
                            'Start Odometer', startPhoto, Colors.blue))
                  else
                    Expanded(
                        child: _odoMissingTile('Start Odometer', Colors.blue)),
                  const SizedBox(width: 10),
                  if (endPhoto != null)
                    Expanded(
                        child: _odoPhotoTile(
                            'End Odometer', endPhoto, Colors.teal))
                  else
                    Expanded(
                        child: _odoMissingTile('End Odometer', Colors.teal)),
                ]),
              ])),
        ]));
  }

  Widget _odoStat(String label, String value, Color c) => Expanded(
      child: Column(children: [
        Text(value,
            style:
            TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: c),
            textAlign: TextAlign.center),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(fontSize: 9, color: kTextHint),
            textAlign: TextAlign.center),
      ]));

  Widget _odoPhotoTile(String label, String url, Color c) => GestureDetector(
      onTap: () => _showFullImage(context, url, label),
      child: Container(
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: c.withValues(alpha: 0.3))),
          child: Column(children: [
            Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.08),
                    borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(9))),
                child: Row(children: [
                  Icon(Icons.speed_outlined, size: 13, color: c),
                  const SizedBox(width: 4),
                  Expanded(
                      child: Text(label,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: c))),
                  Icon(Icons.open_in_full,
                      size: 12, color: c.withValues(alpha: 0.6)),
                ])),
            ClipRRect(
                borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(9)),
                child: Image.network(
                  url,
                  width: double.infinity,
                  height: 130,
                  fit: BoxFit.cover,
                  loadingBuilder: (ctx, child, prog) => prog == null
                      ? child
                      : Container(
                      height: 130,
                      color: c.withValues(alpha: 0.05),
                      child: Center(
                          child: CircularProgressIndicator(
                              color: c, strokeWidth: 2))),
                  errorBuilder: (_, __, ___) => Container(
                      height: 100,
                      color: c.withValues(alpha: 0.05),
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.broken_image_outlined,
                                size: 28, color: c.withValues(alpha: 0.4)),
                            const SizedBox(height: 4),
                            Text('Failed to load',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: c.withValues(alpha: 0.5))),
                          ])),
                )),
          ])));

  Widget _odoMissingTile(String label, Color c) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border: Border.all(
              color: Colors.grey.shade300, style: BorderStyle.solid)),
      child: Column(children: [
        Icon(Icons.photo_camera_outlined,
            size: 28, color: Colors.grey.shade400),
        const SizedBox(height: 6),
        Text(label,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: kTextSub)),
        const SizedBox(height: 2),
        const Text('Not captured',
            style: TextStyle(fontSize: 10, color: kTextHint)),
      ]));

  void _showFullImage(BuildContext context, String url, String title) {
    showDialog(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => Dialog(
            backgroundColor: Colors.black,
            insetPadding: EdgeInsets.zero,
            child: Stack(children: [
              InteractiveViewer(
                  child: Center(
                      child: Image.network(url,
                          fit: BoxFit.contain,
                          loadingBuilder: (_, child, prog) => prog == null
                              ? child
                              : const Center(
                              child: CircularProgressIndicator(
                                  color: Colors.white)),
                          errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.broken_image,
                                  color: Colors.white, size: 64))))),
              Positioned(
                  top: 16,
                  left: 16,
                  child: Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          shadows: [
                            Shadow(color: Colors.black54, blurRadius: 4)
                          ]))),
              Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                      icon: const Icon(Icons.close,
                          color: Colors.white, size: 28),
                      onPressed: () =>
                          Navigator.of(ctx, rootNavigator: true).pop())),
            ])));
  }

  // Mini photo thumbnail for delivery rows in shift detail
  Widget _miniPhotoTile(String label, String url, Color c) => Expanded(
      child: GestureDetector(
          onTap: () => _showFullImage(context, url, label),
          child: Container(
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(kRadiusInner),
                  border: Border.all(color: c.withValues(alpha: 0.3))),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                            color: c.withValues(alpha: 0.08),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(7))),
                        child: Row(children: [
                          Icon(
                              label.contains('Mortality')
                                  ? Icons.warning_amber_rounded
                                  : Icons.check_circle_outline,
                              size: 11,
                              color: c),
                          const SizedBox(width: 4),
                          Expanded(
                              child: Text(label,
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: c),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis)),
                          Icon(Icons.open_in_full,
                              size: 10, color: c.withValues(alpha: 0.6)),
                        ])),
                    ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(7)),
                        child: Image.network(
                          url,
                          width: double.infinity,
                          height: 90,
                          fit: BoxFit.cover,
                          loadingBuilder: (ctx, child, prog) => prog == null
                              ? child
                              : Container(
                              height: 90,
                              color: c.withValues(alpha: 0.05),
                              child: Center(
                                  child: CircularProgressIndicator(
                                      color: c, strokeWidth: 2))),
                          errorBuilder: (_, __, ___) => Container(
                              height: 70,
                              color: c.withValues(alpha: 0.05),
                              child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.broken_image_outlined,
                                        size: 22,
                                        color: c.withValues(alpha: 0.4)),
                                    Text('Load failed',
                                        style: TextStyle(
                                            fontSize: 9,
                                            color: c.withValues(alpha: 0.5))),
                                  ])),
                        )),
                  ]))));

  Widget _trow(String l, String v, {Color? color, bool bold = false}) =>
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(
                child: Text(l,
                    style: const TextStyle(fontSize: 13, color: kTextSub))),
            Text(v,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                    color: color ?? kTextMain)),
          ]));

  Widget _sbox(String label, String value, Color color) => Expanded(
      child: Column(children: [
        Text(value,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: color)),
        Text(label,
            style: const TextStyle(fontSize: 10, color: kTextHint),
            textAlign: TextAlign.center),
      ]));

  // ── Batch Loss Panel ────────────────────────────────────────────────────────
  Widget _buildBatchLossPanel() {
    // U6 FIX: If batchLoss is null (loading) or totals show zero DC weight,
    // warn the trader clearly before they approve blindly.
    if (_batchLoss == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(kRadiusCard),
                border: Border.all(color: kBorderLight),
                boxShadow: kCardShadow),
            child: const Row(children: [
              SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: kPrimary)),
              SizedBox(width: 12),
              Text('Loading batch loss summary...',
                  style: TextStyle(fontSize: 12, color: kTextSub)),
            ])),
        const SizedBox(height: 8),
        Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(kRadiusCard),
                border: Border.all(color: Colors.orange.shade200)),
            child: const Row(children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
              SizedBox(width: 8),
              Expanded(
                  child: Text(
                      'Wait for the batch loss summary to load before approving. '
                          'Approving without DC data will record zero loss.',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange,
                          fontWeight: FontWeight.w600))),
            ])),
      ]);
    }

    // U6 FIX: check if DC data is actually present. A shift built entirely on
    // transferred-in stock (no DC of its own) is now also valid — the loss
    // formula accounts for transferred_in as inbound stock, so only warn when
    // there's truly no inbound stock at all (neither DC nor transfer).
    final _checkTotals =
    (_batchLoss!['shift_totals'] as Map?)?.cast<String, dynamic>();
    final _checkDcKg =
        (_checkTotals?['total_dc_weight_kg'] as num?)?.toDouble() ?? 0;
    final _checkTransferInKg =
        (_checkTotals?['total_transferred_in_kg'] as num?)?.toDouble() ?? 0;
    if (_checkDcKg == 0 && _checkTransferInKg == 0) {
      return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: Colors.amber.shade300, width: 1.5)),
          child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
              SizedBox(width: 8),
              Text('No DC Data Found for This Shift',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: Colors.amber)),
            ]),
            const SizedBox(height: 10),
            const Text(
                'No delivery challans were recorded for the batches in this shift. '
                    'This means the loss calculation cannot be computed — approving now '
                    'will record zero loss, which may be incorrect.',
                style: TextStyle(fontSize: 12, color: kTextSub, height: 1.5)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(kRadiusInner)),
              child: const Text(
                  'Checklist before approving:'
                      '• Verify with the agent that all DCs were uploaded in batch pickup'
                      '• Check Dispatch screen — does the batch show challan data?'
                      '• If DCs are genuinely missing, reject this shift and ask agent to re-upload',
                  style: TextStyle(fontSize: 11, color: kTextSub, height: 1.6)),
            ),
          ]));
    }

    final totals =
    (_batchLoss!['shift_totals'] as Map?)?.cast<String, dynamic>();
    final batches =
    (_batchLoss!['batches'] as List? ?? []).cast<Map<String, dynamic>>();
    final dcBirds      = (totals?['total_dc_birds']           as num?)?.toInt()    ?? 0;
    final dcKg         = (totals?['total_dc_weight_kg']       as num?)?.toDouble() ?? 0;
    final delBirds     = (totals?['total_delivered_birds']    as num?)?.toInt()    ?? 0;
    final delKg        = (totals?['total_delivered_kg']       as num?)?.toDouble() ?? 0;
    final liveRetBirds = (totals?['shift_close_return_birds'] as num?)?.toInt()    ?? 0;
    final liveRetKg    = (totals?['shift_close_return_kg']    as num?)?.toDouble() ?? 0;
    final mortBirds    = (totals?['total_mortality_birds']    as num?)?.toInt()    ?? 0;
    final mortKg       = (totals?['total_mortality_kg']       as num?)?.toDouble() ?? 0;
    final delMortBirds = (totals?['delivery_mortality_birds'] as num?)?.toInt()    ?? 0;
    final delMortKg    = (totals?['delivery_mortality_kg']    as num?)?.toDouble() ?? 0;
    final retMortBirds = (totals?['return_mortality_birds']   as num?)?.toInt()    ?? 0;
    final retMortKg    = (totals?['return_mortality_kg']      as num?)?.toDouble() ?? 0;
    final transferInBirds  = (totals?['total_transferred_in_birds']  as num?)?.toInt()    ?? 0;
    final transferInKg     = (totals?['total_transferred_in_kg']     as num?)?.toDouble() ?? 0;
    final transferOutBirds = (totals?['total_transferred_out_birds'] as num?)?.toInt()    ?? 0;
    final transferOutKg    = (totals?['total_transferred_out_kg']    as num?)?.toDouble() ?? 0;
    final lossKg       = (totals?['unaccounted_loss_kg']      as num?)?.toDouble() ?? 0;
    final totalLossKg  = (totals?['total_loss_kg']            as num?)?.toDouble() ?? 0;
    final lossPct      = (dcKg + transferInKg) > 0 ? (lossKg / (dcKg + transferInKg) * 100) : 0.0;
    final isHighLoss   = lossPct >= 2;
    final hasDelMort   = delMortBirds > 0;
    final hasRetMort   = retMortBirds > 0;

    return Container(
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(kRadiusCard),
            border: Border.all(
                color: isHighLoss ? Colors.red.shade300 : Colors.green.shade300,
                width: 1.5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header bar
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                  color: isHighLoss ? Colors.red.shade50 : Colors.green.shade50,
                  borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(13))),
              child: Row(children: [
                Icon(
                    isHighLoss
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline,
                    color: isHighLoss ? Colors.red : Colors.green,
                    size: 18),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                        isHighLoss
                            ? 'High Weight Variance: ${lossPct.toStringAsFixed(1)}%  (${lossKg.toStringAsFixed(2)} kg)'
                            : 'All stock accounted for',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: isHighLoss
                                ? Colors.red.shade700
                                : Colors.green.shade700))),
              ])),

          // ── Shift reconciliation table (spec-aligned 6-row layout) ─────────
          Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: Column(children: [
                // Column headers
                Row(children: [
                  const Expanded(flex: 3, child: SizedBox()),
                  SizedBox(width: 80, child: Text('Birds',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
                          color: kTextHint, letterSpacing: 0.5))),
                  SizedBox(width: 86, child: Text('Weight',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
                          color: kTextHint, letterSpacing: 0.5))),
                ]),
                const SizedBox(height: 4),
                _approvalReconRow('DC Loaded', dcBirds, dcKg,
                    Colors.blue, false, prefix: '+'),
                if (transferInBirds > 0 || transferInKg > 0)
                  _approvalReconRow('Transfer In', transferInBirds, transferInKg,
                      Colors.green, false, prefix: '+'),
                _approvalReconRow('Delivered', delBirds, delKg,
                    Colors.teal, false, prefix: '−'),
                if (transferOutBirds > 0 || transferOutKg > 0)
                  _approvalReconRow('Transfer Out', transferOutBirds, transferOutKg,
                      Colors.orange, false, prefix: '−'),
                if (liveRetBirds > 0 || liveRetKg > 0)
                  _approvalReconRow('Live Return (Stock Added)',
                      liveRetBirds, liveRetKg, Colors.indigo, false, prefix: '−'),
                if (hasDelMort && hasRetMort) ...[
                  _approvalReconRow('Delivery Mortality',
                      delMortBirds, delMortKg, Colors.red, false, prefix: '−'),
                  _approvalReconRow('Dead Return (Mortality)',
                      retMortBirds, retMortKg, Colors.deepOrange, false, prefix: '−'),
                ] else if (hasRetMort)
                  _approvalReconRow('Dead Return (Mortality)',
                      retMortBirds, retMortKg, Colors.deepOrange, false, prefix: '−')
                else if (hasDelMort || mortBirds > 0)
                    _approvalReconRow('Mortality',
                        mortBirds, mortKg, Colors.red, false, prefix: '−'),
                _approvalReconRow('Weight Variance', null, lossKg,
                    lossKg > 0 ? Colors.orange : Colors.green, lossKg > 0,
                    suffix: lossKg > 0 ? '  (${lossPct.toStringAsFixed(1)}%)' : null),
                const Divider(height: 16, thickness: 1),
                _approvalReconRow('Total Loss', null, totalLossKg,
                    totalLossKg > 0 ? Colors.red : Colors.green,
                    totalLossKg > 0),
              ])),

          // Per-batch breakdown
          // Hidden when shift has only 1 batch (duplicates info already shown above).
          // Shown for multi-batch shifts using the same formula as shift_totals.
          if (batches.length > 1) ...[
            const Divider(height: 1),
            Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                child: const Text('PER-BATCH BREAKDOWN',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: kTextHint,
                        letterSpacing: 0.8))),
            ...batches.map((b) {
              final bDcBirds   = (b['dc_birds']             as num?)?.toInt()    ?? 0;
              final bDcKg      = (b['dc_weight_kg']         as num?)?.toDouble() ?? 0;
              final bDelBirds  = (b['delivered_birds']      as num?)?.toInt()    ?? 0;
              final bDelKg     = (b['delivered_kg']         as num?)?.toDouble() ?? 0;
              final bLiveRet   = (b['close_return_birds']   as num?)?.toInt()    ?? 0;
              final bLiveRetKg = (b['close_return_kg']      as num?)?.toDouble() ?? 0;
              final bMortBirds = (b['mortality_birds']      as num?)?.toInt()    ?? 0;
              final bMortKg    = (b['mortality_kg']         as num?)?.toDouble() ?? 0;
              final bRetMBirds = (b['return_mortality_birds'] as num?)?.toInt()  ?? 0;
              final bRetMKg    = (b['return_mortality_kg']    as num?)?.toDouble() ?? 0;
              final bTransferOutBirds = (b['transferred_out_birds'] as num?)?.toInt()    ?? 0;
              final bTransferOutKg    = (b['transferred_out_kg']    as num?)?.toDouble() ?? 0;
              final bTransferInBirds  = (b['transferred_in_birds']  as num?)?.toInt()    ?? 0;
              final bTransferInKg     = (b['transferred_in_kg']     as num?)?.toDouble() ?? 0;
              final bLossKg    = (b['unaccounted_loss_kg']  as num?)?.toDouble() ?? 0;
              final bTotalLoss = (b['total_loss_kg']        as num?)?.toDouble() ?? 0;
              final bLossPct   = (b['loss_percent']         as num?)?.toDouble() ?? 0;
              final bHigh      = bLossPct >= 2;
              final done       = (b['deliveries_done']      as num?)?.toInt()    ?? 0;
              final pending    = (b['deliveries_pending']   as num?)?.toInt()    ?? 0;
              final bStatus    = b['batch_status'] as String? ?? '';
              return Container(
                  margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: bHigh ? Colors.red.shade50 : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(kRadiusCard),
                      border: Border.all(
                          color: bHigh ? Colors.red.shade300 : Colors.green.shade200,
                          width: 1.2)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Batch header: vehicle + variance badge
                        Row(children: [
                          Icon(Icons.local_shipping_outlined,
                              size: 14, color: bHigh ? Colors.red : kPrimary),
                          const SizedBox(width: 6),
                          Text(b['vehicle_no'] as String? ?? 'Batch',
                              style: TextStyle(fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: bHigh ? Colors.red : kTextMain)),
                          const Spacer(),
                          // Approval-readiness badge
                          Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                  color: bHigh ? Colors.red.shade100 : Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(6)),
                              child: Text(
                                  bHigh
                                      ? 'Variance: ${bLossPct.toStringAsFixed(1)}%'
                                      : '✓ OK',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                                      color: bHigh ? Colors.red.shade700 : Colors.green.shade700))),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                            '$done/${done + pending} orders  ·  '
                                '${bStatus == 'completed' ? 'Completed' : 'In progress'}',
                            style: const TextStyle(fontSize: 10, color: kTextHint)),
                        const SizedBox(height: 10),
                        // Reconciliation rows — same layout and formula as shift-level above
                        Row(children: [
                          const Expanded(flex: 3, child: SizedBox()),
                          SizedBox(width: 76, child: Text('Birds',
                              textAlign: TextAlign.right,
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                                  color: kTextHint))),
                          SizedBox(width: 82, child: Text('Weight',
                              textAlign: TextAlign.right,
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                                  color: kTextHint))),
                        ]),
                        const SizedBox(height: 2),
                        _approvalReconRow('DC Loaded', bDcBirds, bDcKg, Colors.blue, false, prefix: '+'),
                        if (bTransferInBirds > 0 || bTransferInKg > 0)
                          _approvalReconRow('Transfer In', bTransferInBirds, bTransferInKg, Colors.green, false, prefix: '+'),
                        _approvalReconRow('Delivered', bDelBirds, bDelKg, Colors.teal, false, prefix: '−'),
                        if (bTransferOutBirds > 0 || bTransferOutKg > 0)
                          _approvalReconRow('Transfer Out', bTransferOutBirds, bTransferOutKg, Colors.orange, false, prefix: '−'),
                        if (bLiveRet > 0 || bLiveRetKg > 0)
                          _approvalReconRow('Live Return', bLiveRet, bLiveRetKg, Colors.indigo, false, prefix: '−'),
                        if (bRetMBirds > 0)
                          _approvalReconRow('Dead Return', bRetMBirds, bRetMKg, Colors.deepOrange, false, prefix: '−')
                        else if (bMortBirds > 0)
                          _approvalReconRow('Mortality', bMortBirds, bMortKg, Colors.red, false, prefix: '−'),
                        _approvalReconRow('Weight Variance', null, bLossKg,
                            bHigh ? Colors.red : Colors.green, bHigh),
                        const Divider(height: 12, thickness: 0.5),
                        _approvalReconRow('Total Loss', null, bTotalLoss,
                            bTotalLoss > 0 ? Colors.red : Colors.green,
                            bTotalLoss > 0),
                      ]));
            }),
            const SizedBox(height: 4),
          ],
        ]));
  }

  // Small status pill for order status counts in Delivery Summary
  Widget _statusPill(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Text(label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
  );

  // Product movement row: label | birds | kg — used in PRODUCT MOVEMENT section
  static Widget _productMoveRow(
      String label, int birds, double kg, Color c,
      {String prefix = ''}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label,
              style: const TextStyle(fontSize: 11, color: kTextSub))),
          SizedBox(width: 68,
              child: Text('$prefix$birds b',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c))),
          SizedBox(width: 72,
              child: Text('$prefix${kg.toStringAsFixed(1)} kg',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c))),
        ]),
      );

  Widget _lossRow(String label, String value, Color c, bool highlight) =>
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child:
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: highlight ? c : kTextSub,
                    fontWeight:
                    highlight ? FontWeight.w700 : FontWeight.normal)),
            Text(value,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: highlight ? c : kTextMain)),
          ]));

  Widget _batchStat(String l, String v, Color c) => Column(children: [
    Text(v,
        style:
        TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c),
        textAlign: TextAlign.center),
    const SizedBox(height: 2),
    Text(l,
        style: const TextStyle(fontSize: 9, color: kTextHint),
        textAlign: TextAlign.center),
  ]);

  @override
  Widget build(BuildContext context) => ResponsiveLayout(
    mobile: (_) => _buildScaffold(context),
    desktop: (_) => _buildDesktopScaffold(context),
  );
}