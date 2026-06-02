import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/app_user.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import 'navigation_model.dart';

// ── Sidebar dimensions ────────────────────────────────────────────────────
const double kSidebarWidth         = 256.0;
const double kSidebarCollapsedWidth = 64.0;

// ── AppSidebar ─────────────────────────────────────────────────────────────
// Deep Navy background, Gold active icons — Elite Enterprise Poultry style
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user     = ref.watch(appUserProvider).valueOrNull;
    final loc      = GoRouterState.of(context).matchedLocation;
    final sections = TraderNavigation.sidebarSections(
      pendingApprovals: pendingApprovals,
      unreadAlerts:     unreadAlerts,
      pendingOrders:    pendingOrders,
    );
    final activeRoute = activeSidebarRoute(loc, sections);

    return Container(
      width: kSidebarWidth,
      color: kSidebarBg, // Deep Navy
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Brand ─────────────────────────────────────────────────────
          _SidebarBrand(user: user),

          // ── Nav items ─────────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final section in sections) ...[
                  if (section.title != null)
                    _SectionLabel(section.title!),
                  for (final item in section.items)
                    _SidebarItem(
                      item:     item,
                      isActive: activeRoute == item.route,
                      onTap:    () => context.go(item.route),
                    ),
                  if (section.title != null)
                    const SizedBox(height: 4),
                ],
              ],
            ),
          ),

          // ── Footer ────────────────────────────────────────────────────
          _SidebarFooter(user: user, ref: ref),
        ],
      ),
    );
  }
}

// ── Brand header ──────────────────────────────────────────────────────────
class _SidebarBrand extends StatelessWidget {
  const _SidebarBrand({required this.user});
  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        // Navy-on-Navy with subtle gold bottom border
        color:  kNavyMid,
        border: Border(bottom: BorderSide(color: kGold.withValues(alpha: 0.3))),
      ),
      child: Row(
        children: [
          // Gold-bordered logo mark
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [kGold, kGoldLight],
                begin: Alignment.topLeft,
                end:   Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Center(
              child: Text('🐓', style: TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment:  MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ROOSTER OS',
                  style: TextStyle(
                    fontSize:      12,
                    fontWeight:    FontWeight.w800,
                    color:         kGoldLight,
                    letterSpacing: 1.5,
                  ),
                ),
                if (user?.companyName != null)
                  Text(
                    user!.companyName!,
                    style: const TextStyle(
                      fontSize:   13,
                      fontWeight: FontWeight.w500,
                      color:      kSidebarText,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      title,
      style: const TextStyle(
        fontSize:      9,
        fontWeight:    FontWeight.w800,
        color:         kNavyLight,
        letterSpacing: 1.4,
      ),
    ),
  );
}

// ── Nav item ──────────────────────────────────────────────────────────────
class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.item,
    required this.isActive,
    required this.onTap,
  });
  final NavItem      item;
  final bool         isActive;
  final VoidCallback onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active  = widget.isActive;
    final hovered = _hovered;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: Material(
          color: active
              ? kNavyMid
              : hovered
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            onTap:        widget.onTap,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: active
                  ? BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border(
                  left: BorderSide(color: kGold, width: 3),
                ),
              )
                  : null,
              child: Row(children: [
                Icon(
                  active ? widget.item.activeIcon : widget.item.icon,
                  size:  18,
                  color: active ? kGoldLight : kSidebarText,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.item.label,
                    style: TextStyle(
                      fontSize:   13,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color:      active ? Colors.white : kSidebarText,
                    ),
                  ),
                ),
                if (widget.item.badge != null && widget.item.badge! > 0)
                  _Badge(widget.item.badge!, isActive: active),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Badge ─────────────────────────────────────────────────────────────────
class _Badge extends StatelessWidget {
  const _Badge(this.count, {required this.isActive});
  final int  count;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color:        isActive ? kGold : kError,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize:   9,
          fontWeight: FontWeight.w800,
          color:      isActive ? kNavy : Colors.white,
        ),
      ),
    );
  }
}

// ── Footer ────────────────────────────────────────────────────────────────
class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter({required this.user, required this.ref});
  final AppUser? user;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:  kNavyMid,
        border: Border(top: BorderSide(color: kGold.withValues(alpha: 0.2))),
      ),
      child: Row(children: [
        // Gold avatar ring
        Container(
          width:  38, height: 38,
          decoration: BoxDecoration(
            color:        kNavy,
            shape:        BoxShape.circle,
            border: Border.all(color: kGold, width: 1.5),
          ),
          child: Center(
            child: Text(
              _initials(user?.companyName),
              style: const TextStyle(
                fontSize:   13,
                fontWeight: FontWeight.w800,
                color:      kGoldLight,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize:       MainAxisSize.min,
            children: [
              Text(
                user?.companyName ?? 'Trader',
                style: const TextStyle(
                  fontSize:   12,
                  fontWeight: FontWeight.w700,
                  color:      Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              Text(
                user?.role.label ?? '',
                style: const TextStyle(
                    fontSize: 10, color: kSidebarText),
              ),
            ],
          ),
        ),
        // Sign out
        IconButton(
          icon:          const Icon(Icons.logout_rounded, size: 18),
          color:         kNavyLight,
          tooltip:       'Sign out',
          onPressed:     () => _confirmSignOut(context, ref),
          padding:       EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        ),
      ]),
    );
  }

  String _initials(String? name) {
    if (name == null || name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context:          context,
      useRootNavigator: true,
      builder: (c) => AlertDialog(
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8))),
        title: const Text('Sign out?',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        content: const Text('You will be returned to the login screen.',
            style: TextStyle(fontSize: 15, color: kTextSub)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c, rootNavigator: true).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: kTextSub, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.of(c, rootNavigator: true).pop(true),
            child: const Text('Sign out',
                style: TextStyle(color: kError, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    ) ?? false;

    if (ok) ref.read(appUserProvider.notifier).signOut();
  }
}