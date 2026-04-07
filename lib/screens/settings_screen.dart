import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reverie/screens/library_screen.dart';
import 'package:reverie/services/supabase_service.dart';
import 'package:reverie/theme/app_theme.dart';

const Color _defaultAccent = Color(0xFFE94560);

final StateProvider<Color> accentColorProvider =
    StateProvider<Color>((Ref ref) => _defaultAccent);

const List<Color> _accentOptions = [
  Color(0xFFE94560),
  Color(0xFF7C6AF7),
  Color(0xFF2EC4B6),
  Color(0xFFF7B731),
  Color(0xFF4A9EFF),
  Color(0xFF43AA8B),
];

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  double _defaultFontSize = 18.0;
  double _defaultLineHeight = 1.8;
  String _defaultFontFamily = 'Georgia';
  int _defaultThemeIndex = 0;

  static const List<Map<String, dynamic>> _readingThemes = [
    {'name': 'Dark', 'bg': Color(0xFF0f0f1a), 'text': Color(0xFFf0f0f0)},
    {'name': 'Black', 'bg': Color(0xFF000000), 'text': Color(0xFFffffff)},
    {'name': 'Paper', 'bg': Color(0xFFf5f0e8), 'text': Color(0xFF1a1a1a)},
    {'name': 'Sepia', 'bg': Color(0xFFfbf0d9), 'text': Color(0xFF5b4636)},
    {'name': 'Forest', 'bg': Color(0xFF1a2e1a), 'text': Color(0xFFc8e6c8)},
  ];

  @override
  void initState() {
    super.initState();
    _loadDefaults();
  }

  Future<void> _loadDefaults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _defaultFontSize = prefs.getDouble('reader_fontSize') ?? 18.0;
        _defaultLineHeight = prefs.getDouble('reader_lineHeight') ?? 1.8;
        _defaultFontFamily = prefs.getString('reader_fontFamily') ?? 'Georgia';
        _defaultThemeIndex = prefs.getInt('reader_theme') ?? 0;
      });
    } catch (_) {}
  }

  Future<void> _saveDefaults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('reader_fontSize', _defaultFontSize);
      await prefs.setDouble('reader_lineHeight', _defaultLineHeight);
      await prefs.setString('reader_fontFamily', _defaultFontFamily);
      await prefs.setInt('reader_theme', _defaultThemeIndex);
    } catch (_) {}
  }

  Future<void> _clearLibrary() async {
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Clear Library?'),
          content: const Text(
              'This will remove all books from your library. '
              'Your EPUB files will not be deleted.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Clear',
                    style: TextStyle(color: Colors.redAccent))),
          ],
        ),
      );
      if (confirmed == true) {
        ref.read(libraryBooksProvider.notifier).setBooks([]);
        await ref.read(libraryBooksProvider.notifier).saveToPrefs();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Library cleared')),
          );
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mode = ref.watch(themeModeProvider);
    final isDark = mode == ThemeMode.dark;
    final muted = scheme.onSurface.withValues(alpha: 0.5);
    final accent = ref.watch(accentColorProvider);
    final books = ref.watch(libraryBooksProvider);
    final totalSize = books.fold<int>(0, (s, b) => s + b.fileSizeBytes);
    final sizeMB = (totalSize / (1024 * 1024)).toStringAsFixed(1);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded,
                        color: scheme.onSurface, size: 20),
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/library');
                      }
                    },
                  ),
                  const Spacer(),
                  Text('Settings',
                      style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w500)),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  const SizedBox(height: 8),
                  // User profile section
                  if (SupabaseService.isLoggedIn) ...[
                    Center(
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 32,
                            backgroundColor: accent,
                            child: Text(
                              SupabaseService.displayName.isNotEmpty
                                  ? SupabaseService.displayName[0]
                                      .toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            SupabaseService.displayName,
                            style: TextStyle(
                                color: scheme.onSurface,
                                fontSize: 18,
                                fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            SupabaseService.userEmail ?? '',
                            style: TextStyle(color: muted, fontSize: 13),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => ScaffoldMessenger.of(context)
                                .showSnackBar(const SnackBar(
                                    content:
                                        Text('Edit profile coming soon'))),
                            child: Text('Edit Profile',
                                style: TextStyle(
                                    color: accent, fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Center(
                      child: Column(
                        children: [
                          Icon(Icons.person_outline_rounded,
                              size: 64, color: muted),
                          const SizedBox(height: 8),
                          Text('Sign in to sync your library',
                              style: TextStyle(
                                  color: muted, fontSize: 14)),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () => context.go('/auth'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 10),
                            ),
                            child: const Text('Sign In'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Divider(
                      color: muted.withValues(alpha: 0.15), height: 32),
                  _sectionTitle('Appearance', scheme),
                  _settingTile(
                    icon: isDark
                        ? Icons.dark_mode_rounded
                        : Icons.light_mode_rounded,
                    title: 'Theme',
                    trailing: Text(isDark ? 'Dark' : 'Light',
                        style: TextStyle(color: muted, fontSize: 14)),
                    onTap: () {
                      ref.read(themeModeProvider.notifier).state =
                          isDark ? ThemeMode.light : ThemeMode.dark;
                    },
                    scheme: scheme,
                  ),
                  _settingTile(
                    icon: Icons.palette_outlined,
                    title: 'Accent color',
                    trailing: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                          color: accent, shape: BoxShape.circle),
                    ),
                    onTap: () => _showAccentPicker(accent),
                    scheme: scheme,
                  ),
                  Divider(color: muted.withValues(alpha: 0.15), height: 32),
                  _sectionTitle('Reading Defaults', scheme),
                  // Font size slider
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.text_fields_rounded,
                            color: muted, size: 20),
                        const SizedBox(width: 12),
                        Text('Font size',
                            style: TextStyle(
                                color: scheme.onSurface, fontSize: 15)),
                        const Spacer(),
                        Text('${_defaultFontSize.toInt()}',
                            style: TextStyle(color: muted, fontSize: 14)),
                        SizedBox(
                          width: 120,
                          child: Slider(
                            value: _defaultFontSize,
                            min: 14,
                            max: 28,
                            divisions: 14,
                            activeColor: accent,
                            onChanged: (v) {
                              setState(() => _defaultFontSize = v);
                              _saveDefaults();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Spacing pills
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.format_line_spacing_rounded,
                            color: muted, size: 20),
                        const SizedBox(width: 12),
                        Text('Spacing',
                            style: TextStyle(
                                color: scheme.onSurface, fontSize: 15)),
                        const Spacer(),
                        _pill('Compact', _defaultLineHeight == 1.4, () {
                          setState(() => _defaultLineHeight = 1.4);
                          _saveDefaults();
                        }, accent, scheme),
                        const SizedBox(width: 6),
                        _pill('Normal', _defaultLineHeight == 1.8, () {
                          setState(() => _defaultLineHeight = 1.8);
                          _saveDefaults();
                        }, accent, scheme),
                        const SizedBox(width: 6),
                        _pill('Relaxed', _defaultLineHeight == 2.2, () {
                          setState(() => _defaultLineHeight = 2.2);
                          _saveDefaults();
                        }, accent, scheme),
                      ],
                    ),
                  ),
                  // Font pills
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.font_download_outlined,
                            color: muted, size: 20),
                        const SizedBox(width: 12),
                        Text('Font',
                            style: TextStyle(
                                color: scheme.onSurface, fontSize: 15)),
                        const Spacer(),
                        _pill('Serif', _defaultFontFamily == 'Georgia', () {
                          setState(() => _defaultFontFamily = 'Georgia');
                          _saveDefaults();
                        }, accent, scheme),
                        const SizedBox(width: 6),
                        _pill('Sans', _defaultFontFamily == 'Sans', () {
                          setState(() => _defaultFontFamily = 'Sans');
                          _saveDefaults();
                        }, accent, scheme),
                        const SizedBox(width: 6),
                        _pill('Mono', _defaultFontFamily == 'Mono', () {
                          setState(() => _defaultFontFamily = 'Mono');
                          _saveDefaults();
                        }, accent, scheme),
                      ],
                    ),
                  ),
                  // Reading theme circles
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Icon(Icons.color_lens_outlined,
                            color: muted, size: 20),
                        const SizedBox(width: 12),
                        Text('Reading theme',
                            style: TextStyle(
                                color: scheme.onSurface, fontSize: 15)),
                        const Spacer(),
                        ...List.generate(_readingThemes.length, (i) {
                          final sel = _defaultThemeIndex == i;
                          return Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: GestureDetector(
                              onTap: () {
                                setState(() => _defaultThemeIndex = i);
                                _saveDefaults();
                              },
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: _readingThemes[i]['bg'] as Color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: sel
                                        ? accent
                                        : Colors.grey.withValues(alpha: 0.3),
                                    width: sel ? 2 : 1,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  Divider(color: muted.withValues(alpha: 0.15), height: 32),
                  _sectionTitle('Library', scheme),
                  _settingTile(
                    icon: Icons.refresh_rounded,
                    title: 'Rescan Library',
                    trailing: Icon(Icons.chevron_right_rounded, color: muted),
                    onTap: () => context.go('/library'),
                    scheme: scheme,
                  ),
                  _settingTile(
                    icon: Icons.delete_outline_rounded,
                    title: 'Clear Library',
                    titleColor: Colors.redAccent,
                    trailing: Icon(Icons.chevron_right_rounded, color: muted),
                    onTap: _clearLibrary,
                    scheme: scheme,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '${books.length} books · $sizeMB MB',
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                  ),
                  Divider(color: muted.withValues(alpha: 0.15), height: 32),
                  _sectionTitle('About', scheme),
                  const SizedBox(height: 16),
                  Center(
                    child: Column(
                      children: [
                        Icon(Icons.auto_stories_rounded,
                            size: 40, color: accent),
                        const SizedBox(height: 8),
                        Text('Reverie',
                            style: TextStyle(
                                color: scheme.onSurface,
                                fontSize: 22,
                                fontWeight: FontWeight.w300,
                                fontFamily: 'serif')),
                        const SizedBox(height: 4),
                        Text('Version 1.0.0',
                            style: TextStyle(color: muted, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text('Read freely',
                            style: TextStyle(color: muted, fontSize: 13,
                                letterSpacing: 2)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(
                                content: Text('Privacy Policy coming soon'))),
                        child: Text('Privacy Policy',
                            style: TextStyle(color: muted, fontSize: 13)),
                      ),
                      Text(' · ', style: TextStyle(color: muted)),
                      TextButton(
                        onPressed: () => ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(
                                content: Text('Terms coming soon'))),
                        child: Text('Terms',
                            style: TextStyle(color: muted, fontSize: 13)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (SupabaseService.isLoggedIn)
                    _settingTile(
                      icon: Icons.logout_rounded,
                      title: 'Sign Out',
                      titleColor: Colors.redAccent,
                      trailing: Icon(Icons.chevron_right_rounded, color: muted),
                      onTap: () async {
                        try {
                          await SupabaseService.signOut();
                        } catch (_) {}
                        if (mounted) context.go('/auth');
                      },
                      scheme: scheme,
                    )
                  else
                    _settingTile(
                      icon: Icons.login_rounded,
                      title: 'Sign In',
                      trailing: Icon(Icons.chevron_right_rounded, color: muted),
                      onTap: () => context.go('/auth'),
                      scheme: scheme,
                    ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title,
          style: TextStyle(
              color: scheme.onSurface.withValues(alpha: 0.6),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 1)),
    );
  }

  Widget _settingTile({
    required IconData icon,
    required String title,
    required Widget trailing,
    required VoidCallback onTap,
    required ColorScheme scheme,
    Color? titleColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: titleColor ?? scheme.onSurface.withValues(alpha: 0.6),
                size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title,
                  style: TextStyle(
                      color: titleColor ?? scheme.onSurface, fontSize: 15)),
            ),
            trailing,
          ],
        ),
      ),
    );
  }

  Widget _pill(String label, bool selected, VoidCallback onTap,
      Color accent, ColorScheme scheme) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? accent
                : scheme.onSurface.withValues(alpha: 0.2),
          ),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? Colors.white : scheme.onSurface,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            )),
      ),
    );
  }

  void _showAccentPicker(Color current) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Accent Color',
                style: TextStyle(
                    color: Theme.of(ctx).colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _accentOptions.map((c) {
                final sel = c.value == current.value;
                return GestureDetector(
                  onTap: () {
                    ref.read(accentColorProvider.notifier).state = c;
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: sel ? Colors.white : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: sel
                        ? const Icon(Icons.check, color: Colors.white, size: 20)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
