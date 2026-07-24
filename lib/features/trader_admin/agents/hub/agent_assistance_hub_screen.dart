import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:rooster_trader/features/trader_admin/agents/hub/trader_addexpense_sheet.dart' show showTraderAddExpenseSheet;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import 'agent_quick_entry.dart';
import 'current_batch_active_screen.dart';
import 'entry_mode_selector.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AGENT ASSISTANCE HUB
//
// Single workspace for a trader to manage a delivery agent's entire shift.
// All 10 assisted operations launch from here.
//
// Covered operations:
//   • Dashboard strip (8 KPIs)
//   • Adoption analytics (30-day self vs trader entry)
//   • Shift timeline
//   • Shift Open
//   • DC Upload (pickup_batch / add_batch_dc)
//   • Assign Order ← standard mid-shift workflow
//       Hub → Assign Order → Batch Detail → tap + on confirmed order
//       New delivery immediately appears in agent Pending Deliveries
//       No new batch or DC required unless additional stock is needed
//   • Instant Order
//   • Record Delivery / Reassign Order / Transfer Birds
//   • Add Expense / Close Shift
//
// Entry mode selector is shown on every form:
//   called | whatsapp | present | estimated
// ─────────────────────────────────────────────────────────────────────────────

class AgentAssistanceHubScreen extends ConsumerStatefulWidget {
  const AgentAssistanceHubScreen({
    super.key,
    required this.agentId,
    required this.agentName,
  });

  final String agentId;
  final String agentName;

  @override
  ConsumerState<AgentAssistanceHubScreen> createState() =>
      _AgentAssistanceHubScreenState();
}

class _AgentAssistanceHubScreenState
    extends ConsumerState<AgentAssistanceHubScreen> {
  final _c = Supabase.instance.client;

  bool _loading = true;
  bool _creatingBatch = false; // guards DC Upload's "Create Batch" against double-tap
  Map<String, dynamic> _dashboard = {};

  // Derived state from dashboard
  Map<String, dynamic>? get _shift =>
      _dashboard['shift'] as Map<String, dynamic>?;
  bool get _hasShift => _shift != null;

  Map<String, dynamic> get _stock =>
      (_dashboard['stock'] as Map<String, dynamic>?) ?? {};
  Map<String, dynamic> get _today =>
      (_dashboard['today'] as Map<String, dynamic>?) ?? {};
  Map<String, dynamic> get _required =>
      (_dashboard['required'] as Map<String, dynamic>?) ?? {};
  Map<String, dynamic> get _dcToday =>
      (_dashboard['dc_today'] as Map<String, dynamic>?) ?? {};
  Map<String, dynamic> get _adoptionStats =>
      (_dashboard['adoption_stats'] as Map<String, dynamic>?) ?? {};

  int get _stockBirds =>
      (_stock['available_birds'] as num?)?.toInt() ?? 0;
  int get _expenseCount =>
      (_dashboard['expense_count'] as num?)?.toInt() ?? 0;
  int get _transferCount =>
      (_dashboard['transfer_count'] as num?)?.toInt() ?? 0;
  int get _pendingCount =>
      (_required['order_count'] as num?)?.toInt() ?? 0;
  int get _dcCount =>
      (_dcToday['dc_count'] as num?)?.toInt() ?? 0;
  double get _todayCash =>
      (_today['cash_collected'] as num?)?.toDouble() ?? 0;
  int get _todayDelivered =>
      (_today['delivered_count'] as num?)?.toInt() ?? 0;

  List<Map<String, dynamic>> get _pendingList {
    final raw = _dashboard['pending_list'];
    if (raw == null) return [];
    return List<Map<String, dynamic>>.from(raw as List);
  }

  // Timeline events built from dashboard data
  List<_TimelineEvent> _timeline = [];

  // Batches for DC upload — loaded separately
  List<Map<String, dynamic>> _assignedBatches = [];
  // Count of confirmed orders available to assign to this agent's batch
  int _confirmedCount = 0;
  // Full confirmed order list for inline picker
  List<Map<String, dynamic>> _confirmedOrders = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final dash = await _c
          .rpc('get_agent_dashboard', params: {'p_agent_id': widget.agentId})
          .timeout(const Duration(seconds: 12));

      // Assigned/active batches for DC upload picker
      List<Map<String, dynamic>> batches = [];
      try {
        final b = await _c
            .from('delivery_batches')
            .select(
            'id,status,vehicle_no,total_birds,total_weight,'
                'delivery_challans(id)')
            .eq('delivery_agent_id', widget.agentId)
            .inFilter('status', ['assigned', 'picked_up', 'out_for_delivery'])
            .order('created_at', ascending: false);
        batches = List<Map<String, dynamic>>.from(b as List? ?? []);
      } catch (_) {}

      // Load confirmed orders available to assign to this agent
      int confirmedCount = 0;
      List<Map<String, dynamic>> confirmedOrders = [];
      try {
        final user = ref.read(appUserProvider).valueOrNull;
        if (user?.traderId != null) {
          final co = await _c
              .from('orders')
              .select('id,estimated_birds,total_quantity,'
              'retailers(shop_name)')
              .eq('trader_id', user!.traderId!)
              .eq('status', 'confirmed')
              .order('created_at', ascending: false);
          confirmedOrders = List<Map<String, dynamic>>.from(co as List? ?? []);
          confirmedCount  = confirmedOrders.length;
        }
      } catch (_) {}

      // Fetch timeline events from shift history
      List<_TimelineEvent> tl = [];
      try {
        tl = await _fetchTimeline();
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _dashboard = Map<String, dynamic>.from(
            (dash as Map<String, dynamic>?) ?? {});
        _assignedBatches = batches;
        _confirmedCount  = confirmedCount;
        _confirmedOrders = confirmedOrders;
        _timeline = tl;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showError(context, e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  Future<List<_TimelineEvent>> _fetchTimeline() async {
    final events = <_TimelineEvent>[];
    final shiftData = _shift;
    if (shiftData == null) return events;

    final shiftId = shiftData['id'] as String;

    // Shift open event
    events.add(_TimelineEvent(
      type: 'shift_open',
      label: 'Shift opened',
      detail: null,
      time: DateTime.tryParse(shiftData['start_at'] as String? ?? ''),
      actorType: 'agent',
      color: Colors.green,
      icon: Icons.play_circle_outline,
    ));

    // DCs
    try {
      final dcs = await _c
          .from('delivery_challans')
          .select('id,dc_number,farmer_name,created_at,bird_count,net_weight')
          .eq('shift_id', shiftId)
          .order('created_at');
      for (final dc in List<Map<String, dynamic>>.from(dcs as List? ?? [])) {
        events.add(_TimelineEvent(
          type: 'dc',
          label: 'DC: ${dc['dc_number'] ?? '—'} — ${dc['farmer_name'] ?? '—'}',
          detail:
          '${(dc['bird_count'] as num?)?.toInt() ?? 0} birds · ${((dc['net_weight'] as num?)?.toDouble() ?? 0).toStringAsFixed(1)} kg',
          time: DateTime.tryParse(dc['created_at'] as String? ?? ''),
          actorType: 'agent',
          color: Colors.blue,
          icon: Icons.receipt_long_outlined,
        ));
      }
    } catch (_) {}

    // Deliveries
    try {
      final delivs = await _c
          .from('deliveries')
          .select(
          'id,status,delivered_at,delivered_bird_count,delivered_total_weight,'
              'collected_amount,completed_by_actor_type,'
              'orders(retailers(shop_name))')
          .eq('delivery_shift_id', shiftId)
          .eq('status', 'delivered')
          .order('delivered_at');
      for (final d
      in List<Map<String, dynamic>>.from(delivs as List? ?? [])) {
        final shop = ((d['orders'] as Map?)?['retailers']
        as Map?)?['shop_name'] as String? ??
            '—';
        final actor = d['completed_by_actor_type'] as String? ?? 'agent';
        events.add(_TimelineEvent(
          type: 'delivery',
          label: 'Delivered → $shop',
          detail:
          '${(d['delivered_bird_count'] as num?)?.toInt() ?? 0} birds · '
              '${((d['delivered_total_weight'] as num?)?.toDouble() ?? 0).toStringAsFixed(1)} kg · '
              '${Fmt.amount(((d['collected_amount'] as num?)?.toDouble() ?? 0))}',
          time: DateTime.tryParse(d['delivered_at'] as String? ?? ''),
          actorType: actor,
          color: kNavy,
          icon: Icons.check_circle_outline,
        ));
      }
    } catch (_) {}

    // Transfers (today)
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];
      final trs = await _c
          .from('bird_transfers')
          .select('id,from_agent_id,to_agent_id,bird_count,weight_kg,created_at')
          .or('from_agent_id.eq.${widget.agentId},to_agent_id.eq.${widget.agentId}')
          .eq('transfer_date', today)
          .order('created_at');
      for (final t
      in List<Map<String, dynamic>>.from(trs as List? ?? [])) {
        final isOut = t['from_agent_id'] == widget.agentId;
        events.add(_TimelineEvent(
          type: 'transfer',
          label: isOut ? 'Transferred OUT birds' : 'Received IN birds',
          detail:
          '${(t['bird_count'] as num?)?.toInt() ?? 0} birds · '
              '${((t['weight_kg'] as num?)?.toDouble() ?? 0).toStringAsFixed(1)} kg',
          time: DateTime.tryParse(t['created_at'] as String? ?? ''),
          actorType: 'agent',
          color: Colors.purple,
          icon: Icons.swap_horiz_rounded,
        ));
      }
    } catch (_) {}

    // Expenses
    try {
      final exps = await _c
          .from('delivery_expenses')
          .select(
          'id,expense_type,amount,entered_by_actor_type,created_at')
          .eq('shift_id', shiftId)
          .order('created_at');
      for (final e
      in List<Map<String, dynamic>>.from(exps as List? ?? [])) {
        final actor = e['entered_by_actor_type'] as String? ?? 'agent';
        final type = e['expense_type'] as String? ?? 'misc';
        final amt = (e['amount'] as num?)?.toDouble() ?? 0;
        events.add(_TimelineEvent(
          type: 'expense',
          label: 'Expense: ${_expLabel(type)}',
          detail: Fmt.amount(amt),
          time: DateTime.tryParse(e['created_at'] as String? ?? ''),
          actorType: actor,
          color: const Color(0xFFD97706),
          icon: Icons.receipt_outlined,
        ));
      }
    } catch (_) {}

    events.sort((a, b) {
      if (a.time == null && b.time == null) return 0;
      if (a.time == null) return 1;
      if (b.time == null) return -1;
      return a.time!.compareTo(b.time!);
    });

    return events;
  }

  String _expLabel(String t) => switch (t) {
    'fuel' || 'diesel' => 'Fuel',
    'toll' => 'Toll',
    'allowance' => 'Allowance',
    'vehicle' => 'Vehicle',
    'loading' => 'Loading',
    'food' => 'Food',
    _ => 'Misc',
  };

  // ── Shift duration ──────────────────────────────────────────────────────────
  String get _shiftDuration {
    if (!_hasShift) return '—';
    final start = DateTime.tryParse(_shift!['start_at'] as String? ?? '');
    if (start == null) return '—';
    final dur = DateTime.now().difference(start);
    return '${dur.inHours}h ${dur.inMinutes.remainder(60)}m';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  // ── Assign Order Sheet ──────────────────────────────────────────────────────
  // Used when: shift open + no active batch (all deliveries completed).
  // Auto-creates a new 'assigned' batch for this agent, then adds the chosen order.
  // No DC required — agent uses existing shift stock for the new delivery.
  Future<void> _showAssignOrderSheet() async {
    if (_confirmedOrders.isEmpty) {
      showError(context, 'No confirmed orders to assign.');
      return;
    }

    // Show confirmed order picker
    Map<String, dynamic>? chosen;
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.65),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 38, height: 4,
                decoration: BoxDecoration(
                    color: kBorderLight,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Assign Order to ${widget.agentName}',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: kNavy)),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.info_outline,
                          size: 12, color: Colors.orange.shade700),
                      const SizedBox(width: 4),
                      Text(
                        'All deliveries done — a new batch will be '
                            'created automatically.',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange.shade700),
                      ),
                    ]),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(
                    vertical: 8, horizontal: 4),
                itemCount: _confirmedOrders.length,
                separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 56),
                itemBuilder: (ctx, i) {
                  final o = _confirmedOrders[i];
                  final r = o['retailers'] as Map<String, dynamic>?;
                  final shop = r?['shop_name'] as String? ?? '—';
                  final birds =
                      (o['estimated_birds'] as num?)?.toInt() ?? 0;
                  final kg = (o['total_quantity'] as num?)
                      ?.toStringAsFixed(1) ?? '—';
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                      const Color(0xFF0284C7).withValues(alpha: 0.12),
                      radius: 20,
                      child: const Icon(Icons.store_outlined,
                          size: 18, color: Color(0xFF0284C7)),
                    ),
                    title: Text(shop,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    subtitle: Text('$birds birds · $kg kg',
                        style: const TextStyle(
                            fontSize: 12, color: kTextSub)),
                    trailing: const Icon(
                        Icons.add_circle_outline,
                        color: Color(0xFF0284C7)),
                    onTap: () {
                      chosen = o;
                      Navigator.of(ctx, rootNavigator: true).pop();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (chosen == null || !mounted) return;
    await _assignOrderWithNewBatch(chosen!);
  }

  // Reuses the agent's existing open batch, or creates one silently — via
  // the shared `assign_orders_to_agent` RPC. This is the ONLY batch-creation
  // path in the app (dispatch_screen.dart's old manual "New Batch" button
  // has been removed entirely) so a trader can never end up with two
  // concurrently-open batches for the same agent from two different screens.
  Future<void> _assignOrderWithNewBatch(
      Map<String, dynamic> order) async {
    final user = ref.read(appUserProvider).valueOrNull;
    final traderId = user?.traderId;
    if (traderId == null || !mounted) return;

    try {
      await _c.rpc('assign_orders_to_agent', params: {
        'p_trader_id': traderId,
        'p_agent_id':  widget.agentId,
        'p_order_ids': [order['id'] as String],
      });

      if (!mounted) return;
      final shop = (order['retailers']
      as Map<String, dynamic>?)?['shop_name'] as String? ??
          'order';
      showSuccess(context,
          '✓ $shop assigned to ${widget.agentName}.\n'
              'Appears in Pending Deliveries immediately.');
      _load(); // refresh everything
    } catch (e) {
      if (!mounted) return;
      showError(context,
          e.toString()
              .replaceAll('Exception: ', '')
              .replaceAll('PostgrestException(message: ', ''));
    }
  }

  Future<void> _showOpenShiftSheet() async {
    await showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OpenShiftSheet(
        agentId: widget.agentId,
        agentName: widget.agentName,
        onDone: _load,
      ),
    );
  }

  Future<void> _showDCUploadSheet(Map<String, dynamic>? batch) async {
    if (batch != null) {
      context.push(R.batchDetailPath(batch['id'] as String));
      return;
    }

    // No active batch — offer to create one via the SAME shared function
    // Dispatch already uses (ensure_active_batch_for_agent, reached today
    // through assign_orders_to_agent). This is the only batch-creation path
    // in the app; nothing new is introduced here.
    final ok = await confirmDialog(
      context,
      title: 'No Active Batch',
      message: 'No active batch found for this agent.\nCreate an active batch now?',
      confirmText: 'Create Batch',
      confirmColor: kNavy,
    );
    if (!ok || !mounted) return;

    final user = ref.read(appUserProvider).valueOrNull;
    final traderId = user?.traderId;
    if (traderId == null) return;

    setState(() => _creatingBatch = true);
    try {
      final batchId = await _c.rpc('ensure_active_batch_for_agent', params: {
        'p_trader_id': traderId,
        'p_agent_id': widget.agentId,
      }) as String;

      if (!mounted) return;
      await _load(); // refresh Hub state (assigned batches, counts, etc.)
      if (!mounted) return;
      setState(() => _creatingBatch = false);
      context.push(R.batchDetailPath(batchId)).then((_) => _load());
    } catch (e) {
      if (!mounted) return;
      setState(() => _creatingBatch = false);
      showError(
          context,
          e
              .toString()
              .replaceAll('Exception: ', '')
              .replaceAll('PostgrestException(message: ', ''));
    }
  }

  Future<void> _showInstantOrderSheet() async {
    if (!_hasShift) {
      showError(context, 'Agent has no open shift. Open a shift first.');
      return;
    }
    await showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InstantOrderSheet(
        agentId: widget.agentId,
        agentName: widget.agentName,
        onDone: _load,
      ),
    );
  }

  Future<void> _showQuickEntrySheet() async {
    if (!_hasShift) {
      showError(context, 'Agent has no open shift. Open a shift first.');
      return;
    }
    await showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AgentQuickEntrySheet(
        agentId: widget.agentId,
        agentName: widget.agentName,
        onDone: _load,
        onRecoveryNeeded: (deliveryId) {
          // Called after the sheet has already popped itself — safe to use
          // this Hub screen's own (still-mounted) context to navigate.
          if (!mounted) return;
          context.push(
            R.agentAssistDeliveryPath(widget.agentId, deliveryId),
            extra: {'agentName': widget.agentName},
          ).then((_) => _load());
        },
      ),
    );
  }

  Future<void> _showCurrentBatchActivities() async {
    if (!_hasShift) {
      showError(context, 'Agent has no open shift.');
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CurrentBatchActivitiesScreen(
        agentId: widget.agentId,
        agentName: widget.agentName,
      ),
    ));
    if (mounted) _load();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kNavy,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.agentName,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.white),
            ),
            const Text(
              'Agent Assistance Hub',
              style: TextStyle(fontSize: 11, color: Color(0xFFB4C6F4)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const LoadingList()
          : RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            // ── Shift status hero card ──────────────────────────────────
            _buildShiftHeroCard(),
            const SizedBox(height: 14),

            // ── Dashboard KPI strip ─────────────────────────────────────
            _buildDashboardStrip(),
            const SizedBox(height: 14),

            // ── Adoption analytics ──────────────────────────────────────
            _buildAdoptionCard(),
            const SizedBox(height: 14),

            // ── Quick actions ───────────────────────────────────────────
            _buildQuickActions(),
            const SizedBox(height: 14),

            // ── Pending deliveries ──────────────────────────────────────
            if (_pendingList.isNotEmpty) ...[
              _buildPendingDeliveries(),
              const SizedBox(height: 14),
            ],

            // ── Shift timeline ──────────────────────────────────────────
            _buildTimeline(),
          ],
        ),
      ),
    );
  }

  // ── Shift Hero Card ─────────────────────────────────────────────────────────
  Widget _buildShiftHeroCard() {
    final hasShift = _hasShift;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: hasShift
              ? [const Color(0xFF003010), const Color(0xFF005020)]
              : [const Color(0xFF1A0000), const Color(0xFF3B0000)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(kRadiusHero),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  hasShift
                      ? Icons.directions_car_rounded
                      : Icons.directions_car_outlined,
                  color: hasShift ? Colors.greenAccent : Colors.redAccent,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasShift ? 'Shift Active' : 'No Active Shift',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: hasShift ? Colors.greenAccent : Colors.redAccent,
                      ),
                    ),
                    Text(
                      hasShift
                          ? 'Duration: $_shiftDuration'
                          : 'Tap to open shift for this agent',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white60),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: (hasShift ? Colors.green : Colors.red)
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(kRadiusChip),
                  border: Border.all(
                    color: hasShift ? Colors.greenAccent : Colors.redAccent,
                    width: 1,
                  ),
                ),
                child: Text(
                  hasShift ? 'OPEN' : 'CLOSED',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color:
                    hasShift ? Colors.greenAccent : Colors.redAccent,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
          if (hasShift) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                _heroStat('🐔', '$_stockBirds', 'Stock'),
                _heroStat('🚛', '$_todayDelivered', 'Delivered'),
                _heroStat(
                    '💰', Fmt.amount(_todayCash), 'Collected'),
                _heroStat('⏳', '$_pendingCount', 'Pending'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _heroStat(String emoji, String value, String label) => Expanded(
    child: Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(kRadiusChip),
      ),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 9, color: Colors.white60),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );

  // ── Dashboard KPI Strip ─────────────────────────────────────────────────────
  Widget _buildDashboardStrip() {
    final kpis = [
      _KpiData('DCs Today', '$_dcCount', Icons.receipt_long_outlined, Colors.blue),
      _KpiData('Expenses', '$_expenseCount', Icons.receipt_outlined, const Color(0xFFD97706)),
      _KpiData('Transfers', '$_transferCount', Icons.swap_horiz_rounded, Colors.purple),
      _KpiData('Duration', _shiftDuration, Icons.timer_outlined, Colors.teal),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(color: kBorderLight),
        boxShadow: kCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SHIFT DASHBOARD',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: kTextHint,
                letterSpacing: 0.8),
          ),
          const SizedBox(height: 12),
          Row(
            children: kpis
                .map((k) => Expanded(
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                    vertical: 10, horizontal: 8),
                decoration: BoxDecoration(
                  color: k.color.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(kRadiusInner),
                  border: Border.all(
                      color: k.color.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    Icon(k.icon, color: k.color, size: 18),
                    const SizedBox(height: 4),
                    Text(
                      k.value,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: k.color,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      k.label,
                      style: const TextStyle(
                          fontSize: 9, color: kTextHint),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ))
                .toList(),
          ),
        ],
      ),
    );
  }

  // ── Adoption Analytics ──────────────────────────────────────────────────────
  Widget _buildAdoptionCard() {
    final self = (_adoptionStats['self_entered'] as num?)?.toInt() ?? 0;
    final trader = (_adoptionStats['trader_entered'] as num?)?.toInt() ?? 0;
    final total = self + trader;
    final selfPct = total > 0 ? (self / total * 100).round() : 0;
    final traderPct = total > 0 ? (trader / total * 100).round() : 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(color: kBorderLight),
        boxShadow: kCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ADOPTION ANALYTICS',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: kTextHint,
                          letterSpacing: 0.8),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Last 30 days',
                      style: TextStyle(fontSize: 11, color: kTextHint),
                    ),
                  ],
                ),
              ),
              if (total > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: kNavy.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(kRadiusChip),
                  ),
                  child: Text(
                    '$total ops total',
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: kNavy),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (total == 0)
            const Text(
              'No operations recorded yet.',
              style: TextStyle(fontSize: 12, color: kTextHint),
            )
          else ...[
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 10,
                child: LinearProgressIndicator(
                  value: total > 0 ? self / total : 0,
                  backgroundColor: Colors.orange.shade200,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF005020)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _adoptionStat(
                    '📱 Agent Usage',
                    '$selfPct%',
                    '$self ops',
                    const Color(0xFF005020),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _adoptionStat(
                    '🧑‍💼 Trader Assist',
                    '$traderPct%',
                    '$trader ops',
                    Colors.orange.shade700,
                  ),
                ),
              ],
            ),
            if (traderPct > 50)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(kRadiusInner),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.orange, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Agent not using app for $traderPct% of operations. Consider training.',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.orange),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _adoptionStat(
      String label, String pct, String count, Color color) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(kRadiusInner),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color)),
            const SizedBox(height: 4),
            Text(pct,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: color)),
            Text(count,
                style: TextStyle(
                    fontSize: 10,
                    color: color.withValues(alpha: 0.7))),
          ],
        ),
      );

  // ── Quick Actions ───────────────────────────────────────────────────────────
  Widget _buildQuickActions() {
    final actions = <_ActionItem>[
      if (!_hasShift)
        _ActionItem(
          label: 'Open Shift',
          icon: Icons.play_circle_outline_rounded,
          color: Colors.green,
          onTap: _showOpenShiftSheet,
        ),
      _ActionItem(
        label: 'DC Upload',
        icon: Icons.receipt_long_outlined,
        color: Colors.blue,
        enabled: (_hasShift || _assignedBatches.isNotEmpty) && !_creatingBatch,
        onTap: () => _showDCUploadSheet(
          _assignedBatches.isEmpty ? null : _assignedBatches.first,
        ),
      ),
      // Assign Order — two paths:
      //   A) Active batch exists → navigate to Batch Detail (tap + on order)
      //   B) No active batch (all done, shift still open) → auto-create batch,
      //      show inline order picker, add order, agent sees it immediately
      // Enabled: shift open AND at least one confirmed order to assign
      _ActionItem(
        label: 'Assign Order',
        icon: Icons.playlist_add_rounded,
        color: const Color(0xFF0284C7),
        enabled: _hasShift && _confirmedCount > 0,
        badge: _hasShift ? _confirmedCount : 0,
        disabledHint: !_hasShift
            ? 'Open a shift before assigning orders.'
            : 'No confirmed orders to assign.',
        onTap: () {
          if (_assignedBatches.isNotEmpty) {
            // Path A: active batch exists — go to Batch Detail
            context.push(
              R.batchDetailPath(_assignedBatches.first['id'] as String),
            ).then((_) => _load());
          } else {
            // Path B: all deliveries done, shift still open —
            // show order picker, auto-create batch, assign immediately
            _showAssignOrderSheet();
          }
        },
      ),
      _ActionItem(
        label: 'Instant Order',
        icon: Icons.flash_on_rounded,
        color: const Color(0xFFD97706),
        enabled: _hasShift,
        onTap: _showInstantOrderSheet,
      ),
      // Quick Entry — multi-product proxy entry (order + delivery in one pass)
      _ActionItem(
        label: 'Quick Entry',
        icon: Icons.bolt_rounded,
        color: kNavy,
        enabled: _hasShift,
        disabledHint: 'Open a shift before using Quick Entry.',
        onTap: _showQuickEntrySheet,
      ),
      // Current Batch Activities — undo a mistaken Quick Entry delivery
      // while the batch/shift is still open and before approval/invoice.
      _ActionItem(
        label: 'Current Batch Activities',
        icon: Icons.history_rounded,
        color: Colors.deepOrange,
        enabled: _hasShift,
        disabledHint: 'Open a shift to view current batch activities.',
        onTap: _showCurrentBatchActivities,
      ),
      // Phase 5B
      _ActionItem(
        label: 'Record Delivery',
        icon: Icons.local_shipping_outlined,
        color: kNavy,
        // FIX P0: include assigned+picked_up — stock via transfer keeps delivery at 'assigned'
        enabled: _pendingList
            .any((d) => ['assigned','picked_up','out_for_delivery']
            .contains(d['status'] as String?)),
        badge: _pendingList
            .where((d) => ['assigned','picked_up','out_for_delivery']
            .contains(d['status'] as String?))
            .length,
        onTap: () {
          final ready = _pendingList
              .where((d) => ['assigned','picked_up','out_for_delivery']
              .contains(d['status'] as String?))
              .toList();
          if (ready.isEmpty) {
            showError(context, 'No active deliveries to record.');
            return;
          }
          context.push(
            R.agentAssistDeliveryPickerPath(widget.agentId),
            extra: {
              'agentName': widget.agentName,
              'pendingList': ready,
            },
          );
        },
      ),
      // Phase 5B
      _ActionItem(
        label: 'Reassign Order',
        icon: Icons.swap_horiz_rounded,
        color: Colors.purple,
        enabled: _pendingList.isNotEmpty,
        onTap: () {
          if (_pendingList.isEmpty) {
            showError(context, 'No pending deliveries to reassign.');
            return;
          }
          context.push(
            R.agentAssistReassignPath(widget.agentId),
            extra: {
              'agentName': widget.agentName,
              'pendingList': _pendingList,
            },
          );
        },
      ),
      // Phase 5C
      _ActionItem(
        label: 'Transfer Birds',
        icon: Icons.compare_arrows_rounded,
        color: Colors.teal,
        enabled: _hasShift && _stockBirds > 0 && _assignedBatches.isNotEmpty,
        onTap: () {
          if (_assignedBatches.isEmpty) {
            showError(context,
                'No active batch found. DC must be uploaded first.');
            return;
          }
          context.push(
            R.agentAssistTransferPath(
                widget.agentId, _assignedBatches.first['id'] as String),
            extra: {'agentName': widget.agentName},
          );
        },
      ),
      // Phase 5C
      _ActionItem(
        label: 'Add Expense',
        icon: Icons.receipt_outlined,
        color: const Color(0xFFD97706),
        enabled: _hasShift,
        onTap: () {
          if (!_hasShift) {
            showError(context, 'No open shift. Open a shift first.');
            return;
          }
          final user = ref.read(appUserProvider).valueOrNull;
          if (user?.traderId == null) return;
          showTraderAddExpenseSheet(
            context,
            agentId:   widget.agentId,
            agentName: widget.agentName,
            shiftId:   _shift!['id'] as String,
            traderId:  user!.traderId!,
            onDone:    _load,
          );
        },
      ),
      // Phase 5D
      _ActionItem(
        label: 'Close Shift',
        icon: Icons.lock_outline_rounded,
        color: Colors.red,
        enabled: _hasShift,
        onTap: () {
          if (!_hasShift) {
            showError(context, 'No open shift to close.');
            return;
          }
          context.push(
            R.agentAssistShiftClosePath(
                widget.agentId, _shift!['id'] as String),
            extra: {'agentName': widget.agentName},
          );
        },
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(color: kBorderLight),
        boxShadow: kCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ASSISTED OPERATIONS',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: kTextHint,
                letterSpacing: 0.8),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: actions.map(_buildActionChip).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildActionChip(_ActionItem action) {
    final enabled = action.enabled;
    return GestureDetector(
      onTap: enabled
          ? action.onTap
          : action.disabledHint != null
          ? () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(action.disabledHint!),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      )
          : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: enabled
                  ? action.color.withValues(alpha: 0.1)
                  : kBorderLight.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(kRadiusChip),
              border: Border.all(
                color: enabled
                    ? action.color.withValues(alpha: 0.4)
                    : kBorderLight,
                width: enabled ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  action.icon,
                  size: 16,
                  color: enabled ? action.color : kTextHint,
                ),
                const SizedBox(width: 6),
                Text(
                  action.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: enabled ? action.color : kTextHint,
                  ),
                ),
              ],
            ),
          ),
          if (action.badge > 0)
            Positioned(
              right: -6,
              top: -6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${action.badge}',
                  style: const TextStyle(
                      fontSize: 9,
                      color: Colors.white,
                      fontWeight: FontWeight.w900),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Pending Deliveries ──────────────────────────────────────────────────────
  Widget _buildPendingDeliveries() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(color: kBorderLight),
        boxShadow: kCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'PENDING DELIVERIES',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: kTextHint,
                      letterSpacing: 0.8),
                ),
              ),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_pendingList.length}',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.orange),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._pendingList.map((d) => _pendingDeliveryRow(d)),
        ],
      ),
    );
  }

  Widget _pendingDeliveryRow(Map<String, dynamic> d) {
    final shop = d['shop_name'] as String? ?? '—';
    final status = d['status'] as String? ?? '';
    final birds = (d['estimated_birds'] as num?)?.toInt() ?? 0;
    final weight = (d['total_quantity'] as num?)?.toDouble() ?? 0;
    final statusColor = status == 'out_for_delivery'
        ? kNavy
        : status == 'picked_up'
        ? Colors.blue
        : Colors.orange;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(kRadiusInner),
        border: Border.all(color: statusColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shop,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                Text(
                    '$birds birds · ${weight.toStringAsFixed(1)} kg',
                    style: const TextStyle(
                        fontSize: 11, color: kTextHint)),
              ],
            ),
          ),
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              status.replaceAll('_', ' '),
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: statusColor),
            ),
          ),
        ],
      ),
    );
  }

  // ── Timeline ────────────────────────────────────────────────────────────────
  Widget _buildTimeline() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(color: kBorderLight),
        boxShadow: kCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SHIFT TIMELINE',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: kTextHint,
                letterSpacing: 0.8),
          ),
          const SizedBox(height: 12),
          if (_timeline.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'No shift activity yet.',
                  style: TextStyle(fontSize: 13, color: kTextHint),
                ),
              ),
            )
          else
            ...List.generate(_timeline.length, (i) {
              final event = _timeline[i];
              final isLast = i == _timeline.length - 1;
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Timeline spine
                    SizedBox(
                      width: 32,
                      child: Column(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: event.color.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: event.color.withValues(alpha: 0.4)),
                            ),
                            child: Icon(event.icon,
                                size: 14, color: event.color),
                          ),
                          if (!isLast)
                            Expanded(
                              child: Container(
                                width: 1,
                                margin:
                                const EdgeInsets.symmetric(vertical: 2),
                                color: kBorderLight,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Event content
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                            bottom: isLast ? 0 : 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    event.label,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: kTextMain),
                                  ),
                                ),
                                if (event.actorType == 'trader')
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.orange
                                          .withValues(alpha: 0.12),
                                      borderRadius:
                                      BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'TRADER',
                                      style: TextStyle(
                                          fontSize: 8,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.orange,
                                          letterSpacing: 0.5),
                                    ),
                                  ),
                              ],
                            ),
                            if (event.detail != null)
                              Text(
                                event.detail!,
                                style: const TextStyle(
                                    fontSize: 11, color: kTextHint),
                              ),
                            if (event.time != null)
                              Text(
                                DateFormat('h:mm a').format(event.time!),
                                style: const TextStyle(
                                    fontSize: 10, color: kTextHint),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OPEN SHIFT BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _OpenShiftSheet extends ConsumerStatefulWidget {
  const _OpenShiftSheet({
    required this.agentId,
    required this.agentName,
    required this.onDone,
  });

  final String agentId;
  final String agentName;
  final VoidCallback onDone;

  @override
  ConsumerState<_OpenShiftSheet> createState() => _OpenShiftSheetState();
}

class _OpenShiftSheetState extends ConsumerState<_OpenShiftSheet> {
  final _c = Supabase.instance.client;
  final _odoCtrl = TextEditingController();
  String _entryMode = 'called';
  DateTime? _actualAt;
  bool _submitting = false;

  @override
  void dispose() {
    _odoCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickActualTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.now());
    if (time == null || !mounted) return;
    setState(() => _actualAt = DateTime(
        date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _submit() async {
    final user = ref.read(appUserProvider).valueOrNull;
    if (user == null) return;

    setState(() => _submitting = true);
    try {
      await _c.rpc('open_shift_for_agent', params: {
        'p_agent_id': widget.agentId,
        'p_trader_id': user.traderId,
        'p_odometer_start':
        double.tryParse(_odoCtrl.text.trim()) ?? 0.0,
        'p_actor_id': user.userId,
        'p_entry_mode': _entryMode,
        if (_actualAt != null)
          'p_actual_at': _actualAt!.toIso8601String(),
      });
      if (mounted) {
        showSuccess(context, '✅ Shift opened for ${widget.agentName}');
        Navigator.of(context, rootNavigator: true).pop();
        widget.onDone();
      }
    } catch (e) {
      if (mounted) {
        showError(context,
            e.toString().replaceAll('Exception: ', '').replaceAll(
                'PostgrestException(message: ', ''));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: kBgPage,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: kBorderLight,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          // Header
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.play_circle_outline,
                    color: Colors.green, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Open Shift for Agent',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      widget.agentName,
                      style: const TextStyle(
                          fontSize: 12, color: kTextHint),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Entry mode
          const Text(
            'HOW DID AGENT REPORT?',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: kTextHint,
                letterSpacing: 0.8),
          ),
          const SizedBox(height: 8),
          EntryModeSelector(
            value: _entryMode,
            onChanged: (v) => setState(() => _entryMode = v),
          ),
          const SizedBox(height: 16),

          // Odometer
          TextField(
            controller: _odoCtrl,
            keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Odometer Start (km)',
              prefixIcon: Icon(Icons.speed_outlined, size: 20),
              suffixText: 'km',
            ),
          ),
          const SizedBox(height: 12),

          // Backdating
          GestureDetector(
            onTap: _pickActualTime,
            child: Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _actualAt != null
                    ? kNavy.withValues(alpha: 0.06)
                    : kBorderLight.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(kRadiusInner),
                border: Border.all(
                    color: _actualAt != null ? kNavy : kBorderLight),
              ),
              child: Row(
                children: [
                  Icon(Icons.history_rounded,
                      size: 18,
                      color: _actualAt != null ? kNavy : kTextHint),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _actualAt != null
                          ? 'Backdated: ${DateFormat('d MMM h:mm a').format(_actualAt!)}'
                          : 'Backdate (optional) — tap to set actual time',
                      style: TextStyle(
                          fontSize: 13,
                          color: _actualAt != null ? kNavy : kTextHint),
                    ),
                  ),
                  if (_actualAt != null)
                    GestureDetector(
                      onTap: () => setState(() => _actualAt = null),
                      child: const Icon(Icons.close,
                          size: 16, color: kTextHint),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(kRadiusBtn)),
              ),
              child: _submitting
                  ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
                  : Text(
                'Open Shift for ${widget.agentName}',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INSTANT ORDER BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _InstantOrderSheet extends ConsumerStatefulWidget {
  const _InstantOrderSheet({
    required this.agentId,
    required this.agentName,
    required this.onDone,
  });

  final String agentId;
  final String agentName;
  final VoidCallback onDone;

  @override
  ConsumerState<_InstantOrderSheet> createState() =>
      _InstantOrderSheetState();
}

class _InstantOrderSheetState extends ConsumerState<_InstantOrderSheet> {
  final _c = Supabase.instance.client;
  final _birdsCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  List<Map<String, dynamic>> _retailers = [];
  List<Map<String, dynamic>> _products = [];
  Map<String, dynamic>? _selRetailer;
  Map<String, dynamic>? _selProduct;
  String _payMode = 'cash';
  String _entryMode = 'called';
  DateTime? _actualAt;
  bool _loading = true;
  bool _submitting = false;
  String? _err;

  int get _birds => int.tryParse(_birdsCtrl.text.trim()) ?? 0;
  double get _weight =>
      double.tryParse(_weightCtrl.text.trim()) ?? 0;
  double get _rate => double.tryParse(_rateCtrl.text.trim()) ?? 0;
  double get _total => _weight * _rate;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _birdsCtrl.dispose();
    _weightCtrl.dispose();
    _rateCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    try {
      final results = await Future.wait([
        _c
            .from('retailers')
            .select('id,shop_name,phone,address')
            .eq('trader_id', tid)
            .eq('is_active', true)
            .order('shop_name'),
        _c
            .from('master_products')
            .select('id,name,unit')
            .eq('is_active', true)
            .order('name'),
      ]);
      if (!mounted) return;
      setState(() {
        _retailers =
        List<Map<String, dynamic>>.from(results[0] as List? ?? []);
        _products =
        List<Map<String, dynamic>>.from(results[1] as List? ?? []);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickActualTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
        context: context,
        initialDate: now,
        firstDate: now.subtract(const Duration(days: 1)),
        lastDate: now);
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.now());
    if (time == null || !mounted) return;
    setState(() => _actualAt = DateTime(
        date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _submit() async {
    setState(() => _err = null);
    if (_selRetailer == null) {
      setState(() => _err = 'Select a retailer');
      return;
    }
    if (_birds <= 0 && _weight <= 0) {
      setState(() => _err = 'Enter birds or weight');
      return;
    }
    final user = ref.read(appUserProvider).valueOrNull;
    if (user == null) return;

    final ok = await confirmDialog(
      context,
      title: 'Create Instant Order',
      message: '${_selRetailer!['shop_name']}\n'
          'Birds: $_birds  ·  Weight: ${_weight.toStringAsFixed(1)} kg\n'
          '${_rate > 0 ? 'Amount: ${Fmt.amount(_total)}\n' : ''}'
          'Payment: $_payMode\n\n'
          'Acting on behalf of ${widget.agentName}.',
      confirmText: 'Create & Deliver',
      confirmColor: kNavy,
    );
    if (!ok || !mounted) return;

    setState(() => _submitting = true);
    try {
      await _c.rpc('agent_create_instant_order', params: {
        'p_agent_id': widget.agentId,
        'p_retailer_id': _selRetailer!['id'],
        'p_product_id': _selProduct?['id'],
        'p_birds': _birds,
        'p_weight_kg': _weight,
        if (_rate > 0) 'p_rate_per_kg': _rate,
        'p_payment_mode': _payMode,
        if (_notesCtrl.text.trim().isNotEmpty)
          'p_notes': _notesCtrl.text.trim(),
        'p_actor_type': 'trader',
        'p_actor_id': user.userId,
        'p_entry_mode': _entryMode,
        if (_actualAt != null)
          'p_actual_at': _actualAt!.toIso8601String(),
      });
      if (mounted) {
        showSuccess(
            context,
            '⚡ Instant order created for ${widget.agentName}\n'
                '${_selRetailer!['shop_name']} — $_birds birds');
        Navigator.of(context, rootNavigator: true).pop();
        widget.onDone();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _err = e
            .toString()
            .replaceAll('Exception: ', '')
            .replaceAll('PostgrestException(message: ', '')
            .replaceAll(')', ''));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: kBgPage,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: _loading
          ? const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: kBorderLight,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            // Header
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD97706)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.flash_on_rounded,
                      color: Color(0xFFD97706), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Instant Order',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800),
                      ),
                      Text(
                        'For ${widget.agentName}',
                        style: const TextStyle(
                            fontSize: 12, color: kTextHint),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Entry mode
            const Text(
              'HOW DID AGENT REPORT?',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: kTextHint,
                  letterSpacing: 0.8),
            ),
            const SizedBox(height: 8),
            EntryModeSelector(
              value: _entryMode,
              onChanged: (v) => setState(() => _entryMode = v),
            ),
            const SizedBox(height: 16),

            // Retailer
            const SectionHeader('RETAILER'),
            if (_retailers.isEmpty)
              const Text('No retailers found.',
                  style: TextStyle(color: kTextHint, fontSize: 12))
            else
              SearchableRetailerPicker(
                items: _retailers,
                labelKey: 'shop_name',
                hint: 'Choose retailer / shop',
                sheetTitle: 'Select Retailer',
                value: _selRetailer,
                onChanged: (v) => setState(() => _selRetailer = v),
              ),
            const SizedBox(height: 12),

            // Product
            if (_products.isNotEmpty) ...[
              const SectionHeader('PRODUCT (OPTIONAL)'),
              DropdownButtonFormField<Map<String, dynamic>>(
                value: _selProduct,
                decoration: const InputDecoration(
                    hintText: 'Select product'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('No product selected',
                        style: TextStyle(color: kTextHint)),
                  ),
                  ..._products.map((p) => DropdownMenuItem(
                    value: p,
                    child: Text(p['name'] as String),
                  )),
                ],
                onChanged: (v) =>
                    setState(() => _selProduct = v),
              ),
              const SizedBox(height: 12),
            ],

            // Birds + Weight + Rate
            const SectionHeader('QUANTITY & RATE'),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _birdsCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                        labelText: 'Birds',
                        suffixText: 'birds'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _weightCtrl,
                    keyboardType:
                    const TextInputType.numberWithOptions(
                        decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                        labelText: 'Weight (kg)',
                        suffixText: 'kg'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _rateCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Rate (₹/kg)',
                prefixText: '₹',
              ),
            ),
            if (_rate > 0 && _weight > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Total: ${Fmt.amount(_total)}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: kNavy),
                ),
              ),
            const SizedBox(height: 12),

            // Payment mode
            const SectionHeader('PAYMENT MODE'),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'cash', label: Text('Cash')),
                ButtonSegment(value: 'upi', label: Text('UPI')),
                ButtonSegment(
                    value: 'credit', label: Text('Credit')),
              ],
              selected: {_payMode},
              onSelectionChanged: (s) =>
                  setState(() => _payMode = s.first),
            ),
            const SizedBox(height: 12),

            // Notes
            TextField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),

            // Backdating
            GestureDetector(
              onTap: _pickActualTime,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _actualAt != null
                      ? kNavy.withValues(alpha: 0.06)
                      : kBorderLight.withValues(alpha: 0.4),
                  borderRadius:
                  BorderRadius.circular(kRadiusInner),
                  border: Border.all(
                      color: _actualAt != null
                          ? kNavy
                          : kBorderLight),
                ),
                child: Row(
                  children: [
                    Icon(Icons.history_rounded,
                        size: 18,
                        color: _actualAt != null
                            ? kNavy
                            : kTextHint),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _actualAt != null
                            ? 'Backdated: ${DateFormat('d MMM h:mm a').format(_actualAt!)}'
                            : 'Backdate (optional)',
                        style: TextStyle(
                            fontSize: 12,
                            color: _actualAt != null
                                ? kNavy
                                : kTextHint),
                      ),
                    ),
                    if (_actualAt != null)
                      GestureDetector(
                        onTap: () =>
                            setState(() => _actualAt = null),
                        child: const Icon(Icons.close,
                            size: 16, color: kTextHint),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            if (_err != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: kErrorBg,
                    borderRadius:
                    BorderRadius.circular(kRadiusInner),
                  ),
                  child: Text(_err!,
                      style: const TextStyle(
                          fontSize: 12, color: kError)),
                ),
              ),

            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706),
                  shape: RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(kRadiusBtn)),
                ),
                child: _submitting
                    ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white))
                    : const Text(
                  '⚡ Create Instant Order',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODELS (private to this file)
// ─────────────────────────────────────────────────────────────────────────────

class _TimelineEvent {
  const _TimelineEvent({
    required this.type,
    required this.label,
    required this.detail,
    required this.time,
    required this.actorType,
    required this.color,
    required this.icon,
  });

  final String type;
  final String label;
  final String? detail;
  final DateTime? time;
  final String actorType;
  final Color color;
  final IconData icon;
}

class _KpiData {
  const _KpiData(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _ActionItem {
  const _ActionItem({
    required this.label,
    required this.icon,
    required this.color,
    this.enabled = true,
    this.badge = 0,
    this.disabledHint,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool enabled;
  final int badge;
  /// Shown as a snackbar when the chip is tapped while disabled.
  final String? disabledHint;
  final VoidCallback onTap;
}