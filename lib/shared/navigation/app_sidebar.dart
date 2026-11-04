import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/models/app_user.dart';
import '../../core/providers/session_provider.dart';
import '../../core/theme/web_tokens.dart';
import '../widgets/web/web_dialogs.dart';
import 'navigation_model.dart';

// ── Sidebar state ─────────────────────────────────────────────────────────────
final sidebarCollapsedProvider = StateProvider<bool>((ref) => false);

const double kSidebarWidth          = WebSize.sidebar;
const double kSidebarCollapsedWidth = WebSize.sidebarCollapsed;

const _kPrefKey = 'web_sidebar_collapsed';

/// Toggle the sidebar and remember the choice across reloads.
void toggleSidebar(WidgetRef ref) {
  final next = !ref.read(sidebarCollapsedProvider);
  ref.read(sidebarCollapsedProvider.notifier).state = next;
  SharedPreferences.getInstance()
      .then((p) => p.setBool(_kPrefKey, next))
      .catchError((_) => false);
}

// ═════════════════════════════════════════════════════════════════════════════
// AppSidebar — navy brand sidebar (Minimal-UI layout)
// ═════════════════════════════════════════════════════════════════════════════
class AppSidebar extends ConsumerStatefulWidget {
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
  ConsumerState<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends ConsumerState<AppSidebar> {
  String? _openGroup;
  String? _lastActiveRoute;

  static String _groupTitle(String t) =>
      t[0].toUpperCase() + t.substring(1).toLowerCase();

  static IconData _groupIcon(String t) => switch (t) {
    'OPERATIONS' => Icons.local_shipping_outlined,
    'FINANCE'    => Icons.account_balance_wallet_outlined,
    'PEOPLE'     => Icons.groups_outlined,
    'TRACKING'   => Icons.track_changes_outlined,
    'INSIGHTS'   => Icons.insights_outlined,
    'ACCOUNT'    => Icons.manage_accounts_outlined,
    _            => Icons.folder_outlined,
  };

  @override
  void initState() {
    super.initState();
    // Restore the saved collapsed state once (shell is mounted once).
    SharedPreferences.getInstance().then((p) {
      final saved = p.getBool(_kPrefKey);
      if (saved != null && mounted &&
          saved != ref.read(sidebarCollapsedProvider)) {
        ref.read(sidebarCollapsedProvider.notifier).state = saved;
      }
    }).catchError((_) {});
  }

  Future<void> _confirmSignOut() async {
    final ok = await WebConfirmDialog.show(
      context,
      title: 'Sign out?',
      message: 'You will need to sign in again to continue.',
      confirmLabel: 'Sign out',
      icon: Icons.logout_rounded,
      destructive: true,
    );
    if (ok) ref.read(appUserProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final collapsed = ref.watch(sidebarCollapsedProvider);
    final user      = ref.watch(appUserProvider).valueOrNull;
    final loc       = GoRouterState.of(context).matchedLocation;
    final sections  = TraderNavigation.sidebarSections(
      pendingApprovals: widget.pendingApprovals,
      unreadAlerts:     widget.unreadAlerts,
      pendingOrders:    widget.pendingOrders,
    );
    final activeRoute = activeSidebarRoute(loc, sections);
    final w = collapsed ? kSidebarCollapsedWidth : kSidebarWidth;

    // When the page changes, open the group that holds it (one open at a time)
    if (activeRoute != _lastActiveRoute) {
      _lastActiveRoute = activeRoute;
      for (final s in sections) {
        if (s.title != null && s.items.any((i) => i.route == activeRoute)) {
          _openGroup = s.title;
        }
      }
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve:    Curves.easeInOut,
      width:    w,
      decoration: const BoxDecoration(
        color:  WebColors.sideBg,
        border: Border(right: BorderSide(color: WebColors.sideBorder)),
      ),
      child: ClipRect(child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: w, maxWidth: w,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Brand(collapsed: collapsed, onExpand: () => toggleSidebar(ref)),

          Expanded(child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                collapsed ? 8 : 10, 6, collapsed ? 8 : 10, 12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final section in sections)
                // Untitled section (Dashboard) and the collapsed icon strip
                // show items flat; titled sections become accordion groups.
                if (section.title == null || collapsed) ...[
                  if (section.title != null) const _SectionDivider(),
                  for (final item in section.items)
                    _NavItem(
                      key:       ValueKey(item.route),
                      item:      item,
                      isActive:  activeRoute == item.route,
                      collapsed: collapsed,
                      onTap:     () => context.go(item.route),
                    ),
                ] else
                  _NavGroup(
                    key:         ValueKey(section.title),
                    title:       _groupTitle(section.title!),
                    icon:        _groupIcon(section.title!),
                    items:       section.items,
                    activeRoute: activeRoute,
                    open:        _openGroup == section.title,
                    onToggle:    () => setState(() => _openGroup =
                        _openGroup == section.title ? null : section.title),
                    onTapItem:   (r) => context.go(r),
                  ),
            ]),
          )),

          _Footer(user: user, collapsed: collapsed, onSignOut: _confirmSignOut),
        ]),
      )),
    );
  }
}

// ── Round chevron toggle that sits on the sidebar's right edge ───────────────
// Placed by DesktopShell in a Stack so it can overlap the content edge.
class SidebarEdgeToggle extends ConsumerWidget {
  const SidebarEdgeToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collapsed = ref.watch(sidebarCollapsedProvider);
    return Tooltip(
      message: collapsed ? 'Expand sidebar' : 'Collapse sidebar',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => toggleSidebar(ref),
          child: Container(
            width: 26, height: 26,
            decoration: BoxDecoration(
              color: WebColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: WebColors.border),
              boxShadow: WebShadow.card,
            ),
            child: Icon(
              collapsed ? Icons.chevron_right_rounded
                        : Icons.chevron_left_rounded,
              size: 16, color: WebColors.text2),
          ),
        ),
      ),
    );
  }
}

// ── Brand header ──────────────────────────────────────────────────────────────
class _Brand extends StatelessWidget {
  const _Brand({required this.collapsed, required this.onExpand});
  final bool collapsed;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final logo = Container(
      width: 38,
      height: 38,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: WebColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: WebColors.sideBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Image.asset(
        'assets/images/app_icon.png',
        fit: BoxFit.contain,
      ),
    );

    return Container(
      height: WebSize.topbar,
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: WebColors.sideBorder))),
      child: collapsed
          // Collapsed: only the logo — clicking it expands the sidebar
          ? Center(child: Tooltip(
              message: 'Expand sidebar',
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(onTap: onExpand, child: logo),
              ),
            ))
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                logo,
                const SizedBox(width: 12),
                const Expanded(child: Column(
                  mainAxisAlignment:  MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ROOSTER',
                        style: TextStyle(fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                            color: WebColors.navy,
                            letterSpacing: 1.1,
                            height: 1.15)),
                    SizedBox(height: 2),
                    Text('Poultry Operations',
                        style: TextStyle(fontSize: 10.5,
                            color: WebColors.text3,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.1)),
                  ],
                )),
              ]),
            ),
    );
  }
}

// ── Collapsible nav group (accordion) ─────────────────────────────────────────
class _NavGroup extends StatefulWidget {
  const _NavGroup({
    super.key,
    required this.title,
    required this.icon,
    required this.items,
    required this.activeRoute,
    required this.open,
    required this.onToggle,
    required this.onTapItem,
  });
  final String              title;
  final IconData            icon;
  final List<NavItem>       items;
  final String?             activeRoute;
  final bool                open;
  final VoidCallback        onToggle;
  final ValueChanged<String> onTapItem;

  @override
  State<_NavGroup> createState() => _NavGroupState();
}

class _NavGroupState extends State<_NavGroup> {
  bool _hov = false;

  @override
  Widget build(BuildContext context) {
    final hasActive = widget.items.any((i) => i.route == widget.activeRoute);
    // Closed group still shows its items' badge total so nothing is hidden
    final badgeSum = widget.items.fold<int>(0, (s, i) => s + (i.badge ?? 0));
    final fg = hasActive ? WebColors.navy
        : _hov ? WebColors.text1 : WebColors.sideText;

    final header = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hov = true),
      onExit:  (_) => setState(() => _hov = false),
      child: GestureDetector(
        onTap: widget.onToggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 38,
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Icon(widget.icon, size: 18, color: fg),
            const SizedBox(width: 10),
            Expanded(child: Text(widget.title,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13,
                    fontWeight: hasActive ? FontWeight.w700 : FontWeight.w600,
                    color: fg))),
            if (!widget.open && badgeSum > 0) ...[
              _Badge(badgeSum, active: false),
              const SizedBox(width: 6),
            ],
            AnimatedRotation(
              turns: widget.open ? 0.25 : 0,
              duration: const Duration(milliseconds: 180),
              child: Icon(Icons.chevron_right_rounded, size: 18,
                  color: hasActive ? WebColors.navy : WebColors.text3),
            ),
          ]),
        ),
      ),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      header,
      ClipRect(child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: widget.open
            ? Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final item in widget.items)
                      _ChildItem(
                        key: ValueKey(item.route),
                        item: item,
                        active: item.route == widget.activeRoute,
                        onTap: () => widget.onTapItem(item.route),
                      ),
                  ],
                ),
              )
            : const SizedBox(width: double.infinity),
      )),
    ]);
  }
}

class _ChildItem extends StatefulWidget {
  const _ChildItem({super.key, required this.item, required this.active,
    required this.onTap});
  final NavItem item;
  final bool active;
  final VoidCallback onTap;
  @override
  State<_ChildItem> createState() => _ChildItemState();
}

class _ChildItemState extends State<_ChildItem> {
  bool _hov = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final badge  = widget.item.badge ?? 0;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hov = true),
      onExit:  (_) => setState(() => _hov = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 34,
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.only(left: 10, right: 8),
          decoration: BoxDecoration(
            color: active ? WebColors.goldSoft
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            // Bullet column lines up under the group icon
            SizedBox(width: 18, child: Center(child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: active ? 8 : 4, height: active ? 8 : 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? WebColors.gold
                    : _hov ? WebColors.text2 : WebColors.text3,
              ),
            ))),
            const SizedBox(width: 10),
            Expanded(child: Text(widget.item.label,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? WebColors.navy
                      : _hov ? WebColors.text1 : WebColors.sideText,
                ))),
            if (badge > 0) _Badge(badge, active: active),
          ]),
        ),
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();
  @override
  Widget build(BuildContext c) => const Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Divider(height: 1, color: WebColors.sideBorder,
          indent: 10, endIndent: 10));
}

// ── Nav item ──────────────────────────────────────────────────────────────────
class _NavItem extends StatefulWidget {
  const _NavItem({
    super.key,
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
    final c      = widget.collapsed;
    final badge  = widget.item.badge ?? 0;
    final fg = active ? WebColors.sideTextActive
        : _hov ? WebColors.text1 : WebColors.sideText;

    final icon = Icon(
      active ? widget.item.activeIcon : widget.item.icon,
      size: 18,
      color: active ? WebColors.navy : fg,
    );

    Widget content;
    if (c) {
      content = Center(child: Stack(clipBehavior: Clip.none, children: [
        icon,
        if (badge > 0)
          Positioned(top: -2, right: -4, child: Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              color: WebColors.error, shape: BoxShape.circle,
              border: Border.all(color: WebColors.sideBg, width: 1.5),
            ),
          )),
      ]));
    } else {
      content = Row(children: [
        icon,
        const SizedBox(width: 10),
        Expanded(child: Text(widget.item.label,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize:   13,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color:      fg,
            ))),
        if (badge > 0) _Badge(badge, active: active),
      ]);
    }

    final item = MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit:  (_) => setState(() => _hov = false),
      cursor:  SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 36,
          margin: const EdgeInsets.symmetric(vertical: 1),
          decoration: BoxDecoration(
            color: active ? WebColors.goldSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(children: [
            Positioned.fill(child: Padding(
              padding: EdgeInsets.symmetric(horizontal: c ? 0 : 10),
              child: content,
            )),
            // Gold accent bar on the left of the active item
            if (active)
              Positioned(left: 0, top: 8, bottom: 8, child: Container(
                width: 3,
                decoration: BoxDecoration(
                  color: WebColors.gold,
                  borderRadius: BorderRadius.circular(2),
                ),
              )),
          ]),
        ),
      ),
    );

    if (!c) return item;
    return Tooltip(
      message: badge > 0
          ? '${widget.item.label} ($badge)' : widget.item.label,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 200),
      child: item,
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
    height: 18,
    constraints: const BoxConstraints(minWidth: 18),
    padding: const EdgeInsets.symmetric(horizontal: 5),
    alignment: Alignment.center,
    decoration: BoxDecoration(
        color:        WebColors.error,
        borderRadius: BorderRadius.circular(9)),
    child: Text(count > 99 ? '99+' : '$count',
        style: const TextStyle(
            fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
  );
}

// ── Footer — user row + sign out ──────────────────────────────────────────────
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
  Widget build(BuildContext context) {
    final avatar = Container(
      width: 30, height: 30,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: WebColors.navy,
      ),
      child: Center(child: Text(_initials(user?.companyName),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
              color: WebColors.goldLight))),
    );

    final signOut = _SignOutButton(onTap: onSignOut);

    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: collapsed ? 0 : 12, vertical: 10),
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: WebColors.sideBorder))),
      child: collapsed
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              Tooltip(message: user?.companyName ?? 'Trader', child: avatar),
              const SizedBox(height: 8),
              signOut,
            ])
          : Row(children: [
              avatar,
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(user?.companyName ?? 'Trader',
                      style: const TextStyle(fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: WebColors.text1),
                      overflow: TextOverflow.ellipsis, maxLines: 1),
                  Text(user?.role.label ?? 'Owner',
                      style: const TextStyle(fontSize: 11,
                          color: WebColors.text3)),
                ],
              )),
              signOut,
            ]),
    );
  }

  String _initials(String? n) {
    if (n == null || n.isEmpty) return '?';
    final p = n.trim().split(' ');
    return p.length >= 2
        ? '${p[0][0]}${p[1][0]}'.toUpperCase()
        : n[0].toUpperCase();
  }
}

class _SignOutButton extends StatefulWidget {
  const _SignOutButton({required this.onTap});
  final VoidCallback onTap;
  @override
  State<_SignOutButton> createState() => _SignOutButtonState();
}

class _SignOutButtonState extends State<_SignOutButton> {
  bool _hov = false;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Sign out',
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hov = true),
      onExit:  (_) => setState(() => _hov = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 30, height: 30,
          decoration: BoxDecoration(
            color: _hov ? WebColors.errorBg : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.logout_rounded, size: 17,
              color: _hov ? WebColors.error : WebColors.text3),
        ),
      ),
    ),
  );
}
