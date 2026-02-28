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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
