import 'package:get/get.dart';

import '../../modules/auth/views/forgot_password_view.dart';
import '../../modules/auth/views/login_view.dart';
import '../../modules/dashboard/views/dashboard_view.dart';
import '../../modules/products/views/product_detail_view.dart';
import '../../modules/products/views/products_view.dart';
import '../../modules/categories/views/categories_view.dart';
import '../../modules/stores/views/store_detail_view.dart';
import '../../modules/stores/views/stores_view.dart';
import '../../modules/stock/views/stock_view.dart';
import '../../modules/stock/views/stock_movements_view.dart';
import '../../modules/stock/views/stock_availability_view.dart';
import '../../modules/product_requests/views/request_detail_view.dart';
import '../../modules/product_requests/views/request_form_view.dart';
import '../../modules/product_requests/views/requests_view.dart';
import '../../modules/packing_orders/views/packing_detail_view.dart';
import '../../modules/packing_orders/views/packing_form_view.dart';
import '../../modules/packing_orders/views/packing_orders_view.dart';
import '../../modules/transfers/views/transfer_detail_view.dart';
import '../../modules/transfers/views/transfer_form_view.dart';
import '../../modules/transfers/views/transfers_view.dart';
import '../../modules/sales/views/sale_detail_view.dart';
import '../../modules/sales/views/sale_form_view.dart';
import '../../modules/sales/views/sales_view.dart';
import '../../modules/returns/views/return_detail_view.dart';
import '../../modules/returns/views/return_form_view.dart';
import '../../modules/returns/views/returns_view.dart';
import '../../modules/reports/views/reports_view.dart';
import '../../modules/users/views/users_view.dart';
import '../../modules/managers/views/managers_view.dart';
import '../../modules/notifications/views/notifications_view.dart';
import '../../modules/settings/views/settings_view.dart';
import '../../modules/audit_logs/views/audit_logs_view.dart';
import '../constants/permissions.dart';
import 'app_routes.dart';
import 'nav_items.dart';
import 'route_guards.dart';
import 'splash_view.dart';

class AppPages {
  AppPages._();

  static final routes = <GetPage>[
    GetPage(name: AppRoutes.splash, page: () => const SplashView()),
    GetPage(name: AppRoutes.login, page: () => const LoginView(), middlewares: [GuestGuard()]),
    GetPage(name: AppRoutes.forgotPassword, page: () => const ForgotPasswordView(), middlewares: [GuestGuard()]),

    GetPage(name: AppRoutes.dashboard, page: () => const DashboardView(), middlewares: [AuthGuard()]),

    GetPage(name: AppRoutes.products, page: () => const ProductsView(), middlewares: [AuthGuard()]),
    GetPage(name: AppRoutes.productDetail, page: () => const ProductDetailView(), middlewares: [AuthGuard()]),
    GetPage(name: AppRoutes.categories, page: () => const CategoriesView(), middlewares: [AuthGuard(), AccessGuard(Access(anyPermission: [Perm.categoriesManage]))]),

    GetPage(name: AppRoutes.stores, page: () => const StoresView(), middlewares: [AuthGuard(), AccessGuard(Access.staff)]),
    GetPage(name: AppRoutes.storeDetail, page: () => const StoreDetailView(), middlewares: [AuthGuard(), AccessGuard(Access.staff)]),

    GetPage(name: AppRoutes.stock, page: () => const StockView(), middlewares: [AuthGuard(), AccessGuard(Access(anyPermission: [Perm.stockView]))]),
    GetPage(name: AppRoutes.stockMovements, page: () => const StockMovementsView(), middlewares: [AuthGuard(), AccessGuard(Access(anyPermission: [Perm.stockView]))]),
    GetPage(name: AppRoutes.stockAvailability, page: () => const StockAvailabilityView(), middlewares: [AuthGuard(), AccessGuard(Access(anyPermission: [Perm.stockView]))]),

    GetPage(name: AppRoutes.requestNew, page: () => const RequestFormView(), middlewares: [AuthGuard()]),
    GetPage(name: AppRoutes.requestEdit, page: () => const RequestFormView(), middlewares: [AuthGuard()]),
    GetPage(name: AppRoutes.requests, page: () => const RequestsView(), middlewares: [AuthGuard()]),
    GetPage(name: AppRoutes.requestDetail, page: () => const RequestDetailView(), middlewares: [AuthGuard()]),

    GetPage(name: AppRoutes.packingNew, page: () => const PackingFormView(), middlewares: [AuthGuard(), AccessGuard(Access(anyPermission: [Perm.packingManage]))]),
    GetPage(name: AppRoutes.packingEdit, page: () => const PackingFormView(), middlewares: [AuthGuard(), AccessGuard(Access(anyPermission: [Perm.packingManage]))]),
    GetPage(name: AppRoutes.packingOrders, page: () => const PackingOrdersView(), middlewares: [AuthGuard()]),
    GetPage(name: AppRoutes.packingDetail, page: () => const PackingDetailView(), middlewares: [AuthGuard()]),

    GetPage(name: AppRoutes.transferNew, page: () => const TransferFormView(), middlewares: [AuthGuard(), AccessGuard(Access(anyPermission: [Perm.transfersRequest]))]),
    GetPage(name: AppRoutes.transfers, page: () => const TransfersView(), middlewares: [AuthGuard()]),
    GetPage(name: AppRoutes.transferDetail, page: () => const TransferDetailView(), middlewares: [AuthGuard()]),

    GetPage(name: AppRoutes.saleNew, page: () => const SaleFormView(), middlewares: [AuthGuard(), AccessGuard(Access(anyPermission: [Perm.salesCreate]))]),
    GetPage(name: AppRoutes.sales, page: () => const SalesView(), middlewares: [AuthGuard(), AccessGuard(Access(anyPermission: [Perm.salesView]))]),
    GetPage(name: AppRoutes.saleDetail, page: () => const SaleDetailView(), middlewares: [AuthGuard(), AccessGuard(Access(anyPermission: [Perm.salesView]))]),

    GetPage(name: AppRoutes.returnNew, page: () => const ReturnFormView(), middlewares: [AuthGuard(), AccessGuard(Access(anyPermission: [Perm.returnsManage]))]),
    GetPage(name: AppRoutes.returns, page: () => const ReturnsView(), middlewares: [AuthGuard(), AccessGuard(Access(anyPermission: [Perm.salesView, Perm.returnsManage]))]),
    GetPage(name: AppRoutes.returnDetail, page: () => const ReturnDetailView(), middlewares: [AuthGuard(), AccessGuard(Access(anyPermission: [Perm.salesView, Perm.returnsManage]))]),

    GetPage(name: AppRoutes.reports, page: () => const ReportsView(), middlewares: [AuthGuard(), AccessGuard(Access(anyPermission: [Perm.reportsView]))]),
    GetPage(name: AppRoutes.users, page: () => const UsersView(), middlewares: [AuthGuard(), AccessGuard(Access(anyPermission: [Perm.usersManage]))]),
    GetPage(name: AppRoutes.managers, page: () => const ManagersView(), middlewares: [AuthGuard(), AccessGuard(Access.adminOnly)]),
    GetPage(name: AppRoutes.notifications, page: () => const NotificationsView(), middlewares: [AuthGuard()]),
    GetPage(name: AppRoutes.settings, page: () => const SettingsView(), middlewares: [AuthGuard()]),
    GetPage(name: AppRoutes.auditLogs, page: () => const AuditLogsView(), middlewares: [AuthGuard(), AccessGuard(Access(anyPermission: [Perm.auditView]))]),
  ];
}
