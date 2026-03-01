import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'services/auth_service.dart';
import 'services/api_client.dart';
import 'services/user_service.dart';
import 'screens/setup/setup_wizard_screen.dart';
import 'screens/login/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/settings/settings_screen.dart';

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

      if (!authService.isLoggedIn) {
        return state.uri.path == '/login' ? null : '/login';
      }

      // Logged in — bounce away from login/setup
      if (state.uri.path == '/login' || state.uri.path == '/setup') {
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
        builder: (_, __) => SetupWizardScreen(auth: authService, userService: userService),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => LoginScreen(
          auth: authService,
          userService: userService,
        ),
      ),
      GoRoute(
        path: '/home',
        builder: (_, __) => HomeScreen(
          api: apiClient,
          auth: authService,
          userService: userService,
        ),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, __) => SettingsScreen(userService: userService),
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
