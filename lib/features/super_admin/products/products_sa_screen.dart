import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';

class ProductsSaScreen extends StatefulWidget {
  const ProductsSaScreen({super.key});
  @override State<ProductsSaScreen> createState() => _S();
}

class _S extends State<ProductsSaScreen> {
  final _c = Supabase.instance.client;
  List<Map<String,dynamic>> _products = [];
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final res = await _c.from('master_products').select().order('category').order('name');
      if (!mounted) return;
      setState(() {
        _products = List<Map<String,dynamic>>.from(res as List? ?? []);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showForm({Map<String,dynamic>? existing}) async {
    final nameCtrl   = TextEditingController(text: existing?['name']);
    final tamilCtrl  = TextEditingController(text: existing?['name_tamil']);
    final catCtrl    = TextEditingController(text: existing?['category']);
    final descCtrl   = TextEditingController(text: existing?['description']);
    String unit = existing?['unit'] as String? ?? 'kg';
    final isEdit = existing != null;

    final saved = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) =>
        Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              left: 20, right: 20, top: 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(isEdit ? 'Edit Product' : 'New Product',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TextField(controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Product Name (English) *')),
            const SizedBox(height: 10),
            TextField(controller: tamilCtrl,
                decoration: const InputDecoration(labelText: 'Name (Tamil)')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: catCtrl,
                  decoration: const InputDecoration(labelText: 'Category',
                      hintText: 'e.g. Broiler, Country'))),
              const SizedBox(width: 12),
              Expanded(child: DropdownButtonFormField<String>(
                value: unit,
                decoration: const InputDecoration(labelText: 'Unit'),
                items: ['kg','birds','dozen'].map((u) =>
                    DropdownMenuItem(value: u, child: Text(u))).toList(),
                onChanged: (v) => ss(() => unit = v!))),
            ]),
            const SizedBox(height: 10),
            TextField(controller: descCtrl, maxLines: 2,
                decoration: const InputDecoration(labelText: 'Description (optional)',
                    alignLabelWithHint: true)),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
                try {
                  await _c.rpc('super_admin_manage_product', params: {
                    'p_action':      isEdit ? 'update' : 'create',
                    if (isEdit) 'p_product_id': existing['id'],
                    'p_name':        nameCtrl.text.trim(),
                    'p_name_tamil':  tamilCtrl.text.trim().isEmpty ? null : tamilCtrl.text.trim(),
                    'p_category':    catCtrl.text.trim().isEmpty ? null : catCtrl.text.trim(),
                    'p_unit':        unit,
                    'p_description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                  });
                  if (mounted) {
                    showSuccess(context, isEdit ? 'Product updated ✓' : 'Product created ✓');
                    _load();
                  }
                } catch (e) {
                  if (mounted) showError(context, e.toString());
                }
              },
              child: Text(isEdit ? 'Save Changes' : 'Create Product')),
          ]))));
    if (saved == true) _load();
  }

  Future<void> _toggle(Map<String,dynamic> p) async {
    try {
      await _c.rpc('super_admin_manage_product', params: {
        'p_action': 'toggle', 'p_product_id': p['id'],
      });
      _load();
    } catch (e) {
      if (mounted) showError(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    // Group by category
    final byCategory = <String, List<Map<String,dynamic>>>{};
    for (final p in _products) {
      final cat = p['category'] as String? ?? 'Uncategorised';
      byCategory.putIfAbsent(cat, () => []).add(p);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Master Products'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add Product')),
      body: _loading ? const LoadingList()
          : byCategory.isEmpty
              ? const EmptyState(icon: Icons.egg_alt_outlined, message: 'No products configured')
              : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: [
                  for (final cat in byCategory.keys) ...[
                    Padding(padding: const EdgeInsets.only(top: 8, bottom: 6),
                      child: Text(cat, style: const TextStyle(fontSize: 11,
                          fontWeight: FontWeight.w800, color: kTextHint, letterSpacing: 0.8))),
                    ...byCategory[cat]!.map((p) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: p['is_active'] == true ? Colors.white : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kBorder)),
                      child: Row(children: [
                        Container(width: 40, height: 40,
                            decoration: BoxDecoration(
                                color: p['is_active'] == true ? kPrimary.withValues(alpha: 0.1) : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(10)),
                            child: Center(child: Text(
                              (p['name'] as String)[0].toUpperCase(),
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                                  color: p['is_active'] == true ? kPrimary : Colors.grey)))),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p['name'] as String,
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14,
                                  color: p['is_active'] == true ? kTextMain : kTextSub)),
                          if (p['name_tamil'] != null)
                            Text(p['name_tamil'] as String,
                                style: const TextStyle(fontSize: 12, color: kTextSub)),
                          Text('${p['unit'] ?? 'kg'} · ${p['category'] ?? '—'}',
                              style: const TextStyle(fontSize: 11, color: kTextHint)),
                        ])),
                        Row(children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18, color: kPrimary),
                            onPressed: () => _showForm(existing: p)),
                          Switch(
                            value: p['is_active'] == true,
                            onChanged: (_) => _toggle(p),
                            activeColor: kPrimary),
                        ]),
                      ])))
                  ]
                ]));
  }
}
