import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'services/auth_service.dart';
import 'services/api_client.dart';
import 'services/page_service.dart';
import 'services/theme_notifier.dart';
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
  final pageService = PageService(apiClient);
  final themeNotifier = ThemeNotifier();

  authService.onSessionCleared = () {
    userService.clear();
    pageService.clear();
  };

  authService.onLogin = () {
    Future.wait([
      userService.loadProfile(),
      userService.loadPreferences(),
      pageService.loadVaults(),
    ]);
  };

  await authService.initialize();

  if (authService.isLoggedIn) {
    await Future.wait([
      userService.loadProfile(),
      userService.loadPreferences(),
      pageService.loadVaults(),
    ]);
  }

  runApp(LumaApp(
    authService: authService,
    apiClient: apiClient,
    userService: userService,
    pageService: pageService,
    themeNotifier: themeNotifier,
  ));
}

const _seedColor = Color(0xFF1A3A5C);

class LumaApp extends StatelessWidget {
  final AuthService authService;
  final ApiClient apiClient;
  final UserService userService;
  final PageService pageService;
  final ThemeNotifier themeNotifier;

  const LumaApp({
    super.key,
    required this.authService,
    required this.apiClient,
    required this.userService,
    required this.pageService,
    required this.themeNotifier,
  });

  @override
  Widget build(BuildContext context) {
    final router = buildRouter(
      authService,
      apiClient,
      userService,
      themeNotifier,
      pageService,
    );

    return ListenableBuilder(
      listenable: themeNotifier,
      builder: (context, _) {
        return MaterialApp.router(
          title: 'Luma',
          themeMode: themeNotifier.themeMode,
          localizationsDelegates: const [
            AppFlowyEditorLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales:
              AppFlowyEditorLocalizations.delegate.supportedLocales,
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
}
