import 'package:flutter/material.dart';
import 'app_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// WEB DESIGN TOKENS
// Minimal-UI / MUI style layout on the Rooster navy + gold brand.
// Every web (desktop / tablet) widget reads from here — never hardcode a
// colour, radius or spacing value in a screen.
// ═══════════════════════════════════════════════════════════════════════════

// ── Colours ─────────────────────────────────────────────────────────────────
class WebColors {
  WebColors._();

  // Brand
  static const navy      = kNavy;              // primary (buttons, active text)
  static const navyMid   = kNavyMid;
  static const navySoft  = Color(0xFFEEF1F7);  // navy tint (selected rows, pills)
  static const gold      = kGold;              // accent
  static const goldLight = kGoldLight;
  static const goldSoft  = Color(0xFFFBF5E9);  // gold tint

  // Neutrals (Tailwind slate)
  static const pageBg    = Color(0xFFF8FAFC);
  static const surface   = Color(0xFFFFFFFF);
  static const surfaceAlt= Color(0xFFF8FAFC);  // table header, inset boxes
  static const border    = Color(0xFFE2E8F0);
  static const divider   = Color(0xFFF1F5F9);
  static const hover     = Color(0xFFF8FAFC);
  static const text1     = Color(0xFF0F172A);
  static const text2     = Color(0xFF475569);
  static const text3     = Color(0xFF94A3B8);

  // Semantic
  static const success   = Color(0xFF059669);
  static const successBg = Color(0xFFECFDF5);
  static const warning   = Color(0xFFD97706);
  static const warningBg = Color(0xFFFFFBEB);
  static const error     = Color(0xFFDC2626);
  static const errorBg   = Color(0xFFFEF2F2);
  static const info      = Color(0xFF2563EB);
  static const infoBg    = Color(0xFFEFF6FF);

  // Sidebar (white, navy + gold accents)
  static const sideBg        = Color(0xFFFFFFFF);
  static const sideBorder    = Color(0xFFE2E8F0);
  static const sideLabel     = Color(0xFF94A3B8);  // section small-caps
  static const sideText      = Color(0xFF475569);
  static const sideTextActive= kNavy;
  static const sideItemActive= Color(0xFFFBF5E9);  // soft gold tint
  static const sideTile      = Color(0xFFF1F5F9);
}

// ── Spacing ─────────────────────────────────────────────────────────────────
class WebSpace {
  WebSpace._();
  static const double xs  = 4;
  static const double sm  = 8;
  static const double md  = 12;
  static const double lg  = 16;
  static const double xl  = 24;
  static const double xxl = 32;
  static const double x3l = 48;

  /// Padding around page content inside the shell.
  static const page = EdgeInsets.fromLTRB(16, 16, 16, 24);
}

// ── Radius — one value per element type (no drift between screens) ───────
class WebRadius {
  WebRadius._();
  static const double label  = 6;   // status labels / chips
  static const double sm     = 8;   // inputs, small buttons, inset boxes
  static const double button = 10;  // buttons
  static const double card   = 16;  // cards, panels, list cards
  static const double dialog = 16;  // dialogs
}

// ── Sizes ───────────────────────────────────────────────────────────────────
class WebSize {
  WebSize._();
  static const double sidebar          = 220;
  static const double sidebarCollapsed = 64;
  static const double topbar           = 64;
  static const double maxContent       = 1400;
  static const double maxForm          = 960;
  static const double tableMinWidth    = 960;
  static const double filtersDrawer    = 300;

  // Dialog widths — use these instead of ad-hoc numbers
  static const double dialogSm = 400;
  static const double dialogMd = 480;
  static const double dialogLg = 640;
}

// ── Shadows ─────────────────────────────────────────────────────────────────
class WebShadow {
  WebShadow._();
  static const card = [
    BoxShadow(color: Color(0x0A0F172A), blurRadius: 2, offset: Offset(0, 0)),
    BoxShadow(color: Color(0x0F0F172A), blurRadius: 16, offset: Offset(0, 4),
        spreadRadius: -4),
  ];
  static const raised = [
    BoxShadow(color: Color(0x140F172A), blurRadius: 24, offset: Offset(0, 8),
        spreadRadius: -4),
  ];
  static const drawer = [
    BoxShadow(color: Color(0x290F172A), blurRadius: 40, offset: Offset(-8, 0)),
  ];
}

// ── Text styles ─────────────────────────────────────────────────────────────
class WebText {
  WebText._();
  static const pageTitle = TextStyle(fontSize: 24, fontWeight: FontWeight.w800,
      color: WebColors.text1, letterSpacing: -0.4, height: 1.25);
  static const cardTitle = TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
      color: WebColors.text1, letterSpacing: -0.1);
  static const cardSubtitle = TextStyle(fontSize: 12.5,
      color: WebColors.text3, fontWeight: FontWeight.w500);
  static const body = TextStyle(fontSize: 13.5, color: WebColors.text1);
  static const bodySub = TextStyle(fontSize: 12.5, color: WebColors.text2);
  static const caption = TextStyle(fontSize: 12, color: WebColors.text3);
  static const tableHead = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700,
      color: WebColors.text2);
  static const kpiValue = TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
      color: WebColors.text1, letterSpacing: -0.5, height: 1.15);
}

// ── Common decorations ──────────────────────────────────────────────────────
class WebDecor {
  WebDecor._();
  static BoxDecoration card({Color? color}) => BoxDecoration(
    color:        color ?? WebColors.surface,
    borderRadius: BorderRadius.circular(WebRadius.card),
    border:       Border.all(color: WebColors.border),
    boxShadow:    WebShadow.card,
  );
  static BoxDecoration inset() => BoxDecoration(
    color:        WebColors.surfaceAlt,
    borderRadius: BorderRadius.circular(WebRadius.sm),
    border:       Border.all(color: WebColors.border),
  );
}
