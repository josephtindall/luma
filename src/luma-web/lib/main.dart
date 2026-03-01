import 'package:flutter/material.dart';

import 'services/auth_service.dart';
import 'services/api_client.dart';
import 'router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:8002',
  );

  final authService = AuthService(baseUrl);
  final apiClient = ApiClient(authService);

  await authService.initialize();

  runApp(LumaApp(authService: authService, apiClient: apiClient));
}

const _seedColor = Color(0xFF1A3A5C);

class LumaApp extends StatelessWidget {
  final AuthService authService;
  final ApiClient apiClient;

  const LumaApp({
    super.key,
    required this.authService,
    required this.apiClient,
  });

  @override
  Widget build(BuildContext context) {
    final router = buildRouter(authService, apiClient);

    return MaterialApp.router(
      title: 'Luma',
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
  }
}
