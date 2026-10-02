import 'package:flutter/material.dart';
import '../../../../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EntryModeSelector
//
// Shared widget used on every trader-assisted operation form.
// Lets the trader record HOW the agent reported (for operation_log).
//
// Maps to the p_entry_mode parameter present on all Phase 3 RPCs:
//   called | whatsapp | present | estimated
// ─────────────────────────────────────────────────────────────────────────────

class EntryModeSelector extends StatelessWidget {
  const EntryModeSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  static const Map<String, String> modes = {
    'called':    '📞 Called',
    'whatsapp':  '💬 WhatsApp',
    'present':   '🧑 Present',
    'estimated': '📊 Estimated',
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: modes.entries.map((e) {
        final selected = value == e.key;
        return ChoiceChip(
          label: Text(
            e.value,
            style: TextStyle(
              fontSize: 12,
              color: selected ? Colors.white : kTextSub,
              fontWeight: FontWeight.w600,
            ),
          ),
          selected: selected,
          selectedColor: kNavy,
          onSelected: (_) => onChanged(e.key),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BackdateField
//
// Shared tap-to-pick datetime field for backdating any operation.
// Used on open-shift, delivery, reassignment forms.
// ─────────────────────────────────────────────────────────────────────────────

class BackdateField extends StatelessWidget {
  const BackdateField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now,
    );
    if (date == null) return;
    if (!context.mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.now());
    if (time == null) return;
    onChanged(DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) {
    final set = value != null;
    return GestureDetector(
      onTap: () => _pick(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: set ? kNavy.withValues(alpha: 0.06) : kBorderLight.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(kRadiusInner),
          border: Border.all(color: set ? kNavy : kBorderLight),
        ),
        child: Row(
          children: [
            Icon(Icons.history_rounded, size: 18,
                color: set ? kNavy : kTextHint),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                set
                    ? 'Backdated: ${_fmt(value!)}'
                    : 'Backdate (optional) — tap to set actual time',
                style: TextStyle(fontSize: 13,
                    color: set ? kNavy : kTextHint),
              ),
            ),
            if (set)
              GestureDetector(
                onTap: () => onChanged(null),
                child: const Icon(Icons.close, size: 16, color: kTextHint),
              ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime dt) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.day} ${months[dt.month - 1]}, $h:$m $ampm';
  }
}