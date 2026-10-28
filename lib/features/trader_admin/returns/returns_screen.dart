import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import 'return_create_screen.dart';

class ReturnsScreen extends ConsumerStatefulWidget {
  const ReturnsScreen({super.key});

  @override
  ConsumerState<ReturnsScreen> createState() => _S();
}

class _S extends ConsumerState<ReturnsScreen> {
  final _c = Supabase.instance.client;
  List<Map<String, dynamic>> _returns = [];
  List<Map<String, dynamic>> _filtered = [];
  final _searchCtrl = TextEditingController();

  void _applySearch(String q) {
    if (!mounted) return;
    final lower = q.trim().toLowerCase();
    setState(() => _filtered = lower.isEmpty
        ? List.from(_returns)
        : _returns.where((r) {
      final ret = r['retailers'] as Map<String,dynamic>?;
      final ag  = r['delivery_agents'] as Map<String,dynamic>?;
      return (ret?['shop_name'] as String? ?? '').toLowerCase().contains(lower) ||
          (ag?['name']       as String? ?? '').toLowerCase().contains(lower);
    }).toList());
  }

  // Stock summary from returns
  int _totalReturnedBirds = 0;
  double _totalReturnedKg = 0;
  bool _loading = true;
  String _filter = 'all';

  @override
  void initState() {
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
      var q = _c
          .from('return_entries')
          .select(
          'id,return_type,return_date,bird_count,weight_kg,reason,status,stock_credited,created_at,'
              'retailers(shop_name),delivery_agents(name),master_products(name),'
              'credit_notes(id,credit_number,total_amount)')
          .eq('trader_id', tid);
      if (_filter != 'all') q = q.eq('status', _filter);
      final r = await q.order('created_at', ascending: false).limit(100);
      // Return stock summary from stock_ledger
      final sl = await _c
          .from('stock_ledger')
          .select('quantity_birds,quantity_kg')
          .eq('trader_id', tid)
          .eq('movement_type', 'returned_in');
      if (!mounted) return;
      int birds = 0;
      double kg = 0;
      for (final s in sl) {
        birds += (s['quantity_birds'] as num?)?.toInt() ?? 0;
        kg += (s['quantity_kg'] as num?)?.toDouble() ?? 0;
      }
      if (mounted) {
        setState(() {
          _returns = List<Map<String, dynamic>>.from(r);
          _applySearch(_searchCtrl.text);
          _totalReturnedBirds = birds;
          _totalReturnedKg = kg;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      showError(context, e.toString());
    }
  }

  Future<void> _openCreateReturn() async {
    final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const ReturnCreateScreen()));
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kBgPage,
    appBar: AppBar(
        backgroundColor: kSurface,
        title: const Text('Returns'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh_rounded), onPressed: _load)
        ]),
    // Reserve space so FAB clears the parent TraderShell glass bottom nav
    bottomNavigationBar: const SizedBox(height: kBottomNavClearance),
    floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateReturn,
        icon: const Icon(Icons.assignment_return_outlined),
        label: const Text('Process Return')),
    body: _loading
        ? const LoadingList()
        : Column(children: [
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: AppSearchBar(
          controller: _searchCtrl,
          hint: 'Search by shop or agent…',
          onChanged: _applySearch,
          onClear: () { _searchCtrl.clear(); _applySearch(''); },
        ),
      ),
      const Divider(height: 1),
      // Stock integration summary
      if (_totalReturnedBirds > 0)
        Container(
            decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [kNavy, kNavyMid],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight)),
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius:
                      BorderRadius.circular(kRadiusChip)),
                  child: const Icon(Icons.assignment_return_outlined,
                      color: Colors.white, size: 22)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('TOTAL RETURNED TO STOCK',
                            style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFFB4C6F4),
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6)),
                        Text(
                            '$_totalReturnedBirds birds · ${_totalReturnedKg.toStringAsFixed(1)} kg',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: kGoldLight)),
                        const Text('Available for redelivery',
                            style: TextStyle(
                                fontSize: 10, color: Color(0xFFB4C6F4))),
                      ])),
            ])),
      // Filter
      Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('All')),
                ButtonSegment(
                    value: 'pending', label: Text('Pending')),
                ButtonSegment(
                    value: 'processed', label: Text('Processed'))
              ],
              selected: {
                _filter
              },
              onSelectionChanged: (s) {
                if (mounted) setState(() => _filter = s.first);
                _load();
              })),
      const Divider(height: 1),
      Expanded(
          child: _returns.isEmpty
              ? const EmptyState(
              icon: Icons.assignment_return_outlined,
              message: 'No returns recorded')
              : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, kBottomNavClearance),
              itemCount: _filtered.length,
              separatorBuilder: (_, __) =>
              const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final r = _filtered[i];
                final retailer =
                r['retailers'] as Map<String, dynamic>?;
                final agent =
                r['delivery_agents'] as Map<String, dynamic>?;
                final product =
                r['master_products'] as Map<String, dynamic>?;
                final date = DateTime.tryParse(
                    r['return_date'] as String? ?? '');
                final status =
                    r['status'] as String? ?? 'pending';
                final credited =
                    r['stock_credited'] as bool? ?? false;
                // ★ NEW: reverse-embedded credit note (nested relationship
                // returns a List even though return_id is unique per note).
                final creditNotesRaw = r['credit_notes'];
                final creditNote = creditNotesRaw is List && creditNotesRaw.isNotEmpty
                    ? Map<String, dynamic>.from(creditNotesRaw.first as Map)
                    : (creditNotesRaw is Map ? Map<String, dynamic>.from(creditNotesRaw) : null);
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: kSurface,
                      borderRadius:
                      BorderRadius.circular(kRadiusCard),
                      boxShadow: kCardShadow,
                      border: Border.all(
                          color: status == 'processed'
                              ? Colors.green
                              .withValues(alpha: 0.3)
                              : Colors.orange
                              .withValues(alpha: 0.3),
                          width: 1.2)),
                  child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(
                                  retailer?['shop_name']
                                  as String? ??
                                      '—',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                      color: kNavy))),
                          StatusBadge(
                              status,
                              status == 'processed'
                                  ? Colors.green
                                  : Colors.orange),
                        ]),
                        const SizedBox(height: 6),
                        Row(children: [
                          const Icon(Icons.delivery_dining,
                              size: 13, color: kTextHint),
                          const SizedBox(width: 4),
                          Text(agent?['name'] as String? ?? '—',
                              style: const TextStyle(
                                  fontSize: 11, color: kTextSub)),
                          const SizedBox(width: 12),
                          StatusBadge(
                              r['return_type'] as String? ?? '—',
                              Colors.blue,
                              small: true),
                        ]),
                        const SizedBox(height: 6),
                        if (product?['name'] != null) ...[
                          const SizedBox(height: 4),
                          Text(product!['name'] as String,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: kNavy)),
                        ],
                        const SizedBox(height: 2),
                        Row(children: [
                          Text(
                              '${r['bird_count'] ?? 0} birds · ${(r['weight_kg'] as num?)?.toStringAsFixed(1) ?? 0} kg',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                          const Spacer(),
                          if (credited)
                            Row(children: [
                              Icon(Icons.check_circle,
                                  color: Colors.green.shade600,
                                  size: 14),
                              const SizedBox(width: 4),
                              Text('Stock Updated ✓',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color:
                                      Colors.green.shade700,
                                      fontWeight:
                                      FontWeight.w600))
                            ]),
                          if (date != null) ...[
                            const SizedBox(width: 8),
                            Text(DateFormat('d MMM').format(date),
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: kTextHint))
                          ],
                        ]),
                        if (r['reason'] != null)
                          Padding(
                              padding:
                              const EdgeInsets.only(top: 4),
                              child: Text(r['reason'] as String,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: kTextSub),
                                  maxLines: 2,
                                  overflow:
                                  TextOverflow.ellipsis)),
                        if (creditNote != null) ...[
                          const Divider(height: 14),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text(
                                'Credit: ${Fmt.amount((creditNote['total_amount'] as num?)?.toDouble() ?? 0)}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF6A1B9A))),
                            TextButton.icon(
                              onPressed: () => context.push(
                                  R.creditNoteDetailPath(creditNote['id'] as String)),
                              icon: const Icon(Icons.receipt_outlined, size: 14),
                              label: Text(creditNote['credit_number'] as String? ?? 'View Credit Note',
                                  style: const TextStyle(fontSize: 11)),
                            ),
                          ]),
                        ],
                      ]),
                );
              })),
    ]),
  );
}