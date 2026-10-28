import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CREATE RETAILER SCREEN
// Flow: Shop Details → Pricing Zone (required) → Customer Rate (optional)
//       → Credit & Balance (optional) → Save
//
// Pricing Zone: searchable dropdown, auto-suggest from City, inline "Create Zone"
// Customer Rate: collapsed by default, per-product, calls set_customer_rate
// No zone rate preview shown.
// No new DB columns or RPCs — reuses existing infrastructure.
// ═══════════════════════════════════════════════════════════════════════════

class CreateRetailerScreen extends ConsumerStatefulWidget {
  const CreateRetailerScreen({super.key});
  @override
  ConsumerState<CreateRetailerScreen> createState() => _S();
}

class _S extends ConsumerState<CreateRetailerScreen> {
  final _c    = Supabase.instance.client;
  final _form = GlobalKey<FormState>();

  // ── Shop Detail controllers (all existing) ──────────────────────────────
  final _shopName    = TextEditingController();
  final _shopTamil   = TextEditingController();
  final _ownerName   = TextEditingController();
  final _phone       = TextEditingController();
  final _address     = TextEditingController();
  final _city        = TextEditingController();
  final _creditLimit = TextEditingController(text: '100000');

  // ── Opening Balance (existing) ──────────────────────────────────────────
  final _openingBalance = TextEditingController(text: '0');
  final _openingNote    = TextEditingController();
  DateTime _openingDate     = DateTime.now();
  bool     _showOpeningBalance = false;

  // ── Zone state ──────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _zones = [];
  String? _selectedZoneId;
  String? _selectedZoneName;
  bool _loadingZones    = true;
  bool _showCreateZone  = false;
  bool _creatingZone    = false;
  final _newZoneName = TextEditingController();
  final _newZoneCode = TextEditingController();
  final _zoneSearch  = TextEditingController();

  // ── Delivery Area state (dispatch-only, independent of Zone) ────────────
  List<Map<String, dynamic>> _areasList = [];
  String? _selectedAreaId;
  String? _selectedAreaName;
  bool _loadingAreas    = true;
  bool _showCreateArea  = false;
  bool _creatingArea    = false;
  final _newAreaName = TextEditingController();
  final _newAreaCode = TextEditingController();
  final _areaSearch  = TextEditingController();

  // ── Customer Rate state ─────────────────────────────────────────────────
  List<Map<String, dynamic>> _products  = [];
  bool   _loadingProducts               = true;
  bool   _customerRateExpanded          = false;
  // pricing_type applies to all products in this session
  String _pricingType                   = 'flat_discount';
  // productId → controller for the adjustment/rate value
  final Map<String, TextEditingController> _rateCtrl = {};

  bool _submitting = false;

  // ── Pricing type options ────────────────────────────────────────────────
  static const _pricingTypes = [
    ('flat_discount', 'Flat Discount (Cutting Charge)'),
    ('flat_premium',  'Flat Premium (Extra Charge)'),
    ('fixed',         'Fixed Rate (₹/kg)'),
    ('contract',      'Contract Rate (₹/kg)'),
    ('pct_discount',  'Percentage Discount (%)'),
    ('pct_premium',   'Percentage Premium (%)'),
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    await Future.wait([_loadZones(tid), _loadAreas(tid), _loadProducts(tid)]);
  }

  Future<void> _loadAreas(String tid) async {
    try {
      final res = await _c.rpc('get_areas',
          params: {'p_trader_id': tid, 'p_active_only': true});
      if (mounted) {
        setState(() {
          _areasList   = List<Map<String, dynamic>>.from(res as List? ?? []);
          _loadingAreas = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingAreas = false);
    }
  }

  Future<void> _loadZones(String tid) async {
    try {
      final res = await _c.rpc('get_zones',
          params: {'p_trader_id': tid, 'p_active_only': true});
      if (mounted) {
        setState(() {
          _zones       = List<Map<String, dynamic>>.from(res as List? ?? []);
          _loadingZones = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingZones = false);
    }
  }

  Future<void> _loadProducts(String tid) async {
    try {
      final res = await _c
          .from('trader_products')
          .select('product_id, sort_order, master_products(id, name, name_tamil, category)')
          .eq('trader_id', tid)
          .eq('is_enabled', true)
          .order('sort_order');
      if (mounted) {
        final list = List<Map<String, dynamic>>.from(res as List? ?? []);
        // Init one controller per product
        for (final p in list) {
          final pid = (p['master_products'] as Map)['id'] as String;
          _rateCtrl[pid] = TextEditingController();
        }
        setState(() {
          _products        = list;
          _loadingProducts  = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingProducts = false);
    }
  }

  // ── City → zone auto-suggest ────────────────────────────────────────────
  void _onCityChanged(String city) {
    // Only auto-suggest if nothing has been manually selected yet
    if (_selectedZoneId != null) return;
    final q = city.trim().toLowerCase();
    if (q.isEmpty) return;
    final match = _zones.cast<Map<String, dynamic>?>().firstWhere(
          (z) => (z!['zone_name'] as String).toLowerCase().contains(q),
      orElse: () => null,
    );
    if (match != null && mounted) {
      setState(() {
        _selectedZoneId   = match['id'] as String;
        _selectedZoneName = match['zone_name'] as String;
      });
    }
  }

  // ── Inline zone create ──────────────────────────────────────────────────
  Future<void> _createZone() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    final name = _newZoneName.text.trim();
    final code = _newZoneCode.text.trim().toUpperCase();
    if (name.isEmpty || code.isEmpty) {
      showError(context, 'Zone Name and Code are required');
      return;
    }
    // Client-side duplicate check before DB round-trip
    final dup = _zones.any(
            (z) => (z['zone_code'] as String).toUpperCase() == code);
    if (dup) {
      showError(context, 'Zone code "$code" already exists');
      return;
    }
    if (mounted) setState(() => _creatingZone = true);
    try {
      final result = await _c.from('zones').insert({
        'trader_id': tid,
        'zone_name': name,
        'zone_code': code,
      }).select('id, zone_name, zone_code, sort_order, is_active').single();
      // Inject retailer_count = 0 to match get_zones shape
      final newZone = Map<String, dynamic>.from(result)
        ..['retailer_count'] = 0;
      if (mounted) {
        setState(() {
          _zones            = [..._zones, newZone];
          _selectedZoneId   = newZone['id'] as String;
          _selectedZoneName = newZone['zone_name'] as String;
          _showCreateZone   = false;
          _creatingZone     = false;
        });
        _newZoneName.clear();
        _newZoneCode.clear();
        showSuccess(context, 'Zone "$name" created and selected ✓');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _creatingZone = false);
        showError(context, e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  // ── Inline area create ───────────────────────────────────────────────────
  Future<void> _createArea() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    final name = _newAreaName.text.trim();
    final code = _newAreaCode.text.trim().toUpperCase();
    if (name.isEmpty) {
      showError(context, 'Area Name is required');
      return;
    }
    if (code.isNotEmpty &&
        _areasList.any((a) => (a['area_code'] as String? ?? '').toUpperCase() == code)) {
      showError(context, 'Area code "$code" already exists');
      return;
    }
    if (mounted) setState(() => _creatingArea = true);
    try {
      final result = await _c.from('areas').insert({
        'trader_id': tid,
        'area_name': name,
        'area_code': code.isEmpty ? null : code,
      }).select('id, area_name, area_code, sort_order, is_active').single();
      // Inject retailer_count = 0 to match get_areas shape
      final newArea = Map<String, dynamic>.from(result)
        ..['retailer_count'] = 0;
      if (mounted) {
        setState(() {
          _areasList        = [..._areasList, newArea];
          _selectedAreaId   = newArea['id'] as String;
          _selectedAreaName = newArea['area_name'] as String;
          _showCreateArea   = false;
          _creatingArea     = false;
        });
        _newAreaName.clear();
        _newAreaCode.clear();
        showSuccess(context, 'Area "$name" created and selected ✓');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _creatingArea = false);
        showError(context, e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  // ── Save ────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;

    // Zone is required
    if (_selectedZoneId == null) {
      showError(context, 'Please select a Pricing Zone');
      return;
    }

    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (mounted) setState(() => _submitting = true);
    try {
      // ── Step 1: INSERT retailer with zone_id in one round-trip ────────
      // zone_id column already exists on retailers (FK to zones).
      // Passing it here is identical to INSERT then assign_retailer_zone UPDATE.
      final result = await _c.from('retailers').insert({
        'trader_id':       tid,
        'shop_name':       _shopName.text.trim(),
        'shop_name_tamil': _shopTamil.text.trim().isEmpty
            ? null : _shopTamil.text.trim(),
        'owner_name':      _ownerName.text.trim().isEmpty
            ? null : _ownerName.text.trim(),
        'phone':           _phone.text.trim().isEmpty
            ? null : _phone.text.trim(),
        'address':         _address.text.trim().isEmpty
            ? null : _address.text.trim(),
        'city':            _city.text.trim().isEmpty
            ? null : _city.text.trim(),
        'credit_limit':    double.tryParse(_creditLimit.text.trim()) ?? 100000,
        'zone_id':         _selectedZoneId,   // ← zone set at INSERT time
        'area_id':         _selectedAreaId,   // ← optional; dispatch-only, independent of zone_id
        'is_active':       true,
      }).select('id').single();

      final retailerId = result['id'] as String;

      // ── Step 2: Customer rates — only for products with a value entered ─
      if (_customerRateExpanded) {
        final rateOps = <Future<dynamic>>[];
        for (final p in _products) {
          final mp  = p['master_products'] as Map<String, dynamic>;
          final pid = mp['id'] as String;
          final raw = _rateCtrl[pid]?.text.trim() ?? '';
          final val = double.tryParse(raw);
          if (val == null || val <= 0) continue; // skip empty / zero

          // set_customer_rate param mapping based on pricing_type
          final isFixed = _pricingType == 'fixed' || _pricingType == 'contract';
          rateOps.add(_c.rpc('set_customer_rate', params: {
            'p_trader_id':       tid,
            'p_retailer_id':     retailerId,
            'p_product_id':      pid,
            'p_pricing_type':    _pricingType,
            if (isFixed) 'p_rate_per_kg': val
            else 'p_adjustment_value': val,
          }));
        }
        // Run all rate inserts in parallel
        if (rateOps.isNotEmpty) await Future.wait(rateOps);
      }

      // ── Step 3: Opening balance (existing logic — unchanged) ────────────
      final obAmount = double.tryParse(_openingBalance.text.trim()) ?? 0;
      if (_showOpeningBalance && obAmount > 0) {
        await _c.rpc('set_retailer_opening_balance', params: {
          'p_retailer_id': retailerId,
          'p_amount':      obAmount,
          'p_as_of_date':  '${_openingDate.year}-'
              '${_openingDate.month.toString().padLeft(2, '0')}-'
              '${_openingDate.day.toString().padLeft(2, '0')}',
          'p_note': _openingNote.text.trim().isEmpty
              ? 'Opening balance (migration)'
              : _openingNote.text.trim(),
        });
      }

      if (mounted) {
        showSuccess(context, '${_shopName.text.trim()} added ✓');
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(R.retailers);
        }
      }
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _shopName.dispose();  _shopTamil.dispose(); _ownerName.dispose();
    _phone.dispose();     _address.dispose();   _city.dispose();
    _creditLimit.dispose(); _openingBalance.dispose(); _openingNote.dispose();
    _newZoneName.dispose(); _newZoneCode.dispose(); _zoneSearch.dispose();
    _newAreaName.dispose(); _newAreaCode.dispose(); _areaSearch.dispose();
    for (final c in _rateCtrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      backgroundColor: kBgPage,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
          backgroundColor: kSurface,
          title: const Text('Add Retailer')),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset + 80),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Section 1: Shop Details (unchanged) ─────────────────────
              const SectionHeader('SHOP DETAILS'),
              TextFormField(
                  controller: _shopName,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                      labelText: 'Shop Name (English) *',
                      prefixIcon: Icon(Icons.store_outlined, size: 20)),
                  validator: (v) =>
                  v!.trim().isEmpty ? 'Required' : null),
              const SizedBox(height: 12),
              TextFormField(
                  controller: _shopTamil,
                  decoration: const InputDecoration(
                      labelText: 'கடை பெயர் (Tamil — optional)',
                      prefixIcon: Icon(Icons.translate_outlined, size: 20))),
              const SizedBox(height: 12),
              TextFormField(
                  controller: _ownerName,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                      labelText: 'Owner Name',
                      prefixIcon: Icon(Icons.person_outline, size: 20))),
              const SizedBox(height: 12),
              TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                      labelText: 'Phone',
                      prefixIcon: Icon(Icons.phone_outlined, size: 20))),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextFormField(
                      controller: _address,
                      maxLines: 2,
                      decoration: const InputDecoration(
                          labelText: 'Address',
                          alignLabelWithHint: true)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                      controller: _city,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                          labelText: 'City',
                          prefixIcon:
                          Icon(Icons.location_city_outlined, size: 18)),
                      onChanged: _onCityChanged),
                ),
              ]),

              // ── Section 2: Pricing Zone (required) ──────────────────────
              const SizedBox(height: 24),
              _buildZoneSection(),

              // ── Section 2b: Delivery Area (optional, dispatch-only) ──────
              const SizedBox(height: 16),
              _buildAreaSection(),

              // ── Section 3: Customer Rate (optional) ─────────────────────
              const SizedBox(height: 16),
              _buildCustomerRateSection(),

              // ── Section 4: Credit Limit ──────────────────────────────────
              const SizedBox(height: 16),
              const SectionHeader('CREDIT LIMIT'),
              TextFormField(
                  controller: _creditLimit,
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Credit Limit (₹)',
                      prefixText: '₹',
                      helperText: 'Default ₹1,00,000')),

              // ── Section 5: Opening Balance (existing, unchanged) ─────────
              const SizedBox(height: 24),
              _buildOpeningBalanceSection(),

              // ── Save button ──────────────────────────────────────────────
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: _submitting ? null : _save,
                child: _submitting
                    ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                    : const Text('Add Retailer'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Zone Section ─────────────────────────────────────────────────────────
  Widget _buildZoneSection() {
    return Container(
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(
          color: _selectedZoneId != null
              ? kPrimary.withValues(alpha: 0.4)
              : kBorderLight,
          width: _selectedZoneId != null ? 1.5 : 1.0,
        ),
        boxShadow: kCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _selectedZoneId != null
                  ? kPrimary.withValues(alpha: 0.06)
                  : Colors.grey.shade50,
              borderRadius:
              const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(children: [
              Icon(Icons.map_outlined,
                  size: 16,
                  color:
                  _selectedZoneId != null ? kPrimary : kTextSub),
              const SizedBox(width: 8),
              const Text('PRICING ZONE',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: kTextSub)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('Required',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: Colors.red)),
              ),
            ]),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Zone picker
                if (_loadingZones)
                  const Center(
                      child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2)))
                else
                  _buildZonePicker(),

                // Inline Create Zone
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => setState(
                          () => _showCreateZone = !_showCreateZone),
                  child: Row(children: [
                    Icon(
                      _showCreateZone
                          ? Icons.remove_circle_outline
                          : Icons.add_circle_outline,
                      size: 16,
                      color: kPrimary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _showCreateZone
                          ? 'Cancel'
                          : '+ Create New Zone',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: kPrimary),
                    ),
                  ]),
                ),

                if (_showCreateZone) ...[
                  const SizedBox(height: 12),
                  _buildInlineZoneCreate(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Zone picker — searchable bottom sheet trigger
  Widget _buildZonePicker() {
    return GestureDetector(
      onTap: _openZonePicker,
      child: Container(
        padding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(kRadiusInner),
          border: Border.all(
            color: _selectedZoneId != null
                ? kPrimary.withValues(alpha: 0.5)
                : Colors.grey.shade400,
            width: _selectedZoneId != null ? 1.5 : 1.0,
          ),
        ),
        child: Row(children: [
          Expanded(
            child: _selectedZoneId != null
                ? Row(children: [
              Icon(Icons.check_circle_rounded,
                  size: 16,
                  color: kPrimary.withValues(alpha: 0.8)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _selectedZoneName ?? '',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: kTextMain),
                ),
              ),
              // Clear button
              GestureDetector(
                onTap: () => setState(() {
                  _selectedZoneId   = null;
                  _selectedZoneName = null;
                }),
                child: const Icon(Icons.close,
                    size: 16, color: kTextHint),
              ),
            ])
                : const Text(
              'Tap to select a zone...',
              style: TextStyle(
                  fontSize: 14, color: kTextHint),
            ),
          ),
          const Icon(Icons.keyboard_arrow_down,
              color: kTextHint, size: 20),
        ]),
      ),
    );
  }

  void _openZonePicker() {
    _zoneSearch.clear();
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          height: MediaQuery.of(ctx).size.height * 0.6,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 12),
            const Text('Select Pricing Zone',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            // Search
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _zoneSearch,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search zones...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
                onChanged: (_) => setModal(() {}),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Builder(builder: (_) {
                final q = _zoneSearch.text.toLowerCase();
                final filtered = _zones.where((z) {
                  final name =
                  (z['zone_name'] as String).toLowerCase();
                  final code =
                  (z['zone_code'] as String).toLowerCase();
                  return name.contains(q) || code.contains(q);
                }).toList();
                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      q.isEmpty
                          ? 'No zones found.\nUse "Create New Zone" below.'
                          : 'No zone matching "$q".',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: kTextHint, fontSize: 13),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) =>
                  const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final z = filtered[i];
                    final zid = z['id'] as String;
                    final isSelected = zid == _selectedZoneId;
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        isSelected
                            ? Icons.check_circle_rounded
                            : Icons.map_outlined,
                        color: isSelected ? kPrimary : kTextSub,
                        size: 20,
                      ),
                      title: Text(
                        z['zone_name'] as String,
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.w800
                              : FontWeight.w500,
                          color: isSelected ? kPrimary : kTextMain,
                        ),
                      ),
                      trailing: Text(
                        z['zone_code'] as String,
                        style: const TextStyle(
                            fontSize: 11,
                            color: kTextHint,
                            fontWeight: FontWeight.w600),
                      ),
                      onTap: () {
                        setState(() {
                          _selectedZoneId   = zid;
                          _selectedZoneName = z['zone_name'] as String;
                        });
                        Navigator.of(ctx).pop();
                      },
                    );
                  },
                );
              }),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildInlineZoneCreate() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kPrimary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(kRadiusInner),
        border: Border.all(
            color: kPrimary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('New Zone',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: kPrimary)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: _newZoneName,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Zone Name *',
                  hintText: 'e.g. Tiruppur',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _newZoneCode,
                textCapitalization: TextCapitalization.characters,
                maxLength: 8,
                decoration: InputDecoration(
                  labelText: 'Code *',
                  hintText: 'TPR',
                  counterText: '',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 10),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _creatingZone ? null : _createZone,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                minimumSize: const Size(0, 40),
              ),
              child: _creatingZone
                  ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
                  : const Text('Create Zone',
                  style: TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Delivery Area Section (optional, dispatch-only) ──────────────────────
  Widget _buildAreaSection() {
    return Container(
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(
          color: _selectedAreaId != null
              ? kPrimary.withValues(alpha: 0.4)
              : kBorderLight,
          width: _selectedAreaId != null ? 1.5 : 1.0,
        ),
        boxShadow: kCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _selectedAreaId != null
                  ? kPrimary.withValues(alpha: 0.06)
                  : Colors.grey.shade50,
              borderRadius:
              const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(children: [
              Icon(Icons.local_shipping_outlined,
                  size: 16,
                  color:
                  _selectedAreaId != null ? kPrimary : kTextSub),
              const SizedBox(width: 8),
              const Text('DELIVERY AREA',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: kTextSub)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('Optional',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: kTextSub)),
              ),
            ]),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Used only for Dispatch grouping — separate from Pricing Zone above.',
                  style: TextStyle(fontSize: 11, color: kTextHint),
                ),
                const SizedBox(height: 10),
                if (_loadingAreas)
                  const Center(
                      child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2)))
                else
                  _buildAreaPicker(),

                // Inline Create Area
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => setState(
                          () => _showCreateArea = !_showCreateArea),
                  child: Row(children: [
                    Icon(
                      _showCreateArea
                          ? Icons.remove_circle_outline
                          : Icons.add_circle_outline,
                      size: 16,
                      color: kPrimary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _showCreateArea
                          ? 'Cancel'
                          : '+ Create New Delivery Area',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: kPrimary),
                    ),
                  ]),
                ),

                if (_showCreateArea) ...[
                  const SizedBox(height: 12),
                  _buildInlineAreaCreate(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Area picker — searchable bottom sheet trigger (mirrors zone picker)
  Widget _buildAreaPicker() {
    return GestureDetector(
      onTap: _openAreaPicker,
      child: Container(
        padding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(kRadiusInner),
          border: Border.all(
            color: _selectedAreaId != null
                ? kPrimary.withValues(alpha: 0.5)
                : Colors.grey.shade400,
            width: _selectedAreaId != null ? 1.5 : 1.0,
          ),
        ),
        child: Row(children: [
          Expanded(
            child: _selectedAreaId != null
                ? Row(children: [
              Icon(Icons.check_circle_rounded,
                  size: 16,
                  color: kPrimary.withValues(alpha: 0.8)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _selectedAreaName ?? '',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: kTextMain),
                ),
              ),
              // Clear button
              GestureDetector(
                onTap: () => setState(() {
                  _selectedAreaId   = null;
                  _selectedAreaName = null;
                }),
                child: const Icon(Icons.close,
                    size: 16, color: kTextHint),
              ),
            ])
                : const Text(
              'Tap to select a delivery area (optional)...',
              style: TextStyle(
                  fontSize: 14, color: kTextHint),
            ),
          ),
          const Icon(Icons.keyboard_arrow_down,
              color: kTextHint, size: 20),
        ]),
      ),
    );
  }

  void _openAreaPicker() {
    _areaSearch.clear();
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          height: MediaQuery.of(ctx).size.height * 0.6,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 12),
            const Text('Select Delivery Area',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _areaSearch,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search delivery areas...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
                onChanged: (_) => setModal(() {}),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Builder(builder: (_) {
                final q = _areaSearch.text.toLowerCase();
                final filtered = _areasList.where((a) {
                  final name =
                  (a['area_name'] as String).toLowerCase();
                  final code =
                  (a['area_code'] as String? ?? '').toLowerCase();
                  return name.contains(q) || code.contains(q);
                }).toList();
                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      q.isEmpty
                          ? 'No delivery areas found.\nUse "Create New Delivery Area" below.'
                          : 'No area matching "$q".',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: kTextHint, fontSize: 13),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) =>
                  const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final a = filtered[i];
                    final aid = a['id'] as String;
                    final isSelected = aid == _selectedAreaId;
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        isSelected
                            ? Icons.check_circle_rounded
                            : Icons.local_shipping_outlined,
                        color: isSelected ? kPrimary : kTextSub,
                        size: 20,
                      ),
                      title: Text(
                        a['area_name'] as String,
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.w800
                              : FontWeight.w500,
                          color: isSelected ? kPrimary : kTextMain,
                        ),
                      ),
                      trailing: Text(
                        a['area_code'] as String? ?? '',
                        style: const TextStyle(
                            fontSize: 11,
                            color: kTextHint,
                            fontWeight: FontWeight.w600),
                      ),
                      onTap: () {
                        setState(() {
                          _selectedAreaId   = aid;
                          _selectedAreaName = a['area_name'] as String;
                        });
                        Navigator.of(ctx).pop();
                      },
                    );
                  },
                );
              }),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildInlineAreaCreate() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kPrimary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(kRadiusInner),
        border: Border.all(
            color: kPrimary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('New Delivery Area',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: kPrimary)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: _newAreaName,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Area Name *',
                  hintText: 'e.g. Ooty Main',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _newAreaCode,
                textCapitalization: TextCapitalization.characters,
                maxLength: 12,
                decoration: InputDecoration(
                  labelText: 'Code (optional)',
                  hintText: 'OOTY-MAIN',
                  counterText: '',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 10),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _creatingArea ? null : _createArea,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                minimumSize: const Size(0, 40),
              ),
              child: _creatingArea
                  ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
                  : const Text('Create Delivery Area',
                  style: TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Customer Rate Section ─────────────────────────────────────────────────
  Widget _buildCustomerRateSection() {
    return Container(
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(color: kBorderLight),
        boxShadow: kCardShadow,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          onExpansionChanged: (v) =>
              setState(() => _customerRateExpanded = v),
          leading: Icon(Icons.price_change_outlined,
              size: 18,
              color: _customerRateExpanded ? kPrimary : kTextSub),
          title: const Text('Customer Rate',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700)),
          subtitle: const Text('Optional — leave blank to use Zone Rate',
              style: TextStyle(fontSize: 11, color: kTextHint)),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          children: [
            // Pricing type selector
            DropdownButtonFormField<String>(
              initialValue: _pricingType,
              decoration: const InputDecoration(
                labelText: 'Pricing Type',
                prefixIcon: Icon(Icons.tune_outlined, size: 18),
              ),
              items: _pricingTypes
                  .map((t) => DropdownMenuItem(
                value: t.$1,
                child: Text(t.$2,
                    style: const TextStyle(fontSize: 13)),
              ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _pricingType = v);
              },
            ),
            const SizedBox(height: 14),

            // Helper text based on selected pricing type
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline,
                    size: 14, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _pricingTypeHint(_pricingType),
                    style: const TextStyle(
                        fontSize: 11, color: Colors.blue),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 14),

            // Per-product rate fields
            if (_loadingProducts)
              const Center(
                  child: CircularProgressIndicator(strokeWidth: 2))
            else if (_products.isEmpty)
              const Text(
                'No active products found. Enable products first.',
                style: TextStyle(fontSize: 12, color: kTextHint),
              )
            else
              ..._products.map((p) {
                final mp  = p['master_products'] as Map<String, dynamic>;
                final pid = mp['id'] as String;
                final name = mp['name'] as String;
                final cat  = mp['category'] as String;
                final color = _productColor(cat);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    // Product label
                    Container(
                      width: 10, height: 10,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                          color: color, shape: BoxShape.circle),
                    ),
                    Expanded(
                      child: Text(name,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ),
                    // Rate input
                    SizedBox(
                      width: 110,
                      child: TextFormField(
                        controller: _rateCtrl[pid],
                        keyboardType:
                        const TextInputType.numberWithOptions(
                            decimal: true),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          hintText: '0',
                          suffixText: _pricingTypeSuffix(_pricingType),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ]),
                );
              }),
          ],
        ),
      ),
    );
  }

  // ── Opening Balance Section (existing — unchanged) ───────────────────────
  Widget _buildOpeningBalanceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () =>
              setState(() => _showOpeningBalance = !_showOpeningBalance),
          child: Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _showOpeningBalance
                  ? Colors.orange.shade50
                  : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _showOpeningBalance
                    ? Colors.orange.shade300
                    : Colors.grey.shade300,
              ),
            ),
            child: Row(children: [
              Icon(Icons.account_balance_wallet_outlined,
                  size: 18,
                  color:
                  _showOpeningBalance ? Colors.orange : kTextSub),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Opening Balance (Migration)',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _showOpeningBalance
                                ? Colors.orange.shade800
                                : kTextSub),
                      ),
                      const Text(
                          'Only use when migrating from another system',
                          style: TextStyle(
                              fontSize: 10, color: kTextHint)),
                    ]),
              ),
              Icon(
                  _showOpeningBalance
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 18,
                  color: kTextSub),
            ]),
          ),
        ),
        if (_showOpeningBalance) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline,
                              size: 16, color: Colors.orange),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'This adds the retailer\'s current unpaid amount '
                                  'from your previous records. It will appear as '
                                  '"Opening Balance" in their ledger and count '
                                  'toward their outstanding amount.',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.orange),
                            ),
                          ),
                        ]),
                  ),
                  TextFormField(
                    controller: _openingBalance,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Outstanding Amount (₹) *',
                      prefixText: '₹',
                      helperText: 'Amount this retailer currently owes you',
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    validator: (v) {
                      if (!_showOpeningBalance) return null;
                      final n = double.tryParse(v ?? '');
                      if (n == null || n < 0) return 'Enter a valid amount';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _openingDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null && mounted) {
                        setState(() => _openingDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border:
                        Border.all(color: Colors.grey.shade400),
                      ),
                      child: Row(children: [
                        const Icon(Icons.calendar_today_outlined,
                            size: 16, color: kTextSub),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                const Text('As of Date',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: kTextSub)),
                                Text(
                                    '${_openingDate.day} '
                                        '${[
                                      'Jan', 'Feb', 'Mar', 'Apr',
                                      'May', 'Jun', 'Jul', 'Aug',
                                      'Sep', 'Oct', 'Nov', 'Dec'
                                    ][_openingDate.month - 1]} '
                                        '${_openingDate.year}',
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600)),
                              ]),
                        ),
                        const Icon(Icons.arrow_drop_down,
                            color: kTextSub),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _openingNote,
                    decoration: const InputDecoration(
                      labelText: 'Note / Reference (optional)',
                      hintText:
                      'e.g. Balance from previous system as of Jan 2025',
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                ]),
          ),
        ],
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _pricingTypeHint(String t) => switch (t) {
    'flat_discount' =>
    'Zone Rate − entered value = Selling Price. '
        'e.g. Zone ₹200, Cutting ₹5 → ₹195/kg',
    'flat_premium'  =>
    'Zone Rate + entered value = Selling Price. '
        'e.g. Zone ₹200, Premium ₹5 → ₹205/kg',
    'fixed'         =>
    'Exact rate regardless of Zone Rate.',
    'contract'      =>
    'Locked contract rate — does not change with Zone.',
    'pct_discount'  =>
    'Zone Rate × (1 − %/100). e.g. Zone ₹200, 5% → ₹190/kg',
    'pct_premium'   =>
    'Zone Rate × (1 + %/100). e.g. Zone ₹200, 5% → ₹210/kg',
    _               => '',
  };

  String _pricingTypeSuffix(String t) => switch (t) {
    'pct_discount' || 'pct_premium' => '%',
    _ => '₹/kg',
  };

  Color _productColor(String category) => switch (category) {
    'broiler' => const Color(0xFF00796B),
    'country' => const Color(0xFF6D4C41),
    'quail'   => Colors.purple,
    _         => Colors.indigo,
  };
}