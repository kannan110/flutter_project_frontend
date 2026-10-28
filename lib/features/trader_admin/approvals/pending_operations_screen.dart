import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PENDING OPERATIONS SCREEN
//
// Shows all deliveries stuck in out_for_delivery > 4 hours.
// Trader selects a delivery and enters actual data on behalf of the agent.
// Calls complete_delivery() with p_actor_type='trader', p_entry_mode from
// dropdown, and p_actual_at from the backdated time picker.
//
// Phase 3C actor params used:
//   p_actor_type  = 'trader'
//   p_actor_id    = trader's auth.uid()
//   p_entry_mode  = selected by trader (called/whatsapp/present/estimated)
//   p_actual_at   = backdated time (optional, defaults to now)
// ─────────────────────────────────────────────────────────────────────────────

class PendingOperationsScreen extends ConsumerStatefulWidget {
  const PendingOperationsScreen({super.key});
  @override ConsumerState<PendingOperationsScreen> createState() => _S();
}

class _S extends ConsumerState<PendingOperationsScreen> {
  final _c = Supabase.instance.client;
  List<Map<String, dynamic>> _stuck = [];
  bool _loading = true;

  // Threshold: show deliveries stuck longer than this
  static const _stuckHours = 4;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    if (mounted) setState(() => _loading = true);
    try {
      final cutoff = DateTime.now().subtract(const Duration(hours: _stuckHours));
      final data = await _c
          .from('deliveries')
          .select(
          'id, status, expected_bird_count, expected_total_weight, '
              'assigned_at, delivery_shift_id, delivery_agent_id, '
              'orders!inner(id, retailer_id, '
              '  retailers(shop_name, phone), '
              '  order_items(product_id, master_products(name))), '
              'delivery_agents!inner(id, name, phone)')
          .eq('trader_id', tid)
          .eq('status', 'out_for_delivery')
          .lt('assigned_at', cutoff.toIso8601String())
          .order('assigned_at', ascending: true)
          .limit(50);

      if (mounted) {
        setState(() {
          _stuck = List<Map<String, dynamic>>.from(data);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kBgPage,
    appBar: AppBar(
      backgroundColor: kSurface,
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pending Operations',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          Text('Deliveries stuck > $_stuckHours hours',
              style: TextStyle(fontSize: 11, color: kTextHint)),
        ],
      ),
      actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ],
    ),
    body: _loading
        ? const LoadingList()
        : _stuck.isEmpty
        ? EmptyState(
      icon: Icons.check_circle_outline,
      message: 'All deliveries are up to date!\n'
          'No deliveries stuck longer than $_stuckHours hours.',
      actionLabel: 'Refresh',
      onAction: _load,
    )
        : RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding:
        const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: _stuck.length,
        separatorBuilder: (_, __) =>
        const SizedBox(height: 10),
        itemBuilder: (_, i) => _StuckDeliveryCard(
          delivery: _stuck[i],
          onResolved: _load,
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Card for each stuck delivery
// ─────────────────────────────────────────────────────────────────────────────
class _StuckDeliveryCard extends ConsumerStatefulWidget {
  const _StuckDeliveryCard({
    required this.delivery,
    required this.onResolved,
  });
  final Map<String, dynamic> delivery;
  final VoidCallback onResolved;
  @override
  ConsumerState<_StuckDeliveryCard> createState() => _StuckDeliveryCardState();
}

class _StuckDeliveryCardState extends ConsumerState<_StuckDeliveryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.delivery;
    final agent = d['delivery_agents'] as Map<String, dynamic>? ?? {};
    final order = d['orders'] as Map<String, dynamic>? ?? {};
    final retailer = order['retailers'] as Map<String, dynamic>? ?? {};
    final agentName = agent['name'] as String? ?? '—';
    final shopName = retailer['shop_name'] as String? ?? '—';
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
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hoursStuck > 24
              ? Colors.red.shade200
              : Colors.orange.shade200,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: (hoursStuck > 24
                      ? Colors.red
                      : Colors.orange)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.schedule,
                  color: hoursStuck > 24
                      ? Colors.red.shade700
                      : Colors.orange.shade700,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(shopName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 14)),
                        Row(children: [
                          const Icon(Icons.delivery_dining,
                              size: 12, color: kPrimary),
                          const SizedBox(width: 4),
                          Text(agentName,
                              style: const TextStyle(
                                  fontSize: 12, color: kTextSub)),
                        ]),
                      ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: (hoursStuck > 24
                          ? Colors.red
                          : Colors.orange)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    hoursStuck > 48
                        ? '${(hoursStuck / 24).floor()}d stuck'
                        : '${hoursStuck}h stuck',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: hoursStuck > 24
                            ? Colors.red.shade700
                            : Colors.orange.shade700),
                  ),
                ),
                const SizedBox(height: 4),
                Text('$expectedBirds birds · ${expectedKg.toStringAsFixed(1)} kg',
                    style: const TextStyle(
                        fontSize: 10, color: kTextHint)),
              ]),
            ]),
          ),

          // ── Resolve button ─────────────────────────────────────────
          if (!_expanded)
            Padding(
              padding:
              const EdgeInsets.only(left: 14, right: 14, bottom: 14),
              child: SizedBox(
                width: double.infinity,
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: () => setState(() => _expanded = true),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Enter Delivery Data',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                ),
              ),
            ),

          // ── Resolve form ───────────────────────────────────────────
          if (_expanded)
            _ResolveForm(
              delivery: widget.delivery,
              onCancel: () => setState(() => _expanded = false),
              onResolved: () {
                setState(() => _expanded = false);
                widget.onResolved();
              },
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Compact resolve form — enters delivery data on behalf of agent
// ─────────────────────────────────────────────────────────────────────────────
class _ResolveForm extends ConsumerStatefulWidget {
  const _ResolveForm({
    required this.delivery,
    required this.onCancel,
    required this.onResolved,
  });
  final Map<String, dynamic> delivery;
  final VoidCallback onCancel;
  final VoidCallback onResolved;
  @override
  ConsumerState<_ResolveForm> createState() => _ResolveFormState();
}

class _ResolveFormState extends ConsumerState<_ResolveForm> {
  final _c = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _birdsCtrl;
  late TextEditingController _weightCtrl;
  final _mortalityCtrl = TextEditingController(text: '0');
  final _returnsCtrl = TextEditingController(text: '0');
  final _cashCtrl = TextEditingController(text: '0');
  String _paymentMode = 'credit';
  String _entryMode = 'called';
  DateTime? _actualAt;
  bool _submitting = false;

  static const _entryModes = {
    'called': 'Agent Called',
    'whatsapp': 'WhatsApp',
    'present': 'Agent Present',
    'estimated': 'Estimated',
  };

  static const _paymentModes = ['cash', 'upi', 'bank', 'credit'];

  @override
  void initState() {
    super.initState();
    final expectedBirds =
        (widget.delivery['expected_bird_count'] as num?)?.toInt() ?? 0;
    final expectedKg =
        (widget.delivery['expected_total_weight'] as num?)?.toDouble() ?? 0;
    _birdsCtrl = TextEditingController(text: '$expectedBirds');
    _weightCtrl =
        TextEditingController(text: expectedKg.toStringAsFixed(1));
  }

  @override
  void dispose() {
    _birdsCtrl.dispose();
    _weightCtrl.dispose();
    _mortalityCtrl.dispose();
    _returnsCtrl.dispose();
    _cashCtrl.dispose();
    super.dispose();
  }

  // Scenario 1 fix: preserves a blank Bird Count as NULL instead of silently
  // becoming 0, used only for the value persisted via complete_delivery.
  int? get _birdsToRecord => int.tryParse(_birdsCtrl.text.trim());

  Future<void> _pickActualTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 7)),
      lastDate: now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (time == null || !mounted) return;
    setState(() {
      _actualAt = DateTime(
          date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
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
        'p_mortality_birds':
        int.tryParse(_mortalityCtrl.text.trim()) ?? 0,
        'p_returned_birds':
        int.tryParse(_returnsCtrl.text.trim()) ?? 0,
        'p_collected_amount':
        double.tryParse(_cashCtrl.text.trim()) ?? 0.0,
        'p_payment_mode': _paymentMode,
        // Phase 3C actor params — trader entering on behalf of agent
        'p_actor_type': 'trader',
        'p_actor_id': user.userId,
        'p_entry_mode': _entryMode,
        if (_actualAt != null)
          'p_actual_at': _actualAt!.toIso8601String(),
      });

      if (mounted) {
        showSuccess(
            context,
            'Delivery resolved ✓ — entered as trader '
                '(${_entryModes[_entryMode]})');
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
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Form(
        key: _formKey,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Entry mode
              const Text('How did you get this data?',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: kTextHint)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: _entryModes.entries.map((e) {
                  final sel = _entryMode == e.key;
                  return ChoiceChip(
                    label: Text(e.value,
                        style: TextStyle(
                            fontSize: 11,
                            color: sel ? Colors.white : kTextSub,
                            fontWeight: FontWeight.w600)),
                    selected: sel,
                    onSelected: (_) =>
                        setState(() => _entryMode = e.key),
                    selectedColor: kPrimary,
                    backgroundColor: kBgPage,
                    side: BorderSide(
                        color: sel ? kPrimary : kBorderLight),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                  );
                }).toList(),
              ),

              const SizedBox(height: 10),

              // Actual delivery time (optional)
              GestureDetector(
                onTap: _pickActualTime,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                      border: Border.all(color: kBorderLight),
                      borderRadius: BorderRadius.circular(8),
                      color: kBgPage),
                  child: Row(children: [
                    const Icon(Icons.access_time,
                        size: 16, color: kTextHint),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(
                          _actualAt != null
                              ? 'Delivered at: ${DateFormat('d MMM, h:mm a').format(_actualAt!)}'
                              : 'Tap to set actual delivery time (optional)',
                          style: TextStyle(
                              fontSize: 12,
                              color: _actualAt != null
                                  ? kTextSub
                                  : kTextHint),
                        )),
                    if (_actualAt != null)
                      GestureDetector(
                        onTap: () => setState(() => _actualAt = null),
                        child: const Icon(Icons.close,
                            size: 14, color: kTextHint),
                      ),
                  ]),
                ),
              ),

              const SizedBox(height: 12),

              // Birds + Weight row
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _birdsCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly
                    ],
                    decoration: const InputDecoration(
                        labelText: 'Birds Delivered *',
                        isDense: true,
                        prefixIcon: Icon(Icons.egg_alt_outlined,
                            size: 16)),
                    validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0
                        ? 'Required'
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _weightCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Weight (kg) *',
                        isDense: true,
                        prefixIcon:
                        Icon(Icons.scale_outlined, size: 16)),
                    validator: (v) =>
                    (double.tryParse(v ?? '') ?? 0) <= 0
                        ? 'Required'
                        : null,
                  ),
                ),
              ]),

              const SizedBox(height: 10),

              // Mortality + Returns row
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _mortalityCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly
                    ],
                    decoration: const InputDecoration(
                        labelText: 'Mortality',
                        isDense: true,
                        prefixIcon:
                        Icon(Icons.warning_outlined, size: 16)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _returnsCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly
                    ],
                    decoration: const InputDecoration(
                        labelText: 'Returns',
                        isDense: true,
                        prefixIcon: Icon(Icons.assignment_return_outlined,
                            size: 16)),
                  ),
                ),
              ]),

              const SizedBox(height: 10),

              // Cash + Payment mode row
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _cashCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Cash Collected (₹)',
                        isDense: true,
                        prefixIcon: Icon(Icons.currency_rupee,
                            size: 16)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _paymentMode,
                    decoration: const InputDecoration(
                        labelText: 'Payment Mode', isDense: true),
                    items: _paymentModes
                        .map((m) => DropdownMenuItem(
                        value: m,
                        child: Text(m.toUpperCase(),
                            style:
                            const TextStyle(fontSize: 12))))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _paymentMode = v!),
                  ),
                ),
              ]),

              const SizedBox(height: 14),

              // Actor notice
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline,
                      size: 14, color: Colors.amber.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(
                        'This will be recorded as "Entered by Trader" in the audit log.',
                        style: TextStyle(
                            fontSize: 11, color: Colors.amber.shade800),
                      )),
                ]),
              ),

              const SizedBox(height: 12),

              // Action buttons
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                    _submitting ? null : widget.onCancel,
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 42),
                        side:
                        const BorderSide(color: kBorderLight)),
                    child: const Text('Cancel',
                        style: TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 42),
                        backgroundColor: kPrimary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                            BorderRadius.circular(10))),
                    child: _submitting
                        ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white))
                        : const Text('Resolve Delivery',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ]),
      ),
    );
  }
}