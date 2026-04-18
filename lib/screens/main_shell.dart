import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

const Color _accent = Color(0xFFE94560);

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MAIN SHELL — floating pill-style bottom nav
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  static int _calculateIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    if (location.startsWith('/discover')) return 1;
    if (location.startsWith('/profile')) return 2;
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    HapticFeedback.lightImpact();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentIndex = _calculateIndex(context);

    return Scaffold(
      body: Stack(
        children: [
          // Current tab content
          child,
          // Floating nav bar
          Positioned(
            bottom: 20,
            left: 24,
            right: 24,
            child: _buildFloatingNavBar(context, isDark, currentIndex),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingNavBar(
    BuildContext context,
    bool isDark,
    int currentIndex,
  ) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1a1a2e) : const Color(0xFFffffff),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
          width: 0.5,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(
            icon: Icons.auto_stories_rounded,
            isActive: currentIndex == 0,
            onTap: () => _onTap(context, 0),
          ),
          _NavItem(
            icon: Icons.explore_rounded,
            isActive: currentIndex == 1,
            onTap: () => _onTap(context, 1),
          ),
          _NavItem(
            icon: Icons.person_rounded,
            isActive: currentIndex == 2,
            onTap: () => _onTap(context, 2),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFFe94560).withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Icon(
          icon,
          size: 24,
          color: isActive
              ? const Color(0xFFe94560)
              : Colors.grey.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
