import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/number_input.dart';
import '../../../shared/layouts/responsive_layout.dart';

// ══════════════════════════════════════════════════════════════════════════
// RETAILER TO RETAILER TRANSFER
// Retailer A (Purchase From) sells birds to Retailer B (Sales To) through the
// trader. One save = create_retailer_transfer RPC, which in one transaction:
//   • credits A's customer ledger at A's rate × kg and books the stock in,
//   • debits B's customer ledger at B's rate × kg and books the stock out.
// Doc No (RTR-YYYYMM-NNNNN) is assigned on save; the header shows the next
// expected number. Edit / Delete never change ledger or stock rows — the RPCs
// post reversing entries (update_retailer_transfer / delete_retailer_transfer).
// ══════════════════════════════════════════════════════════════════════════

class RetailerTransferScreen extends ConsumerStatefulWidget {
  const RetailerTransferScreen({super.key});

  @override
  ConsumerState<RetailerTransferScreen> createState() => _RetailerTransferScreenState();
}

/// One side of the transfer: Sales To (B) or Purchase From (A).
class _Side {
  Map<String, dynamic>? retailer;
  String? productId;
  final rateCtrl = TextEditingController();
  bool rateEdited = false;
  String? rateLabel;
  bool rateLoading = false;

  double get rate => double.tryParse(rateCtrl.text.trim()) ?? 0;

  void clear() {
    retailer = null;
    productId = null;
    rateCtrl.clear();
    rateEdited = false;
    rateLabel = null;
  }

  void dispose() => rateCtrl.dispose();
}

class _RetailerTransferScreenState extends ConsumerState<RetailerTransferScreen> {
  final _c = Supabase.instance.client;

  bool _loading = true;
  bool _saving = false;

  List<Map<String, dynamic>> _retailers = [];
  List<Map<String, dynamic>> _products = [];

  // Header
  String? _docNoPreview;
  final _manualDocCtrl = TextEditingController();
  DateTime _date = DateUtils.dateOnly(DateTime.now());

  // Sales To (B) / Purchase From (A)
  final _to = _Side();
  final _from = _Side();
  final _birdsCtrl = TextEditingController();
  final _kgCtrl = TextEditingController();
  Timer? _kgDebounce;

  // The transfer loaded from View (null = new entry). _locked = shown
  // read-only until Edit is pressed.
  Map<String, dynamic>? _loaded;
  bool _locked = false;

  String? get _traderId => ref.read(appUserProvider).valueOrNull?.traderId;

  double get _kg => double.tryParse(_kgCtrl.text.trim()) ?? 0;
  double get _saleAmount => _round2(_kg * _to.rate);
  double get _purchaseAmount => _round2(_kg * _from.rate);
  static double _round2(double v) => (v * 100).roundToDouble() / 100;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _kgDebounce?.cancel();
    _manualDocCtrl.dispose();
    _birdsCtrl.dispose();
    _kgCtrl.dispose();
    _to.dispose();
    _from.dispose();
    super.dispose();
  }

  // ── Data ────────────────────────────────────────────────────────────────
  Future<void> _load() async {
    final tid = _traderId;
    if (tid == null) return;
    _loadDocNoPreview();
    try {
      final retailers = await _c
          .from('retailers')
          .select('id,shop_name,owner_name,phone')
          .eq('trader_id', tid)
          .eq('is_active', true)
          .neq('retailer_type', 'walk_in');
      final products = await _c
          .from('master_products')
          .select('id,name')
          .eq('is_active', true)
          .order('name');
      final list = List<Map<String, dynamic>>.from(retailers as List? ?? []);
      list.sort((a, b) => (a['shop_name'] as String? ?? '')
          .toLowerCase()
          .compareTo((b['shop_name'] as String? ?? '').toLowerCase()));
      if (!mounted) return;
      setState(() {
        _retailers = list;
        _products = List<Map<String, dynamic>>.from(products as List? ?? []);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showError(context, e.toString());
    }
  }

  Future<void> _loadDocNoPreview() async {
    final tid = _traderId;
    if (tid == null) return;
    try {
      final res = await _c.rpc('preview_retailer_transfer_doc_no', params: {
        'p_trader_id': tid,
        'p_date': DateFormat('yyyy-MM-dd').format(_date),
      });
      if (mounted) setState(() => _docNoPreview = res as String?);
    } catch (_) {
      if (mounted) setState(() => _docNoPreview = null);
    }
  }

  /// Customer rate for this side's retailer + item on the transfer date —
  /// the same get_effective_rate_v4 Quick Entry uses. Leaves a rate the
  /// user typed alone.
  Future<void> _fetchRate(_Side side) async {
    final tid = _traderId;
    final retailerId = side.retailer?['id'];
    if (tid == null || retailerId == null || side.productId == null || _locked) return;
    setState(() => side.rateLoading = true);
    try {
      final res = await _c.rpc('get_effective_rate_v4', params: {
        'p_trader_id': tid,
        'p_retailer_id': retailerId,
        'p_product_id': side.productId,
        'p_quantity_kg': _kg > 0 ? _kg : 1,
        'p_date': DateFormat('yyyy-MM-dd').format(_date),
      });
      final rows = res as List?;
      if (!mounted) return;
      final row = (rows == null || rows.isEmpty) ? null : rows.first as Map<String, dynamic>;
      final rate = (row?['rate'] as num?)?.toDouble() ?? 0;
      setState(() {
        side.rateLoading = false;
        side.rateLabel = row?['rate_label'] as String?;
        if (!side.rateEdited && rate > 0) side.rateCtrl.text = _fmtRate(rate);
      });
    } catch (_) {
      if (mounted) setState(() => side.rateLoading = false);
    }
  }

  static String _fmtRate(double r) =>
      r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(2);

  static String _fmtKg(num v) {
    final s = v.toStringAsFixed(3);
    return s.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  // ── Actions ─────────────────────────────────────────────────────────────
  void _reset() {
    setState(() {
      _loaded = null;
      _locked = false;
      _to.clear();
      _from.clear();
      _birdsCtrl.clear();
      _kgCtrl.clear();
      _manualDocCtrl.clear();
      _date = DateUtils.dateOnly(DateTime.now());
    });
    _loadDocNoPreview();
  }

  String? _validate() {
    if (_to.retailer == null) return 'Choose the Sales To customer.';
    if (_from.retailer == null) return 'Choose the Purchase From customer.';
    if (_to.retailer!['id'] == _from.retailer!['id']) {
      return 'Sales To and Purchase From must be different customers.';
    }
    if (_to.productId == null || _from.productId == null) return 'Choose the item.';
    if (_kg <= 0) return 'Enter the Kgs.';
    if (_to.rate <= 0) return 'Enter the Sales To rate.';
    if (_from.rate <= 0) return 'Enter the Purchase From rate.';
    return null;
  }

  Map<String, dynamic> _params() => {
        'p_transfer_date': DateFormat('yyyy-MM-dd').format(_date),
        'p_to_retailer_id': _to.retailer!['id'],
        'p_to_product_id': _to.productId,
        'p_from_retailer_id': _from.retailer!['id'],
        'p_from_product_id': _from.productId,
        'p_bird_count': int.tryParse(_birdsCtrl.text.trim()) ?? 0,
        'p_quantity_kg': _kg,
        'p_sale_rate': _to.rate,
        'p_purchase_rate': _from.rate,
        'p_manual_doc_no': _manualDocCtrl.text.trim().isEmpty ? null : _manualDocCtrl.text.trim(),
      };

  Future<void> _save() async {
    if (_saving || _locked) return;
    final err = _validate();
    if (err != null) {
      showError(context, err);
      return;
    }
    final tid = _traderId;
    if (tid == null) return;

    String? reason;
    if (_loaded != null) {
      reason = await _askReason(
        title: 'Save changes to ${_loaded!['doc_no']}?',
        message: 'The old ledger and stock entries are reversed and new ones are posted.',
        required: false,
        confirmLabel: 'Save',
      );
      if (reason == null) return;
    }

    setState(() => _saving = true);
    try {
      final Map<String, dynamic> res;
      if (_loaded == null) {
        res = Map<String, dynamic>.from(await _c.rpc('create_retailer_transfer',
            params: {'p_trader_id': tid, ..._params()}) as Map);
      } else {
        res = Map<String, dynamic>.from(await _c.rpc('update_retailer_transfer', params: {
          'p_transfer_id': _loaded!['id'],
          ..._params(),
          'p_reason': (reason == null || reason.isEmpty) ? null : reason,
        }) as Map);
      }
      if (!mounted) return;
      setState(() => _saving = false);
      showSuccess(context,
          '${_loaded == null ? 'Transfer saved' : 'Transfer updated'} ✓  Doc No ${res['doc_no']}');
      _reset();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showError(context, _msg(e));
    }
  }

  Future<void> _edit() async {
    if (_loaded == null) {
      await _openView(pickFor: 'edit');
      return;
    }
    if (_loaded!['status'] != 'active') {
      showError(context, 'This transfer is deleted and cannot be edited.');
      return;
    }
    setState(() => _locked = false);
  }

  Future<void> _delete() async {
    if (_loaded == null) {
      await _openView(pickFor: 'delete');
      return;
    }
    if (_loaded!['status'] != 'active') {
      showError(context, 'This transfer is already deleted.');
      return;
    }
    final reason = await _askReason(
      title: 'Delete ${_loaded!['doc_no']}?',
      message: 'Both customers\' ledger entries and the stock entries are reversed. '
          'The transfer stays in View as deleted.',
      required: true,
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (reason == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await _c.rpc('delete_retailer_transfer', params: {
        'p_transfer_id': _loaded!['id'],
        'p_reason': reason,
      });
      if (!mounted) return;
      setState(() => _saving = false);
      showSuccess(context, 'Transfer ${_loaded!['doc_no']} deleted');
      _reset();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showError(context, _msg(e));
    }
  }

  static String _msg(Object e) =>
      e is PostgrestException ? e.message : e.toString().replaceAll('Exception: ', '');

  /// Returns the typed reason ('' when optional and left blank), or null when
  /// cancelled.
  Future<String?> _askReason({
    required String title,
    required String message,
    required bool required,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final ctrl = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(message, style: const TextStyle(fontSize: 13, color: kTextSub)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLines: 2,
                onChanged: (_) => setD(() {}),
                decoration: InputDecoration(
                  labelText: required ? 'Reason *' : 'Reason (optional)',
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              style: destructive ? FilledButton.styleFrom(backgroundColor: kError) : null,
              onPressed: required && ctrl.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    return res;
  }

  /// Fills the form from a transfer picked in View (read-only until Edit).
  void _loadTransfer(Map<String, dynamic> t, {bool unlock = false}) {
    Map<String, dynamic>? findRetailer(String? id, String? name) =>
        _retailers.firstWhere((r) => r['id'] == id,
            orElse: () => {'id': id, 'shop_name': name ?? '—'});
    setState(() {
      _loaded = t;
      _locked = !unlock || t['status'] != 'active';
      _date = DateTime.parse(t['transfer_date'] as String);
      _manualDocCtrl.text = (t['manual_doc_no'] as String?) ?? '';
      _to
        ..retailer = findRetailer(t['to_retailer_id'] as String?, t['to_retailer_name'] as String?)
        ..productId = t['to_product_id'] as String?
        ..rateCtrl.text = _fmtRate((t['sale_rate'] as num).toDouble())
        ..rateEdited = true
        ..rateLabel = null;
      _from
        ..retailer = findRetailer(t['from_retailer_id'] as String?, t['from_retailer_name'] as String?)
        ..productId = t['from_product_id'] as String?
        ..rateCtrl.text = _fmtRate((t['purchase_rate'] as num).toDouble())
        ..rateEdited = true
        ..rateLabel = null;
      _birdsCtrl.text = '${(t['bird_count'] as num?)?.toInt() ?? 0}';
      _kgCtrl.text = _fmtKg(t['quantity_kg'] as num);
    });
  }

  Future<void> _pickDate() async {
    if (_locked) return;
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(today) ? today : _date,
      firstDate: DateTime(today.year - 3),
      lastDate: today,
    );
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
    if (_loaded == null) _loadDocNoPreview();
    _fetchRate(_to);
    _fetchRate(_from);
  }

  Future<void> _pickRetailer(_Side side) async {
    if (_locked) return;
    final other = identical(side, _to) ? _from : _to;
    final options = _retailers.where((r) => r['id'] != other.retailer?['id']).toList();
    final picked = await _showRetailerSearch(options,
        title: identical(side, _to) ? 'Sales To — customer' : 'Purchase From — customer');
    if (picked == null || !mounted) return;
    setState(() {
      side.retailer = picked;
      side.rateEdited = false;
      side.rateLabel = null;
    });
    _fetchRate(side);
  }

  void _setProduct(_Side side, String? id) {
    setState(() {
      // Purchase From follows Sales To's item until it's changed on its own.
      if (identical(side, _to) && (_from.productId == null || _from.productId == _to.productId)) {
        if (_from.productId != id) {
          _from.productId = id;
          _from.rateEdited = false;
        }
      }
      side.productId = id;
      side.rateEdited = false;
    });
    _fetchRate(_to);
    _fetchRate(_from);
  }

  void _onKgChanged(String _) {
    setState(() {});
    _kgDebounce?.cancel();
    _kgDebounce = Timer(const Duration(milliseconds: 500), () {
      _fetchRate(_to);
      _fetchRate(_from);
    });
  }

  Future<Map<String, dynamic>?> _showRetailerSearch(List<Map<String, dynamic>> options,
      {required String title}) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (ctx) {
        final ctrl = TextEditingController();
        var filtered = List<Map<String, dynamic>>.from(options);
        return StatefulBuilder(builder: (ctx, setSheet) {
          return DraggableScrollableSheet(
            initialChildSize: 0.75,
            minChildSize: 0.4,
            maxChildSize: 0.92,
            expand: false,
            builder: (ctx, scrollCtrl) => Container(
              decoration: const BoxDecoration(
                color: kSurface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusCard)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Column(children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
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
                        ? List.from(options)
                        : options
                            .where((r) =>
                                (r['shop_name'] as String? ?? '').toLowerCase().contains(ql) ||
                                (r['owner_name'] as String? ?? '').toLowerCase().contains(ql) ||
                                (r['phone'] as String? ?? '').toLowerCase().contains(ql))
                            .toList();
                  }),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('No customers found', style: TextStyle(color: kTextHint)))
                      : ListView.builder(
                          controller: scrollCtrl,
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) {
                            final r = filtered[i];
                            final sub = [r['owner_name'], r['phone']]
                                .whereType<String>()
                                .where((s) => s.trim().isNotEmpty)
                                .join(' · ');
                            return Material(
                              type: MaterialType.transparency,
                              child: ListTile(
                                dense: true,
                                title: Text(r['shop_name'] as String? ?? ''),
                                subtitle: sub.isEmpty ? null : Text(sub),
                                onTap: () => Navigator.of(ctx).pop(r),
                              ),
                            );
                          },
                        ),
                ),
              ]),
            ),
          );
        });
      },
    );
  }

  // ── View: past transfers ────────────────────────────────────────────────
  /// [pickFor] — 'edit' / 'delete' when opened from those buttons with no
  /// transfer loaded; tapping a row then goes straight to that action.
  Future<void> _openView({String? pickFor}) async {
    final tid = _traderId;
    if (tid == null) return;
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 980),
      builder: (ctx) => _TransferListSheet(
        traderId: tid,
        title: switch (pickFor) {
          'edit' => 'Pick a transfer to edit',
          'delete' => 'Pick a transfer to delete',
          _ => 'Retailer transfers',
        },
      ),
    );
    if (picked == null || !mounted) return;
    _loadTransfer(picked, unlock: pickFor == 'edit');
    if (pickFor == 'delete') await _delete();
  }

  // ── UI ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: const Row(children: [
          Icon(Icons.swap_horiz_rounded, color: Color(0xFF7C3AED), size: 22),
          SizedBox(width: 8),
          Flexible(child: Text('Retailer to Retailer Transfer', overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          if (_loaded != null)
            IconButton(
              tooltip: 'New transfer',
              icon: const Icon(Icons.add_rounded),
              onPressed: _saving ? null : _reset,
            ),
        ],
      ),
      body: _loading
          ? const LoadingList()
          : LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth >= 720;
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 960),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (_loaded != null) _loadedBanner(),
                      _headerCard(wide),
                      const SizedBox(height: 14),
                      _salesToCard(wide),
                      const SizedBox(height: 14),
                      _purchaseFromCard(wide),
                      const SizedBox(height: 14),
                      _summary(),
                    ]),
                  ),
                ),
              );
            }),
      // On phones the shell's glass bottom nav floats over the page, so keep
      // the buttons above it (same clearance other trader screens reserve).
      bottomNavigationBar: _loading
          ? null
          : Column(mainAxisSize: MainAxisSize.min, children: [
              _buttonBar(),
              if (context.isMobile) const SizedBox(height: kBottomNavClearance),
            ]),
    );
  }

  Widget _loadedBanner() {
    final deleted = _loaded!['status'] != 'active';
    final color = deleted ? kError : (_locked ? const Color(0xFF0369A1) : kWarning);
    final text = deleted
        ? 'Deleted${_loaded!['delete_reason'] != null ? ' — ${_loaded!['delete_reason']}' : ''}'
        : _locked
            ? 'Viewing ${_loaded!['doc_no']} — press Edit to change it'
            : 'Editing ${_loaded!['doc_no']} — Save posts reversing entries and the new ones';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(kRadiusInner),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Icon(deleted ? Icons.block_rounded : (_locked ? Icons.visibility_outlined : Icons.edit_outlined),
            size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color))),
      ]),
    );
  }

  Widget _card({required String title, required IconData icon, required Color color, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(color: kBorderLight),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Text(title, style: kTypeSectionTitle.copyWith(color: color)),
        ]),
        const SizedBox(height: 14),
        child,
      ]),
    );
  }

  /// Lays fields out 2 (or 3) per row on wide screens, one per row on phones.
  Widget _grid(bool wide, List<Widget> fields, {int columns = 2}) {
    return LayoutBuilder(builder: (context, c) {
      final cols = wide ? columns : 1;
      const gap = 12.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: 12,
        children: [for (final f in fields) SizedBox(width: w, child: f)],
      );
    });
  }

  Widget _readOnlyField(String label, String value, {Color? color, String? helper}) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        filled: true,
        fillColor: kBgGrey,
      ),
      child: Text(value,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color ?? kTextMain)),
    );
  }

  Widget _headerCard(bool wide) {
    final docNo = _loaded != null ? _loaded!['doc_no'] as String : (_docNoPreview ?? '—');
    return _card(
      title: 'DOCUMENT',
      icon: Icons.description_outlined,
      color: kNavy,
      child: _grid(wide, columns: 3, [
        _readOnlyField('Auto Doc No', docNo,
            color: kNavy, helper: _loaded == null ? 'Assigned on save' : null),
        TextField(
          controller: _manualDocCtrl,
          readOnly: _locked,
          decoration: const InputDecoration(labelText: 'Man. Doc No (optional)'),
        ),
        InkWell(
          onTap: _locked ? null : _pickDate,
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Date',
              suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
            ),
            child: Text(DateFormat('dd MMM yyyy').format(_date), style: const TextStyle(fontSize: 15)),
          ),
        ),
      ]),
    );
  }

  Widget _customerField(_Side side, String label) {
    final name = side.retailer?['shop_name'] as String?;
    return InkWell(
      onTap: _locked ? null : () => _pickRetailer(side),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
        ),
        child: Text(name ?? 'Choose customer…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15, color: name == null ? kTextHint : kTextMain)),
      ),
    );
  }

  Widget _itemField(_Side side) {
    final ids = _products.map((p) => p['id']).toSet();
    return DropdownButtonFormField<String>(
      // A deactivated item from an old transfer isn't in the list — show blank.
      initialValue: ids.contains(side.productId) ? side.productId : null,
      key: ValueKey('item-${identical(side, _to)}-${side.productId}-$_locked'),
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Item Name'),
      items: [
        for (final p in _products)
          DropdownMenuItem(value: p['id'] as String, child: Text(p['name'] as String? ?? '')),
      ],
      onChanged: _locked ? null : (v) => _setProduct(side, v),
    );
  }

  Widget _rateField(_Side side) {
    return TextField(
      controller: side.rateCtrl,
      readOnly: _locked,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: moneyInputFormatters,
      onChanged: (_) => setState(() => side.rateEdited = true),
      decoration: InputDecoration(
        labelText: 'Rate (₹/kg)',
        helperText: side.rateEdited && _loaded == null
            ? 'Edited'
            : (side.rateLabel != null ? 'Customer rate · ${side.rateLabel}' : null),
        suffixIcon: side.rateLoading
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : (side.rateEdited && !_locked && side.retailer != null && side.productId != null
                ? IconButton(
                    tooltip: 'Reload customer rate',
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    onPressed: () {
                      setState(() => side.rateEdited = false);
                      _fetchRate(side);
                    },
                  )
                : null),
      ),
    );
  }

  Widget _salesToCard(bool wide) {
    return _card(
      title: 'SALES TO',
      icon: Icons.call_made_rounded,
      color: const Color(0xFF0369A1),
      child: _grid(wide, [
        _customerField(_to, 'Customer name'),
        _itemField(_to),
        TextField(
          controller: _birdsCtrl,
          readOnly: _locked,
          keyboardType: TextInputType.number,
          inputFormatters: birdsInputFormatters,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'No. of birds'),
        ),
        TextField(
          controller: _kgCtrl,
          readOnly: _locked,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: kgInputFormatters,
          onChanged: _onKgChanged,
          decoration: const InputDecoration(labelText: 'Kgs'),
        ),
        _rateField(_to),
        _readOnlyField('Amount', Fmt.amount(_saleAmount),
            color: const Color(0xFF0369A1), helper: 'Kgs × rate · debit to this customer'),
      ]),
    );
  }

  Widget _purchaseFromCard(bool wide) {
    return _card(
      title: 'PURCHASE FROM',
      icon: Icons.call_received_rounded,
      color: const Color(0xFF16A34A),
      child: _grid(wide, [
        _customerField(_from, 'Customer name'),
        _itemField(_from),
        _rateField(_from),
        _readOnlyField('Amount', Fmt.amount(_purchaseAmount),
            color: const Color(0xFF16A34A),
            helper: '${_kg > 0 ? _fmtKg(_kg) : '0'} kg × rate · credit to this customer'),
      ]),
    );
  }

  Widget _summary() {
    final margin = _saleAmount - _purchaseAmount;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(kRadiusInner),
        border: Border.all(color: kBorderLight),
      ),
      child: Wrap(spacing: 24, runSpacing: 6, children: [
        _sumItem('Sale', Fmt.amount(_saleAmount)),
        _sumItem('Purchase', Fmt.amount(_purchaseAmount)),
        _sumItem('Margin', Fmt.amount(margin), color: margin < 0 ? kError : kSuccess),
        _sumItem('Stock', 'net 0 (in & out ${_kg > 0 ? _fmtKg(_kg) : 0} kg)'),
      ]),
    );
  }

  Widget _sumItem(String label, String value, {Color? color}) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label  ', style: kTypeCaption),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color ?? kTextMain)),
      ]);

  Widget _buttonBar() {
    final canSave = !_saving && !_locked;
    final isDeleted = _loaded != null && _loaded!['status'] != 'active';
    Widget btn(String label, IconData icon, VoidCallback? onTap, {Color? color, bool filled = false}) {
      final child = FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text(label),
        ]),
      );
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SizedBox(
            height: 46,
            child: filled
                ? FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: color, padding: const EdgeInsets.symmetric(horizontal: 8)),
                    onPressed: onTap,
                    child: child)
                : OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: color, padding: const EdgeInsets.symmetric(horizontal: 8)),
                    onPressed: onTap,
                    child: child),
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: kSurface,
          border: Border(top: BorderSide(color: kBorderLight)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        // heightFactor 1: shrink to the buttons — a plain Center fills the
        // whole screen in bottomNavigationBar and hides the form.
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Row(children: [
              btn(_saving ? 'Saving…' : (_loaded == null ? 'Save' : 'Update'), Icons.save_outlined,
                  canSave ? _save : null,
                  filled: true, color: kNavy),
              btn('Edit', Icons.edit_outlined, _saving || isDeleted || (_loaded != null && !_locked) ? null : _edit),
              btn('View', Icons.list_alt_rounded, _saving ? null : () => _openView()),
              btn('Delete', Icons.delete_outline_rounded, _saving || isDeleted ? null : _delete, color: kError),
            ]),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// View sheet — past transfers with date, Doc No, A, B, kg and both amounts.
// Pops the tapped transfer.
// ══════════════════════════════════════════════════════════════════════════
class _TransferListSheet extends StatefulWidget {
  const _TransferListSheet({required this.traderId, required this.title});

  final String traderId;
  final String title;

  @override
  State<_TransferListSheet> createState() => _TransferListSheetState();
}

class _TransferListSheetState extends State<_TransferListSheet> {
  final _c = Supabase.instance.client;
  final _searchCtrl = TextEditingController();
  late DateTime _from;
  late DateTime _to;
  bool _showDeleted = false;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    final today = DateUtils.dateOnly(DateTime.now());
    _to = today;
    _from = today.subtract(const Duration(days: 30));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _c.rpc('get_retailer_transfers', params: {
        'p_trader_id': widget.traderId,
        'p_from_date': DateFormat('yyyy-MM-dd').format(_from),
        'p_to_date': DateFormat('yyyy-MM-dd').format(_to),
        'p_include_deleted': _showDeleted,
      });
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(
            (res as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is PostgrestException ? e.message : e.toString();
      });
    }
  }

  Future<void> _pickRange() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 3),
      lastDate: today,
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (r == null) return;
    setState(() {
      _from = r.start;
      _to = r.end;
    });
    _load();
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _rows;
    return _rows.where((t) {
      return [t['doc_no'], t['manual_doc_no'], t['from_retailer_name'], t['to_retailer_name']]
          .whereType<String>()
          .any((s) => s.toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    final active = rows.where((t) => t['status'] == 'active');
    final totKg = active.fold<double>(0, (s, t) => s + (t['quantity_kg'] as num).toDouble());
    final totSale = active.fold<double>(0, (s, t) => s + (t['sale_amount'] as num).toDouble());
    final totPur = active.fold<double>(0, (s, t) => s + (t['purchase_amount'] as num).toDouble());

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusCard)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            OutlinedButton.icon(
              onPressed: _pickRange,
              icon: const Icon(Icons.date_range_rounded, size: 18),
              label: Text('${DateFormat('dd MMM yy').format(_from)} – ${DateFormat('dd MMM yy').format(_to)}'),
            ),
            FilterChip(
              label: const Text('Show deleted'),
              selected: _showDeleted,
              onSelected: (v) {
                setState(() => _showDeleted = v);
                _load();
              },
            ),
            SizedBox(
              width: 240,
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Search Doc No / customer',
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          if (!_loading && _error == null && rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${active.length} transfer${active.length == 1 ? '' : 's'} · ${_fmtKg(totKg)} kg · '
                'Sale ${Fmt.amount(totSale)} · Purchase ${Fmt.amount(totPur)}',
                style: kTypeCaption,
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: kError)))
                    : rows.isEmpty
                        ? const Center(
                            child: Text('No transfers in this period', style: TextStyle(color: kTextHint)))
                        : ListView.separated(
                            controller: scrollCtrl,
                            itemCount: rows.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (ctx, i) => _row(rows[i]),
                          ),
          ),
        ]),
      ),
    );
  }

  static String _fmtKg(num v) => v.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');

  Widget _row(Map<String, dynamic> t) {
    final deleted = t['status'] != 'active';
    final date = DateTime.parse(t['transfer_date'] as String);
    final man = t['manual_doc_no'] as String?;
    final strike = deleted ? TextDecoration.lineThrough : null;
    return InkWell(
      borderRadius: BorderRadius.circular(kRadiusInner),
      onTap: () => Navigator.of(context).pop(t),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: deleted ? kErrorBg.withValues(alpha: 0.35) : kSurface,
          borderRadius: BorderRadius.circular(kRadiusInner),
          border: Border.all(color: kBorderLight),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(DateFormat('dd MMM yyyy').format(date), style: kTypeCaption),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                '${t['doc_no']}${man != null ? '  ·  Man: $man' : ''}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kNavy, decoration: strike),
              ),
            ),
            if (deleted) ...[
              const SizedBox(width: 8),
              const Text('DELETED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: kError)),
            ],
            if (!deleted && ((t['version'] as num?) ?? 1) > 1) ...[
              const SizedBox(width: 8),
              const Text('EDITED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: kWarning)),
            ],
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 16, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _party('From (A)', t['from_retailer_name'] as String?, const Color(0xFF16A34A), strike),
            const Icon(Icons.arrow_forward_rounded, size: 16, color: kTextHint),
            _party('To (B)', t['to_retailer_name'] as String?, const Color(0xFF0369A1), strike),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 16, runSpacing: 4, children: [
            Text('${t['to_product_name']} · ${t['bird_count']} birds · ${_fmtKg(t['quantity_kg'] as num)} kg',
                style: kTypeBody),
            Text('A ${Fmt.amount((t['purchase_amount'] as num).toDouble())} @ ${t['purchase_rate']}',
                style: const TextStyle(fontSize: 13, color: Color(0xFF16A34A), fontWeight: FontWeight.w600)),
            Text('B ${Fmt.amount((t['sale_amount'] as num).toDouble())} @ ${t['sale_rate']}',
                style: const TextStyle(fontSize: 13, color: Color(0xFF0369A1), fontWeight: FontWeight.w600)),
          ]),
          if (deleted && t['delete_reason'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Reason: ${t['delete_reason']}', style: kTypeCaption),
            ),
        ]),
      ),
    );
  }

  Widget _party(String label, String? name, Color color, TextDecoration? strike) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label ', style: kTypeCaption),
        Text(name ?? '—',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color, decoration: strike)),
      ]);
}
