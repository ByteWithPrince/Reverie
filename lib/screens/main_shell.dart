import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const Color _accent = Color(0xFFE94560);

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MAIN SHELL — bottom navigation bar
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  static int _calculateIndex(BuildContext context) {
    final location =
        GoRouterState.of(context).uri.toString();
    if (location.startsWith('/discover')) return 1;
    if (location.startsWith('/profile')) return 2;
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/library');
        break;
      case 1:
        context.go('/discover');
        break;
      case 2:
        context.go('/profile');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = scheme.onSurface.withValues(alpha: 0.4);
    final currentIndex = _calculateIndex(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        height: 64,
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(
            top: BorderSide(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.08),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(
              icon: Icons.auto_stories_rounded,
              index: 0,
              currentIndex: currentIndex,
              muted: muted,
              onTap: () => _onTap(context, 0),
            ),
            _navItem(
              icon: Icons.explore_rounded,
              index: 1,
              currentIndex: currentIndex,
              muted: muted,
              onTap: () => _onTap(context, 1),
            ),
            _navItem(
              icon: Icons.person_rounded,
              index: 2,
              currentIndex: currentIndex,
              muted: muted,
              onTap: () => _onTap(context, 2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem({
    required IconData icon,
    required int index,
    required int currentIndex,
    required Color muted,
    required VoidCallback onTap,
  }) {
    final isActive = index == currentIndex;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 60,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isActive ? _accent : muted,
              size: isActive ? 26 : 24,
            ),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: isActive ? 4 : 0,
              height: 4,
              decoration: BoxDecoration(
                color: _accent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
