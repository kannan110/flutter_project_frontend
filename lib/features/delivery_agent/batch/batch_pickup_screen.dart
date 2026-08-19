import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/providers/ui_mode_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/weight_calc.dart';

class BatchPickupScreen extends ConsumerStatefulWidget {
  const BatchPickupScreen({super.key, required this.batchId});

  final String batchId;

  @override
  ConsumerState<BatchPickupScreen> createState() => _S();
}

class _S extends ConsumerState<BatchPickupScreen> {
  final _c = Supabase.instance.client;
  final _form = GlobalKey<FormState>();

  final _dcNum = TextEditingController();
  final _farmer = TextEditingController();
  final _farmLoc = TextEditingController();
  final _vehicle = TextEditingController();
  final _driver = TextEditingController();
  final _grossWt = TextEditingController();
  final _emptyWt = TextEditingController(text: '0');
  final _birds = TextEditingController();
  final _crates = TextEditingController(text: '0');
  final _farmRate = TextEditingController();

  DateTime _dcDate = DateTime.now();
  String _srcType = 'farm';

  // Farm/supplier selection — links DC to supplier master
  String? _selectedFarmId;
  String? _selectedFarmName;
  List<Map<String, dynamic>> _farms = [];

  // Product selection — REQUIRED at DC time. Parent-level products only
  // (e.g. Broiler, Country) — variant breakdown (Broiler Small/Medium/Big)
  // is recorded later via loaded-stock confirmation, not here. Enforced
  // both here (parent_product_id IS NULL filter) and server-side in
  // pickup_batch/add_batch_dc (rejects variant ids even if somehow sent).
  String? _selectedProductId;
  String? _selectedProductName;
  List<Map<String, dynamic>> _parentProducts = [];
  bool _loading = false, _dataLoading = true, _uploadingDcImage = false;
  Map<String, dynamic>? _batch, _shift;
  List<Map<String, dynamic>> _existingDCs = [];
  List<Map<String, dynamic>> _deliveries = [];
  File? _dcImage;
  String? _dcImageUrl;
  final _picker = ImagePicker();

  // In-house stock per product — shown when Source Type = In-House, so the
  // agent can see what's actually available at the trader's stock point
  // before loading a DC against it. Read-only, reuses the same
  // get_available_stock RPC already used elsewhere (e.g. trader dashboard).
  List<Map<String, dynamic>> _inHouseStock = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _dcNum,
      _farmer,
      _farmLoc,
      _vehicle,
      _driver,
      _grossWt,
      _emptyWt,
      _birds,
      _crates,
      _farmRate
    ]) c.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final agentId = ref.read(appUserProvider).valueOrNull?.agentId;
    if (mounted) setState(() => _dataLoading = true);

    // FIX: each query independent with own try/catch — same fix as agent_home
    Map<String, dynamic>? batch;
    try {
      batch = await _c
          .from('delivery_batches')
          .select('*,delivery_agents(id,name,vehicle_no,phone)')
          .eq('id', widget.batchId)
          .maybeSingle();
    } catch (_) {}

    // FIX: shift query isolated — prevents silent null from shared try/catch
    Map<String, dynamic>? shift;
    try {
      if (agentId != null) {
        shift = await _c
            .from('delivery_shifts')
            .select('id,status,shift_start_at')
            .eq('delivery_agent_id', agentId)
            .eq('status', 'open')
            .maybeSingle();
      }
    } catch (_) {}

    List<Map<String, dynamic>> dcs = [];
    try {
      final raw = await _c
          .from('delivery_challans')
          .select('id,dc_number,dc_date,farmer_name,farm_location,'
          'bird_count,gross_weight,empty_weight,net_weight,'
          'crates_count,farm_rate,source_type')
          .eq('batch_id', widget.batchId)
          .order('created_at');
      dcs = List<Map<String, dynamic>>.from(raw as List? ?? []);
    } catch (_) {}

    List<Map<String, dynamic>> deliveries = [];
    try {
      final raw = await _c
          .from('deliveries')
          .select('id,status,orders(id,estimated_birds,total_quantity,'
          'retailers(shop_name,address,phone))')
          .eq('batch_id', widget.batchId);
      deliveries = List<Map<String, dynamic>>.from(raw as List? ?? []);
    } catch (_) {}

    // Pre-fill vehicle from agent profile
    if (batch?['delivery_agents']?['vehicle_no'] != null &&
        _vehicle.text.isEmpty) {
      _vehicle.text = batch!['delivery_agents']['vehicle_no'] as String;
    }

    // Load supplier list for farm picker
    List<Map<String, dynamic>> farms = [];
    try {
      final tid = ref.read(appUserProvider).valueOrNull?.traderId;
      if (tid != null) {
        final f = await _c
            .from('farms')
            .select('id,farmer_name,farm_name,location,phone')
            .eq('trader_id', tid)
            .eq('is_active', true)
            .order('farmer_name');
        farms = List<Map<String, dynamic>>.from(f as List? ?? []);
      }
    } catch (_) {}

    // Load parent-level products only (e.g. Broiler, Country, Quail) for the
    // mandatory product picker. Variants (parent_product_id IS NOT NULL) are
    // intentionally excluded — DC time is family-level only, per design.
    List<Map<String, dynamic>> parentProducts = [];
    try {
      final p = await _c
          .from('master_products')
          .select('id,name,category')
          .isFilter('parent_product_id', null)
          .eq('is_active', true)
          .order('sort_order');
      parentProducts = List<Map<String, dynamic>>.from(p as List? ?? []);
    } catch (_) {}

    // In-house stock per product (read-only) — lets the agent see what's
    // available at the trader's stock point before loading an In-House DC.
    // Reuses the existing get_available_stock RPC; no new backend logic.
    List<Map<String, dynamic>> inHouseStock = [];
    try {
      final tid = ref.read(appUserProvider).valueOrNull?.traderId;
      if (tid != null) {
        final raw = await _c
            .rpc('get_available_stock', params: {'p_trader_id': tid});
        inHouseStock = List<Map<String, dynamic>>.from(raw as List? ?? [])
            .where((r) => ((r['in_house_birds'] as num?) ?? 0) > 0 ||
            ((r['in_house_kg'] as num?) ?? 0) > 0)
            .toList();
      }
    } catch (_) {}

    if (mounted)
      setState(() {
        _batch = batch;
        _shift = shift;
        _existingDCs = dcs;
        _deliveries = deliveries;
        _farms = farms;
        _parentProducts = parentProducts;
        _inHouseStock = inHouseStock;
        _dataLoading = false;
      });
  }

  double get _grossWtVal => double.tryParse(_grossWt.text.trim()) ?? 0;

  double get _emptyWtVal => double.tryParse(_emptyWt.text.trim()) ?? 0;

  // Same shared calculation Quick Entry's optional Box/Gross/Empty
  // Weight fields now use too — one implementation, not duplicated.
  double get _netWt => WeightCalc.net(_grossWtVal, _emptyWtVal);

  int get _birdCount => int.tryParse(_birds.text.trim()) ?? 0;

  double get _avgWt => _birdCount > 0 && _netWt > 0 ? _netWt / _birdCount : 0;

  int get _totalDcBirds =>
      _existingDCs.fold(
          0, (s, c) => s + ((c['bird_count'] as num?)?.toInt() ?? 0)) +
          _birdCount;

  double get _totalDcWeight =>
      _existingDCs.fold(
          0.0, (s, c) => s + ((c['net_weight'] as num?)?.toDouble() ?? 0)) +
          _netWt;

  int get _expectedBirds =>
      _deliveries.where((d) => d['status'] != 'cancelled').fold(
          0,
              (s, d) =>
          s +
              (((d['orders'] as Map?)
                  ?.cast<String, dynamic>()?['estimated_birds'] as num?)
                  ?.toInt() ??
                  0));

  double get _expectedWeight =>
      _deliveries.where((d) => d['status'] != 'cancelled').fold(
          0.0,
              (s, d) =>
          s +
              (((d['orders'] as Map?)
                  ?.cast<String, dynamic>()?['total_quantity'] as num?)
                  ?.toDouble() ??
                  0));

  Future<void> _takeDcPhoto() async {
    try {
      final picked = await _picker.pickImage(
          source: ImageSource.camera, imageQuality: 70, maxWidth: 1200);
      if (picked == null || !mounted) return;
      final file = File(picked.path);
      if (mounted)
        setState(() {
          _dcImage = file;
          _uploadingDcImage = true;
        });
      try {
        final path = 'dc/${DateTime.now().millisecondsSinceEpoch}.jpg';
        await Supabase.instance.client.storage
            .from('dc-images')
            .upload(path, file);
        final url = Supabase.instance.client.storage
            .from('dc-images')
            .getPublicUrl(path);
        if (mounted)
          setState(() {
            _dcImageUrl = url;
            _uploadingDcImage = false;
          });
      } catch (e) {
        if (mounted) setState(() => _uploadingDcImage = false);
        if (mounted)
          showError(context, 'DC photo upload failed — check connection');
      }
    } catch (_) {}
  }

  Future<void> _saveDC() async {
    if (!_form.currentState!.validate()) return;
    if (_dcNum.text.trim().isEmpty) {
      showError(context, 'Enter DC number');
      return;
    }
    if (_farmer.text.trim().isEmpty) {
      showError(
          context, 'Enter ${_srcType == "farm" ? "Farmer" : "Source"} name');
      return;
    }
    if (_grossWtVal <= 0) {
      showError(context, 'Enter gross weight (must be > 0)');
      return;
    }
    if (_dcImageUrl == null) {
      showError(context, 'DC photo is mandatory — tap the camera button above');
      return;
    }
    if (_selectedProductId == null) {
      showError(
          context, 'Select a product for this DC (e.g. Broiler, Country)');
      return;
    }

    final bStatus = _batch?['status'] as String? ?? 'assigned';
    final isFirstPickup = bStatus == 'assigned';

    if (isFirstPickup && _shift == null) {
      showError(context, 'No active shift. Open a shift first then come back.');
      return;
    }

    if (mounted) setState(() => _loading = true);
    try {
      // FIX: always pass empty_weight as double (never null) — DB has NOT NULL constraint
      final emptyWt = _emptyWtVal; // already defaults to 0.0

      if (isFirstPickup) {
        // Step 1: Record DC and move batch to picked_up
        // FIX: p_source_type now supported — inhouse_stock writes transfer entries, not purchased
        await _c.rpc('pickup_batch', params: {
          'p_batch_id': widget.batchId,
          'p_shift_id': _shift!['id'],
          'p_dc_number': _dcNum.text.trim(),
          'p_dc_date': _dcDate.toIso8601String().split('T')[0],
          'p_farmer_name':
          _farmer.text.trim().isEmpty && _selectedFarmName != null
              ? _selectedFarmName
              : _farmer.text.trim(),
          'p_farm_id': _selectedFarmId,
          'p_farm_location':
          _farmLoc.text.trim().isEmpty ? null : _farmLoc.text.trim(),
          'p_vehicle_number':
          _vehicle.text.trim().isEmpty ? null : _vehicle.text.trim(),
          'p_driver_name':
          _driver.text.trim().isEmpty ? null : _driver.text.trim(),
          'p_supervisor_name': null,
          'p_gross_weight': _grossWtVal,
          'p_empty_weight': emptyWt,
          'p_net_weight': _netWt,
          'p_avg_weight': _avgWt > 0 ? _avgWt : 0.0,
          'p_bird_count': _birdCount,
          'p_weak_birds': 0,
          'p_crates_count': int.tryParse(_crates.text.trim()) ?? 0,
          'p_farm_rate': _farmRate.text.trim().isEmpty
              ? null
              : double.tryParse(_farmRate.text.trim()),
          'p_in_time': null,
          'p_out_time': null,
          'p_dc_photo_url': _dcImageUrl,
          'p_source_type': _srcType,
          // FIX: was missing — inhouse_stock was treated as farm
          'p_product_id': _selectedProductId,
          // NEW: explicit, mandatory — no more guessing
        });

        // Step 2: CRITICAL — advance all deliveries picked_up → out_for_delivery
        // DB trigger blocks: picked_up → delivered directly
        // start_batch_delivery moves batch + all deliveries to out_for_delivery
        await _c.rpc('start_batch_delivery',
            params: {'p_batch_id': widget.batchId});

        if (mounted) {
          showSuccess(context, 'DC saved ✓ — ready to deliver!');
          if (context.canPop())
            context.pop();
          else
            context.go(R.agentHome);
        }
      } else {
        // add_batch_dc exact signature: has p_source_type, p_bird_count int DEFAULT 0,
        // p_product_id uuid DEFAULT NULL (NEW — explicit parent product, mandatory in UI)
        await _c.rpc('add_batch_dc', params: {
          'p_batch_id': widget.batchId,
          'p_dc_number': _dcNum.text.trim(),
          'p_dc_date': _dcDate.toIso8601String().split('T')[0],
          'p_farmer_name':
          _farmer.text.trim().isEmpty && _selectedFarmName != null
              ? _selectedFarmName
              : _farmer.text.trim(),
          'p_farm_id': _selectedFarmId,
          'p_farm_location':
          _farmLoc.text.trim().isEmpty ? null : _farmLoc.text.trim(),
          'p_vehicle_number':
          _vehicle.text.trim().isEmpty ? null : _vehicle.text.trim(),
          'p_gross_weight': _grossWtVal,
          'p_empty_weight': emptyWt,
          'p_net_weight': _netWt,
          'p_avg_weight': _avgWt > 0 ? _avgWt : 0.0,
          'p_bird_count': _birdCount,
          // int DEFAULT 0 — always pass int
          'p_crates_count': int.tryParse(_crates.text.trim()) ?? 0,
          'p_farm_rate': _farmRate.text.trim().isEmpty
              ? null
              : double.tryParse(_farmRate.text.trim()),
          'p_source_type': _srcType,
          'p_product_id': _selectedProductId,
          // NEW: explicit, mandatory — no more guessing
          'p_dc_photo_url': _dcImageUrl,
          // FIX: was missing on add_batch_dc — photo was captured (mandatory,
          // validated above) but never sent, so 2nd+ DCs always saved with
          // no photo even though one was taken.
        });
        if (mounted) {
          showSuccess(context, 'DC added ✓');
          _clearForm();
          _load();
        }
      }
    } catch (e) {
      if (mounted) {
        final msg = e
            .toString()
            .replaceAll('Exception: ', '')
            .replaceAll('PostgrestException(message: ', '')
            .replaceAll(')', '');
        showError(context, msg);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _clearForm() {
    _dcNum.clear();
    _farmer.clear();
    _farmLoc.clear();
    _birds.clear();
    _farmRate.clear();
    _grossWt.clear();
    _emptyWt.text = '0';
    _crates.text = '0';
    if (mounted)
      setState(() {
        _dcDate = DateTime.now();
        // Do NOT silently carry the product forward — a second DC on the same
        // batch may legitimately be a different product (e.g. Farm A → Broiler,
        // Farm B → Country). Force a fresh, deliberate choice each time.
        _selectedProductId = null;
        _selectedProductName = null;
        // FIX: the DC photo must never carry over to the next DC either — a
        // stale, already-uploaded photo passing the "mandatory" check would
        // silently attach the PREVIOUS DC's photo to this new one. Every DC
        // must have its own explicitly re-taken photo.
        _dcImage = null;
        _dcImageUrl = null;
        _uploadingDcImage = false;
      });
  }

  void _showFarmPicker() {
    showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) {
          String query = '';
          return StatefulBuilder(builder: (ctx, ss) {
            final filtered = query.isEmpty
                ? _farms
                : _farms
                .where((f) =>
            (f['farmer_name'] as String? ?? '')
                .toLowerCase()
                .contains(query.toLowerCase()) ||
                (f['farm_name'] as String? ?? '')
                    .toLowerCase()
                    .contains(query.toLowerCase()) ||
                (f['location'] as String? ?? '')
                    .toLowerCase()
                    .contains(query.toLowerCase()))
                .toList();
            return DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.6,
                maxChildSize: 0.9,
                builder: (_, ctrl) => Column(children: [
                  // Handle
                  Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                      child: Column(children: [
                        Center(
                            child: Container(
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                    color: Colors.grey.shade300,
                                    borderRadius:
                                    BorderRadius.circular(2)))),
                        const SizedBox(height: 10),
                        const Text('Select Supplier',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 10),
                        // Search
                        TextField(
                            onChanged: (v) => ss(() => query = v),
                            decoration: const InputDecoration(
                                hintText: 'Search supplier...',
                                prefixIcon: Icon(Icons.search, size: 18),
                                isDense: true)),
                      ])),
                  const Divider(height: 1),
                  // List
                  Expanded(
                      child: ListView.separated(
                          controller: ctrl,
                          padding: const EdgeInsets.all(12),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                          const SizedBox(height: 4),
                          itemBuilder: (_, i) {
                            final f = filtered[i];
                            final name = f['farmer_name'] as String? ?? '—';
                            final farm = f['farm_name'] as String?;
                            final loc = f['location'] as String?;
                            final phone = f['phone'] as String?;
                            return InkWell(
                                onTap: () {
                                  Navigator.of(ctx, rootNavigator: true)
                                      .pop();
                                  setState(() {
                                    _selectedFarmId = f['id'] as String;
                                    _selectedFarmName = farm != null
                                        ? '$name ($farm)'
                                        : name;
                                    // Pre-fill the manual field too
                                    _farmer.text = name;
                                    if (loc != null &&
                                        _farmLoc.text.isEmpty)
                                      _farmLoc.text = loc;
                                  });
                                },
                                borderRadius:
                                BorderRadius.circular(kRadiusCard),
                                child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                        color: _selectedFarmId == f['id']
                                            ? kPrimary.withValues(
                                            alpha: 0.06)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(
                                            kRadiusCard),
                                        border: Border.all(
                                            color:
                                            _selectedFarmId == f['id']
                                                ? kPrimary
                                                : kBorder,
                                            width:
                                            _selectedFarmId == f['id']
                                                ? 1.5
                                                : 1)),
                                    child: Row(children: [
                                      Container(
                                          width: 36,
                                          height: 36,
                                          decoration: BoxDecoration(
                                              color: kPrimary.withValues(
                                                  alpha: 0.08),
                                              shape: BoxShape.circle),
                                          child: Center(
                                              child: Text(
                                                  name[0].toUpperCase(),
                                                  style: const TextStyle(
                                                      fontWeight:
                                                      FontWeight.w800,
                                                      color: kPrimary)))),
                                      const SizedBox(width: 10),
                                      Expanded(
                                          child: Column(
                                              crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                              children: [
                                                Text(name,
                                                    style: const TextStyle(
                                                        fontSize: 13,
                                                        fontWeight:
                                                        FontWeight.w700)),
                                                if (farm != null)
                                                  Text(farm,
                                                      style: const TextStyle(
                                                          fontSize: 10,
                                                          color: kTextHint)),
                                                if (loc != null)
                                                  Text(loc,
                                                      style: const TextStyle(
                                                          fontSize: 10,
                                                          color: kTextHint)),
                                              ])),
                                      if (phone != null)
                                        Text(phone,
                                            style: const TextStyle(
                                                fontSize: 10,
                                                color: kTextHint)),
                                      if (_selectedFarmId == f['id'])
                                        const Icon(Icons.check_circle,
                                            color: kPrimary, size: 16),
                                    ])));
                          })),
                  // Add new supplier shortcut
                  SafeArea(
                      child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(ctx, rootNavigator: true)
                                    .pop();
                                // Navigate to purchase screen to add supplier
                                context.go(R.purchase);
                              },
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add New Supplier'),
                              style: OutlinedButton.styleFrom(
                                  minimumSize:
                                  const Size(double.infinity, 44))))),
                ]));
          });
        });
  }

  void _showProductPicker() {
    showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 10),
              const Text('What product is this DC?',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                  'One product per DC. Variant breakdown (Small/Medium/Big) '
                      'is confirmed separately after loading.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: kTextHint)),
              const SizedBox(height: 14),
              if (_parentProducts.isEmpty)
                Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('No active products found. Contact admin.',
                        style: TextStyle(color: kTextHint))),
              ..._parentProducts.map((p) {
                final id = p['id'] as String;
                final name = p['name'] as String? ?? '—';
                final cat = p['category'] as String?;
                final selected = _selectedProductId == id;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedProductId = id;
                        _selectedProductName = name;
                      });
                      Navigator.of(ctx, rootNavigator: true).pop();
                    },
                    borderRadius: BorderRadius.circular(kRadiusCard),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: selected
                            ? kPrimary.withValues(alpha: 0.08)
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(kRadiusCard),
                        border: Border.all(
                            color: selected ? kPrimary : kBorder,
                            width: selected ? 2 : 1),
                      ),
                      child: Row(children: [
                        Icon(
                          cat == 'broiler'
                              ? Icons.egg_outlined
                              : cat == 'country'
                              ? Icons.pets_outlined
                              : Icons.flutter_dash_outlined,
                          size: 24,
                          color: selected ? kPrimary : kTextHint,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Text(name,
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color:
                                    selected ? kPrimary : Colors.black))),
                        if (selected)
                          const Icon(Icons.check_circle,
                              color: kPrimary, size: 20),
                      ]),
                    ),
                  ),
                );
              }),
            ]),
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    if (_dataLoading)
      return Scaffold(
          backgroundColor: kBgPage,
          appBar: AppBar(
              backgroundColor: const Color(0xFF1B6CA8),
              foregroundColor: Colors.white,
              title: const Text('Add DC')),
          body: const LoadingList());

    final a = _batch?['delivery_agents'] as Map<String, dynamic>?;
    final bStatus = _batch?['status'] as String? ?? 'assigned';
    final isAdditional = bStatus != 'assigned';

    if (ref.watch(uiModeProvider).isSimple) {
      return _buildSimpleView(isAdditional);
    }

    return Scaffold(
      appBar: AppBar(
        // FIX: explicit back button always present
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (context.canPop())
                context.pop();
              else
                context.go(R.agentHome);
            }),
        title: Text(isAdditional
            ? 'Add DC — Additional Pickup'
            : 'Farm Pickup — Create DC'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load)
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 96 + MediaQuery.viewInsetsOf(context).bottom),
        child: Form(
            key: _form,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Batch info card ──────────────────────────────────
                  WhiteCard(
                      child: Row(children: [
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(a?['name'] as String? ?? '—',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700, fontSize: 14)),
                                  Text(
                                      'Vehicle: ${_batch?['vehicle_no'] ?? a?['vehicle_no'] ?? '—'}',
                                      style: const TextStyle(
                                          fontSize: 11, color: kTextSub)),
                                ])),
                        StatusBadge(bStatus, SC.order(bStatus)),
                      ])),
                  const SizedBox(height: 12),

                  // ── Shift status ─────────────────────────────────────
                  Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: _shift != null
                              ? Colors.green.shade50
                              : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(kRadiusCard),
                          border: Border.all(
                              color: _shift != null
                                  ? Colors.green.shade200
                                  : Colors.red.shade200)),
                      child: Row(children: [
                        Icon(
                            _shift != null
                                ? Icons.check_circle_outline
                                : Icons.warning_amber_rounded,
                            color: _shift != null ? Colors.green : Colors.red,
                            size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(
                                _shift != null
                                    ? 'Shift active ✓ — ready to add DC'
                                    : 'No active shift! Open a shift first.',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _shift != null
                                        ? Colors.green.shade700
                                        : Colors.red))),
                        if (_shift == null)
                          TextButton(
                              onPressed: () {
                                if (context.canPop()) context.pop();
                                context.go(R.shiftOpen);
                              },
                              child: const Text('Open Shift →',
                                  style:
                                  TextStyle(fontWeight: FontWeight.w700))),
                      ])),
                  const SizedBox(height: 12),

                  // ── Orders in batch ──────────────────────────────────
                  if (_deliveries.isNotEmpty) ...[
                    const SectionHeader('ORDERS IN THIS BATCH'),
                    WhiteCard(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(children: [
                                    _miniStat('Expected Birds', '$_expectedBirds',
                                        Colors.blue),
                                    _miniStat(
                                        'Expected Weight',
                                        '${_expectedWeight.toStringAsFixed(0)} kg',
                                        Colors.teal),
                                    _miniStat(
                                        'Orders',
                                        '${_deliveries.where((d) => d['status'] != 'cancelled').length}',
                                        kPrimary),
                                  ])),
                              ..._deliveries
                                  .where((d) => d['status'] != 'cancelled')
                                  .map((d) {
                                final o = d['orders'] as Map<String, dynamic>?;
                                final r = o?['retailers'] as Map<String, dynamic>?;
                                final birds =
                                    (o?['estimated_birds'] as num?)?.toInt() ?? 0;
                                final weight =
                                    (o?['total_quantity'] as num?)?.toDouble() ?? 0;
                                return Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Row(children: [
                                      const Icon(Icons.store_outlined,
                                          size: 13, color: kPrimary),
                                      const SizedBox(width: 6),
                                      Expanded(
                                          child: Text(
                                              r?['shop_name'] as String? ?? '—',
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600))),
                                      Text(
                                          '${birds > 0 ? '$birds birds' : ''}${birds > 0 && weight > 0 ? ' · ' : ''}${weight > 0 ? '${weight.toStringAsFixed(0)} kg' : ''}',
                                          style: const TextStyle(
                                              fontSize: 11, color: kTextSub)),
                                    ]));
                              }),
                            ])),
                    const SizedBox(height: 12),
                  ],

                  // ── Existing DCs ─────────────────────────────────────
                  if (_existingDCs.isNotEmpty) ...[
                    const SectionHeader('EXISTING DCs'),
                    ..._existingDCs.map((ch) {
                      final net = (ch['net_weight'] as num?)?.toDouble() ?? 0;
                      final birds = (ch['bird_count'] as num?)?.toInt() ?? 0;
                      final crates = (ch['crates_count'] as num?)?.toInt() ?? 0;
                      final src = ch['source_type'] as String? ?? 'farm';
                      return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(kRadiusChip),
                              border: Border.all(color: Colors.green.shade200)),
                          child: Row(children: [
                            const Icon(Icons.check_circle_outline,
                                color: Colors.green, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          '${ch['dc_number'] ?? '—'} — ${ch['farmer_name'] ?? '—'}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12)),
                                      Text(
                                          '$birds birds · ${net.toStringAsFixed(1)} kg · $crates crates · $src',
                                          style: const TextStyle(
                                              fontSize: 11, color: kTextSub)),
                                    ])),
                          ]));
                    }),
                    Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                            color: kPrimary.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(8)),
                        child: Row(children: [
                          const Icon(Icons.summarize_outlined,
                              size: 14, color: kPrimary),
                          const SizedBox(width: 6),
                          Expanded(
                              child: Text(
                                  'Total picked up: '
                                      '${_existingDCs.fold(0, (s, c) => s + ((c['bird_count'] as num?)?.toInt() ?? 0))} birds · '
                                      '${_existingDCs.fold(0.0, (s, c) => s + ((c['net_weight'] as num?)?.toDouble() ?? 0)).toStringAsFixed(1)} kg',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: kPrimary,
                                      fontWeight: FontWeight.w700))),
                        ])),
                    const Divider(height: 20),
                  ],

                  // ── New DC section header ────────────────────────────
                  Text(
                      _existingDCs.isEmpty
                          ? '📋 DC DETAILS'
                          : '📋 ADD ANOTHER DC',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: kTextHint,
                          letterSpacing: 0.8)),
                  const SizedBox(height: 10),

                  // FIX: Source type toggle for ALL DCs (first AND additional)
                  const Text('Source Type',
                      style: TextStyle(
                          fontSize: 11,
                          color: kTextHint,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                            value: 'farm',
                            icon: Icon(Icons.agriculture, size: 14),
                            label: Text('Farm')),
                        ButtonSegment(
                            value: 'shop_collection',
                            icon: Icon(Icons.store_outlined, size: 14),
                            label: Text('Shop')),
                        ButtonSegment(
                            value: 'inhouse_stock',
                            icon: Icon(Icons.warehouse_outlined, size: 14),
                            label: Text('In-House')),
                      ],
                      selected: {
                        _srcType
                      },
                      onSelectionChanged: (s) =>
                          setState(() => _srcType = s.first)),
                  // FIX: Show in-house DC guidance when source = inhouse_stock
                  if (_srcType == 'inhouse_stock') ...[
                    const SizedBox(height: 8),
                    Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(kRadiusChip),
                            border: Border.all(color: Colors.orange.shade200)),
                        child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Icon(Icons.warehouse_outlined,
                                    color: Colors.orange, size: 14),
                                SizedBox(width: 6),
                                Text('IN-HOUSE DC — Internal Transfer',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.orange)),
                              ]),
                              SizedBox(height: 4),
                              Text(
                                  'This will move stock FROM trader in-house inventory TO your agent stock.\n'
                                      'Trader in-house stock will DECREASE. Your stock will INCREASE.',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.orange,
                                      height: 1.4)),
                            ])),
                    if (_inHouseStock.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: kBgGrey,
                              borderRadius: BorderRadius.circular(kRadiusChip),
                              border: Border.all(color: kBorderLight)),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('AVAILABLE IN-HOUSE STOCK',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: kTextHint,
                                        letterSpacing: 0.6)),
                                const SizedBox(height: 6),
                                ..._inHouseStock.map((s) {
                                  final birds =
                                      (s['in_house_birds'] as num?)?.toInt() ?? 0;
                                  final kg =
                                      (s['in_house_kg'] as num?)?.toDouble() ?? 0;
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 2),
                                    child: Row(children: [
                                      Expanded(
                                          child: Text(
                                              s['product_name'] as String? ??
                                                  '—',
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: kNavy))),
                                      Text(
                                          'Available: $birds Birds | ${kg.toStringAsFixed(2)} Kg',
                                          style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: kTextSub)),
                                    ]),
                                  );
                                }),
                              ])),
                    ],
                  ],
                  const SizedBox(height: 12),

                  // ── Product (REQUIRED) ───────────────────────────────
                  const Text('PRODUCT *',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: kTextHint,
                          letterSpacing: 0.5)),
                  const SizedBox(height: 6),
                  GestureDetector(
                      onTap: _showProductPicker,
                      child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: _selectedProductId != null
                                  ? kPrimary.withValues(alpha: 0.08)
                                  : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(kRadiusCard),
                              border: Border.all(
                                  color: _selectedProductId != null
                                      ? kPrimary
                                      : Colors.red.shade300,
                                  width:
                                  _selectedProductId != null ? 1.5 : 1.5)),
                          child: Row(children: [
                            Icon(Icons.egg_outlined,
                                size: 22,
                                color: _selectedProductId != null
                                    ? kPrimary
                                    : Colors.red.shade400),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Text(
                                    _selectedProductId != null
                                        ? _selectedProductName!
                                        : 'Select Product (e.g. Broiler, Country)',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: _selectedProductId != null
                                            ? kPrimary
                                            : Colors.red.shade700))),
                            Icon(Icons.chevron_right,
                                size: 20,
                                color: _selectedProductId != null
                                    ? kPrimary
                                    : Colors.red.shade300),
                          ]))),
                  const SizedBox(height: 12),

                  // ── DC Image (mandatory) ─────────────────────────
                  const Text('DC PHOTO *',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: kTextHint,
                          letterSpacing: 0.5)),
                  const SizedBox(height: 6),
                  GestureDetector(
                      onTap: _uploadingDcImage ? null : _takeDcPhoto,
                      child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: _dcImage != null
                                  ? Colors.green.shade50
                                  : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(kRadiusCard),
                              border: Border.all(
                                  color: _dcImage != null
                                      ? Colors.green.shade300
                                      : Colors.red.shade300,
                                  width: _dcImage != null ? 1 : 1.5)),
                          child: Row(children: [
                            if (_dcImage != null)
                              ClipRRect(
                                  borderRadius:
                                  BorderRadius.circular(kRadiusChip),
                                  child: Image.file(_dcImage!,
                                      width: 60, height: 60, fit: BoxFit.cover))
                            else
                              Column(children: [
                                const Icon(Icons.camera_alt,
                                    size: 40, color: Colors.red),
                                const SizedBox(height: 2),
                                const Text('Required',
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.red,
                                        fontWeight: FontWeight.w700)),
                              ]),
                            const SizedBox(width: 14),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          _dcImage != null
                                              ? 'DC Photo Captured ✓'
                                              : 'Take DC Photo (Mandatory)',
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w800,
                                              color: _dcImage != null
                                                  ? Colors.green
                                                  : Colors.red)),
                                      const SizedBox(height: 4),
                                      Text(
                                          _uploadingDcImage
                                              ? 'Uploading...'
                                              : _dcImageUrl != null
                                              ? 'Uploaded & linked to DC ✓'
                                              : 'Take a clear photo of the farm goods / challan',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: _dcImageUrl != null
                                                  ? Colors.green
                                                  : Colors.red.shade400)),
                                    ])),
                            if (_uploadingDcImage)
                              const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child:
                                  CircularProgressIndicator(strokeWidth: 2))
                            else if (_dcImageUrl != null)
                              const Icon(Icons.check_circle,
                                  color: Colors.green, size: 26)
                            else
                              Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle),
                                  child: const Icon(Icons.camera_alt,
                                      color: Colors.white, size: 18)),
                          ]))),
                  const SizedBox(height: 14),

                  // ── DC Number + Date ─────────────────────────────────
                  Row(children: [
                    Expanded(
                        child: TextFormField(
                            controller: _dcNum,
                            textCapitalization: TextCapitalization.characters,
                            decoration:
                            const InputDecoration(labelText: 'DC Number *'),
                            validator: (v) =>
                            v!.trim().isEmpty ? 'Required' : null)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: InkWell(
                            onTap: () async {
                              final d = await showDatePicker(
                                  context: context,
                                  initialDate: _dcDate,
                                  firstDate: DateTime.now()
                                      .subtract(const Duration(days: 7)),
                                  lastDate: DateTime.now());
                              if (d != null && mounted)
                                setState(() => _dcDate = d);
                            },
                            child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 16),
                                decoration: BoxDecoration(
                                    color: const Color(0xFFF3F4F6),
                                    borderRadius: BorderRadius.circular(10)),
                                child: Row(children: [
                                  const Icon(Icons.calendar_today_outlined,
                                      size: 16, color: kPrimary),
                                  const SizedBox(width: 8),
                                  Text(DateFormat('d MMM y').format(_dcDate),
                                      style: const TextStyle(fontSize: 13)),
                                ])))),
                  ]),
                  const SizedBox(height: 10),

                  // ── Supplier picker from master list ─────────────────────
                  if (_srcType == 'farm' && _farms.isNotEmpty) ...[
                    GestureDetector(
                        onTap: _showFarmPicker,
                        child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 13),
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius:
                                BorderRadius.circular(kRadiusCard),
                                border: Border.all(
                                    color: _selectedFarmId != null
                                        ? kPrimary
                                        : kBorder,
                                    width: _selectedFarmId != null ? 1.5 : 1)),
                            child: Row(children: [
                              Icon(Icons.agriculture_outlined,
                                  size: 16,
                                  color: _selectedFarmId != null
                                      ? kPrimary
                                      : kTextHint),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            _selectedFarmId != null
                                                ? 'Supplier Selected'
                                                : 'Select from Supplier List',
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: _selectedFarmId != null
                                                    ? kPrimary
                                                    : kTextHint)),
                                        if (_selectedFarmId != null)
                                          Text(_selectedFarmName ?? '—',
                                              style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700)),
                                      ])),
                              if (_selectedFarmId != null)
                                GestureDetector(
                                    onTap: () => setState(() {
                                      _selectedFarmId = null;
                                      _selectedFarmName = null;
                                      _farmer.clear();
                                    }),
                                    child: const Icon(Icons.close,
                                        size: 16, color: kTextHint))
                              else
                                const Icon(Icons.chevron_right,
                                    size: 16, color: kTextHint),
                            ]))),
                    const SizedBox(height: 6),
                    const Center(
                        child: Text('— or type manually —',
                            style: TextStyle(fontSize: 10, color: kTextHint))),
                    const SizedBox(height: 6),
                  ],
                  // ── Farmer name text input ────────────────────────────────
                  TextFormField(
                      controller: _farmer,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                          labelText: _srcType == 'shop_collection'
                              ? 'Shop Name *'
                              : _srcType == 'inhouse_stock'
                              ? 'Stock Point Name *'
                              : 'Farmer Name *',
                          prefixIcon: Icon(
                              _srcType == 'farm'
                                  ? Icons.agriculture
                                  : _srcType == 'shop_collection'
                                  ? Icons.store_outlined
                                  : Icons.warehouse_outlined,
                              size: 18,
                              color: kPrimary)),
                      validator: (v) => v!.trim().isEmpty ? 'Required' : null),
                  const SizedBox(height: 8),
                  TextFormField(
                      controller: _farmLoc,
                      decoration: InputDecoration(
                          labelText: _srcType == 'shop_collection'
                              ? 'Shop Location (optional)'
                              : _srcType == 'inhouse_stock'
                              ? 'Storage Location (optional)'
                              : 'Farm Location (optional)')),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                        child: TextFormField(
                            controller: _vehicle,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                                labelText: 'Vehicle No.'))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextFormField(
                            controller: _driver,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                                labelText: 'Driver Name'))),
                  ]),
                  const SizedBox(height: 16),

                  // ── Weight & Birds ───────────────────────────────────
                  const SectionHeader('WEIGHT & BIRDS'),
                  Row(children: [
                    Expanded(
                        child: TextFormField(
                            controller: _grossWt,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                                labelText: 'Gross Weight (kg) *',
                                suffixText: 'kg'),
                            onChanged: (_) => setState(() {}),
                            validator: (v) {
                              final n = double.tryParse(v?.trim() ?? '');
                              return (n == null || n <= 0)
                                  ? 'Enter gross weight'
                                  : null;
                            })),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextFormField(
                            controller: _emptyWt,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                                labelText: 'Empty Crates (kg)',
                                suffixText: 'kg'),
                            onChanged: (_) => setState(() {}))),
                  ]),

                  // Live net weight display
                  if (_grossWtVal > 0)
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                                color: _netWt > 0
                                    ? Colors.green.shade50
                                    : Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(8)),
                            child: Row(children: [
                              Icon(Icons.balance_outlined,
                                  size: 14,
                                  color: _netWt > 0
                                      ? Colors.green
                                      : Colors.orange),
                              const SizedBox(width: 8),
                              Text(
                                  'Net = ${_grossWtVal.toStringAsFixed(2)} − ${_emptyWtVal.toStringAsFixed(2)} = ${_netWt.toStringAsFixed(2)} kg',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: _netWt > 0
                                          ? Colors.green.shade700
                                          : Colors.orange)),
                            ]))),
                  const SizedBox(height: 8),

                  Row(children: [
                    Expanded(
                        child: TextFormField(
                            controller: _birds,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Bird Count', suffixText: 'birds'),
                            onChanged: (_) => setState(() {}))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextFormField(
                            controller: _crates,
                            keyboardType: TextInputType.number,
                            decoration:
                            const InputDecoration(labelText: 'Crates'))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextFormField(
                            controller: _farmRate,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                                labelText: 'Rate (₹/kg)', prefixText: '₹'))),
                  ]),

                  if (_birdCount > 0 && _netWt > 0)
                    Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('Avg: ${_avgWt.toStringAsFixed(3)} kg/bird',
                            style: const TextStyle(
                                fontSize: 11, color: kTextSub))),

                  // Running total vs expected
                  if (_expectedBirds > 0) ...[
                    const SizedBox(height: 10),
                    Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(kRadiusChip),
                            border: Border.all(color: Colors.blue.shade100)),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Running Total (this DC + previous):',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.blue,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 6),
                              Row(children: [
                                _miniStat(
                                    'DC Birds', '$_totalDcBirds', Colors.blue),
                                _miniStat(
                                    'DC Weight',
                                    '${_totalDcWeight.toStringAsFixed(1)} kg',
                                    Colors.teal),
                                _miniStat(
                                    'Need Birds', '$_expectedBirds', kPrimary),
                                _miniStat(
                                    'Need Weight',
                                    '${_expectedWeight.toStringAsFixed(0)} kg',
                                    kPrimary),
                              ]),
                              if (_totalDcBirds < _expectedBirds &&
                                  _totalDcBirds > 0)
                                Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                        '⚠ ${_expectedBirds - _totalDcBirds} birds still needed',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.orange,
                                            fontWeight: FontWeight.w600))),
                              if (_totalDcBirds >= _expectedBirds &&
                                  _expectedBirds > 0)
                                const Padding(
                                    padding: EdgeInsets.only(top: 6),
                                    child: Text(
                                        '✓ Sufficient birds for all orders',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.green,
                                            fontWeight: FontWeight.w600))),
                            ])),
                  ],
                  const SizedBox(height: 24),

                  ElevatedButton(
                      onPressed: (_loading || _shift == null && !isAdditional)
                          ? null
                          : _saveDC,
                      style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52)),
                      child: _loading
                          ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white))
                          : Text(
                          isAdditional
                              ? 'Save Additional DC'
                              : 'Confirm Pickup & Save DC',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700))),
                  const SizedBox(height: 20),
                ])),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SIMPLE MODE — large buttons, big fonts, icon-first
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildSimpleView(bool isAdditional) {
    final a = _batch?['delivery_agents'] as Map<String, dynamic>?;
    final bStatus = _batch?['status'] as String? ?? 'assigned';
    final hasShift = _shift != null;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop())
              context.pop();
            else
              context.go(R.agentHome);
          },
        ),
        title: Text(isAdditional ? '📋 Add DC' : '🚜 Farm Pickup',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load)
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 96 + MediaQuery.viewInsetsOf(context).bottom),
        child: Form(
            key: _form,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Shift status ─────────────────────────────────────
                  _simpleShiftBanner(hasShift),
                  if (!hasShift) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (context.canPop()) context.pop();
                            context.go(R.shiftOpen);
                          },
                          icon: const Icon(Icons.access_time, size: 20),
                          label: const Text('Open Shift',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800)),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: kPrimary,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14))),
                        )),
                  ],

                  if (hasShift) ...[
                    const SizedBox(height: 12),

                    // ── Batch info ────────────────────────────────────────
                    _simpleInfoCard(
                      emoji: '🚚',
                      title: a?['name'] as String? ?? '—',
                      subtitle:
                      'Vehicle: ${_batch?['vehicle_no'] ?? a?['vehicle_no'] ?? '—'}',
                      trailing: bStatus,
                    ),
                    const SizedBox(height: 12),

                    // ── Existing DCs summary ──────────────────────────────
                    if (_existingDCs.isNotEmpty) ...[
                      _simpleInfoCard(
                        emoji: '✅',
                        title: '${_existingDCs.length} DC(s) already added',
                        subtitle: '${_totalDcBirds - _birdCount} birds · '
                            '${(_totalDcWeight - _netWt).toStringAsFixed(1)} kg',
                        color: Colors.green,
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ── Source type ───────────────────────────────────────
                    _simpleSectionCard(
                      emoji: '📍',
                      title: 'Source Type',
                      children: [
                        Row(children: [
                          _simpleSourceChip('Farm', 'farm', Icons.agriculture),
                          const SizedBox(width: 8),
                          _simpleSourceChip(
                              'Shop', 'shop_collection', Icons.store_outlined),
                          const SizedBox(width: 8),
                          _simpleSourceChip('In-House', 'inhouse_stock',
                              Icons.warehouse_outlined),
                        ]),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ── Product (REQUIRED) ──────────────────────────────────
                    // One product per DC — matches real farm pickups (one species
                    // per visit). Variant split happens later via loaded-stock
                    // confirmation, not here.
                    _simpleSectionCard(
                      emoji: '🐔',
                      title: 'Product',
                      children: [_simpleProductPicker()],
                    ),
                    const SizedBox(height: 12),

                    // ── DC Photo (mandatory) ─────────────────────────────
                    _simpleCameraTile(),
                    const SizedBox(height: 12),

                    // ── DC Number & Date ─────────────────────────────────
                    _simpleSectionCard(
                      emoji: '📄',
                      title: 'DC Details',
                      children: [
                        _simpleBigInput(
                          controller: _dcNum,
                          hint: 'DC Number',
                          textCapitalization: TextCapitalization.characters,
                          validator: (v) =>
                          v!.trim().isEmpty ? 'Required' : null,
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () async {
                            final d = await showDatePicker(
                                context: context,
                                initialDate: _dcDate,
                                firstDate: DateTime.now()
                                    .subtract(const Duration(days: 7)),
                                lastDate: DateTime.now());
                            if (d != null && mounted)
                              setState(() => _dcDate = d);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 16),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(kRadiusCard),
                              border: Border.all(color: kBorder),
                            ),
                            child: Row(children: [
                              const Icon(Icons.calendar_today_outlined,
                                  size: 22, color: kPrimary),
                              const SizedBox(width: 10),
                              Text(DateFormat('d MMM y').format(_dcDate),
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ── Farmer/Supplier ─────────────────────────────────
                    _simpleSectionCard(
                      emoji: '👨‍🌾',
                      title: _srcType == 'shop_collection'
                          ? 'Shop Name'
                          : 'Farmer Name',
                      children: [
                        if (_srcType == 'farm' && _farms.isNotEmpty)
                          _simpleFarmPicker(),
                        _simpleBigInput(
                          controller: _farmer,
                          hint: _srcType == 'shop_collection'
                              ? 'Shop Name'
                              : 'Farmer Name',
                          textCapitalization: TextCapitalization.words,
                          validator: (v) =>
                          v!.trim().isEmpty ? 'Required' : null,
                        ),
                        const SizedBox(height: 8),
                        _simpleBigInput(
                          controller: _farmLoc,
                          hint: 'Location (optional)',
                          textCapitalization: TextCapitalization.words,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ── Vehicle & Driver ────────────────────────────────
                    _simpleSectionCard(
                      emoji: '🚛',
                      title: 'Vehicle & Driver',
                      children: [
                        Row(children: [
                          Expanded(
                            child: _simpleBigInput(
                              controller: _vehicle,
                              hint: 'Vehicle No.',
                              textCapitalization: TextCapitalization.characters,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _simpleBigInput(
                              controller: _driver,
                              hint: 'Driver Name',
                              textCapitalization: TextCapitalization.words,
                            ),
                          ),
                        ]),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ── Weight & Birds ──────────────────────────────────
                    _simpleSectionCard(
                      emoji: '⚖️',
                      title: 'Weight & Birds',
                      children: [
                        Row(children: [
                          Expanded(
                            child: _simpleBigInput(
                              controller: _grossWt,
                              hint: 'Gross Weight',
                              suffix: 'kg',
                              keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true),
                              validator: (v) {
                                final n = double.tryParse(v?.trim() ?? '');
                                return (n == null || n <= 0)
                                    ? 'Enter gross weight'
                                    : null;
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _simpleBigInput(
                              controller: _emptyWt,
                              hint: 'Empty',
                              suffix: 'kg',
                              keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true),
                            ),
                          ),
                        ]),
                        if (_grossWtVal > 0) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(kRadiusCard),
                            ),
                            child: Row(children: [
                              const Text('⚖️', style: TextStyle(fontSize: 22)),
                              const SizedBox(width: 10),
                              Text('Net = ${_netWt.toStringAsFixed(2)} kg',
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.green)),
                            ]),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                            child: _simpleBigInput(
                              controller: _birds,
                              hint: 'Birds',
                              suffix: 'birds',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _simpleBigInput(
                              controller: _crates,
                              hint: 'Crates',
                            ),
                          ),
                        ]),
                        if (_birdCount > 0 && _netWt > 0) ...[
                          const SizedBox(height: 6),
                          Text('🐔 Avg: ${_avgWt.toStringAsFixed(3)} kg/bird',
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: kTextSub)),
                        ],
                        const SizedBox(height: 8),
                        _simpleBigInput(
                          controller: _farmRate,
                          hint: 'Rate (₹/kg)',
                          prefix: '₹',
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // ── Submit ──────────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _saveDC,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18)),
                          elevation: 3,
                        ),
                        child: _loading
                            ? const SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                                strokeWidth: 3, color: Colors.white))
                            : Text(
                            isAdditional
                                ? '✅ Save Additional DC'
                                : '✅ Start Pickup',
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: Colors.white)),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ])),
      ),
    );
  }

  Widget _simpleShiftBanner(bool hasShift) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasShift ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: hasShift ? Colors.green.shade300 : Colors.red.shade300,
            width: 2),
      ),
      child: Row(children: [
        Text(hasShift ? '✅' : '⛔', style: const TextStyle(fontSize: 28)),
        const SizedBox(width: 12),
        Expanded(
          child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(hasShift ? 'Shift Active' : 'No Active Shift',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: hasShift
                        ? Colors.green.shade700
                        : Colors.red.shade700)),
            Text(hasShift ? 'Ready to add DC' : 'Open a shift first',
                style: TextStyle(
                    fontSize: 14,
                    color: hasShift
                        ? Colors.green.shade600
                        : Colors.red.shade600)),
          ]),
        ),
      ]),
    );
  }

  Widget _simpleInfoCard({
    required String emoji,
    required String title,
    String? subtitle,
    String? trailing,
    Color? color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: color ?? kPrimary.withValues(alpha: 0.3), width: 2),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 24)),
        const SizedBox(width: 12),
        Expanded(
            child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              if (subtitle != null)
                Text(subtitle,
                    style: const TextStyle(fontSize: 13, color: kTextSub)),
            ])),
        if (trailing != null) StatusBadge(trailing, SC.order(trailing)),
      ]),
    );
  }

  Widget _simpleSectionCard({
    required String emoji,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Text(title,
              style:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 14),
        ...children,
      ]),
    );
  }

  Widget _simpleBigInput({
    required TextEditingController controller,
    required String hint,
    String? suffix,
    String? prefix,
    TextInputType? keyboardType,
    TextCapitalization? textCapitalization,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType ?? TextInputType.text,
      textCapitalization: textCapitalization ?? TextCapitalization.none,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        suffixText: suffix,
        prefixText: prefix,
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadiusCard),
          borderSide: BorderSide(color: kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadiusCard),
          borderSide: BorderSide(color: kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadiusCard),
          borderSide: const BorderSide(color: kPrimary, width: 2),
        ),
      ),
    );
  }

  Widget _simpleSourceChip(String label, String value, IconData icon) {
    final selected = _srcType == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _srcType = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: selected
                ? kPrimary.withValues(alpha: 0.1)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(kRadiusCard),
            border: Border.all(
              color: selected ? kPrimary : Colors.grey.shade300,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(children: [
            Icon(icon, size: 22, color: selected ? kPrimary : kTextHint),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? kPrimary : kTextHint)),
          ]),
        ),
      ),
    );
  }

  Widget _simpleCameraTile() {
    return GestureDetector(
      onTap: _uploadingDcImage ? null : _takeDcPhoto,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _dcImage != null ? Colors.green.shade50 : Colors.red.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
            _dcImage != null ? Colors.green.shade300 : Colors.red.shade300,
            width: _dcImage != null ? 2 : 2,
          ),
        ),
        child: Row(children: [
          if (_dcImage != null)
            ClipRRect(
                borderRadius: BorderRadius.circular(kRadiusCard),
                child: Image.file(_dcImage!,
                    width: 64, height: 64, fit: BoxFit.cover))
          else
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(kRadiusCard),
              ),
              child: const Icon(Icons.camera_alt_outlined,
                  size: 32, color: Colors.red),
            ),
          const SizedBox(width: 16),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        _dcImage != null
                            ? '✅ DC Photo taken'
                            : '📸 Take DC Photo (Required)',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: _dcImage != null
                                ? Colors.green.shade700
                                : Colors.red.shade700)),
                    const SizedBox(height: 4),
                    Text(
                        _uploadingDcImage
                            ? 'Uploading...'
                            : _dcImageUrl != null
                            ? '✓ Uploaded & linked'
                            : 'Take a clear photo of the challan',
                        style: TextStyle(
                            fontSize: 13,
                            color: _dcImageUrl != null
                                ? Colors.green.shade600
                                : Colors.red.shade600)),
                  ])),
          if (_uploadingDcImage)
            const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.5))
          else if (_dcImageUrl != null)
            const Icon(Icons.check_circle, color: Colors.green, size: 32)
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                  color: Colors.red, shape: BoxShape.circle),
              child:
              const Icon(Icons.camera_alt, color: Colors.white, size: 22),
            ),
        ]),
      ),
    );
  }

  Widget _simpleProductPicker() {
    final selected = _selectedProductId != null;
    return GestureDetector(
      onTap: _showProductPicker,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:
          selected ? kPrimary.withValues(alpha: 0.08) : Colors.red.shade50,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border: Border.all(
            color: selected ? kPrimary : Colors.red.shade300,
            width: selected ? 2 : 2,
          ),
        ),
        child: Row(children: [
          Icon(Icons.egg_outlined,
              size: 24, color: selected ? kPrimary : Colors.red.shade400),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selected
                          ? _selectedProductName!
                          : '👆 Select Product (Required)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: selected ? kPrimary : Colors.red.shade700,
                      ),
                    ),
                    if (selected)
                      Text('Tap to change',
                          style: TextStyle(fontSize: 12, color: kTextHint)),
                  ])),
          const Icon(Icons.chevron_right, size: 22, color: kTextHint),
        ]),
      ),
    );
  }

  Widget _simpleFarmPicker() {
    final selected = _selectedFarmId != null;
    return GestureDetector(
      onTap: _showFarmPicker,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:
          selected ? kPrimary.withValues(alpha: 0.08) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border: Border.all(
            color: selected ? kPrimary : kBorder,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(children: [
          Icon(Icons.agriculture_outlined,
              size: 24, color: selected ? kPrimary : kTextHint),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selected
                          ? _selectedFarmName!
                          : '👆 Select from Supplier List',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: selected ? kPrimary : kTextHint,
                      ),
                    ),
                    if (selected)
                      Text('Tap to change',
                          style: TextStyle(fontSize: 12, color: kTextHint)),
                  ])),
          const Icon(Icons.chevron_right, size: 22, color: kTextHint),
        ]),
      ),
    );
  }

  Widget _miniStat(String l, String v, Color c) => Expanded(
      child: Column(children: [
        Text(v,
            style:
            TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c)),
        Text(l,
            style: const TextStyle(fontSize: 9, color: kTextHint),
            textAlign: TextAlign.center),
      ]));
}