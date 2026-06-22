import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SHIFT VERIFICATION SCREEN
//
// Phase 6: Structured pre-approval review of a closed shift.
// Trader reviews each delivery and each DC challan line-by-line before
// calling approve_shift. Can flag discrepancies and adjust weights.
//
// Architecture:
//   • Loads via get_shift_verification_status(p_shift_id) — single call returns
//     everything: deliveries, challans, summary counts, shift state.
//   • Each delivery row has a Review button → inline expansion with:
//       - Weight / bird count check
//       - Optional correction fields (trader_adjusted_weight, trader_adjusted_birds)
//       - Discrepancy flag toggle
//       - Notes field
//   • Each DC challan row has a Verify button → inline expansion with:
//       - DC weight check vs gross/empty
//       - Optional adjusted weight
//       - Notes
//   • Verification is guidance, NOT a hard gate — trader can proceed to
//     approve_shift even with unverified items. The UI shows a warning.
//   • After all items reviewed, a "Review Complete — Go to Approve" button
//     appears that navigates to shift_detail_screen for the final approve_shift call.
//
// CRITICAL: Zero business logic here. verify_delivery and verify_dc RPCs handle
// all state mutations. approve_shift is called from shift_detail_screen (unchanged).
// ─────────────────────────────────────────────────────────────────────────────

class ShiftVerificationScreen extends ConsumerStatefulWidget {
  const ShiftVerificationScreen({
    super.key,
    required this.shiftId,
  });

  final String shiftId;

  @override
  ConsumerState<ShiftVerificationScreen> createState() =>
      _ShiftVerificationScreenState();
}

class _ShiftVerificationScreenState
    extends ConsumerState<ShiftVerificationScreen> {
  final _c = Supabase.instance.client;

  bool _loading = true;
  Map<String, dynamic> _data = {};

  // Track which delivery/challan card is expanded for inline review
  String? _expandedDeliveryId;
  String? _expandedChallanId;

  // Per-item form state — keyed by delivery/challan id
  final Map<String, TextEditingController> _wt   = {};
  final Map<String, TextEditingController> _birds = {};
  final Map<String, TextEditingController> _notes = {};
  final Map<String, bool> _hasDiscrepancy = {};

  // Per-DC form state
  final Map<String, TextEditingController> _dcWt    = {};
  final Map<String, TextEditingController> _dcNotes = {};

  // Submitting state per item
  final Set<String> _submitting = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [..._wt.values, ..._birds.values, ..._notes.values,
      ..._dcWt.values, ..._dcNotes.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final res = await _c
          .rpc('get_shift_verification_status',
          params: {'p_shift_id': widget.shiftId})
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      setState(() {
        _data    = (res as Map?)?.cast<String, dynamic>() ?? {};
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showError(context, e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  // ── Derived state ───────────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _deliveries =>
      List<Map<String, dynamic>>.from(
          (_data['deliveries'] as List?)?.map((e) =>
              (e as Map).cast<String, dynamic>()) ?? []);

  List<Map<String, dynamic>> get _challans =>
      List<Map<String, dynamic>>.from(
          (_data['challans'] as List?)?.map((e) =>
              (e as Map).cast<String, dynamic>()) ?? []);

  Map<String, dynamic> get _summary =>
      ((_data['summary'] as Map?)?.cast<String, dynamic>()) ?? {};

  Map<String, dynamic> get _dcSummary =>
      ((_data['dc_summary'] as Map?)?.cast<String, dynamic>()) ?? {};

  Map<String, dynamic> get _shift =>
      ((_data['shift'] as Map?)?.cast<String, dynamic>()) ?? {};

  bool get _verificationComplete =>
      _data['verification_complete'] == true;

  int get _totalDeliveries =>
      (_summary['total_deliveries'] as num?)?.toInt() ?? 0;
  int get _verifiedDeliveries =>
      (_summary['verified_deliveries'] as num?)?.toInt() ?? 0;
  int get _discrepancyCount =>
      (_summary['discrepancy_count'] as num?)?.toInt() ?? 0;
  int get _totalChallans =>
      (_dcSummary['total_challans'] as num?)?.toInt() ?? 0;
  int get _verifiedChallans =>
      (_dcSummary['verified_challans'] as num?)?.toInt() ?? 0;

  // ── Ensure form controllers exist for an item ───────────────────────────────
  void _ensureDeliveryControllers(String id, Map<String, dynamic> d) {
    _wt.putIfAbsent(id, () => TextEditingController(
        text: (d['trader_adjusted_weight'] as num?)?.toStringAsFixed(1) ??
            (d['delivered_total_weight'] as num?)?.toStringAsFixed(1) ?? ''));
    _birds.putIfAbsent(id, () => TextEditingController(
        text: (d['trader_adjusted_birds'] as num?)?.toString() ??
            (d['delivered_bird_count'] as num?)?.toString() ?? ''));
    _notes.putIfAbsent(id, () => TextEditingController(
        text: d['verification_notes'] as String? ?? ''));
    _hasDiscrepancy.putIfAbsent(id, () =>
    d['has_discrepancy'] as bool? ?? false);
  }

  void _ensureChallanControllers(String id, Map<String, dynamic> dc) {
    _dcWt.putIfAbsent(id, () => TextEditingController(
        text: (dc['dc_adjusted_weight'] as num?)?.toStringAsFixed(1) ??
            (dc['net_weight'] as num?)?.toStringAsFixed(1) ?? ''));
    _dcNotes.putIfAbsent(id, () => TextEditingController(
        text: dc['dc_verification_notes'] as String? ?? ''));
  }

  // ── Submit delivery verification ────────────────────────────────────────────
  Future<void> _verifyDelivery(String deliveryId) async {
    final user = ref.read(appUserProvider).valueOrNull;
    if (user == null) return;

    final adjWt   = double.tryParse(_wt[deliveryId]?.text.trim()    ?? '');
    final adjBirds= int.tryParse(_birds[deliveryId]?.text.trim()     ?? '');
    final notes   = _notes[deliveryId]?.text.trim();
    final disc    = _hasDiscrepancy[deliveryId] ?? false;

    // Find original delivery values for comparison
    final d = _deliveries.firstWhere((d) => d['id'] == deliveryId,
        orElse: () => {});
    final origWt    = (d['delivered_total_weight'] as num?)?.toDouble() ?? 0;
    final origBirds = (d['delivered_bird_count']   as num?)?.toInt()   ?? 0;

    // Only pass adjusted values if they differ from originals
    final adjustedWt   = (adjWt    != null && adjWt    != origWt)    ? adjWt    : null;
    final adjustedBirds= (adjBirds != null && adjBirds != origBirds) ? adjBirds : null;

    setState(() => _submitting.add(deliveryId));
    try {
      await _c.rpc('verify_delivery', params: {
        'p_delivery_id':      deliveryId,
        'p_verified_by':      user.userId,
        'p_notes':            notes?.isEmpty == true ? null : notes,
        'p_adjusted_weight':  adjustedWt,
        'p_adjusted_birds':   adjustedBirds,
        'p_has_discrepancy':  disc,
      });

      if (mounted) {
        showSuccess(context, disc
            ? '⚠️ Discrepancy flagged for review'
            : '✅ Delivery verified');
        setState(() => _expandedDeliveryId = null);
        await _load();
      }
    } catch (e) {
      if (mounted) showError(context,
          e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting.remove(deliveryId));
    }
  }

  // ── Submit DC verification ──────────────────────────────────────────────────
  Future<void> _verifyDC(String challanId) async {
    final user = ref.read(appUserProvider).valueOrNull;
    if (user == null) return;

    final dc       = _challans.firstWhere((c) => c['id'] == challanId,
        orElse: () => {});
    final origWt   = (dc['net_weight']  as num?)?.toDouble() ?? 0;
    final adjWtStr = _dcWt[challanId]?.text.trim() ?? '';
    final adjWt    = double.tryParse(adjWtStr);
    final adjusted = (adjWt != null && adjWt != origWt) ? adjWt : null;
    final notes    = _dcNotes[challanId]?.text.trim();

    setState(() => _submitting.add(challanId));
    try {
      await _c.rpc('verify_dc', params: {
        'p_challan_id':      challanId,
        'p_verified_by':     user.userId,
        'p_notes':           notes?.isEmpty == true ? null : notes,
        'p_adjusted_weight': adjusted,
      });

      if (mounted) {
        final msg = adjusted != null
            ? '✅ DC verified — adjusted to ${adjusted.toStringAsFixed(1)} kg'
            : '✅ DC verified';
        showSuccess(context, msg);
        setState(() => _expandedChallanId = null);
        await _load();
      }
    } catch (e) {
      if (mounted) showError(context,
          e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting.remove(challanId));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final agentName = _shift['agent_name'] as String? ?? 'Agent';
    final approvalStatus = _shift['shift_approval_status'] as String? ?? 'pending';

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kNavy,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : null,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Verify Shift — $agentName',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800,
                    color: Colors.white)),
            const Text('Review before approval',
                style: TextStyle(fontSize: 11, color: Color(0xFFB4C6F4))),
          ],
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _load),
        ],
      ),
      body: _loading
          ? const LoadingList()
          : Column(children: [
        _progressBar(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
            children: [
              // Already approved
              if (approvalStatus == 'approved')
                _approvedBanner()
              else ...[
                // Progress summary card
                _summaryCard(),
                const SizedBox(height: 14),
              ],

              // ── DC Challans section ──────────────────────────────────
              if (_challans.isNotEmpty) ...[
                _sectionHeader(
                  'DELIVERY CHALLANS (${_verifiedChallans}/${_totalChallans} verified)',
                  Icons.receipt_long_outlined,
                  Colors.blue,
                ),
                const SizedBox(height: 8),
                ..._challans.map(_buildChallanCard),
                const SizedBox(height: 14),
              ],

              // ── Deliveries section ───────────────────────────────────
              _sectionHeader(
                'DELIVERIES (${_verifiedDeliveries}/${_totalDeliveries} verified)',
                Icons.local_shipping_outlined,
                kNavy,
              ),
              const SizedBox(height: 8),
              if (_deliveries.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: kSurface,
                      borderRadius: BorderRadius.circular(kRadiusCard),
                      border: Border.all(color: kBorderLight)),
                  child: const Center(
                    child: Text('No delivered items in this shift.',
                        style: TextStyle(color: kTextHint)),
                  ),
                )
              else
                ..._deliveries.map(_buildDeliveryCard),
              const SizedBox(height: 20),

              // ── Action button ────────────────────────────────────────
              if (approvalStatus == 'pending')
                _actionButton(),
            ],
          ),
        ),
      ]),
    );
  }

  // ── Progress bar ────────────────────────────────────────────────────────────
  Widget _progressBar() {
    final total = _totalDeliveries + _totalChallans;
    final done  = _verifiedDeliveries + _verifiedChallans;
    final pct   = total > 0 ? done / total : 0.0;
    final color = _verificationComplete ? Colors.green
        : _discrepancyCount > 0 ? Colors.orange : kNavy;
    return Container(
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Expanded(child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: Colors.white.withValues(alpha: 0.3),
            valueColor: const AlwaysStoppedAnimation(Colors.white),
            minHeight: 6,
          ),
        )),
        const SizedBox(width: 12),
        Text(
          _verificationComplete
              ? '✓ All reviewed'
              : '$done / $total reviewed',
          style: const TextStyle(
              color: Colors.white, fontSize: 11,
              fontWeight: FontWeight.w700),
        ),
      ]),
    );
  }

  // ── Summary card ─────────────────────────────────────────────────────────────
  Widget _summaryCard() {
    final totalKg   = (_summary['total_delivered_kg']  as num?)?.toDouble() ?? 0;
    final totalCash = (_summary['total_cash']          as num?)?.toDouble() ?? 0;
    final adjKg     = (_summary['total_adjusted_kg']   as num?)?.toDouble() ?? 0;
    final dcKg      = (_dcSummary['total_dc_kg']       as num?)?.toDouble() ?? 0;
    final hasAdj    = adjKg > 0;
    final hasDisc   = _discrepancyCount > 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(color: kBorderLight),
        boxShadow: kCardShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('SHIFT OVERVIEW',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                color: kTextHint, letterSpacing: 0.8)),
        const SizedBox(height: 12),
        Row(children: [
          _kpi('DC Weight', '${dcKg.toStringAsFixed(1)} kg',   Colors.blue),
          _kpi('Delivered', '${totalKg.toStringAsFixed(1)} kg', kNavy),
          _kpi('Cash',     Fmt.amount(totalCash),               Colors.green),
        ]),
        if (hasDisc || hasAdj) ...[
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          if (hasDisc)
            _alertRow(Icons.warning_amber_rounded, Colors.orange,
                '$_discrepancyCount discrepancy(s) flagged — review before approving'),
          if (hasAdj)
            _alertRow(Icons.edit_outlined, Colors.blue,
                'Trader adjustments: ${adjKg.toStringAsFixed(1)} kg corrected'),
        ],
        if (!_verificationComplete) ...[
          const SizedBox(height: 8),
          _alertRow(Icons.info_outline, kNavy,
              'Verification is optional — you can approve without reviewing all items.'),
        ],
      ]),
    );
  }

  // ── DC Challan card ──────────────────────────────────────────────────────────
  Widget _buildChallanCard(Map<String, dynamic> dc) {
    final id          = dc['id'] as String;
    final dcNum       = dc['dc_number'] as String? ?? '—';
    final farmerName  = dc['farmer_name'] as String? ?? '—';
    final birds       = (dc['bird_count']  as num?)?.toInt()    ?? 0;
    final netWt       = (dc['net_weight']  as num?)?.toDouble() ?? 0;
    final grossWt     = (dc['gross_weight'] as num?)?.toDouble();
    final adjWt       = (dc['dc_adjusted_weight'] as num?)?.toDouble();
    final verified    = dc['dc_verified'] as bool? ?? false;
    final expanded    = _expandedChallanId == id;
    final isSubmit    = _submitting.contains(id);

    if (expanded) _ensureChallanControllers(id, dc);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(
          color: verified ? Colors.blue.withValues(alpha: 0.4) : kBorderLight,
          width: verified ? 1.5 : 1,
        ),
        boxShadow: kCardShadow,
      ),
      child: Column(children: [
        // Header row
        InkWell(
          onTap: () => setState(() =>
          _expandedChallanId = expanded ? null : id),
          borderRadius: BorderRadius.vertical(
              top: const Radius.circular(kRadiusCard),
              bottom: Radius.circular(expanded ? 0 : kRadiusCard)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.receipt_long_outlined,
                    color: Colors.blue, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('DC: $dcNum',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800)),
                    Text('$farmerName  ·  $birds birds  ·  '
                        '${netWt.toStringAsFixed(1)} kg'
                        '${adjWt != null ? ' → ${adjWt.toStringAsFixed(1)} kg' : ''}',
                        style: const TextStyle(fontSize: 11, color: kTextSub)),
                  ])),
              if (verified)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('VERIFIED',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
                          color: Colors.blue)),
                )
              else
                TextButton(
                  onPressed: () => setState(() =>
                  _expandedChallanId = expanded ? null : id),
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero),
                  child: Text(expanded ? 'Close' : 'Verify',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700,
                          color: Colors.blue)),
                ),
              Icon(expanded
                  ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: kTextHint, size: 16),
            ]),
          ),
        ),

        // Expanded review form
        if (expanded) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // DC details
                  if (grossWt != null)
                    _detailRow('Gross weight', '${grossWt.toStringAsFixed(1)} kg'),
                  _detailRow('Net weight (recorded)', '${netWt.toStringAsFixed(1)} kg'),
                  if (dc['dc_verification_notes'] != null)
                    _detailRow('Previous notes',
                        dc['dc_verification_notes'] as String),
                  const SizedBox(height: 12),

                  // Adjusted weight
                  TextField(
                    controller: _dcWt[id],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Confirmed Net Weight (kg)',
                      hintText: netWt.toStringAsFixed(1),
                      suffixText: 'kg',
                      helperText: 'Edit only if DC weight differs from weighment slip',
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Notes
                  TextField(
                    controller: _dcNotes[id],
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Verification Notes (optional)',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 14),

                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isSubmit ? null : () =>
                            setState(() => _expandedChallanId = null),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: isSubmit ? null : () => _verifyDC(id),
                        icon: isSubmit
                            ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check_rounded, size: 16),
                        label: const Text('Mark DC as Verified',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                                color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue),
                      ),
                    ),
                  ]),
                ]),
          ),
        ],
      ]),
    );
  }

  // ── Delivery card ────────────────────────────────────────────────────────────
  Widget _buildDeliveryCard(Map<String, dynamic> d) {
    final id          = d['id'] as String;
    final shop        = d['shop_name'] as String? ?? '—';
    final birds       = (d['delivered_bird_count']   as num?)?.toInt()    ?? 0;
    final wt          = (d['delivered_total_weight'] as num?)?.toDouble() ?? 0;
    final cash        = (d['collected_amount']       as num?)?.toDouble() ?? 0;
    final mortalityB  = (d['mortality_birds']        as num?)?.toInt()    ?? 0;
    final lossPct     = (d['loss_percentage']        as num?)?.toDouble() ?? 0;
    final isHighLoss  = d['is_high_loss'] as bool? ?? false;
    final actorType   = d['completed_by_actor_type'] as String? ?? 'agent';
    final verified    = d['verified_by_trader'] as bool? ?? false;
    final hasDisc     = d['has_discrepancy'] as bool? ?? false;
    final adjWt       = (d['trader_adjusted_weight'] as num?)?.toDouble();
    final expanded    = _expandedDeliveryId == id;
    final isSubmit    = _submitting.contains(id);

    if (expanded) _ensureDeliveryControllers(id, d);

    Color borderColor = kBorderLight;
    if (hasDisc)   borderColor = Colors.orange;
    else if (verified) borderColor = Colors.green.withValues(alpha: 0.5);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(color: borderColor,
            width: (hasDisc || verified) ? 1.5 : 1),
        boxShadow: kCardShadow,
      ),
      child: Column(children: [
        // Header row
        InkWell(
          onTap: () => setState(() =>
          _expandedDeliveryId = expanded ? null : id),
          borderRadius: BorderRadius.vertical(
              top: const Radius.circular(kRadiusCard),
              bottom: Radius.circular(expanded ? 0 : kRadiusCard)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: kNavy.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.store_outlined,
                        color: kNavy, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(child: Text(shop,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w800))),
                          if (actorType == 'trader')
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('TRADER',
                                  style: TextStyle(fontSize: 8,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.orange, letterSpacing: 0.5)),
                            ),
                        ]),
                        Text(
                          '$birds birds  ·  ${wt.toStringAsFixed(1)} kg'
                              '${adjWt != null ? ' → ${adjWt.toStringAsFixed(1)} kg' : ''}'
                              '  ·  ${Fmt.amount(cash)}',
                          style: const TextStyle(fontSize: 11, color: kTextSub),
                        ),
                        if (mortalityB > 0 || isHighLoss)
                          Text(
                            '${mortalityB > 0 ? "Dead: $mortalityB birds  " : ""}'
                                '${isHighLoss ? "⚠ High variance: ${lossPct.toStringAsFixed(1)}%" : ""}',
                            style: const TextStyle(fontSize: 10, color: Colors.red),
                          ),
                      ])),
                  const SizedBox(width: 8),
                  Column(crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasDisc)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: Colors.orange.withValues(alpha: 0.4)),
                            ),
                            child: const Text('DISCREPANCY',
                                style: TextStyle(fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.orange)),
                          )
                        else if (verified)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('VERIFIED',
                                style: TextStyle(fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.green)),
                          )
                        else
                          TextButton(
                            onPressed: () => setState(() =>
                            _expandedDeliveryId = expanded ? null : id),
                            style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                minimumSize: Size.zero),
                            child: Text(expanded ? 'Close' : 'Review',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isHighLoss ? Colors.red : kNavy)),
                          ),
                        Icon(expanded
                            ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                            color: kTextHint, size: 14),
                      ]),
                ]),
          ),
        ),

        // Expanded review form
        if (expanded) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Delivery details
                  _detailRow('Agent entered', '${wt.toStringAsFixed(1)} kg  ·  $birds birds'),
                  if (d['mortality_birds'] != null && mortalityB > 0)
                    _detailRow('Mortality', '$mortalityB birds'),
                  if (lossPct > 0)
                    _detailRow('Weight Variance %', '${lossPct.toStringAsFixed(1)}%',
                        isHighLoss ? Colors.red : null),
                  const SizedBox(height: 12),
                  const Text('TRADER VERIFICATION',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                          color: kTextHint, letterSpacing: 0.6)),
                  const SizedBox(height: 8),

                  // Adjusted weight + birds
                  Row(children: [
                    Expanded(child: TextField(
                      controller: _wt[id],
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Confirmed Weight (kg)',
                        suffixText: 'kg',
                        helperText: 'Edit only if incorrect',
                      ),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(
                      controller: _birds[id],
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Confirmed Birds',
                        suffixText: 'birds',
                        helperText: 'Edit only if incorrect',
                      ),
                    )),
                  ]),
                  const SizedBox(height: 10),

                  // Notes
                  TextField(
                    controller: _notes[id],
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Review Notes (optional)',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Discrepancy flag
                  Container(
                    decoration: BoxDecoration(
                      color: (_hasDiscrepancy[id] == true)
                          ? Colors.orange.shade50 : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(kRadiusInner),
                      border: Border.all(
                        color: (_hasDiscrepancy[id] == true)
                            ? Colors.orange.shade300 : kBorderLight,
                      ),
                    ),
                    child: SwitchListTile(
                      value: _hasDiscrepancy[id] ?? false,
                      onChanged: (v) =>
                          setState(() => _hasDiscrepancy[id] = v),
                      activeColor: Colors.orange,
                      secondary: Icon(
                        (_hasDiscrepancy[id] == true)
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle_outline,
                        color: (_hasDiscrepancy[id] == true)
                            ? Colors.orange : Colors.green,
                      ),
                      title: Text(
                        (_hasDiscrepancy[id] == true)
                            ? 'Discrepancy Flagged'
                            : 'No Discrepancy',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700,
                            color: (_hasDiscrepancy[id] == true)
                                ? Colors.orange : Colors.green),
                      ),
                      subtitle: Text(
                        (_hasDiscrepancy[id] == true)
                            ? 'Weight/count mismatch noted — recorded for approval'
                            : 'Agent figures look correct',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isSubmit ? null : () =>
                            setState(() => _expandedDeliveryId = null),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: isSubmit ? null : () => _verifyDelivery(id),
                        icon: isSubmit
                            ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                            : Icon(
                            (_hasDiscrepancy[id] == true)
                                ? Icons.warning_amber_rounded
                                : Icons.check_rounded,
                            size: 16),
                        label: Text(
                          (_hasDiscrepancy[id] == true)
                              ? 'Flag & Save Review'
                              : 'Mark as Verified',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700,
                              color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: (_hasDiscrepancy[id] == true)
                              ? Colors.orange : kNavy,
                        ),
                      ),
                    ),
                  ]),
                ]),
          ),
        ],
      ]),
    );
  }

  // ── Action button ────────────────────────────────────────────────────────────
  Widget _actionButton() {
    final unverified = _totalDeliveries - _verifiedDeliveries;
    final allDone    = _verificationComplete;

    return Column(children: [
      if (!allDone)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(kRadiusCard),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline, color: Colors.orange, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(
              '$unverified delivery(s) not yet reviewed. '
                  'You can still proceed to approve.',
              style: const TextStyle(
                  fontSize: 11, color: Colors.orange),
            )),
          ]),
        ),
      if (_discrepancyCount > 0)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(kRadiusCard),
            border: Border.all(color: Colors.orange.shade300),
          ),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.orange, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(
              '$_discrepancyCount discrepancy(s) flagged. '
                  'These will be visible during approval.',
              style: const TextStyle(
                  fontSize: 11, color: Colors.orange,
                  fontWeight: FontWeight.w600),
            )),
          ]),
        ),
      ElevatedButton.icon(
        onPressed: () {
          // Navigate to shift detail screen for final approve_shift call
          context.pop();
        },
        icon: Icon(
            allDone
                ? Icons.check_circle_outline : Icons.arrow_forward_rounded,
            size: 20),
        label: Text(
          allDone
              ? '✓ Review Complete — Go to Approve'
              : 'Proceed to Approval Screen',
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w800,
              color: Colors.white),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: allDone ? Colors.green : kNavy,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kRadiusBtn)),
        ),
      ),
    ]);
  }

  // ── Already approved banner ──────────────────────────────────────────────────
  Widget _approvedBanner() => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.green.shade50,
      borderRadius: BorderRadius.circular(kRadiusCard),
      border: Border.all(color: Colors.green.shade300),
    ),
    child: const Row(children: [
      Icon(Icons.check_circle, color: Colors.green, size: 22),
      SizedBox(width: 10),
      Expanded(child: Text(
        'Shift already approved. Verification history shown below.',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
            color: Colors.green),
      )),
    ]),
  );

  // ── Helpers ──────────────────────────────────────────────────────────────────
  Widget _sectionHeader(String title, IconData icon, Color color) =>
      Row(children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Text(title,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                color: color, letterSpacing: 0.5)),
      ]);

  Widget _kpi(String label, String value, Color color) =>
      Expanded(child: Column(children: [
        Text(value, style: TextStyle(fontSize: 14,
            fontWeight: FontWeight.w900, color: color),
            textAlign: TextAlign.center,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(label, style: const TextStyle(fontSize: 9, color: kTextHint),
            textAlign: TextAlign.center),
      ]));

  Widget _alertRow(IconData icon, Color color, String msg) =>
      Padding(padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Expanded(child: Text(msg,
                style: TextStyle(fontSize: 11, color: color,
                    fontWeight: FontWeight.w600))),
          ]));

  Widget _detailRow(String label, String value, [Color? valueColor]) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            SizedBox(width: 140,
                child: Text(label, style: const TextStyle(
                    fontSize: 11, color: kTextSub))),
            Expanded(child: Text(value,
                style: TextStyle(fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: valueColor ?? kTextMain))),
          ]));
}