import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/app_user.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import 'navigation_model.dart';

// ── Sidebar state ─────────────────────────────────────────────────────────────
final sidebarCollapsedProvider = StateProvider<bool>((ref) => false);

const double kSidebarWidth          = 200.0;
const double kSidebarCollapsedWidth = 60.0;

// ═════════════════════════════════════════════════════════════════════════════
// AppSidebar — Kirtwin-style dark sidebar, collapsible
// Dark #0F172A background, subtle section labels, icon+label nav items
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

  // Slate-900 color system (matches reference exactly)
  static const _bg       = Color(0xFF0F172A);
  static const _border   = Color(0xFF1E293B);
  static const _textSub  = Color(0xFF64748B);
  static const _textNav  = Color(0xFFCBD5E1);
  static const _activeBg = Color(0xFF1E293B);
  static const _activeFg = Color(0xFFFFFFFF);
  static const _gold     = Color(0xFFF59E0B);

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
      duration: const Duration(milliseconds: 220),
      curve:    Curves.easeInOut,
      width:    w,
      decoration: const BoxDecoration(
        color:  _bg,
        border: Border(right: BorderSide(color: _border)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ── Brand ─────────────────────────────────────────────────────────
        _Brand(collapsed: collapsed, onToggle: () =>
        ref.read(sidebarCollapsedProvider.notifier).state = !collapsed),

        // ── Nav items ─────────────────────────────────────────────────────
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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

        // ── Day status footer ──────────────────────────────────────────────
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
    height:      56,
    padding:     const EdgeInsets.symmetric(horizontal: 14),
    decoration:  const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B)))),
    child: Row(children: [
      // Logo mark
      Container(
        width: 30, height: 30,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(7),
        ),
        child: const Center(child: Text('🐓',
            style: TextStyle(fontSize: 16))),
      ),
      if (!collapsed) ...[
        const SizedBox(width: 10),
        Expanded(child: Column(
          mainAxisAlignment:  MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ROOSTER',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                    color: Colors.white, letterSpacing: 0.8)),
            const Text('Poultry Operations',
                style: TextStyle(fontSize: 10, color: Color(0xFF64748B),
                    fontWeight: FontWeight.w400)),
          ],
        )),
      ],
      // Collapse toggle
      GestureDetector(
        onTap: onToggle,
        child: Container(
          width: 24, height: 24,
          decoration: BoxDecoration(
              color:        const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(5)),
          child: Icon(
              collapsed ? Icons.chevron_right : Icons.chevron_left,
              size: 14, color: const Color(0xFF64748B)),
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
    padding: const EdgeInsets.fromLTRB(14, 18, 14, 4),
    child: Text(title,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
            color: Color(0xFF475569), letterSpacing: 0.8)),
  );
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();
  @override Widget build(BuildContext c) =>
      const Padding(padding: EdgeInsets.symmetric(vertical: 6),
          child: Divider(height: 1, color: Color(0xFF1E293B), indent: 12, endIndent: 12));
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
  @override State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hov = false;
  @override
  Widget build(BuildContext context) {
    final active  = widget.isActive;
    final hov     = _hov && !active;
    final c       = widget.collapsed;

    Widget row = Row(children: [
      SizedBox(width: c ? 60 : 14, child: Icon(
        active ? widget.item.activeIcon : widget.item.icon,
        size:  18,
        color: active ? Colors.white
            : hov  ? const Color(0xFFCBD5E1)
            :         const Color(0xFF64748B),
      )),
      if (!c) ...[
        Expanded(child: Text(widget.item.label,
            style: TextStyle(
              fontSize:   13,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color:      active ? Colors.white
                  : hov  ? const Color(0xFFCBD5E1)
                  :         const Color(0xFF94A3B8),
            ),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (widget.item.badge != null && widget.item.badge! > 0)
          _Badge(widget.item.badge!, active: active),
        const SizedBox(width: 10),
      ],
    ]);

    if (c) {
      row = Tooltip(message: widget.item.label,
          preferBelow: false,
          child: SizedBox(width: 60, child: Center(child: row)));
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit:  (_) => setState(() => _hov = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          padding: EdgeInsets.symmetric(
              horizontal: c ? 0 : 8, vertical: 7),
          decoration: BoxDecoration(
            color:        active ? const Color(0xFF1E293B)
                : hov  ? const Color(0xFF1E293B).withValues(alpha: 0.5)
                :         Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: active ? Border.all(
                color: const Color(0xFF334155), width: 0.5) : null,
          ),
          child: row,
        ),
      ),
    );
  }

  bool get collapsed => widget.collapsed;
}

// ── Badge ─────────────────────────────────────────────────────────────────────
class _Badge extends StatelessWidget {
  const _Badge(this.count, {required this.active});
  final int count; final bool active;
  @override
  Widget build(BuildContext c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
        color:        active ? const Color(0xFFF59E0B) : const Color(0xFFDC2626),
        borderRadius: BorderRadius.circular(99)),
    child: Text(count > 99 ? '99+' : '$count',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
            color: active ? const Color(0xFF0F172A) : Colors.white)),
  );
}

// ── Footer ────────────────────────────────────────────────────────────────────
class _Footer extends StatelessWidget {
  const _Footer({required this.user, required this.collapsed,
    required this.onSignOut});
  final AppUser? user;
  final bool collapsed;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF1E293B)))),
    child: collapsed
        ? GestureDetector(
      onTap:   onSignOut,
      child:   const SizedBox(width: 36, height: 36,
          child: Center(child: Icon(Icons.logout_rounded,
              size: 18, color: Color(0xFF64748B)))),
    )
        : Row(children: [
      // Avatar
      Container(width: 30, height: 30,
          decoration: BoxDecoration(
              color: const Color(0xFF1E293B), shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF334155))),
          child: Center(child: Text(
              _initials(user?.companyName),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: Color(0xFFF59E0B))))),
      const SizedBox(width: 8),
      Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize:       MainAxisSize.min,
          children: [
            Text(user?.companyName ?? 'Trader',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: Colors.white),
                overflow: TextOverflow.ellipsis, maxLines: 1),
            Text(user?.role.label ?? 'Owner',
                style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
          ])),
      GestureDetector(onTap: onSignOut,
          child: const Icon(Icons.logout_rounded,
              size: 16, color: Color(0xFF64748B))),
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