import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/products/presentation/products_page.dart';
import '../../features/reports/presentation/reports_page.dart';
import '../../features/sales/presentation/pos_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../theme/app_theme.dart';
import 'app_shell.dart';
import 'routes.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.dashboard,
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.uri.path, child: child),
        routes: [
          _page(AppRoutes.dashboard, const DashboardPage()),
          _page(AppRoutes.kasir, const PosPage()),
          _page(AppRoutes.produk, const ProductsPage()),
          _page(AppRoutes.laporan, const ReportsPage()),
          _page(AppRoutes.pengaturan, const SettingsPage()),
        ],
      ),
    ],
  );
});

GoRoute _page(String path, Widget child) {
  return GoRoute(
    path: path,
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
