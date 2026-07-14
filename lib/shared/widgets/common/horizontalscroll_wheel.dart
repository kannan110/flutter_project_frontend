import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SHARED HORIZONTAL SCROLL SOLUTION
//
// Problem: on Flutter Web/Desktop, a horizontally-scrolling widget
// (SingleChildScrollView/ListView with scrollDirection: Axis.horizontal)
// does not respond to a plain mouse wheel or a trackpad's vertical swipe.
// Flutter only ever applies a wheel event's `scrollDelta.dx` to a horizontal
// scrollable by default — but most mice only ever emit `dy`, and most
// trackpad "scroll" gestures (as opposed to an explicit horizontal swipe)
// also arrive as `dy`. There is no built-in flag for this; it requires
// intercepting the pointer-scroll event and forwarding it manually.
//
// This file is the ONE place that fixes it, reused everywhere instead of a
// per-screen hack:
//   1. `isDesktopOrWeb`         — platform check (not screen-width based;
//                                 mobile/tablet OS builds are never affected,
//                                 even at a wide tablet resolution).
//   2. `AppScrollBehavior`      — registered once on MaterialApp. Enables
//                                 mouse/trackpad click-and-drag scrolling on
//                                 every Scrollable app-wide.
//   3. `HorizontalScrollWheel`  — a thin wrapper around an EXISTING
//                                 SingleChildScrollView/ListView. Give it the
//                                 same ScrollController your scrollable
//                                 already uses; it adds wheel-to-horizontal
//                                 forwarding and (on Web/Desktop only) a
//                                 visible, draggable scrollbar thumb.
//
// Touch never emits PointerScrollEvent, so wrapping a widget in
// HorizontalScrollWheel is a no-op on mobile/tablet drag-to-scroll — nothing
// about existing touch behavior changes.
// ─────────────────────────────────────────────────────────────────────────────

/// True for Flutter Web and native desktop builds (macOS/Windows/Linux).
/// False for Android/iOS regardless of screen size — a large tablet should
/// still behave like a touch device, not like a desktop.
bool get isDesktopOrWeb =>
    kIsWeb ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;

/// App-wide ScrollBehavior — register once via `MaterialApp(scrollBehavior:
/// const AppScrollBehavior())`. Adds mouse/trackpad as drag devices for every
/// Scrollable (vertical and horizontal alike), so click-and-drag scrolling
/// works everywhere without touching individual screens. Touch remains a
/// drag device as before, so mobile/tablet is unaffected.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.unknown,
  };
}

/// Drop-in wrapper for an existing horizontally-scrolling widget. Pass the
/// SAME `ScrollController` your `SingleChildScrollView`/`ListView` already
/// uses (create one if the call site didn't have one before).
///
/// Example — before:
///   SingleChildScrollView(scrollDirection: Axis.horizontal, child: row)
///
/// After:
///   HorizontalScrollWheel(
///     controller: _hCtrl,
///     child: SingleChildScrollView(
///       controller: _hCtrl,
///       scrollDirection: Axis.horizontal,
///       child: row,
///     ),
///   )
class HorizontalScrollWheel extends StatelessWidget {
  const HorizontalScrollWheel({
    super.key,
    required this.controller,
    required this.child,
    this.showScrollbar = true,
  });

  /// Must be the same controller attached to the wrapped scrollable.
  final ScrollController controller;
  final Widget child;

  /// Shows a persistent, draggable scrollbar thumb on Web/Desktop only.
  /// Ignored on mobile/tablet — set false to opt a given screen out
  /// entirely (e.g. a purely decorative chip strip).
  final bool showScrollbar;

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!controller.hasClients) return;
    // Prefer the vertical wheel delta (the common mouse-wheel case); fall
    // back to the horizontal delta for trackpads that already emit dx for
    // a genuine horizontal two-finger swipe.
    final delta = event.scrollDelta.dy.abs() > event.scrollDelta.dx.abs()
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    final pos = controller.position;
    final target = (pos.pixels + delta)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    controller.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    Widget result = child;

    if (showScrollbar && isDesktopOrWeb) {
      result = Scrollbar(
        controller: controller,
        thumbVisibility: true,
        trackVisibility: true,
        child: result,
      );
    }

    return Listener(
      onPointerSignal: _onPointerSignal,
      child: result,
    );
  }
}