import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:google_fonts/google_fonts.dart';

import 'services/auth_service.dart';
import 'services/api_client.dart';
import 'services/page_service.dart';
import 'services/theme_notifier.dart';
import 'services/user_service.dart';
import 'theme/tokens.dart';
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

// ── Untitled UI color palette ────────────────────────────────────────────────

// Light palette — Monochrome primary (black buttons, white text)
const _lightPrimary            = Color(0xFF101828); // Near-black
const _lightOnPrimary          = Color(0xFFFFFFFF);
const _lightPrimaryContainer   = Color(0xFFEAECF0); // Gray 200
const _lightOnPrimaryContainer = Color(0xFF101828); // Near-black
const _lightSecondary          = Color(0xFF475467); // Gray 600
const _lightOnSecondary        = Color(0xFFFFFFFF);
const _lightSecondaryContainer = Color(0xFFF2F4F7); // Gray 100
const _lightOnSecondaryContainer = Color(0xFF344054); // Gray 700
const _lightTertiary           = Color(0xFF175CD3); // Blue 700
const _lightOnTertiary         = Color(0xFFFFFFFF);
const _lightTertiaryContainer  = Color(0xFFB2DDFF); // Blue 200
const _lightOnTertiaryContainer = Color(0xFF194185); // Blue 900
const _lightError              = Color(0xFFD92D20); // Error 600
const _lightOnError            = Color(0xFFFFFFFF);
const _lightErrorContainer     = Color(0xFFFEE4E2); // Error 100
const _lightOnErrorContainer   = Color(0xFFB42318); // Error 700
const _lightSurface            = Color(0xFFFFFFFF);
const _lightOnSurface          = Color(0xFF101828); // Gray 900
const _lightCHigh              = Color(0xFFF2F4F7); // Gray 100
const _lightC                  = Color(0xFFF9FAFB); // Gray 50
const _lightCLow               = Color(0xFFFCFCFD); // Gray 25
const _lightCLowest            = Color(0xFFFFFFFF);
const _lightCHighest           = Color(0xFFEAECF0); // Gray 200
const _lightOnSurfaceVariant   = Color(0xFF475467); // Gray 600
const _lightOutline            = Color(0xFF98A2B3); // Gray 400
const _lightOutlineVariant     = Color(0xFFEAECF0); // Gray 200

// Dark palette — MacOS Slate inspired
const _darkPrimary             = Color(0xFFF2F2F7); // Near-white text/buttons
const _darkOnPrimary           = Color(0xFF1C1C1E); // Slate black
const _darkPrimaryContainer    = Color(0xFF2C2C2E); // System Gray 5
const _darkOnPrimaryContainer  = Color(0xFFF2F2F7); 
const _darkSecondary           = Color(0xFFAEAEB2); // System Gray 2
const _darkOnSecondary         = Color(0xFF1C1C1E);
const _darkSecondaryContainer  = Color(0xFF242426); // Surface variant
const _darkOnSecondaryContainer= Color(0xFFF2F2F7);
const _darkTertiary            = Color(0xFF53B1FD); // Blue accent
const _darkOnTertiary          = Color(0xFF194185);
const _darkTertiaryContainer   = Color(0xFF1849A9);
const _darkOnTertiaryContainer = Color(0xFFB2DDFF);
const _darkError               = Color(0xFFFF453A); // Apple Red
const _darkOnError             = Color(0xFF4A0F0D);
const _darkErrorContainer      = Color(0xFF3B1210);
const _darkOnErrorContainer    = Color(0xFFFFD4D1);
const _darkSurface             = Color(0xFF1C1C1E); // System Gray 6 (Main background)
const _darkOnSurface           = Color(0xFFF2F2F7); 
const _darkCHigh               = Color(0xFF242426);
const _darkC                   = Color(0xFF1C1C1E);
const _darkCLow                = Color(0xFF161618);
const _darkCLowest             = Color(0xFF121214); // Near-black slate
const _darkCHighest            = Color(0xFF2C2C2E);
const _darkOnSurfaceVariant    = Color(0xFFAEAEB2); // System Gray 2
const _darkOutline             = Color(0xFF48484A); // System Gray 3
const _darkOutlineVariant      = Color(0xFF3A3A3C); // System Gray 4

ThemeData _buildTheme(Brightness brightness) {
  final isLight = brightness == Brightness.light;

  final colorScheme = ColorScheme(
    brightness: brightness,
    primary:                isLight ? _lightPrimary                : _darkPrimary,
    onPrimary:              isLight ? _lightOnPrimary              : _darkOnPrimary,
    primaryContainer:       isLight ? _lightPrimaryContainer       : _darkPrimaryContainer,
    onPrimaryContainer:     isLight ? _lightOnPrimaryContainer     : _darkOnPrimaryContainer,
    secondary:              isLight ? _lightSecondary              : _darkSecondary,
    onSecondary:            isLight ? _lightOnSecondary            : _darkOnSecondary,
    secondaryContainer:     isLight ? _lightSecondaryContainer     : _darkSecondaryContainer,
    onSecondaryContainer:   isLight ? _lightOnSecondaryContainer   : _darkOnSecondaryContainer,
    tertiary:               isLight ? _lightTertiary               : _darkTertiary,
    onTertiary:             isLight ? _lightOnTertiary             : _darkOnTertiary,
    tertiaryContainer:      isLight ? _lightTertiaryContainer      : _darkTertiaryContainer,
    onTertiaryContainer:    isLight ? _lightOnTertiaryContainer    : _darkOnTertiaryContainer,
    error:                  isLight ? _lightError                  : _darkError,
    onError:                isLight ? _lightOnError                : _darkOnError,
    errorContainer:         isLight ? _lightErrorContainer         : _darkErrorContainer,
    onErrorContainer:       isLight ? _lightOnErrorContainer       : _darkOnErrorContainer,
    surface:                isLight ? _lightSurface                : _darkSurface,
    onSurface:              isLight ? _lightOnSurface              : _darkOnSurface,
    surfaceContainerHighest:isLight ? _lightCHighest               : _darkCHighest,
    surfaceContainerHigh:   isLight ? _lightCHigh                  : _darkCHigh,
    surfaceContainer:       isLight ? _lightC                      : _darkC,
    surfaceContainerLow:    isLight ? _lightCLow                   : _darkCLow,
    surfaceContainerLowest: isLight ? _lightCLowest                : _darkCLowest,
    onSurfaceVariant:       isLight ? _lightOnSurfaceVariant       : _darkOnSurfaceVariant,
    outline:                isLight ? _lightOutline                : _darkOutline,
    outlineVariant:         isLight ? _lightOutlineVariant         : _darkOutlineVariant,
    shadow:                 isLight ? const Color(0xFF101828)      : Colors.black,
    scrim:                  Colors.black,
    inverseSurface:         isLight ? const Color(0xFF101828)      : const Color(0xFFE0E0E0),
    onInverseSurface:       isLight ? Colors.white                 : const Color(0xFF1A1A1A),
    inversePrimary:         isLight ? _darkPrimary                 : _lightPrimary,
    surfaceTint:            Colors.transparent,
  );

  final scaffoldBg = isLight ? const Color(0xFFF9FAFB) : const Color(0xFF121212);
  final borderColor = isLight ? const Color(0xFFD0D5DD) : _darkOutlineVariant; // Gray 300 / dark border
  final onSurface = isLight ? _lightOnSurface : _darkOnSurface;
  final onSurfaceVariant = isLight ? _lightOnSurfaceVariant : _darkOnSurfaceVariant;

  final baseTextTheme = GoogleFonts.interTextTheme(
    ThemeData(brightness: brightness).textTheme,
  );

  final textTheme = baseTextTheme.copyWith(
    displayLarge:  GoogleFonts.inter(fontSize: 48, height: 60 / 48, fontWeight: FontWeight.w600, color: onSurface),
    displayMedium: GoogleFonts.inter(fontSize: 36, height: 44 / 36, fontWeight: FontWeight.w600, color: onSurface),
    displaySmall:  GoogleFonts.inter(fontSize: 30, height: 38 / 30, fontWeight: FontWeight.w600, color: onSurface),
    headlineLarge: GoogleFonts.inter(fontSize: 24, height: 32 / 24, fontWeight: FontWeight.w600, color: onSurface),
    headlineMedium:GoogleFonts.inter(fontSize: 20, height: 30 / 20, fontWeight: FontWeight.w600, color: onSurface),
    headlineSmall: GoogleFonts.inter(fontSize: 18, height: 28 / 18, fontWeight: FontWeight.w600, color: onSurface),
    titleLarge:    GoogleFonts.inter(fontSize: 18, height: 28 / 18, fontWeight: FontWeight.w600, color: onSurface),
    titleMedium:   GoogleFonts.inter(fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w500, color: onSurface),
    titleSmall:    GoogleFonts.inter(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500, color: onSurface),
    bodyLarge:     GoogleFonts.inter(fontSize: 18, height: 28 / 18, fontWeight: FontWeight.w400, color: onSurface),
    bodyMedium:    GoogleFonts.inter(fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w400, color: onSurface),
    bodySmall:     GoogleFonts.inter(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w400, color: onSurface),
    labelLarge:    GoogleFonts.inter(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500, color: onSurface),
    labelMedium:   GoogleFonts.inter(fontSize: 12, height: 18 / 12, fontWeight: FontWeight.w500, color: onSurfaceVariant),
    labelSmall:    GoogleFonts.inter(fontSize: 12, height: 18 / 12, fontWeight: FontWeight.w500, color: onSurfaceVariant),
  );

  return ThemeData(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: scaffoldBg,
    useMaterial3: true,

    // ── Typography ────────────────────────────────────────────────────────────
    textTheme: textTheme,

    // ── App bar ───────────────────────────────────────────────────────────────
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: isLight ? Colors.white : const Color(0xFF1A1A1A),
      foregroundColor: onSurface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      titleTextStyle: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
    ),

    // ── Cards ─────────────────────────────────────────────────────────────────
    cardTheme: CardThemeData(
      color: isLight ? Colors.white : const Color(0xFF1A1A1A),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: LumaRadius.radiusLg,
        side: BorderSide(color: borderColor),
      ),
      margin: EdgeInsets.zero,
    ),

    // ── Buttons ───────────────────────────────────────────────────────────────
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const RoundedRectangleBorder(borderRadius: LumaRadius.radiusMd),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const Size(0, 40),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const RoundedRectangleBorder(borderRadius: LumaRadius.radiusMd),
        side: BorderSide(color: borderColor),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const Size(0, 40),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: const RoundedRectangleBorder(borderRadius: LumaRadius.radiusMd),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: const RoundedRectangleBorder(borderRadius: LumaRadius.radiusMd),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const Size(0, 40),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: const RoundedRectangleBorder(borderRadius: LumaRadius.radiusMd),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),

    // ── Input fields ──────────────────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: LumaRadius.radiusMd,
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: LumaRadius.radiusMd,
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: LumaRadius.radiusMd,
        borderSide: BorderSide(
          color: isLight ? _lightPrimary : _darkPrimary,
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: LumaRadius.radiusMd,
        borderSide: BorderSide(
          color: isLight ? _lightError : _darkError,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: LumaRadius.radiusMd,
        borderSide: BorderSide(
          color: isLight ? _lightError : _darkError,
          width: 1.5,
        ),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: LumaRadius.radiusMd,
        borderSide: BorderSide(color: borderColor.withAlpha(100)),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      isDense: false,
      hintStyle: GoogleFonts.inter(color: onSurfaceVariant.withAlpha(160)),
      labelStyle: GoogleFonts.inter(color: onSurfaceVariant),
    ),

    // ── Chips ─────────────────────────────────────────────────────────────────
    chipTheme: ChipThemeData(
      shape: const RoundedRectangleBorder(borderRadius: LumaRadius.radiusSm),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      side: isLight ? BorderSide.none : BorderSide(color: borderColor),
      backgroundColor:
          isLight ? const Color(0xFFF2F4F7) : _darkCHighest,
    ),

    // ── Dividers ──────────────────────────────────────────────────────────────
    dividerTheme: DividerThemeData(
      color: borderColor,
      thickness: 1,
      space: 1,
    ),

    // ── List tiles ────────────────────────────────────────────────────────────
    listTileTheme: ListTileThemeData(
      dense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      titleTextStyle: GoogleFonts.inter(fontSize: 14, color: onSurface),
      subtitleTextStyle: GoogleFonts.inter(fontSize: 12, color: onSurfaceVariant),
    ),

    // ── Segmented buttons ───────────────────────────────────────────────────
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: LumaRadius.radiusMd),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12),
        ),
      ),
    ),

    // ── Dialogs ───────────────────────────────────────────────────────────────
    dialogTheme: DialogThemeData(
      shape: const RoundedRectangleBorder(borderRadius: LumaRadius.radiusLg),
      elevation: 6,
      surfaceTintColor: Colors.transparent,
      backgroundColor: isLight ? Colors.white : const Color(0xFF202020),
    ),

    // ── Tooltips ──────────────────────────────────────────────────────────────
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: isLight
            ? const Color(0xFF101828)
            : const Color(0xFF2E2E2E),
        borderRadius: LumaRadius.radiusMd,
        border: isLight
            ? null
            : Border.all(color: _darkOutline),
      ),
      textStyle: GoogleFonts.inter(
          color: Colors.white, fontSize: 12, fontWeight: FontWeight.w400),
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      waitDuration: const Duration(milliseconds: 400),
    ),

    // ── Popup/dropdown menus ──────────────────────────────────────────────────
    popupMenuTheme: PopupMenuThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: LumaRadius.radiusMd,
        side: BorderSide(color: borderColor),
      ),
      elevation: 4,
      surfaceTintColor: Colors.transparent,
      color: isLight ? Colors.white : const Color(0xFF202020),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: LumaRadius.radiusMd,
            side: BorderSide(color: borderColor),
          ),
        ),
        elevation: const WidgetStatePropertyAll(4),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        backgroundColor: WidgetStatePropertyAll(
          isLight ? Colors.white : const Color(0xFF202020),
        ),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: LumaRadius.radiusMd,
          borderSide: BorderSide(color: borderColor),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        isDense: false,
      ),
    ),

    // ── Switches & checkboxes ─────────────────────────────────────────────────
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        return null;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return isLight ? _lightPrimary : _darkPrimary;
        }
        return null;
      }),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4))),
      side: BorderSide(color: borderColor, width: 1.5),
    ),

    // ── Scrollbar ─────────────────────────────────────────────────────────────
    scrollbarTheme: ScrollbarThemeData(
      radius: const Radius.circular(2),
      thickness: const WidgetStatePropertyAll(4),
      thumbColor: WidgetStatePropertyAll(
        onSurfaceVariant.withAlpha(80),
      ),
    ),

    // ── Expansion tile ────────────────────────────────────────────────────────
    expansionTileTheme: ExpansionTileThemeData(
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
    ),
  );
}

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
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          routerConfig: router,
        );
      },
    );
  }
}
