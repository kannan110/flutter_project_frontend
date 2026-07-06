import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AREA MANAGEMENT
//
// CRUD for the Delivery Area master — used ONLY for dispatch/operations.
// This is deliberately independent of the Zone master (pricing-only).
// Mirrors the existing zones table shape (areas: id, trader_id, area_name,
// area_code, description, is_active, sort_order) and the get_areas RPC
// (mirrors get_zones exactly).
//
// Area is never read by pricing (get_effective_rate_v4, rate_zone_id, etc.)
// — those all continue to reference zones only.
// ─────────────────────────────────────────────────────────────────────────────

class AreaManagementScreen extends ConsumerStatefulWidget {
  const AreaManagementScreen({super.key});
  @override
  ConsumerState<AreaManagementScreen> createState() => _S();
}

class _S extends ConsumerState<AreaManagementScreen> {
  final _c = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _areas = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    if (mounted) setState(() => _loading = true);
    try {
      final rows = await _c.rpc('get_areas',
          params: {'p_trader_id': tid, 'p_active_only': false});
      if (mounted) {
        setState(() {
          _areas = List<Map<String, dynamic>>.from(rows as List? ?? []);
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

  Future<void> _createOrEdit({Map<String, dynamic>? existing}) async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    final nameCtrl = TextEditingController(text: existing?['area_name'] as String? ?? '');
    final codeCtrl = TextEditingController(text: existing?['area_code'] as String? ?? '');
    final descCtrl = TextEditingController(text: existing?['description'] as String? ?? '');
    bool submitting = false;
    String? err;

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        Future<void> submit() async {
          final name = nameCtrl.text.trim();
          final code = codeCtrl.text.trim();
          if (name.isEmpty) {
            setSheet(() => err = 'Area name is required');
            return;
          }
          setSheet(() { submitting = true; err = null; });
          try {
            if (existing == null) {
              await _c.from('areas').insert({
                'trader_id': tid,
                'area_name': name,
                'area_code': code.isEmpty ? null : code,
                'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
              });
            } else {
              await _c.from('areas').update({
                'area_name': name,
                'area_code': code.isEmpty ? null : code,
                'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                'updated_at': DateTime.now().toIso8601String(),
              }).eq('id', existing['id']);
            }
            if (ctx.mounted) Navigator.of(ctx, rootNavigator: true).pop();
          } catch (e) {
            setSheet(() {
              submitting = false;
              err = e.toString()
                  .replaceAll('Exception: ', '')
                  .replaceAll('PostgrestException(message: ', '');
            });
          }
        }

        return Container(
          padding: EdgeInsets.only(
              left: 20, right: 20, top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          decoration: const BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusCard)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(existing == null ? 'New Delivery Area' : 'Edit Delivery Area',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kNavy)),
            const SizedBox(height: 4),
            const Text('Operational area used for dispatch only — not linked to pricing.',
                style: TextStyle(fontSize: 12, color: kTextHint)),
            const SizedBox(height: 16),
            TextField(controller: nameCtrl, autofocus: true,
                decoration: const InputDecoration(labelText: 'Area Name', hintText: 'e.g. Ooty Main')),
            const SizedBox(height: 10),
            TextField(controller: codeCtrl,
                decoration: const InputDecoration(labelText: 'Area Code (optional)', hintText: 'e.g. OOTY-MAIN')),
            const SizedBox(height: 10),
            TextField(controller: descCtrl, maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes (optional)')),
            if (err != null) ...[
              const SizedBox(height: 10),
              Text(err!, style: const TextStyle(color: kError, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 48, width: double.infinity,
              child: ElevatedButton(
                onPressed: submitting ? null : submit,
                child: submitting
                    ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(existing == null ? 'Create Area' : 'Save Changes',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        );
      }),
    );
    _load();
  }

  Future<void> _toggleActive(Map<String, dynamic> area) async {
    try {
      await _c.from('areas')
          .update({'is_active': !(area['is_active'] as bool)})
          .eq('id', area['id']);
      _load();
    } catch (e) {
      if (mounted) showError(context, e.toString());
    }
  }

  Future<void> _delete(Map<String, dynamic> area) async {
    final count = (area['retailer_count'] as num?)?.toInt() ?? 0;
    if (count > 0) {
      showError(context,
          '${area['area_name']} has $count retailer(s) tagged. Reassign them first, or mark it Inactive instead.');
      return;
    }
    final ok = await confirmDialog(context,
        title: 'Delete Delivery Area',
        message: 'Delete "${area['area_name']}"? This cannot be undone.',
        confirmText: 'Delete', confirmColor: Colors.red);
    if (!ok) return;
    try {
      await _c.from('areas').delete().eq('id', area['id']);
      _load();
      if (mounted) showSuccess(context, 'Deleted ✓');
    } catch (e) {
      if (mounted) showError(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kBgPage,
    appBar: AppBar(
      backgroundColor: kSurface,
      title: const Text('Delivery Areas'),
      actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        // Guaranteed-visible create entry point — the bottom FAB can end
        // up visually hidden behind this app's persistent glass bottom
        // nav bar (a nested-Scaffold quirk), so the create action isn't
        // solely dependent on it.
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          tooltip: 'New Delivery Area',
          onPressed: () => _createOrEdit(),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _createOrEdit(),
      icon: const Icon(Icons.add),
      label: const Text('New Area'),
    ),
    body: _loading
        ? const LoadingList()
        : RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          WhiteCard(
            child: Row(children: [
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Bulk Assign Retailers',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  SizedBox(height: 2),
                  Text('Tag many retailers with one Delivery Area at once',
                      style: TextStyle(fontSize: 12, color: kTextHint)),
                ]),
              ),
              FilledButton.icon(
                onPressed: () => context.push(R.bulkAreaAssign),
                icon: const Icon(Icons.checklist_rtl, size: 18),
                label: const Text('Open'),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _createOrEdit(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New Delivery Area'),
            ),
          ),
          const SizedBox(height: 16),
          if (_areas.isEmpty)
            const EmptyState(
                icon: Icons.map_outlined,
                message: 'No Delivery Areas yet',
                sub: 'Create areas like "Ooty Main" or "Coonoor" to group '
                    'confirmed orders for dispatch — independent of pricing Zones.')
          else
            ..._areas.map((a) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: WhiteCard(
                child: Row(children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                        color: (a['is_active'] as bool ? kPrimary : kTextHint)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(kRadiusInner)),
                    child: Icon(Icons.map_outlined,
                        color: a['is_active'] as bool ? kPrimary : kTextHint, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a['area_name'] as String,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      Text(
                          '${a['area_code'] ?? '—'} · ${a['retailer_count']} retailers',
                          style: const TextStyle(fontSize: 12, color: kTextSub)),
                    ]),
                  ),
                  if (!(a['is_active'] as bool))
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: StatusBadge('inactive', kTextHint, small: true),
                    ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') _createOrEdit(existing: a);
                      if (v == 'toggle') _toggleActive(a);
                      if (v == 'delete') _delete(a);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(
                          value: 'toggle',
                          child: Text(a['is_active'] as bool ? 'Mark Inactive' : 'Mark Active')),
                      const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ]),
              ),
            )),
        ],
      ),
    ),
  );
}