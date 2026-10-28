import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_router.dart';

// ═════════════════════════════════════════════════════════════════════════════
// AppTopbar — Kirtwin-style top navigation bar
// White bg, search bar, icon cluster, profile avatar
// ═════════════════════════════════════════════════════════════════════════════

const double kTopbarHeight = 56.0;

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

  final String                   title;
  final int                      unreadAlerts;
  final VoidCallback?            onRefresh;
  final StateController<String>? langNotifier;
  final String?                  currentLang;
  final List<Widget>?            actions;

  static const _bg     = Color(0xFFFFFFFF);
  static const _border = Color(0xFFE2E8F0);
  static const _text2  = Color(0xFF475569);
  static const _text3  = Color(0xFF94A3B8);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(appUserProvider).valueOrNull;

    return Container(
      height:    kTopbarHeight,
      color:     _bg,
      child: Column(children: [
        Expanded(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            // ── Search bar ─────────────────────────────────────────────────
            Expanded(child: _SearchBar()),
            const SizedBox(width: 16),

            // ── Caller actions ─────────────────────────────────────────────
            if (actions != null) ...actions!,

            // ── Icon cluster ───────────────────────────────────────────────
            // Alert bell with badge
            Stack(clipBehavior: Clip.none, children: [
              _TopIconBtn(
                  icon: Icons.notifications_outlined,
                  tooltip: 'Alerts',
                  onTap: () => context.go(R.alerts)),
              if (unreadAlerts > 0)
                Positioned(right: 4, top: 4,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                          color: const Color(0xFFDC2626),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: _bg, width: 1.5)),
                      child: Text('$unreadAlerts',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 8,
                              fontWeight: FontWeight.w800, color: Colors.white)),
                    )),
            ]),
            const SizedBox(width: 12),

            // ── Profile cluster ────────────────────────────────────────────
            Column(mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(user?.companyName ?? 'Ramesh',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                          color: Color(0xFF0F172A))),
                  Text(user?.role.label ?? 'Owner',
                      style: const TextStyle(fontSize: 11, color: _text3)),
                ]),
            const SizedBox(width: 10),
            // Avatar
            GestureDetector(
              onTap: () => context.go(R.settings),
              child: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  image: null,
                  color: const Color(0xFF1E293B),
                  border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
                ),
                child: Center(child: Text(
                  _initials(user?.companyName),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                      color: Colors.white),
                )),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded,
                size: 16, color: _text3),
          ]),
        )),
        const Divider(height: 1, color: _border),
      ]),
    );
  }

  String _initials(String? n) {
    if (n == null || n.isEmpty) return '?';
    final p = n.trim().split(' ');
    return p.length >= 2
        ? '${p[0][0]}${p[1][0]}'.toUpperCase() : n[0].toUpperCase();
  }
}

// ── Search bar ────────────────────────────────────────────────────────────────
class _SearchBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 360),
    height: 34,
    decoration: BoxDecoration(
      color:        const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(7),
      border:       Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: Row(children: [
      const SizedBox(width: 10),
      const Icon(Icons.search_rounded, size: 16, color: Color(0xFF94A3B8)),
      const SizedBox(width: 8),
      const Expanded(child: TextField(
        decoration: InputDecoration(
          hintText:       'Search orders, customers, agents...',
          hintStyle:      TextStyle(fontSize: 13, color: Color(0xFF94A3B8),
              fontWeight: FontWeight.w400),
          border:         InputBorder.none,
          enabledBorder:  InputBorder.none,
          focusedBorder:  InputBorder.none,
          isDense:        true,
          contentPadding: EdgeInsets.zero,
        ),
        style: TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
      )),
      Container(
        margin:  const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color:        const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(4),
          border:       Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: const Text('Ctrl + K',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                color: Color(0xFF3B82F6))),
      ),
    ]),
  );
}

// ── Icon button ───────────────────────────────────────────────────────────────
class _TopIconBtn extends StatefulWidget {
  const _TopIconBtn({required this.icon, required this.tooltip,
    required this.onTap});
  final IconData icon; final String tooltip; final VoidCallback onTap;
  @override State<_TopIconBtn> createState() => _TopIconBtnState();
}
class _TopIconBtnState extends State<_TopIconBtn> {
  bool _hov = false;
  @override
  Widget build(BuildContext c) => Tooltip(message: widget.tooltip,
      child: MouseRegion(
          onEnter: (_) => setState(() => _hov = true),
          onExit:  (_) => setState(() => _hov = false),
          child: GestureDetector(onTap: widget.onTap,
              child: AnimatedContainer(duration: const Duration(milliseconds: 100),
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    color:        _hov ? const Color(0xFFF1F5F9) : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(widget.icon, size: 18, color: const Color(0xFF64748B))))));
}

// ── Route → title ──────────────────────────────────────────────────────────────
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
  if (loc.startsWith('/t/purchase'))         return 'Purchase Management';
  return 'Rooster Commerce OS';
}