import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:reverie/providers/pro_provider.dart';
import 'package:reverie/screens/library_screen.dart';
import 'package:reverie/services/goals_service.dart';
import 'package:reverie/services/streak_service.dart';
import 'package:reverie/services/supabase_service.dart';
import 'package:reverie/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Color _accent = Color(0xFFE94560);

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// READING BADGE MODEL
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class ReadingBadge {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final bool Function(int books, int minutes, int streak, int genres) isUnlocked;

  const ReadingBadge({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.isUnlocked,
  });

  static final List<ReadingBadge> allBadges = [
    ReadingBadge(
      id: 'first_book',
      name: 'First Chapter',
      description: 'Read your first book',
      icon: Icons.auto_stories_rounded,
      color: const Color(0xFF4a9eff),
      isUnlocked: (b, m, s, g) => b >= 1,
    ),
    ReadingBadge(
      id: 'night_owl',
      name: 'Night Owl',
      description: '10+ late night reads',
      icon: Icons.nightlight_rounded,
      color: const Color(0xFF7c6af7),
      isUnlocked: (b, m, s, g) => b >= 5,
    ),
    ReadingBadge(
      id: 'polymath',
      name: 'Polymath',
      description: '3+ different genres',
      icon: Icons.psychology_rounded,
      color: const Color(0xFFf7b731),
      isUnlocked: (b, m, s, g) => g >= 3,
    ),
    ReadingBadge(
      id: 'streak_week',
      name: 'Week Warrior',
      description: '7 day reading streak',
      icon: Icons.local_fire_department_rounded,
      color: const Color(0xFFe94560),
      isUnlocked: (b, m, s, g) => s >= 7,
    ),
    ReadingBadge(
      id: 'speed_reader',
      name: 'Speed Reader',
      description: '60+ minutes in one session',
      icon: Icons.bolt_rounded,
      color: const Color(0xFF2ec4b6),
      isUnlocked: (b, m, s, g) => m >= 60,
    ),
    ReadingBadge(
      id: 'bookworm',
      name: 'Bookworm',
      description: 'Read 10 books',
      icon: Icons.menu_book_rounded,
      color: const Color(0xFF43aa8b),
      isUnlocked: (b, m, s, g) => b >= 10,
    ),
    ReadingBadge(
      id: 'dedicated',
      name: 'Dedicated',
      description: '30 day streak',
      icon: Icons.stars_rounded,
      color: const Color(0xFFf7b731),
      isUnlocked: (b, m, s, g) => s >= 30,
    ),
    ReadingBadge(
      id: 'legend',
      name: 'Legend',
      description: 'Read 50 books',
      icon: Icons.workspace_premium_rounded,
      color: const Color(0xFFe94560),
      isUnlocked: (b, m, s, g) => b >= 50,
    ),
  ];
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// PROFILE SCREEN
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  int _totalBooks = 0;
  int _totalReadingMinutes = 0;
  int _currentStreak = 0;
  int _yearlyGoal = 12;
  List<int> _weeklyMinutes = List.filled(7, 0);

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final streak = await StreakService.getCurrentStreak();
      final goal = await GoalsService.loadGoal();
      final weekly = await _loadWeeklyMinutes(prefs);
      if (mounted) {
        setState(() {
          _totalReadingMinutes = prefs.getInt('total_reading_minutes') ?? 0;
          _currentStreak = streak;
          _yearlyGoal = goal.yearlyBooks;
          _weeklyMinutes = weekly;
        });
      }
    } catch (_) {}
  }

  Future<List<int>> _loadWeeklyMinutes(SharedPreferences prefs) async {
    try {
      final now = DateTime.now();
      // Find Monday of this week
      final monday = now.subtract(Duration(days: now.weekday - 1));
      final result = <int>[];
      for (int i = 0; i < 7; i++) {
        final day = monday.add(Duration(days: i));
        final key = DateFormat('yyyy-MM-dd').format(day);
        result.add(prefs.getInt('today_minutes_$key') ?? 0);
      }
      return result;
    } catch (_) {
      return List.filled(7, 0);
    }
  }

  String _getUserTitle(int books) {
    if (books >= 50) return 'CURATOR OF STORIES';
    if (books >= 30) return 'LITERARY EXPLORER';
    if (books >= 15) return 'BOOK ENTHUSIAST';
    if (books >= 5) return 'DEVOTED READER';
    return 'CURIOUS READER';
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
    final booksWithProgress =
        books.where((b) => b.readingProgress > 0.9).length;
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
    final surfaceColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.03);

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 100),
          children: [
            // SECTION 1 — User Identity
            _buildIdentitySection(scheme, muted, scaffoldBg),
            const SizedBox(height: 20),

            // SECTION 2 — Stats Row
            _buildStatsRow(scheme, muted, surfaceColor),
            const SizedBox(height: 16),

            // SECTION 3 — Weekly Chart
            _buildWeeklyChart(scheme, muted, surfaceColor, isDark),
            const SizedBox(height: 16),

            // SECTION 4 — Badges
            _buildBadgesSection(scheme, muted, surfaceColor, booksWithProgress),
            const SizedBox(height: 16),

            // SECTION 5 — Annual Goal
            _buildAnnualGoal(
              scheme, muted, surfaceColor, booksWithProgress,
            ),
            const SizedBox(height: 16),

            // Pro upgrade banner
            if (!isPro) _buildProBanner(scheme, muted),

            // Theme toggle
            _buildThemeToggle(scheme, muted),
            const SizedBox(height: 8),

            // SECTION 6 — Settings
            _buildSettingsSection(scheme, muted),
            const SizedBox(height: 16),

            // Sign out / Sign in
            _buildAuthButton(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ━━━ SECTION 1 — Identity ━━━

  Widget _buildIdentitySection(
    ColorScheme scheme,
    Color muted,
    Color scaffoldBg,
  ) {
    final name = SupabaseService.isLoggedIn
        ? (SupabaseService.displayName.isNotEmpty
            ? SupabaseService.displayName
            : 'Reader')
        : 'Reader';
    final title = _getUserTitle(_totalBooks);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Avatar with badge
          Stack(
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
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w300,
                          ),
                        )
                      : Icon(Icons.person_rounded, color: muted, size: 36),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF1a1a2e),
                    border: Border.all(color: scaffoldBg, width: 2),
                  ),
                  child: const Icon(
                    Icons.auto_stories_rounded,
                    size: 12,
                    color: _accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Name
          Text(
            name,
            style: GoogleFonts.cormorantGaramond(
              fontSize: 26,
              fontWeight: FontWeight.w400,
              color: scheme.onSurface,
            ),
          ),
          if (SupabaseService.isLoggedIn &&
              SupabaseService.userEmail != null) ...[
            const SizedBox(height: 4),
            Text(
              SupabaseService.userEmail!,
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 6),
          // Title
          Text(
            title,
            style: TextStyle(
              color: muted,
              fontSize: 11,
              letterSpacing: 2,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (!SupabaseService.isLoggedIn) ...[
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.push('/auth'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
              ),
              child: const Text('Sign In'),
            ),
          ],
        ],
      ),
    );
  }

  // ━━━ SECTION 2 — Stats Row ━━━

  Widget _buildStatsRow(ColorScheme scheme, Color muted, Color surfaceColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              icon: Icons.local_fire_department_rounded,
              iconColor: _currentStreak > 0
                  ? const Color(0xFFf7b731)
                  : muted,
              label: 'CURRENT STREAK',
              value: _currentStreak,
              valueColor: _currentStreak > 2
                  ? const Color(0xFFf7b731)
                  : scheme.onSurface,
              suffix: ' Days',
              scheme: scheme,
              muted: muted,
              surfaceColor: surfaceColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              icon: Icons.menu_book_rounded,
              iconColor: _accent,
              label: 'BOOKS READ',
              value: _totalBooks,
              valueColor: _accent,
              suffix: ' Volumes',
              scheme: scheme,
              muted: muted,
              surfaceColor: surfaceColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required int value,
    required Color valueColor,
    required String suffix,
    required ColorScheme scheme,
    required Color muted,
    required Color surfaceColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.onSurface.withValues(alpha: 0.06),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: muted,
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              TweenAnimationBuilder<int>(
                tween: IntTween(begin: 0, end: value),
                duration: const Duration(milliseconds: 800),
                builder: (_, v, __) => Text(
                  '$v',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w300,
                    color: valueColor,
                  ),
                ),
              ),
              Text(suffix, style: TextStyle(color: muted, fontSize: 14)),
            ],
          ),
        ],
      ),
    );
  }

  // ━━━ SECTION 3 — Weekly Chart ━━━

  Widget _buildWeeklyChart(
    ColorScheme scheme,
    Color muted,
    Color surfaceColor,
    bool isDark,
  ) {
    final totalWeek = _weeklyMinutes.fold<int>(0, (a, b) => a + b);
    final goalMinutes = 600; // 10 hours
    final pct = ((totalWeek / goalMinutes) * 100).clamp(0, 100).toInt();
    final maxMin =
        _weeklyMinutes.reduce((a, b) => a > b ? a : b).clamp(1, 999);
    final today = DateTime.now().weekday - 1; // 0=Mon
    const dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.onSurface.withValues(alpha: 0.06),
          width: 0.5,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WEEKLY RITUAL',
                    style: TextStyle(
                      color: muted,
                      fontSize: 10,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        _formatTime(totalWeek),
                        style: GoogleFonts.cormorantGaramond(
                          fontSize: 22,
                          fontWeight: FontWeight.w500,
                          color: scheme.onSurface,
                        ),
                      ),
                      Text(
                        ' / 10h',
                        style: TextStyle(color: muted, fontSize: 14),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              Text(
                '$pct%',
                style: const TextStyle(
                  color: _accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 110,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final mins = _weeklyMinutes[i];
                final barH = (mins / maxMin * 80).clamp(8.0, 80.0);
                final isToday = i == today;
                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      width: 28,
                      height: barH,
                      decoration: BoxDecoration(
                        color: isToday
                            ? _accent
                            : mins > 0
                                ? _accent.withValues(alpha: 0.4)
                                : isDark
                                    ? Colors.white.withValues(alpha: 0.06)
                                    : Colors.black.withValues(alpha: 0.04),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dayLabels[i],
                      style: TextStyle(
                        color: isToday ? _accent : muted,
                        fontSize: 10,
                        fontWeight: isToday ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ━━━ SECTION 4 — Badges ━━━

  Widget _buildBadgesSection(
    ColorScheme scheme,
    Color muted,
    Color surfaceColor,
    int booksRead,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                'Curated Laurels',
                style: GoogleFonts.cormorantGaramond(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                'View all',
                style: TextStyle(color: _accent, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: ReadingBadge.allBadges.length,
            itemBuilder: (ctx, i) {
              final badge = ReadingBadge.allBadges[i];
              final unlocked = badge.isUnlocked(
                booksRead,
                _totalReadingMinutes,
                _currentStreak,
                0, // genres placeholder
              );
              return _buildBadgeItem(badge, unlocked, scheme, muted, surfaceColor);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBadgeItem(
    ReadingBadge badge,
    bool unlocked,
    ColorScheme scheme,
    Color muted,
    Color surfaceColor,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: surfaceColor,
                  border: Border.all(
                    color: unlocked
                        ? badge.color.withValues(alpha: 0.5)
                        : muted.withValues(alpha: 0.15),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  badge.icon,
                  size: 28,
                  color: unlocked
                      ? badge.color
                      : muted.withValues(alpha: 0.3),
                ),
              ),
              if (!unlocked)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.4),
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      size: 18,
                      color: Colors.white54,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            badge.name,
            style: TextStyle(
              color: unlocked ? scheme.onSurface : muted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            badge.description,
            style: TextStyle(color: muted, fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ━━━ SECTION 5 — Annual Goal ━━━

  Widget _buildAnnualGoal(
    ColorScheme scheme,
    Color muted,
    Color surfaceColor,
    int booksRead,
  ) {
    final progress = (_yearlyGoal > 0)
        ? (booksRead / _yearlyGoal).clamp(0.0, 1.0)
        : 0.0;
    final pct = (progress * 100).toInt();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.onSurface.withValues(alpha: 0.06),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: Stack(
              children: [
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 6,
                  backgroundColor: muted.withValues(alpha: 0.12),
                  valueColor: const AlwaysStoppedAnimation(_accent),
                ),
                Center(
                  child: Text(
                    '$pct%',
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${DateTime.now().year} Collection',
                  style: GoogleFonts.cormorantGaramond(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'You have read $booksRead of your $_yearlyGoal book goal.',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => _showGoalUpdateDialog(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _accent),
                    ),
                    child: const Text(
                      'UPDATE GOAL',
                      style: TextStyle(
                        color: _accent,
                        fontSize: 11,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showGoalUpdateDialog() {
    try {
      int tempGoal = _yearlyGoal;
      showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDlg) => AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              'Yearly Goal',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$tempGoal books',
                  style: const TextStyle(fontSize: 28, color: _accent),
                ),
                Slider(
                  value: tempGoal.toDouble(),
                  min: 1,
                  max: 100,
                  divisions: 99,
                  activeColor: _accent,
                  onChanged: (v) => setDlg(() => tempGoal = v.toInt()),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    await GoalsService.saveGoal(
                      ReadingGoal(yearlyBooks: tempGoal),
                    );
                    if (mounted) {
                      setState(() => _yearlyGoal = tempGoal);
                    }
                  } catch (_) {}
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Save', style: TextStyle(color: _accent)),
              ),
            ],
          ),
        ),
      );
    } catch (_) {}
  }

  // ━━━ Pro Banner ━━━

  Widget _buildProBanner(ColorScheme scheme, Color muted) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () => context.push('/paywall'),
        child: Container(
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _accent.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded, color: _accent, size: 20),
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
                style: TextStyle(color: muted, fontSize: 13),
              ),
              const SizedBox(height: 4),
              const Text(
                'From \$1.99/month',
                style: TextStyle(
                  color: _accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ━━━ Theme Toggle ━━━

  Widget _buildThemeToggle(ColorScheme scheme, Color muted) {
    return Row(
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                      style: TextStyle(color: scheme.onSurface, fontSize: 13),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ━━━ SECTION 6 — Settings ━━━

  Widget _buildSettingsSection(ColorScheme scheme, Color muted) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
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
            icon: Icons.info_outline_rounded,
            label: 'About Reverie',
            onTap: () => _showAbout(),
            scheme: scheme,
            muted: muted,
          ),
        ],
      ),
    );
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
              child: Text(
                label,
                style: TextStyle(color: scheme.onSurface, fontSize: 15),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: muted, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthButton() {
    return Center(
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
                  fontSize: 14,
                ),
              ),
            )
          : TextButton(
              onPressed: () => context.push('/auth'),
              child: const Text(
                'Sign in',
                style: TextStyle(color: _accent, fontSize: 14),
              ),
            ),
    );
  }

  void _showComingSoon(String feature) {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$feature coming soon'),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (_) {}
  }

  void _showAbout() {
    try {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1a1a2e),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Reverie',
            style: TextStyle(color: Colors.white, fontSize: 22),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Version 1.0.0',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'A free, immersive EPUB reader for people '
                'who love books but cannot afford a Kindle.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close', style: TextStyle(color: _accent)),
            ),
          ],
        ),
      );
    } catch (_) {}
  }
}
