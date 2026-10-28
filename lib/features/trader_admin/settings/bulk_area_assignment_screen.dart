import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BULK AREA ASSIGNMENT
//
// One-time (and ongoing) cleanup tool: tag many retailers with one Delivery
// Area at once. Deliberately does NOT auto-fill Area = Zone — Area and Zone
// are independent geographies (per business decision), so this is a manual,
// explicit action every time. Calls the additive `bulk_assign_area` RPC —
// touches only retailers.area_id, nothing pricing-related.
// ─────────────────────────────────────────────────────────────────────────────

class BulkAreaAssignmentScreen extends ConsumerStatefulWidget {
  const BulkAreaAssignmentScreen({super.key});
  @override
  ConsumerState<BulkAreaAssignmentScreen> createState() => _S();
}

class _S extends ConsumerState<BulkAreaAssignmentScreen> {
  final _c = Supabase.instance.client;
  bool _loading = true, _submitting = false;
  List<Map<String, dynamic>> _retailers = [];
  List<Map<String, dynamic>> _areas = [];
  List<Map<String, dynamic>> _zones = [];
  String? _zoneFilter; // filter by pricing zone (helps locate the right group)
  String _search = '';
  String? _targetAreaId;
  final Set<String> _selected = {};
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => setState(() => _search = _searchCtrl.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    if (mounted) setState(() => _loading = true);
    try {
      final retailers = await _c.from('retailers')
          .select('id,shop_name,city,zone_id,area_id,zones(zone_name),areas(area_name)')
          .eq('trader_id', tid).eq('is_active', true)
          .order('shop_name');
      final areas = await _c.rpc('get_areas', params: {'p_trader_id': tid, 'p_active_only': true});
      final zones = await _c.from('zones')
          .select('id,zone_name').eq('trader_id', tid).eq('is_active', true).order('zone_name');
      if (mounted) {
        setState(() {
          _retailers = List<Map<String, dynamic>>.from(retailers as List? ?? []);
          _areas = List<Map<String, dynamic>>.from(areas as List? ?? []);
          _zones = List<Map<String, dynamic>>.from(zones as List? ?? []);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showError(context, e.toString());
      }
    }
  }

  List<Map<String, dynamic>> get _filtered {
    return _retailers.where((r) {
      if (_zoneFilter != null && r['zone_id'] != _zoneFilter) return false;
      if (_search.isNotEmpty) {
        final name = (r['shop_name'] as String? ?? '').toLowerCase();
        final city = (r['city'] as String? ?? '').toLowerCase();
        if (!name.contains(_search) && !city.contains(_search)) return false;
      }
      return true;
    }).toList();
  }

  void _selectAllVisible() {
    setState(() => _selected.addAll(_filtered.map((r) => r['id'] as String)));
  }

  void _clearSelection() => setState(() => _selected.clear());

  Future<void> _apply() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null || _targetAreaId == null || _selected.isEmpty) return;
    final areaName = _areas.firstWhere((a) => a['id'] == _targetAreaId)['area_name'] as String;
    final ok = await confirmDialog(context,
        title: 'Assign Delivery Area',
        message: 'Tag ${_selected.length} retailer(s) as "$areaName"? '
            'This only affects dispatch grouping, not pricing.',
        confirmText: 'Assign', confirmColor: kPrimary);
    if (!ok) return;
    if (mounted) setState(() => _submitting = true);
    try {
      final res = await _c.rpc('bulk_assign_area', params: {
        'p_trader_id': tid,
        'p_area_id': _targetAreaId,
        'p_retailer_ids': _selected.toList(),
      });
      final updated = (res as Map?)?['updated_count'] ?? _selected.length;
      if (mounted) {
        showSuccess(context, '✓ $updated retailer(s) tagged as $areaName');
        setState(() { _selected.clear(); _submitting = false; });
      }
      _load();
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        showError(context, e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(backgroundColor: kSurface, title: const Text('Bulk Area Assignment')),
      body: _loading
          ? const LoadingList()
          : Column(children: [
              Container(
                color: kSurface,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(children: [
                  AppSearchBar(
                    controller: _searchCtrl,
                    hint: 'Search retailer or city…',
                    onClear: () { _searchCtrl.clear(); setState(() => _search = ''); },
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    const Text('Filter by Zone:', style: TextStyle(fontSize: 12, color: kTextHint)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          ChoiceChip(
                            label: const Text('All'),
                            selected: _zoneFilter == null,
                            onSelected: (_) => setState(() => _zoneFilter = null),
                          ),
                          const SizedBox(width: 6),
                          ..._zones.map((z) => Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(z['zone_name'] as String),
                                  selected: _zoneFilter == z['id'],
                                  onSelected: (_) => setState(() => _zoneFilter = z['id'] as String),
                                ),
                              )),
                        ]),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Text('${_selected.length} selected · ${filtered.length} shown',
                        style: const TextStyle(fontSize: 12, color: kTextSub, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    TextButton(onPressed: _selectAllVisible, child: const Text('Select all shown')),
                    TextButton(onPressed: _clearSelection, child: const Text('Clear')),
                  ]),
                ]),
              ),
              const Divider(height: 1),
              Expanded(
                child: filtered.isEmpty
                    ? const EmptyState(icon: Icons.store_outlined, message: 'No retailers match')
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 160),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final r = filtered[i];
                          final id = r['id'] as String;
                          final currentArea = (r['areas'] as Map?)?['area_name'] as String?;
                          final currentZone = (r['zones'] as Map?)?['zone_name'] as String?;
                          final sel = _selected.contains(id);
                          return WhiteCard(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: CheckboxListTile(
                              value: sel,
                              onChanged: (_) => setState(
                                  () => sel ? _selected.remove(id) : _selected.add(id)),
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                              title: Text(r['shop_name'] as String,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                              subtitle: Text(
                                  '${r['city'] ?? '—'} · Zone: ${currentZone ?? '—'} · '
                                  'Area: ${currentArea ?? 'Unassigned'}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: currentArea == null ? Colors.orange.shade800 : kTextHint)),
                            ),
                          );
                        },
                      ),
              ),
            ]),
      bottomSheet: _selected.isEmpty
          ? null
          : Container(
              padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
              decoration: BoxDecoration(
                color: kSurface,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, -2))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  initialValue: _targetAreaId,
                  decoration: const InputDecoration(labelText: 'Assign to Delivery Area'),
                  items: _areas.map((a) => DropdownMenuItem(
                      value: a['id'] as String, child: Text(a['area_name'] as String))).toList(),
                  onChanged: (v) => setState(() => _targetAreaId = v),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 50, width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (_targetAreaId == null || _submitting) ? null : _apply,
                    child: _submitting
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text('Assign to ${_selected.length} retailer(s)',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
    );
  }
}
