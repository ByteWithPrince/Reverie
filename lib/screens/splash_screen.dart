import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  double _opacity = 0;
  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();

    Future<void>.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() => _opacity = 1);
      }
    });

    _navigationTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) {
        context.go('/library');
      }
    });
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: AnimatedOpacity(
          opacity: _opacity,
          duration: const Duration(milliseconds: 1500),
          curve: Curves.easeInOut,
          child: const Text(
            'Reverie',
            style: TextStyle(
              color: Colors.white,
              fontSize: 42,
              fontFamily: 'serif',
              fontWeight: FontWeight.w500,
              letterSpacing: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}
