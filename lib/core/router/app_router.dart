import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/app_user.dart';
import '../providers/session_provider.dart';
import '../../features/splash_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/agent_link_screen.dart';
import '../../features/trader_admin/dashboard/trader_shell.dart';
import '../../features/trader_admin/dashboard/dashboard_screen.dart';
import '../../features/trader_admin/orders/orders_screen.dart';
import '../../features/trader_admin/orders/create_order_screen.dart';
import '../../features/trader_admin/orders/order_detail_screen.dart';
import '../../features/trader_admin/dispatch/dispatch_screen.dart';
import '../../features/trader_admin/dispatch/batch_detail_screen.dart';
import '../../features/trader_admin/approvals/approvals_screen.dart';
import '../../features/trader_admin/approvals/approval_detail_screen.dart';
import '../../features/trader_admin/invoices/invoices_screen.dart';
import '../../features/trader_admin/invoices/invoice_detail_screen.dart';
import '../../features/trader_admin/ledger/ledger_screen.dart';
import '../../features/trader_admin/ledger/retailer_ledger_screen.dart';
import '../../features/trader_admin/retailers/retailers_screen.dart';
import '../../features/trader_admin/retailers/create_retailer_screen.dart';
import '../../features/trader_admin/retailers/retailer_detail_screen.dart';
import '../../features/trader_admin/agents/agents_screen.dart';
import '../../features/trader_admin/agents/create_agent_screen.dart';
import '../../features/trader_admin/agents/agent_detail_screen.dart';
import '../../features/trader_admin/rates/rates_screen.dart';
import '../../features/trader_admin/shifts/shifts_screen.dart';
import '../../features/trader_admin/shifts/shift_detail_screen.dart';
import '../../features/trader_admin/crates/crates_screen.dart';
import '../../features/trader_admin/analytics/analytics_screen.dart';
import '../../features/trader_admin/settings/settings_screen.dart';
import '../../features/trader_admin/settings/user_management_screen.dart';
import '../../features/trader_admin/returns/returns_screen.dart';
import '../../features/trader_admin/stock/stock_screen.dart';
import '../../features/trader_admin/pricing/pricing_rules_screen.dart';
import '../../features/trader_admin/reconciliation/cash_reconciliation_screen.dart';
import '../../features/trader_admin/day_closure/day_closure_screen.dart';
import '../../features/trader_admin/alerts/alerts_screen.dart';
import '../../features/trader_admin/reports/daily_report_screen.dart';
import '../../features/delivery_agent/home/agent_shell.dart';
import '../../features/auth/trader_setup_screen.dart';
import '../../features/delivery_agent/batch/dc_view_screen.dart';
import '../../features/delivery_agent/orders/instant_order_screen.dart';
import '../../features/super_admin/dashboard/super_dashboard_screen.dart';
import '../../features/super_admin/traders/traders_list_sa_screen.dart';
import '../../features/super_admin/traders/trader_detail_sa_screen.dart';
import '../../features/super_admin/products/products_sa_screen.dart';
import '../../features/super_admin/plans/plans_sa_screen.dart';
import '../../features/auth/pending_approval_screen.dart';
import '../../features/delivery_agent/batch/bird_transfer_screen.dart';
import '../../features/delivery_agent/batch/transfer_history_screen.dart';
import '../../features/delivery_agent/home/agent_home_screen.dart';
import '../../features/delivery_agent/shift/shift_open_screen.dart';
import '../../features/delivery_agent/shift/shift_close_screen.dart';
import '../../features/delivery_agent/batch/batch_pickup_screen.dart';
import '../../features/delivery_agent/deliveries/agent_deliveries_screen.dart';
import '../../features/delivery_agent/deliveries/delivery_complete_screen.dart';
import '../../features/delivery_agent/expenses/expenses_screen.dart';
import '../../features/delivery_agent/deliveries/delivery_history_screen.dart';

abstract class R {
  static const splash         = '/';
  static const login          = '/login';
  static const agentLink      = '/agent-link';
  static const traderSetup       = '/trader-setup';
  static const pendingApproval   = '/pending-approval';
  static const superAdmin        = '/super-admin';
  static const saDashboard       = '/sa/dashboard';
  static const saTraders         = '/sa/traders';
  static const saProducts        = '/sa/products';
  static const saPlans           = '/sa/plans';
  static String saTraderDetail(String id) => '/sa/traders/$id';
  static const instantOrder   = '/a/instant-order'; // accessible even when signed in
  static const dashboard      = '/t/dashboard';
  static const orders         = '/t/orders';
  static const orderCreate    = '/t/orders/create';
  static const orderDetail    = '/t/orders/:id';
  static const dispatch       = '/t/dispatch';
  static const batchDetail    = '/t/dispatch/batch/:id';
  static const approvals      = '/t/approvals';
  static const approvalDetail = '/t/approvals/:id';
  static const invoices       = '/t/invoices';
  static const invoiceDetail  = '/t/invoices/:id';
  static const ledger         = '/t/ledger';
  static const retailerLedger = '/t/ledger/:rid';
  static const retailers      = '/t/retailers';
  static const retailerCreate = '/t/retailers/create';
  static const retailerDetail = '/t/retailers/:id';
  static const agents         = '/t/agents';
  static const agentCreate    = '/t/agents/create';
  static const agentDetail    = '/t/agents/:id';
  static const rates          = '/t/rates';
  static const shifts         = '/t/shifts';
  static const shiftDetail    = '/t/shifts/:id';
  static const crates         = '/t/crates';
  static const analytics      = '/t/analytics';
  static const settings       = '/t/settings';
  static const returns        = '/t/returns';
  static const stock          = '/t/stock';
  static const pricing        = '/t/pricing';
  static const cashRecon      = '/t/reconciliation';
  static const dayClosure     = '/t/day-closure';
  static const alerts         = '/t/alerts';
  static const dailyReport    = '/t/reports/daily';
  static const agentHome      = '/a/home';
  static const shiftOpen      = '/a/shift/open';
  static const shiftClose     = '/a/shift/close';
  static const batchPickup    = '/a/batch/:id/pickup';
  static const dcView          = '/a/batch/:id/dc';
  static const birdTransfer    = '/a/batch/:id/transfer';
  static const transferHistory = '/a/transfers';
  static const agentDeliveries = '/a/deliveries';
  static const deliveryDone   = '/a/delivery/:id/complete';
  static const agentExpenses  = '/a/expenses';
  static const userMgmt        = '/t/user-management';
  static const deliveryHistory = '/a/delivery-history/:id';
  static String deliveryHistoryPath(String id) => '/a/delivery-history/\$id';

  static String orderDetailPath(String id)     => '/t/orders/$id';
  static String batchDetailPath(String id)     => '/t/dispatch/batch/$id';
  static String approvalDetailPath(String id)  => '/t/approvals/$id';
  static String invoiceDetailPath(String id)   => '/t/invoices/$id';
  static String retailerLedgerPath(String id)  => '/t/ledger/$id';
  static String retailerDetailPath(String id)  => '/t/retailers/$id';
  static String agentDetailPath(String id)     => '/t/agents/$id';
  static String shiftDetailPath(String id)     => '/t/shifts/$id';
  static String batchPickupPath(String id)     => '/a/batch/$id/pickup';
  static String dcViewPath(String id)          => '/a/batch/$id/dc';
  static String birdTransferPath(String id)    => '/a/batch/$id/transfer';
  static String deliveryDonePath(String id)    => '/a/delivery/$id/complete';
}

final appRouterProvider = Provider<GoRouter>((ref) => GoRouter(
  initialLocation: R.splash,
  refreshListenable: _Refresh(ref),
  redirect: (ctx, state) {
    final async = ref.read(appUserProvider);

    // While loading session — don't redirect, show splash
    if (async.isLoading) return null;

    final user = async.valueOrNull;
    final loc  = state.matchedLocation;

    // ── Not signed in ─────────────────────────────────────────────
    if (user == null) {
      // Allow login and agent-link when signed out
      if (loc == R.splash || loc == R.login || loc == R.agentLink) return null;
      return R.login;
    }

    // ── Signed in ─────────────────────────────────────────────────

    // IMPORTANT FIX: /agent-link is allowed even when signed in
    // An agent may be signed in but not yet linked — let them link!
    if (loc == R.agentLink) return null;

    // Super admin → super admin screen
    // Unlinked → trader setup
    // Super admin: redirect to SA dashboard
    if (user.isSuperAdmin || user.role == UserRole.superAdmin) {
      if (loc.startsWith('/sa/') || loc == R.saDashboard || loc == R.superAdmin) return null;
      return R.saDashboard;
    }

    if (user.isUnlinked) {
      if (loc == R.traderSetup || loc == R.agentLink) return null;
      return R.traderSetup;
    }

    // Trader pending approval or suspended
    if (user.isTraderAdmin && (user.isPendingApproval || user.isSuspended)) {
      if (loc == R.pendingApproval) return null;
      return R.pendingApproval;
    }

    // Redirect away from login if already signed in
    if (loc == R.login) {
      return user.isDeliveryAgent ? R.agentHome : R.dashboard;
    }

    // Keep delivery agents in /a/* routes
    if (user.isDeliveryAgent && !loc.startsWith('/a/')) return R.agentHome;

    // Keep trader admin in /t/* routes
    if (!user.isDeliveryAgent && loc.startsWith('/a/')) return R.dashboard;

    return null;
  },
  routes: [
    GoRoute(path: R.splash,          builder: (_, __) => const SplashScreen()),
    GoRoute(path: R.login,           builder: (_, __) => const LoginScreen()),
    GoRoute(path: R.agentLink,       builder: (_, __) => const AgentLinkScreen()),
    GoRoute(path: R.traderSetup,     builder: (_, __) => const TraderSetupScreen()),
    GoRoute(path: R.pendingApproval, builder: (_, __) => const PendingApprovalScreen()),
    GoRoute(path: R.superAdmin,      builder: (_, __) => const SuperDashboardScreen()),
    GoRoute(path: R.saDashboard,      builder: (_, __) => const SuperDashboardScreen()),
    GoRoute(path: R.saTraders,        builder: (_, __) => const TradersListSaScreen()),
    GoRoute(path: R.saProducts,       builder: (_, __) => const ProductsSaScreen()),
    GoRoute(path: R.saPlans,          builder: (_, __) => const PlansSaScreen()),
    GoRoute(path: '/sa/traders/:id',  builder: (_, s)  =>
        TraderDetailSaScreen(traderId: s.pathParameters['id']!)),

    // ── Trader Admin Shell ──────────────────────────────────────
    ShellRoute(
      builder: (_, __, child) => TraderShell(child: child),
      routes: [
        GoRoute(path: R.dashboard,      builder: (_, __) => const DashboardScreen()),
        GoRoute(path: R.orders,         builder: (_, __) => const OrdersScreen()),
        GoRoute(path: R.orderCreate,    builder: (_, __) => const CreateOrderScreen()),
        GoRoute(path: R.orderDetail,    builder: (_, s)  => OrderDetailScreen(id: s.pathParameters['id']!)),
        GoRoute(path: R.dispatch,       builder: (_, __) => const DispatchScreen()),
        GoRoute(path: R.batchDetail,    builder: (_, s)  => BatchDetailScreen(id: s.pathParameters['id']!)),
        GoRoute(path: R.approvals,      builder: (_, __) => const ApprovalsScreen()),
        GoRoute(path: R.approvalDetail, builder: (_, s)  => ApprovalDetailScreen(id: s.pathParameters['id']!)),
        GoRoute(path: R.invoices,       builder: (_, __) => const InvoicesScreen()),
        GoRoute(path: R.invoiceDetail,  builder: (_, s)  => InvoiceDetailScreen(id: s.pathParameters['id']!)),
        GoRoute(path: R.ledger,         builder: (_, __) => const LedgerScreen()),
        GoRoute(path: R.retailerLedger, builder: (_, s)  => RetailerLedgerScreen(retailerId: s.pathParameters['rid']!)),
        GoRoute(path: R.retailers,      builder: (_, __) => const RetailersScreen()),
        GoRoute(path: R.retailerCreate, builder: (_, __) => const CreateRetailerScreen()),
        GoRoute(path: R.retailerDetail, builder: (_, s)  => RetailerDetailScreen(id: s.pathParameters['id']!)),
        GoRoute(path: R.agents,         builder: (_, __) => const AgentsScreen()),
        GoRoute(path: R.agentCreate,    builder: (_, __) => const CreateAgentScreen()),
        GoRoute(path: R.agentDetail,    builder: (_, s)  => AgentDetailScreen(id: s.pathParameters['id']!)),
        GoRoute(path: R.rates,          builder: (_, __) => const RatesScreen()),
        GoRoute(path: R.shifts,         builder: (_, __) => const ShiftsScreen()),
        GoRoute(path: R.shiftDetail,    builder: (_, s)  => ShiftDetailScreen(id: s.pathParameters['id']!)),
        GoRoute(path: R.crates,         builder: (_, __) => const CratesScreen()),
        GoRoute(path: R.analytics,      builder: (_, __) => const AnalyticsScreen()),
        GoRoute(path: R.userMgmt,   builder: (_, __) => const UserManagementScreen()),
        GoRoute(path: R.settings,       builder: (_, __) => const SettingsScreen()),
        GoRoute(path: R.returns,        builder: (_, __) => const ReturnsScreen()),
        GoRoute(path: R.stock,          builder: (_, __) => const StockScreen()),
        GoRoute(path: R.pricing,        builder: (_, __) => const PricingRulesScreen()),
        GoRoute(path: R.cashRecon,      builder: (_, __) => const CashReconciliationScreen()),
        GoRoute(path: R.dayClosure,     builder: (_, __) => const DayClosureScreen()),
        GoRoute(path: R.alerts,         builder: (_, __) => const AlertsScreen()),
        GoRoute(path: R.dailyReport,    builder: (_, __) => const DailyReportScreen()),
      ],
    ),

    // ── Delivery Agent Shell ────────────────────────────────────
    ShellRoute(
      builder: (_, __, child) => AgentShell(child: child),
      routes: [
        GoRoute(path: R.agentHome,        builder: (_, __) => const AgentHomeScreen()),
        GoRoute(path: R.shiftOpen,        builder: (_, __) => const ShiftOpenScreen()),
        GoRoute(path: R.shiftClose,       builder: (_, __) => const ShiftCloseScreen()),
        GoRoute(path: R.batchPickup,      builder: (_, s)  => BatchPickupScreen(batchId: s.pathParameters['id']!)),
        GoRoute(path: R.dcView,          builder: (_, s)  => DcViewScreen(batchId: s.pathParameters['id']!)),
        GoRoute(path: R.birdTransfer,    builder: (_, s)  => BirdTransferScreen(batchId: s.pathParameters['id']!)),
        GoRoute(path: R.transferHistory, builder: (_, __) => const TransferHistoryScreen()),
        GoRoute(path: R.agentDeliveries,  builder: (_, __) => const AgentDeliveriesScreen()),
        GoRoute(path: R.deliveryDone,     builder: (_, s)  => DeliveryCompleteScreen(deliveryId: s.pathParameters['id']!)),
        GoRoute(path: R.agentExpenses,    builder: (_, __) => const ExpensesScreen()),
        GoRoute(path: R.instantOrder,     builder: (_, __)  => const InstantOrderScreen()),
        GoRoute(path: R.deliveryHistory,  builder: (_, s)   =>
            DeliveryHistoryScreen(orderId: s.pathParameters['id']!)),
      ],
    ),
  ],
  errorBuilder: (_, s) => Scaffold(
    body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.error_outline, size: 48, color: Colors.red),
      const SizedBox(height: 12),
      Text('Page not found: ${s.uri}', textAlign: TextAlign.center),
    ])),
  ),
));

class _Refresh extends ChangeNotifier {
  _Refresh(Ref ref) { ref.listen(appUserProvider, (_, __) => notifyListeners()); }
}
