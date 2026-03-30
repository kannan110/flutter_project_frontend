import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/app_user.dart';
import '../providers/session_provider.dart';
import '../../features/auth/login_screen.dart';
import '../../features/trader_admin/dashboard/dashboard_screen.dart';
import '../../features/trader_admin/dashboard/trader_shell.dart';
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
import '../../features/delivery_agent/home/agent_home_screen.dart';
import '../../features/delivery_agent/home/agent_shell.dart';
import '../../features/delivery_agent/shift/shift_open_screen.dart';
import '../../features/delivery_agent/shift/shift_close_screen.dart';
import '../../features/delivery_agent/batch/batch_pickup_screen.dart';
import '../../features/delivery_agent/deliveries/agent_deliveries_screen.dart';
import '../../features/delivery_agent/deliveries/delivery_complete_screen.dart';
import '../../features/delivery_agent/expenses/expenses_screen.dart';

class Routes {
  static const login = '/login';

  // Trader / Admin — all under /t/
  static const dashboard       = '/t/dashboard';
  static const orders          = '/t/orders';
  static const orderCreate     = '/t/orders/create';
  static const orderDetail     = '/t/orders/:id';
  static const dispatch        = '/t/dispatch';
  static const batchDetail     = '/t/dispatch/batch/:id';
  static const approvals       = '/t/approvals';
  static const approvalDetail  = '/t/approvals/:id';
  static const invoices        = '/t/invoices';
  static const invoiceDetail   = '/t/invoices/:id';
  static const ledger          = '/t/ledger';
  static const retailerLedger  = '/t/ledger/:retailerId';
  static const retailers       = '/t/retailers';
  static const retailerCreate  = '/t/retailers/create';
  static const retailerDetail  = '/t/retailers/:id';
  static const agents          = '/t/agents';
  static const agentCreate     = '/t/agents/create';
  static const agentDetail     = '/t/agents/:id';
  static const rates           = '/t/rates';
  static const shifts          = '/t/shifts';
  static const shiftDetail     = '/t/shifts/:id';
  static const crates          = '/t/crates';
  static const analytics       = '/t/analytics';
  static const settings        = '/t/settings';

  // Delivery Agent — all under /a/
  static const agentHome          = '/a/home';
  static const agentShiftOpen     = '/a/shift/open';
  static const agentShiftClose    = '/a/shift/close';
  static const agentBatchPickup   = '/a/batch/:id/pickup';
  static const agentDeliveries    = '/a/deliveries';
  static const agentDeliveryDone  = '/a/delivery/:id/complete';
  static const agentExpenses      = '/a/expenses';

  // Helpers to build parameterised paths
  static String orderDetailPath(String id)      => '/t/orders/$id';
  static String batchDetailPath(String id)      => '/t/dispatch/batch/$id';
  static String approvalDetailPath(String id)   => '/t/approvals/$id';
  static String invoiceDetailPath(String id)    => '/t/invoices/$id';
  static String retailerLedgerPath(String id)   => '/t/ledger/$id';
  static String retailerDetailPath(String id)   => '/t/retailers/$id';
  static String agentDetailPath(String id)      => '/t/agents/$id';
  static String shiftDetailPath(String id)      => '/t/shifts/$id';
  static String agentBatchPickupPath(String id) => '/a/batch/$id/pickup';
  static String agentDeliveryDonePath(String id) => '/a/delivery/$id/complete';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.login,
    refreshListenable: _RouterRefresh(ref),
    redirect: (context, state) {
      final async = ref.read(appUserProvider);
      if (async.isLoading) return null;

      final user = async.valueOrNull;
      final loc  = state.matchedLocation;

      if (user == null) {
        return loc == Routes.login ? null : Routes.login;
      }
      if (loc == Routes.login) {
        return user.isDeliveryAgent ? Routes.agentHome : Routes.dashboard;
      }
      if (user.isDeliveryAgent && !loc.startsWith('/a/')) return Routes.agentHome;
      if (!user.isDeliveryAgent && loc.startsWith('/a/'))  return Routes.dashboard;
      return null;
    },
    routes: [
      GoRoute(path: Routes.login, builder: (_, __) => const LoginScreen()),

      // ── Trader / Admin shell ─────────────────────────────────
      ShellRoute(
        builder: (_, __, child) => TraderShell(child: child),
        routes: [
          GoRoute(path: Routes.dashboard,      builder: (_, __) => const DashboardScreen()),
          GoRoute(path: Routes.orders,         builder: (_, __) => const OrdersScreen()),
          GoRoute(path: Routes.orderCreate,    builder: (_, __) => const CreateOrderScreen()),
          GoRoute(path: Routes.orderDetail,    builder: (_, s)  => OrderDetailScreen(id: s.pathParameters['id']!)),
          GoRoute(path: Routes.dispatch,       builder: (_, __) => const DispatchScreen()),
          GoRoute(path: Routes.batchDetail,    builder: (_, s)  => BatchDetailScreen(id: s.pathParameters['id']!)),
          GoRoute(path: Routes.approvals,      builder: (_, __) => const ApprovalsScreen()),
          GoRoute(path: Routes.approvalDetail, builder: (_, s)  => ApprovalDetailScreen(id: s.pathParameters['id']!)),
          GoRoute(path: Routes.invoices,       builder: (_, __) => const InvoicesScreen()),
          GoRoute(path: Routes.invoiceDetail,  builder: (_, s)  => InvoiceDetailScreen(id: s.pathParameters['id']!)),
          GoRoute(path: Routes.ledger,         builder: (_, __) => const LedgerScreen()),
          GoRoute(path: Routes.retailerLedger, builder: (_, s)  => RetailerLedgerScreen(retailerId: s.pathParameters['retailerId']!)),
          GoRoute(path: Routes.retailers,      builder: (_, __) => const RetailersScreen()),
          GoRoute(path: Routes.retailerCreate, builder: (_, __) => const CreateRetailerScreen()),
          GoRoute(path: Routes.retailerDetail, builder: (_, s)  => RetailerDetailScreen(id: s.pathParameters['id']!)),
          GoRoute(path: Routes.agents,         builder: (_, __) => const AgentsScreen()),
          GoRoute(path: Routes.agentCreate,    builder: (_, __) => const CreateAgentScreen()),
          GoRoute(path: Routes.agentDetail,    builder: (_, s)  => AgentDetailScreen(id: s.pathParameters['id']!)),
          GoRoute(path: Routes.rates,          builder: (_, __) => const RatesScreen()),
          GoRoute(path: Routes.shifts,         builder: (_, __) => const ShiftsScreen()),
          GoRoute(path: Routes.shiftDetail,    builder: (_, s)  => ShiftDetailScreen(id: s.pathParameters['id']!)),
          GoRoute(path: Routes.crates,         builder: (_, __) => const CratesScreen()),
          GoRoute(path: Routes.analytics,      builder: (_, __) => const AnalyticsScreen()),
          GoRoute(path: Routes.settings,       builder: (_, __) => const SettingsScreen()),
        ],
      ),

      // ── Delivery Agent shell ──────────────────────────────────
      ShellRoute(
        builder: (_, __, child) => AgentShell(child: child),
        routes: [
          GoRoute(path: Routes.agentHome,          builder: (_, __) => const AgentHomeScreen()),
          GoRoute(path: Routes.agentShiftOpen,     builder: (_, __) => const ShiftOpenScreen()),
          GoRoute(path: Routes.agentShiftClose,    builder: (_, __) => const ShiftCloseScreen()),
          GoRoute(path: Routes.agentBatchPickup,   builder: (_, s)  => BatchPickupScreen(batchId: s.pathParameters['id']!)),
          GoRoute(path: Routes.agentDeliveries,    builder: (_, __) => const AgentDeliveriesScreen()),
          GoRoute(path: Routes.agentDeliveryDone,  builder: (_, s)  => DeliveryCompleteScreen(deliveryId: s.pathParameters['id']!)),
          GoRoute(path: Routes.agentExpenses,      builder: (_, __) => const ExpensesScreen()),
        ],
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      appBar: AppBar(title: const Text('Page Not Found')),
      body: Center(child: Text('No route for: ${state.uri}')),
    ),
  );
});

class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(appUserProvider, (_, __) => notifyListeners());
  }
}
