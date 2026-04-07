import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:reverie/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Color _accent = Color(0xFFE94560);
const Color _bg = Color(0xFF0F0F1A);

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isSignIn = true;
  bool _isLoading = false;
  String _errorMessage = '';
  bool _showPassword = false;
  StreamSubscription<AuthState>? _authSubscription;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    try {
      _authSubscription = SupabaseService.authStateChanges.listen((data) {
        final event = data.event;
        if (event == AuthChangeEvent.signedIn) {
          if (mounted) {
            context.go('/library');
          }
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      if (_isSignIn) {
        await SupabaseService.signInWithEmail(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await SupabaseService.signUpWithEmail(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          name: _nameController.text.trim(),
        );
      }

      if (mounted) {
        context.go('/library');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                _isSignIn ? 'Welcome back!' : 'Check your email to confirm!'),
            backgroundColor: _accent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = _parseAuthError(e.toString());
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _parseAuthError(String error) {
    if (error.contains('Invalid login credentials')) {
      return 'Wrong email or password. Please try again.';
    }
    if (error.contains('Email not confirmed')) {
      return 'Please check your email to confirm your account.';
    }
    if (error.contains('User already registered')) {
      return 'An account with this email already exists.';
    }
    if (error.contains('Password should be')) {
      return 'Password must be at least 6 characters.';
    }
    if (error.contains('network')) {
      return 'No internet connection. Please try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0x8AFFFFFF), fontSize: 14),
      hintStyle: const TextStyle(color: Color(0x61FFFFFF)),
      prefixIcon: Icon(icon, color: const Color(0x61FFFFFF), size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.07),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _accent, width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo
                  const Icon(Icons.auto_stories_rounded,
                      size: 52, color: _accent),
                  const SizedBox(height: 16),
                  Text(
                    'Reverie',
                    style: GoogleFonts.cormorantGaramond(
                      fontSize: 38,
                      fontWeight: FontWeight.w300,
                      color: Colors.white,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Read freely',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.38),
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 36),

                  // Mode switcher
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _modePill('Sign In', _isSignIn, () {
                          setState(() {
                            _isSignIn = true;
                            _errorMessage = '';
                          });
                        }),
                        _modePill('Sign Up', !_isSignIn, () {
                          setState(() {
                            _isSignIn = false;
                            _errorMessage = '';
                          });
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Name field (sign up only)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: _isSignIn ? 0 : 64,
                    curve: Curves.easeInOut,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _isSignIn ? 0.0 : 1.0,
                      child: SingleChildScrollView(
                        physics: const NeverScrollableScrollPhysics(),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TextField(
                            controller: _nameController,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 15),
                            textInputAction: TextInputAction.next,
                            decoration: _fieldDecoration(
                              label: 'Your name',
                              icon: Icons.person_outline,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Email field
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    style:
                        const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: _fieldDecoration(
                      label: 'Email address',
                      icon: Icons.email_outlined,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Password field
                  TextField(
                    controller: _passwordController,
                    obscureText: !_showPassword,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    style:
                        const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: _fieldDecoration(
                      label: 'Password',
                      icon: Icons.lock_outline,
                      suffix: IconButton(
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                          color: const Color(0x61FFFFFF),
                          size: 20,
                        ),
                        onPressed: () => setState(
                            () => _showPassword = !_showPassword),
                      ),
                    ),
                  ),

                  // Error message
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: _errorMessage.isEmpty ? 0 : null,
                    margin: EdgeInsets.only(
                        top: _errorMessage.isEmpty ? 0 : 16),
                    child: _errorMessage.isEmpty
                        ? const SizedBox.shrink()
                        : Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color:
                                      Colors.red.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              _errorMessage,
                              style: const TextStyle(
                                  color: Colors.redAccent, fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                          ),
                  ),
                  const SizedBox(height: 24),

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        disabledBackgroundColor:
                            _accent.withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : Text(
                              _isSignIn ? 'Sign In' : 'Create Account',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Skip
                  TextButton(
                    onPressed: () => context.go('/library'),
                    child: Text(
                      'Continue without account',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.38),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _modePill(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
        decoration: BoxDecoration(
          color: active ? _accent : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active
                ? Colors.white
                : Colors.white.withValues(alpha: 0.54),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
