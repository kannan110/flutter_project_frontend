import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';

/// Assign / Unassign Retailers for one supervisor — shows every active
/// retailer for the trader, pre-checked for whichever are currently
/// assigned to THIS supervisor (retailers.supervisor_id = supervisorId).
/// Saving writes retailers.supervisor_id directly (assign = set to this
/// supervisor's id, unassign = set to NULL) — same simple FK approach
/// used at creation time in create_supervisor_screen.dart, just made
/// editable afterward too. Returns true if anything changed, so callers
/// know to refresh.
Future<bool> showAssignRetailersSheet(
    BuildContext context, {
      required String traderId,
      required String supervisorId,
      required String supervisorName,
    }) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => _AssignRetailersSheet(
      traderId: traderId, supervisorId: supervisorId, supervisorName: supervisorName,
    ),
  );
  return result ?? false;
}

class _AssignRetailersSheet extends StatefulWidget {
  const _AssignRetailersSheet({required this.traderId, required this.supervisorId, required this.supervisorName});
  final String traderId;
  final String supervisorId;
  final String supervisorName;

  @override State<_AssignRetailersSheet> createState() => _AssignRetailersSheetState();
}

class _AssignRetailersSheetState extends State<_AssignRetailersSheet> {
  final _c = Supabase.instance.client;
  final _search = TextEditingController();
  bool _loading = true, _saving = false;
  List<Map<String, dynamic>> _retailers = []; // id, shop_name, supervisor_id
  late Set<String> _selected;
  late Set<String> _initiallySelected;

  @override void initState() { super.initState(); _load(); }
  @override void dispose() { _search.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final r = await _c.from('retailers')
          .select('id,shop_name,supervisor_id')
          .eq('trader_id', widget.traderId).eq('is_active', true)
          .order('shop_name').limit(5000);
      final list = List<Map<String, dynamic>>.from(r as List? ?? []);
      final mine = list.where((x) => x['supervisor_id'] == widget.supervisorId).map((x) => x['id'] as String).toSet();
      if (mounted) setState(() {
        _retailers = list;
        _selected = {...mine};
        _initiallySelected = {...mine};
        _loading = false;
      });
    } catch (e) {
      if (mounted) { setState(() => _loading = false); showError(context, e.toString()); }
    }
  }

  Future<void> _save() async {
    final toAssign   = _selected.difference(_initiallySelected);
    final toUnassign = _initiallySelected.difference(_selected);
    if (toAssign.isEmpty && toUnassign.isEmpty) {
      Navigator.of(context, rootNavigator: true).pop(false);
      return;
    }
    if (mounted) setState(() => _saving = true);
    try {
      if (toAssign.isNotEmpty) {
        await _c.from('retailers').update({'supervisor_id': widget.supervisorId}).inFilter('id', toAssign.toList());
      }
      if (toUnassign.isNotEmpty) {
        // Only clear if still pointing at THIS supervisor — a defensive
        // no-op in the normal case, but avoids ever clobbering a
        // reassignment made by someone else between load and save.
        await _c.from('retailers').update({'supervisor_id': null})
            .inFilter('id', toUnassign.toList()).eq('supervisor_id', widget.supervisorId);
      }
      if (mounted) Navigator.of(context, rootNavigator: true).pop(true);
    } catch (e) {
      if (mounted) { setState(() => _saving = false); showError(context, e.toString().replaceAll('Exception: ', '')); }
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _retailers;
    return _retailers.where((r) => (r['shop_name'] as String? ?? '').toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return DraggableScrollableSheet(
      initialChildSize: 0.85, minChildSize: 0.5, maxChildSize: 0.95, expand: false,
      builder: (ctx, scrollCtrl) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Assign Retailers — ${widget.supervisorName}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
              Text('${_selected.length} assigned', style: const TextStyle(fontSize: 12, color: kTextSub, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search retailers…',
                prefixIcon: const Icon(Icons.search, size: 18),
                filled: true, fillColor: kBgPage,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorderLight)),
              ),
            ),
            const Divider(height: 24),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('No matches', style: TextStyle(color: kTextHint)))
                  : ListView.separated(
                controller: scrollCtrl,
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = filtered[i];
                  final id = r['id'] as String;
                  final assignedElsewhere = r['supervisor_id'] != null && r['supervisor_id'] != widget.supervisorId
                      && !_selected.contains(id);
                  return CheckboxListTile(
                    value: _selected.contains(id),
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    title: Text(r['shop_name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                    subtitle: assignedElsewhere
                        ? const Text('Assigned to another supervisor — checking will move it here',
                        style: TextStyle(fontSize: 11, color: Colors.orange))
                        : null,
                    onChanged: (v) => setState(() {
                      if (v == true) _selected.add(id); else _selected.remove(id);
                    }),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(height: 50, child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
            )),
          ]),
        ),
      ),
    );
  }
}