import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';

/// Shows transfer history for the current agent (both sent and received)
class TransferHistoryScreen extends ConsumerStatefulWidget {
  const TransferHistoryScreen({super.key});

  @override
  ConsumerState<TransferHistoryScreen> createState() => _S();
}

class _S extends ConsumerState<TransferHistoryScreen> {
  final _c = Supabase.instance.client;
  List<Map<String, dynamic>> _transfers = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  void _applySearch(String q) {
    if (!mounted) return;
    final lower = q.trim().toLowerCase();
    setState(() => _filtered = lower.isEmpty
        ? List.from(_transfers)
        : _transfers.where((t) {
            final fa = t['from_agent'] as Map<String,dynamic>?;
            final ta = t['to_agent']   as Map<String,dynamic>?;
            return (fa?['name'] as String? ?? '').toLowerCase().contains(lower) ||
                   (ta?['name'] as String? ?? '').toLowerCase().contains(lower);
          }).toList());
  }

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => _applySearch(_searchCtrl.text));
  }
  @override void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    final agentId = ref.read(appUserProvider).valueOrNull?.agentId;
    if (agentId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      final sent = await _c
          .from('bird_transfers')
          .select('*,'
              'from_agent:delivery_agents!bird_transfers_from_agent_id_fkey(name,vehicle_no),'
              'to_agent:delivery_agents!bird_transfers_to_agent_id_fkey(name,vehicle_no)')
          .or('from_agent_id.eq.$agentId,to_agent_id.eq.$agentId')
          .order('created_at', ascending: false)
          .limit(50);
      if (!mounted) return;
      setState(() {
        _transfers = List<Map<String, dynamic>>.from(sent as List? ?? []);
        _loading = false;
        _applySearch(_searchCtrl.text);
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final agentId = ref.read(appUserProvider).valueOrNull?.agentId;
    return Scaffold(
      appBar: AppBar(title: const Text('Transfer History'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load)
      ]),
      body: Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: AppSearchBar(
            controller: _searchCtrl,
            hint: 'Search by agent name…',
            onChanged: _applySearch,
            onClear: () { _searchCtrl.clear(); _applySearch(''); },
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _loading
          ? const LoadingList()
          : _transfers.isEmpty
              ? const EmptyState(
                  icon: Icons.swap_horiz, message: 'No bird transfers yet')
              : _filtered.isEmpty
              ? const EmptyState(icon: Icons.search_off_rounded, message: 'No transfers match')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                      16, 16, 16, kBottomNavClearance),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final t = _filtered[i];
                    final isOut = t['from_agent_id'] == agentId;
                    final other = isOut
                        ? t['to_agent'] as Map<String, dynamic>?
                        : t['from_agent'] as Map<String, dynamic>?;
                    final birds = (t['bird_count'] as num?)?.toInt() ?? 0;
                    final weight = (t['weight_kg'] as num?)?.toDouble() ?? 0;
                    final date = t['transfer_date'] as String?;
                    final reason = t['transfer_reason'] as String?;

                    return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: isOut
                                    ? Colors.orange.shade200
                                    : Colors.green.shade200,
                                width: 1.5)),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                        color: isOut
                                            ? Colors.orange.shade100
                                            : Colors.green.shade100,
                                        borderRadius: BorderRadius.circular(6)),
                                    child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                              isOut
                                                  ? Icons.arrow_upward
                                                  : Icons.arrow_downward,
                                              size: 12,
                                              color: isOut
                                                  ? Colors.orange
                                                  : Colors.green),
                                          const SizedBox(width: 4),
                                          Text(isOut ? 'SENT' : 'RECEIVED',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w800,
                                                  color: isOut
                                                      ? Colors.orange
                                                      : Colors.green)),
                                        ])),
                                const Spacer(),
                                if (date != null)
                                  Text(
                                      DateFormat('d MMM y')
                                          .format(DateTime.parse(date)),
                                      style: const TextStyle(
                                          fontSize: 11, color: kTextHint)),
                              ]),
                              const SizedBox(height: 8),
                              Row(children: [
                                Icon(Icons.delivery_dining,
                                    size: 16,
                                    color:
                                        isOut ? Colors.orange : Colors.green),
                                const SizedBox(width: 6),
                                Text(isOut ? 'To: ' : 'From: ',
                                    style: const TextStyle(
                                        fontSize: 12, color: kTextSub)),
                                Text(other?['name'] as String? ?? '—',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700)),
                              ]),
                              const SizedBox(height: 6),
                              Row(children: [
                                _chip('$birds birds', Icons.set_meal_outlined),
                                const SizedBox(width: 12),
                                _chip('${weight.toStringAsFixed(1)} kg',
                                    Icons.balance_outlined),
                              ]),
                              if (reason != null && reason.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text('Reason: $reason',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: kTextSub,
                                        fontStyle: FontStyle.italic)),
                              ],
                              const SizedBox(height: 6),
                              Text(
                                  'ID: ${(t['id'] as String).substring(0, 8)}...',
                                  style: const TextStyle(
                                      fontSize: 10, color: kTextHint)),
                            ]));
                  }),
        ),
      ]),
    );
  }

  Widget _chip(String label, IconData icon) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: kPrimary),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: kPrimary)),
      ]);
}
