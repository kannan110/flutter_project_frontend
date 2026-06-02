import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rooster_trader/shared/layouts/desktop_shell.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';

// ── AppTopbar ─────────────────────────────────────────────────────────────
// White topbar with navy text — sits above content area (right of sidebar)
class AppTopbar extends ConsumerWidget {
  const AppTopbar({
    super.key,
    required this.title,
    this.unreadAlerts   = 0,
    this.onRefresh,
    this.langNotifier,
    this.currentLang,
    this.actions,
  });

  final String   title;
  final int      unreadAlerts;
  final VoidCallback?          onRefresh;
  final StateController<String>? langNotifier;
  final String?  currentLang;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: kTopbarHeight,
      decoration: const BoxDecoration(
        color:  kSurface,
        border: Border(bottom: BorderSide(color: kBorderLight, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          // Page title
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize:      20,
                fontWeight:    FontWeight.w700,
                color:         kTextMain,
                letterSpacing: -0.3,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Caller-provided actions
          if (actions != null) ...actions!,

          // Language toggle
          if (langNotifier != null && currentLang != null) ...[
            const SizedBox(width: 8),
            _LangToggle(
              lang:     currentLang!,
              onToggle: () => langNotifier!.state =
              currentLang == 'en' ? 'ta' : 'en',
            ),
          ],

          // Refresh
          if (onRefresh != null) ...[
            const SizedBox(width: 4),
            _TopbarIconBtn(
              icon:    Icons.refresh_rounded,
              tooltip: 'Refresh',
              onTap:   onRefresh!,
            ),
          ],

          // Notifications bell
          const SizedBox(width: 4),
          _AlertBell(unreadAlerts: unreadAlerts),
        ],
      ),
    );
  }
}

// ── Language toggle ────────────────────────────────────────────────────────
class _LangToggle extends StatelessWidget {
  const _LangToggle({required this.lang, required this.onToggle});
  final String       lang;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onToggle,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color:        kNavy,
        borderRadius: BorderRadius.circular(4),
        border:       Border.all(color: kGold.withValues(alpha: 0.4)),
      ),
      child: Text(
        lang == 'en' ? 'தமிழ்' : 'EN',
        style: const TextStyle(
          fontSize:   12,
          fontWeight: FontWeight.w700,
          color:      kGoldLight,
        ),
      ),
    ),
  );
}

// ── Alert bell ─────────────────────────────────────────────────────────────
class _AlertBell extends StatelessWidget {
  const _AlertBell({required this.unreadAlerts});
  final int unreadAlerts;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      _TopbarIconBtn(
        icon:    Icons.notifications_outlined,
        tooltip: 'Alerts',
        onTap:   () => context.go(R.alerts),
      ),
      if (unreadAlerts > 0)
        Positioned(
          right: 6, top: 6,
          child: Container(
            width:  9, height: 9,
            decoration: const BoxDecoration(
                color: kError, shape: BoxShape.circle),
          ),
        ),
    ],
  );
}

// ── Icon button ────────────────────────────────────────────────────────────
class _TopbarIconBtn extends StatelessWidget {
  const _TopbarIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData     icon;
  final String       tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap:        onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color:        kBgGrey,
          borderRadius: BorderRadius.circular(4),
          border:       Border.all(color: kBorderLight),
        ),
        child: Icon(icon, size: 18, color: kTextSub),
      ),
    ),
  );
}

// ── Route → title map ──────────────────────────────────────────────────────
String topbarTitleForRoute(String loc) {
  if (loc.startsWith('/t/dashboard'))        return 'Dashboard';
  if (loc.startsWith('/t/orders/create'))    return 'New Order';
  if (loc.startsWith('/t/orders/'))          return 'Order Detail';
  if (loc.startsWith('/t/orders'))           return 'Orders';
  if (loc.startsWith('/t/dispatch/batch/'))  return 'Batch Detail';
  if (loc.startsWith('/t/dispatch'))         return 'Dispatch';
  if (loc.startsWith('/t/approvals/'))       return 'Approval Detail';
  if (loc.startsWith('/t/approvals'))        return 'Approvals';
  if (loc.startsWith('/t/invoices/'))        return 'Invoice Detail';
  if (loc.startsWith('/t/invoices'))         return 'Invoices';
  if (loc.startsWith('/t/ledger/'))          return 'Retailer Ledger';
  if (loc.startsWith('/t/ledger'))           return 'Ledger';
  if (loc.startsWith('/t/retailers/create')) return 'New Retailer';
  if (loc.startsWith('/t/retailers/'))       return 'Retailer Detail';
  if (loc.startsWith('/t/retailers'))        return 'Retailers';
  if (loc.startsWith('/t/agents/create'))    return 'New Agent';
  if (loc.startsWith('/t/agents/'))          return 'Agent Detail';
  if (loc.startsWith('/t/agents'))           return 'Agents';
  if (loc.startsWith('/t/rates'))            return 'Rates';
  if (loc.startsWith('/t/shifts/'))          return 'Shift Detail';
  if (loc.startsWith('/t/shifts'))           return 'Shifts';
  if (loc.startsWith('/t/crates'))           return 'Crates';
  if (loc.startsWith('/t/analytics'))        return 'Analytics';
  if (loc.startsWith('/t/stock/detail'))     return 'Stock Detail';
  if (loc.startsWith('/t/stock'))            return 'Stock';
  if (loc.startsWith('/t/returns'))          return 'Returns';
  if (loc.startsWith('/t/pricing'))          return 'Pricing Rules';
  if (loc.startsWith('/t/reconciliation'))   return 'Cash Reconciliation';
  if (loc.startsWith('/t/day-closure'))      return 'Day Closure';
  if (loc.startsWith('/t/alerts'))           return 'Alerts';
  if (loc.startsWith('/t/reports/daily'))    return 'Daily Report';
  if (loc.startsWith('/t/reports'))          return 'Reports';
  if (loc.startsWith('/t/user-management'))  return 'User Management';
  if (loc.startsWith('/t/settings'))         return 'Settings';
  if (loc.startsWith('/t/purchase'))         return 'Purchase';
  return 'Rooster Commerce OS';
}