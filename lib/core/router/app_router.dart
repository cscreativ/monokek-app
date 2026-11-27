import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_controller.dart';
import '../../features/auth/login_page.dart';
import '../../features/auth/setup_page.dart';
import '../../features/cashier/comptoir_page.dart';
import '../../features/clock/clock_page.dart';
import '../../features/printing/usb_printer_page.dart';
import '../../features/cashier/history_page.dart';
import '../../features/cashier/register_picker_page.dart';
import '../../features/cashier/sales_page.dart';
import '../../features/home/role_home_page.dart';
import '../../features/kitchen/kitchen_dashboard_page.dart';
import '../../features/kitchen/kitchen_tickets_page.dart';
import '../../features/pos/order_page.dart';
import '../../features/waiter/history_page.dart';
import '../../features/waiter/tables_page.dart';
import '../../features/waiter/waiter_shell.dart';
import '../../shared/widgets/app_shell.dart';
import '../roles.dart';
import '../storage/app_storage.dart';

/// Pure redirect rule (testable): setup → login → role home, with role-based route guard
/// (port of RouteGuard + roleHomeRoute).
String? computeRedirect({required String location, required bool hasBackend, required bool authenticated, String? role}) {
  final isSetup = location == '/setup';
  final isLogin = location == '/login';

  if (!hasBackend) return isSetup ? null : '/setup';
  if (!authenticated) return (isLogin || isSetup) ? null : '/login';

  final home = roleHomeRoute(role);
  if (location == '/' || isLogin) return home;
  if (location == '/unsupported') return Roles.supported.contains(role) ? home : null;
  if (location == '/pos/clock') return null; // kiosk clock-in is open to every role, kitchen included
  if (location == '/printer/usb') return null; // each terminal's own printer, kitchen tablets included
  if (location.startsWith('/kitchen') && role != Roles.kitchen) return home;
  if (location.startsWith('/pos') && role == Roles.kitchen) return home;
  if (location.startsWith('/pos/sales') && role == Roles.waiter) return home; // cash screens are cashier-only
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final storage = ref.read(storageProvider);
  final refresh = ValueNotifier<int>(0);
  ref.listen(authProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      return computeRedirect(
        location: state.matchedLocation,
        hasBackend: (storage.backendIp ?? '').isNotEmpty,
        authenticated: auth.isAuthenticated,
        role: auth.user?.role,
      );
    },
    routes: [
      // /setup stays outside the shell so it is reachable when the licence/network gate blocks the app.
      GoRoute(path: '/setup', builder: (_, _) => const SetupPage()),
      ShellRoute(
        builder: (_, _, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink()),
          GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
          GoRoute(path: '/pos/clock', builder: (_, _) => const ClockPage()),
          GoRoute(path: '/printer/usb', builder: (_, _) => const UsbPrinterPage()),
          GoRoute(path: '/unsupported', builder: (_, _) => const UnsupportedRolePage()),
          ShellRoute(
            builder: (_, _, child) => WaiterShell(alerts: true, child: child),
            routes: [
              GoRoute(path: '/pos/tables', builder: (_, _) => const TablesPage()),
              GoRoute(path: '/pos/tables/history', builder: (_, _) => const WaiterHistoryPage()),
            ],
          ),
          GoRoute(
            path: '/pos/tables/order',
            builder: (_, state) => OrderPage(tableId: int.tryParse(state.uri.queryParameters['table'] ?? '')),
          ),
          // Cashier: register assignment, then the shift screens inside the cashier shell.
          GoRoute(path: '/pos/sales', builder: (_, _) => const RegisterPickerPage()),
          ShellRoute(
            builder: (context, _, child) => Consumer(
              builder: (_, ref, _) => WaiterShell(
                tabs: cashierTabs,
                showLogout: true,
                registerName: ref.read(storageProvider).registerName ?? '—',
                child: child,
              ),
            ),
            routes: [
              GoRoute(path: '/pos/sales/order', builder: (_, _) => const SalesPage()),
              GoRoute(path: '/pos/sales/tables', builder: (_, _) => const TablesPage(orderRoute: '/pos/sales/tables/order')),
              GoRoute(path: '/pos/sales/comptoir', builder: (_, _) => const ComptoirPage()),
              GoRoute(path: '/pos/sales/history', builder: (_, _) => const SalesHistoryPage()),
            ],
          ),
          GoRoute(
            path: '/pos/sales/tables/order',
            builder: (_, state) => OrderPage(
              tableId: int.tryParse(state.uri.queryParameters['table'] ?? ''),
              backRoute: '/pos/sales/tables',
            ),
          ),
          GoRoute(path: '/kitchen', builder: (_, _) => const KitchenDashboardPage()),
          GoRoute(
            path: '/kitchen/tickets',
            builder: (_, state) => KitchenTicketsPage(stationId: int.tryParse(state.uri.queryParameters['station'] ?? '')),
          ),
        ],
      ),
    ],
  );
});
