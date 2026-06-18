import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/ui_mode.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/providers/ui_mode_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import 'agent_home_simple_screen.dart';
import '../../../shared/layouts/responsive_layout.dart';

class AgentHomeScreen extends ConsumerStatefulWidget {
  const AgentHomeScreen({super.key});

  @override
  ConsumerState<AgentHomeScreen> createState() => _S();
}

class _S extends ConsumerState<AgentHomeScreen> {
  final _c = Supabase.instance.client;
  Map<String, dynamic>? _dash;
  List<Map<String, dynamic>> _activeBatches = [];
  bool _loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ── Data load ────────────────────────────────────────────────────────────
  Future<void> _load() async {
    final user = ref.read(appUserProvider).valueOrNull;
    if (user?.agentId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted) setState(() => _loading = true);

    Map<String, dynamic>? dash;
    try {
      final res = await _c
          .rpc('get_agent_dashboard', params: {'p_agent_id': user!.agentId});
      dash = res as Map<String, dynamic>?;
    } catch (_) {}

    List<Map<String, dynamic>> batches = [];
    try {
      final raw = await _c
          .from('delivery_batches')
          .select(
          'id,status,vehicle_no,deliveries(id,status,orders(estimated_birds,total_quantity,retailers(shop_name,address,phone)))')
          .eq('delivery_agent_id', user!.agentId!)
          .order('created_at', ascending: false)
          .limit(10);
      batches = (raw as List).cast<Map<String, dynamic>>().where((b) {
        final s = b['status'] as String? ?? '';
        return s != 'completed' && s != 'cancelled';
      }).toList();
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _dash = dash;
      _activeBatches = batches;
      _loading = false;
    });
  }

  // ── Data accessors ───────────────────────────────────────────────────────
  Map<String, dynamic>? get _shift =>
      (_dash?['shift'] as Map?)?.cast<String, dynamic>();

  Map<String, dynamic>? get _required =>
      (_dash?['required'] as Map?)?.cast<String, dynamic>();

  Map<String, dynamic>? get _stock =>
      (_dash?['stock'] as Map?)?.cast<String, dynamic>();

  Map<String, dynamic>? get _dcToday =>
      (_dash?['dc_today'] as Map?)?.cast<String, dynamic>();

  Map<String, dynamic>? get _today =>
      (_dash?['today'] as Map?)?.cast<String, dynamic>();

  List get _pendingList => (_dash?['pending_list'] as List? ?? []);

  List get _otherAgents => (_dash?['other_agents'] as List? ?? []);

  bool get _hasShift => _shift != null;

  int get _reqBirds => (_required?['total_birds'] as num?)?.toInt() ?? 0;

  double get _reqWeight =>
      (_required?['total_weight'] as num?)?.toDouble() ?? 0;

  int get _orderCount => (_required?['order_count'] as num?)?.toInt() ?? 0;

  int get _ofdBirds =>
      (_required?['out_for_delivery_birds'] as num?)?.toInt() ?? 0;

  int get _asnBirds => (_required?['assigned_birds'] as num?)?.toInt() ?? 0;

  int get _availBirds => (_stock?['available_birds'] as num?)?.toInt() ?? 0;

  double get _availKg => (_stock?['available_kg'] as num?)?.toDouble() ?? 0;

  int get _shortBirds => (_reqBirds - _availBirds).clamp(0, 999999);

  double get _shortKg => (_reqWeight - _availKg).clamp(0.0, 999999.0);

  bool get _hasShortage => _reqBirds > 0 && _availBirds < _reqBirds;

  double get _coverPct => _reqBirds > 0
      ? (_availBirds / _reqBirds).clamp(0.0, 1.0)
      : (_reqBirds == 0 ? 1.0 : 0.0);

  // ── Reassign: pick delivery then pick agent ───────────────────────────────
  Future<void> _pickAndReassign() async {
    if (_pendingList.isEmpty) {
      showError(context, 'No pending deliveries to reassign.');
      return;
    }
    // Step 1: pick which delivery
    final delivery = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 16),
              const Text('Select Delivery',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              ..._pendingList.map((d) {
                final dm = (d as Map).cast<String, dynamic>();
                return ListTile(
                    leading: Icon(_dIcon(dm['status'] as String? ?? ''),
                        color: _dColor(dm['status'] as String? ?? '')),
                    title: Text(dm['shop_name'] as String? ?? '--',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${dm['estimated_birds'] ?? 0} birds  '
                        '${(dm['total_quantity'] as num?)?.toStringAsFixed(1) ?? '0'} kg'),
                    trailing: const Icon(Icons.chevron_right, size: 16),
                    onTap: () => Navigator.pop(ctx, dm));
              }),
              const SizedBox(height: 12),
            ])));
    if (delivery == null || !mounted) return;
    // Step 2: pick which agent
    _doReassign(delivery);
  }

  Future<void> _doReassign(Map<String, dynamic> delivery) async {
    if (_otherAgents.isEmpty) {
      showError(context,
          'No other active agents available. Ask admin to add agents.');
      return;
    }
    Map<String, dynamic>? selected;
    await showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 16),
              const Text('Reassign To',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              Text('Shop: ${delivery['shop_name'] ?? '--'}',
                  style: const TextStyle(fontSize: 12, color: kTextSub)),
              const SizedBox(height: 8),
              ..._otherAgents.map((a) {
                final am = (a as Map).cast<String, dynamic>();
                final ok = am['has_shift'] == true;
                return ListTile(
                    leading: CircleAvatar(
                        backgroundColor: ok
                            ? kNavy.withValues(alpha: 0.1)
                            : Colors.grey.shade200,
                        child: Text(
                            ((am['name'] as String?) ?? '?').isNotEmpty
                                ? (am['name'] as String)[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: ok ? kNavy : Colors.grey))),
                    title: Text(am['name'] as String? ?? '--',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(ok ? 'Shift open' : 'No active shift',
                        style: TextStyle(
                            fontSize: 11,
                            color: ok ? Colors.green : Colors.orange)),
                    trailing: ok
                        ? const Icon(Icons.chevron_right_rounded, color: kNavy)
                        : null,
                    onTap: ok
                        ? () {
                      selected = am;
                      Navigator.pop(ctx);
                    }
                        : null);
              }),
              const SizedBox(height: 12),
            ])));
    if (selected == null || !mounted) return;

    final ok = await confirmDialog(context,
        title: 'Confirm Reassign',
        message: 'Reassign "${delivery['shop_name']}" to ${selected!['name']}?',
        confirmText: 'Reassign',
        confirmColor: kPrimary);
    if (!ok || !mounted) return;
    try {
      // M4 FIX: Also update delivery_shift_id to the new agent's open shift.
      // Without this, the delivery stays linked to the old agent's shift in
      // shift_detail_screen and get_shift_summary, causing phantom entries.
      String? newShiftId;
      try {
        final newShift = await _c
            .from('delivery_shifts')
            .select('id')
            .eq('delivery_agent_id', selected!['id'] as String)
            .eq('status', 'open')
            .maybeSingle()
            .timeout(const Duration(seconds: 8));
        newShiftId = newShift?['id'] as String?;
      } catch (_) {
        // Non-fatal — reassign still proceeds, shift linkage just won't update
      }

      final updateData = <String, dynamic>{
        'delivery_agent_id': selected!['id']
      };
      if (newShiftId != null) updateData['delivery_shift_id'] = newShiftId;

      await _c
          .from('deliveries')
          .update(updateData)
          .eq('id', delivery['id'] as String);

      if (mounted) {
        final note = newShiftId != null
            ? 'Reassigned to ${selected!['name']} ✓ (linked to their active shift)'
            : 'Reassigned to ${selected!['name']} ✓ (no active shift found — link manually if needed)';
        showSuccess(context, note);
        _load();
      }
    } catch (e) {
      if (mounted)
        showError(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SIMPLE MODE DASHBOARD — delegates to SimpleDashboard widget
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildSimpleDashboard() {
    // DEBUG: wrap in a Container to verify the build method runs
    debugPrint(
        '[AgentHomeScreen] Building SimpleDashboard — hasShift=$_hasShift pending=${_pendingList.length} batches=${_activeBatches.length}');
    return SimpleDashboard(
      hasShift: _hasShift,
      today: _today,
      reqBirds: _reqBirds,
      reqWeight: _reqWeight,
      orderCount: _orderCount,
      availBirds: _availBirds,
      availKg: _availKg,
      hasShortage: _hasShortage,
      shortBirds: _shortBirds,
      shortKg: _shortKg,
      pendingList: _pendingList,
      activeBatches: _activeBatches,
      onRefresh: _load,
      onGoToShiftOpen: () => context.go(R.shiftOpen),
      onGoToShiftClose: () => context.go(R.shiftClose),
      onGoToPendingOrder: () => context.go(R.pendingOrder),
      onGoToMyOrders: () => context.push(R.agentMyOrders),
      onGoToInstantOrder: () => context.push(R.instantOrder),
      onGoToExpenses: () => context.go(R.agentExpenses),
      onGoToBatchPickup: () {
        if (_activeBatches.isNotEmpty) {
          context.push(R.batchPickupPath(_activeBatches.first['id'] as String));
        } else {
          showError(context, 'No active batch. Ask admin to create one.');
        }
      },
      onGoToDeliveries: () => context.go(R.agentDeliveries),
      onGoToTransfers: () {
        if (_activeBatches.isNotEmpty) {
          context
              .push(R.birdTransferPath(_activeBatches.first['id'] as String));
        } else {
          context.push(R.transferHistory);
        }
      },
      onGoToDeliveryComplete: () {
        final firstOfd = _pendingList
            .whereType<Map<String, dynamic>>()
            .where((d) => d['status'] == 'out_for_delivery')
            .firstOrNull;
        if (firstOfd != null) {
          context.push(R.deliveryDonePath(firstOfd['id'] as String));
        } else {
          context.go(R.agentDeliveries);
        }
      },
      onGoToDcView: () {
        if (_activeBatches.isNotEmpty) {
          context.push(R.dcViewPath(_activeBatches.first['id'] as String));
        } else {
          showError(context, 'No active batch.');
        }
      },
      onGoToAllDeliveries: () => context.go(R.agentDeliveries),
      onDeliveryCompleteItem: (deliveryId) =>
          context.push(R.deliveryDonePath(deliveryId)),
      onTransferItem: (batchId) => context.push(R.birdTransferPath(batchId)),
      onReassignItem: (delivery) => _doReassign(delivery),
    );
  }

  // ── Profile / Settings Bottom Sheet ────────────────────────────────────
  void _showProfileSheet() {
    final user = ref.read(appUserProvider).valueOrNull;
    final mode = ref.read(uiModeProvider);
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Drag handle
            Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),

            // ── Avatar + Name ────────────────────────────────────
            Row(children: [
              Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                      color: kPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14)),
                  child: const Center(
                      child: Text('🛵', style: TextStyle(fontSize: 22)))),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user?.companyName ?? 'Delivery Agent',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                      Text('Agent',
                          style: const TextStyle(fontSize: 12, color: kTextHint)),
                    ],
                  )),
            ]),
            const SizedBox(height: 24),

            // ── UI Mode Toggle ───────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: kBgGrey, borderRadius: BorderRadius.circular(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.palette_outlined,
                        size: 16, color: kTextSub),
                    const SizedBox(width: 8),
                    const Text('UI Mode',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text(mode.label,
                        style: const TextStyle(
                            fontSize: 11,
                            color: kPrimary,
                            fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 10),
                  SegmentedButton<UiMode>(
                    segments: const [
                      ButtonSegment(
                          value: UiMode.smart,
                          label: Text('Smart', style: TextStyle(fontSize: 12)),
                          icon: Icon(Icons.dashboard_outlined, size: 16)),
                      ButtonSegment(
                          value: UiMode.simple,
                          label: Text('Simple', style: TextStyle(fontSize: 12)),
                          icon: Icon(Icons.accessible_rounded, size: 16)),
                    ],
                    selected: {mode},
                    onSelectionChanged: (set) {
                      final newMode = set.first;
                      ref.read(uiModeProvider.notifier).setMode(newMode);
                      Navigator.pop(ctx);
                    },
                    showSelectedIcon: false,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    mode.isSimple
                        ? 'Larger text, simpler layout, bigger buttons'
                        : 'Full ERP-style dashboard with detailed KPIs',
                    style: const TextStyle(fontSize: 11, color: kTextHint),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Sign Out ─────────────────────────────────────────
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                final ok = await confirmDialog(context,
                    title: 'Sign Out', message: 'Sign out of Rooster Trader?');
                if (ok == true && mounted) {
                  ref.read(appUserProvider.notifier).signOut();
                }
              },
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Sign Out',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: kError,
                side: const BorderSide(color: kError),
                minimumSize: const Size(double.infinity, 44),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────
  Widget _buildScaffold(BuildContext context) {
    final user = ref.watch(appUserProvider).valueOrNull;
    if (!_loading && user?.agentId == null) {
      return Scaffold(
          appBar: AppBar(title: const Text('Delivery App')),
          body: Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.link_off, size: 64, color: kTextHint),
                    const SizedBox(height: 16),
                    const Text('Account Not Linked',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    const Text(
                        'Ask admin to add you in Agents, then link your account.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13, color: kTextSub, height: 1.5)),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                        onPressed: () => context.go(R.agentLink),
                        icon: const Icon(Icons.link),
                        label: const Text('Link Agent Account')),
                  ]))));
    }

    return Scaffold(
        backgroundColor: kBgPage,
        extendBodyBehindAppBar: ref.watch(uiModeProvider).isSimple,
        appBar: ref.watch(uiModeProvider).isSimple
        // Simple mode: minimal transparent AppBar — refresh, my orders, profile
            ? AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            actions: [
              if (!_loading)
                Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Center(
                        child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color:
                                _hasShift ? Colors.green : Colors.red,
                                shape: BoxShape.circle)))),
              IconButton(
                  icon: const Icon(Icons.refresh_rounded,
                      color: Colors.white70),
                  onPressed: _load),
              IconButton(
                  icon: const Icon(Icons.receipt_long_outlined,
                      color: Colors.white70, size: 22),
                  tooltip: 'My Orders',
                  onPressed: () => context.push(R.agentMyOrders)),
              IconButton(
                  icon: const Icon(Icons.account_circle_outlined,
                      color: Colors.white70, size: 22),
                  onPressed: _showProfileSheet),
            ])
            : AppBar(
            backgroundColor: kSurface,
            title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Delivery Dashboard',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800)),
                  Text(user?.companyName ?? 'Agent',
                      style: const TextStyle(
                          fontSize: 11,
                          color: kTextHint,
                          fontWeight: FontWeight.w400)),
                ]),
            actions: [
              if (!_loading)
                Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Center(
                        child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color:
                                _hasShift ? Colors.green : Colors.red,
                                shape: BoxShape.circle)))),
              IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _load),
              IconButton(
                  icon: const Icon(Icons.receipt_long_outlined, size: 22),
                  tooltip: 'My Orders',
                  onPressed: () => context.push(R.agentMyOrders)),
              IconButton(
                  icon:
                  const Icon(Icons.account_circle_outlined, size: 22),
                  onPressed: _showProfileSheet),
            ]),
        body: _loading
            ? const LoadingList()
            : ref.watch(uiModeProvider).isSimple
            ? _buildSimpleDashboard()
            : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 80),
                children: [
                  _buildShiftCard(),
                  const SizedBox(height: 12),
                  _buildStockPanel(),
                  const SizedBox(height: 12),
                  _buildQuickActions(),
                  const SizedBox(height: 14),
                  if (_today != null) ...[
                    _buildTodayStats(),
                    const SizedBox(height: 12)
                  ],
                  if (_pendingList.isNotEmpty) ...[
                    _buildPendingList(),
                    const SizedBox(height: 4)
                  ],
                  if (_activeBatches.isNotEmpty) ...[
                    const SectionHeader('ACTIVE BATCHES'),
                    ..._activeBatches.map(_buildBatchCard),
                  ] else if (_pendingList.isEmpty) ...[
                    const SectionHeader('BATCHES'),
                    Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                            color: kSurface,
                            borderRadius:
                            BorderRadius.circular(kRadiusCard),
                            border: Border.all(color: kBorderLight),
                            boxShadow: kCardShadow),
                        child: const Column(children: [
                          Icon(Icons.inbox_outlined,
                              size: 40, color: kTextHint),
                          SizedBox(height: 8),
                          Text('No active batches',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: kTextSub)),
                          Text('Waiting for admin to assign a batch',
                              style: TextStyle(
                                  fontSize: 13, color: kTextHint)),
                        ])),
                  ],
                  const SizedBox(height: 20),
                ])));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SECTION 1: SHIFT CARD
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildShiftCard() => Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: _hasShift ? const Color(0xFF1A7A3C) : const Color(0xFF374151),
          borderRadius: BorderRadius.circular(kRadiusHero),
          boxShadow: [
            BoxShadow(
                color: (_hasShift
                    ? const Color(0xFF1A7A3C)
                    : const Color(0xFF374151))
                    .withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 6))
          ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: _hasShift
                      ? const Color(0xFF90EE90)
                      : Colors.grey.shade400,
                  shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(_hasShift ? 'SHIFT ACTIVE' : 'NO ACTIVE SHIFT',
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2)),
          const Spacer(),
          if (!_hasShift)
            ElevatedButton(
                onPressed: () => context.go(R.shiftOpen),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: kPrimary,
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 14)),
                child: const Text('Open Shift',
                    style:
                    TextStyle(fontSize: 12, fontWeight: FontWeight.w700)))
          else
            OutlinedButton(
                onPressed: () => context.go(R.shiftClose),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white54),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 14)),
                child:
                const Text('Close Shift', style: TextStyle(fontSize: 12))),
        ]),
        // Pre-shift order entry — only reachable before a shift is open.
        // Once the shift opens, this disappears; use Instant Order instead.
        if (!_hasShift) ...[
          const SizedBox(height: 10),
          SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                  onPressed: () => context.go(R.pendingOrder),
                  icon: const Icon(Icons.pending_actions_outlined,
                      size: 16, color: Colors.white),
                  label: const Text('Create Order (Pending Approval)',
                      style: TextStyle(fontSize: 12, color: Colors.white)),
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white54),
                      minimumSize: const Size(0, 38)))),
        ],
        const SizedBox(height: 14),
        Row(children: [
          _shiftKpi(
              'Done',
              '${(_today?['delivered_count'] as num?)?.toInt() ?? 0}',
              const Color(0xFFB3E5FC)),
          _shiftKpi(
              'Cash',
              Fmt.amount((_today?['cash_collected'] as num?)?.toDouble() ?? 0),
              const Color(0xFFA5D6A7)),
          _shiftKpi(
              'Pending',
              '$_orderCount',
              _orderCount > 0
                  ? const Color(0xFFFFCC80)
                  : const Color(0xFFB3E5FC)),
          _shiftKpi(
              'Mortality',
              '${(_today?['mortality_birds'] as num?)?.toInt() ?? 0}',
              const Color(0xFFEF9A9A)),
        ]),
      ]));

  // ══════════════════════════════════════════════════════════════════════════
  // SECTION 2: STOCK vs REQUIREMENT PANEL
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildStockPanel() {
    final hasData = _reqBirds > 0 || _availBirds > 0;
    final Color borderClr = _hasShortage
        ? Colors.red.shade300
        : hasData
        ? Colors.green.shade300
        : kBorder;
    final Color headerBg = _hasShortage
        ? Colors.red.shade50
        : !hasData
        ? Colors.grey.shade50
        : Colors.green.shade50;
    final Color headerClr = _hasShortage
        ? Colors.red.shade700
        : !hasData
        ? kTextSub
        : Colors.green.shade700;
    final String headerTxt = _hasShortage
        ? 'Shortage: $_shortBirds birds  ${_shortKg.toStringAsFixed(1)} kg short'
        : !hasData
        ? 'Stock & Requirements'
        : _reqBirds == 0
        ? 'No pending orders'
        : 'Stock sufficient for all orders';
    final IconData headerIcon = _hasShortage
        ? Icons.warning_amber_rounded
        : !hasData
        ? Icons.inventory_2_outlined
        : Icons.check_circle_outline;

    return Container(
        decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(kRadiusCard),
            border: Border.all(
                color: borderClr, width: hasData || _hasShortage ? 1.5 : 1),
            boxShadow: kCardShadow),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Header bar ───────────────────────────────────────────
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                  color: headerBg,
                  borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14))),
              child: Row(children: [
                Icon(headerIcon, color: headerClr, size: 18),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(headerTxt,
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: headerClr))),
              ])),

          Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Coverage progress bar ─────────────────────────────
                    if (_reqBirds > 0) ...[
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Stock Coverage',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: kTextSub,
                                    fontWeight: FontWeight.w600)),
                            Text('${(_coverPct * 100).toStringAsFixed(0)}%',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: _coverPct >= 1.0
                                        ? Colors.green
                                        : _coverPct >= 0.7
                                        ? Colors.orange
                                        : Colors.red)),
                          ]),
                      const SizedBox(height: 6),
                      ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                              value: _coverPct,
                              minHeight: 10,
                              backgroundColor: Colors.red.shade100,
                              valueColor:
                              AlwaysStoppedAnimation(_coverPct >= 1.0
                                  ? Colors.green
                                  : _coverPct >= 0.7
                                  ? Colors.orange
                                  : Colors.red))),
                      const SizedBox(height: 16),
                    ],

                    // ── 3-column comparison: Required | Available | Shortage ─
                    Row(children: [
                      _stockCol('Required', _reqBirds, _reqWeight, Colors.blue),
                      _divider(),
                      _stockCol('In Stock', _availBirds, _availKg,
                          _hasShortage ? Colors.red : Colors.green),
                      if (_hasShortage) ...[
                        _divider(),
                        _stockCol('Short', _shortBirds, _shortKg, Colors.red)
                      ],
                    ]),

                    // ── Status breakdown: OFD vs Assigned ────────────────
                    if (_reqBirds > 0) ...[
                      const SizedBox(height: 12),
                      Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius:
                              BorderRadius.circular(kRadiusInner)),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _statusRow(
                                    Icons.local_shipping_outlined,
                                    Colors.blue,
                                    'Out for delivery',
                                    '$_ofdBirds birds'),
                                const SizedBox(height: 6),
                                _statusRow(
                                    Icons.pending_outlined,
                                    Colors.orange,
                                    'Assigned / Picked up',
                                    '$_asnBirds birds'),
                              ])),
                    ],

                    // ── DC Today ─────────────────────────────────────────
                    if (((_dcToday?['dc_count'] as num?)?.toInt() ?? 0) >
                        0) ...[
                      const SizedBox(height: 10),
                      Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: kPrimary.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(10)),
                          child: Row(children: [
                            const Icon(Icons.receipt_long_outlined,
                                size: 14, color: kPrimary),
                            const SizedBox(width: 6),
                            Expanded(
                                child: Text(
                                    'Today DC: ${(_dcToday!['dc_count'] as num?)?.toInt() ?? 0} pickup(s)  '
                                        '${(_dcToday!['total_birds'] as num?)?.toInt() ?? 0} birds  '
                                        '${(_dcToday!['total_kg'] as num?)?.toDouble().toStringAsFixed(1) ?? '0'} kg',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: kPrimary,
                                        fontWeight: FontWeight.w600))),
                          ])),
                    ],

                    // ── Shortage action buttons ───────────────────────────
                    if (_hasShortage) ...[
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                            child: ElevatedButton.icon(
                                onPressed: () {
                                  if (_activeBatches.isNotEmpty) {
                                    context.push(R.batchPickupPath(
                                        _activeBatches.first['id'] as String));
                                  } else {
                                    showError(context,
                                        'No active batch. Ask admin to create one.');
                                  }
                                },
                                icon: const Icon(Icons.agriculture, size: 16),
                                label: const Text('Farm Pickup',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700)),
                                style: ElevatedButton.styleFrom(
                                    minimumSize: const Size(0, 40),
                                    backgroundColor: Colors.red))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: OutlinedButton.icon(
                                onPressed: () {
                                  if (_activeBatches.isNotEmpty) {
                                    context.push(R.birdTransferPath(
                                        _activeBatches.first['id'] as String));
                                  } else {
                                    showError(context,
                                        'No active batch for transfer.');
                                  }
                                },
                                icon: const Icon(Icons.swap_horiz,
                                    size: 16, color: Colors.purple),
                                label: const Text('Request Stock',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.purple)),
                                style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 40),
                                    side: const BorderSide(
                                        color: Colors.purple)))),
                      ]),
                    ],
                  ])),
        ]));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SECTION 3: QUICK ACTIONS
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildQuickActions() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader('QUICK ACTIONS'),
        // Row 1: primary
        Row(children: [
          _qaBtn(Icons.electric_bolt, 'Instant\nOrder', Colors.deepOrange,
                  () => context.push(R.instantOrder),
              highlight: true),
          const SizedBox(width: 8),
          _qaBtn(Icons.agriculture_outlined, 'Farm\nPickup', Colors.green, () {
            if (_activeBatches.isNotEmpty) {
              context.push(
                  R.batchPickupPath(_activeBatches.first['id'] as String));
            } else {
              showError(context, 'No active batch. Ask admin.');
            }
          }),
          const SizedBox(width: 8),
          _qaBtn(Icons.local_shipping_outlined, 'All\nDeliveries', Colors.blue,
                  () => context.go(R.agentDeliveries)),
          const SizedBox(width: 8),
          _qaBtn(Icons.swap_horiz, 'Transfer\nBirds', Colors.purple, () {
            if (_activeBatches.isNotEmpty) {
              context.push(
                  R.birdTransferPath(_activeBatches.first['id'] as String));
            } else {
              context.push(R.transferHistory);
            }
          }),
        ]),
        const SizedBox(height: 8),
        // Row 2: secondary
        Row(children: [
          _qaBtn(Icons.person_pin_circle_outlined, 'Reassign\nOrder',
              Colors.brown, () => _pickAndReassign()),
          const SizedBox(width: 8),
          _qaBtn(Icons.receipt_long_outlined, 'View\nDCs', Colors.teal, () {
            if (_activeBatches.isNotEmpty) {
              context.push(R.dcViewPath(_activeBatches.first['id'] as String));
            } else {
              showError(context, 'No active batch.');
            }
          }),
          const SizedBox(width: 8),
          _qaBtn(Icons.money_outlined, 'Expenses', Colors.orange,
                  () => context.go(R.agentExpenses)),
          const SizedBox(width: 8),
          _qaBtn(Icons.schedule_outlined, 'Shift', kPrimary,
                  () => context.go(_hasShift ? R.shiftClose : R.shiftOpen)),
        ]),
        const SizedBox(height: 8),
        // Row 3: my orders (pre-shift orders this agent created, across
        // their full lifecycle — always reachable, regardless of shift state)
        GestureDetector(
          onTap: () => context.push(R.agentMyOrders),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            decoration: BoxDecoration(
                color: Colors.indigo.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(kRadiusCard),
                border: Border.all(color: Colors.indigo.withValues(alpha: 0.18)),
                boxShadow: kCardShadow),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(kRadiusChip),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.indigo.withValues(alpha: 0.2),
                        blurRadius: 6,
                        offset: const Offset(0, 2))
                  ],
                ),
                child: const Icon(Icons.assignment_outlined,
                    size: 18, color: Colors.indigo),
              ),
              const SizedBox(width: 12),
              const Expanded(
                  child: Text('My Orders',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.indigo))),
              const Icon(Icons.chevron_right, size: 18, color: Colors.indigo),
            ]),
          ),
        ),
      ]);

  // ══════════════════════════════════════════════════════════════════════════
  // SECTION 4: TODAY'S PERFORMANCE
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildTodayStats() {
    final t = _today!;
    final weight = (t['delivered_weight'] as num?)?.toDouble() ?? 0;
    final loss = (t['total_loss_kg'] as num?)?.toDouble() ?? 0;
    final lossPct = (weight + loss) > 0 ? (loss / (weight + loss) * 100) : 0.0;
    return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(kRadiusCard),
            border: Border.all(color: kBorderLight),
            boxShadow: kCardShadow),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("TODAY'S PERFORMANCE",
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: kTextHint,
                  letterSpacing: 0.8)),
          const SizedBox(height: 10),
          Row(children: [
            _todayStat(
                'Delivered',
                '${(t['delivered_birds'] as num?)?.toInt() ?? 0} birds',
                kPrimary),
            _todayStat(
                'Weight', '${weight.toStringAsFixed(1)} kg', Colors.teal),
            _todayStat(
                'Cash',
                Fmt.amount((t['cash_collected'] as num?)?.toDouble() ?? 0),
                Colors.green),
            _todayStat('Loss', '${lossPct.toStringAsFixed(1)}%',
                lossPct >= 2 ? Colors.red : kTextSub),
          ]),
        ]));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SECTION 5: PENDING DELIVERIES — per-row action buttons
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildPendingList() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const SectionHeader('PENDING DELIVERIES'),
          if (_pendingList.length > 3)
            TextButton(
                onPressed: () => context.go(R.agentDeliveries),
                child: Text('All ${_pendingList.length}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700))),
        ]),
        ..._pendingList.map((raw) {
          final d = (raw as Map).cast<String, dynamic>();
          final birds = (d['estimated_birds'] as num?)?.toInt() ?? 0;
          final wt = (d['total_quantity'] as num?)?.toDouble() ?? 0;
          final st = d['status'] as String? ?? '';
          final isOfd = st == 'out_for_delivery';
          final bid = d['batch_id'] as String?;

          return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(
                      color: isOfd
                          ? const Color(0xFF1B6CA8).withValues(alpha: 0.4)
                          : kBorderLight,
                      width: isOfd ? 1.5 : 0.8),
                  boxShadow: kCardShadow),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Shop name + status badge
                    Row(children: [
                      Icon(_dIcon(st), size: 16, color: _dColor(st)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(d['shop_name'] as String? ?? '--',
                                    style: const TextStyle(
                                        fontSize: 13, fontWeight: FontWeight.w700)),
                                if ((d['address'] as String?)?.isNotEmpty == true)
                                  Text(d['address'] as String,
                                      style: const TextStyle(
                                          fontSize: 10, color: kTextHint),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                              ])),
                      StatusBadge(st, SC.order(st), small: true),
                    ]),
                    const SizedBox(height: 8),

                    // Info chips
                    Row(children: [
                      _chip(Icons.numbers, '$birds birds', Colors.blue),
                      const SizedBox(width: 6),
                      _chip(Icons.scale_outlined, '${wt.toStringAsFixed(1)} kg',
                          Colors.teal),
                    ]),
                    const SizedBox(height: 10),

                    // Action buttons — 2-row layout when all 3 are present to prevent label wrapping
                    if (isOfd && bid != null) ...[
                      // Row 1: primary action full-width
                      SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                              onPressed: () => context
                                  .push(R.deliveryDonePath(d['id'] as String)),
                              icon: const Icon(Icons.check_circle_outline,
                                  size: 16),
                              label: const Text('Mark Delivered',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700)),
                              style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(0, 42),
                                  backgroundColor: kPrimary))),
                      const SizedBox(height: 6),
                      // Row 2: Transfer + Reassign split
                      Row(children: [
                        Expanded(
                            child: OutlinedButton.icon(
                                onPressed: () =>
                                    context.push(R.birdTransferPath(bid)),
                                icon: const Icon(Icons.swap_horiz,
                                    size: 14, color: Colors.purple),
                                label: const Text('Transfer',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.purple)),
                                style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 38),
                                    side: const BorderSide(
                                        color: Colors.purple)))),
                        const SizedBox(width: 6),
                        Expanded(
                            child: OutlinedButton.icon(
                                onPressed: () => _doReassign(d),
                                icon: const Icon(
                                    Icons.person_pin_circle_outlined,
                                    size: 14,
                                    color: Colors.brown),
                                label: const Text('Reassign',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.brown)),
                                style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 38),
                                    side: const BorderSide(
                                        color: Colors.brown)))),
                      ]),
                    ] else
                      Row(children: [
                        if (isOfd) ...[
                          Expanded(
                              child: ElevatedButton.icon(
                                  onPressed: () => context.push(
                                      R.deliveryDonePath(d['id'] as String)),
                                  icon: const Icon(Icons.check_circle_outline,
                                      size: 14),
                                  label: const Text('Mark Delivered',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700)),
                                  style: ElevatedButton.styleFrom(
                                      minimumSize: const Size(0, 36),
                                      backgroundColor: kPrimary))),
                          const SizedBox(width: 6),
                        ],
                        if (bid != null) ...[
                          Expanded(
                              child: OutlinedButton.icon(
                                  onPressed: () =>
                                      context.push(R.birdTransferPath(bid)),
                                  icon: const Icon(Icons.swap_horiz,
                                      size: 14, color: Colors.purple),
                                  label: const Text('Transfer',
                                      style: TextStyle(
                                          fontSize: 11, color: Colors.purple)),
                                  style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(0, 36),
                                      side: const BorderSide(
                                          color: Colors.purple)))),
                          const SizedBox(width: 6),
                        ],
                        OutlinedButton.icon(
                            onPressed: () => _doReassign(d),
                            icon: const Icon(Icons.person_pin_circle_outlined,
                                size: 14, color: Colors.brown),
                            label: const Text('Reassign',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.brown)),
                            style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 36),
                                side: const BorderSide(color: Colors.brown))),
                      ]),
                  ]));
        }).toList(),
      ]);

  // ══════════════════════════════════════════════════════════════════════════
  // SECTION 6: ACTIVE BATCH CARDS
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildBatchCard(Map<String, dynamic> b) {
    final deliveries =
    (b['deliveries'] as List? ?? []).cast<Map<String, dynamic>>();
    final status = b['status'] as String? ?? 'assigned';
    final active = deliveries.where((d) => d['status'] != 'cancelled').toList();
    final done = active.where((d) => d['status'] == 'delivered').length;
    final total = active.length;
    final reqBirds = active.fold(
        0,
            (s, d) =>
        s +
            (((d['orders'] as Map?)?['estimated_birds'] as num?)?.toInt() ??
                0));
    final reqWt = active.fold(
        0.0,
            (s, d) =>
        s +
            (((d['orders'] as Map?)?['total_quantity'] as num?)?.toDouble() ??
                0));
    final pending = active
        .where((d) => !['delivered', 'cancelled'].contains(d['status']))
        .toList();
    final remBirds = pending.fold(
        0,
            (s, d) =>
        s +
            (((d['orders'] as Map?)?['estimated_birds'] as num?)?.toInt() ??
                0));
    final remWt = pending.fold(
        0.0,
            (s, d) =>
        s +
            (((d['orders'] as Map?)?['total_quantity'] as num?)?.toDouble() ??
                0));

    return Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
            color: const Color(0xFF1B2B4B),
            borderRadius: BorderRadius.circular(kRadiusCard),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFF1B2B4B).withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 5))
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Batch header
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(kRadiusCard))),
              child: Row(children: [
                StatusBadge(status, SC.order(status)),
                const SizedBox(width: 8),
                if (b['vehicle_no'] != null)
                  Text('${b['vehicle_no']}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: Colors.white)),
                const Spacer(),
                Text('$done / $total done',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: kTextSub)),
              ])),

          // Progress bar
          ClipRRect(
              child: LinearProgressIndicator(
                  value: total > 0 ? done / total : 0,
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  color: const Color(0xFF86EFAC),
                  minHeight: 6)),

          Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Summary KPIs — glass background so white text is readable on dark card
                    Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12))),
                        child: Row(children: [
                          _batchKpi(
                              'Total',
                              '$reqBirds b  ${reqWt.toStringAsFixed(0)} kg',
                              Colors.blue),
                          Container(
                              width: 1,
                              height: 30,
                              color: Colors.white.withValues(alpha: 0.2),
                              margin:
                              const EdgeInsets.symmetric(horizontal: 10)),
                          _batchKpi(
                              'Remaining',
                              '$remBirds b  ${remWt.toStringAsFixed(0)} kg',
                              remBirds > 0 ? Colors.orange : Colors.green),
                        ])),

                    // Individual delivery rows
                    ...active.map((d) {
                      final o = d['orders'] as Map<String, dynamic>?;
                      final r = o?['retailers'] as Map<String, dynamic>?;
                      final dSt = d['status'] as String? ?? '';
                      final birds =
                          (o?['estimated_birds'] as num?)?.toInt() ?? 0;
                      final wt =
                          (o?['total_quantity'] as num?)?.toDouble() ?? 0;
                      return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            Icon(_dIcon(dSt), size: 15, color: _dColor(dSt)),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Text(r?['shop_name'] as String? ?? '--',
                                          style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white)),
                                      Text(
                                          '$birds birds  ${wt.toStringAsFixed(1)} kg',
                                          style: const TextStyle(
                                              fontSize: 11, color: Colors.white60)),
                                    ])),
                            StatusBadge(dSt, SC.order(dSt), small: true),
                            if (dSt == 'out_for_delivery') ...[
                              const SizedBox(width: 6),
                              GestureDetector(
                                  onTap: () => context.push(
                                      R.deliveryDonePath(d['id'] as String)),
                                  child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                          color:
                                          kPrimary.withValues(alpha: 0.1),
                                          borderRadius:
                                          BorderRadius.circular(6)),
                                      child: const Text('Complete',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: kPrimary,
                                              fontWeight: FontWeight.w700)))),
                            ],
                          ]));
                    }),

                    const SizedBox(height: 4),
                    // Batch action buttons
                    if (['assigned', 'picked_up', 'out_for_delivery']
                        .contains(status)) ...[
                      Row(children: [
                        Expanded(
                            child: OutlinedButton.icon(
                                onPressed: () => context
                                    .push(R.batchPickupPath(b['id'] as String)),
                                icon: const Icon(Icons.add_circle_outline,
                                    size: 15),
                                label: Text(
                                    status == 'assigned'
                                        ? 'Add DC & Pickup'
                                        : 'Add DC',
                                    style: const TextStyle(fontSize: 11)),
                                style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 36)))),
                        const SizedBox(width: 6),
                        OutlinedButton.icon(
                            onPressed: () =>
                                context.push(R.dcViewPath(b['id'] as String)),
                            icon: const Icon(Icons.receipt_long_outlined,
                                size: 15),
                            label: const Text('DCs',
                                style: TextStyle(fontSize: 11)),
                            style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 36))),
                      ]),
                    ],
                    if (['picked_up', 'out_for_delivery'].contains(status)) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        Expanded(
                            child: OutlinedButton.icon(
                                onPressed: () => context.push(
                                    R.birdTransferPath(b['id'] as String)),
                                icon: const Icon(Icons.swap_horiz,
                                    size: 15, color: Colors.purple),
                                label: const Text('Transfer Birds',
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.purple)),
                                style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 36),
                                    side: const BorderSide(
                                        color: Colors.purple)))),
                        const SizedBox(width: 6),
                        Expanded(
                            child: ElevatedButton.icon(
                                onPressed: () => context.go(R.agentDeliveries),
                                icon: const Icon(Icons.local_shipping_outlined,
                                    size: 15),
                                label: const Text('Deliveries',
                                    style: TextStyle(fontSize: 11)),
                                style: ElevatedButton.styleFrom(
                                    minimumSize: const Size(0, 36)))),
                      ]),
                    ],
                  ])),
        ]));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // WIDGET HELPERS
  // ══════════════════════════════════════════════════════════════════════════
  Widget _shiftKpi(String l, String v, Color c) => Expanded(
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(kRadiusInner),
          ),
          child: Text(v,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w900, color: c),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(height: 4),
        Text(l,
            style: const TextStyle(
                fontSize: 9,
                color: Colors.white60,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4),
            textAlign: TextAlign.center),
      ]));

  Widget _stockCol(String label, int birds, double kg, Color c) => Expanded(
      child: Column(children: [
        Text(label,
            style:
            TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('$birds',
            style:
            TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: c)),
        Text('birds',
            style: TextStyle(fontSize: 9, color: c.withValues(alpha: 0.7))),
        const SizedBox(height: 2),
        Text('${kg.toStringAsFixed(1)} kg',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: c.withValues(alpha: 0.8))),
      ]));

  Widget _divider() => Container(
      width: 1,
      height: 70,
      color: kBorder,
      margin: const EdgeInsets.symmetric(horizontal: 10));

  Widget _statusRow(IconData icon, Color c, String label, String value) =>
      Row(children: [
        Icon(icon, size: 13, color: c),
        const SizedBox(width: 6),
        Text('$label: ',
            style:
            TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600)),
        Text(value,
            style:
            TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w800)),
      ]);

  Widget _todayStat(String l, String v, Color c) => Expanded(
      child: Column(children: [
        Text(v,
            style:
            TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(l,
            style: const TextStyle(fontSize: 9, color: kTextHint),
            textAlign: TextAlign.center),
      ]));

  Widget _batchKpi(String l, String v, Color c) => Expanded(
      child:
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l,
            style: const TextStyle(
                fontSize: 9,
                color: Colors.white60,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5)),
        const SizedBox(height: 2),
        Text(v,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: Colors.white)),
      ]));

  Widget _qaBtn(IconData icon, String label, Color color, VoidCallback onTap,
      {bool highlight = false}) =>
      Expanded(
          child: GestureDetector(
              onTap: onTap,
              child: Container(
                  padding:
                  const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                  decoration: BoxDecoration(
                      color: highlight
                          ? color.withValues(alpha: 0.12)
                          : color.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(kRadiusCard),
                      border: Border.all(
                          color:
                          color.withValues(alpha: highlight ? 0.4 : 0.18),
                          width: highlight ? 1.5 : 0.8),
                      boxShadow: kCardShadow),
                  child: Column(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(kRadiusChip),
                        boxShadow: [
                          BoxShadow(
                              color: color.withValues(alpha: 0.2),
                              blurRadius: 6,
                              offset: const Offset(0, 2))
                        ],
                      ),
                      child: Icon(icon, size: 22, color: color),
                    ),
                    const SizedBox(height: 6),
                    Text(label,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: color),
                        textAlign: TextAlign.center,
                        maxLines: 2),
                  ]))));

  Widget _chip(IconData icon, String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      ]));

  IconData _dIcon(String s) => switch (s) {
    'delivered' => Icons.check_circle_outline,
    'out_for_delivery' => Icons.local_shipping_outlined,
    'picked_up' => Icons.inventory_2_outlined,
    _ => Icons.radio_button_unchecked,
  };

  Color _dColor(String s) => switch (s) {
    'delivered' => Colors.green,
    'out_for_delivery' => Colors.blue,
    'picked_up' => Colors.teal,
    _ => Colors.grey,
  };

  @override
  Widget build(BuildContext context) => ResponsiveLayout(
    mobile: (_) => _buildScaffold(context),
    desktop: (_) => _buildScaffold(context),
  );
}