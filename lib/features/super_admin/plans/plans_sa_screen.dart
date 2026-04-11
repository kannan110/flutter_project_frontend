import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';

class PlansSaScreen extends StatefulWidget {
  const PlansSaScreen({super.key});
  @override State<PlansSaScreen> createState() => _S();
}

class _S extends State<PlansSaScreen> {
  final _c = Supabase.instance.client;
  List<Map<String,dynamic>> _plans = [];
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final res = await _c.from('subscription_plans').select().order('base_price');
      if (!mounted) return;
      setState(() {
        _plans = List<Map<String,dynamic>>.from(res as List? ?? []);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showForm({Map<String,dynamic>? existing}) async {
    final nameCtrl     = TextEditingController(text: existing?['name']);
    final priceCtrl    = TextEditingController(text: existing?['base_price']?.toString());
    final daysCtrl     = TextEditingController(text: existing?['duration_days']?.toString());
    final ordersCtrl   = TextEditingController(text: existing?['max_orders']?.toString() ?? '');
    final retailersCtrl= TextEditingController(text: existing?['max_retailers']?.toString() ?? '');
    final agentsCtrl   = TextEditingController(text: existing?['max_agents']?.toString() ?? '');
    final graceCtrl    = TextEditingController(text: (existing?['grace_days'] ?? 7).toString());
    final isEdit = existing != null;

    await showModalBottomSheet(
      context: context, isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            left: 20, right: 20, top: 24),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(isEdit ? 'Edit Plan' : 'New Plan',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          TextField(controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Plan Name *')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: priceCtrl, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Price (₹)', prefixText: '₹'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: daysCtrl, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Duration (days)', suffixText: 'd'))),
          ]),
          const SizedBox(height: 10),
          const Text('Limits (leave blank for unlimited)',
              style: TextStyle(fontSize: 11, color: kTextHint)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: ordersCtrl, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Max Orders'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: retailersCtrl, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Max Retailers'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: agentsCtrl, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Max Agents'))),
          ]),
          const SizedBox(height: 10),
          TextField(controller: graceCtrl, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Grace Days', suffixText: 'days')),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              try {
                await _c.rpc('super_admin_manage_plan', params: {
                  'p_action':        isEdit ? 'update' : 'create',
                  if (isEdit) 'p_plan_id': existing['id'],
                  'p_name':          nameCtrl.text.trim(),
                  'p_base_price':    int.tryParse(priceCtrl.text) ?? 0,
                  'p_duration_days': int.tryParse(daysCtrl.text),
                  'p_max_orders':    ordersCtrl.text.isEmpty ? null : int.tryParse(ordersCtrl.text),
                  'p_max_retailers': retailersCtrl.text.isEmpty ? null : int.tryParse(retailersCtrl.text),
                  'p_max_agents':    agentsCtrl.text.isEmpty ? null : int.tryParse(agentsCtrl.text),
                  'p_grace_days':    int.tryParse(graceCtrl.text) ?? 7,
                });
                if (mounted) {
                  showSuccess(context, isEdit ? 'Plan updated ✓' : 'Plan created ✓');
                  _load();
                }
              } catch (e) {
                if (mounted) showError(context, e.toString());
              }
            },
            child: Text(isEdit ? 'Save Changes' : 'Create Plan')),
          const SizedBox(height: 8),
        ]))));
  }

  Future<void> _toggle(Map<String,dynamic> p) async {
    final ok = await confirmDialog(context,
        title: p['is_active'] == true ? 'Deactivate Plan' : 'Activate Plan',
        message: 'This will ${p['is_active'] == true ? 'deactivate' : 'activate'} the "${p['name']}" plan.',
        confirmText: p['is_active'] == true ? 'Deactivate' : 'Activate',
        confirmColor: p['is_active'] == true ? Colors.red : Colors.green);
    if (!ok) return;
    try {
      await _c.rpc('super_admin_manage_plan', params: {
        'p_action': 'toggle', 'p_plan_id': p['id'],
      });
      _load();
    } catch (e) {
      if (mounted) showError(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Subscription Plans'),
      actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
    floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add Plan')),
    body: _loading ? const LoadingList()
        : ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: _plans.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final p = _plans[i];
              final isActive = p['is_active'] == true;
              final features = (p['features'] as Map?)?.cast<String,dynamic>() ?? {};
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: isActive ? Colors.white : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isActive ? kBorder : Colors.grey.shade300,
                        width: isActive ? 1 : 1)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p['name'] as String,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                              color: isActive ? kPrimary : Colors.grey)),
                      Text('₹${p['base_price']} · ${p['duration_days'] ?? '—'} days · '
                           '${p['grace_days'] ?? 7}d grace',
                          style: const TextStyle(fontSize: 12, color: kTextSub)),
                    ])),
                    Row(children: [
                      IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18, color: kPrimary),
                          onPressed: () => _showForm(existing: p)),
                      Switch(value: isActive, onChanged: (_) => _toggle(p), activeColor: kPrimary),
                    ]),
                  ]),
                  const Divider(height: 14),
                  Wrap(spacing: 12, runSpacing: 4, children: [
                    _limit('Orders',    p['max_orders']),
                    _limit('Retailers', p['max_retailers']),
                    _limit('Agents',    p['max_agents']),
                  ]),
                  if (features.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, children: features.entries
                        .where((e) => e.value != false)
                        .map((e) => Chip(
                            label: Text('${e.key}: ${e.value}',
                                style: const TextStyle(fontSize: 10)),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: EdgeInsets.zero,
                            backgroundColor: kPrimary.withValues(alpha: 0.08)))
                        .toList()),
                  ],
                ]));
            }));

  Widget _limit(String label, dynamic val) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(6)),
    child: Text('$label: ${val ?? '∞'}',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)));
}
