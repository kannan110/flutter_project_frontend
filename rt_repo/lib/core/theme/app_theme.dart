// lib/core/theme/app_theme.dart
import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary    = Color(0xFF1B6B3A);
  static const Color secondary  = Color(0xFFE8A020);
  static const Color error      = Color(0xFFD32F2F);
  static const Color surface    = Color(0xFFF8FBF8);
  static const Color onPrimary  = Colors.white;

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          brightness: Brightness.light,
          primary: primary,
          secondary: secondary,
          error: error,
          surface: surface,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 1,
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF1C1C1E),
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1C1C1E),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          color: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF5F5F5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: primary, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: error),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(50),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
            textStyle: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: primary,
            minimumSize: const Size.fromHeight(50),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            side: const BorderSide(color: primary),
            textStyle: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          selectedItemColor: primary,
          unselectedItemColor: Color(0xFF9E9E9E),
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
          backgroundColor: Colors.white,
        ),
        dividerTheme:
            DividerThemeData(color: Colors.grey.shade100, space: 1),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          brightness: Brightness.dark,
          primary: const Color(0xFF4CAF82),
          secondary: secondary,
        ),
      );
}

class StatusColors {
  static Color forOrderStatus(String status) => switch (status) {
        'pending'           => const Color(0xFF9E9E9E),
        'confirmed'         => const Color(0xFF1976D2),
        'assigned'          => const Color(0xFF7B1FA2),
        'picked_up'         => const Color(0xFFE65100),
        'out_for_delivery'  => const Color(0xFFF57F17),
        'delivered'         => const Color(0xFF388E3C),
        'approved'          => const Color(0xFF1B5E20),
        'invoiced'          => const Color(0xFF1B6B3A),
        'cancelled'         => const Color(0xFFD32F2F),
        _                   => const Color(0xFF9E9E9E),
      };

  static Color forApprovalStatus(String status) => switch (status) {
        'pending'  => const Color(0xFFE65100),
        'approved' => const Color(0xFF388E3C),
        'rejected' => const Color(0xFFD32F2F),
        _          => const Color(0xFF9E9E9E),
      };

  static Color forShiftStatus(String status) => switch (status) {
        'open'      => const Color(0xFF1976D2),
        'closed'    => const Color(0xFF388E3C),
        'cancelled' => const Color(0xFFD32F2F),
        _           => const Color(0xFF9E9E9E),
      };
}
