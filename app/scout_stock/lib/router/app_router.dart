import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scout_stock/domain/models/app_user.dart';
import 'package:scout_stock/domain/models/auth_session.dart';

import 'package:scout_stock/presentation/pages/admin/activity_log_admin_page.dart';
import 'package:scout_stock/presentation/pages/admin/bucket_management_admin_page.dart';
import 'package:scout_stock/presentation/pages/admin/bucket_upsert_page.dart';
import 'package:scout_stock/presentation/pages/admin/user_upsert_page.dart';
import 'package:scout_stock/presentation/pages/admin/users_page.dart';
import 'package:scout_stock/presentation/pages/bucket_loader_page.dart';
import 'package:scout_stock/presentation/pages/bucket_mixed_items_page.dart';
import 'package:scout_stock/presentation/pages/bucket_single_item_page.dart';
import 'package:scout_stock/presentation/pages/cart_page.dart';
import 'package:scout_stock/presentation/pages/login_page.dart';
import 'package:scout_stock/presentation/pages/manual_entry_page.dart';
import 'package:scout_stock/presentation/pages/me_page.dart';
import 'package:scout_stock/presentation/pages/scan_page.dart';
import 'package:scout_stock/presentation/widgets/admin_shell.dart';
import 'package:scout_stock/presentation/widgets/scout_shell.dart';
import 'package:scout_stock/state/providers/auth_providers.dart';
import 'package:scout_stock/theme/app_theme.dart';

import 'app_routes.dart';

final _rootNavKey = GlobalKey<NavigatorState>(debugLabel: 'rootNav');

class _RouterAuthNotifier extends ChangeNotifier {
  _RouterAuthNotifier(this._ref) {
    _ref.listen<AsyncValue<AuthSession?>>(authControllerProvider, (
      previous,
      next,
    ) {
      _authAsync = next;
      notifyListeners();
    }, fireImmediately: true);
  }

  final Ref _ref;

  AsyncValue<AuthSession?> _authAsync = const AsyncLoading<AuthSession?>();
  AsyncValue<AuthSession?> get authAsync => _authAsync;
}

final _routerAuthNotifierProvider = Provider<_RouterAuthNotifier>((ref) {
  final notifier = _RouterAuthNotifier(ref);
  ref.onDispose(notifier.dispose);
  return notifier;
});

final goRouterProvider = Provider<GoRouter>((ref) {
  final authNotifier = ref.watch(_routerAuthNotifierProvider);

  return GoRouter(
    navigatorKey: _rootNavKey,
    initialLocation: AppRoutes.root,
    debugLogDiagnostics: false,
    refreshListenable: authNotifier,
    redirect: (context, state) {
      final authAsync = authNotifier.authAsync;
      final location = state.matchedLocation;

      final isAtLogin = location == AppRoutes.login;
      final isAtLoading = location == AppRoutes.loading;

      if (authAsync.isLoading) {
        return isAtLoading ? null : AppRoutes.loading;
      }

      if (authAsync.hasError) {
        return isAtLogin ? null : AppRoutes.login;
      }

      final session = authAsync.asData?.value;
      final signedIn = session != null;

      if (!signedIn) {
        return isAtLogin ? null : AppRoutes.login;
      }

      final AppUser user = session.user;
      final bool isAdmin = user.role.isAdmin;

      if (isAtLogin || location == AppRoutes.root || isAtLoading) {
        return isAdmin ? AppRoutes.adminScan : AppRoutes.scan;
      }

      if (!isAdmin && location.startsWith(AppRoutes.adminBase)) {
        return AppRoutes.scan;
      }

      if (isAdmin) {
        if (location == AppRoutes.scan) return AppRoutes.adminScan;
        if (location == AppRoutes.cart) return AppRoutes.adminCart;
        if (location == AppRoutes.me) return AppRoutes.adminMe;
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
        path: AppRoutes.login,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: AppRoutes.error,
        builder: (context, state) => const _AppErrorScreen(),
      ),

      // Scout shell (tabs) — 3 tabs: Scan · Cart · Me
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return ScoutRouterShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.scan,
                name: 'scan',
                builder: (context, state) => const ScanPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.cart,
                name: 'cart',
                builder: (context, state) => const CartPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.me,
                name: 'me',
                builder: (context, state) => MePage(),
              ),
            ],
          ),
        ],
      ),

      GoRoute(
        parentNavigatorKey: _rootNavKey,
        path: AppRoutes.manualEntry,
        name: 'manualEntry',
        builder: (context, state) => const ManualEntryPage(),
      ),

      // ─── Bucket route — fetches by barcode, renders single/mixed ──────
      GoRoute(
        parentNavigatorKey: _rootNavKey,
        path: '/bucket/:barcode',
        name: 'bucket',
        builder: (context, state) {
          final raw = state.pathParameters['barcode'] ?? '';
          final barcode = Uri.decodeComponent(raw);
          return BucketLoaderPage(barcode: barcode);
        },
      ),

      GoRoute(
        parentNavigatorKey: _rootNavKey,
        path: AppRoutes.adminUserCreate,
        name: 'adminUserCreate',
        builder: (context, state) {
          final extra = state.extra;
          final createArgs = extra is CreateUserArgs ? extra : null;
          return UserUpsertPage(createArgs: createArgs);
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavKey,
        path: '/a/users/:id/edit',
        name: 'adminUserEdit',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          final extra = state.extra;

          final args = extra is UserUpsertArgs
              ? extra
              : UserUpsertArgs(scoutId: id, displayName: '', role: 'scout');

          return UserUpsertPage(editArgs: args);
        },
      ),

      GoRoute(
        parentNavigatorKey: _rootNavKey,
        path: AppRoutes.adminBucketCreate,
        name: 'adminBucketCreate',
        builder: (context, state) => const BucketUpsertPage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavKey,
        path: '/a/manage/buckets/:id/edit',
        name: 'adminBucketEdit',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          final extra = state.extra;

          final args = extra is BucketUpsertArgs
              ? extra
              : BucketUpsertArgs(
                  barcode: id,
                  name: '',
                  emoji: '🪣',
                  contents: const [],
                );

          return BucketUpsertPage(editArgs: args);
        },
      ),

      GoRoute(
        path: AppRoutes.adminBase,
        redirect: (context, state) => AppRoutes.adminScan,
      ),

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
                builder: (context, state) => const BucketManagementAdminPage(),
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
    final authAsync = ref.watch(authControllerProvider);
    final message = authAsync.hasError
        ? authAsync.error.toString()
        : 'Unknown error';

    return Scaffold(
      body: Center(child: Text('Failed to load user:\n$message')),
    );
  }
}
