import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/responsive_layout.dart';

class ShiftsScreen extends ConsumerStatefulWidget {
  const ShiftsScreen({super.key});
  @override ConsumerState<ShiftsScreen> createState() => _S();
}
class _S extends ConsumerState<ShiftsScreen> {
  final _c = Supabase.instance.client;
  List<Map<String,dynamic>> _shifts = [];
  List<Map<String,dynamic>> _filtered = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  void _applySearch(String q) {
    if (!mounted) return;
    final lower = q.trim().toLowerCase();
    setState(() => _filtered = lower.isEmpty
        ? List.from(_shifts)
        : _shifts.where((s) {
            final a = s['delivery_agents'] as Map<String,dynamic>?;
            return (a?['name'] as String? ?? '').toLowerCase().contains(lower) ||
                   (a?['vehicle_no'] as String? ?? '').toLowerCase().contains(lower);
          }).toList());
  }

  @override void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => _applySearch(_searchCtrl.text));
  }

  @override void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null || !mounted) return;
    if (mounted) setState(() => _loading = true);
    try {
      final data = await _c.from('delivery_shifts')
          .select('id,status,shift_start_at,shift_end_at,total_cash_collected,total_orders,total_birds_delivered,total_expenses,shift_approval_status,delivery_agents(name,vehicle_no)')
          .eq('trader_id', tid).order('shift_start_at', ascending: false).limit(60);
      if (!mounted) return;
      if (mounted) setState(() { _shifts = List<Map<String,dynamic>>.from(data); _loading = false; _applySearch(_searchCtrl.text); });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final pendingApprovals = _shifts.where((s) => s['status'] == 'closed' && s['shift_approval_status'] == 'pending').length;
    final _scaffold = Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: Row(children: [
          const Text('Shifts'),
          if (pendingApprovals > 0) ...[const SizedBox(width: 8),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(10)),
                child: Text('$pendingApprovals to review', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)))],
        ]),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: AppSearchBar(
            controller: _searchCtrl,
            hint: 'Search by agent or vehicle…',
            onChanged: _applySearch,
            onClear: () { _searchCtrl.clear(); _applySearch(''); },
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _loading ? const LoadingList() : _shifts.isEmpty
          ? const EmptyState(icon: Icons.schedule_outlined, message: 'No shifts yet')
          : _filtered.isEmpty
          ? const EmptyState(icon: Icons.search_off_rounded, message: 'No shifts match')
          : RefreshIndicator(onRefresh: _load, child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, kBottomNavClearance),
            itemCount: _filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final s = _filtered[i];
            final a = s['delivery_agents'] as Map<String,dynamic>?;
            final shiftStatus = s['status'] as String? ?? 'open';
            final approvalStatus = s['shift_approval_status'] as String? ?? 'pending';
            final startAt = DateTime.tryParse(s['shift_start_at'] as String? ?? '');
            final cash = (s['total_cash_collected'] as num?)?.toDouble() ?? 0;
            final needsReview = shiftStatus == 'closed' && approvalStatus == 'pending';

            return InkWell(
              onTap: () => context.push(R.shiftDetailPath(s['id'])),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: Colors.white, borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: needsReview ? Colors.orange.shade300 : kBorder, width: needsReview ? 1.5 : 1)),
                  child: Row(children: [
                    Container(width: 44, height: 44, decoration: BoxDecoration(
                        color: shiftStatus == 'open' ? kPrimary.withValues(alpha: 0.1) : Colors.grey.shade100, shape: BoxShape.circle),
                        child: Icon(shiftStatus == 'open' ? Icons.play_circle_outline : Icons.check_circle_outline,
                            color: shiftStatus == 'open' ? kPrimary : Colors.grey.shade500, size: 22)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a?['name'] as String? ?? '—', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      if (startAt != null) Text(DateFormat('d MMM y, h:mm a').format(startAt), style: const TextStyle(fontSize: 11, color: kTextHint)),
                      Text('${s['total_orders'] ?? 0} orders · ${Fmt.amount(cash)}', style: const TextStyle(fontSize: 11, color: kTextSub)),
                    ])),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      StatusBadge(shiftStatus, SC.shift(shiftStatus)),
                      const SizedBox(height: 4),
                      if (needsReview) const StatusBadge('REVIEW', Colors.orange, small: true)
                      else if (approvalStatus == 'approved') const StatusBadge('APPROVED', Colors.green, small: true),
                    ]),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, color: kTextHint, size: 18),
                  ])),
            );
          }))),
      ]),
    );
    return ResponsiveLayout(mobile: (_) => _scaffold, desktop: (_) => _scaffold);
  }
}