import 'package:flutter/material.dart';

import '../constants/permissions.dart';
import '../session/auth_service.dart';
import 'app_routes.dart';

/// Access rule for a route / menu entry. Empty = any signed-in user.
class Access {
  const Access({this.roles = const [], this.anyPermission = const []});
  final List<String> roles;
  final List<String> anyPermission;

  bool allows(AuthService auth) {
    if (!auth.isLoggedIn) return false;
    if (roles.isNotEmpty && !auth.hasRole(roles)) return false;
    if (anyPermission.isNotEmpty && !auth.canAny(anyPermission)) return false;
    return true;
  }

  static const any = Access();
  static const adminOnly = Access(roles: [Roles.admin]);
  static const staff = Access(roles: [Roles.admin, Roles.manager]);
}

class NavItem {
  const NavItem(this.label, this.route, this.icon, this.selectedIcon, {this.access = Access.any, this.section = ''});
  final String label;
  final String route;
  final IconData icon;
  final IconData selectedIcon;
  final Access access;
  final String section;
}

/// Sidebar menu. Every route here is also guarded server-side.
const navItems = <NavItem>[
  NavItem('Dashboard', AppRoutes.dashboard, Icons.space_dashboard_outlined, Icons.space_dashboard, section: 'Overview'),
  NavItem('Products', AppRoutes.products, Icons.inventory_2_outlined, Icons.inventory_2, section: 'Catalog'),
  NavItem('Categories', AppRoutes.categories, Icons.category_outlined, Icons.category, access: Access(anyPermission: [Perm.categoriesManage]), section: 'Catalog'),
  NavItem('Stores', AppRoutes.stores, Icons.storefront_outlined, Icons.storefront, access: Access.staff, section: 'Catalog'),
  NavItem('Stock', AppRoutes.stock, Icons.warehouse_outlined, Icons.warehouse, access: Access(anyPermission: [Perm.stockView]), section: 'Inventory'),
  NavItem('Movements', AppRoutes.stockMovements, Icons.swap_vert_outlined, Icons.swap_vert, access: Access(anyPermission: [Perm.stockView]), section: 'Inventory'),
  NavItem('Availability', AppRoutes.stockAvailability, Icons.fact_check_outlined, Icons.fact_check, access: Access(anyPermission: [Perm.stockView]), section: 'Inventory'),
  NavItem('Requests', AppRoutes.requests, Icons.assignment_outlined, Icons.assignment, section: 'Operations'),
  NavItem('Packing', AppRoutes.packingOrders, Icons.local_shipping_outlined, Icons.local_shipping, section: 'Operations'),
  NavItem('Transfers', AppRoutes.transfers, Icons.compare_arrows_outlined, Icons.compare_arrows, section: 'Operations'),
  NavItem('Sales', AppRoutes.sales, Icons.point_of_sale_outlined, Icons.point_of_sale, access: Access(anyPermission: [Perm.salesView]), section: 'Sales'),
  NavItem('Returns', AppRoutes.returns, Icons.assignment_return_outlined, Icons.assignment_return, access: Access(anyPermission: [Perm.salesView, Perm.returnsManage]), section: 'Sales'),
  NavItem('Reports', AppRoutes.reports, Icons.insights_outlined, Icons.insights, access: Access(anyPermission: [Perm.reportsView]), section: 'Sales'),
  NavItem('Users', AppRoutes.users, Icons.people_outline, Icons.people, access: Access(anyPermission: [Perm.usersManage]), section: 'Administration'),
  NavItem('Managers', AppRoutes.managers, Icons.manage_accounts_outlined, Icons.manage_accounts, access: Access.adminOnly, section: 'Administration'),
  NavItem('Audit log', AppRoutes.auditLogs, Icons.history_outlined, Icons.history, access: Access(anyPermission: [Perm.auditView]), section: 'Administration'),
  NavItem('Settings', AppRoutes.settings, Icons.settings_outlined, Icons.settings, section: 'Administration'),
];
