import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const Color _accent = Color(0xFFE94560);
const Color _bg = Color(0xFF0F0F1A);

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  bool _isYearly = true;

  static const List<Map<String, dynamic>> _features = [
    {'icon': Icons.auto_awesome_rounded, 'text': 'AI companion — ask anything about your book'},
    {'icon': Icons.explore_rounded, 'text': 'Smart recommendations based on what you love'},
    {'icon': Icons.cloud_sync_rounded, 'text': 'Sync your library across all your devices'},
    {'icon': Icons.insights_rounded, 'text': 'Advanced stats — streaks, reading speed, trends'},
    {'icon': Icons.palette_rounded, 'text': 'Exclusive premium reading themes'},
    {'icon': Icons.flag_rounded, 'text': 'Set reading goals and track them'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: IconButton(
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/library');
                    }
                  },
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white54, size: 24),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    const Icon(Icons.auto_stories_rounded,
                        size: 48, color: _accent),
                    const SizedBox(height: 16),
                    const Text(
                      'Reverie Pro',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'For the reader who lives in books',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Features
                    ...List.generate(_features.length, (i) {
                      final feature = _features[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: _accent.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                feature['icon'] as IconData,
                                color: _accent,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                feature['text'] as String,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 24),

                    // Plan cards
                    Row(
                      children: [
                        Expanded(
                            child: _buildPlanCard(
                          title: 'Monthly',
                          subtitle: 'Less than one coffee',
                          price: '\$1.99',
                          period: '/month',
                          isSelected: !_isYearly,
                          onTap: () => setState(() => _isYearly = false),
                        )),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _buildPlanCard(
                          title: 'Yearly · Save 37%',
                          subtitle: 'Just \$1.25/month',
                          price: '\$14.99',
                          period: '/year',
                          isSelected: _isYearly,
                          isBestValue: true,
                          onTap: () => setState(() => _isYearly = true),
                        )),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // Subscribe button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content:
                                  Text('Subscriptions coming soon!'),
                              backgroundColor: _accent,
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Try Free for 7 Days',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isYearly
                          ? 'Then \$14.99/year · Cancel anytime'
                          : 'Then \$1.99/month · Cancel anytime',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Restore purchases
                    TextButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Restore coming soon')),
                        );
                      },
                      child: Text(
                        'Restore purchases',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Philosophy note
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Text(
                        'Reverie will always be free to read unlimited books.\n'
                        'Pro unlocks features that make reading even better.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 12,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard({
    required String title,
    required String subtitle,
    required String price,
    required String period,
    required bool isSelected,
    bool isBestValue = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isSelected && isBestValue
              ? _accent.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.05),
          border: Border.all(
            color: isSelected
                ? (isBestValue
                    ? _accent.withValues(alpha: 0.8)
                    : Colors.white.withValues(alpha: 0.4))
                : Colors.white.withValues(alpha: 0.15),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  price,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                Text(
                  period,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: isBestValue
                        ? _accent
                        : Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            if (isBestValue)
              Positioned(
                top: -8,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'BEST VALUE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
