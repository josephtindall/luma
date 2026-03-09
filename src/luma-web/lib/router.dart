import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'services/auth_service.dart';
import 'services/api_client.dart';
import 'services/user_service.dart';
import 'screens/setup/setup_wizard_screen.dart';
import 'screens/login/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/admin/admin_layout.dart';
import 'screens/admin/admin_users_screen.dart';
import 'screens/admin/admin_invites_screen.dart';
import 'screens/admin/admin_settings_screen.dart';
import 'screens/admin/admin_groups_screen.dart';
import 'screens/admin/admin_roles_screen.dart';
import 'screens/register/register_screen.dart';
import 'screens/auth/reset_password_screen.dart';
import 'screens/main_layout.dart';

GoRouter buildRouter(
  AuthService authService,
  ApiClient apiClient,
  UserService userService,
) {
  return GoRouter(
    refreshListenable: authService,
    redirect: (BuildContext context, GoRouterState state) {
      if (!authService.isInitialized) return null; // show splash spinner

      if (authService.setupState == 'unclaimed') {
        return state.uri.path == '/setup' ? null : '/setup';
      }

      // Force-change pending — gate to reset-password screen.
      if (authService.hasPasswordChangePending) {
        return state.uri.path == '/reset-password' ? null : '/reset-password';
      }

      if (!authService.isLoggedIn) {
        // Allow unauthenticated flows without being logged in.
        if (state.uri.path == '/login' ||
            state.uri.path == '/join' ||
            state.uri.path == '/reset-password') {
          return null;
        }
        return '/login';
      }

      // Logged in — bounce away from login/setup/join/reset-password.
      if (state.uri.path == '/login' ||
          state.uri.path == '/setup' ||
          state.uri.path == '/join' ||
          state.uri.path == '/reset-password') {
        return '/home';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const _SplashScreen(),
      ),
      GoRoute(
        path: '/setup',
        builder: (_, __) =>
            SetupWizardScreen(auth: authService, userService: userService),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => LoginScreen(
          auth: authService,
          userService: userService,
        ),
      ),
      GoRoute(
        path: '/join',
        builder: (context, state) => RegisterScreen(
          auth: authService,
          userService: userService,
          token: state.uri.queryParameters['token'] ?? '',
        ),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) => ResetPasswordScreen(
          auth: authService,
          userService: userService,
          token: state.uri.queryParameters['token'],
        ),
      ),
      ShellRoute(
        builder: (_, __, child) => MainLayout(
          auth: authService,
          userService: userService,
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, __) => HomeScreen(
              api: apiClient,
            ),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, __) => SettingsScreen(userService: userService),
          ),
          ShellRoute(
            builder: (_, __, child) => AdminLayout(userService: userService, child: child),
            routes: [
              GoRoute(
                path: '/admin/users',
                builder: (_, __) => AdminUsersScreen(userService: userService),
              ),
              GoRoute(
                path: '/admin/invites',
                builder: (_, __) => AdminInvitesScreen(userService: userService),
              ),
              GoRoute(
                path: '/admin/groups',
                builder: (_, __) => AdminGroupsScreen(userService: userService),
              ),
              GoRoute(
                path: '/admin/roles',
                builder: (_, __) => AdminRolesScreen(userService: userService),
              ),
              GoRoute(
                path: '/admin/settings',
                builder: (_, __) => AdminSettingsScreen(userService: userService),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
