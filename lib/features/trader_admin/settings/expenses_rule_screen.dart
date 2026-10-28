import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EXPENSE RULES SCREEN
//
// Phase 7: Trader configures per-vehicle-type expense caps.
// These rules are used by validate_shift_expenses() when reviewing shift costs.
//
// One rule per vehicle_type per trader. Fields:
//   • Fuel rate (₹/km)      — expected diesel cost per km
//   • Allowance cap/shift   — max daily allowance
//   • Max toll/shift
//   • Max loading/shift
//   • Max misc/shift
//   • Max total expenses/shift (hard cap across all categories)
//
// Vehicle types shown match what delivery_agents.vehicle_type contains.
// Standard types: two_wheeler, mini_truck, tempo, auto.
// An 'all' type acts as a fallback for any unmatched vehicle.
//
// Direct CRUD on vehicle_expense_rules table — no RPC needed (RLS covers access).
// ─────────────────────────────────────────────────────────────────────────────

class ExpenseRulesScreen extends ConsumerStatefulWidget {
  const ExpenseRulesScreen({super.key});

  @override
  ConsumerState<ExpenseRulesScreen> createState() => _ExpenseRulesScreenState();
}

class _ExpenseRulesScreenState extends ConsumerState<ExpenseRulesScreen> {
  final _c = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _rules = [];

  // Known vehicle types — drives the "Add Rule" picker
  static const _vehicleTypes = [
    ('two_wheeler', '🛵 Two-Wheeler'),
    ('mini_truck',  '🚛 Mini Truck'),
    ('tempo',       '🚐 Tempo'),
    ('auto',        '🛺 Auto'),
    ('all',         '🚗 All Vehicles (fallback)'),
  ];

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
      final res = await _c
          .from('vehicle_expense_rules')
          .select()
          .eq('trader_id', tid)
          .order('vehicle_type');
      if (mounted) {
        setState(() {
          _rules = List<Map<String, dynamic>>.from(res as List? ?? []);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showError(context, e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  // Vehicle types that don't have a rule yet
  List<(String, String)> get _availableTypes {
    final existing = _rules.map((r) => r['vehicle_type'] as String).toSet();
    return _vehicleTypes.where((t) => !existing.contains(t.$1)).toList();
  }

  String _displayLabel(String type) {
    for (final t in _vehicleTypes) {
      if (t.$1 == type) return t.$2;
    }
    return type;
  }

  Future<void> _openEditor({Map<String, dynamic>? existing}) async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;

    String? selectedType = existing?['vehicle_type'] as String?;

    // For new rule: pick vehicle type first if multiple available
    if (existing == null) {
      if (_availableTypes.isEmpty) {
        showError(context, 'Rules already configured for all vehicle types.');
        return;
      }
      if (_availableTypes.length == 1) {
        selectedType = _availableTypes.first.$1;
      } else {
        selectedType = await showDialog<String>(
          context: context,
          useRootNavigator: true,
          builder: (ctx) => AlertDialog(
            title: const Text('Select Vehicle Type'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: _availableTypes.map((t) => ListTile(
                leading: Text(t.$2.split(' ').first,
                    style: const TextStyle(fontSize: 22)),
                title: Text(t.$2.split(' ').last),
                onTap: () => Navigator.of(ctx, rootNavigator: true).pop(t.$1),
              )).toList(),
            ),
          ),
        );
        if (selectedType == null || !mounted) return;
      }
    }

    await showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RuleEditorSheet(
        vehicleType: selectedType!,
        existing: existing,
        traderId: tid,
        onSaved: _load,
      ),
    );
  }

  Future<void> _delete(String ruleId, String vehicleType) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete Rule',
      message: 'Delete expense rule for ${_displayLabel(vehicleType)}?\n\n'
          'Shifts with this vehicle type will no longer be validated.',
      confirmText: 'Delete',
      confirmColor: kError,
    );
    if (!ok || !mounted) return;
    try {
      await _c.from('vehicle_expense_rules').delete().eq('id', ruleId);
      if (mounted) {
        showSuccess(context, '✓ Rule deleted');
        _load();
      }
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kNavy,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : null,
        ),
        title: const Text('Expense Rules',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                color: Colors.white)),
        actions: [
          if (_availableTypes.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              tooltip: 'Add Rule',
              onPressed: () => _openEditor(),
            ),
        ],
      ),
      body: _loading
          ? const LoadingList()
          : ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          // Explainer
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kNavy.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: kNavy.withValues(alpha: 0.15)),
            ),
            child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.info_outline, color: kNavy, size: 16),
                    SizedBox(width: 8),
                    Text('How Expense Validation Works',
                        style: TextStyle(fontSize: 13,
                            fontWeight: FontWeight.w800, color: kNavy)),
                  ]),
                  SizedBox(height: 8),
                  Text(
                    'When a shift is closed, the system checks reported '
                        'expenses against these rules.\n\n'
                        'Fuel cap = Distance (km) × Fuel Rate (₹/km).\n'
                        'Other caps are fixed per shift.\n\n'
                        'Overclaims appear as alerts and are shown on the shift '
                        'detail screen before approval.',
                    style: TextStyle(fontSize: 12, color: kTextSub,
                        height: 1.5),
                  ),
                ]),
          ),
          const SizedBox(height: 16),

          if (_rules.isEmpty)
            EmptyState(
              icon: Icons.rule_outlined,
              message: 'No expense rules yet',
              sub: 'Tap + to add rules for each vehicle type',
              onAction: _availableTypes.isNotEmpty ? _openEditor : null,
              actionLabel: 'Add First Rule',
            )
          else
            ..._rules.map((rule) => _ruleCard(rule)),

          if (_availableTypes.isNotEmpty && _rules.isNotEmpty) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _openEditor,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Rule for Another Vehicle Type'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 44)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _ruleCard(Map<String, dynamic> rule) {
    final id          = rule['id'] as String;
    final vType       = rule['vehicle_type'] as String;
    final fuelRate    = (rule['fuel_rate_per_km']    as num?)?.toDouble() ?? 0;
    final allowance   = (rule['allowance_per_shift'] as num?)?.toDouble() ?? 0;
    final maxToll     = (rule['max_toll']            as num?)?.toDouble() ?? 0;
    final maxLoading  = (rule['max_loading']         as num?)?.toDouble() ?? 0;
    final maxMisc     = (rule['max_misc']            as num?)?.toDouble() ?? 0;
    final maxTotal    = (rule['max_total_expenses']  as num?)?.toDouble() ?? 0;
    final notes       = rule['notes'] as String?;
    final isActive    = rule['is_active'] as bool? ?? true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(
          color: isActive ? kBorderLight : kBorderLight.withValues(alpha: 0.4),
        ),
        boxShadow: kCardShadow,
      ),
      child: Column(children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: kNavy.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(kRadiusInner),
              ),
              child: Center(
                child: Text(
                  _displayLabel(vType).split(' ').first,
                  style: const TextStyle(fontSize: 22),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_displayLabel(vType),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800)),
                  Text('₹${fuelRate.toStringAsFixed(1)}/km fuel rate',
                      style: const TextStyle(fontSize: 12, color: kTextSub)),
                ])),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18, color: kNavy),
              onPressed: () => _openEditor(existing: rule),
              tooltip: 'Edit',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18, color: kError),
              onPressed: () => _delete(id, vType),
              tooltip: 'Delete',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ]),
        ),

        // Caps grid
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          decoration: const BoxDecoration(
            color: kBgPage,
            borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(kRadiusCard)),
          ),
          child: Column(children: [
            Row(children: [
              _cap('⛽ Fuel/km', '₹${fuelRate.toStringAsFixed(1)}'),
              _cap('💰 Allowance', allowance > 0
                  ? '₹${allowance.toStringAsFixed(0)}' : 'No cap'),
              _cap('🚧 Max Toll', maxToll > 0
                  ? '₹${maxToll.toStringAsFixed(0)}' : 'No cap'),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              _cap('📦 Max Loading', maxLoading > 0
                  ? '₹${maxLoading.toStringAsFixed(0)}' : 'No cap'),
              _cap('📋 Max Misc', maxMisc > 0
                  ? '₹${maxMisc.toStringAsFixed(0)}' : 'No cap'),
              _cap('📊 Max Total', maxTotal > 0
                  ? '₹${maxTotal.toStringAsFixed(0)}' : 'No cap'),
            ]),
            if (notes != null && notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.notes_outlined, size: 13, color: kTextHint),
                const SizedBox(width: 6),
                Expanded(child: Text(notes,
                    style: const TextStyle(fontSize: 11, color: kTextHint))),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _cap(String label, String value) => Expanded(
    child: Column(children: [
      Text(label, style: const TextStyle(fontSize: 9, color: kTextHint),
          textAlign: TextAlign.center),
      const SizedBox(height: 2),
      Text(value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
              color: kTextMain),
          textAlign: TextAlign.center,
          maxLines: 1, overflow: TextOverflow.ellipsis),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// RULE EDITOR BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _RuleEditorSheet extends ConsumerStatefulWidget {
  const _RuleEditorSheet({
    required this.vehicleType,
    required this.traderId,
    required this.onSaved,
    this.existing,
  });

  final String vehicleType;
  final String traderId;
  final VoidCallback onSaved;
  final Map<String, dynamic>? existing;

  @override
  ConsumerState<_RuleEditorSheet> createState() => _RuleEditorSheetState();
}

class _RuleEditorSheetState extends ConsumerState<_RuleEditorSheet> {
  final _c = Supabase.instance.client;

  late final _fuelCtrl      = TextEditingController(text: _val('fuel_rate_per_km',    '5.0'));
  late final _allowCtrl     = TextEditingController(text: _val('allowance_per_shift', '0'));
  late final _tollCtrl      = TextEditingController(text: _val('max_toll',            '0'));
  late final _loadCtrl      = TextEditingController(text: _val('max_loading',         '0'));
  late final _miscCtrl      = TextEditingController(text: _val('max_misc',            '0'));
  late final _totalCtrl     = TextEditingController(text: _val('max_total_expenses',  '0'));
  late final _notesCtrl     = TextEditingController(text: widget.existing?['notes'] as String? ?? '');

  bool _submitting = false;

  String _val(String key, String def) {
    final v = (widget.existing?[key] as num?)?.toDouble();
    return v != null ? v.toStringAsFixed(v == v.truncateToDouble() ? 0 : 1) : def;
  }

  static const _vehicleLabels = {
    'two_wheeler': '🛵 Two-Wheeler',
    'mini_truck':  '🚛 Mini Truck',
    'tempo':       '🚐 Tempo',
    'auto':        '🛺 Auto',
    'all':         '🚗 All Vehicles',
  };

  @override
  void dispose() {
    for (final c in [_fuelCtrl, _allowCtrl, _tollCtrl, _loadCtrl,
      _miscCtrl, _totalCtrl, _notesCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final fuel  = double.tryParse(_fuelCtrl.text.trim())  ?? 0;
    if (fuel <= 0) { showError(context, 'Fuel rate must be > 0'); return; }

    final data = {
      'trader_id':           widget.traderId,
      'vehicle_type':        widget.vehicleType,
      'fuel_rate_per_km':    fuel,
      'allowance_per_shift': double.tryParse(_allowCtrl.text.trim()) ?? 0,
      'max_toll':            double.tryParse(_tollCtrl.text.trim())   ?? 0,
      'max_loading':         double.tryParse(_loadCtrl.text.trim())   ?? 0,
      'max_misc':            double.tryParse(_miscCtrl.text.trim())   ?? 0,
      'max_total_expenses':  double.tryParse(_totalCtrl.text.trim())  ?? 0,
      'notes':               _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      'is_active':           true,
      'updated_at':          DateTime.now().toIso8601String(),
    };

    setState(() => _submitting = true);
    try {
      if (widget.existing != null) {
        await _c.from('vehicle_expense_rules')
            .update(data)
            .eq('id', widget.existing!['id'] as String);
      } else {
        await _c.from('vehicle_expense_rules').insert(data);
      }
      if (mounted) {
        showSuccess(context, '✓ Rule saved for '
            '${_vehicleLabels[widget.vehicleType] ?? widget.vehicleType}');
        Navigator.of(context, rootNavigator: true).pop();
        widget.onSaved();
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
    final label = _vehicleLabels[widget.vehicleType] ?? widget.vehicleType;
    return Container(
      decoration: const BoxDecoration(
        color: kBgPage,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: kBorderLight,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),

            // Header
            Row(children: [
              Text(label.split(' ').first,
                  style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.existing != null ? 'Edit Rule' : 'New Rule',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(label, style: const TextStyle(
                        fontSize: 12, color: kTextSub)),
                  ])),
            ]),
            const SizedBox(height: 20),

            // Fuel rate — primary field
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: kNavy.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(kRadiusCard),
                border: Border.all(color: kNavy.withValues(alpha: 0.2)),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('FUEL RATE (₹/KM) *',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                            color: kNavy, letterSpacing: 0.8)),
                    const SizedBox(height: 4),
                    const Text(
                      'Used to compute expected fuel cost. '
                          'Expected = Distance × Rate.',
                      style: TextStyle(fontSize: 11, color: kTextSub),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _fuelCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      autofocus: widget.existing == null,
                      decoration: const InputDecoration(
                        labelText: 'Fuel Rate (₹/km) *',
                        prefixText: '₹',
                        suffixText: '/km',
                        helperText: 'e.g. 6.0 for mini truck, 2.5 for two-wheeler',
                      ),
                    ),
                  ]),
            ),
            const SizedBox(height: 16),

            // Per-shift caps
            const Text('PER-SHIFT CAPS (0 = no cap)',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                    color: kTextHint, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _capField(_allowCtrl, '💰 Allowance (₹)')),
              const SizedBox(width: 10),
              Expanded(child: _capField(_tollCtrl,  '🚧 Max Toll (₹)')),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _capField(_loadCtrl, '📦 Max Loading (₹)')),
              const SizedBox(width: 10),
              Expanded(child: _capField(_miscCtrl, '📋 Max Misc (₹)')),
            ]),
            const SizedBox(height: 10),
            _capField(_totalCtrl, '📊 Max Total Expenses/Shift (₹)',
                helperText: 'Hard cap across all categories. 0 = no cap.'),
            const SizedBox(height: 12),

            // Notes
            TextField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                alignLabelWithHint: true,
                hintText: 'e.g. Urban routes only, revised Dec 2026…',
              ),
            ),
            const SizedBox(height: 20),

            SizedBox(height: 52,
              child: ElevatedButton.icon(
                onPressed: _submitting ? null : _save,
                icon: _submitting
                    ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(
                  widget.existing != null ? 'Update Rule' : 'Save Rule',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800,
                      color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(backgroundColor: kNavy),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _capField(TextEditingController ctrl, String label,
      {String? helperText}) =>
      TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          prefixText: '₹',
          helperText: helperText,
        ),
      );
}