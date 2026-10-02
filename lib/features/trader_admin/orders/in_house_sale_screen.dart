import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/common/horizontalscroll_wheel.dart';

// ══════════════════════════════════════════════════════════════════════════
// STOCK POINT SALE (In-House) — UI redesign only, no backend changes.
// Same create_in_house_sale_v1 RPC as before. Layout/interaction now
// follows Quick Entry's patterns: tap-to-search customer (not an embedded
// list), chip-based product entry with one active card + collapsed rows
// for the rest, and a true sticky footer (Total + Create Invoice) —
// a dedicated screen throughout, never a bottom sheet, per request.
// No Delivery Agent / Shift / Batch / Route / Approval fields — POS-only.
// ══════════════════════════════════════════════════════════════════════════

class _SaleLine {
  Map<String, dynamic>? product;
  final birdsCtrl = TextEditingController();
  final weightCtrl = TextEditingController();
  final rateCtrl = TextEditingController(); // optional manual override
  int? availBirds;
  double? availKg;

  void dispose() {
    birdsCtrl.dispose();
    weightCtrl.dispose();
    rateCtrl.dispose();
  }
}

class InHouseSaleScreen extends ConsumerStatefulWidget {
  const InHouseSaleScreen({super.key});

  @override
  ConsumerState<InHouseSaleScreen> createState() => _S();
}

class _S extends ConsumerState<InHouseSaleScreen> {
  final _c = Supabase.instance.client;

  bool _loading = true;
  bool _submitting = false;

  // ── Customer ──────────────────────────────────────────────────────────
  bool _isWalkIn = false;
  List<Map<String, dynamic>> _retailers = [];
  Map<String, dynamic>? _selectedRetailer;
  final _walkinNameCtrl = TextEditingController();
  final _walkinPhoneCtrl = TextEditingController();

  // ── Products ──────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _products = [];
  final List<_SaleLine> _lines = [];
  int _activeIdx = -1;

  final _customerScrollCtrl = ScrollController();
  final _productScrollCtrl = ScrollController();

  // ── Payment ───────────────────────────────────────────────────────────
  String _paymentMode = 'cash';
  // Business Date — defaults to today, editable, never future. Lets the
  // trader record a stock point sale that actually happened a few days
  // ago (e.g. catching up on pending entries) so it lands on the correct
  // day everywhere downstream — Stock/Valuation Ledger, Customer Ledger,
  // Cash Flow, P&L, Dashboard, Reports — instead of always today.
  DateTime _saleDate = DateTime.now();
  final _notesCtrl = TextEditingController();

  String? get _traderId => ref.read(appUserProvider).valueOrNull?.traderId;
  String? get _userId => ref.read(appUserProvider).valueOrNull?.userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _walkinNameCtrl.dispose();
    _walkinPhoneCtrl.dispose();
    _notesCtrl.dispose();
    _customerScrollCtrl.dispose();
    _productScrollCtrl.dispose();
    for (final l in _lines) l.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final tid = _traderId;
    if (tid == null || !mounted) return;
    setState(() => _loading = true);
    try {
      final retailers = await _c
          .from('retailers')
          .select('id,shop_name,owner_name,phone')
          .eq('trader_id', tid)
          .eq('is_active', true)
          .neq('retailer_type', 'walk_in')
          .order('shop_name');
      final products = await _c
          .from('master_products')
          .select('id,name')
          .eq('is_active', true)
          .order('name');
      if (!mounted) return;
      setState(() {
        _retailers = List<Map<String, dynamic>>.from(retailers as List? ?? []);
        _products = List<Map<String, dynamic>>.from(products as List? ?? []);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  // ── Customer: tap-to-search sheet (same mechanism as Quick Entry) ────────
  Future<void> _openSearchSheet() async {
    final ctrl = TextEditingController();
    var filtered = List<Map<String, dynamic>>.from(_retailers);
    await showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (ctx, scrollCtrl) => Container(
            decoration: const BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusCard)),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search customer name or phone',
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
                onChanged: (q) => setSheet(() {
                  final ql = q.trim().toLowerCase();
                  filtered = ql.isEmpty
                      ? List.from(_retailers)
                      : _retailers.where((r) =>
                  (r['shop_name'] as String? ?? '').toLowerCase().contains(ql) ||
                      (r['phone'] as String? ?? '').toLowerCase().contains(ql)).toList();
                }),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) {
                    final r = filtered[i];
                    return ListTile(
                      title: Text(r['shop_name'] as String? ?? ''),
                      subtitle: Text(r['phone'] as String? ?? ''),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        setState(() => _selectedRetailer = r);
                      },
                    );
                  },
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }

  // ── Products: chip tap adds/reopens a line, never duplicates ────────────
  void _tapProduct(Map<String, dynamic> product) {
    final existingIdx = _lines.indexWhere((l) => l.product?['id'] == product['id']);
    if (existingIdx != -1) {
      setState(() => _activeIdx = existingIdx);
      return;
    }
    final line = _SaleLine()..product = product;
    setState(() {
      _lines.add(line);
      _activeIdx = _lines.length - 1;
    });
    _refreshLineStock(line);
  }

  void _removeLine(int idx) {
    setState(() {
      _lines[idx].dispose();
      _lines.removeAt(idx);
      if (_activeIdx >= _lines.length) _activeIdx = _lines.length - 1;
    });
  }

  Future<void> _refreshLineStock(_SaleLine line) async {
    final tid = _traderId;
    if (tid == null || line.product == null || !mounted) return;
    try {
      final res = await _c.rpc('get_available_stock', params: {
        'p_trader_id': tid,
        'p_product_id': line.product!['id'],
      });
      final row = ((res as List?) ?? []).isNotEmpty ? (res as List).first as Map<String, dynamic> : null;
      if (!mounted) return;
      setState(() {
        line.availBirds = (row?['in_house_birds'] as num?)?.toInt() ?? 0;
        line.availKg = (row?['in_house_kg'] as num?)?.toDouble() ?? 0;
      });
    } catch (_) {
      // Non-fatal — the server-side RPC re-validates stock regardless.
    }
  }

  double get _grandTotal {
    double total = 0;
    for (final l in _lines) {
      final kg = double.tryParse(l.weightCtrl.text) ?? 0;
      final rate = double.tryParse(l.rateCtrl.text) ?? 0;
      if (kg > 0 && rate > 0) total += kg * rate;
    }
    return total;
  }

  int get _totalBirds =>
      _lines.fold(0, (s, l) => s + (int.tryParse(l.birdsCtrl.text) ?? 0));
  double get _totalKg =>
      _lines.fold(0, (s, l) => s + (double.tryParse(l.weightCtrl.text) ?? 0));

  String _placeholderEmojiFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('country')) return '🦃';
    if (n.contains('duck')) return '🦆';
    if (n.contains('layer') || n.contains('egg')) return '🥚';
    if (n.contains('quail')) return '🐦';
    if (n.contains('turkey')) return '🦃';
    return '🐔';
  }

  Color _colorFor(String name) {
    final colors = [kNavy, const Color(0xFF185FA5), const Color(0xFF16A34A), Colors.teal];
    return colors[name.hashCode.abs() % colors.length];
  }

  String _initialsFor(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    return parts.length == 1
        ? parts.first.substring(0, 1).toUpperCase()
        : (parts.first.substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  Future<void> _submit() async {
    final tid = _traderId;
    final uid = _userId;
    if (tid == null || !mounted) return;

    if (!_isWalkIn && _selectedRetailer == null) {
      showError(context, 'Select a customer, or switch to Walk-in.');
      return;
    }

    final items = <Map<String, dynamic>>[];
    for (final l in _lines) {
      if (l.product == null) continue;
      final kg = double.tryParse(l.weightCtrl.text);
      if (kg == null || kg <= 0) continue;
      items.add({
        'product_id': l.product!['id'],
        'bird_count': int.tryParse(l.birdsCtrl.text),
        'weight_kg': kg,
        'rate_per_kg': double.tryParse(l.rateCtrl.text),
      });
    }
    if (items.isEmpty) {
      showError(context, 'Add at least one product with a weight.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final res = await _c.rpc('create_in_house_sale_v1', params: {
        'p_trader_id': tid,
        'p_items': items,
        'p_retailer_id': _isWalkIn ? null : _selectedRetailer!['id'],
        'p_walkin_name': _isWalkIn && _walkinNameCtrl.text.trim().isNotEmpty ? _walkinNameCtrl.text.trim() : null,
        'p_walkin_phone': _isWalkIn && _walkinPhoneCtrl.text.trim().isNotEmpty ? _walkinPhoneCtrl.text.trim() : null,
        'p_payment_mode': _paymentMode,
        'p_notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'p_created_by': uid,
        'p_sale_date': DateFormat('yyyy-MM-dd').format(_saleDate),
      });
      if (!mounted) return;
      final result = res as Map<String, dynamic>;
      setState(() => _submitting = false);
      showSuccess(context, 'Sale recorded ✓  Invoice ${result['invoice_number']}');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _submitting = false);
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: Row(children: const [
          Icon(Icons.storefront, color: Color(0xFF16A34A), size: 22),
          SizedBox(width: 8),
          Text('Stock Point Sale'),
        ]),
      ),
      body: _loading
          ? const LoadingList()
          : ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        children: [
          _customerSection(),
          const SizedBox(height: 18),
          _productSection(),
          const SizedBox(height: 8),
          ..._lines.asMap().entries.map((e) => e.key == _activeIdx
              ? _activeProductCard(e.key)
              : _collapsedProductRow(e.key)),
          const SizedBox(height: 10),
          _paymentRow(),
        ],
      ),
      // ── Sticky footer: always visible, no scrolling needed ──────────────
      bottomNavigationBar: _loading ? null : _stickyFooter(),
    );
  }

  Widget _customerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('CUSTOMER'),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: ChoiceChip(
              label: const Text('Existing'),
              selected: !_isWalkIn,
              onSelected: (_) => setState(() => _isWalkIn = false),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ChoiceChip(
              label: const Text('Walk-in'),
              selected: _isWalkIn,
              onSelected: (_) => setState(() {
                _isWalkIn = true;
                if (_paymentMode == 'credit') _paymentMode = 'cash';
              }),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        if (!_isWalkIn) ...[
          GestureDetector(
            onTap: _openSearchSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: kBgPage,
                borderRadius: BorderRadius.circular(kRadiusInner),
                border: Border.all(color: kBorderLight),
              ),
              child: const Row(children: [
                Icon(Icons.search, size: 18, color: kTextHint),
                SizedBox(width: 8),
                Text('Search customer…', style: TextStyle(fontSize: 13, color: kTextHint)),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          if (_retailers.isEmpty)
            const Text('No customers found.', style: TextStyle(color: kTextHint, fontSize: 12))
          else
            SizedBox(
              height: 82,
              child: HorizontalScrollWheel(
                controller: _customerScrollCtrl,
                child: ListView(
                  controller: _customerScrollCtrl,
                  scrollDirection: Axis.horizontal,
                  children: _retailers.take(15).map(_customerChip).toList(),
                ),
              ),
            ),
          if (_selectedRetailer != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Selected: ${_selectedRetailer!['shop_name']}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kNavy)),
            ),
        ] else ...[
          Row(children: [
            Expanded(
              child: TextField(
                controller: _walkinNameCtrl,
                decoration: const InputDecoration(labelText: 'Name (optional)', isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _walkinPhoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone (optional)', isDense: true),
              ),
            ),
          ]),
        ],
      ],
    );
  }

  Widget _customerChip(Map<String, dynamic> r) {
    final selected = _selectedRetailer?['id'] == r['id'];
    final name = r['shop_name'] as String? ?? '';
    return GestureDetector(
      onTap: () => setState(() => _selectedRetailer = r),
      child: Container(
        width: 66,
        margin: const EdgeInsets.only(right: 8),
        child: Column(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _colorFor(name).withValues(alpha: 0.15),
              border: Border.all(color: selected ? kNavy : Colors.transparent, width: 2),
            ),
            alignment: Alignment.center,
            child: Text(_initialsFor(name),
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: _colorFor(name))),
          ),
          const SizedBox(height: 4),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _productSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SectionHeader('PRODUCTS — TAP TO ADD'),
      const SizedBox(height: 6),
      if (_products.isEmpty)
        const Text('No products found.', style: TextStyle(color: kTextHint, fontSize: 12))
      else
        SizedBox(
          height: 88,
          child: HorizontalScrollWheel(
            controller: _productScrollCtrl,
            child: ListView(
              controller: _productScrollCtrl,
              scrollDirection: Axis.horizontal,
              children: _products.map(_productChip).toList(),
            ),
          ),
        ),
    ],
  );

  Widget _productChip(Map<String, dynamic> product) {
    final name = product['name'] as String? ?? '';
    final selected = _lines.any((l) => l.product?['id'] == product['id']);
    return GestureDetector(
      onTap: () => _tapProduct(product),
      child: Container(
        width: 68,
        margin: const EdgeInsets.only(right: 10),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: selected ? const Color(0xFF16A34A).withValues(alpha: 0.12) : kBgPage,
                border: selected ? Border.all(color: const Color(0xFF16A34A), width: 2) : null,
              ),
              alignment: Alignment.center,
              child: Text(_placeholderEmojiFor(name), style: const TextStyle(fontSize: 28, height: 1.0)),
            ),
            if (selected)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(color: Color(0xFF16A34A), shape: BoxShape.circle),
                  child: const Icon(Icons.check, size: 12, color: Colors.white),
                ),
              ),
          ]),
          const SizedBox(height: 6),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected ? const Color(0xFF16A34A) : Colors.black87)),
        ]),
      ),
    );
  }

  Widget _activeProductCard(int idx) {
    final line = _lines[idx];
    final product = line.product;
    if (product == null) return const SizedBox.shrink();
    final name = product['name'] as String;
    final short = line.availKg != null &&
        (double.tryParse(line.weightCtrl.text) ?? 0) > (line.availKg ?? 0);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(_placeholderEmojiFor(name), style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(child: Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
          GestureDetector(
            onTap: () => _removeLine(idx),
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.08), shape: BoxShape.circle),
              child: const Icon(Icons.delete_outline, size: 19, color: Colors.redAccent),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: _compactField(
              label: 'Birds',
              controller: line.birdsCtrl,
              icon: Icons.egg_alt_outlined,
              onChanged: () => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _compactField(
              label: 'Weight (kg) *',
              controller: line.weightCtrl,
              icon: Icons.scale_outlined,
              decimal: true,
              onChanged: () => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _compactField(
              label: 'Rate/kg',
              controller: line.rateCtrl,
              icon: Icons.currency_rupee,
              decimal: true,
              onChanged: () => setState(() {}),
            ),
          ),
        ]),
        if (line.availKg != null) ...[
          const SizedBox(height: 8),
          Text(
            'In-house available: ${line.availBirds} birds · ${line.availKg!.toStringAsFixed(1)} kg',
            style: TextStyle(
              fontSize: 11,
              color: short ? kError : kTextHint,
              fontWeight: short ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
        ],
      ]),
    );
  }

  Widget _collapsedProductRow(int idx) {
    final line = _lines[idx];
    final product = line.product;
    if (product == null) return const SizedBox.shrink();
    final name = product['name'] as String;
    final birds = int.tryParse(line.birdsCtrl.text) ?? 0;
    final kg = double.tryParse(line.weightCtrl.text) ?? 0;
    return GestureDetector(
      onTap: () => setState(() => _activeIdx = idx),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border: Border.all(color: kBorderLight),
        ),
        child: Row(children: [
          Text(_placeholderEmojiFor(name), style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('$name — ${birds > 0 ? '$birds birds · ' : ''}${kg.toStringAsFixed(1)} kg'),
          ),
          IconButton(
            onPressed: () => setState(() => _activeIdx = idx),
            icon: const Icon(Icons.edit_outlined, size: 18, color: kTextHint),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => _removeLine(idx),
            icon: const Icon(Icons.close_rounded, size: 18, color: kTextHint),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ]),
      ),
    );
  }

  Widget _compactField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required VoidCallback onChanged,
    bool decimal = false,
  }) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 10, color: kTextHint)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          textAlign: TextAlign.center,
          keyboardType: decimal ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.number,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: kBgPage,
            prefixIcon: Icon(icon, size: 14, color: kTextHint),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
          onChanged: (_) => onChanged(),
        ),
      ]);

  Widget _paymentRow() {
    final modes = _isWalkIn ? ['cash', 'upi', 'bank'] : ['cash', 'upi', 'bank', 'credit'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('BUSINESS DATE'),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _saleDate,
              firstDate: DateTime.now().subtract(const Duration(days: 365)),
              lastDate: DateTime.now(),
            );
            if (picked != null) setState(() => _saleDate = picked);
          },
          child: InputDecorator(
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: kBgPage,
              prefixIcon: const Icon(Icons.calendar_today_outlined, size: 14, color: kTextHint),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            ),
            child: Text(DateFormat('d MMM yyyy').format(_saleDate),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          ),
        ),
        const SizedBox(height: 14),
        const SectionHeader('PAYMENT'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: modes.map((m) {
            final selected = _paymentMode == m;
            return ChoiceChip(
              label: Text(m[0].toUpperCase() + m.substring(1)),
              selected: selected,
              onSelected: (_) => setState(() => _paymentMode = m),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _notesCtrl,
          decoration: const InputDecoration(labelText: 'Notes (optional)', isDense: true),
        ),
      ],
    );
  }

  Widget _stickyFooter() {
    final total = _grandTotal;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.viewInsetsOf(context).bottom > 0 ? 10 : 20),
      decoration: BoxDecoration(
        color: kSurface,
        border: const Border(top: BorderSide(color: kBorderLight)),
      ),
      child: SafeArea(
        top: false,
        child: Row(children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Total', style: TextStyle(fontSize: 11, color: kTextHint)),
                Text('₹${total.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF16A34A))),
                if (_totalBirds > 0 || _totalKg > 0)
                  Text('$_totalBirds birds · ${_totalKg.toStringAsFixed(1)} kg',
                      style: const TextStyle(fontSize: 11, color: kTextHint)),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusBtn)),
                ),
                child: _submitting
                    ? const SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Create Invoice',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}