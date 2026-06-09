import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SHIFT EXPENSE VALIDATION PANEL
//
// Phase 7: Inline widget embedded in shift_detail_screen.dart.
// Shows the result of validate_shift_expenses() for the current shift.
//
// States:
//   • Not validated yet → shows "Run Validation" button
//   • Validation skipped (no distance/no rules) → shows reason
//   • 'ok' → green checkmark, fuel comparison
//   • 'overclaim' → orange warning, per-category breakdown
//   • Running → loading indicator
//
// Calls validate_shift_expenses RPC and re-renders on completion.
// ─────────────────────────────────────────────────────────────────────────────

class ShiftExpenseValidationPanel extends ConsumerStatefulWidget {
  const ShiftExpenseValidationPanel({
    super.key,
    required this.shiftId,
    this.initialStatus,
    this.initialResult,
  });

  final String shiftId;
  final String? initialStatus;   // from get_shift_summary if already validated
  final Map<String, dynamic>? initialResult;

  @override
  ConsumerState<ShiftExpenseValidationPanel> createState() =>
      _ShiftExpenseValidationPanelState();
}

class _ShiftExpenseValidationPanelState
    extends ConsumerState<ShiftExpenseValidationPanel> {
  final _c = Supabase.instance.client;

  bool _running = false;
  Map<String, dynamic>? _result;
  String? _status;

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
    _result = widget.initialResult;
  }

  Future<void> _validate() async {
    setState(() => _running = true);
    try {
      final res = await _c.rpc('validate_shift_expenses',
          params: {'p_shift_id': widget.shiftId})
          .timeout(const Duration(seconds: 15));
      if (mounted) {
        final r = (res as Map?)?.cast<String, dynamic>() ?? {};
        setState(() {
          _result  = r;
          _status  = r['status'] as String?;
          _running = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _running = false);
        showError(context, e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Not yet validated and no initial data
    if (_status == null && !_running) {
      return _notValidatedTile();
    }
    if (_running) {
      return _runningTile();
    }
    return _resultTile();
  }

  // ── Not validated ────────────────────────────────────────────────────────
  Widget _notValidatedTile() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(kRadiusCard),
      border: Border.all(color: kBorderLight),
    ),
    child: Row(children: [
      const Icon(Icons.receipt_long_outlined, color: kTextHint, size: 20),
      const SizedBox(width: 12),
      const Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Expense Validation',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              Text('Not yet validated for this shift.',
                  style: TextStyle(fontSize: 11, color: kTextSub)),
            ]),
      ),
      ElevatedButton(
        onPressed: _validate,
        style: ElevatedButton.styleFrom(
            backgroundColor: kNavy, padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 8)),
        child: const Text('Validate',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                color: Colors.white)),
      ),
    ]),
  );

  // ── Running ──────────────────────────────────────────────────────────────
  Widget _runningTile() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(kRadiusCard),
      border: Border.all(color: kBorderLight),
    ),
    child: const Row(children: [
      SizedBox(width: 20, height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: kNavy)),
      SizedBox(width: 12),
      Text('Validating expenses…',
          style: TextStyle(fontSize: 13, color: kTextSub)),
    ]),
  );

  // ── Result tile ──────────────────────────────────────────────────────────
  Widget _resultTile() {
    final status    = _status ?? 'unknown';
    final result    = _result ?? {};
    final notes     = result['notes'] as String? ?? '';
    final distKm    = (result['distance_km']  as num?)?.toDouble() ?? 0;
    final expected  = (result['expected_fuel'] as num?)?.toDouble() ?? 0;
    final reported  = (result['reported_fuel'] as num?)?.toDouble() ?? 0;
    final overclaim = (result['overclaim_amount'] as num?)?.toDouble() ?? 0;
    final ruleApplied = result['rule_applied'] as String?;
    final flags     = (result['category_flags'] as List? ?? [])
        .map((f) => (f as Map).cast<String, dynamic>()).toList();

    switch (status) {
      case 'no_rules':
        return _statusTile(
          color:   Colors.grey,
          icon:    Icons.rule_outlined,
          title:   'No Rules Configured',
          message: 'Set expense rules in Settings → Expense Rules for '
              '${result['vehicle_type'] ?? 'this vehicle type'}.',
          trailing: _revalidateBtn(),
        );

      case 'no_distance':
        return _statusTile(
          color:   Colors.blue,
          icon:    Icons.speed_outlined,
          title:   'No Distance — Skipped',
          message: 'Odometer not recorded. Record start/end readings to '
              'enable fuel cost validation.',
          trailing: _revalidateBtn(),
        );

      case 'skipped':
        return _statusTile(
          color:   Colors.grey,
          icon:    Icons.skip_next_outlined,
          title:   'Validation Skipped',
          message: notes,
          trailing: _revalidateBtn(),
        );

      case 'ok':
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(kRadiusCard),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.check_circle_outline,
                      color: Colors.green, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Expenses Within Limits ✓',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                          color: Colors.green))),
                  _revalidateBtn(small: true),
                ]),
                const SizedBox(height: 8),
                _fuelRow(distKm, expected, reported,
                    result['fuel_rate_per_km'], ruleApplied),
              ]),
        );

      case 'overclaim':
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(kRadiusCard),
            border: Border.all(color: Colors.orange.shade300, width: 1.5),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    'Expense Overclaim — ₹${overclaim.toStringAsFixed(0)} over limit',
                    style: const TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w800, color: Colors.orange),
                  )),
                  _revalidateBtn(small: true, color: Colors.orange),
                ]),
                const SizedBox(height: 8),
                _fuelRow(distKm, expected, reported,
                    result['fuel_rate_per_km'], ruleApplied),
                if (flags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...flags.map((f) => _flagRow(f)),
                ],
              ]),
        );

      default:
        return _statusTile(
          color:   Colors.grey,
          icon:    Icons.help_outline,
          title:   'Unknown Validation State',
          message: notes,
          trailing: _revalidateBtn(),
        );
    }
  }

  Widget _fuelRow(double dist, double expected, double reported,
      dynamic rateRaw, String? ruleType) {
    final rate = (rateRaw as num?)?.toDouble() ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kRadiusInner),
        border: Border.all(color: kBorderLight),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('⛽', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Expanded(child: Text(
            '${dist.toStringAsFixed(0)} km × ₹${rate.toStringAsFixed(1)}/km = '
                'expected ₹${expected.toStringAsFixed(0)}',
            style: const TextStyle(fontSize: 11, color: kTextSub),
          )),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          _fuelStat('Reported', '₹${reported.toStringAsFixed(0)}',
              reported > expected ? Colors.orange : kNavy),
          _fuelStat('Expected', '₹${expected.toStringAsFixed(0)}', Colors.green),
          if (ruleType != null)
            _fuelStat('Rule', ruleType, kTextHint),
        ]),
      ]),
    );
  }

  Widget _fuelStat(String label, String value, Color color) =>
      Expanded(child: Column(children: [
        Text(value, style: TextStyle(fontSize: 12,
            fontWeight: FontWeight.w800, color: color),
            textAlign: TextAlign.center),
        Text(label, style: const TextStyle(
            fontSize: 9, color: kTextHint),
            textAlign: TextAlign.center),
      ]));

  Widget _flagRow(Map<String, dynamic> f) {
    final cat      = f['category'] as String? ?? '—';
    final reported = (f['reported']  as num?)?.toDouble() ?? 0;
    final cap      = (f['cap']       as num?)?.toDouble() ?? 0;
    final over     = (f['overclaim'] as num?)?.toDouble() ?? 0;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [
        const Icon(Icons.arrow_right, color: Colors.orange, size: 14),
        Text('$cat: ', style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: Colors.orange)),
        Text('₹${reported.toStringAsFixed(0)} reported vs '
            '₹${cap.toStringAsFixed(0)} cap '
            '(₹${over.toStringAsFixed(0)} over)',
            style: const TextStyle(fontSize: 11, color: kTextSub)),
      ]),
    );
  }

  Widget _statusTile({
    required Color color,
    required IconData icon,
    required String title,
    required String message,
    required Widget trailing,
  }) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(kRadiusCard),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w800, color: color)),
                const SizedBox(height: 2),
                Text(message, style: const TextStyle(
                    fontSize: 11, color: kTextSub)),
              ])),
          const SizedBox(width: 8),
          trailing,
        ]),
      );

  Widget _revalidateBtn({bool small = false, Color? color}) => TextButton(
    onPressed: _running ? null : _validate,
    style: TextButton.styleFrom(
        padding: EdgeInsets.symmetric(
            horizontal: small ? 8 : 12, vertical: small ? 4 : 8),
        minimumSize: Size.zero,
        foregroundColor: color ?? kNavy),
    child: Text(small ? '↻' : '↻ Re-validate',
        style: TextStyle(fontSize: small ? 14 : 12,
            fontWeight: FontWeight.w700)),
  );
}