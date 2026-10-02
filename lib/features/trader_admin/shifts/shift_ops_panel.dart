import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TRADER SHIFT OPERATIONS PANEL
//
// A bottom sheet launched from the Agent Detail screen.
// Allows the trader to perform any shift operation on behalf of an agent.
// All operations call the same RPCs as the agent app, but with:
//   p_actor_type = 'trader'
//   p_actor_id   = trader's auth.uid()
//   p_entry_mode = selected from dropdown
//   p_actual_at  = optional backdated time
//
// Available operations:
//   1. Complete a stuck delivery
//   2. Close shift (with return count)
//   3. Add expense
//   4. Self-update rate KPI display (read-only)
// ─────────────────────────────────────────────────────────────────────────────

/// Launch the panel as a modal bottom sheet from the agent detail screen.
Future<void> showTraderShiftOpsPanel(
    BuildContext context, String agentId, String agentName) async {
  await showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ShiftOpsPanel(
        agentId: agentId, agentName: agentName),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
class _ShiftOpsPanel extends ConsumerStatefulWidget {
  const _ShiftOpsPanel(
      {required this.agentId, required this.agentName});
  final String agentId;
  final String agentName;
  @override
  ConsumerState<_ShiftOpsPanel> createState() => _ShiftOpsPanelState();
}

class _ShiftOpsPanelState extends ConsumerState<_ShiftOpsPanel> {
  final _c = Supabase.instance.client;
  bool _loading = true;

  Map<String, dynamic>? _openShift;
  List<Map<String, dynamic>> _stuckDeliveries = [];
  int _selfUpdateCount = 0;
  int _traderEnteredCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      // Open shift for this agent
      final shiftData = await _c
          .from('delivery_shifts')
          .select(
          'id, status, shift_start_at, opening_bird_count, '
              'total_orders, total_birds_delivered, total_cash_collected, '
              'total_expenses, closing_bird_count')
          .eq('delivery_agent_id', widget.agentId)
          .eq('status', 'open')
          .maybeSingle();

      // Stuck deliveries for this agent (out_for_delivery > 2h)
      List<Map<String, dynamic>> stuck = [];
      final cutoff =
      DateTime.now().subtract(const Duration(hours: 2));
      final delivData = await _c
          .from('deliveries')
          .select(
          'id, status, expected_bird_count, expected_total_weight, '
              'assigned_at, orders(retailers(shop_name))')
          .eq('delivery_agent_id', widget.agentId)
          .eq('status', 'out_for_delivery')
          .lt('assigned_at', cutoff.toIso8601String())
          .order('assigned_at')
          .limit(10);
      stuck = List<Map<String, dynamic>>.from(delivData);

      // Self-update rate from operation_log (last 30 days)
      int selfCount = 0, traderCount = 0;
      try {
        final since = DateTime.now()
            .subtract(const Duration(days: 30))
            .toIso8601String();
        final opData = await _c
            .from('operation_log')
            .select('actor_type')
            .eq('subject_agent_id', widget.agentId)
            .gte('recorded_at', since);
        final ops = List<Map<String, dynamic>>.from(opData);
        selfCount =
            ops.where((o) => o['actor_type'] == 'agent').length;
        traderCount =
            ops.where((o) => o['actor_type'] == 'trader').length;
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _openShift = shiftData;
        _stuckDeliveries = stuck;
        _selfUpdateCount = selfCount;
        _traderEnteredCount = traderCount;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Container(
        decoration: const BoxDecoration(
          color: kBgPage,
          borderRadius:
          BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          // Drag handle
          const SizedBox(height: 10),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: kBorderLight,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Shift Operations',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900)),
                        Text('Acting on behalf of ${widget.agentName}',
                            style: const TextStyle(
                                fontSize: 12, color: kTextHint)),
                      ])),
              IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _load),
            ]),
          ),

          const SizedBox(height: 4),
          const Divider(height: 1),

          Expanded(
            child: _loading
                ? const LoadingList()
                : ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(
                  16, 12, 16, 60),
              children: [
                // ── Self-update rate KPI ──────────────────────
                _SelfUpdateKpi(
                  agentName: widget.agentName,
                  selfCount: _selfUpdateCount,
                  traderCount: _traderEnteredCount,
                ),
                const SizedBox(height: 14),

                // ── Shift status ──────────────────────────────
                _ShiftStatusCard(shift: _openShift),
                const SizedBox(height: 14),

                // ── Stuck deliveries ──────────────────────────
                if (_stuckDeliveries.isNotEmpty) ...[
                  const SectionHeader('STUCK DELIVERIES'),
                  const SizedBox(height: 8),
                  ..._stuckDeliveries.map((d) =>
                      _StuckDeliveryRow(
                        delivery: d,
                        agentId: widget.agentId,
                        onResolved: _load,
                      )),
                  const SizedBox(height: 14),
                ],

                // ── Close shift ───────────────────────────────
                if (_openShift != null) ...[
                  const SectionHeader('SHIFT OPERATIONS'),
                  const SizedBox(height: 8),
                  _CloseShiftTile(
                    shiftId: _openShift!['id'] as String,
                    agentId: widget.agentId,
                    onDone: () {
                      _load();
                      Navigator.of(context,
                          rootNavigator: true)
                          .pop();
                    },
                  ),
                  const SizedBox(height: 8),
                  _AddExpenseTile(
                    shiftId: _openShift!['id'] as String,
                    agentId: widget.agentId,
                    onDone: _load,
                  ),
                ],

                if (_openShift == null &&
                    _stuckDeliveries.isEmpty)
                  const EmptyState(
                    icon: Icons.check_circle_outline,
                    message:
                    'No active shift or stuck deliveries.\nAgent is up to date.',
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Self-Update Rate KPI
// ─────────────────────────────────────────────────────────────────────────────
class _SelfUpdateKpi extends StatelessWidget {
  const _SelfUpdateKpi({
    required this.agentName,
    required this.selfCount,
    required this.traderCount,
  });
  final String agentName;
  final int selfCount;
  final int traderCount;

  @override
  Widget build(BuildContext context) {
    final total = selfCount + traderCount;
    final rate =
    total == 0 ? 1.0 : selfCount / total;
    final pct = (rate * 100).round();
    final color = pct >= 80
        ? Colors.green.shade700
        : pct >= 50
        ? Colors.orange.shade700
        : Colors.red.shade700;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorderLight)),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Text('Self-Update Rate',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6)),
                child: Text('$pct%',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: color)),
              ),
              const Spacer(),
              Text('Last 30 days',
                  style: const TextStyle(
                      fontSize: 10, color: kTextHint)),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                  value: rate,
                  minHeight: 8,
                  backgroundColor: Colors.red.shade100,
                  color: color),
            ),
            const SizedBox(height: 6),
            Row(children: [
              _dot(Colors.green.shade700),
              const SizedBox(width: 4),
              Text('$selfCount self-entered',
                  style:
                  const TextStyle(fontSize: 10, color: kTextSub)),
              const SizedBox(width: 12),
              _dot(Colors.red.shade300),
              const SizedBox(width: 4),
              Text('$traderCount trader-entered',
                  style:
                  const TextStyle(fontSize: 10, color: kTextSub)),
            ]),
          ]),
    );
  }

  Widget _dot(Color c) => Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle));
}

// ─────────────────────────────────────────────────────────────────────────────
// Shift Status Card
// ─────────────────────────────────────────────────────────────────────────────
class _ShiftStatusCard extends StatelessWidget {
  const _ShiftStatusCard({required this.shift});
  final Map<String, dynamic>? shift;

  @override
  Widget build(BuildContext context) {
    if (shift == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kBorderLight)),
        child: const Row(children: [
          Icon(Icons.bedtime_outlined,
              color: kTextHint, size: 18),
          SizedBox(width: 10),
          Text('No active shift',
              style: TextStyle(
                  fontSize: 13, color: kTextHint)),
        ]),
      );
    }
    final startAt = DateTime.tryParse(
        shift!['shift_start_at'] as String? ?? '');
    final duration = startAt != null
        ? DateTime.now().difference(startAt)
        : null;
    final orders =
        (shift!['total_orders'] as num?)?.toInt() ?? 0;
    final cash =
        (shift!['total_cash_collected'] as num?)?.toDouble() ??
            0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: kPrimary.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: kPrimary.withValues(alpha: 0.2))),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.play_circle,
                  color: kPrimary, size: 18),
              const SizedBox(width: 8),
              const Text('Active Shift',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: kPrimary)),
              const Spacer(),
              if (duration != null)
                Text(
                    '${duration.inHours}h ${duration.inMinutes.remainder(60)}m',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: kTextSub)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              _stat('Orders', '$orders'),
              const SizedBox(width: 20),
              _stat('Cash', Fmt.amount(cash)),
              if (startAt != null) ...[
                const SizedBox(width: 20),
                _stat('Started',
                    DateFormat('h:mm a').format(startAt)),
              ],
            ]),
          ]),
    );
  }

  Widget _stat(String l, String v) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(v,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: kTextSub)),
        Text(l,
            style: const TextStyle(
                fontSize: 10, color: kTextHint)),
      ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Stuck delivery row — compact inline resolve
// ─────────────────────────────────────────────────────────────────────────────
class _StuckDeliveryRow extends ConsumerStatefulWidget {
  const _StuckDeliveryRow({
    required this.delivery,
    required this.agentId,
    required this.onResolved,
  });
  final Map<String, dynamic> delivery;
  final String agentId;
  final VoidCallback onResolved;
  @override
  ConsumerState<_StuckDeliveryRow> createState() =>
      _StuckDeliveryRowState();
}

class _StuckDeliveryRowState
    extends ConsumerState<_StuckDeliveryRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.delivery;
    final order = d['orders'] as Map<String, dynamic>? ?? {};
    final retailer =
        order['retailers'] as Map<String, dynamic>? ?? {};
    final shopName =
        retailer['shop_name'] as String? ?? '—';
    final expectedBirds =
        (d['expected_bird_count'] as num?)?.toInt() ?? 0;
    final expectedKg =
        (d['expected_total_weight'] as num?)?.toDouble() ?? 0;
    final assignedAt =
    DateTime.tryParse(d['assigned_at'] as String? ?? '');
    final hoursStuck = assignedAt != null
        ? DateTime.now().difference(assignedAt).inHours
        : 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kBorderLight)),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(shopName,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800)),
                        Text(
                            '$expectedBirds birds · '
                                '${expectedKg.toStringAsFixed(1)} kg · '
                                '${hoursStuck}h ago',
                            style: const TextStyle(
                                fontSize: 10, color: kTextHint)),
                      ])),
              if (!_expanded)
                TextButton(
                  onPressed: () => setState(() => _expanded = true),
                  style: TextButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      foregroundColor: kPrimary),
                  child: const Text('Resolve',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
            ]),
            if (_expanded)
              _MiniResolveForm(
                delivery: widget.delivery,
                agentId: widget.agentId,
                onCancel: () => setState(() => _expanded = false),
                onResolved: () {
                  setState(() => _expanded = false);
                  widget.onResolved();
                },
              ),
          ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mini inline resolve form (used inside the panel for space efficiency)
// ─────────────────────────────────────────────────────────────────────────────
class _MiniResolveForm extends ConsumerStatefulWidget {
  const _MiniResolveForm({
    required this.delivery,
    required this.agentId,
    required this.onCancel,
    required this.onResolved,
  });
  final Map<String, dynamic> delivery;
  final String agentId;
  final VoidCallback onCancel;
  final VoidCallback onResolved;
  @override
  ConsumerState<_MiniResolveForm> createState() =>
      _MiniResolveFormState();
}

class _MiniResolveFormState
    extends ConsumerState<_MiniResolveForm> {
  final _c = Supabase.instance.client;
  late TextEditingController _birdsCtrl;
  late TextEditingController _weightCtrl;
  final _cashCtrl = TextEditingController(text: '0');
  String _mode = 'called';
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _birdsCtrl = TextEditingController(
        text:
        '${(widget.delivery['expected_bird_count'] as num?)?.toInt() ?? 0}');
    _weightCtrl = TextEditingController(
        text:
        '${((widget.delivery['expected_total_weight'] as num?)?.toDouble() ?? 0).toStringAsFixed(1)}');
  }

  @override
  void dispose() {
    _birdsCtrl.dispose();
    _weightCtrl.dispose();
    _cashCtrl.dispose();
    super.dispose();
  }

  // Scenario 1 fix: preserves a blank Bird Count as NULL instead of silently
  // becoming 0, used only for the value persisted via complete_delivery.
  int? get _birdsToRecord => int.tryParse(_birdsCtrl.text.trim());

  Future<void> _submit() async {
    final user = ref.read(appUserProvider).valueOrNull;
    if (user == null) return;
    setState(() => _submitting = true);
    try {
      await _c.rpc('complete_delivery', params: {
        'p_delivery_id': widget.delivery['id'] as String,
        'p_birds_delivered':
        _birdsToRecord,
        'p_delivered_total_weight':
        double.tryParse(_weightCtrl.text.trim()) ?? 0.0,
        'p_collected_amount':
        double.tryParse(_cashCtrl.text.trim()) ?? 0.0,
        'p_actor_type': 'trader',
        'p_actor_id': user.userId,
        'p_entry_mode': _mode,
      });
      if (mounted) {
        showSuccess(context, 'Resolved ✓');
        widget.onResolved();
      }
    } catch (e) {
      if (mounted) {
        showError(context,
            e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(children: [
        // Entry mode chips
        Wrap(
          spacing: 6,
          children: {
            'called': 'Called',
            'whatsapp': 'WhatsApp',
            'present': 'Present',
            'estimated': 'Est.'
          }
              .entries
              .map((e) {
            final sel = _mode == e.key;
            return ChoiceChip(
              label: Text(e.value,
                  style: TextStyle(
                      fontSize: 10,
                      color:
                      sel ? Colors.white : kTextSub,
                      fontWeight: FontWeight.w600)),
              selected: sel,
              onSelected: (_) =>
                  setState(() => _mode = e.key),
              selectedColor: kPrimary,
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 0),
              materialTapTargetSize:
              MaterialTapTargetSize.shrinkWrap,
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: TextField(
                controller: _birdsCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly
                ],
                decoration: const InputDecoration(
                    labelText: 'Birds', isDense: true),
              )),
          const SizedBox(width: 8),
          Expanded(
              child: TextField(
                controller: _weightCtrl,
                keyboardType:
                const TextInputType.numberWithOptions(
                    decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Weight (kg)', isDense: true),
              )),
          const SizedBox(width: 8),
          Expanded(
              child: TextField(
                controller: _cashCtrl,
                keyboardType:
                const TextInputType.numberWithOptions(
                    decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Cash ₹', isDense: true),
              )),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          TextButton(
              onPressed:
              _submitting ? null : widget.onCancel,
              child: const Text('Cancel',
                  style: TextStyle(fontSize: 12))),
          const SizedBox(width: 8),
          Expanded(
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    backgroundColor: kPrimary,
                    foregroundColor: Colors.white),
                child: _submitting
                    ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white))
                    : const Text('Submit',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                        FontWeight.w700)),
              )),
        ]),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Close Shift tile
// ─────────────────────────────────────────────────────────────────────────────
class _CloseShiftTile extends ConsumerStatefulWidget {
  const _CloseShiftTile({
    required this.shiftId,
    required this.agentId,
    required this.onDone,
  });
  final String shiftId;
  final String agentId;
  final VoidCallback onDone;
  @override
  ConsumerState<_CloseShiftTile> createState() =>
      _CloseShiftTileState();
}

class _CloseShiftTileState
    extends ConsumerState<_CloseShiftTile> {
  final _c = Supabase.instance.client;
  bool _expanded = false;
  bool _submitting = false;
  final _birdsCtrl = TextEditingController(text: '0');
  final _weightCtrl = TextEditingController(text: '0');
  final _odoCtrl = TextEditingController();
  String _mode = 'called';

  @override
  void dispose() {
    _birdsCtrl.dispose();
    _weightCtrl.dispose();
    _odoCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = ref.read(appUserProvider).valueOrNull;
    if (user == null) return;
    final ok = await confirmDialog(
        context,
        title: 'Close Shift',
        message:
        'Close this shift on behalf of the agent? '
            'This action will be logged as trader-entered.',
        confirmText: 'Close Shift',
        confirmColor: Colors.orange.shade700);
    if (!ok || !mounted) return;
    setState(() => _submitting = true);
    try {
      await _c.rpc('close_delivery_shift', params: {
        'p_shift_id': widget.shiftId,
        'p_closing_bird_count':
        int.tryParse(_birdsCtrl.text.trim()) ?? 0,
        'p_closing_weight':
        double.tryParse(_weightCtrl.text.trim()) ?? 0.0,
        if (_odoCtrl.text.trim().isNotEmpty)
          'p_odometer_end':
          double.tryParse(_odoCtrl.text.trim()),
        'p_actor_type': 'trader',
        'p_actor_id': user.userId,
        'p_entry_mode': _mode,
      });
      if (mounted) {
        showSuccess(context, 'Shift closed ✓');
        widget.onDone();
      }
    } catch (e) {
      if (mounted) {
        showError(context,
            e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kBorderLight)),
      child: Column(children: [
        ListTile(
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.lock_clock_outlined,
                color: Colors.orange, size: 18),
          ),
          title: const Text('Close Agent Shift',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          subtitle: const Text(
              'Enter return birds and close shift',
              style: TextStyle(fontSize: 11)),
          trailing: Icon(
              _expanded
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_down,
              color: kTextHint),
          onTap: () => setState(() => _expanded = !_expanded),
          dense: true,
        ),
        if (_expanded)
          Padding(
            padding:
            const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(children: [
              // Entry mode
              Wrap(
                spacing: 6,
                children: {
                  'called': 'Called',
                  'whatsapp': 'WhatsApp',
                  'present': 'Present',
                  'estimated': 'Est.'
                }
                    .entries
                    .map((e) {
                  final sel = _mode == e.key;
                  return ChoiceChip(
                    label: Text(e.value,
                        style: TextStyle(
                            fontSize: 10,
                            color: sel
                                ? Colors.white
                                : kTextSub,
                            fontWeight:
                            FontWeight.w600)),
                    selected: sel,
                    onSelected: (_) =>
                        setState(() => _mode = e.key),
                    selectedColor: Colors.orange.shade700,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 0),
                    materialTapTargetSize:
                    MaterialTapTargetSize.shrinkWrap,
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: TextField(
                      controller: _birdsCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      decoration: const InputDecoration(
                          labelText: 'Return Birds',
                          isDense: true),
                    )),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(
                      controller: _weightCtrl,
                      keyboardType:
                      const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Return Kg',
                          isDense: true),
                    )),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(
                      controller: _odoCtrl,
                      keyboardType:
                      const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Odometer',
                          isDense: true),
                    )),
              ]),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                      backgroundColor:
                      Colors.orange.shade700,
                      foregroundColor: Colors.white),
                  child: _submitting
                      ? const SizedBox(
                      width: 16,
                      height: 16,
                      child:
                      CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white))
                      : const Text('Close Shift',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                          FontWeight.w700)),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add Expense tile
// ─────────────────────────────────────────────────────────────────────────────
class _AddExpenseTile extends ConsumerStatefulWidget {
  const _AddExpenseTile({
    required this.shiftId,
    required this.agentId,
    required this.onDone,
  });
  final String shiftId;
  final String agentId;
  final VoidCallback onDone;
  @override
  ConsumerState<_AddExpenseTile> createState() =>
      _AddExpenseTileState();
}

class _AddExpenseTileState
    extends ConsumerState<_AddExpenseTile> {
  final _c = Supabase.instance.client;
  bool _expanded = false;
  bool _submitting = false;
  final _amtCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _expType = 'fuel';

  static const _expTypes = [
    'fuel', 'toll', 'vehicle', 'food', 'other'
  ];

  @override
  void dispose() {
    _amtCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = ref.read(appUserProvider).valueOrNull;
    if (user == null) return;
    final amt = double.tryParse(_amtCtrl.text.trim()) ?? 0;
    if (amt <= 0) {
      showError(context, 'Enter a valid amount');
      return;
    }
    setState(() => _submitting = true);
    try {
      // delivery_expenses now has agent_id + entered_by_actor_type columns
      await _c.from('delivery_expenses').insert({
        'shift_id': widget.shiftId,
        'trader_id': user.traderId,
        'agent_id': widget.agentId,
        'expense_type': _expType,
        'amount': amt,
        'notes': _noteCtrl.text.trim().isEmpty
            ? null
            : _noteCtrl.text.trim(),
        'entered_by_actor_type': 'trader',
        'entered_by_actor_id': user.userId,
      });
      if (mounted) {
        _amtCtrl.clear();
        _noteCtrl.clear();
        showSuccess(context, 'Expense added ✓');
        setState(() => _expanded = false);
        widget.onDone();
      }
    } catch (e) {
      if (mounted) {
        showError(context,
            e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kBorderLight)),
      child: Column(children: [
        ListTile(
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color:
                Colors.teal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.receipt_long_outlined,
                color: Colors.teal, size: 18),
          ),
          title: const Text('Add Expense',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          subtitle: const Text(
              'Fuel, toll, allowance, etc.',
              style: TextStyle(fontSize: 11)),
          trailing: Icon(
              _expanded
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_down,
              color: kTextHint),
          onTap: () => setState(() => _expanded = !_expanded),
          dense: true,
        ),
        if (_expanded)
          Padding(
            padding:
            const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(children: [
              DropdownButtonFormField<String>(
                value: _expType,
                decoration: const InputDecoration(
                    labelText: 'Type', isDense: true),
                items: _expTypes
                    .map((t) => DropdownMenuItem(
                    value: t,
                    child: Text(
                        t[0].toUpperCase() +
                            t.substring(1),
                        style: const TextStyle(
                            fontSize: 13))))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _expType = v!),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: TextField(
                      controller: _amtCtrl,
                      keyboardType:
                      const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Amount (₹) *',
                          isDense: true,
                          prefixIcon: Icon(
                              Icons.currency_rupee,
                              size: 16)),
                    )),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(
                      controller: _noteCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Notes',
                          isDense: true),
                    )),
              ]),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white),
                  child: _submitting
                      ? const SizedBox(
                      width: 16,
                      height: 16,
                      child:
                      CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white))
                      : const Text('Add Expense',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                          FontWeight.w700)),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}