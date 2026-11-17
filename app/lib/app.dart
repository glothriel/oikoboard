import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'core/backend.dart';
import 'core/login_screen.dart';
import 'core/onboarding_screen.dart';
import 'core/server_screen.dart';
import 'core/session.dart';
import 'core/shell.dart';
import 'core/wall.dart';
import 'modules/registry.dart';

ThemeData _theme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF2E7D6B),
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: scheme,
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
  );
}

class OikoboardApp extends ConsumerWidget {
  const OikoboardApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final invite = ref.watch(pendingInviteProvider);
    final noServer =
        ref.watch(serverChoiceProvider) && ref.watch(serverUrlProvider) == null;
    if (noServer ||
        session == null ||
        !session.hasHousehold ||
        invite != null) {
      return MaterialApp(
        title: 'Oikoboard',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        locale: _locale,
        supportedLocales: const [_locale],
        localizationsDelegates: _delegates,
        home: noServer
            ? const ServerScreen()
            : session == null
            ? const LoginScreen()
            : const OnboardingScreen(),
      );
    }
    // Inna osoba lub inna rodzina = nowy router od ekranu głównego.
    return _LoggedInApp(key: ValueKey('${session.token}/${session.memberId}'));
  }
}

class _LoggedInApp extends StatefulWidget {
  const _LoggedInApp({super.key});

  @override
  State<_LoggedInApp> createState() => _LoggedInAppState();
}

class _LoggedInAppState extends State<_LoggedInApp> {
  final _router = _buildRouter();

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Oikoboard',
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      locale: _locale,
      supportedLocales: const [_locale],
      localizationsDelegates: _delegates,
    );
  }
}

const _locale = Locale('pl');
const _delegates = [
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

GoRouter _buildRouter() => GoRouter(
  initialLocation: '/',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(navigationShell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/', builder: (context, state) => const WallScreen()),
          ],
        ),
        for (final m in modules)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: m.path,
                builder: (context, state) => m.buildScreen(context),
                routes: m.subRoutes,
              ),
            ],
          ),
      ],
    ),
  ],
);
