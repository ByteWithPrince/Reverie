import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SPLASH SCREEN — animated logo reveal
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _iconController;
  late final AnimationController _titleController;
  late final AnimationController _taglineController;
  late final Animation<double> _iconOpacity;
  late final Animation<double> _titleOpacity;
  late final Animation<double> _taglineOpacity;
  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();

    // Icon: fade in 0→1, 600ms
    _iconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _iconOpacity = CurvedAnimation(
      parent: _iconController,
      curve: Curves.easeInOut,
    );

    // Title: fade in 0→1, 800ms, starts after 400ms
    _titleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _titleOpacity = CurvedAnimation(
      parent: _titleController,
      curve: Curves.easeInOut,
    );

    // Tagline: fade in 0→1, 600ms, starts after 1000ms
    _taglineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _taglineOpacity = CurvedAnimation(
      parent: _taglineController,
      curve: Curves.easeInOut,
    );

    // Start sequential animations
    _iconController.forward();

    Future<void>.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _titleController.forward();
    });

    Future<void>.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) _taglineController.forward();
    });

    // Navigate after 3 seconds
    _navigationTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) _navigate();
    });
  }

  Future<void> _navigate() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool hasSeenOnboarding =
          prefs.getBool('hasSeenOnboarding') ?? false;
      if (mounted) {
        if (hasSeenOnboarding) {
          bool isLoggedIn = false;
          try {
            final session = Supabase.instance.client.auth.currentSession;
            isLoggedIn = session != null;
          } catch (_) {}
          if (isLoggedIn) {
            context.go('/library');
          } else {
            context.go('/auth');
          }
        } else {
          context.go('/onboarding');
        }
      }
    } catch (_) {
      if (mounted) context.go('/library');
    }
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _iconController.dispose();
    _titleController.dispose();
    _taglineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Icon
            FadeTransition(
              opacity: _iconOpacity,
              child: const Icon(
                Icons.auto_stories_rounded,
                size: 56,
                color: Color(0xFFE94560),
              ),
            ),
            const SizedBox(height: 20),

            // Title
            FadeTransition(
              opacity: _titleOpacity,
              child: Text(
                'Reverie',
                style: GoogleFonts.cormorantGaramond(
                  fontSize: 44,
                  fontWeight: FontWeight.w300,
                  color: Colors.white,
                  letterSpacing: 8,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Tagline
            FadeTransition(
              opacity: _taglineOpacity,
              child: Text(
                'Read freely',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.5),
                  letterSpacing: 3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
