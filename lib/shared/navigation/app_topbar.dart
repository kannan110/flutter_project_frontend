import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/web_tokens.dart';
import 'topbar_search_data.dart';

// ═════════════════════════════════════════════════════════════════════════════
// AppTopbar — white top bar: search · caller actions · alerts · profile
// ═════════════════════════════════════════════════════════════════════════════

const double kTopbarHeight = WebSize.topbar;

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(appUserProvider).valueOrNull;

    return Container(
      height: kTopbarHeight,
      decoration: const BoxDecoration(
        color:  WebColors.surface,
        border: Border(bottom: BorderSide(color: WebColors.border)),
      ),
      // Left padding clears the sidebar's round edge toggle
      padding: const EdgeInsets.fromLTRB(20, 0, 16, 0),
      child: Row(children: [
        // ── Search bar ─────────────────────────────────────────────────────
        Expanded(child: Align(
            alignment: Alignment.centerLeft, child: _SearchBar())),
        const SizedBox(width: 16),

        // ── Caller actions ─────────────────────────────────────────────────
        if (actions != null) ...actions!,

        // ── Alert bell with badge ──────────────────────────────────────────
        Stack(clipBehavior: Clip.none, children: [
          _TopIconBtn(
              icon: Icons.notifications_none_rounded,
              tooltip: 'Alerts',
              onTap: () => context.go(R.alerts)),
          if (unreadAlerts > 0)
            Positioned(right: 2, top: 2,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: WebColors.error,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: WebColors.surface, width: 2)),
                  child: Text(unreadAlerts > 99 ? '99+' : '$unreadAlerts',
                      style: const TextStyle(fontSize: 9,
                          fontWeight: FontWeight.w800, color: Colors.white)),
                )),
        ]),
        const SizedBox(width: 12),
        Container(width: 1, height: 28, color: WebColors.border),
        const SizedBox(width: 12),

        // ── Profile cluster (opens Settings) ───────────────────────────────
        _ProfileChip(
          name:     user?.companyName ?? 'Ramesh',
          role:     user?.role.label ?? 'Owner',
          initials: _initials(user?.companyName),
          onTap:    () => context.go(R.settings),
        ),
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

// ── Profile chip ──────────────────────────────────────────────────────────────
class _ProfileChip extends StatefulWidget {
  const _ProfileChip({required this.name, required this.role,
    required this.initials, required this.onTap});
  final String name, role, initials;
  final VoidCallback onTap;
  @override
  State<_ProfileChip> createState() => _ProfileChipState();
}

class _ProfileChipState extends State<_ProfileChip> {
  bool _hov = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hov = true),
    onExit:  (_) => setState(() => _hov = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
        decoration: BoxDecoration(
          color: _hov ? WebColors.divider : Colors.transparent,
          borderRadius: BorderRadius.circular(WebRadius.button),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Column(mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(widget.name, style: const TextStyle(fontSize: 13,
                fontWeight: FontWeight.w700, color: WebColors.text1)),
            Text(widget.role, style: const TextStyle(fontSize: 11,
                color: WebColors.text3)),
          ]),
          const SizedBox(width: 10),
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: WebColors.navy,
              border: Border.all(color: WebColors.gold, width: 2),
            ),
            child: Center(child: Text(widget.initials,
                style: const TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w800, color: WebColors.goldLight))),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down_rounded,
              size: 18, color: WebColors.text3),
        ]),
      ),
    ),
  );
}

// ── Search bar ────────────────────────────────────────────────────────────────
// ── Focus Provider ────────────────────────────────────────────────────────────
final topbarSearchFocusNodeProvider = Provider<FocusNode>((ref) {
  final node = FocusNode(debugLabel: 'TopbarSearchFocus');
  ref.onDispose(node.dispose);
  return node;
});

// ── Search bar ────────────────────────────────────────────────────────────────
class _SearchBar extends ConsumerStatefulWidget {
  @override
  ConsumerState<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends ConsumerState<_SearchBar> {
  final LayerLink _layerLink = LayerLink();
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  OverlayEntry? _overlayEntry;
  Timer? _debounce;
  bool _isLoading = false;
  int _selectedIndex = 0;

  List<TopbarSearchItem> _retailers = [];
  List<TopbarSearchItem> _orders = [];
  List<TopbarSearchItem> _agents = [];

  List<TopbarSearchItem> get _allVisible => [
    ..._retailers,
    ..._orders,
    ..._agents,
  ];

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final focusNode = ref.read(topbarSearchFocusNodeProvider);
      focusNode.addListener(_onFocusChanged);
    });
  }

  @override
  void dispose() {
    _hideOverlay();
    _debounce?.cancel();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!mounted) return;
    final focusNode = ref.read(topbarSearchFocusNodeProvider);
    if (focusNode.hasFocus) {
      _showOverlay();
      _searchEntities(_textCtrl.text);
      setState(() {});
    } else {
      _hideOverlay();
      setState(() {});
    }
  }

  void _onTextChanged() {
    final q = _textCtrl.text;
    _debounce?.cancel();

    setState(() => _isLoading = true);
    _overlayEntry?.markNeedsBuild();

    // Debounce database queries
    _debounce = Timer(const Duration(milliseconds: 200), () => _searchEntities(q));
  }

  Future<void> _searchEntities(String query) async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null || !mounted) {
      if (mounted) {
        setState(() => _isLoading = false);
        _overlayEntry?.markNeedsBuild();
      }
      return;
    }

    final results = await TopbarSearchData.searchEntities(
      client: Supabase.instance.client,
      traderId: tid,
      query: query,
    );

    if (!mounted) return;
    setState(() {
      _retailers = results[TopbarSearchResultType.retailer] ?? [];
      _orders = results[TopbarSearchResultType.order] ?? [];
      _agents = results[TopbarSearchResultType.agent] ?? [];
      _isLoading = false;
      if (_selectedIndex >= _allVisible.length) {
        _selectedIndex = 0;
      }
    });
    _overlayEntry?.markNeedsBuild();
  }

  void _showOverlay() {
    if (_overlayEntry != null) return;
    final overlay = Overlay.of(context, rootOverlay: true);

    _overlayEntry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          // Invisible tap catcher to close dropdown on tap outside
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                ref.read(topbarSearchFocusNodeProvider).unfocus();
              },
            ),
          ),
          // Attached dropdown card
          Positioned(
            width: 480,
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: const Offset(0, 44),
              child: _buildDropdownCard(),
            ),
          ),
        ],
      ),
    );

    overlay.insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _selectItem(TopbarSearchItem item) {
    ref.read(topbarSearchFocusNodeProvider).unfocus();
    _hideOverlay();
    _textCtrl.clear();
    context.go(item.route);
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final list = _allVisible;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (list.isNotEmpty) {
        setState(() {
          _selectedIndex = (_selectedIndex + 1) % list.length;
        });
        _overlayEntry?.markNeedsBuild();
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (list.isNotEmpty) {
        setState(() {
          _selectedIndex = (_selectedIndex - 1 + list.length) % list.length;
        });
        _overlayEntry?.markNeedsBuild();
      }
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (list.isNotEmpty && _selectedIndex >= 0 && _selectedIndex < list.length) {
        _selectItem(list[_selectedIndex]);
      }
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      ref.read(topbarSearchFocusNodeProvider).unfocus();
      _hideOverlay();
    }
  }

  Widget _buildDropdownCard() {
    final list = _allVisible;

    return Material(
      elevation: 12,
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 460),
        decoration: BoxDecoration(
          color: WebColors.surface,
          borderRadius: BorderRadius.circular(WebRadius.card),
          border: Border.all(color: WebColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F00081E),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // List of results
            Flexible(
              child: list.isNotEmpty
                  ? ListView(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      shrinkWrap: true,
                      children: [
                        if (_retailers.isNotEmpty) ...[
                          _buildSectionHeader('RETAILERS / CUSTOMERS'),
                          ..._buildItemsSection(_retailers),
                        ],
                        if (_orders.isNotEmpty) ...[
                          _buildSectionHeader('ORDERS'),
                          ..._buildItemsSection(_orders),
                        ],
                        if (_agents.isNotEmpty) ...[
                          _buildSectionHeader('DELIVERY AGENTS'),
                          ..._buildItemsSection(_agents),
                        ],
                      ],
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.search_off_rounded, size: 28, color: WebColors.text3),
                          const SizedBox(height: 8),
                          Text(
                            _textCtrl.text.isEmpty
                                ? 'No recent customers or orders found'
                                : 'No records found for "${_textCtrl.text}"',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: WebColors.text2),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Search by retailer shop name, phone, order ID, or agent name',
                            style: TextStyle(fontSize: 11, color: WebColors.text3),
                          ),
                        ],
                      ),
                    ),
            ),
            const Divider(height: 1, color: WebColors.border),
            // Bottom key shortcuts hint
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  _buildKeyHint('↑↓', 'Navigate'),
                  const SizedBox(width: 12),
                  _buildKeyHint('↵', 'Select'),
                  const SizedBox(width: 12),
                  _buildKeyHint('ESC', 'Close'),
                  const Spacer(),
                  if (_isLoading)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: WebColors.navy),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: WebColors.text3,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  List<Widget> _buildItemsSection(List<TopbarSearchItem> items) {
    final all = _allVisible;
    return items.map((item) {
      final idx = all.indexOf(item);
      final isSelected = idx == _selectedIndex;

      return InkWell(
        onTap: () => _selectItem(item),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? WebColors.navySoft : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: isSelected ? WebColors.navy : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isSelected ? WebColors.surface : WebColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected ? WebColors.navy.withValues(alpha: 0.15) : WebColors.border,
                  ),
                ),
                child: Icon(
                  item.icon ?? Icons.arrow_forward_rounded,
                  size: 15,
                  color: isSelected ? WebColors.navy : WebColors.text2,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                        color: isSelected ? WebColors.navy : WebColors.text1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.subtitle != null && item.subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        item.subtitle!,
                        style: const TextStyle(fontSize: 11, color: WebColors.text3),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (item.badge != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected ? WebColors.navy.withValues(alpha: 0.10) : WebColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: WebColors.border),
                  ),
                  child: Text(
                    item.badge!,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? WebColors.navy : WebColors.text2,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }).toList();
  }

  Widget _buildKeyHint(String k, String l) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: WebColors.surfaceAlt,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: WebColors.border),
          ),
          child: Text(k, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: WebColors.text2)),
        ),
        const SizedBox(width: 4),
        Text(l, style: const TextStyle(fontSize: 10.5, color: WebColors.text3)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final focusNode = ref.watch(topbarSearchFocusNodeProvider);
    final hasFocus = focusNode.hasFocus;
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    final shortcutText = isMac ? '⌘G' : 'Ctrl + G';

    return CompositedTransformTarget(
      link: _layerLink,
      child: Focus(
        onKeyEvent: (node, event) {
          _handleKeyEvent(event);
          return KeyEventResult.ignored;
        },
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          height: 40,
          decoration: BoxDecoration(
            color: hasFocus ? WebColors.surface : WebColors.surfaceAlt,
            borderRadius: BorderRadius.circular(WebRadius.button),
            border: Border.all(
              color: hasFocus ? WebColors.navy : WebColors.border,
              width: hasFocus ? 1.5 : 1.0,
            ),
            boxShadow: hasFocus
                ? const [
                    BoxShadow(
                      color: Color(0x0F00081E),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),
              Icon(
                Icons.search_rounded,
                size: 18,
                color: hasFocus ? WebColors.navy : WebColors.text3,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _textCtrl,
                  focusNode: focusNode,
                  style: const TextStyle(fontSize: 13, color: WebColors.text1, fontWeight: FontWeight.w400),
                  decoration: const InputDecoration(
                    hintText: 'Search orders, customers, agents...',
                    hintStyle: TextStyle(fontSize: 13, color: WebColors.text3, fontWeight: FontWeight.w400),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              if (_textCtrl.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16, color: WebColors.text3),
                  onPressed: () {
                    _textCtrl.clear();
                  },
                  tooltip: 'Clear',
                  visualDensity: VisualDensity.compact,
                ),
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: hasFocus ? WebColors.navySoft : WebColors.surface,
                  borderRadius: BorderRadius.circular(WebRadius.label),
                  border: Border.all(
                    color: hasFocus ? WebColors.navy.withValues(alpha: 0.2) : WebColors.border,
                  ),
                ),
                child: Text(
                  shortcutText,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: hasFocus ? WebColors.navy : WebColors.text2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hov = true),
          onExit:  (_) => setState(() => _hov = false),
          child: GestureDetector(onTap: widget.onTap,
              child: AnimatedContainer(duration: const Duration(milliseconds: 100),
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: _hov ? WebColors.divider : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(widget.icon, size: 22, color: WebColors.text2)))));
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
