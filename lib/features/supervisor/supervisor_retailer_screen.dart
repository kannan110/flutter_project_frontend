import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';

/// Assigned-only retailer list ("View assigned retailers" permission —
/// filtered by retailers.supervisor_id, never the trader's full list).
/// Doubles as a picker: when reached with `extra: {'pickMode': true}`
/// (as the Dashboard's Collect Cash button does), tapping a retailer
/// pops the id back to the caller instead of opening the ledger.
class SupervisorRetailersScreen extends ConsumerStatefulWidget {
  const SupervisorRetailersScreen({super.key});
  @override ConsumerState<SupervisorRetailersScreen> createState() => _S();
}

class _S extends ConsumerState<SupervisorRetailersScreen> {
  final _c = Supabase.instance.client;
  final _search = TextEditingController();
  bool _loading = true;
  List<Map<String, dynamic>> _retailers = [];

  @override void initState() { super.initState(); _load(); }
  @override void dispose() { _search.dispose(); super.dispose(); }

  Future<void> _load() async {
    final supId = ref.read(appUserProvider).valueOrNull?.supervisorId;
    if (supId == null) { if (mounted) setState(() => _loading = false); return; }
    if (mounted) setState(() => _loading = true);
    try {
      final r = await _c.from('retailers')
          .select('id,shop_name,owner_name,phone,outstanding_balance')
          .eq('supervisor_id', supId).eq('is_active', true)
          .order('shop_name');
      if (mounted) setState(() { _retailers = List<Map<String, dynamic>>.from(r as List? ?? []); _loading = false; });
    } catch (e) {
      if (mounted) { setState(() => _loading = false); showError(context, e.toString()); }
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _retailers;
    return _retailers.where((r) => (r['shop_name'] as String? ?? '').toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final extra = GoRouterState.of(context).extra;
    final pickMode = extra is Map && extra['pickMode'] == true;

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(backgroundColor: kSurface,
          title: Text(pickMode ? 'Select Retailer to Collect' : 'My Retailers')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(16), children: [
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search retailers…',
              prefixIcon: const Icon(Icons.search, size: 18),
              filled: true, fillColor: kSurface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorderLight)),
            ),
          ),
          const SizedBox(height: 12),
          if (_filtered.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 40),
                child: Center(child: Text('No retailers assigned to you yet.', style: TextStyle(color: kTextHint)))),
          ..._filtered.map((r) {
            final outstanding = (r['outstanding_balance'] as num?)?.toDouble() ?? 0;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(color: kBorderLight), boxShadow: kCardShadow),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                leading: CircleAvatar(backgroundColor: kNavy.withValues(alpha: 0.08),
                    child: Text(
                        ((r['shop_name'] as String? ?? '?').isEmpty ? '?' : (r['shop_name'] as String).substring(0, 1)).toUpperCase(),
                        style: const TextStyle(color: kNavy, fontWeight: FontWeight.w900))),
                title: Text(r['shop_name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(r['owner_name'] as String? ?? r['phone'] as String? ?? '',
                    style: const TextStyle(fontSize: 12, color: kTextSub)),
                trailing: Text(Fmt.amount(outstanding),
                    style: TextStyle(fontWeight: FontWeight.w800,
                        color: outstanding > 0 ? Colors.orange.shade700 : Colors.green.shade700)),
                onTap: () {
                  if (pickMode) {
                    context.pop(r['id'] as String);
                  } else {
                    context.push(R.supervisorLedgerPath(r['id'] as String));
                  }
                },
              ),
            );
          }),
        ]),
      ),
    );
  }
}