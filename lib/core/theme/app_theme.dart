import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Brand Colors (from splash screen) ─────────────────────────────────────
const kPrimary    = Color(0xFFBF1B2C);   // Deep crimson red from splash
const kPrimaryDark= Color(0xFF8B0000);   // Darker red for gradients
const kPrimaryLight= Color(0xFFE53945);  // Lighter red for hover
const kSecondary  = Color(0xFF1A2B6B);   // Navy blue (rooster eye / TEAM4YOU)
const kAccent     = Color(0xFFE8A020);   // Amber accent (kept for badges)
const kError      = Color(0xFFD32F2F);
const kBgGrey     = Color(0xFFF5F5F7);
const kSurface    = Color(0xFFFFFFFF);
const kBorder     = Color(0xFFE8E8EC);
const kTextMain   = Color(0xFF1A1A2E);
const kTextSub    = Color(0xFF6B7280);
const kTextHint   = Color(0xFF9CA3AF);

class AppTheme {
  static const primary    = kPrimary;
  static const secondary  = kSecondary;
  static const errorRed   = kError;
  static const bgGrey     = kBgGrey;
  static const border     = kBorder;
  static const textMain   = kTextMain;
  static const textSub    = kTextSub;
  static const textHint   = kTextHint;

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: kPrimary,
      primary: kPrimary,
      secondary: kSecondary,
      error: kError,
      surface: kSurface,
    ),
    scaffoldBackgroundColor: kBgGrey,

    // AppBar — white with red accent
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: kTextMain,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w800, color: kTextMain,
          letterSpacing: -0.3),
      iconTheme: IconThemeData(color: kTextMain, size: 22),
      actionsIconTheme: IconThemeData(color: kPrimary, size: 22),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    ),

    // Cards
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: kBorder)),
    ),

    // Inputs
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF3F4F6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kPrimary, width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kError)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kError, width: 1.5)),
        labelStyle: const TextStyle(color: kTextSub, fontSize: 14),
      hintStyle: const TextStyle(color: kTextHint, fontSize: 14),
    ),

    // Buttons
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
            letterSpacing: 0.2),
      )),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kPrimary,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: kPrimary, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      )),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: kPrimary,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      )),

    // Bottom nav
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: kPrimary,
      unselectedItemColor: kTextHint,
      type: BottomNavigationBarType.fixed,
      elevation: 12,
      selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      unselectedLabelStyle: TextStyle(fontSize: 11),
    ),

    // Chips
    chipTheme: ChipThemeData(
      backgroundColor: const Color(0xFFF3F4F6),
      selectedColor: kPrimary.withValues(alpha: 0.12),
      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),

    dividerTheme: const DividerThemeData(color: kBorder, space: 1),

    // Segmented button
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? kPrimary.withValues(alpha: 0.12) : Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? kPrimary : kTextSub),
      )),

    // FAB
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kPrimary,
      foregroundColor: Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16))),
    ),

    // Text theme — larger, more readable
    textTheme: const TextTheme(
      displayLarge:  TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: kTextMain),
      titleLarge:    TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kTextMain),
      titleMedium:   TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kTextMain),
      titleSmall:    TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: kTextMain),
      bodyLarge:     TextStyle(fontSize: 17, fontWeight: FontWeight.w400, color: kTextMain),
      bodyMedium:    TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: kTextMain),
      bodySmall:     TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: kTextSub),
      labelLarge:    TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kTextMain),
      labelMedium:   TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: kTextSub),
      labelSmall:    TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kTextHint),
    ),
  );
}

// ── Status colours ─────────────────────────────────────────────────────────
class SC {
  static Color order(String s) => switch (s) {
    'pending'            => const Color(0xFF9E9E9E),
    'confirmed'          => const Color(0xFF1976D2),
    'assigned'           => const Color(0xFF7B1FA2),
    'picked_up'          => const Color(0xFFE65100),
    'out_for_delivery'   => const Color(0xFFF57F17),
    'partially_delivered'=> const Color(0xFFFF6D00),
    'delivered'          => const Color(0xFF388E3C),
    'approved'           => const Color(0xFF1B5E20),
    'invoiced'           => kPrimary,
    'closed'             => const Color(0xFF4CAF50),
    'cancelled'          => kError,
    _                    => const Color(0xFF9E9E9E),
  };
  static Color shift(String s) => switch (s) {
    'open'   => const Color(0xFF1976D2),
    'closed' => const Color(0xFF388E3C),
    _        => const Color(0xFF9E9E9E),
  };
}

// ── Formatters ─────────────────────────────────────────────────────────────
class Fmt {
  static String amount(double v) {
    if (v >= 100000) return '₹${(v/100000).toStringAsFixed(2)}L';
    if (v >= 1000)   return '₹${(v/1000).toStringAsFixed(1)}K';
    return '₹${v.toStringAsFixed(2)}';
  }
  static String kg(double v) => '${v.toStringAsFixed(1)} kg';
  static double? parseNum(String s) {
    final clean = s.trim().replaceAll(',', '');
    if (clean.isEmpty) return null;
    final upper = clean.toUpperCase();
    if (upper.endsWith('L')) return double.tryParse(upper.replaceAll('L', ''))?.let((n) => n * 100000);
    if (upper.endsWith('K')) return double.tryParse(upper.replaceAll('K', ''))?.let((n) => n * 1000);
    return double.tryParse(clean);
  }
  static int? parseInt(String s) => parseNum(s)?.round();
}

extension _Let<T> on T {
  R let<R>(R Function(T) fn) => fn(this);
}

// ── Shared Widgets ──────────────────────────────────────────────────────────

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, this.color, {super.key, this.small = false});
  final String label; final Color color; final bool small;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: small ? 7 : 10, vertical: small ? 3 : 4),
    decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.7)),
    child: Text(
      label.replaceAll('_', ' ').toUpperCase(),
      style: TextStyle(
          fontSize: small ? 9 : 10,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.3)),
  );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10, top: 6),
    child: Text(text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
            color: kTextHint, letterSpacing: 1.0)),
  );
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.valueColor});
  final String label, value; final Color? valueColor;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      SizedBox(width: 140,
          child: Text(label,
              style: const TextStyle(fontSize: 15, color: kTextSub,
                  fontWeight: FontWeight.w500))),
      Expanded(child: Text(value,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
              color: valueColor ?? kTextMain))),
    ]),
  );
}

class KpiCard extends StatelessWidget {
  const KpiCard(this.label, this.value, this.icon, this.color,
      {super.key, this.sub, this.onTap});
  final String label, value;
  final IconData icon;
  final Color color;
  final String? sub;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(14),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kBorder),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8, offset: const Offset(0, 2))
          ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 36, height: 36,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9)),
            child: Center(child: Icon(icon, color: color, size: 18))),
        const Spacer(),
        Text(value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
                color: kTextMain)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(fontSize: 14, color: kTextSub,
                fontWeight: FontWeight.w500)),
        if (sub != null) ...[
          const SizedBox(height: 2),
          Text(sub!, style: TextStyle(fontSize: 13, color: color,
              fontWeight: FontWeight.w700))
        ],
      ]),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message,
      this.sub, this.onAction, this.actionLabel});
  final IconData icon;
  final String message;
  final String? sub, actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(40),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 80, height: 80,
          decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(20)),
          child: Center(child: Icon(icon, size: 38,
              color: kPrimary.withValues(alpha: 0.5)))),
      const SizedBox(height: 20),
      Text(message,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
              color: kTextSub),
          textAlign: TextAlign.center),
      if (sub != null) ...[
        const SizedBox(height: 8),
        Text(sub!, style: const TextStyle(fontSize: 15, color: kTextHint),
            textAlign: TextAlign.center)
      ],
      if (onAction != null) ...[
        const SizedBox(height: 24),
        ElevatedButton(onPressed: onAction,
            child: Text(actionLabel ?? 'Add'))
      ],
    ]),
  ));
}

class LoadingList extends StatelessWidget {
  const LoadingList({super.key});
  @override Widget build(BuildContext context) => const Center(
    child: Padding(padding: EdgeInsets.all(40),
        child: CircularProgressIndicator(color: kPrimary, strokeWidth: 2.5)));
}

class WhiteCard extends StatelessWidget {
  const WhiteCard({super.key, required this.child, this.padding});
  final Widget child; final EdgeInsets? padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding ?? const EdgeInsets.all(16),
    decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 6, offset: const Offset(0, 1))]),
    child: child,
  );
}

class SmartNumField extends StatelessWidget {
  const SmartNumField({super.key, required this.controller, required this.label,
      this.suffix, this.hint, this.onChanged, this.validator, this.isInt = false});
  final TextEditingController controller;
  final String label;
  final String? suffix, hint;
  final void Function(String)? onChanged;
  final String? Function(String?)? validator;
  final bool isInt;
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
        labelText: label, suffixText: suffix, helperText: hint),
    onChanged: onChanged,
    validator: validator,
  );
}

// ── Search bar widget ───────────────────────────────────────────────────────
class AppSearchBar extends StatelessWidget {
  const AppSearchBar({super.key, required this.controller, required this.hint,
      this.onChanged, this.onClear});
  final TextEditingController controller;
  final String hint;
  final void Function(String)? onChanged;
  final VoidCallback? onClear;
  @override
  Widget build(BuildContext context) => Container(
    height: 44,
    decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12)),
    child: TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: kTextHint, fontSize: 14),
        prefixIcon: const Icon(Icons.search, color: kTextHint, size: 20),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18, color: kTextHint),
                onPressed: onClear)
            : null,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
    ));
}

// ── Dialogs ─────────────────────────────────────────────────────────────────
Future<bool> confirmDialog(BuildContext ctx, {required String title,
    required String message, String confirmText = 'Confirm',
    Color confirmColor = kError}) async {
  return await showDialog<bool>(
    context: ctx, useRootNavigator: true,
    builder: (c) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      title: Text(title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      content: Text(message,
          style: const TextStyle(fontSize: 14, color: kTextSub, height: 1.5)),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(c, rootNavigator: true).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: kTextSub, fontWeight: FontWeight.w600))),
        TextButton(
            onPressed: () => Navigator.of(c, rootNavigator: true).pop(true),
            child: Text(confirmText,
                style: TextStyle(color: confirmColor,
                    fontWeight: FontWeight.w800))),
      ],
    ),
  ) ?? false;
}

void showSuccess(BuildContext ctx, String msg) => ScaffoldMessenger.of(ctx)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(
    content: Row(children: [
      const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
      const SizedBox(width: 10),
      Expanded(child: Text(msg, style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600)))
    ]),
    backgroundColor: const Color(0xFF2E7D32),
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.all(16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    duration: const Duration(seconds: 3),
  ));

void showError(BuildContext ctx, String msg) => ScaffoldMessenger.of(ctx)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(
    content: Row(children: [
      const Icon(Icons.error_rounded, color: Colors.white, size: 18),
      const SizedBox(width: 10),
      Expanded(child: Text(
        msg.replaceAll('Exception: ', '')
           .replaceAll('PostgrestException(message: ', '')
           .replaceAll(')', ''),
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)))
    ]),
    backgroundColor: kError,
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.all(16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    duration: const Duration(seconds: 5),
  ));
