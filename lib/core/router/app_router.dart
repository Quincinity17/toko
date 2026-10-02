import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/payments/presentation/payment_methods_page.dart';
import '../../features/products/presentation/product_import_page.dart';
import '../../features/products/presentation/products_page.dart';
import '../../features/products/presentation/tags_page.dart';
import '../../features/receipt/presentation/receipt_settings_page.dart';
import '../../features/reports/presentation/reports_page.dart';
import '../../features/sales/presentation/pos_page.dart';
import '../../features/settings/presentation/accounts/accounts_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/stock/presentation/stock_page.dart';
import '../../features/stores/presentation/stores_page.dart';
import '../theme/app_theme.dart';
import 'app_shell.dart';
import 'routes.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  // Router dibuat sekali; perubahan sesi hanya memicu evaluasi ulang redirect.
  final authChanged = ValueNotifier(0);
  ref.listen(authControllerProvider, (_, _) => authChanged.value++);
  ref.onDispose(authChanged.dispose);

  return GoRouter(
    initialLocation: AppRoutes.login,
    refreshListenable: authChanged,
    redirect: (context, state) {
      final user = ref.read(authControllerProvider);
      final path = state.matchedLocation;
      final atLogin = path == AppRoutes.login;

      if (user == null) return atLogin ? null : AppRoutes.login;
      if (atLogin || !user.role.canAccess(path)) return user.role.homePath;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.login,
        pageBuilder: (context, state) =>
            SpringFadePage(key: state.pageKey, child: const LoginPage()),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.uri.path, child: child),
        routes: [
          _page(AppRoutes.dashboard, const DashboardPage()),
          _page(AppRoutes.kasir, const PosPage()),
          _page(
            AppRoutes.produk,
            const ProductsPage(),
            routes: [_page('import', const ProductImportPage())],
          ),
          _page(AppRoutes.stok, const StockPage()),
          _page(AppRoutes.laporan, const ReportsPage()),
          _page(
            AppRoutes.pengaturan,
            const SettingsPage(),
            routes: [
              _page('akun', const AccountsPage()),
              _page('pembayaran', const PaymentMethodsPage()),
              _page('toko', const StoresPage()),
              _page('struk', const ReceiptSettingsPage()),
              _page('tag', const TagsPage()),
            ],
          ),
        ],
      ),
    ],
  );
});

GoRoute _page(String path, Widget child, {List<RouteBase> routes = const []}) {
  return GoRoute(
    path: path,
    routes: routes,
    pageBuilder: (context, state) =>
        SpringFadePage(key: state.pageKey, child: child),
  );
}

/// Transisi halaman: fade + geser naik sedikit dengan kurva pegas.
class SpringFadePage<T> extends CustomTransitionPage<T> {
  SpringFadePage({required super.child, super.key})
    : super(
        transitionDuration: AppDurations.slow,
        reverseTransitionDuration: AppDurations.fast,
        transitionsBuilder: (context, animation, secondary, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: SpringCurve.smooth,
            reverseCurve: Curves.easeOut,
          );
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.015),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      );
}
