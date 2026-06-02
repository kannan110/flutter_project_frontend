import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ROOSTER COMMERCE OS — ELITE ENTERPRISE DESIGN SYSTEM
// Reference: Elite Enterprise Poultry (Hanken Grotesk / Navy-Gold palette)
// Mobile-first premium consumer style. Web/tablet layout deferred.
// ═══════════════════════════════════════════════════════════════════════════

// ── Core palette ───────────────────────────────────────────────────────────
const kNavy         = Color(0xFF00081E);
const kNavyMid      = Color(0xFF0A1F44);
const kNavyLight    = Color(0xFF34466D);
const kGold         = Color(0xFFC5A059);
const kGoldLight    = Color(0xFFE9C176);
const kGoldBg       = Color(0xFFFFDEA5);

// Legacy aliases — every existing screen imports these; keep them
const kPrimary      = kNavy;
const kPrimaryDark  = Color(0xFF00040F);
const kPrimaryLight = kNavyMid;
const kSecondary    = kGold;
const kAccent       = kGoldLight;

// ── Semantic ───────────────────────────────────────────────────────────────
const kError        = Color(0xFFBA1A1A);
const kErrorBg      = Color(0xFFFFDAD6);
const kSuccess      = Color(0xFF1B5E20);
const kSuccessBg    = Color(0xFFE8F5E9);
const kWarning      = Color(0xFF775A19);
const kWarningBg    = Color(0xFFFFFDE7);

// ── Surfaces — cream bg is the reference's #FDFBF7 ────────────────────────
const kBgPage       = Color(0xFFFDFBF7);   // cream — reference exact match
const kBgGrey       = Color(0xFFF3F4F5);
const kSurface      = Color(0xFFFFFFFF);
const kSurfaceHigh  = Color(0xFFE7E8E9);

// ── Borders ────────────────────────────────────────────────────────────────
const kBorder       = Color(0xFFC5C6CF);
const kBorderLight  = Color(0xFFE1E3E4);

// ── Text ───────────────────────────────────────────────────────────────────
const kTextMain     = Color(0xFF191C1D);
const kTextSub      = Color(0xFF44464E);
const kTextHint     = Color(0xFF75777F);
const kTextOnNavy   = Color(0xFFFFFFFF);
const kTextGold     = Color(0xFFC5A059);

// ── Sidebar (web — unchanged) ──────────────────────────────────────────────
const kSidebarBg     = kNavy;
const kSidebarActive = kNavyMid;
const kSidebarText   = Color(0xFFB4C6F4);
const kSidebarGold   = kGoldLight;

// ── Card shadow — reference style ─────────────────────────────────────────
const kCardShadow = [
  BoxShadow(
    color:      Color(0x0A000000),
    blurRadius: 30,
    offset:     Offset(0, 10),
    spreadRadius: -5,
  ),
  BoxShadow(
    color:      Color(0x05000000),
    blurRadius: 12,
    offset:     Offset(0, 4),
    spreadRadius: -4,
  ),
];

// ── Radius — reference uses 28px on hero cards ────────────────────────────
const kRadiusHero  = 28.0;   // navy gradient card, stock card
const kRadiusCard  = 20.0;   // regular section cards
const kRadiusChip  = 14.0;   // action pills, chips
const kRadiusInner = 10.0;   // internal containers
const kRadiusBtn   = 14.0;   // action buttons

// ── Status colours helper ─────────────────────────────────────────────────
class SC {
  static Color order(String s) => switch (s) {
    'pending'             => const Color(0xFF775A19),
    'confirmed'           => const Color(0xFF1565C0),
    'assigned'            => const Color(0xFF6A1B9A),
    'picked_up'           => const Color(0xFFE65100),
    'out_for_delivery'    => const Color(0xFF775A19),
    'partially_delivered' => const Color(0xFFBF360C),
    'delivered'           => const Color(0xFF1B5E20),
    'approved'            => const Color(0xFF1B5E20),
    'invoiced'            => kNavy,
    'closed'              => const Color(0xFF2E7D32),
    'cancelled'           => kError,
    _                     => const Color(0xFF75777F),
  };
  static Color shift(String s) => switch (s) {
    'open'   => const Color(0xFF1565C0),
    'closed' => const Color(0xFF1B5E20),
    _        => const Color(0xFF75777F),
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// THEME DATA
// ═══════════════════════════════════════════════════════════════════════════
class AppTheme {
  static ThemeData get light => ThemeData(
    useMaterial3:             true,
    scaffoldBackgroundColor:  kBgPage,
    colorScheme: const ColorScheme(
      brightness:           Brightness.light,
      primary:              kNavy,
      onPrimary:            kTextOnNavy,
      primaryContainer:     kNavyMid,
      onPrimaryContainer:   kSidebarText,
      secondary:            kGold,
      onSecondary:          kNavy,
      secondaryContainer:   kGoldBg,
      onSecondaryContainer: kNavy,
      error:                kError,
      onError:              Colors.white,
      errorContainer:       kErrorBg,
      onErrorContainer:     Color(0xFF93000A),
      surface:              kSurface,
      onSurface:            kTextMain,
      surfaceContainerHighest: kSurfaceHigh,
      outline:              kBorder,
      outlineVariant:       kBorderLight,
    ),

    // AppBar — white, no elevation
    appBarTheme: const AppBarTheme(
      backgroundColor:     kSurface,
      foregroundColor:     kTextMain,
      elevation:           0,
      scrolledUnderElevation: 0,
      centerTitle:         false,
      titleTextStyle: TextStyle(
        fontSize:      18,
        fontWeight:    FontWeight.w800,
        color:         kTextMain,
        letterSpacing: -0.2,
      ),
      iconTheme:     IconThemeData(color: kTextSub, size: 22),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor:          Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness:     Brightness.light,
      ),
    ),

    // Card — white, large radius, soft shadow
    cardTheme: CardThemeData(
      elevation: 0,
      color:     kSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusCard),
        side:         const BorderSide(color: kBorderLight, width: 0.5),
      ),
      shadowColor: Colors.black,
      clipBehavior: Clip.antiAlias,
    ),

    // Inputs
    inputDecorationTheme: InputDecorationTheme(
      filled:     true,
      fillColor:  kSurface,
      isDense:    false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusInner),
        borderSide:   const BorderSide(color: kBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusInner),
        borderSide:   const BorderSide(color: kBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusInner),
        borderSide:   const BorderSide(color: kNavy, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusInner),
        borderSide:   const BorderSide(color: kError),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusInner),
        borderSide:   const BorderSide(color: kError, width: 2),
      ),
      labelStyle: const TextStyle(fontSize: 15, color: kTextSub, fontWeight: FontWeight.w500),
      hintStyle:  const TextStyle(fontSize: 15, color: kTextHint),
      floatingLabelStyle: const TextStyle(fontSize: 13, color: kNavy, fontWeight: FontWeight.w700),
    ),

    // Elevated button
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kNavy,
        foregroundColor: Colors.white,
        minimumSize:     const Size.fromHeight(52),
        elevation:       0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusBtn)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.2),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    ),

    // Outlined button
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kNavy,
        minimumSize:     const Size.fromHeight(52),
        side:            const BorderSide(color: kNavy, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusBtn)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    ),

    // Text button
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: kNavy,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),

    // Bottom nav — transparent bg; glass handled in trader_shell.dart
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor:      Colors.transparent,
      selectedItemColor:    kWarning,       // gold-brown for active
      unselectedItemColor:  kTextHint,
      type:                 BottomNavigationBarType.fixed,
      elevation:            0,
      selectedLabelStyle:   TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
          letterSpacing: 0.6),
      unselectedLabelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
          letterSpacing: 0.6),
    ),

    // NavigationRail (tablet — unchanged)
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor:          kSurface,
      selectedIconTheme:        IconThemeData(color: kNavy),
      unselectedIconTheme:      IconThemeData(color: kTextHint),
      selectedLabelTextStyle:   TextStyle(color: kNavy, fontWeight: FontWeight.w700, fontSize: 11),
      unselectedLabelTextStyle: TextStyle(color: kTextHint, fontSize: 11),
      indicatorColor:           Color(0xFFD9E2FF),
    ),

    // Chips
    chipTheme: ChipThemeData(
      backgroundColor: kBgGrey,
      selectedColor:   kNavy.withValues(alpha: 0.10),
      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      side:        BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusChip)),
    ),

    dividerTheme: const DividerThemeData(color: kBorderLight, space: 1),

    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kNavy,
      foregroundColor: Colors.white,
      elevation:       4,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(kRadiusBtn))),
    ),

    // Text theme — weight 800/900 to match Hanken Grotesk Black style
    textTheme: const TextTheme(
      displayLarge:  TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: kTextMain, letterSpacing: -0.5),
      displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: kTextMain, letterSpacing: -0.4),
      headlineLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: kTextMain, letterSpacing: -0.3),
      headlineMedium:TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kTextMain),
      titleLarge:    TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kTextMain),
      titleMedium:   TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kTextMain),
      titleSmall:    TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kTextMain),
      bodyLarge:     TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: kTextMain, height: 1.6),
      bodyMedium:    TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: kTextMain, height: 1.5),
      bodySmall:     TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: kTextSub,  height: 1.5),
      labelLarge:    TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kTextMain),
      labelMedium:   TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kTextSub,  letterSpacing: 0.6),
      labelSmall:    TextStyle(fontSize: 9,  fontWeight: FontWeight.w800, color: kTextHint, letterSpacing: 0.8),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS — all existing screens use these; API is unchanged
// ═══════════════════════════════════════════════════════════════════════════

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, this.color, {super.key, this.small = false});
  final String label;
  final Color  color;
  final bool   small;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
        horizontal: small ? 8 : 10, vertical: small ? 3 : 5),
    decoration: BoxDecoration(
      color:        color.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(kRadiusChip),
      border:       Border.all(color: color.withValues(alpha: 0.28), width: 0.8),
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

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10, top: 6),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize:      10,
        fontWeight:    FontWeight.w800,
        color:         kTextHint,
        letterSpacing: 1.0,
      ),
    ),
  );
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.valueColor});
  final String label, value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(children: [
      SizedBox(
        width: 160,
        child: Text(label,
            style: const TextStyle(fontSize: 15, color: kTextSub,
                fontWeight: FontWeight.w500)),
      ),
      Expanded(child: Text(value,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
              color: valueColor ?? kTextMain))),
    ]),
  );
}

// KpiCard — used in desktop dashboard and other screens
class KpiCard extends StatelessWidget {
  const KpiCard(this.label, this.value, this.icon, this.color,
      {super.key, this.sub, this.onTap});
  final String     label, value;
  final IconData   icon;
  final Color      color;
  final String?    sub;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap:        onTap,
    borderRadius: BorderRadius.circular(kRadiusCard),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        kSurface,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border:       Border.all(color: kBorderLight, width: 0.5),
        boxShadow:    kCardShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color:        kNavy,
            borderRadius: BorderRadius.circular(kRadiusChip),
          ),
          child: Center(child: Icon(icon, color: kGoldLight, size: 20)),
        ),
        const Spacer(),
        Text(value,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900,
                color: kTextMain, letterSpacing: -0.5)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(fontSize: 13, color: kTextSub,
                fontWeight: FontWeight.w600)),
        if (sub != null) ...[
          const SizedBox(height: 2),
          Text(sub!,
              style: TextStyle(fontSize: 12, color: color,
                  fontWeight: FontWeight.w700)),
        ],
      ]),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.sub, this.onAction, this.actionLabel,
  });
  final IconData   icon;
  final String     message;
  final String?    sub, actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(48),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color:        kNavy.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(kRadiusCard),
            border:       Border.all(color: kBorderLight),
          ),
          child: Center(
              child: Icon(icon, size: 36, color: kNavy.withValues(alpha: 0.35))),
        ),
        const SizedBox(height: 24),
        Text(message,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                color: kTextSub),
            textAlign: TextAlign.center),
        if (sub != null) ...[
          const SizedBox(height: 8),
          Text(sub!,
              style: const TextStyle(fontSize: 14, color: kTextHint, height: 1.5),
              textAlign: TextAlign.center),
        ],
        if (onAction != null) ...[
          const SizedBox(height: 28),
          ElevatedButton(onPressed: onAction,
              child: Text(actionLabel ?? 'Add')),
        ],
      ]),
    ),
  );
}

class LoadingList extends StatelessWidget {
  const LoadingList({super.key});

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(48),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 36, height: 36,
          child: CircularProgressIndicator(color: kNavy, strokeWidth: 3),
        ),
        SizedBox(height: 16),
        Text('Loading…',
            style: TextStyle(fontSize: 14, color: kTextHint,
                fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

class WhiteCard extends StatelessWidget {
  const WhiteCard({super.key, required this.child, this.padding});
  final Widget      child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding ?? const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color:        kSurface,
      borderRadius: BorderRadius.circular(kRadiusCard),
      border:       Border.all(color: kBorderLight, width: 0.5),
      boxShadow:    kCardShadow,
    ),
    child: child,
  );
}

class SmartNumField extends StatelessWidget {
  const SmartNumField({
    super.key,
    required this.controller,
    required this.label,
    this.suffix, this.hint, this.onChanged, this.validator, this.isInt = false,
  });
  final TextEditingController  controller;
  final String                 label;
  final String?                suffix, hint;
  final void Function(String)? onChanged;
  final String? Function(String?)? validator;
  final bool                   isInt;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller:   controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    style:        const TextStyle(fontSize: 16, color: kTextMain),
    decoration: InputDecoration(
        labelText: label, suffixText: suffix, helperText: hint),
    onChanged: onChanged,
    validator: validator,
  );
}

class AppSearchBar extends StatelessWidget {
  const AppSearchBar({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged, this.onClear,
  });
  final TextEditingController  controller;
  final String                 hint;
  final void Function(String)? onChanged;
  final VoidCallback?          onClear;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, __) => Container(
      height: 48,
      decoration: BoxDecoration(
        color:        kSurface,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border:       Border.all(color: kBorderLight),
        boxShadow:    kCardShadow,
      ),
      child: TextField(
        controller: controller,
        onChanged:  onChanged,
        style: const TextStyle(fontSize: 15, color: kTextMain),
        decoration: InputDecoration(
          hintText:   hint,
          hintStyle:  const TextStyle(color: kTextHint, fontSize: 15),
          prefixIcon: const Icon(Icons.search_rounded, color: kTextHint, size: 20),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
            icon: const Icon(Icons.close_rounded, size: 16, color: kTextHint),
            onPressed: onClear ?? () { controller.clear(); onChanged?.call(''); },
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          )
              : null,
          border:         InputBorder.none,
          enabledBorder:  InputBorder.none,
          focusedBorder:  InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    ),
  );
}

Future<bool> confirmDialog(
    BuildContext ctx, {
      required String title,
      required String message,
      String confirmText  = 'Confirm',
      Color  confirmColor = kError,
    }) async {
  return await showDialog<bool>(
    context:          ctx,
    useRootNavigator: true,
    builder: (c) => AlertDialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusCard)),
      title: Text(title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      content: Text(message,
          style: const TextStyle(fontSize: 15, color: kTextSub, height: 1.6)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(c, rootNavigator: true).pop(false),
          child: const Text('Cancel',
              style: TextStyle(color: kTextSub, fontWeight: FontWeight.w600)),
        ),
        TextButton(
          onPressed: () => Navigator.of(c, rootNavigator: true).pop(true),
          child: Text(confirmText,
              style: TextStyle(color: confirmColor, fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  ) ?? false;
}

void showSuccess(BuildContext ctx, String msg) =>
    ScaffoldMessenger.of(ctx)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(msg,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
        ]),
        backgroundColor: kSuccess,
        behavior:        SnackBarBehavior.floating,
        margin:          const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kRadiusChip)),
        duration: const Duration(seconds: 3),
      ));

void showError(BuildContext ctx, String msg) =>
    ScaffoldMessenger.of(ctx)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.error_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(
            msg.replaceAll('Exception: ', '')
                .replaceAll('PostgrestException(message: ', '')
                .replaceAll(')', ''),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          )),
        ]),
        backgroundColor: kError,
        behavior:        SnackBarBehavior.floating,
        margin:          const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kRadiusChip)),
        duration: const Duration(seconds: 5),
      ));

// ═══════════════════════════════════════════════════════════════════════════
// Fmt — formatting helpers used across all screens
// Preserved exactly — DO NOT modify these methods
// ═══════════════════════════════════════════════════════════════════════════
class Fmt {
  /// Plain Indian rupee format — no K/L abbreviations
  /// ₹85,400  |  ₹1,22,600  |  ₹45,00,000
  static String amount(double v) {
    final rounded = v.toStringAsFixed(0);
    return '₹${_indianCommas(rounded)}';
  }

  static String _indianCommas(String n) {
    if (n.length <= 3) return n;
    // Last 3 digits, then groups of 2
    final last3 = n.substring(n.length - 3);
    final rest   = n.substring(0, n.length - 3);
    final buf    = StringBuffer();
    for (int i = 0; i < rest.length; i++) {
      if (i > 0 && (rest.length - i) % 2 == 0) buf.write(',');
      buf.write(rest[i]);
    }
    return '${buf.toString()},${last3}';
  }

  /// 760.5 → "760.5 kg"
  static String kg(double v) => '${v.toStringAsFixed(1)} kg';

  /// Parses "1.2L", "85K", "1000" → double
  static double? parseNum(String s) {
    final clean = s.trim().replaceAll(',', '');
    if (clean.isEmpty) return null;
    final upper = clean.toUpperCase();
    if (upper.endsWith('L')) {
      final n = double.tryParse(upper.replaceAll('L', ''));
      return n != null ? n * 100000 : null;
    }
    if (upper.endsWith('K')) {
      final n = double.tryParse(upper.replaceAll('K', ''));
      return n != null ? n * 1000 : null;
    }
    return double.tryParse(clean);
  }

  static int? parseInt(String s) => parseNum(s)?.round();
}
