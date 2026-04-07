import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:reverie/providers/pro_provider.dart';
import 'package:reverie/screens/library_screen.dart';
import 'package:reverie/services/streak_service.dart';
import 'package:reverie/services/supabase_service.dart';
import 'package:reverie/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Color _accent = Color(0xFFE94560);

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  int _totalBooks = 0;
  int _totalReadingMinutes = 0;
  int _currentStreak = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final streak = await StreakService.getCurrentStreak();
      if (mounted) {
        setState(() {
          _totalReadingMinutes =
              prefs.getInt('total_reading_minutes') ?? 0;
          _currentStreak = streak;
        });
      }
    } catch (_) {}
  }

  String _formatTime(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = scheme.onSurface.withValues(alpha: 0.5);
    final isPro = ref.watch(isProProvider);
    final books = ref.watch(libraryBooksProvider);
    _totalBooks = books.length;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            const SizedBox(height: 8),

            // User identity
            Center(
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SupabaseService.isLoggedIn
                          ? const LinearGradient(
                              colors: [Color(0xFFe94560), Color(0xFF7c6af7)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: SupabaseService.isLoggedIn
                          ? null
                          : muted.withValues(alpha: 0.15),
                    ),
                    child: Center(
                      child: SupabaseService.isLoggedIn
                          ? Text(
                              SupabaseService.displayName.isNotEmpty
                                  ? SupabaseService.displayName[0]
                                      .toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w300),
                            )
                          : Icon(Icons.person_rounded,
                              color: muted, size: 36),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    SupabaseService.isLoggedIn
                        ? SupabaseService.displayName.isNotEmpty
                            ? SupabaseService.displayName
                            : 'Reader'
                        : 'Reader',
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (SupabaseService.isLoggedIn &&
                      SupabaseService.userEmail != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      SupabaseService.userEmail!,
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (!SupabaseService.isLoggedIn)
                    ElevatedButton(
                      onPressed: () => context.push('/auth'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 8),
                      ),
                      child: const Text('Sign In'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Stats card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  _statItem('$_totalBooks', 'Books', scheme),
                  _divider(muted),
                  _statItem('$_currentStreak', 'Streak 🔥', scheme),
                  _divider(muted),
                  _statItem(
                      _formatTime(_totalReadingMinutes), 'Read', scheme),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Settings rows
            _sectionHeader('Settings', muted),
            const SizedBox(height: 8),
            _settingsRow(
              icon: Icons.tune_rounded,
              label: 'Reading preferences',
              onTap: () => context.push('/settings'),
              scheme: scheme,
              muted: muted,
            ),
            _settingsRow(
              icon: Icons.notifications_none_rounded,
              label: 'Notifications',
              onTap: () => _showComingSoon('Notifications'),
              scheme: scheme,
              muted: muted,
            ),
            _settingsRow(
              icon: Icons.storage_rounded,
              label: 'Storage & offline',
              onTap: () => _showComingSoon('Storage settings'),
              scheme: scheme,
              muted: muted,
            ),
            _settingsRow(
              icon: Icons.help_outline_rounded,
              label: 'Help & feedback',
              onTap: () => _showComingSoon('Help'),
              scheme: scheme,
              muted: muted,
            ),
            _settingsRow(
              icon: Icons.info_outline_rounded,
              label: 'About Reverie',
              onTap: () => _showAbout(),
              scheme: scheme,
              muted: muted,
            ),
            const SizedBox(height: 24),

            // Pro upgrade banner
            if (!isPro) ...[
              GestureDetector(
                onTap: () => context.push('/paywall'),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: _accent.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.auto_awesome_rounded,
                              color: _accent, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Unlock Reverie Pro',
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'AI companion · Smart recommendations · Cloud sync',
                        style: TextStyle(
                            color: muted, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'From \$1.99/month',
                        style: TextStyle(
                            color: _accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Theme toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Theme', style: TextStyle(color: muted, fontSize: 13)),
                const SizedBox(width: 12),
                Consumer(
                  builder: (ctx, ref, _) {
                    final mode = ref.watch(themeModeProvider);
                    final isDarkMode = mode == ThemeMode.dark;
                    return GestureDetector(
                      onTap: () {
                        ref.read(themeModeProvider.notifier).state =
                            isDarkMode ? ThemeMode.light : ThemeMode.dark;
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: muted.withValues(alpha: 0.1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isDarkMode
                                  ? Icons.dark_mode_rounded
                                  : Icons.light_mode_rounded,
                              size: 16,
                              color: scheme.onSurface,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isDarkMode ? 'Dark' : 'Light',
                              style: TextStyle(
                                  color: scheme.onSurface, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Sign out / Sign in
            Center(
              child: SupabaseService.isLoggedIn
                  ? TextButton(
                      onPressed: () async {
                        try {
                          await SupabaseService.signOut();
                          if (mounted) setState(() {});
                        } catch (_) {}
                      },
                      child: Text(
                        'Sign out',
                        style: TextStyle(
                            color: Colors.redAccent.withValues(alpha: 0.7),
                            fontSize: 14),
                      ),
                    )
                  : TextButton(
                      onPressed: () => context.push('/auth'),
                      child: const Text(
                        'Sign in',
                        style: TextStyle(color: _accent, fontSize: 14),
                      ),
                    ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _statItem(String value, String label, ColorScheme scheme) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  color: _accent, fontSize: 28, fontWeight: FontWeight.w300)),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.5),
                  fontSize: 12)),
        ],
      ),
    );
  }

  Widget _divider(Color muted) {
    return Container(
        width: 1, height: 36, color: muted.withValues(alpha: 0.2));
  }

  Widget _sectionHeader(String title, Color muted) {
    return Text(title,
        style: TextStyle(
            color: muted, fontSize: 12, fontWeight: FontWeight.w600));
  }

  Widget _settingsRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required ColorScheme scheme,
    required Color muted,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, color: muted, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style:
                      TextStyle(color: scheme.onSurface, fontSize: 15)),
            ),
            Icon(Icons.chevron_right_rounded, color: muted, size: 20),
          ],
        ),
      ),
    );
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature coming soon'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _showAbout() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reverie',
            style: TextStyle(color: Colors.white, fontSize: 22)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version 1.0.0',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 14)),
            const SizedBox(height: 8),
            Text(
              'A free, immersive EPUB reader for people '
              'who love books but cannot afford a Kindle.',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 13,
                  height: 1.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close',
                style: TextStyle(color: _accent)),
          ),
        ],
      ),
    );
  }
}
