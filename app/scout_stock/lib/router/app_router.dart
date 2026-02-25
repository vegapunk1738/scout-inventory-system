import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scout_stock/domain/models/app_user.dart';

import 'package:scout_stock/presentation/pages/admin/activity_log_admin_page.dart';
import 'package:scout_stock/presentation/pages/admin/users_page.dart';
import 'package:scout_stock/presentation/pages/admin/user_upsert_page.dart';
import 'package:scout_stock/presentation/pages/bucket_mixed_items_page.dart';
import 'package:scout_stock/presentation/pages/bucket_single_item_page.dart';
import 'package:scout_stock/presentation/pages/cart_page.dart';
import 'package:scout_stock/presentation/pages/manual_entry_page.dart';
import 'package:scout_stock/presentation/pages/me_page.dart';
import 'package:scout_stock/presentation/pages/scan_page.dart';
import 'package:scout_stock/presentation/widgets/admin_shell.dart';
import 'package:scout_stock/theme/app_theme.dart';

import 'package:scout_stock/state/providers/current_user_provider.dart';
import 'app_routes.dart';

final _rootNavKey = GlobalKey<NavigatorState>(debugLabel: 'rootNav');

/// Keeps GoRouter in sync with Riverpod auth/user state without rebuilding the
/// router instance (important for performance and to preserve navigation stacks).
class _RouterAuthNotifier extends ChangeNotifier {
  _RouterAuthNotifier(this._ref) {
    _ref.listen(currentUserProvider, (prev, next) {
      _userAsync = next;
      notifyListeners();
    }, fireImmediately: true);
  }

  final Ref _ref;

  AsyncValue<dynamic> _userAsync = const AsyncLoading<dynamic>();
  AsyncValue<dynamic> get userAsync => _userAsync;
}

final _routerAuthNotifierProvider = Provider<_RouterAuthNotifier>((ref) {
  final n = _RouterAuthNotifier(ref);
  ref.onDispose(n.dispose);
  return n;
});

final goRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(_routerAuthNotifierProvider);

  return GoRouter(
    navigatorKey: _rootNavKey,
    initialLocation: AppRoutes.root,
    debugLogDiagnostics: false,
    refreshListenable: auth,
    redirect: (context, state) {
      final userAsync = auth.userAsync;
      final loc = state.matchedLocation;

      // 1) User bootstrap
      if (userAsync.isLoading) {
        return (loc == AppRoutes.loading) ? null : AppRoutes.loading;
      }
      if (userAsync.hasError) {
        return (loc == AppRoutes.error) ? null : AppRoutes.error;
      }

      // 2) Role gates + canonical admin tab URLs
      final user = userAsync.value;
      final AppUser u = user;
      final bool isAdmin = u.role.isAdmin == true;

      if (loc == AppRoutes.loading) {
        return isAdmin ? AppRoutes.adminScan : AppRoutes.scan;
      }

      // Root always redirects to a stable entry point.
      if (loc == AppRoutes.root) {
        return isAdmin ? AppRoutes.adminScan : AppRoutes.scan;
      }

      // Non-admins never see admin shell routes.
      if (!isAdmin && loc.startsWith(AppRoutes.adminBase)) {
        return AppRoutes.scan;
      }

      // Admins: keep legacy/scout URLs canonical by mapping to admin tabs.
      if (isAdmin) {
        if (loc == AppRoutes.scan) return AppRoutes.adminScan;
        if (loc == AppRoutes.cart) return AppRoutes.adminCart;
        if (loc == AppRoutes.me) return AppRoutes.adminMe;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.root,
        builder: (context, state) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: AppRoutes.loading,
        builder: (context, state) => const _AppLoadingScreen(),
      ),
      GoRoute(
        path: AppRoutes.error,
        builder: (context, state) => const _AppErrorScreen(),
      ),

      // Scout/common top-level routes (admins are redirected to /a/*).
      GoRoute(
        path: AppRoutes.scan,
        name: 'scan',
        builder: (context, state) => const ScanPage(),
      ),
      GoRoute(
        path: AppRoutes.cart,
        name: 'cart',
        builder: (context, state) => const CartPage(),
      ),
      GoRoute(
        path: AppRoutes.me,
        name: 'me',
        builder: (context, state) => MePage(),
      ),

      // Routes that must always sit above the admin shell (no bottom nav).
      GoRoute(
        parentNavigatorKey: _rootNavKey,
        path: AppRoutes.manualEntry,
        name: 'manualEntry',
        builder: (context, state) => const ManualEntryPage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavKey,
        path: '/bucket/:barcode',
        name: 'bucket',
        builder: (context, state) {
          final raw = state.pathParameters['barcode'] ?? '';
          final barcode = Uri.decodeComponent(raw);
          return _BucketRouteDecider(barcode: barcode);
        },
      ),

      
      // Admin: user create/edit pages (above the shell, no bottom nav).
      GoRoute(
        parentNavigatorKey: _rootNavKey,
        path: AppRoutes.adminUserCreate,
        name: 'adminUserCreate',
        builder: (context, state) => const UserUpsertPage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavKey,
        path: '/a/users/:id/edit',
        name: 'adminUserEdit',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          final extra = state.extra;
          final args =
              extra is UserUpsertArgs
                  ? extra
                  : UserUpsertArgs(
                      scoutId: id,
                      displayName: '',
                      role: 'scout',
                    );
          return UserUpsertPage(editArgs: args);
        },
      ),

      // Make /a resolve cleanly.
      GoRoute(
        path: AppRoutes.adminBase,
        redirect: (context, state) => AppRoutes.adminScan,
      ),

      // Admin shell (tabs) with preserved per-tab navigation stacks.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AdminRouterShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.adminScan,
                name: 'adminScan',
                builder: (context, state) => const ScanPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.adminCart,
                name: 'adminCart',
                builder: (context, state) => const CartPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.adminMe,
                name: 'adminMe',
                builder: (context, state) => MePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.adminManage,
                name: 'adminManage',
                builder: (context, state) =>
                    const _PlaceholderPage(title: 'Manage'),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.adminActivity,
                name: 'adminActivity',
                builder: (context, state) => const ActivityLogPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.adminUsers,
                name: 'adminUsers',
                builder: (context, state) => const UsersAdminPage(),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Text(
            'Route not found\n${state.uri}',
            textAlign: TextAlign.center,
          ),
        ),
      );
    },
  );
});

class _BucketRouteDecider extends StatelessWidget {
  const _BucketRouteDecider({required this.barcode});

  final String barcode;

  @override
  Widget build(BuildContext context) {
    // Demo routing behavior (mirrors ScanPage demo barcodes).
    if (barcode == 'ABC-ABC-123') {
      return BucketItemPage(barcode: barcode);
    }

    if (barcode == 'AAA-AAA-111') {
      return BucketMixedItemsPage(
        bucketId: barcode,
        bucketName: 'Bucket 1',
        items: const [
          BucketCatalogItem(
            id: 'ITM-HDS-0001',
            name: 'Heavy Duty Stakes',
            emoji: '📌',
            available: 12,
          ),
          BucketCatalogItem(
            id: 'ITM-NRP-0002',
            name: 'Nylon Rope (10m)',
            emoji: '🪢',
            available: 5,
          ),
          BucketCatalogItem(
            id: 'ITM-LED-0003',
            name: 'LED Lantern',
            emoji: '🏮',
            available: 7,
          ),
          BucketCatalogItem(
            id: 'ITM-FTC-0004',
            name: 'First Aid Kit',
            emoji: '🩹',
            available: 2,
          ),
          BucketCatalogItem(
            id: 'ITM-TPR-0005',
            name: 'Tarp (2×3m)',
            emoji: '⛺️',
            available: 4,
          ),
        ],
      );
    }

    // Unknown buckets shouldn't happen in demo flows, but handle deep links.
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Bucket'),
        backgroundColor: AppColors.background,
      ),
      body: Center(
        child: Text(
          'Unknown bucket barcode:\n$barcode',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _AppLoadingScreen extends StatelessWidget {
  const _AppLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _AppErrorScreen extends ConsumerWidget {
  const _AppErrorScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    final msg = userAsync.hasError
        ? userAsync.error.toString()
        : 'Unknown error';

    return Scaffold(body: Center(child: Text('Failed to load user:\n$msg')));
  }
}

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
    );
  }
}
