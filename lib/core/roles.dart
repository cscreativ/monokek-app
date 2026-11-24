import 'package:flutter/material.dart';

/// Role names as stored in the identity `roles` table (same as mono-kep-tauri/src/constants/roles.ts).
class Roles {
  static const admin = 'admin';
  static const manager = 'manager';
  static const cashier = 'cashier';
  static const waiter = 'waiter';
  static const kitchen = 'kitchen';

  /// Roles this app serves; admin/manager use the Tauri back-office.
  static const supported = {cashier, waiter, kitchen};
}

/// Where a role lands after login — single source of truth shared by the router redirect.
String roleHomeRoute(String? role) {
  switch (role) {
    case Roles.kitchen:
      return '/kitchen';
    case Roles.cashier:
      return '/pos/sales';
    case Roles.waiter:
      return '/pos/tables';
    case Roles.admin:
    case Roles.manager:
      return '/unsupported';
    default:
      return '/pos/tables';
  }
}

class RoleTheme {
  const RoleTheme(this.color, this.label);
  final Color color;
  final String label;
}

const roleThemes = <String, RoleTheme>{
  Roles.admin: RoleTheme(Color(0xFF8B5CF6), 'Administrateur'),
  Roles.manager: RoleTheme(Color(0xFF8B5CF6), 'Administrateur'),
  Roles.cashier: RoleTheme(Color(0xFF10B981), 'Caissier'),
  Roles.waiter: RoleTheme(Color(0xFF3B82F6), 'Serveur'),
  Roles.kitchen: RoleTheme(Color(0xFFF59E0B), 'Cuisine'),
};

class Permissions {
  static const createOrders = 'create_orders';
  static const editOrders = 'edit_orders';
  static const cancelOrders = 'cancel_orders';
  static const viewHistory = 'view_history';
  static const closeCashier = 'close_cashier';
  static const manageDiscounts = 'manage_discounts';
}
