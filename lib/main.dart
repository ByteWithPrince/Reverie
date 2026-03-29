import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:reverie/screens/auth_screen.dart';
import 'package:reverie/screens/library_screen.dart';
import 'package:reverie/screens/onboarding_screen.dart';
import 'package:reverie/screens/reader_screen.dart';
import 'package:reverie/screens/settings_screen.dart';
import 'package:reverie/screens/splash_screen.dart';
import 'package:reverie/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );

  try {
    await Supabase.initialize(
      url: 'https://hhvjrrektwmyzrhnnjbr.supabase.co',
      anonKey: 'sb_publishable_iBUypBygju5FJPcgH2gKFA_dOiVCpLX',
    );
  } catch (_) {
    // Supabase not configured yet — app works without auth
  }

  runApp(const ProviderScope(child: ReverieApp()));
}

final GoRouter _router = GoRouter(
  errorBuilder: (BuildContext context, GoRouterState state) =>
      const LibraryScreen(),
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (BuildContext context, GoRouterState state) =>
          const SplashScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (BuildContext context, GoRouterState state) =>
          const OnboardingScreen(),
    ),
    GoRoute(
      path: '/auth',
      builder: (BuildContext context, GoRouterState state) =>
          const AuthScreen(),
    ),
    GoRoute(
      path: '/library',
      builder: (BuildContext context, GoRouterState state) =>
          const LibraryScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (BuildContext context, GoRouterState state) =>
          const SettingsScreen(),
    ),
    GoRoute(
      path: '/reader',
      builder: (BuildContext context, GoRouterState state) {
        final String filePath = state.uri.queryParameters['path'] ?? '';
        if (filePath.isEmpty) {
          return const LibraryScreen();
        }
        return ReaderScreen(filePath: filePath);
      },
    ),
  ],
);

class ReverieApp extends ConsumerWidget {
  const ReverieApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      theme: AppTheme.paperTheme,
      darkTheme: AppTheme.midnightTheme,
      themeMode: themeMode,
    );
  }
}
