import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary = Color(0xFF1B6B3A);
  static const Color secondary = Color(0xFFE8A020);
  static const Color errorRed = Color(0xFFD32F2F);
  static const Color bgGrey = Color(0xFFF8FBF8);

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          primary: primary,
          secondary: secondary,
          error: errorRed,
          surface: bgGrey,
        ),
        scaffoldBackgroundColor: bgGrey,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF1C1C1E),
          elevation: 0,
          scrolledUnderElevation: 1,
          centerTitle: false,
          titleTextStyle: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1C1C1E)),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFEEEEEE)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF3F4F6),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: primary, width: 1.5)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: errorRed)),
          focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: errorRed, width: 1.5)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(50),
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: primary,
            minimumSize: const Size.fromHeight(50),
            side: const BorderSide(color: primary),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: primary,
          unselectedItemColor: Color(0xFF9E9E9E),
          type: BottomNavigationBarType.fixed,
          elevation: 8,
          showUnselectedLabels: true,
        ),
        dividerColor: const Color(0xFFF0F0F0),
        dividerTheme:
            const DividerThemeData(color: Color(0xFFF0F0F0), space: 1),
      );
}

class StatusColors {
  static Color order(String s) => switch (s) {
        'pending' => const Color(0xFF9E9E9E),
        'confirmed' => const Color(0xFF1976D2),
        'assigned' => const Color(0xFF7B1FA2),
        'picked_up' => const Color(0xFFE65100),
        'out_for_delivery' => const Color(0xFFF57F17),
        'delivered' => const Color(0xFF388E3C),
        'approved' => const Color(0xFF1B5E20),
        'invoiced' => const Color(0xFF1B6B3A),
        'cancelled' => const Color(0xFFD32F2F),
        _ => const Color(0xFF9E9E9E),
      };

  static Color approval(String s) => switch (s) {
        'pending' => const Color(0xFFE65100),
        'approved' => const Color(0xFF388E3C),
        'rejected' => const Color(0xFFD32F2F),
        _ => const Color(0xFF9E9E9E),
      };

  static Color shift(String s) => switch (s) {
        'open' => const Color(0xFF1976D2),
        'closed' => const Color(0xFF388E3C),
        'cancelled' => const Color(0xFFD32F2F),
        _ => const Color(0xFF9E9E9E),
      };
}

// Reusable status badge
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, this.color, {super.key});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(6)),
        child: Text(label.replaceAll('_', ' ').toUpperCase(),
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      );
}

// Section header
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9E9E9E),
                letterSpacing: 0.5)),
      );
}

// Info row for detail screens
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.valueColor});

  final String label, value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          SizedBox(
              width: 140,
              child: Text(label,
                  style:
                      const TextStyle(fontSize: 13, color: Color(0xFF757575)))),
          Expanded(
              child: Text(value,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: valueColor ?? const Color(0xFF1C1C1E)))),
        ]),
      );
}

// Amount display
class AmountText extends StatelessWidget {
  const AmountText(this.amount, {super.key, this.style, this.color});

  final double amount;
  final TextStyle? style;
  final Color? color;

  static String format(double v) {
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(2)}L';
    if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
    return '₹${v.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) => Text(
        format(amount),
        style: (style ??
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))
            .copyWith(color: color ?? AppTheme.primary),
      );
}

// Empty state
class EmptyState extends StatelessWidget {
  const EmptyState(
      {super.key, required this.icon, required this.message, this.sub});

  final IconData icon;
  final String message;
  final String? sub;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(message,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF757575)),
                textAlign: TextAlign.center),
            if (sub != null) ...[
              const SizedBox(height: 8),
              Text(sub!,
                  style:
                      const TextStyle(fontSize: 13, color: Color(0xFF9E9E9E)),
                  textAlign: TextAlign.center),
            ],
          ]),
        ),
      );
}

// Loading card shimmer
class LoadingList extends StatelessWidget {
  const LoadingList({super.key, this.count = 5});

  final int count;

  @override
  Widget build(BuildContext context) => ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, __) => Container(
          height: 80,
          decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12)),
        ),
      );
}

// Confirm dialog helper
Future<bool> confirmDialog(BuildContext context,
    {required String title,
    required String message,
    String confirmText = 'Confirm',
    Color confirmColor = AppTheme.errorRed}) async {
  return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
                title: Text(title),
                content: Text(message),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(confirmText,
                          style: TextStyle(
                              color: confirmColor,
                              fontWeight: FontWeight.w600))),
                ],
              )) ??
      false;
}

// Snackbar helpers
void showSuccess(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppTheme.primary));

void showError(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppTheme.errorRed));
