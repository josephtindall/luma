import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'services/auth_service.dart';
import 'services/api_client.dart';
import 'services/page_service.dart';
import 'services/theme_notifier.dart';
import 'services/user_service.dart';
import 'screens/setup/setup_wizard_screen.dart';
import 'screens/login/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/pages/vault_pages_screen.dart';
import 'screens/pages/page_editor_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/settings/settings_layout.dart';
import 'screens/admin/admin_layout.dart';
import 'screens/admin/admin_users_screen.dart';
import 'screens/admin/admin_user_detail_screen.dart';
import 'screens/admin/admin_invites_screen.dart';
import 'screens/admin/admin_settings_screen.dart';
import 'screens/admin/admin_groups_screen.dart';
import 'screens/admin/admin_group_detail_screen.dart';
import 'screens/admin/admin_roles_screen.dart';
import 'screens/admin/admin_role_detail_screen.dart';
import 'screens/admin/admin_events_screen.dart';
import 'screens/admin/admin_vaults_screen.dart';
import 'models/user.dart';
import 'models/group.dart';
import 'models/custom_role.dart';
import 'screens/pages/vault_settings_screen.dart';
import 'screens/register/register_screen.dart';
import 'screens/auth/reset_password_screen.dart';
import 'screens/auth/recovery_code_screen.dart';
import 'screens/main_layout.dart';

GoRouter buildRouter(
  AuthService authService,
  ApiClient apiClient,
  UserService userService,
  ThemeNotifier themeNotifier,
  PageService pageService,
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

      // Recovery token pending — gate to recovery-code screen after login.
      if (authService.recoveryTokenPending) {
        return state.uri.path == '/recovery-code' ? null : '/recovery-code';
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
          state.uri.path == '/reset-password' ||
          state.uri.path == '/recovery-code') {
        return '/home';
      }

      // Guard admin routes — redirect to /home if user has no admin capabilities.
      if (state.uri.path.startsWith('/admin') &&
          userService.profile != null &&
          !userService.hasAnyAdminAccess) {
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
      GoRoute(
        path: '/recovery-code',
        builder: (_, __) => RecoveryCodeScreen(auth: authService),
      ),
      ShellRoute(
        builder: (_, __, child) => MainLayout(
          auth: authService,
          userService: userService,
          themeNotifier: themeNotifier,
          pageService: pageService,
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
            path: '/vaults/:slug',
            builder: (_, state) => VaultPagesScreen(
              slug: state.pathParameters['slug']!,
              pageService: pageService,
            ),
          ),
          GoRoute(
            path: '/vaults/:slug/settings',
            builder: (_, state) => VaultSettingsScreen(
              slug: state.pathParameters['slug']!,
              pageService: pageService,
            ),
          ),
          GoRoute(
            path: '/pages/:shortId',
            builder: (_, state) => PageEditorScreen(
              shortId: state.pathParameters['shortId']!,
              pageService: pageService,
            ),
          ),
          GoRoute(
            path: '/settings',
            redirect: (_, __) => '/settings/profile',
          ),
          ShellRoute(
            builder: (_, __, child) => SettingsLayout(child: child),
            routes: [
              GoRoute(
                path: '/settings/profile',
                builder: (_, __) =>
                    SettingsProfileTab(userService: userService),
              ),
              GoRoute(
                path: '/settings/security',
                builder: (_, __) =>
                    SettingsSecurityTab(userService: userService),
              ),
              GoRoute(
                path: '/settings/activity',
                builder: (_, __) =>
                    SettingsActivityTab(userService: userService),
              ),
            ],
          ),
          ShellRoute(
            builder: (_, __, child) =>
                AdminLayout(userService: userService, child: child),
            routes: [
              GoRoute(
                path: '/admin/users',
                builder: (_, __) => AdminUsersScreen(userService: userService),
              ),
              GoRoute(
                path: '/admin/users/:id',
                builder: (_, state) {
                  final user = state.extra as AdminUserRecord?;
                  return AdminUserDetailScreen(
                    userService: userService,
                    user: user,
                    isSelf: user != null &&
                        userService.profile?.id == user.id,
                  );
                },
              ),
              GoRoute(
                path: '/admin/invites',
                builder: (_, __) =>
                    AdminInvitesScreen(userService: userService),
              ),
              GoRoute(
                path: '/admin/groups',
                builder: (_, __) => AdminGroupsScreen(userService: userService),
              ),
              GoRoute(
                path: '/admin/groups/:id',
                builder: (_, state) => AdminGroupDetailScreen(
                  userService: userService,
                  group: state.extra as GroupRecord?,
                ),
              ),
              GoRoute(
                path: '/admin/roles',
                builder: (_, __) => AdminRolesScreen(userService: userService),
              ),
              GoRoute(
                path: '/admin/roles/:id',
                builder: (_, state) => AdminRoleDetailScreen(
                  userService: userService,
                  roleId: state.pathParameters['id']!,
                  role: state.extra as CustomRoleRecord?,
                ),
              ),
              GoRoute(
                path: '/admin/settings',
                builder: (_, __) =>
                    AdminSettingsScreen(userService: userService),
              ),
              GoRoute(
                path: '/admin/events',
                builder: (_, __) =>
                    AdminEventsScreen(userService: userService),
              ),
              GoRoute(
                path: '/admin/vaults',
                builder: (_, __) =>
                    AdminVaultsScreen(userService: userService),
              ),
              GoRoute(
                path: '/admin/vaults/:id/settings',
                builder: (_, state) => VaultSettingsScreen(
                  vaultId: state.pathParameters['id']!,
                  pageService: pageService,
                  userService: userService,
                  adminMode: true,
                ),
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
