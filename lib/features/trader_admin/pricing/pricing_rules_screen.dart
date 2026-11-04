import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/responsive_layout.dart';
import '../../../shared/widgets/web/web.dart';

class PricingRulesScreen extends ConsumerStatefulWidget {
  const PricingRulesScreen({super.key});

  @override
  ConsumerState<PricingRulesScreen> createState() => _S();
}

class _S extends ConsumerState<PricingRulesScreen> {
  final _c = Supabase.instance.client;
  List<Map<String, dynamic>> _rules = [], _retailers = [], _products = [];
  bool _loading = true;

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
      // pricing_rules: id,rule_type,rate_per_kg,discount_pct,discount_amount,min_quantity_kg,is_active,created_at
      // rule_type CHECK: flat, percentage_discount, absolute_discount, bulk_tier
      final r = await _c
          .from('pricing_rules')
          .select('*,retailers(shop_name),master_products(name)')
          .eq('trader_id', tid)
          .order('created_at', ascending: false);
      final ret = await _c
          .from('retailers')
          .select('id,shop_name')
          .eq('trader_id', tid)
          .eq('is_active', true);
      final prod = await _c
          .from('master_products')
          .select('id,name')
          .eq('is_active', true);
      if (mounted) {
        setState(() {
          _rules = List<Map<String, dynamic>>.from(r);
          _retailers = List<Map<String, dynamic>>.from(ret);
          _products = List<Map<String, dynamic>>.from(prod);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addRule() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    final uid = ref.read(appUserProvider).valueOrNull?.userId;
    Map<String, dynamic>? selRetailer, selProduct;
    String ruleType = 'flat';
    final rateCtrl = TextEditingController();
    final discPctCtrl = TextEditingController(text: '0');
    final minQtyCtrl = TextEditingController(text: '0');

    // Same form: bottom sheet on mobile, centred dialog on web.
    Widget form(BuildContext ctx) => Padding(
            padding: EdgeInsets.fromLTRB(
                20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: StatefulBuilder(
                builder: (_, ss) => Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Add Pricing Rule',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 12),
                          SearchableRetailerPicker(
                              items: _retailers,
                              labelKey: 'shop_name',
                              hint: 'Retailer (blank = all)',
                              sheetTitle: 'Select Retailer',
                              allowNone: true,
                              noneLabel: 'All Retailers',
                              value: selRetailer,
                              onChanged: (v) => ss(() => selRetailer = v)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<Map<String, dynamic>>(
                              hint: const Text('Product (blank = all)'),
                              items: [
                                const DropdownMenuItem(
                                    value: null, child: Text('All Products')),
                                ..._products.map((p) => DropdownMenuItem(
                                    value: p, child: Text(p['name'] as String)))
                              ],
                              onChanged: (v) => ss(() => selProduct = v)),
                          const SizedBox(height: 8),
                          SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(
                                    value: 'flat', label: Text('Flat Rate')),
                                ButtonSegment(
                                    value: 'percentage_discount',
                                    label: Text('% Disc.')),
                                ButtonSegment(
                                    value: 'absolute_discount',
                                    label: Text('Abs. Disc.'))
                              ],
                              selected: {
                                ruleType
                              },
                              onSelectionChanged: (s) =>
                                  ss(() => ruleType = s.first)),
                          const SizedBox(height: 8),
                          if (ruleType == 'flat')
                            TextField(
                                controller: rateCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: const InputDecoration(
                                    labelText: 'Rate ₹/kg', prefixText: '₹')),
                          if (ruleType == 'percentage_discount')
                            TextField(
                                controller: discPctCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: const InputDecoration(
                                    labelText: 'Discount %', suffixText: '%')),
                          if (ruleType == 'absolute_discount')
                            TextField(
                                controller: rateCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: const InputDecoration(
                                    labelText: 'Discount Amount ₹',
                                    prefixText: '₹')),
                          const SizedBox(height: 8),
                          TextField(
                              controller: minQtyCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                  labelText: 'Min Qty (kg, 0=always)',
                                  suffixText: 'kg')),
                          const SizedBox(height: 14),
                          ElevatedButton(
                              onPressed: () async {
                                Navigator.of(ctx, rootNavigator: true).pop();
                                try {
                                  await _c.from('pricing_rules').insert({
                                    'trader_id': tid,
                                    'retailer_id': selRetailer?['id'],
                                    'product_id': selProduct?['id'],
                                    'rule_type': ruleType,
                                    'rate_per_kg': ruleType == 'flat'
                                        ? double.tryParse(rateCtrl.text)
                                        : null,
                                    'discount_pct': ruleType ==
                                            'percentage_discount'
                                        ? double.tryParse(discPctCtrl.text) ?? 0
                                        : 0,
                                    'discount_amount': ruleType ==
                                            'absolute_discount'
                                        ? double.tryParse(rateCtrl.text) ?? 0
                                        : 0,
                                    'min_quantity_kg':
                                        double.tryParse(minQtyCtrl.text) ?? 0,
                                    'is_active': true,
                                    'created_by': uid,
                                  });
                                  _load();
                                  if (mounted) {
                                    showSuccess(context, 'Rule added ✓');
                                  }
                                } catch (e) {
                                  if (mounted) showError(context, e.toString());
                                }
                              },
                              child: const Text('Add Rule')),
                        ])));
    if (context.isDesktop) {
      await showDialog(
          context: context,
          useRootNavigator: true,
          builder: (ctx) => Dialog(
                backgroundColor: WebColors.surface,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(WebRadius.dialog)),
                child: SizedBox(width: WebSize.dialogMd,
                    child: SingleChildScrollView(child: form(ctx))),
              ));
    } else {
      await showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useRootNavigator: true,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: form);
    }
    // controllers are ephemeral locals — GC handles disposal
  }

  Future<void> _deleteRule(Map<String, dynamic> rule) async {
    final ok = await confirmDialog(context,
        title: 'Delete Rule',
        message: 'Delete this pricing rule?');
    if (ok) {
      await _c
          .from('pricing_rules')
          .delete()
          .eq('id', rule['id']);
      _load();
    }
  }

  String _valueStr(Map<String, dynamic> rule) {
    final type = rule['rule_type'] as String? ?? 'flat';
    final rate = (rule['rate_per_kg'] as num?)?.toDouble();
    final pct = (rule['discount_pct'] as num?)?.toDouble() ?? 0;
    final abs = (rule['discount_amount'] as num?)?.toDouble() ?? 0;
    return type == 'flat'
        ? '₹${rate?.toStringAsFixed(2) ?? '—'}/kg'
        : type == 'percentage_discount'
            ? '${pct.toStringAsFixed(1)}% off'
            : '₹${abs.toStringAsFixed(2)} off';
  }

  // ═══════════════════════════════════════════════════════════════════════
  // WEB (desktop) — KPIs and a rules table.
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildWeb() {
    int countType(String t) =>
        _rules.where((r) => (r['rule_type'] ?? 'flat') == t).length;
    return WebPage(
      header: PageBreadcrumbsHeader(
        title: 'Pricing Rules',
        subtitle: 'Custom rates and discounts per retailer or product',
        crumbs: const [Crumb('Dashboard', R.dashboard), Crumb('Pricing Rules')],
        action: Row(mainAxisSize: MainAxisSize.min, children: [
          WebIconButton(icon: Icons.refresh_rounded, tooltip: 'Refresh',
              onTap: _load),
          const SizedBox(width: 8),
          WebButton(label: 'Add Rule', icon: Icons.add_rounded,
              onPressed: _addRule),
        ]),
      ),
      children: [
        WebKpiRow(children: [
          WebKpiCard(label: 'Total Rules', value: '${_rules.length}',
              icon: Icons.rule_outlined, color: WebColors.navy),
          WebKpiCard(label: 'Flat Rate', value: '${countType('flat')}',
              icon: Icons.currency_rupee, color: WebColors.info),
          WebKpiCard(label: '% Discount',
              value: '${countType('percentage_discount')}',
              icon: Icons.percent_rounded, color: WebColors.success),
          WebKpiCard(label: 'Amount Discount',
              value: '${countType('absolute_discount')}',
              icon: Icons.local_offer_outlined, color: WebColors.gold),
        ]),
        const SizedBox(height: WebSpace.lg),
        WebListCard(children: [
          const WebCardHeader(title: 'Rules', icon: Icons.rule_outlined),
          WebDataTable<Map<String, dynamic>>(
            columns: const [
              WebColumn('Retailer', flex: 3),
              WebColumn('Product', flex: 2),
              WebColumn('Type', width: 190),
              WebColumn('Value', width: 150, align: TextAlign.right),
              WebColumn('Min Qty', width: 110, align: TextAlign.right),
              WebColumn('Created', width: 130),
              WebColumn('Delete', width: 90, align: TextAlign.center),
            ],
            rows: _rules,
            paginate: true,
            dense: true,
            loading: _loading,
            emptyText: 'No pricing rules',
            emptyAction: WebButton(label: 'Add Rule', icon: Icons.add_rounded,
                onPressed: _addRule),
            cellBuilder: (rule, col) {
              final retailer =
                  (rule['retailers'] as Map?)?['shop_name'] as String?;
              final product =
                  (rule['master_products'] as Map?)?['name'] as String?;
              final type = rule['rule_type'] as String? ?? 'flat';
              switch (col) {
                case 0:
                  return Text(retailer ?? 'All Retailers',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: retailer == null
                              ? WebColors.text2 : WebColors.text1));
                case 1:
                  return Text(product ?? 'All Products',
                      style: const TextStyle(
                          fontSize: 13.5, color: WebColors.text2));
                case 2:
                  return WebLabel(type.replaceAll('_', ' '),
                      color: switch (type) {
                        'percentage_discount' => WebColors.success,
                        'absolute_discount'   => WebColors.gold,
                        _                     => WebColors.info,
                      });
                case 3:
                  return Text(_valueStr(rule), style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800,
                      color: WebColors.navy));
                case 4:
                  final q = (rule['min_quantity_kg'] as num?)?.toDouble() ?? 0;
                  return Text(q > 0 ? '${q.toStringAsFixed(0)} kg' : 'Always',
                      style: const TextStyle(
                          fontSize: 13, color: WebColors.text2));
                case 5:
                  final d =
                      DateTime.tryParse(rule['created_at'] as String? ?? '');
                  return Text(d != null ? DateFormat('d MMM y').format(d) : '—',
                      style: WebText.caption);
                default:
                  return WebIconButton(icon: Icons.delete_outline,
                      tooltip: 'Delete rule', color: WebColors.error,
                      size: 32, outlined: false,
                      onTap: () => _deleteRule(rule));
              }
            },
          ),
          const SizedBox(height: WebSpace.md),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => context.isDesktop ? _buildWeb() : Scaffold(
        backgroundColor: kBgPage,
        appBar: AppBar(
            backgroundColor: kSurface,
            title: const Text('Pricing Rules'),
            actions: [
              IconButton(
                  icon: const Icon(Icons.refresh_rounded), onPressed: _load)
            ]),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: _addRule,
            icon: const Icon(Icons.add),
            label: const Text('Add Rule')),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        // Reserve space so FAB clears the parent TraderShell glass bottom nav
        bottomNavigationBar: const SizedBox(height: kBottomNavClearance),
        body: _loading
            ? const LoadingList()
            : _rules.isEmpty
                ? const EmptyState(
                    icon: Icons.rule_outlined,
                    message: 'No pricing rules',
                    sub:
                        'Set custom rates or discounts per retailer or product')
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: _rules.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final rule = _rules[i];
                      final retailer =
                          rule['retailers'] as Map<String, dynamic>?;
                      final product =
                          rule['master_products'] as Map<String, dynamic>?;
                      final type = rule['rule_type'] as String? ?? 'flat';
                      final rate = (rule['rate_per_kg'] as num?)?.toDouble();
                      final pct =
                          (rule['discount_pct'] as num?)?.toDouble() ?? 0;
                      final abs =
                          (rule['discount_amount'] as num?)?.toDouble() ?? 0;
                      final valueStr = type == 'flat'
                          ? '₹${rate?.toStringAsFixed(2) ?? '—'}/kg'
                          : type == 'percentage_discount'
                              ? '${pct.toStringAsFixed(1)}% off'
                              : '₹${abs.toStringAsFixed(2)} off';
                      return WhiteCard(
                          child: Row(children: [
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(
                                  retailer?['shop_name'] as String? ??
                                      'All Retailers',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13)),
                              Text(
                                  product?['name'] as String? ?? 'All Products',
                                  style: const TextStyle(
                                      fontSize: 12, color: kTextSub)),
                              StatusBadge(
                                  type.replaceAll('_', ' '), Colors.blue,
                                  small: true),
                            ])),
                        Text(valueStr,
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: kNavy)),
                        IconButton(
                            icon: const Icon(Icons.delete_outline,
                                size: 18, color: kError),
                            onPressed: () => _deleteRule(rule)),
                      ]));
                    }),
      );
}
