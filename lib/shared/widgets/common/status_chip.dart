import 'package:flutter/material.dart';
import 'package:rooster_trader/core/theme/app_theme.dart';

// ── StatusChip ────────────────────────────────────────────────────────────
// Enterprise chip: low-saturation bg, high-saturation text, square corners
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.size = StatusChipSize.medium,
  });

  factory StatusChip.order(String status,
      {StatusChipSize size = StatusChipSize.medium}) =>
      StatusChip(label: status, color: SC.order(status), size: size);

  factory StatusChip.shift(String status,
      {StatusChipSize size = StatusChipSize.medium}) =>
      StatusChip(label: status, color: SC.shift(status), size: size);

  factory StatusChip.active(bool isActive,
      {StatusChipSize size = StatusChipSize.medium}) =>
      StatusChip(
        label: isActive ? 'Active' : 'Inactive',
        color: isActive ? kSuccess : kTextHint,
        size:  size,
      );

  final String         label;
  final Color          color;
  final StatusChipSize size;

  @override
  Widget build(BuildContext context) {
    final small = size == StatusChipSize.small;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: small ? 8 : 10, vertical: small ? 3 : 5),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border:       Border.all(color: color.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Text(
        label.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(
          fontSize:      small ? 9 : 10,
          fontWeight:    FontWeight.w800,
          color:         color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

enum StatusChipSize { small, medium }

// ── StatusDot ─────────────────────────────────────────────────────────────
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.size = 8});
  final Color  color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width:  size, height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}