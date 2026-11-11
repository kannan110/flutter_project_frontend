import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/responsive_layout.dart';
import '../../../shared/widgets/web/web.dart';

class AgentsScreen extends ConsumerStatefulWidget {
  const AgentsScreen({super.key});
  @override ConsumerState<AgentsScreen> createState() => _S();
}

class _S extends ConsumerState<AgentsScreen> {
  final _c = Supabase.instance.client;
  List<Map<String,dynamic>> _agents = [];
  List<Map<String,dynamic>> _filtered = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  void _applySearch(String q) {
    if (!mounted) return;
    final lower = q.trim().toLowerCase();
    setState(() => _filtered = lower.isEmpty
        ? List.from(_agents)
        : _agents.where((a) =>
            (a['name'] as String? ?? '').toLowerCase().contains(lower) ||
            (a['phone'] as String? ?? '').toLowerCase().contains(lower) ||
            (a['vehicle_no'] as String? ?? '').toLowerCase().contains(lower),
          ).toList());
  }

  @override void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => _applySearch(_searchCtrl.text));
  }

  @override void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    if (mounted) setState(() => _loading = true);
    try {
      final data = await _c.from('delivery_agents')
          .select('id,name,phone,vehicle_no,vehicle_type,is_active,auth_user_id,notes')
          .eq('trader_id', tid).order('name');
      // Alphabetical by name, case-insensitive (the database's order can put
      // mixed-case names after all-caps ones).
      final agents = List<Map<String,dynamic>>.from(data)
        ..sort((a, b) =>
            (a['name'] as String? ?? '').trim().toLowerCase().compareTo(
                (b['name'] as String? ?? '').trim().toLowerCase()));
      if (mounted) setState(() { _agents = agents; _loading = false; _applySearch(_searchCtrl.text); });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  void _showAgentInstructions(BuildContext ctx, String agentName) {
    final code = ref.read(appUserProvider).valueOrNull?.companyCode ?? '—';
    // Same content: bottom sheet on mobile, centred dialog on web.
    Widget sheet(BuildContext c) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Share these with the agent:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              // Company Code
              Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: kPrimary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: kPrimary.withValues(alpha: 0.2))),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Company Code', style: TextStyle(fontSize: 11, color: kTextHint)),
                      Text(code, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: kPrimary, letterSpacing: 3)),
                    ])),
                    IconButton(
                      icon: const Icon(Icons.copy, color: kPrimary),
                      tooltip: 'Copy',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: code));
                        showSuccess(ctx, 'Company code copied!');
                      },
                    ),
                  ])),
              const SizedBox(height: 12),
              // Name reminder
              Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.shade200)),
                  child: Row(children: [
                    const Icon(Icons.warning_amber_outlined, color: Colors.orange, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Agent must use this exact name:', style: TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w600)),
                      Text(agentName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.orange)),
                      const Text('(Case sensitive — must match exactly)', style: TextStyle(fontSize: 10, color: Colors.orange)),
                    ])),
                    IconButton(
                      icon: const Icon(Icons.copy, color: Colors.orange),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: agentName));
                        showSuccess(ctx, 'Name copied!');
                      },
                    ),
                  ])),
              const SizedBox(height: 16),
              // Instructions
              Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Agent steps:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.blue)),
                    const SizedBox(height: 8),
                    _istep('1', 'Open Rooster Trader app'),
                    _istep('2', 'Tap "Sign Up" → create account with their email'),
                    _istep('3', 'Tap "Link My Agent Account"'),
                    _istep('4', 'Enter: Company Code = $code'),
                    _istep('5', 'Enter: Name = $agentName (exactly as shown)'),
                    _istep('6', 'Tap "Link My Account" → Done!'),
                  ])),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () => Navigator.of(c, rootNavigator: true).pop(), child: const Text('Close')),
            ]));
    if (ctx.isDesktop) {
      showDialog(
          context: ctx, useRootNavigator: true,
          builder: (c) => Dialog(
                backgroundColor: WebColors.surface,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(WebRadius.dialog)),
                child: SizedBox(width: WebSize.dialogMd,
                    child: SingleChildScrollView(child: sheet(c))),
              ));
    } else {
      showModalBottomSheet(
          context: ctx, useRootNavigator: true, isScrollControlled: true,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: sheet);
    }
  }

  Widget _istep(String n, String t) => Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$n. ', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.blue)),
        Expanded(child: Text(t, style: const TextStyle(fontSize: 12, color: Colors.blue))),
      ]));

  // ═══════════════════════════════════════════════════════════════════════
  // WEB (desktop) — company code + KPIs, tabs, agents table.
  // ═══════════════════════════════════════════════════════════════════════
  static const _webTabs = ['all', 'linked', 'unlinked', 'inactive'];
  String _webTab = 'all';
  bool _dense = true;

  bool _linked(Map<String, dynamic> a) => a['auth_user_id'] != null;
  bool _activeA(Map<String, dynamic> a) => a['is_active'] as bool? ?? true;
  bool _inTab(Map<String, dynamic> a, String t) => switch (t) {
    'linked'   => _linked(a),
    'unlinked' => !_linked(a),
    'inactive' => !_activeA(a),
    _          => true,
  };

  Widget _buildWeb() {
    final companyCode =
        ref.watch(appUserProvider).valueOrNull?.companyCode ?? '—';
    final unlinked = _agents.where((a) => !_linked(a)).length;
    int count(String t) => _filtered.where((a) => _inTab(a, t)).length;
    final rows = _filtered.where((a) => _inTab(a, _webTab)).toList();

    final codeCard = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [WebColors.navy, WebColors.navyMid],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(WebRadius.card),
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('Your Company Code — share with agents',
              style: TextStyle(fontSize: 11, color: Colors.white70)),
          const SizedBox(height: 2),
          Text(companyCode, style: const TextStyle(fontSize: 20,
              fontWeight: FontWeight.w900, color: WebColors.goldLight,
              letterSpacing: 2)),
        ])),
        IconButton(
          icon: const Icon(Icons.copy_rounded, color: Colors.white, size: 18),
          tooltip: 'Copy',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: companyCode));
            showSuccess(context, 'Copied!');
          },
        ),
      ]),
    );

    return WebPage(
      header: PageBreadcrumbsHeader(
        title: 'Delivery Agents',
        subtitle: 'Your delivery team, their vehicles and app access',
        crumbs: const [Crumb('Dashboard', R.dashboard), Crumb('Agents')],
        action: Row(mainAxisSize: MainAxisSize.min, children: [
          WebIconButton(icon: Icons.refresh_rounded, tooltip: 'Refresh',
              onTap: _load),
          const SizedBox(width: 8),
          WebButton(label: 'Add Agent', icon: Icons.person_add_outlined,
              onPressed: () => context.push(R.agentCreate)),
        ]),
      ),
      children: [
        WebKpiRow(children: [
          codeCard,
          WebKpiCard(label: 'Total Agents', value: '${_agents.length}',
              icon: Icons.delivery_dining, color: WebColors.navy),
          WebKpiCard(label: 'Linked', value: '${_agents.length - unlinked}',
              sub: 'can log in to the app',
              icon: Icons.link_rounded, color: WebColors.success),
          WebKpiCard(label: 'Not Linked', value: '$unlinked',
              sub: 'cannot log in yet',
              icon: Icons.link_off_rounded, color: WebColors.warning),
        ]),
        if (unlinked > 0) ...[
          const SizedBox(height: WebSpace.md),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: WebColors.warningBg,
              borderRadius: BorderRadius.circular(WebRadius.sm),
            ),
            child: Row(children: [
              const Icon(Icons.link_off, color: WebColors.warning, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(
                  '$unlinked agent(s) not yet linked. Use "How to Link" on the '
                  'agent row to share instructions.',
                  style: const TextStyle(fontSize: 13,
                      color: WebColors.warning, fontWeight: FontWeight.w600))),
            ]),
          ),
        ],
        const SizedBox(height: WebSpace.lg),
        WebListCard(children: [
          WebListTabs(
            tabs: [
              WebTab('All', count: count('all')),
              WebTab('Linked', count: count('linked'), color: WebColors.success),
              WebTab('Not Linked', count: count('unlinked'),
                  color: WebColors.warning),
              WebTab('Inactive', count: count('inactive'),
                  color: WebColors.text3),
            ],
            selected: _webTabs.indexOf(_webTab),
            onChanged: (i) => setState(() => _webTab = _webTabs[i]),
          ),
          WebListToolbar(
            search: WebSearchField(
              controller: _searchCtrl,
              hint: 'Search by name, phone, vehicle…',
              debounce: const Duration(milliseconds: 200),
              onChanged: _applySearch,
            ),
            trailing: [
              const Text('Dense', style: WebText.bodySub),
              Switch(value: _dense, activeTrackColor: WebColors.navy,
                  onChanged: (v) => setState(() => _dense = v)),
            ],
          ),
          WebDataTable<Map<String, dynamic>>(
            columns: const [
              WebColumn('Agent', flex: 3),
              WebColumn('Phone', width: 130),
              WebColumn('Vehicle No', width: 130),
              WebColumn('Vehicle Type', width: 120),
              WebColumn('Status', width: 180),
              WebColumn('Actions', width: 200, align: TextAlign.right),
            ],
            rows: rows,
            paginate: true,
            dense: _dense,
            loading: _loading,
            onRowTap: (a) => context.push(R.agentDetailPath(a['id'])),
            emptyText: _agents.isEmpty ? 'No agents yet' : 'No agents match',
            emptyAction: _agents.isEmpty
                ? WebButton(label: 'Add Agent', icon: Icons.person_add_outlined,
                    onPressed: () => context.push(R.agentCreate))
                : null,
            cellBuilder: (a, col) {
              final name = a['name'] as String? ?? '—';
              final linked = _linked(a);
              switch (col) {
                case 0:
                  return Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: WebColors.text1));
                case 1:
                  return Text(a['phone'] as String? ?? '—',
                      style: const TextStyle(fontSize: 13, color: WebColors.text2));
                case 2:
                  return Text(a['vehicle_no'] as String? ?? '—',
                      style: const TextStyle(fontSize: 13, color: WebColors.text2));
                case 3:
                  return Text(a['vehicle_type'] as String? ?? '—',
                      style: const TextStyle(fontSize: 13, color: WebColors.text3));
                case 4:
                  return Wrap(spacing: 6, runSpacing: 4, children: [
                    WebLabel(linked ? 'Linked ✓' : 'Not linked',
                        color: linked ? WebColors.success : WebColors.warning,
                        dot: true),
                    if (!_activeA(a))
                      const WebLabel('Inactive', color: WebColors.text3),
                  ]);
                default:
                  return Row(mainAxisSize: MainAxisSize.min, children: [
                    if (!linked) ...[
                      WebButton(label: 'How to Link',
                          icon: Icons.link_outlined,
                          color: WebColors.warning,
                          onPressed: () => _showAgentInstructions(context, name)),
                      const SizedBox(width: 6),
                    ],
                    WebIconButton(
                      icon: Icons.visibility_outlined,
                      tooltip: 'Details',
                      size: 32,
                      outlined: false,
                      onTap: () => context.push(R.agentDetailPath(a['id'])),
                    ),
                  ]);
              }
            },
          ),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (context.isDesktop) return _buildWeb();
    final companyCode = ref.watch(appUserProvider).valueOrNull?.companyCode ?? '—';
    final unlinked = _agents.where((a) => a['auth_user_id'] == null).length;
    final showList = _filtered;

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(title: const Text('Delivery Agents'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push(R.agentCreate),
          icon: const Icon(Icons.person_add_outlined),
          label: const Text('Add Agent')),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      // Reserve space so FAB clears the parent TraderShell glass bottom nav
      bottomNavigationBar: const SizedBox(height: 80),
      body: Column(children: [

        // Company code bar
        Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Your Company Code — share with agents', style: TextStyle(fontSize: 11, color: kTextHint)),
                  Text(companyCode, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: kPrimary, letterSpacing: 3)),
                ])),
                IconButton(
                  icon: const Icon(Icons.copy, color: kPrimary),
                  tooltip: 'Copy',
                  onPressed: () { Clipboard.setData(ClipboardData(text: companyCode)); showSuccess(context, 'Copied!'); },
                ),
              ]),
              if (unlinked > 0) Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade200)),
                  child: Row(children: [
                    Icon(Icons.link_off, color: Colors.orange.shade700, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text('$unlinked agent(s) not yet linked. Tap agent → "How to Link" button to share instructions.',
                        style: TextStyle(fontSize: 12, color: Colors.orange.shade800))),
                  ])),
            ])),
        const Divider(height: 1),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: AppSearchBar(
            controller: _searchCtrl,
            hint: 'Search by name, phone, vehicle…',
            onChanged: _applySearch,
            onClear: () { _searchCtrl.clear(); _applySearch(''); },
          ),
        ),
        const Divider(height: 1),

        Expanded(child: _loading ? const LoadingList() : _agents.isEmpty
            ? EmptyState(icon: Icons.delivery_dining_outlined, message: 'No agents yet', sub: 'Add your delivery agents and share the Company Code with them', onAction: () => context.push(R.agentCreate), actionLabel: 'Add Agent')
            : RefreshIndicator(onRefresh: _load, child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), itemCount: showList.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final a      = showList[i];
              final linked = a['auth_user_id'] != null;
              final active = a['is_active'] as bool? ?? true;
              final name   = a['name'] as String;

              return Container(
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(kRadiusCard),
                    border: Border.all(color: linked ? kBorderLight : Colors.orange.withValues(alpha: 0.4), width: linked ? 1 : 1.5)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(padding: const EdgeInsets.all(14), child: Row(children: [
                    // Avatar
                    Container(
                        width: 46, height: 46,
                        decoration: BoxDecoration(
                            color: linked ? kNavy.withValues(alpha: 0.08) : Colors.orange.withValues(alpha: 0.1),
                            shape: BoxShape.circle),
                        child: Icon(linked ? Icons.delivery_dining : Icons.person_add_outlined,
                            color: linked ? kPrimary : Colors.orange, size: 24)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: kNavy)),
                        if (!active) ...[const SizedBox(width: 6), const StatusBadge('inactive', Colors.grey, small: true)],
                      ]),
                      if (a['phone'] != null) Text(a['phone'] as String, style: const TextStyle(fontSize: 12, color: kTextSub)),
                      if (a['vehicle_no'] != null) Text('${a['vehicle_type'] ?? ''} · ${a['vehicle_no']}', style: const TextStyle(fontSize: 11, color: kTextHint)),
                    ])),
                    // Status badge
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      StatusBadge(linked ? 'linked ✓' : 'not linked', linked ? Colors.green : Colors.orange),
                      const SizedBox(height: 4),
                      InkWell(onTap: () => context.push(R.agentDetailPath(a['id'])), child: const Text('Details ›', style: TextStyle(fontSize: 11, color: kPrimary, fontWeight: FontWeight.w600))),
                    ]),
                  ])),

                  // Unlinked — show clear action
                  if (!linked) Container(
                      decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(13))),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.link_outlined, color: Colors.orange, size: 20),
                        title: const Text('Not linked yet — agent cannot log in', style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w600)),
                        trailing: ElevatedButton(
                            onPressed: () => _showAgentInstructions(context, name),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, minimumSize: const Size(90, 32)),
                            child: const Text('How to Link', style: TextStyle(fontSize: 12))),
                      )),
                ]),
              );
            }))),
      ]),
    );
  }
}