import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import 'retailer_invoice_detail_screen.dart';

class RetailerScreen extends ConsumerStatefulWidget {
  const RetailerScreen({super.key});
  @override ConsumerState<RetailerScreen> createState() => _RS();
}

class _RS extends ConsumerState<RetailerScreen>
    with SingleTickerProviderStateMixin {
  final _c = Supabase.instance.client;
  late TabController _tab;

  Map<String,dynamic>?      _dashboard;
  List<Map<String,dynamic>> _orders     = [];
  Map<String,dynamic>?      _ledgerData;
  List<Map<String,dynamic>> _complaints = [];
  List<Map<String,dynamic>> _history    = [];

  bool _loading = true;
  String? _retailerId;
  DateTime _from = DateTime.now().subtract(const Duration(days: 29));
  DateTime _to   = DateTime.now();
  // Ledger — List (card) vs Table view toggle.
  bool _ledgerTableView = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 6, vsync: this);
    _tab.addListener(() { if (!_tab.indexIsChanging) _load(); });
    _initRetailer();
  }
  @override void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _initRetailer() async {
    _retailerId = ref.read(appUserProvider).valueOrNull?.retailerId;
    if (_retailerId == null) {
      final uid = ref.read(appUserProvider).valueOrNull?.userId;
      if (uid == null) return;
      final ru = await _c.from('retailer_users')
          .select('retailer_id').eq('user_id', uid).maybeSingle();
      _retailerId = (ru)?['retailer_id'] as String?;
    }
    _load();
  }

  Future<void> _load() async {
    final rid = _retailerId;
    if (rid == null || !mounted) return;
    if (mounted) setState(() => _loading = true);
    final fromStr = DateFormat('yyyy-MM-dd').format(_from);
    final toStr   = DateFormat('yyyy-MM-dd').format(_to);
    try {
      switch (_tab.index) {
        case 0:
        case 5:
          final d = await _c.rpc('get_retailer_dashboard',
              params: {'p_retailer_id': rid}).timeout(const Duration(seconds: 12));
          if (mounted) setState(() => _dashboard = d as Map<String,dynamic>?);
        case 1:
          final r = await _c.from('orders')
              .select('id,status,order_date,delivery_date,total_quantity,'
              'estimated_birds,total_amount,final_amount,delivered_weight,'
              'collected_amount,balance_amount,notes,created_at,'
              'invoices(invoice_number,total_amount,status)')
              .eq('retailer_id', rid)
              .gte('order_date', fromStr).lte('order_date', toStr)
              .neq('status', 'cancelled')
              .order('created_at', ascending: false).limit(50);
          if (mounted) setState(() => _orders = List<Map<String,dynamic>>.from(r as List? ?? []));
        case 2:
        // Ledger Detail — calls the new get_retailer_ledger_v2 (reuses
        // get_retailer_statement's logic, retailer-only auth built in).
        // get_retailer_ledger (old) is untouched, kept for backward
        // compatibility.
          final l = await _c.rpc('get_retailer_ledger_v2', params: {
            'p_retailer_id': rid, 'p_from_date': fromStr, 'p_to_date': toStr,
          }).timeout(const Duration(seconds: 10));
          if (mounted) setState(() => _ledgerData = l as Map<String,dynamic>?);
        case 3:
          final r = await _c.from('retailer_complaints')
              .select('id,complaint_type,description,claimed_amount,status,resolution,created_at')
              .eq('retailer_id', rid).order('created_at', ascending: false).limit(30);
          if (mounted) setState(() => _complaints = List<Map<String,dynamic>>.from(r as List? ?? []));
        case 4:
          final r = await _c.rpc('get_retailer_order_history', params: {
            'p_retailer_id': rid, 'p_from_date': fromStr, 'p_to_date': toStr,
          }).timeout(const Duration(seconds: 10));
          if (mounted) {
            setState(() => _history = List<Map<String,dynamic>>.from(
              (r as Map<String,dynamic>?)?['orders'] as List? ?? []));
          }
      }
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ',''));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final shopName = (_dashboard?['retailer'] as Map<String,dynamic>?)?['shop_name']
    as String? ?? 'My Shop';
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
          backgroundColor: kSurface, elevation: 0,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(shopName,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: kNavy)),
            const Text('Retailer Portal',
                style: TextStyle(fontSize: 10, color: kTextHint, fontWeight: FontWeight.w600,
                    letterSpacing: 0.4)),
          ]),
          actions: [
            Stack(children: [
              IconButton(icon: const Icon(Icons.notifications_outlined, color: kTextMain),
                  onPressed: _showNotifications),
              if ((_dashboard?['unread_notifications'] as num? ?? 0) > 0)
                Positioned(right: 8, top: 8, child: Container(width: 8, height: 8,
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle))),
            ]),
            IconButton(icon: const Icon(Icons.refresh, color: kTextMain), onPressed: _load),
          ],
          bottom: TabBar(
              controller: _tab, isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              tabs: const [
                Tab(text: 'Home'),  Tab(text: 'Orders'),
                Tab(text: 'Ledger'), Tab(text: 'Complaints'),
                Tab(text: 'History'), Tab(text: 'Profile'),
              ])),
      body: _loading ? const LoadingList()
          : TabBarView(controller: _tab, children: [
        _tabHome(), _tabOrders(), _tabLedger(),
        _tabComplaints(), _tabHistory(), _tabProfile(),
      ]),
      // Reserve space so FAB clears the TraderShell glass bottom nav
      bottomNavigationBar: const SizedBox(height: 80),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: (_tab.index == 0 || _tab.index == 1)
          ? FloatingActionButton.extended(
          onPressed: _showPlaceOrder,
          backgroundColor: kPrimary,
          icon: const Icon(Icons.add_shopping_cart),
          label: const Text('Place Order'))
          : null,
    );
  }

  // ─── HOME ────────────────────────────────────────────────────────────────
  Widget _tabHome() {
    final fin    = _dashboard?['financials'] as Map<String,dynamic>?;
    final credit = _dashboard?['credit']     as Map<String,dynamic>?;
    final rate   = _dashboard?['current_rate'] as Map<String,dynamic>?;
    final pending   = _dashboard?['pending_deliveries'] as List? ?? [];
    final lastDel   = _dashboard?['last_delivery'] as Map<String,dynamic>?;
    final complaints= (_dashboard?['open_complaints'] as num?)?.toInt() ?? 0;

    final outstanding = (fin?['outstanding']       as num?)?.toDouble() ?? 0;
    final totalPaid   = (fin?['total_paid']         as num?)?.toDouble() ?? 0;
    final creditLimit = (credit?['credit_limit']    as num?)?.toDouble() ?? 0;
    final avail       = (credit?['available_credit'] as num?)?.toDouble() ?? 0;
    final isBlocked   = credit?['is_blocked'] == true;
    final usedPct     = creditLimit > 0 ? (outstanding/creditLimit).clamp(0.0,1.0) : 0.0;

    return RefreshIndicator(onRefresh: _load,
        child: SingleChildScrollView(physics: const AlwaysScrollableScrollPhysics(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (isBlocked) Container(color: Colors.red.shade50, padding: const EdgeInsets.all(12),
                  child: const Row(children: [
                    Icon(Icons.block, color: Colors.red, size: 16), SizedBox(width: 8),
                    Expanded(child: Text('Account blocked. Contact your supplier.',
                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700))),
                  ])),
              if (rate != null) Container(
                  decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [kNavy, kNavyMid],
                          begin: Alignment.centerLeft, end: Alignment.centerRight)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    const Icon(Icons.trending_up_rounded, color: kGoldLight, size: 16),
                    const SizedBox(width: 8),
                    Text("Today's Rate: ₹" + ((rate['rate'] as num?)?.toStringAsFixed(2) ?? '--') + '/kg',
                        style: const TextStyle(color: Colors.white,
                            fontWeight: FontWeight.w900, fontSize: 14)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: kGold.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: const Text('LIVE', style: TextStyle(color: kGoldLight,
                          fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
                    ),
                  ])),
              const SizedBox(height: 12),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(children: [
                    _kpiCard('Outstanding', Fmt.amount(outstanding),
                        outstanding > 0 ? Colors.orange : Colors.green, Icons.account_balance_outlined),
                    const SizedBox(width: 8),
                    _kpiCard('Total Paid', Fmt.amount(totalPaid),
                        Colors.green, Icons.check_circle_outline),
                    const SizedBox(width: 8),
                    _kpiCard('Credit Avail.', Fmt.amount(avail),
                        avail > 0 ? Colors.blue : Colors.grey, Icons.credit_card_outlined),
                  ])),
              if (creditLimit > 0) ...[
                const SizedBox(height: 8),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: kSurface,
                            borderRadius: BorderRadius.circular(kRadiusCard),
                            border: Border.all(color: kBorderLight), boxShadow: kCardShadow),
                        child: Column(children: [
                          Row(children: [
                            const Text('Credit Usage',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                            const Spacer(),
                            Text('${Fmt.amount(outstanding)} / ${Fmt.amount(creditLimit)}',
                                style: const TextStyle(fontSize: 10, color: kTextSub)),
                          ]),
                          const SizedBox(height: 6),
                          ClipRRect(borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(value: usedPct, minHeight: 6,
                                  backgroundColor: Colors.grey.shade200,
                                  valueColor: AlwaysStoppedAnimation(
                                      usedPct > 0.8 ? Colors.red
                                          : usedPct > 0.5 ? Colors.orange : Colors.green))),
                          const SizedBox(height: 4),
                          Row(children: [
                            Text('${(usedPct*100).toStringAsFixed(0)}% used',
                                style: TextStyle(fontSize: 9,
                                    color: usedPct > 0.8 ? Colors.red : kTextHint)),
                            const Spacer(),
                            Text('${Fmt.amount(avail)} free',
                                style: const TextStyle(fontSize: 9, color: Colors.green)),
                          ]),
                        ]))),
              ],
              const SizedBox(height: 10),
              if (pending.isNotEmpty) ...[
                _sectionTitle('Active Deliveries'),
                ...pending.map((del) {
                  final d = del as Map<String,dynamic>;
                  final sts = d['status'] as String? ?? '';
                  final agent = d['agent_name'] as String?;
                  return Container(
                      margin: const EdgeInsets.fromLTRB(12,0,12,6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade200)),
                      child: Row(children: [
                        Container(width: 36, height: 36,
                            decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(kRadiusChip)),
                            child: const Icon(Icons.local_shipping_outlined, color: Colors.blue, size: 18)),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(sts.replaceAll('_',' ').toUpperCase(),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.blue)),
                          if (agent != null) Text('Agent: $agent',
                              style: const TextStyle(fontSize: 10, color: kTextHint)),
                        ])),
                        const Icon(Icons.chevron_right, size: 18, color: kTextHint),
                      ]));
                }),
              ],
              if (lastDel != null) ...[
                _sectionTitle('Last Delivery'),
                Container(
                    margin: const EdgeInsets.fromLTRB(12,0,12,6),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: kSurface,
                        borderRadius: BorderRadius.circular(kRadiusCard),
                        border: Border.all(color: kBorderLight), boxShadow: kCardShadow),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${(lastDel['pickup_bird_count'] as num?)?.toInt() ?? 0} birds  |  '
                            '${(lastDel['delivered_total_weight'] as num?)?.toStringAsFixed(1) ?? 0} kg',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        if (lastDel['delivered_at'] != null)
                          Text(DateFormat('d MMM, hh:mm a').format(
                              DateTime.tryParse(lastDel['delivered_at'] as String)?.toLocal() ?? DateTime.now()),
                              style: const TextStyle(fontSize: 10, color: kTextHint)),
                      ])),
                      if (lastDel['total_amount'] != null)
                        Text(Fmt.amount((lastDel['total_amount'] as num).toDouble()),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: kPrimary)),
                    ])),
              ],
              if (complaints > 0) GestureDetector(
                  onTap: () => _tab.animateTo(3),
                  child: Container(
                      margin: const EdgeInsets.fromLTRB(12,4,12,6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(kRadiusCard),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.25))),
                      child: Row(children: [
                        const Icon(Icons.warning_amber_outlined, color: Colors.orange, size: 16),
                        const SizedBox(width: 8),
                        Text('$complaints open complaint${complaints > 1 ? "s" : ""}',
                            style: const TextStyle(fontSize: 11, color: Colors.orange,
                                fontWeight: FontWeight.w700)),
                        const Spacer(),
                        const Text('View', style: TextStyle(fontSize: 10, color: Colors.orange)),
                      ]))),
              _sectionTitle('Quick Actions'),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(children: [
                    _quickAction('Order Now',  Icons.add_shopping_cart, kPrimary,     _showPlaceOrder),
                    const SizedBox(width: 8),
                    _quickAction('Pay Now',    Icons.payments_outlined,  Colors.green, _showPayment),
                    const SizedBox(width: 8),
                    _quickAction('Invoices',   Icons.receipt_outlined,   Colors.blue,  () => _tab.animateTo(4)),
                    const SizedBox(width: 8),
                    _quickAction('Complaint',  Icons.report_outlined,    Colors.orange, _showRaiseComplaint),
                  ])),
              const SizedBox(height: 80),
            ])));
  }

  // ─── ORDERS ──────────────────────────────────────────────────────────────
  Widget _tabOrders() => Column(children: [
    _dateRangeBar(),
    Expanded(child: _orders.isEmpty
        ? const EmptyState(icon: Icons.shopping_bag_outlined, message: 'No orders')
        : ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (_, i) {
          final o = _orders[i];
          final status  = o['status'] as String? ?? 'pending';
          final birds   = (o['estimated_birds'] as num?)?.toInt() ?? 0;
          final qty     = (o['total_quantity']  as num?)?.toDouble() ?? 0;
          final total   = (o['total_amount']    as num?)?.toDouble() ?? 0;
          final paid    = (o['collected_amount'] as num?)?.toDouble() ?? 0;
          final balance = (o['balance_amount']  as num?)?.toDouble() ?? 0;
          final dt      = DateTime.tryParse(o['created_at'] as String? ?? '');
          final c       = _statusColor(status);
          return GestureDetector(
              onTap: () => _showOrderDetail(o),
              child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: kSurface,
                      borderRadius: BorderRadius.circular(kRadiusCard),
                      border: Border.all(color: kBorderLight), boxShadow: kCardShadow),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(birds > 0 ? '$birds birds' : '${qty.toStringAsFixed(0)} kg',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                        if (dt != null) Text(DateFormat('d MMM yyyy').format(dt.toLocal()),
                            style: const TextStyle(fontSize: 10, color: kTextHint)),
                      ])),
                      Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: c.withValues(alpha: 0.09),
                              borderRadius: BorderRadius.circular(kRadiusChip),
                              border: Border.all(color: c.withValues(alpha: 0.25))),
                          child: Text(status.toUpperCase().replaceAll('_',' '),
                              style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: c))),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      _oStat('Total', Fmt.amount(total), Colors.blue),
                      _oStat('Paid',  Fmt.amount(paid),  Colors.green),
                      _oStat('Due',   Fmt.amount(balance), balance > 0 ? Colors.orange : Colors.green),
                    ]),
                    if (balance > 0) ...[
                      const SizedBox(height: 6),
                      ClipRRect(borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                              value: total > 0 ? (paid/total).clamp(0.0,1.0) : 0,
                              minHeight: 3, backgroundColor: Colors.grey.shade200,
                              valueColor: const AlwaysStoppedAnimation(Colors.orange))),
                    ],
                    // Cancel button — only for pending/confirmed (before pickup)
                    if (['pending','confirmed'].contains(status)) ...[
                      const SizedBox(height: 8),
                      const Divider(height: 1),
                      const SizedBox(height: 6),
                      GestureDetector(
                          onTap: () => _cancelOrder(o['id'] as String, status),
                          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.cancel_outlined, size: 14, color: kError),
                            SizedBox(width: 4),
                            Text('Cancel Order',
                                style: TextStyle(fontSize: 11, color: kError,
                                    fontWeight: FontWeight.w700)),
                          ])),
                    ],
                  ])));
        })),
  ]);

  // ─── LEDGER ──────────────────────────────────────────────────────────────
  // Reuses get_retailer_ledger_v2 — same calculation logic as the Trader
  // Customer Ledger's get_retailer_statement (cancelled-invoice/payment-
  // reversal exclusion, real opening balance), with the retailer-only
  // auth check built into that function. No separate calculation lives
  // here; this only renders the JSON that RPC returns.
  Widget _tabLedger() {
   // final opening = (_ledgerData?['opening_balance'] as num?)?.toDouble() ?? 0;
    //final closing = (_ledgerData?['closing_balance'] as num?)?.toDouble() ?? 0;
  final rows    = List<Map<String,dynamic>>.from(
    (_ledgerData?['rows'] ?? _ledgerData?['entries']) as List? ?? []);
final summary = _ledgerData?['summary'] as Map<String,dynamic>?;
final debit   = ((summary?['total_debits'] ?? summary?['total_debit']) as num?)?.toDouble() ?? 0;
final credit  = ((summary?['total_credits'] ?? summary?['total_credit']) as num?)?.toDouble() ?? 0;
final closing = ((_ledgerData?['closing_balance'] ?? summary?['balance']) as num?)?.toDouble() ?? 0;

// opening balance is not in the response, so derive it from the first row
double opening = (_ledgerData?['opening_balance'] as num?)?.toDouble() ?? 0;
if (_ledgerData?['opening_balance'] == null && rows.isNotEmpty) {
  final f   = rows.first;
  final amt = (f['amount'] as num?)?.toDouble() ?? 0;
  final rb  = (f['running_balance'] as num?)?.toDouble() ?? 0;
  opening = f['entry_type'] == 'debit' ? rb - amt : rb + amt;
}
    return Column(children: [
      _dateRangeBar(),
      Container(decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [kNavy, kNavyMid],
              begin: Alignment.topLeft, end: Alignment.bottomRight)),
          padding: const EdgeInsets.fromLTRB(16,16,16,16),
          child: Column(children: [
            Row(children: [
              _lStat('Opening', Fmt.amount(opening), Colors.white70),
              _lStat('Billed', Fmt.amount(debit),   Colors.red),
              _lStat('Paid',   Fmt.amount(credit),  Colors.green),
            ]),
            const SizedBox(height: 10),
            const Divider(color: Color(0xFFB4C6F4), height: 1),
            const SizedBox(height: 10),
            Row(children: [
              _lStat('Closing Balance', Fmt.amount(closing), closing > 0 ? Colors.orange : Colors.green),
            ]),
          ])),
      // List / Table view toggle.
      Container(
          color: kSurface,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          alignment: Alignment.centerRight,
          child: ToggleButtons(
              constraints: const BoxConstraints(minHeight: 30, minWidth: 64),
              borderRadius: BorderRadius.circular(8),
              isSelected: [!_ledgerTableView, _ledgerTableView],
              onPressed: (i) => setState(() => _ledgerTableView = i == 1),
              children: const [
                Padding(padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.view_agenda_outlined, size: 14), SizedBox(width: 4), Text('List', style: TextStyle(fontSize: 11)),
                    ])),
                Padding(padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.table_rows_outlined, size: 14), SizedBox(width: 4), Text('Table', style: TextStyle(fontSize: 11)),
                    ])),
              ])),
      if (rows.isEmpty)
        const Expanded(child: EmptyState(icon: Icons.book_outlined, message: 'No ledger entries'))
      else Expanded(child: _ledgerTableView ? _ledgerTable(rows, opening, closing) : _ledgerList(rows)),
    ]);
  }

  Widget _ledgerList(List<Map<String,dynamic>> rows) => ListView.separated(
      padding: const EdgeInsets.all(12), itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (_, i) {
        final e   = rows[i];
        final isD = e['entry_type'] == 'debit';
        final amt = (e['amount'] as num?)?.toDouble() ?? 0;
        final rb  = (e['running_balance'] as num?)?.toDouble() ?? 0;
        final dt  = DateTime.tryParse(e['entry_date'] as String? ?? '');
        final ref = e['ref_number'] as String?;
        final isInvoice = e['source_type'] == 'invoice' && e['invoice_id'] != null;
        final c   = isD ? Colors.red : Colors.green;
        return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(color: kSurface,
                borderRadius: BorderRadius.circular(kRadiusCard),
                border: Border.all(color: kBorderLight),
                boxShadow: kCardShadow),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(isD ? 'Purchase / Bill' : 'Payment',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
                // Invoice/payment reference — same ref_number the
                // trader's Customer Ledger already shows (invoice
                // number, "OB" for opening balance, credit note
                // number).
                if (ref != null)
                  Text('Ref: $ref', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kTextSub)),
                if (e['description'] != null)
                  Text(e['description'] as String,
                      style: const TextStyle(fontSize: 9, color: kTextHint),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                // View Invoice — reuses get_invoice_detail via
                // RetailerInvoiceDetailScreen, no separate rendering.
                if (isInvoice) ...[
                  const SizedBox(height: 4),
                  GestureDetector(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => RetailerInvoiceDetailScreen(invoiceId: e['invoice_id'] as String))),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.receipt_long_outlined, size: 12, color: kNavy),
                        SizedBox(width: 3),
                        Text('View Invoice', style: TextStyle(fontSize: 10, color: kNavy, fontWeight: FontWeight.w700)),
                      ])),
                ],
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${isD ? "+" : "-"}${Fmt.amount(amt)}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c)),
                Text('Bal: ${Fmt.amount(rb)}',
                    style: const TextStyle(fontSize: 9, color: kTextHint)),
                // Business date (entry_date) — not created_at.
                if (dt != null) Text(DateFormat('d MMM').format(dt),
                    style: const TextStyle(fontSize: 9, color: kTextHint)),
              ]),
            ]));
      });

  // Table view — Date | Ref No | Particulars | Debit | Credit | Running
  // Balance, with Opening Balance as the first row and Closing Balance
  // as the last, matching the same convention the Trader Customer
  // Ledger PDF already uses. Ref No is tappable (View Invoice) when the
  // row is an invoice entry.
  Widget _ledgerTable(List<Map<String,dynamic>> rows, double opening, double closing) {
    return SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        scrollDirection: Axis.horizontal,
        child: DataTable(
            headingRowHeight: 36, dataRowMinHeight: 40, dataRowMaxHeight: 52,
            columnSpacing: 18,
            headingTextStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: kNavy),
            dataTextStyle: const TextStyle(fontSize: 11, color: kTextMain),
            columns: const [
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Ref No')),
              DataColumn(label: Text('Particulars')),
              DataColumn(label: Text('Debit'), numeric: true),
              DataColumn(label: Text('Credit'), numeric: true),
              DataColumn(label: Text('Running Balance'), numeric: true),
            ],
            rows: [
              DataRow(cells: [
                const DataCell(Text('—')),
                const DataCell(Text('OPEN', style: TextStyle(fontWeight: FontWeight.w700))),
                const DataCell(Text('Opening Balance')),
                const DataCell(Text('—')),
                const DataCell(Text('—')),
                DataCell(Text(Fmt.amount(opening), style: const TextStyle(fontWeight: FontWeight.w700))),
              ]),
              ...rows.map((e) {
                final isD = e['entry_type'] == 'debit';
                final amt = (e['amount'] as num?)?.toDouble() ?? 0;
                final rb  = (e['running_balance'] as num?)?.toDouble() ?? 0;
                final dt  = DateTime.tryParse(e['entry_date'] as String? ?? '');
                final ref = e['ref_number'] as String?;
                final particulars = (e['description'] as String?) ?? (isD ? 'Purchase / Bill' : 'Payment');
                final isInvoice = e['source_type'] == 'invoice' && e['invoice_id'] != null;
                return DataRow(cells: [
                  DataCell(Text(dt != null ? DateFormat('d MMM yy').format(dt) : '—')),
                  DataCell(
                      ref == null ? const Text('—') : isInvoice
                          ? GestureDetector(
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => RetailerInvoiceDetailScreen(invoiceId: e['invoice_id'] as String))),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(ref, style: const TextStyle(color: kNavy, fontWeight: FontWeight.w700,
                                decoration: TextDecoration.underline)),
                            const SizedBox(width: 3),
                            const Icon(Icons.open_in_new, size: 11, color: kNavy),
                          ]))
                          : Text(ref)),
                  DataCell(SizedBox(width: 130, child: Text(particulars, maxLines: 2, overflow: TextOverflow.ellipsis))),
                  DataCell(Text(isD ? Fmt.amount(amt) : '—', style: const TextStyle(color: Colors.red))),
                  DataCell(Text(!isD ? Fmt.amount(amt) : '—', style: const TextStyle(color: Colors.green))),
                  DataCell(Text(Fmt.amount(rb), style: const TextStyle(fontWeight: FontWeight.w700))),
                ]);
              }),
              DataRow(cells: [
                const DataCell(Text('—')),
                const DataCell(Text('—')),
                const DataCell(Text('Closing Balance', style: TextStyle(fontWeight: FontWeight.w800))),
                const DataCell(Text('—')),
                const DataCell(Text('—')),
                DataCell(Text(Fmt.amount(closing),
                    style: TextStyle(fontWeight: FontWeight.w900, color: closing > 0 ? Colors.orange : Colors.green))),
              ]),
            ]));
  }

  // ─── COMPLAINTS ──────────────────────────────────────────────────────────
  Widget _tabComplaints() => Column(children: [
    Container(color: Colors.white, padding: const EdgeInsets.all(12),
        child: Row(children: [
          const Expanded(child: Text('My Complaints',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
          ElevatedButton.icon(onPressed: _showRaiseComplaint,
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Raise', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 32), backgroundColor: Colors.orange)),
        ])),
    Expanded(child: _complaints.isEmpty
        ? const EmptyState(icon: Icons.thumb_up_outlined, message: 'No complaints')
        : ListView.separated(
        padding: const EdgeInsets.all(12), itemCount: _complaints.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (_, i) {
          final cp  = _complaints[i];
          final sts = cp['status'] as String? ?? 'open';
          final amt = (cp['claimed_amount'] as num?)?.toDouble() ?? 0;
          final dt  = DateTime.tryParse(cp['created_at'] as String? ?? '');
          final c   = sts == 'resolved' ? Colors.green
              : sts == 'rejected' ? Colors.grey : Colors.orange;
          return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: kSurface,
                  borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(color: kBorderLight), boxShadow: kCardShadow),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(
                      (cp['complaint_type'] as String? ?? '').replaceAll('_', ' ')
                          .split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
                          .join(' '),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800))),
                  Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: c.withValues(alpha: 0.09),
                          borderRadius: BorderRadius.circular(kRadiusChip),
                          border: Border.all(color: c.withValues(alpha: 0.25))),
                      child: Text(sts.toUpperCase(),
                          style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: c))),
                ]),
                const SizedBox(height: 4),
                Text(cp['description'] as String? ?? '—',
                    style: const TextStyle(fontSize: 11, color: kTextSub)),
                if (amt > 0) Text('Claimed: ${Fmt.amount(amt)}',
                    style: const TextStyle(fontSize: 11, color: Colors.orange,
                        fontWeight: FontWeight.w700)),
                if (cp['resolution'] != null) Text(
                    'Resolution: ${cp["resolution"]}',
                    style: const TextStyle(fontSize: 10, color: Colors.green)),
                if (dt != null) Text(DateFormat('d MMM yyyy').format(dt.toLocal()),
                    style: const TextStyle(fontSize: 9, color: kTextHint)),
              ]));
        })),
  ]);

  // ─── HISTORY ─────────────────────────────────────────────────────────────
  Widget _tabHistory() => Column(children: [
    _dateRangeBar(),
    Expanded(child: _history.isEmpty
        ? const EmptyState(icon: Icons.history_outlined, message: 'No history')
        : ListView.separated(
        padding: const EdgeInsets.all(12), itemCount: _history.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (_, i) {
          final o      = _history[i];
          final birds  = (o['estimated_birds'] as num?)?.toInt() ?? 0;
          final kg     = (o['delivered_weight'] as num?)?.toDouble() ?? 0;
          final billed = (o['final_amount'] as num?)?.toDouble();
          final paid   = (o['collected_amount'] as num?)?.toDouble() ?? 0;
          final dt     = DateTime.tryParse(o['order_date'] as String? ?? '');
          final status = o['status'] as String? ?? '—';
          final inv    = o['invoice_number'] as String?;
          return GestureDetector(
              onTap: () => _showOrderDetail(o, historyRow: true),
              child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(color: kSurface,
                      borderRadius: BorderRadius.circular(kRadiusCard),
                      border: Border.all(color: kBorderLight), boxShadow: kCardShadow),
                  child: Row(children: [
                    Container(width: 40, height: 40,
                        decoration: BoxDecoration(color: kNavy.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(kRadiusChip)),
                        child: Center(child: Text(dt != null ? DateFormat('d').format(dt) : '—',
                            style: const TextStyle(fontWeight: FontWeight.w900, color: kPrimary)))),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${birds > 0 ? "$birds birds" : "${kg.toStringAsFixed(0)} kg"}'
                          '${inv != null ? "  |  $inv" : ""}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      Text('${dt != null ? DateFormat("d MMM yyyy").format(dt) : "—"}  |  '
                          '${status.toUpperCase().replaceAll("_", " ")}',
                          style: const TextStyle(fontSize: 10, color: kTextHint)),
                    ])),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      if (billed != null) Text(Fmt.amount(billed),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                      if (billed != null && paid < billed)
                        Text('Due: ${Fmt.amount(billed - paid)}',
                            style: const TextStyle(fontSize: 10, color: Colors.orange)),
                      GestureDetector(onTap: () => _showPlaceOrder(reorderFrom: o),
                          child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                  color: kNavy.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(kRadiusChip)),
                              child: const Text('Reorder',
                                  style: TextStyle(fontSize: 9, color: kNavy,
                                      fontWeight: FontWeight.w700)))),
                    ]),
                  ])));
        })),
  ]);

  // ─── PROFILE ─────────────────────────────────────────────────────────────
  Widget _tabProfile() {
    final r      = _dashboard?['retailer'] as Map<String,dynamic>?;
    final credit = _dashboard?['credit']   as Map<String,dynamic>?;
    final trader = _dashboard?['trader']   as Map<String,dynamic>?;
    if (r == null) return const EmptyState(icon: Icons.person_outlined, message: 'Loading...');

    final creditLimit = (credit?['credit_limit']    as num?)?.toDouble() ?? 0;
    final outstanding = (credit?['outstanding']      as num?)?.toDouble() ?? 0;
    final avail       = (credit?['available_credit'] as num?)?.toDouble() ?? 0;
    final usedPct     = creditLimit > 0 ? (outstanding/creditLimit).clamp(0.0,1.0) : 0.0;

    return SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Profile header card
          Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [kNavy, kNavyMid],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(kRadiusHero),
                  boxShadow: kCardShadow),
              child: Row(children: [
                CircleAvatar(radius: 28, backgroundColor: Colors.white.withValues(alpha: 0.15),
                    child: Text((r['shop_name'] as String? ?? 'S')[0].toUpperCase(),
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: kGoldLight))),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r['shop_name'] as String? ?? '—',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900,
                          color: Colors.white)),
                  if (r['owner_name'] != null)
                    Text(r['owner_name'] as String,
                        style: const TextStyle(fontSize: 12, color: Color(0xFFB4C6F4),
                            fontWeight: FontWeight.w600)),
                  if (r['phone'] != null)
                    Text(r['phone'] as String,
                        style: const TextStyle(fontSize: 11, color: Color(0xFFB4C6F4))),
                ])),
                IconButton(icon: const Icon(Icons.edit_outlined, color: kGoldLight, size: 20),
                    onPressed: () => _showEditProfile(r)),
              ])),
          const SizedBox(height: 12),

          // Credit card
          Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: kSurface,
                  borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
                  boxShadow: kCardShadow),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.credit_card_outlined, size: 16, color: Colors.blue),
                  SizedBox(width: 6),
                  Text('Credit Account', style: TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w800, color: Colors.blue)),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  _creditStat('Limit',     Fmt.amount(creditLimit), kTextMain),
                  _creditStat('Used',      Fmt.amount(outstanding),
                      outstanding > creditLimit * 0.8 ? Colors.red : Colors.orange),
                  _creditStat('Available', Fmt.amount(avail), Colors.green),
                ]),
                const SizedBox(height: 8),
                ClipRRect(borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: usedPct, minHeight: 8,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation(
                            usedPct > 0.8 ? Colors.red : usedPct > 0.5 ? Colors.orange : Colors.green))),
                const SizedBox(height: 4),
                Text('${(usedPct*100).toStringAsFixed(0)}% credit used',
                    style: const TextStyle(fontSize: 10, color: kTextHint)),
              ])),
          const SizedBox(height: 12),

          // Shop details
          Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: kSurface,
                  borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(color: kBorderLight), boxShadow: kCardShadow),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Shop Details',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                _detailRow(Icons.store_outlined, 'Type',
                    (r['retailer_type'] as String? ?? 'retail_shop').replaceAll('_',' ').toUpperCase()),
                _detailRow(Icons.location_on_outlined, 'Address',
                    [r['address'], r['city']].where((v) => v != null && v.toString().isNotEmpty).join(', ')),
                _detailRow(Icons.receipt_outlined, 'GST', r['gst_number'] as String? ?? 'Not provided'),
                _detailRow(Icons.access_time_outlined, 'Preferred Slot',
                    r['preferred_slot'] as String? ?? 'Any time'),
                _detailRow(Icons.payments_outlined, 'Payment',
                    (r['payment_pref'] as String? ?? 'credit').toUpperCase()),
              ])),
          const SizedBox(height: 12),

          // Supplier info
          if (trader != null) Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: kSurface,
                  borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(color: kBorderLight), boxShadow: kCardShadow),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.store_mall_directory_outlined, size: 16, color: kNavy),
                  SizedBox(width: 6),
                  Text('Your Supplier', style: TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w800, color: kNavy)),
                ]),
                const SizedBox(height: 10),
                _detailRow(Icons.business_outlined,    'Company', trader['company_name'] as String? ?? '—'),
                _detailRow(Icons.tag_outlined,          'Code',    trader['company_code'] as String? ?? '—'),
                if (trader['phone'] != null)
                  _detailRow(Icons.phone_outlined, 'Phone', trader['phone'] as String),
                if (trader['city'] != null)
                  _detailRow(Icons.location_city_outlined, 'City', trader['city'] as String),
              ])),
          const SizedBox(height: 12),

          // Actions
          _profileAction(Icons.lock_outline,  'Change Password', Colors.blue, _showChangePassword),
          const SizedBox(height: 8),
          _profileAction(Icons.logout, 'Sign Out', Colors.red, _signOut),
          const SizedBox(height: 30),
        ]));
  }

  // ─── DIALOGS ─────────────────────────────────────────────────────────────

  void _showPlaceOrder({Map<String,dynamic>? reorderFrom}) {
    final products = List<Map<String,dynamic>>.from(
        _dashboard?['products'] as List? ?? []);
    String? selectedProductId = reorderFrom?['product_id'] as String?
        ?? (products.isNotEmpty ? products.first['id'] as String? : null);
    final qtyCtrl  = TextEditingController(
        text: reorderFrom != null
            ? (reorderFrom['total_quantity'] as num?)?.toStringAsFixed(0) ?? '' : '');
    final noteCtrl = TextEditingController();
    String mode        = 'kg';
    String deliverySlot = 'today';   // 'today' or 'tomorrow'
    bool urgent        = false;

    showModalBottomSheet(
        context: context, useRootNavigator: true, isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Padding(padding: const EdgeInsets.all(20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    Expanded(child: Text(reorderFrom != null ? 'Reorder' : 'Place Order',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                    IconButton(icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx, rootNavigator: true).pop()),
                  ]),
                  const SizedBox(height: 8),
                  // Product selection
                  if (products.isEmpty) Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8)),
                      child: const Text('No products available. Contact your supplier.',
                          style: TextStyle(fontSize: 11, color: Colors.orange)))
                  else if (products.length == 1) Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: kPrimary.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8)),
                      child: Row(children: [
                        Text(products.first['name'] as String? ?? 'Broiler',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Text(products.first['rate'] != null
                            ? 'Rs.${(products.first["rate"] as num).toStringAsFixed(2)}/kg'
                            : 'Rate TBD',
                            style: TextStyle(color: products.first['rate'] != null
                                ? kPrimary : kTextHint, fontWeight: FontWeight.w700)),
                      ]))
                  else DropdownButtonFormField<String>(
                        initialValue: selectedProductId,
                        decoration: const InputDecoration(labelText: 'Product *', isDense: true),
                        items: products.map((p) => DropdownMenuItem(
                            value: p['id'] as String,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  fit: FlexFit.loose,
                                  child: Text(
                                    p['name'] as String? ?? '—',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  p['rate'] != null
                                      ? 'Rs.${(p["rate"] as num).toStringAsFixed(2)}/kg'
                                      : 'Rate TBD',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: p['rate'] != null ? kTextSub : kTextHint,
                                  ),
                                ),
                              ],
                            ))).toList(),
                        onChanged: (v) => ss(() => selectedProductId = v)),
                  const SizedBox(height: 10),
                  Row(children: [
                    const Text('Order by:', style: TextStyle(fontSize: 12, color: kTextSub)),
                    const SizedBox(width: 10),
                    SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'kg',    label: Text('Weight (kg)')),
                          ButtonSegment(value: 'birds', label: Text('Birds')),
                        ],
                        selected: {mode},
                        onSelectionChanged: (s) => ss(() => mode = s.first)),
                  ]),
                  const SizedBox(height: 10),
                  TextField(controller: qtyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: mode == 'kg' ? 'Quantity (kg) *' : 'Number of Birds *',
                          suffixText: mode == 'kg' ? 'kg' : 'birds')),
                  const SizedBox(height: 8),
                  TextField(controller: noteCtrl,
                      decoration: const InputDecoration(labelText: 'Instructions (optional)')),
                  const SizedBox(height: 8),
                  // Delivery date — Today / Tomorrow / Custom
                  Row(children: [
                    const Text('Delivery:', style: TextStyle(fontSize: 12, color: kTextSub)),
                    const SizedBox(width: 10),
                    Expanded(child: SegmentedButton<String>(
                        style: const ButtonStyle(visualDensity: VisualDensity.compact),
                        segments: const [
                          ButtonSegment(value: 'today',    label: Text('Today',    style: TextStyle(fontSize: 11))),
                          ButtonSegment(value: 'tomorrow', label: Text('Tomorrow', style: TextStyle(fontSize: 11))),
                        ],
                        selected: {deliverySlot},
                        onSelectionChanged: (s) => ss(() => deliverySlot = s.first))),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Checkbox(value: urgent, onChanged: (v) => ss(() => urgent = v ?? false)),
                    const Text('Urgent Order', style: TextStyle(fontSize: 12)),
                    if (urgent) const Text('  — Priority',
                        style: TextStyle(fontSize: 10, color: Colors.orange)),
                  ]),
                  const SizedBox(height: 14),
                  ElevatedButton(
                      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                      onPressed: () async {
                        final qty = double.tryParse(qtyCtrl.text.trim()) ?? 0;
                        if (qty <= 0) { showError(context, 'Enter quantity'); return; }
                        if (selectedProductId == null && products.isNotEmpty) {
                          selectedProductId = products.first['id'] as String;
                        }
                        Navigator.of(ctx, rootNavigator: true).pop();
                        try {
                          // ★ NEW (duplicate-order audit): warn, never block.
                          try {
                            final ret = await _c.from('retailers')
                                .select('trader_id').eq('id', _retailerId!).single();
                            final dup = await _c.rpc('check_duplicate_order', params: {
                              'p_trader_id': (ret)['trader_id'],
                              'p_retailer_id': _retailerId,
                              'p_product_id': selectedProductId,
                              'p_estimated_birds': mode == 'birds' ? qty.toInt() : 0,
                            });
                            final d = (dup as Map?)?.cast<String, dynamic>();
                            if (d?['is_duplicate'] == true) {
                              if (!mounted) return;
                              final proceed = await _showDuplicateOrderDialog(d!);
                              if (proceed != true) return;
                            }
                          } catch (_) {
                            // Pre-check failing should never block order creation.
                          }
                          final dDate = deliverySlot == 'tomorrow'
                              ? DateTime.now().add(const Duration(days: 1))
                              : DateTime.now();
                          await _c.rpc('retailer_place_order', params: {
                            'p_retailer_id':  _retailerId,
                            'p_product_id':   selectedProductId,
                            if (mode == 'kg')    'p_quantity_kg': qty,
                            if (mode == 'birds') 'p_birds':       qty.toInt(),
                            'p_delivery_date': '${dDate.year}-${dDate.month.toString().padLeft(2,"0")}-${dDate.day.toString().padLeft(2,"0")}',
                            'p_notes':    noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                            'p_is_urgent': urgent,
                          });
                          _load();
                          if (mounted) showSuccess(context, 'Order placed!');
                        } catch (e) {
                          if (mounted) showError(context, e.toString().replaceAll('Exception: ',''));
                        }
                      },
                      child: const Text('Confirm Order')),
                ])))));
  }

  // ★ NEW: Possible-duplicate confirmation dialog — never blocks, just warns.
  Future<bool?> _showDuplicateOrderDialog(Map<String, dynamic> d) {
    final createdAt = DateTime.tryParse(d['created_at'] as String? ?? '');
    final timeStr = createdAt != null
        ? DateFormat('dd MMM, hh:mm a').format(createdAt.toLocal())
        : '—';
    return showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusCard)),
        title: const Row(children: [
          Icon(Icons.info_outline, color: Colors.orange, size: 20),
          SizedBox(width: 8),
          Text('Possible Duplicate Order', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('A similar order was created recently.',
                style: TextStyle(fontSize: 13, color: kTextSub, height: 1.4)),
            const SizedBox(height: 12),
            _dupRow('Order No', '${d['order_no']}'),
            _dupRow('Retailer', '${d['retailer_name']}'),
            _dupRow('Time', timeStr),
            _dupRow('Product(s)', (d['products'] as String? ?? '').isEmpty ? '—' : '${d['products']}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c, rootNavigator: true).pop(false),
            child: const Text('Cancel', style: TextStyle(color: kTextSub, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.of(c, rootNavigator: true).pop(true),
            child: const Text('Create New Order', style: TextStyle(color: kNavy, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _dupRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 12, color: kTextHint))),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
    ]),
  );

  // ─── ORDER DETAIL ────────────────────────────────────────────────────────
  // Shown on tap from both Orders and History rows. Fetches the order's
  // latest invoice + its delivery directly (RLS already scopes both to
  // this retailer's own rows — same trust boundary Order/History already
  // rely on), rather than re-deriving anything client-side. Reorder stays
  // available here too, same _showPlaceOrder(reorderFrom:) call the row
  // itself already uses.
  Future<void> _showOrderDetail(Map<String,dynamic> order, {bool historyRow = false}) async {
    final orderId = order['id'] as String?;
    if (orderId == null) return;
    Map<String,dynamic>? invoice;
    Map<String,dynamic>? delivery;
    try {
      final results = await Future.wait([
        _c.from('invoices')
            .select('id,invoice_number,invoice_date,total_amount,collected_amount,'
            'balance_amount,status,corrected_from_invoice_id')
            .eq('order_id', orderId)
            .order('created_at', ascending: false).limit(1).maybeSingle(),
        _c.from('deliveries')
            .select('status,delivered_at,delivered_bird_count,delivered_total_weight')
            .eq('order_id', orderId)
            .order('created_at', ascending: false).limit(1).maybeSingle(),
      ]);
      invoice  = results[0];
      delivery = results[1];
    } catch (_) {
      // Non-fatal — order/delivery/invoice may simply not exist yet.
    }
    if (!mounted) return;

    final birds  = (order['estimated_birds'] as num?)?.toInt() ?? 0;
    final qty    = (order['total_quantity'] as num?)?.toDouble() ?? 0;
    final notes  = (order['notes'] as String?) ?? '';
    final status = order['status'] as String? ?? '—';

    await showModalBottomSheet(
        context: context, useRootNavigator: true, isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => DraggableScrollableSheet(expand: false,
            initialChildSize: 0.7, maxChildSize: 0.92,
            builder: (_, scrollCtrl) => SingleChildScrollView(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Expanded(child: Text('Order Details',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                    IconButton(icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx, rootNavigator: true).pop()),
                  ]),
                  _detailRow(Icons.shopping_bag_outlined, 'Quantity',
                      birds > 0 ? '$birds birds' : '${qty.toStringAsFixed(0)} kg'),
                  _detailRow(Icons.flag_outlined, 'Status', status.toUpperCase().replaceAll('_',' ')),
                  if (notes.isNotEmpty) _detailRow(Icons.notes_outlined, 'Remarks', notes),
                  const SizedBox(height: 10),
                  // Delivery timeline/status — same deliveries row the
                  // trader side already reads, RLS already scopes it to
                  // this retailer.
                  if (delivery != null) ...[
                    const Divider(height: 20),
                    const Text('DELIVERY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: kNavy, letterSpacing: 0.6)),
                    const SizedBox(height: 8),
                    _detailRow(Icons.local_shipping_outlined, 'Delivery Status',
                        ((delivery['status'] as String?) ?? '—').toUpperCase().replaceAll('_',' ')),
                    if (delivery['delivered_at'] != null)
                      _detailRow(Icons.event_available_outlined, 'Delivered',
                          DateFormat('d MMM yyyy, hh:mm a').format(
                              DateTime.tryParse(delivery['delivered_at'] as String)?.toLocal() ?? DateTime.now())),
                    if (delivery['delivered_bird_count'] != null || delivery['delivered_total_weight'] != null)
                      _detailRow(Icons.scale_outlined, 'Delivered Qty',
                          '${(delivery['delivered_bird_count'] as num?)?.toInt() ?? 0} birds · '
                              '${((delivery['delivered_total_weight'] as num?)?.toDouble() ?? 0).toStringAsFixed(1)} kg'),
                  ],
                  // Invoice linkage — business date, payment status,
                  // corrected-invoice reference, and a way through to the
                  // full invoice (products/rate/payment status), reusing
                  // get_invoice_detail via RetailerInvoiceDetailScreen —
                  // no separate invoice-rendering logic here.
                  if (invoice != null) ...[
                    const Divider(height: 20),
                    const Text('INVOICE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: kNavy, letterSpacing: 0.6)),
                    const SizedBox(height: 8),
                    _detailRow(Icons.receipt_outlined, 'Invoice No', invoice['invoice_number'] as String? ?? '—'),
                    if (invoice['invoice_date'] != null)
                      _detailRow(Icons.calendar_today_outlined, 'Business Date',
                          DateFormat('d MMM yyyy').format(DateTime.parse(invoice['invoice_date'] as String))),
                    _detailRow(Icons.payments_outlined, 'Payment Status',
                        ((invoice['balance_amount'] as num?) ?? 0) > 0 ? 'Outstanding' : 'Paid'),
                    _detailRow(Icons.currency_rupee, 'Amount', Fmt.amount((invoice['total_amount'] as num?)?.toDouble() ?? 0)),
                    if (invoice['corrected_from_invoice_id'] != null)
                      Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(kRadiusCard),
                              border: Border.all(color: Colors.amber.withValues(alpha: 0.3))),
                          child: const Row(children: [
                            Icon(Icons.info_outline, size: 14, color: Colors.brown),
                            SizedBox(width: 8),
                            Expanded(child: Text(
                                'This invoice was corrected from an earlier version — the amount shown here is the current, corrected one.',
                                style: TextStyle(fontSize: 11, color: Colors.brown))),
                          ])),
                    const SizedBox(height: 10),
                    SizedBox(width: double.infinity, height: 44, child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(ctx, rootNavigator: true).pop();
                          Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => RetailerInvoiceDetailScreen(invoiceId: invoice!['id'] as String)));
                        },
                        icon: const Icon(Icons.description_outlined, size: 16),
                        label: const Text('View Full Invoice'))),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(width: double.infinity, height: 46, child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(ctx, rootNavigator: true).pop();
                        _showPlaceOrder(reorderFrom: order);
                      },
                      icon: const Icon(Icons.replay_outlined, size: 16),
                      label: const Text('Reorder'),
                      style: ElevatedButton.styleFrom(backgroundColor: kNavy))),
                  const SizedBox(height: 20),
                ]))));
  }

  Future<void> _cancelOrder(String orderId, String status) async {
    final ok = await confirmDialog(context,
        title: 'Cancel Order',
        message: 'Are you sure you want to cancel this order? '
            'You can only cancel before the order is picked up.',
        confirmText: 'Yes, Cancel');
    if (!ok || !mounted) return;
    try {
      await _c.rpc('cancel_retailer_order', params: {
        'p_order_id':    orderId,
        'p_retailer_id': _retailerId,
        'p_reason':      'Cancelled by retailer',
      });
      _load();
      if (mounted) showSuccess(context, 'Order cancelled.');
    } catch (e) {
      if (mounted) {
        showError(context,
          e.toString().replaceAll('Exception: ','').replaceAll('PostgrestException: ',''));
      }
    }
  }

  void _showPayment() {
    final amtCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    String mode   = 'cash';
    final due     = ((_dashboard?['financials']?['outstanding']) as num?)?.toDouble() ?? 0;

    showModalBottomSheet(
        context: context, useRootNavigator: true, isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Padding(padding: const EdgeInsets.all(20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    const Expanded(child: Text('Record Payment',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                    IconButton(icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx, rootNavigator: true).pop()),
                  ]),
                  if (due > 0) Text('Outstanding: ${Fmt.amount(due)}',
                      style: const TextStyle(fontSize: 12, color: Colors.orange,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Row(children: ['cash','upi','bank','cheque'].map((m) => Expanded(
                      child: GestureDetector(onTap: () => ss(() => mode = m),
                          child: Container(margin: const EdgeInsets.only(right: 4),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                  color: mode == m ? kPrimary : Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: mode == m ? kPrimary : kBorder)),
                              child: Text(m.toUpperCase(), textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                                      color: mode == m ? Colors.white : kTextSub)))))).toList()),
                  const SizedBox(height: 12),
                  TextField(controller: amtCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onTap: () {
                        if (amtCtrl.text.isEmpty && due > 0) {
                          amtCtrl.text = due.toStringAsFixed(2);
                          amtCtrl.selection = TextSelection(
                              baseOffset: 0, extentOffset: amtCtrl.text.length);
                        }
                      },
                      decoration: InputDecoration(labelText: 'Amount *',
                          prefixText: 'Rs.', hintText: due.toStringAsFixed(0))),
                  if (mode != 'cash') ...[
                    const SizedBox(height: 8),
                    TextField(controller: refCtrl,
                        decoration: const InputDecoration(labelText: 'Reference / UTR')),
                  ],
                  const SizedBox(height: 14),
                  ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green,
                          minimumSize: const Size(double.infinity, 48)),
                      onPressed: () async {
                        final amt = double.tryParse(amtCtrl.text.trim()) ?? 0;
                        if (amt <= 0) { showError(context, 'Enter amount'); return; }
                        Navigator.of(ctx, rootNavigator: true).pop();
                        try {
                          final ret = await _c.from('retailers')
                              .select('trader_id').eq('id', _retailerId!).single();
                          await _c.from('retailer_payments').insert({
                            'trader_id':    (ret as Map)['trader_id'],
                            'retailer_id':  _retailerId,
                            'amount':       amt,
                            'payment_mode': mode,
                            'reference_number': refCtrl.text.trim().isEmpty
                                ? null : refCtrl.text.trim(),
                          });
                          _load();
                          if (mounted) showSuccess(context, 'Payment recorded!');
                        } catch (e) {
                          if (mounted) showError(context, e.toString().replaceAll('Exception: ',''));
                        }
                      },
                      child: const Text('Submit Payment')),
                ])))));
  }

  void _showRaiseComplaint() {
    String type    = 'weight_issue';
    final descCtrl = TextEditingController();
    final amtCtrl  = TextEditingController();
    showModalBottomSheet(
        context: context, useRootNavigator: true, isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Padding(padding: const EdgeInsets.all(20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    const Expanded(child: Text('Raise Complaint',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                    IconButton(icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx, rootNavigator: true).pop()),
                  ]),
                  DropdownButtonFormField<String>(initialValue: type,
                      decoration: const InputDecoration(labelText: 'Type', isDense: true),
                      items: const [
                        DropdownMenuItem(value: 'weight_issue',  child: Text('Weight Issue')),
                        DropdownMenuItem(value: 'mortality',     child: Text('Mortality')),
                        DropdownMenuItem(value: 'missing_qty',   child: Text('Missing Quantity')),
                        DropdownMenuItem(value: 'quality',       child: Text('Quality Issue')),
                        DropdownMenuItem(value: 'rate_dispute',  child: Text('Rate Dispute')),
                        DropdownMenuItem(value: 'other',         child: Text('Other')),
                      ],
                      onChanged: (v) => ss(() => type = v ?? type)),
                  const SizedBox(height: 8),
                  TextField(controller: descCtrl, maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Description *',
                          hintText: 'Describe the issue...')),
                  const SizedBox(height: 8),
                  TextField(controller: amtCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Claim Amount (optional)',
                          prefixText: 'Rs.')),
                  const SizedBox(height: 14),
                  ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange,
                          minimumSize: const Size(double.infinity, 48)),
                      onPressed: () async {
                        if (descCtrl.text.trim().isEmpty) {
                          showError(context, 'Describe the issue'); return;
                        }
                        Navigator.of(ctx, rootNavigator: true).pop();
                        try {
                          final ret = await _c.from('retailers')
                              .select('trader_id').eq('id', _retailerId!).single();
                          await _c.from('retailer_complaints').insert({
                            'trader_id':      (ret as Map)['trader_id'],
                            'retailer_id':    _retailerId,
                            'complaint_type': type,
                            'description':    descCtrl.text.trim(),
                            'claimed_amount': double.tryParse(amtCtrl.text.trim()) ?? 0,
                          });
                          _tab.animateTo(3); _load();
                          if (mounted) showSuccess(context, 'Complaint raised.');
                        } catch (e) {
                          if (mounted) showError(context, e.toString().replaceAll('Exception: ',''));
                        }
                      },
                      child: const Text('Submit Complaint')),
                ])))));
  }

  void _showEditProfile(Map<String,dynamic> r) {
    final shopCtrl    = TextEditingController(text: r['shop_name']  as String? ?? '');
    final ownerCtrl   = TextEditingController(text: r['owner_name'] as String? ?? '');
    final addressCtrl = TextEditingController(text: r['address']    as String? ?? '');
    final cityCtrl    = TextEditingController(text: r['city']       as String? ?? '');
    final gstCtrl     = TextEditingController(text: r['gst_number'] as String? ?? '');
    showModalBottomSheet(
        context: context, useRootNavigator: true, isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Padding(padding: const EdgeInsets.all(20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    const Expanded(child: Text('Edit Profile',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                    IconButton(icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx, rootNavigator: true).pop()),
                  ]),
                  TextField(controller: shopCtrl,
                      decoration: const InputDecoration(labelText: 'Shop Name *', isDense: true)),
                  const SizedBox(height: 8),
                  TextField(controller: ownerCtrl,
                      decoration: const InputDecoration(labelText: 'Owner Name', isDense: true)),
                  const SizedBox(height: 8),
                  TextField(controller: addressCtrl,
                      decoration: const InputDecoration(labelText: 'Address', isDense: true)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: TextField(controller: cityCtrl,
                        decoration: const InputDecoration(labelText: 'City', isDense: true))),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(controller: gstCtrl,
                        decoration: const InputDecoration(labelText: 'GST Number', isDense: true))),
                  ]),
                  const SizedBox(height: 16),
                  ElevatedButton(
                      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                      onPressed: () async {
                        if (shopCtrl.text.trim().isEmpty) {
                          showError(context, 'Shop name required'); return;
                        }
                        Navigator.of(ctx, rootNavigator: true).pop();
                        try {
                          await _c.rpc('update_retailer_profile', params: {
                            'p_retailer_id': _retailerId,
                            'p_shop_name':   shopCtrl.text.trim(),
                            'p_owner_name':  ownerCtrl.text.trim().isEmpty ? null : ownerCtrl.text.trim(),
                            'p_address':     addressCtrl.text.trim().isEmpty ? null : addressCtrl.text.trim(),
                            'p_city':        cityCtrl.text.trim().isEmpty ? null : cityCtrl.text.trim(),
                            'p_gst_number':  gstCtrl.text.trim().isEmpty ? null : gstCtrl.text.trim(),
                          });
                          _load();
                          if (mounted) showSuccess(context, 'Profile updated!');
                        } catch (e) {
                          if (mounted) showError(context, e.toString().replaceAll('Exception: ',''));
                        }
                      },
                      child: const Text('Save Changes')),
                ]))));
  }

  void _showChangePassword() {
    final newCtrl     = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool busy = false;
    showModalBottomSheet(
        context: context, useRootNavigator: true, isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Padding(padding: const EdgeInsets.all(20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    const Expanded(child: Text('Change Password',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                    IconButton(icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx, rootNavigator: true).pop()),
                  ]),
                  const SizedBox(height: 8),
                  TextField(controller: newCtrl, obscureText: true,
                      decoration: const InputDecoration(labelText: 'New Password *',
                          hintText: 'Min 6 characters', isDense: true)),
                  const SizedBox(height: 8),
                  TextField(controller: confirmCtrl, obscureText: true,
                      decoration: const InputDecoration(
                          labelText: 'Confirm New Password *', isDense: true)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                      onPressed: busy ? null : () async {
                        final np = newCtrl.text.trim(); final cp = confirmCtrl.text.trim();
                        if (np.length < 6) { showError(context, 'Min 6 characters'); return; }
                        if (np != cp) { showError(context, 'Passwords do not match'); return; }
                        ss(() => busy = true);
                        try {
                          await _c.auth.updateUser(UserAttributes(password: np));
                          Navigator.of(ctx, rootNavigator: true).pop();
                          if (mounted) showSuccess(context, 'Password changed!');
                        } on AuthException catch (e) {
                          ss(() => busy = false);
                          if (mounted) showError(context, e.message);
                        } catch (e) {
                          ss(() => busy = false);
                          if (mounted) showError(context, e.toString().replaceAll('Exception: ',''));
                        }
                      },
                      child: busy
                          ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Update Password')),
                ])))));
  }

  void _showNotifications() {
    showModalBottomSheet(
        context: context, useRootNavigator: true, isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => FutureBuilder(
            future: _c.from('retailer_notifications')
                .select('id,type,title,body,is_read,created_at')
                .eq('retailer_id', _retailerId ?? '')
                .order('created_at', ascending: false).limit(20),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const SizedBox(height: 120, child: LoadingList());
              }
              final notifs = List<Map<String,dynamic>>.from(snap.data as List? ?? []);
              if (notifs.any((n) => n['is_read'] == false)) {
                _c.from('retailer_notifications').update({'is_read': true})
                    .eq('retailer_id', _retailerId ?? '').eq('is_read', false);
              }
              return DraggableScrollableSheet(expand: false,
                  initialChildSize: 0.6, maxChildSize: 0.9,
                  builder: (_, ctrl) => Column(children: [
                    const Padding(padding: EdgeInsets.all(16),
                        child: Text('Notifications',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                    const Divider(height: 1),
                    Expanded(child: notifs.isEmpty
                        ? const EmptyState(icon: Icons.notifications_none_outlined,
                        message: 'No notifications')
                        : ListView.separated(controller: ctrl,
                        padding: const EdgeInsets.all(12),
                        itemCount: notifs.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final n      = notifs[i];
                          final unread = n['is_read'] == false;
                          final dt     = DateTime.tryParse(n['created_at'] as String? ?? '');
                          return ListTile(dense: true,
                              tileColor: unread ? kPrimary.withValues(alpha: 0.04) : null,
                              leading: Icon(_notifIcon(n['type'] as String? ?? ''),
                                  color: kPrimary, size: 20),
                              title: Text(n['title'] as String? ?? '—',
                                  style: TextStyle(fontSize: 12,
                                      fontWeight: unread ? FontWeight.w800 : FontWeight.normal)),
                              subtitle: Text(n['body'] as String? ?? '',
                                  style: const TextStyle(fontSize: 10)),
                              trailing: dt != null
                                  ? Text(DateFormat('d MMM HH:mm').format(dt.toLocal()),
                                  style: const TextStyle(fontSize: 9, color: kTextHint))
                                  : null);
                        })),
                  ]));
            }));
  }

  Future<void> _signOut() async {
    final ok = await confirmDialog(context,
        title: 'Sign Out',
        message: 'Are you sure you want to sign out?',
        confirmText: 'Sign Out');
    if (!ok || !mounted) return;
    await _c.auth.signOut();
    if (mounted) context.go(R.login);
  }

  // ─── HELPERS ─────────────────────────────────────────────────────────────
  Widget _kpiCard(String l, String v, Color c, IconData icon) =>
      Expanded(child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: kSurface,
              borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: c.withValues(alpha: 0.2)),
              boxShadow: kCardShadow),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 30, height: 30,
                decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(kRadiusInner)),
                child: Icon(icon, size: 16, color: c)),
            const SizedBox(height: 6),
            Text(v, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: c)),
            Text(l, style: const TextStyle(fontSize: 9, color: kTextHint, fontWeight: FontWeight.w600)),
          ])));

  Widget _quickAction(String l, IconData icon, Color c, VoidCallback onTap) =>
      Expanded(child: GestureDetector(onTap: onTap,
          child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: c.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(color: c.withValues(alpha: 0.15)),
                  boxShadow: kCardShadow),
              child: Column(children: [
                Container(width: 36, height: 36,
                    decoration: BoxDecoration(color: kSurface,
                        borderRadius: BorderRadius.circular(kRadiusChip),
                        boxShadow: [BoxShadow(color: c.withValues(alpha: 0.15),
                            blurRadius: 6, offset: const Offset(0,2))]),
                    child: Icon(icon, size: 20, color: c)),
                const SizedBox(height: 6),
                Text(l, textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: c)),
              ]))));

  Widget _sectionTitle(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(16,14,16,8),
      child: Text(t.toUpperCase(), style: const TextStyle(fontSize: 10,
          fontWeight: FontWeight.w900, color: kNavy, letterSpacing: 0.6)));

  Widget _dateRangeBar() => Container(
      color: kSurface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: GestureDetector(onTap: _pickDateRange,
          child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: kNavy.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: kNavy.withValues(alpha: 0.15))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.calendar_today_outlined, size: 14, color: kNavy),
                const SizedBox(width: 6),
                Text('${DateFormat("d MMM").format(_from)} – ${DateFormat("d MMM").format(_to)}',
                    style: const TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w800, color: kNavy)),
                const SizedBox(width: 6),
                const Text('Change', style: TextStyle(fontSize: 10, color: kNavy,
                    fontWeight: FontWeight.w600)),
              ]))));

  Widget _oStat(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c),
        textAlign: TextAlign.center),
    Text(l, style: const TextStyle(fontSize: 8, color: kTextHint), textAlign: TextAlign.center),
  ]));

  Widget _lStat(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white),
        textAlign: TextAlign.center),
    Text(l, style: const TextStyle(fontSize: 9, color: Color(0xFFB4C6F4),
        fontWeight: FontWeight.w700), textAlign: TextAlign.center),
  ]));

  Widget _creditStat(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c),
        textAlign: TextAlign.center),
    Text(l, style: const TextStyle(fontSize: 9, color: kTextHint), textAlign: TextAlign.center),
  ]));

  Widget _detailRow(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(icon, size: 14, color: kTextHint), const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(fontSize: 11, color: kTextHint)),
        Expanded(child: Text(value.isEmpty ? '—' : value,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
      ]));

  Widget _profileAction(IconData icon, String label, Color c, VoidCallback onTap) =>
      GestureDetector(onTap: onTap,
          child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: kSurface,
                  borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(color: c.withValues(alpha: 0.25)),
                  boxShadow: kCardShadow),
              child: Row(children: [
                Container(width: 36, height: 36,
                    decoration: BoxDecoration(color: c.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(kRadiusChip)),
                    child: Icon(icon, size: 18, color: c)),
                const SizedBox(width: 14),
                Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: c)),
                const Spacer(),
                Icon(Icons.chevron_right_rounded, size: 18, color: c),
              ])));

  Future<void> _pickDateRange() async {
    final r = await showDateRangePicker(context: context,
        firstDate: DateTime(2024), lastDate: DateTime.now(),
        initialDateRange: DateTimeRange(start: _from, end: _to));
    if (r != null && mounted) {
      setState(() { _from = r.start; _to = r.end; });
      _load();
    }
  }

  Color _statusColor(String s) => switch (s) {
    'pending'          => Colors.orange,
    'confirmed'        => Colors.blue,
    'picked_up'        => Colors.indigo,
    'out_for_delivery' => Colors.purple,
    'delivered'        => Colors.green,
    'approved'         => Colors.teal,
    'invoiced'         => kPrimary,
    'closed'           => Colors.grey,
    'cancelled'        => Colors.red,
    _                  => kTextHint,
  };

  IconData _notifIcon(String type) => switch (type) {
    'order_confirmed'      => Icons.check_circle_outline,
    'order_dispatched'     => Icons.local_shipping_outlined,
    'order_delivered'      => Icons.done_all_outlined,
    'payment_due'          => Icons.payment_outlined,
    'invoice_ready'        => Icons.receipt_outlined,
    'outstanding_reminder' => Icons.account_balance_wallet_outlined,
    'complaint_update'     => Icons.report_problem_outlined,
    _                      => Icons.notifications_outlined,
  };
}