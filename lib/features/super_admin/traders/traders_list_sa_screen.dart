import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class TradersListSaScreen extends StatefulWidget {
  const TradersListSaScreen({super.key});
  @override State<TradersListSaScreen> createState() => _S();
}

class _S extends State<TradersListSaScreen> {
  final _c = Supabase.instance.client;
  List<Map<String,dynamic>> _all      = [];
  List<Map<String,dynamic>> _filtered = [];
  bool   _loading = true;
  String _filter  = 'all';
  String _search  = '';

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final res = await _c.rpc('get_all_traders');
      if (!mounted) return;
      setState(() {
        _all = List<Map<String,dynamic>>.from(res as List? ?? []);
        _applyFilter();
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    var list = List<Map<String,dynamic>>.from(_all);
    if (_filter != 'all') {
      list = list.where((t) {
        if (_filter == 'pending')   return t['approval_status'] == 'pending';
        if (_filter == 'suspended') return t['status'] == 'suspended';
        if (_filter == 'active')    return t['status'] == 'active' && t['approval_status'] == 'approved';
        return true;
      }).toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((t) =>
      (t['company_name'] as String? ?? '').toLowerCase().contains(q) ||
          (t['company_code'] as String? ?? '').toLowerCase().contains(q) ||
          (t['city']         as String? ?? '').toLowerCase().contains(q)
      ).toList();
    }
    _filtered = list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        title: const Text('All Traders'),
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            onChanged: (v) => setState(() { _search = v; _applyFilter(); }),
            decoration: const InputDecoration(
                hintText: 'Search by name, code, city...',
                prefixIcon: Icon(Icons.search, size: 18),
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            for (final f in ['all', 'pending', 'active', 'suspended'])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(f[0].toUpperCase() + f.substring(1),
                      style: const TextStyle(fontSize: 12)),
                  selected: _filter == f,
                  onSelected: (_) => setState(() { _filter = f; _applyFilter(); }),
                  selectedColor: kNavy.withValues(alpha: 0.15),
                  checkmarkColor: kNavy,
                ),
              ),
          ]),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('${_filtered.length} traders',
                style: const TextStyle(fontSize: 12, color: kTextSub)),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _loading
              ? const LoadingList()
              : _filtered.isEmpty
              ? const EmptyState(
              icon: Icons.business_outlined,
              message: 'No traders found')
              : RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final t = _filtered[i];
                return _TraderCard(
                    trader: t,
                    onTap: () => context.push(
                        R.saTraderDetail(t['id'] as String)));
              },
            ),
          ),
        ),
      ]),
    );
  }
}

class _TraderCard extends StatelessWidget {
  const _TraderCard({required this.trader, required this.onTap});
  final Map<String,dynamic> trader;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status   = trader['status']          as String? ?? 'active';
    final approval = trader['approval_status'] as String? ?? 'approved';
    final endDate  = DateTime.tryParse(trader['subscription_end_date'] ?? '');
    final daysLeft = endDate?.difference(DateTime.now()).inDays;
    final isExpiring = daysLeft != null && daysLeft <= 7 && daysLeft >= 0;

    final Color c = switch (approval == 'pending' ? 'pending' : status) {
      'active'    => Colors.green,
      'pending'   => Colors.orange,
      'suspended' => Colors.deepOrange,
      _           => Colors.grey,
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(kRadiusCard),
            border: Border.all(
                color: approval == 'pending'
                    ? Colors.orange.withValues(alpha: 0.45)
                    : isExpiring ? Colors.red.withValues(alpha: 0.35) : kBorderLight,
                width: (approval == 'pending' || isExpiring) ? 1.5 : 0.8),
            boxShadow: kCardShadow),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
                color: c.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(kRadiusChip)),
            child: Center(
              child: Text(
                (trader['company_name'] as String? ?? '?')[0].toUpperCase(),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: c),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(trader['company_name'] as String? ?? '—',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: kNavy)),
            Text(
              '${trader['company_code'] ?? '—'} · '
                  '${trader['city'] ?? '—'} · '
                  '${trader['agent_count'] ?? 0} agents',
              style: const TextStyle(fontSize: 11, color: kTextSub),
            ),
            Text(trader['plan_name'] as String? ?? 'No plan',
                style: const TextStyle(fontSize: 10, color: kTextHint)),
            if (isExpiring)
              Text('⚠️ Expires in $daysLeft days',
                  style: const TextStyle(fontSize: 10, color: Colors.red,
                      fontWeight: FontWeight.w600)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(kRadiusChip)),
              child: Text(
                approval == 'pending' ? 'PENDING' : status.toUpperCase(),
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: c),
              ),
            ),
            const SizedBox(height: 4),
            const Icon(Icons.chevron_right_rounded, color: kTextHint, size: 18),
          ]),
        ]),
      ),
    );
  }
}