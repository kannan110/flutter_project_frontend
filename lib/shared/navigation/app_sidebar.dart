import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/app_user.dart';
import '../../core/providers/session_provider.dart';
import 'navigation_model.dart';

// ── Sidebar state ─────────────────────────────────────────────────────────────
final sidebarCollapsedProvider = StateProvider<bool>((ref) => false);

const double kSidebarWidth          = 220.0;
const double kSidebarCollapsedWidth = 64.0;

// ═════════════════════════════════════════════════════════════════════════════
// AppSidebar
// ═════════════════════════════════════════════════════════════════════════════
class AppSidebar extends ConsumerWidget {
  const AppSidebar({
    super.key,
    this.pendingApprovals = 0,
    this.unreadAlerts     = 0,
    this.pendingOrders    = 0,
  });

  final int pendingApprovals;
  final int unreadAlerts;
  final int pendingOrders;

  // ── Colour tokens ──────────────────────────────────────────────────────────
  static const _bg          = Color(0xFF0D1117);  // slightly deeper — better contrast
  static const _bgHover     = Color(0xFF161B22);  // hover surface
  static const _bgActive    = Color(0xFF1C2331);  // active surface
  static const _border      = Color(0xFF21262D);  // subtle borders
  static const _textLabel   = Color(0xFF8B949E);  // section labels
  static const _textInactive= Color(0xFFB0BEC5);  // ↑ brighter — was 94A3B8
  static const _textActive  = Color(0xFFFFFFFF);
  static const _gold        = Color(0xFFF59E0B);
  static const _goldDim     = Color(0xFF92600A);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collapsed = ref.watch(sidebarCollapsedProvider);
    final user      = ref.watch(appUserProvider).valueOrNull;
    final loc       = GoRouterState.of(context).matchedLocation;
    final sections  = TraderNavigation.sidebarSections(
      pendingApprovals: pendingApprovals,
      unreadAlerts:     unreadAlerts,
      pendingOrders:    pendingOrders,
    );
    final activeRoute = activeSidebarRoute(loc, sections);
    final w = collapsed ? kSidebarCollapsedWidth : kSidebarWidth;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve:    Curves.easeInOut,
      width:    w,
      decoration: BoxDecoration(
        color:  _bg,
        border: Border(right: BorderSide(color: _border, width: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _Brand(collapsed: collapsed, onToggle: () =>
        ref.read(sidebarCollapsedProvider.notifier).state = !collapsed),

        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(0, 6, 0, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final section in sections) ...[
              if (section.title != null && !collapsed)
                _SectionLabel(section.title!),
              if (section.title != null && collapsed)
                const _SectionDivider(),
              for (final item in section.items)
                _NavItem(
                  item:      item,
                  isActive:  activeRoute == item.route,
                  collapsed: collapsed,
                  onTap:     () => context.go(item.route),
                ),
            ],
          ]),
        )),

        _Footer(user: user, collapsed: collapsed,
            onSignOut: () => ref.read(appUserProvider.notifier).signOut()),
      ]),
    );
  }
}

// ── Brand header ──────────────────────────────────────────────────────────────
class _Brand extends StatelessWidget {
  const _Brand({required this.collapsed, required this.onToggle});
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Container(
    height:     60,
    padding:    EdgeInsets.symmetric(horizontal: collapsed ? 12 : 14),
    decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF21262D), width: 0.5))),
    child: Row(children: [
      // Logo mark
      Container(
        width: 38, height: 34,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(9),
          boxShadow: [BoxShadow(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.25),
              blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: const Center(child: Text('🐓', style: TextStyle(fontSize: 18))),
      ),
      if (!collapsed) ...[
      const SizedBox(width: 14),
      Expanded(child: Column(
        mainAxisAlignment:  MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text('ROOSTER',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900,
                  color: Colors.white, letterSpacing: 1.0)),
          SizedBox(height: 1),
          Text('Poultry Operations',
              style: TextStyle(fontSize: 10, color: Color(0xFF8B949E),
                  fontWeight: FontWeight.w400)),
        ],
      )),
    ],
        // Collapse toggle
        GestureDetector(
          onTap: onToggle,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                  color:        const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(6),
                  border:       Border.all(color: const Color(0xFF30363D), width: 0.5)),
              child: Icon(
                  collapsed ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
                  size: 16, color: const Color(0xFF8B949E)),
            ),
          ),
        ),
        ]),
  );
}

// ── Section label ─────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);
  final String title;
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(title,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
            color: Color(0xFF8B949E), letterSpacing: 0.9)),
  );
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();
  @override
  Widget build(BuildContext c) => const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Divider(height: 1, color: Color(0xFF21262D), indent: 14, endIndent: 14));
}

// ── Nav item ──────────────────────────────────────────────────────────────────
class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.item,
    required this.isActive,
    required this.collapsed,
    required this.onTap,
  });
  final NavItem      item;
  final bool         isActive;
  final bool         collapsed;
  final VoidCallback onTap;
  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hov = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isActive;
    final hov    = _hov && !active;
    final c      = widget.collapsed;

    // ── Icon + label row ────────────────────────────────────────────────────
    Widget row;

    if (c) {
      // Collapsed: icon centred with tooltip
      row = Tooltip(
        message:    widget.item.label,
        preferBelow: false,
        decoration: BoxDecoration(
            color: const Color(0xFF1C2331),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF30363D), width: 0.5)),
        textStyle: const TextStyle(
            fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500),
        child: SizedBox(
          width: kSidebarCollapsedWidth,
          child: Center(child: Stack(clipBehavior: Clip.none, children: [
            Icon(active ? widget.item.activeIcon : widget.item.icon,
                size: 20,
                color: active ? const Color(0xFFF59E0B)
                    : hov  ? const Color(0xFFB0BEC5)
                    :         const Color(0xFF6E7681)),
            // Small badge dot when collapsed
            if (widget.item.badge != null && widget.item.badge! > 0)
              Positioned(top: -3, right: -6,
                  child: Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(
                        color: Color(0xFFDC2626),
                        shape: BoxShape.circle),
                  )),
          ])),
        ),
      );
    } else {
      // Expanded: icon + gap + label + badge
      row = Row(children: [
        // Fixed-width icon zone — 40px gives breathing room
        SizedBox(width: 40,
          child: Center(child: Icon(
            active ? widget.item.activeIcon : widget.item.icon,
            size:  18,
            color: active ? const Color(0xFFF59E0B)
                : hov  ? const Color(0xFFB0BEC5)
                :         const Color(0xFF6E7681),
          )),
        ),
        // Label
        Expanded(child: Text(widget.item.label,
            style: TextStyle(
              fontSize:   13,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color:      active ? Colors.white
                  : hov  ? const Color(0xFFB0BEC5)
                  :         const Color(0xFFB0BEC5),
              letterSpacing: -0.1,
            ),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
        // Badge
        if (widget.item.badge != null && widget.item.badge! > 0) ...[
          _Badge(widget.item.badge!, active: active),
          const SizedBox(width: 8),
        ],
      ]);
    }

    // ── Container with left gold accent when active ─────────────────────────
    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit:  (_) => setState(() => _hov = false),
      cursor:  SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: EdgeInsets.symmetric(
              horizontal: c ? 6 : 8, vertical: 1.5),
          padding: EdgeInsets.symmetric(
              horizontal: c ? 0 : 0,
              vertical: 9),                       // ↑ was 7 — taller tap target
          decoration: BoxDecoration(
            color:        active ? const Color(0xFF1C2331)
                : hov  ? const Color(0xFF161B22)
                :         Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            border: active
                ? Border.all(color: const Color(0xFF30363D), width: 0.5)
                : null,
          ),
          child: c
              ? row  // collapsed: just the icon row
              : Stack(children: [
            // Gold left accent bar on active item
            if (active) Positioned(left: 0, top: 6, bottom: 6,
              child: Container(
                width: 3,
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Indent the row to make room for the accent bar
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: row,
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Badge ─────────────────────────────────────────────────────────────────────
class _Badge extends StatelessWidget {
  const _Badge(this.count, {required this.active});
  final int count;
  final bool active;

  @override
  Widget build(BuildContext c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
        color:        active ? const Color(0xFFF59E0B) : const Color(0xFFDC2626),
        borderRadius: BorderRadius.circular(99)),
    child: Text(count > 99 ? '99+' : '$count',
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700,
            color: active ? const Color(0xFF0D1117) : Colors.white)),
  );
}

// ── Footer ────────────────────────────────────────────────────────────────────
class _Footer extends StatelessWidget {
  const _Footer({
    required this.user,
    required this.collapsed,
    required this.onSignOut,
  });
  final AppUser?     user;
  final bool         collapsed;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(collapsed ? 10 : 12),
    decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF21262D), width: 0.5))),
    child: collapsed
        ? MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onSignOut,
        child: Center(
          child: Tooltip(
            message: 'Sign out',
            child: Icon(Icons.logout_rounded,
                size: 18, color: const Color(0xFF6E7681)),
          ),
        ),
      ),
    )
        : Row(children: [
      // Avatar
      Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF1C2331), Color(0xFF161B22)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF30363D), width: 0.5)),
          child: Center(child: Text(
              _initials(user?.companyName),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                  color: Color(0xFFF59E0B))))),
      const SizedBox(width: 10),
      Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize:       MainAxisSize.min,
          children: [
            Text(user?.companyName ?? 'Trader',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: Colors.white),
                overflow: TextOverflow.ellipsis, maxLines: 1),
            const SizedBox(height: 1),
            Text(user?.role.label ?? 'Owner',
                style: const TextStyle(fontSize: 10, color: Color(0xFF8B949E))),
          ])),
      MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onSignOut,
          child: Tooltip(
            message: 'Sign out',
            child: Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                  color:        const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(6),
                  border:       Border.all(color: const Color(0xFF30363D), width: 0.5)),
              child: const Icon(Icons.logout_rounded,
                  size: 14, color: Color(0xFF6E7681)),
            ),
          ),
        ),
      ),
    ]),
  );

  String _initials(String? n) {
    if (n == null || n.isEmpty) return '?';
    final p = n.trim().split(' ');
    return p.length >= 2
        ? '${p[0][0]}${p[1][0]}'.toUpperCase()
        : n[0].toUpperCase();
  }
}