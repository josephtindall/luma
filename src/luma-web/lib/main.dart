import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'services/auth_service.dart';
import 'services/api_client.dart';
import 'services/user_service.dart';
import 'router.dart';

void main() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();

  const baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:8002',
  );

  final authService = AuthService(baseUrl);
  final apiClient = ApiClient(authService);
  final userService = UserService(apiClient);

  authService.onSessionCleared = userService.clear;

  await authService.initialize();

  if (authService.isLoggedIn) {
    await Future.wait([
      userService.loadProfile(),
      userService.loadPreferences(),
    ]);
  }

  runApp(LumaApp(
    authService: authService,
    apiClient: apiClient,
    userService: userService,
  ));
}

const _seedColor = Color(0xFF1A3A5C);

class LumaApp extends StatelessWidget {
  final AuthService authService;
  final ApiClient apiClient;
  final UserService userService;

  const LumaApp({
    super.key,
    required this.authService,
    required this.apiClient,
    required this.userService,
  });

  @override
  Widget build(BuildContext context) {
    final router = buildRouter(authService, apiClient, userService);

    return ListenableBuilder(
      listenable: userService,
      builder: (context, _) {
        final themeMode = _resolveThemeMode(userService.preferences?.theme);

        return MaterialApp.router(
          title: 'Luma',
          themeMode: themeMode,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: _seedColor,
              brightness: Brightness.light,
              surface: const Color(0xFFFAFAFB),
            ),
            scaffoldBackgroundColor: const Color(0xFFFAFAFB),
            cardTheme: const CardThemeData(
              color: Colors.white,
              elevation: 1,
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: _seedColor,
              brightness: Brightness.dark,
              surface: const Color(0xFF1D1D20),
            ),
            scaffoldBackgroundColor: const Color(0xFF1D1D20),
            cardTheme: const CardThemeData(
              color: Color(0xFF222226),
              elevation: 1,
            ),
            useMaterial3: true,
          ),
          routerConfig: router,
        );
      },
    );
  }

  static ThemeMode _resolveThemeMode(String? theme) {
    return switch (theme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }
}
