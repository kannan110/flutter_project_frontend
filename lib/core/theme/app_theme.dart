import 'package:flutter/material.dart';

// ── Colors ────────────────────────────────────────────────────────────
const kPrimary   = Color(0xFF1B6B3A);
const kSecondary = Color(0xFFE8A020);
const kError     = Color(0xFFD32F2F);
const kBgGrey    = Color(0xFFF5F7F5);
const kBorder    = Color(0xFFEEEEEE);
const kTextMain  = Color(0xFF1C1C1E);
const kTextSub   = Color(0xFF757575);
const kTextHint  = Color(0xFF9E9E9E);

class AppTheme {
  // Aliases for easy access
  static const primary   = kPrimary;
  static const secondary = kSecondary;
  static const errorRed  = kError;
  static const bgGrey    = kBgGrey;
  static const border    = kBorder;
  static const textMain  = kTextMain;
  static const textSub   = kTextSub;
  static const textHint  = kTextHint;

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: kPrimary, primary: kPrimary, secondary: kSecondary, error: kError, surface: kBgGrey),
    scaffoldBackgroundColor: kBgGrey,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white, foregroundColor: kTextMain,
      elevation: 0, scrolledUnderElevation: 1, centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kTextMain),
    ),
    cardTheme: CardThemeData(
      elevation: 0, color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: kBorder)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: const Color(0xFFF3F4F6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kPrimary, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kError)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kError, width: 1.5)),
      labelStyle: const TextStyle(color: kTextSub),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kPrimary, foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(50), elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kPrimary, minimumSize: const Size.fromHeight(50),
        side: const BorderSide(color: kPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white, selectedItemColor: kPrimary,
      unselectedItemColor: kTextHint, type: BottomNavigationBarType.fixed, elevation: 8,
    ),
    dividerTheme: const DividerThemeData(color: kBorder, space: 1),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? kPrimary.withOpacity(0.12) : Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? kPrimary : kTextSub),
      ),
    ),
  );
}

// ── Status Colors ─────────────────────────────────────────────────────
class SC {
  static Color order(String s) => switch (s) {
    'pending'          => const Color(0xFF9E9E9E),
    'confirmed'        => const Color(0xFF1976D2),
    'assigned'         => const Color(0xFF7B1FA2),
    'picked_up'        => const Color(0xFFE65100),
    'out_for_delivery' => const Color(0xFFF57F17),
    'delivered'        => const Color(0xFF388E3C),
    'approved'         => const Color(0xFF1B5E20),
    'invoiced'         => kPrimary,
    'closed'           => const Color(0xFF4CAF50),
    'cancelled'        => kError,
    _                  => const Color(0xFF9E9E9E),
  };
  static Color shift(String s) => switch (s) {
    'open'   => const Color(0xFF1976D2),
    'closed' => const Color(0xFF388E3C),
    _        => const Color(0xFF9E9E9E),
  };
}

// ── Format Helpers ────────────────────────────────────────────────────
class Fmt {
  static String amount(double v) {
    if (v >= 100000) return '₹${(v/100000).toStringAsFixed(2)}L';
    if (v >= 1000)   return '₹${(v/1000).toStringAsFixed(1)}K';
    return '₹${v.toStringAsFixed(2)}';
  }
  static String kg(double v) => '${v.toStringAsFixed(1)} kg';
}

// ── Shared Widgets ────────────────────────────────────────────────────
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, this.color, {super.key, this.small = false});
  final String label; final Color color; final bool small;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: small ? 6 : 8, vertical: small ? 2 : 3),
    decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
    child: Text(label.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(fontSize: small ? 9 : 10, fontWeight: FontWeight.w700, color: color)),
  );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10, top: 6),
    child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kTextHint, letterSpacing: 0.8)),
  );
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.valueColor});
  final String label, value; final Color? valueColor;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      SizedBox(width: 140, child: Text(label, style: const TextStyle(fontSize: 13, color: kTextSub))),
      Expanded(child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: valueColor ?? kTextMain))),
    ]),
  );
}

class KpiCard extends StatelessWidget {
  const KpiCard(this.label, this.value, this.icon, this.color, {super.key, this.sub, this.onTap});
  final String label, value; final IconData icon; final Color color;
  final String? sub; final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
          border: const Border.fromBorderSide(BorderSide(color: kBorder))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 22),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kTextMain)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: kTextHint)),
        if (sub != null) Text(sub!, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message, this.sub, this.onAction, this.actionLabel});
  final IconData icon; final String message; final String? sub, actionLabel; final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(40),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 64, color: Colors.grey.shade300),
      const SizedBox(height: 16),
      Text(message, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: kTextSub), textAlign: TextAlign.center),
      if (sub != null) ...[const SizedBox(height: 8), Text(sub!, style: const TextStyle(fontSize: 13, color: kTextHint), textAlign: TextAlign.center)],
      if (onAction != null) ...[const SizedBox(height: 20), ElevatedButton(onPressed: onAction, child: Text(actionLabel ?? 'Add'))],
    ]),
  ));
}

class LoadingList extends StatelessWidget {
  const LoadingList({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()));
}

class WhiteCard extends StatelessWidget {
  const WhiteCard({super.key, required this.child, this.padding});
  final Widget child; final EdgeInsets? padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding ?? const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: const Border.fromBorderSide(BorderSide(color: kBorder))),
    child: child,
  );
}

// ── Dialogs & Snackbars ───────────────────────────────────────────────
Future<bool> confirmDialog(BuildContext ctx, {required String title, required String message,
    String confirmText = 'Confirm', Color confirmColor = kError}) async {
  return await showDialog<bool>(
    context: ctx, useRootNavigator: true,
    builder: (c) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(c, rootNavigator: true).pop(false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.of(c, rootNavigator: true).pop(true),
            child: Text(confirmText, style: TextStyle(color: confirmColor, fontWeight: FontWeight.w700))),
      ],
    ),
  ) ?? false;
}

void showSuccess(BuildContext ctx, String msg) => ScaffoldMessenger.of(ctx)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(
    content: Row(children: [const Icon(Icons.check_circle_outline, color: Colors.white, size: 18), const SizedBox(width: 8), Expanded(child: Text(msg))]),
    backgroundColor: kPrimary, behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  ));

void showError(BuildContext ctx, String msg) => ScaffoldMessenger.of(ctx)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(
    content: Row(children: [const Icon(Icons.error_outline, color: Colors.white, size: 18), const SizedBox(width: 8), Expanded(child: Text(msg.replaceAll('Exception: ', '')))]),
    backgroundColor: kError, behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    duration: const Duration(seconds: 4),
  ));
