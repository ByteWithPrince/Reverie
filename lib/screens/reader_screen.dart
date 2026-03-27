import 'dart:async';
import 'dart:io';

import 'package:epub_view/epub_view.dart' as epub;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// READING THEME DATA
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class ReadingTheme {
  final String name;
  final Color background;
  final Color textColor;

  const ReadingTheme({
    required this.name,
    required this.background,
    required this.textColor,
  });
}

const List<ReadingTheme> _readingThemes = <ReadingTheme>[
  ReadingTheme(
    name: 'Midnight',
    background: Color(0xFF000000),
    textColor: Color(0xFFFFFFFF),
  ),
  ReadingTheme(
    name: 'Dark',
    background: Color(0xFF0F0F1A),
    textColor: Color(0xFFF0F0F0),
  ),
  ReadingTheme(
    name: 'Paper',
    background: Color(0xFFF5F0E8),
    textColor: Color(0xFF1A1A1A),
  ),
  ReadingTheme(
    name: 'Sepia',
    background: Color(0xFFFBF0D9),
    textColor: Color(0xFF5B4636),
  ),
  ReadingTheme(
    name: 'Forest',
    background: Color(0xFF1A2E1A),
    textColor: Color(0xFFC8E6C8),
  ),
];

const Color _accent = Color(0xFFE94560);

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// READER SCREEN
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class ReaderScreen extends ConsumerStatefulWidget {
  final String filePath;

  const ReaderScreen({super.key, required this.filePath});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  bool _showControls = false;
  bool _showBrightnessOverlay = false;
  Timer? _hideTimer;

  // Reading settings
  double _fontSize = 18.0;
  double _lineSpacing = 1.8;
  double _horizontalMargin = 24.0;
  double _brightness = 1.0;
  String _fontFamily = 'Georgia';
  int _selectedFontIndex = 0;
  int _selectedSpacingIndex = 1;
  int _selectedThemeIndex = 1;

  // Progress tracking
  int _currentChapterIndex = 0;
  int _totalChapters = 1;
  String _currentChapter = '';
  String _bookTitle = '';

  epub.EpubController? _epubController;

  String get _prefsPrefix => 'reader_${widget.filePath.hashCode}';

  @override
  void initState() {
    super.initState();
    _loadAllSettings();
    _initReader();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _saveProgress();
    _epubController?.dispose();
    _resetBrightness();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // INIT & PERSISTENCE
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  void _initReader() {
    _epubController = epub.EpubController(
      document: epub.EpubDocument.openFile(File(widget.filePath)),
    );

    // Derive book title from file path
    final String filename =
        widget.filePath.split(Platform.pathSeparator).last;
    final int dotIndex = filename.lastIndexOf('.');
    _bookTitle =
        dotIndex > 0 ? filename.substring(0, dotIndex) : filename;
  }

  Future<void> _loadAllSettings() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      final double? savedFontSize = prefs.getDouble('fontSize');
      final double? savedLineSpacing =
          prefs.getDouble('${_prefsPrefix}_lineSpacing');
      final double? savedMargin =
          prefs.getDouble('${_prefsPrefix}_margin');
      final int? savedFontIndex =
          prefs.getInt('${_prefsPrefix}_fontIndex');
      final int? savedSpacingIndex =
          prefs.getInt('${_prefsPrefix}_spacingIndex');
      final int? savedThemeIndex =
          prefs.getInt('${_prefsPrefix}_themeIndex');

      if (mounted) {
        setState(() {
          if (savedFontSize != null) _fontSize = savedFontSize;
          if (savedLineSpacing != null) _lineSpacing = savedLineSpacing;
          if (savedMargin != null) _horizontalMargin = savedMargin;
          if (savedFontIndex != null) {
            _selectedFontIndex = savedFontIndex;
            _fontFamily = _fontFamilyForIndex(savedFontIndex);
          }
          if (savedSpacingIndex != null) _selectedSpacingIndex = savedSpacingIndex;
          if (savedThemeIndex != null) _selectedThemeIndex = savedThemeIndex;
        });
      }

      try {
        final double currentBrightness =
            await ScreenBrightness().current;
        if (mounted) setState(() => _brightness = currentBrightness);
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('fontSize', _fontSize);
      await prefs.setDouble('${_prefsPrefix}_lineSpacing', _lineSpacing);
      await prefs.setDouble('${_prefsPrefix}_margin', _horizontalMargin);
      await prefs.setInt('${_prefsPrefix}_fontIndex', _selectedFontIndex);
      await prefs.setInt('${_prefsPrefix}_spacingIndex', _selectedSpacingIndex);
      await prefs.setInt('${_prefsPrefix}_themeIndex', _selectedThemeIndex);
    } catch (_) {}
  }

  Future<void> _saveProgress() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final double progress =
          _totalChapters > 0 ? _currentChapterIndex / _totalChapters : 0.0;
      await prefs.setDouble(
        'progress_${widget.filePath.hashCode}',
        progress.clamp(0.0, 1.0),
      );
      await prefs.setInt(
        'progress_chapter_${widget.filePath.hashCode}',
        _currentChapterIndex,
      );
    } catch (_) {}
  }

  Future<void> _setBrightness(double value) async {
    try {
      await ScreenBrightness().setScreenBrightness(value);
      if (mounted) setState(() => _brightness = value);
    } catch (_) {}
  }

  Future<void> _resetBrightness() async {
    try {
      await ScreenBrightness().resetScreenBrightness();
    } catch (_) {}
  }

  String _fontFamilyForIndex(int index) {
    switch (index) {
      case 0:
        return 'Georgia';
      case 1:
        return 'sans-serif';
      case 2:
        return 'monospace';
      default:
        return 'Georgia';
    }
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // CONTROLS
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (!_showControls) _showBrightnessOverlay = false;
    });
    if (_showControls) {
      _startHideTimer();
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showControls = false;
          _showBrightnessOverlay = false;
        });
      }
    });
  }

  void _toggleBrightnessOverlay() {
    _hideTimer?.cancel();
    setState(() {
      _showBrightnessOverlay = !_showBrightnessOverlay;
    });
  }

  bool _isDarkBackground(Color bg) {
    return bg.computeLuminance() < 0.5;
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // FONT SETTINGS BOTTOM SHEET
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  void _showFontSettingsSheet() {
    _hideTimer?.cancel();
    setState(() => _showBrightnessOverlay = false);

    final ReadingTheme activeTheme = _readingThemes[_selectedThemeIndex];
    final bool isThemeDark = _isDarkBackground(activeTheme.background);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext ctx, StateSetter setSheetState) {
            final Color sheetBg = isThemeDark
                ? const Color(0xFF1A1A2E)
                : const Color(0xFFEDE8DF);
            final Color sheetText = isThemeDark
                ? const Color(0xFFF0F0F0)
                : const Color(0xFF1A1A1A);
            final Color sheetMuted = sheetText.withValues(alpha: 0.5);

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // Drag handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: sheetMuted,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Reading settings',
                      style: TextStyle(
                        color: sheetText,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // a) Font size
                    Row(
                      children: <Widget>[
                        Text('Text size',
                            style: TextStyle(color: sheetText, fontSize: 13)),
                        const Spacer(),
                        _buildCircleButton(
                          icon: Icons.remove,
                          color: sheetMuted,
                          onTap: () {
                            if (_fontSize > 14) {
                              setSheetState(() => _fontSize -= 1);
                              setState(() {});
                              _saveSettings();
                            }
                          },
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            '${_fontSize.round()}',
                            style: TextStyle(
                              color: sheetText,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        _buildCircleButton(
                          icon: Icons.add,
                          color: sheetMuted,
                          onTap: () {
                            if (_fontSize < 28) {
                              setSheetState(() => _fontSize += 1);
                              setState(() {});
                              _saveSettings();
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // b) Line spacing
                    Row(
                      children: <Widget>[
                        Text('Spacing',
                            style: TextStyle(color: sheetText, fontSize: 13)),
                        const Spacer(),
                        ..._buildSpacingPills(
                            setSheetState, sheetText, sheetMuted),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // c) Font family
                    Row(
                      children: <Widget>[
                        Text('Font',
                            style: TextStyle(color: sheetText, fontSize: 13)),
                        const Spacer(),
                        ..._buildFontPills(
                            setSheetState, sheetText, sheetMuted),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // d) Reading theme
                    Text('Theme',
                        style: TextStyle(color: sheetText, fontSize: 13)),
                    const SizedBox(height: 10),
                    Row(
                      children: List<Widget>.generate(
                        _readingThemes.length,
                        (int i) {
                          if (i > 0) {
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                const SizedBox(width: 8),
                                _buildThemeCircle(
                                    i, setSheetState),
                              ],
                            );
                          }
                          return _buildThemeCircle(i, setSheetState);
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      if (_showControls) _startHideTimer();
    });
  }

  Widget _buildCircleButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 1),
        ),
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }

  List<Widget> _buildSpacingPills(
      StateSetter setSheetState, Color textColor, Color mutedColor) {
    const List<String> labels = <String>['Compact', 'Normal', 'Relaxed'];
    const List<double> values = <double>[1.4, 1.8, 2.2];
    return List<Widget>.generate(3, (int i) {
      final bool selected = _selectedSpacingIndex == i;
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: GestureDetector(
          onTap: () {
            setSheetState(() {
              _selectedSpacingIndex = i;
              _lineSpacing = values[i];
            });
            setState(() {});
            _saveSettings();
          },
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: selected ? _accent : Colors.transparent,
              border: Border.all(
                color: selected ? _accent : mutedColor,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              labels[i],
              style: TextStyle(
                color: selected ? Colors.white : textColor,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    });
  }

  List<Widget> _buildFontPills(
      StateSetter setSheetState, Color textColor, Color mutedColor) {
    const List<String> labels = <String>['Serif', 'Sans', 'Mono'];
    return List<Widget>.generate(3, (int i) {
      final bool selected = _selectedFontIndex == i;
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: GestureDetector(
          onTap: () {
            setSheetState(() {
              _selectedFontIndex = i;
              _fontFamily = _fontFamilyForIndex(i);
            });
            setState(() {});
            _saveSettings();
          },
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: selected ? _accent : Colors.transparent,
              border: Border.all(
                color: selected ? _accent : mutedColor,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              labels[i],
              style: TextStyle(
                color: selected ? Colors.white : textColor,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildThemeCircle(int index, StateSetter setSheetState) {
    final ReadingTheme rt = _readingThemes[index];
    final bool selected = _selectedThemeIndex == index;

    return GestureDetector(
      onTap: () {
        setSheetState(() => _selectedThemeIndex = index);
        setState(() {});
        _saveSettings();
      },
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: rt.background,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? _accent
                : Colors.grey.withValues(alpha: 0.3),
            width: selected ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(
            'A',
            style: TextStyle(
              color: rt.textColor,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // BUILD
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  @override
  Widget build(BuildContext context) {
    final ReadingTheme activeTheme = _readingThemes[_selectedThemeIndex];
    final Color bg = activeTheme.background;
    final Color textColor = activeTheme.textColor;
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDark = _isDarkBackground(bg);
    final double progress =
        _totalChapters > 0 ? (_currentChapterIndex / _totalChapters).clamp(0.0, 1.0) : 0.0;
    final int progressPct = (progress * 100).round();
    final Color muted = isDark
        ? Colors.white.withValues(alpha: 0.5)
        : Colors.black.withValues(alpha: 0.5);

    return Scaffold(
      backgroundColor: bg,
      body: GestureDetector(
        onTapUp: (TapUpDetails details) {
          final double dx = details.globalPosition.dx;
          final double quarter = screenWidth * 0.25;
          if (_showBrightnessOverlay) {
            setState(() => _showBrightnessOverlay = false);
            return;
          }
          if (dx < quarter) {
            // Left 25%: scroll up / previous
          } else if (dx > screenWidth - quarter) {
            // Right 25%: scroll down / next
          } else {
            _toggleControls();
          }
        },
        onLongPress: () {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Highlights coming soon'),
                duration: Duration(seconds: 1),
              ),
            );
          }
        },
        child: Stack(
          children: <Widget>[
            // EPUB reader
            _buildEpubReader(bg, textColor),

            // Bottom progress section (always visible)
            _buildBottomProgress(progress, progressPct, muted),

            // Top controls bar (shows/hides)
            if (_showControls)
              _buildTopControlsBar(isDark, muted),

            // Brightness overlay
            if (_showBrightnessOverlay && _showControls)
              _buildBrightnessOverlay(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildEpubReader(Color bg, Color textColor) {
    if (_epubController == null) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    return epub.EpubView(
      controller: _epubController!,
      onChapterChanged: (value) {
        if (value != null && mounted) {
          setState(() {
            _currentChapter = value.chapter?.Title ?? '';
            _currentChapterIndex = value.position.index + 1;
          });
          _saveProgress();
        }
      },
      onDocumentLoaded: (epub.EpubBook document) {
        if (mounted) {
          final int chapters = document.Chapters?.length ?? 1;
          setState(() {
            _totalChapters = chapters > 0 ? chapters : 1;
            _bookTitle = document.Title ?? _bookTitle;
          });

          // Restore reading position
          _restoreChapterPosition();
        }
      },
      builders: epub.EpubViewBuilders<epub.DefaultBuilderOptions>(
        options: epub.DefaultBuilderOptions(
          chapterPadding: EdgeInsets.symmetric(
            horizontal: _horizontalMargin,
            vertical: 16,
          ),
          paragraphPadding: const EdgeInsets.symmetric(vertical: 8),
          textStyle: TextStyle(
            fontFamily: _fontFamily,
            fontSize: _fontSize,
            height: _lineSpacing,
            color: textColor,
          ),
        ),
        chapterDividerBuilder: (_) => const SizedBox(height: 32),
      ),
    );
  }

  Future<void> _restoreChapterPosition() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final int? savedChapter =
          prefs.getInt('progress_chapter_${widget.filePath.hashCode}');
      if (savedChapter != null && savedChapter > 0 && _epubController != null) {
        // epub_view auto-restores scroll position in most cases
        // but we save chapter index for progress tracking
        setState(() => _currentChapterIndex = savedChapter);
      }
    } catch (_) {}
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // BOTTOM PROGRESS (ALWAYS VISIBLE)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildBottomProgress(double progress, int progressPct, Color muted) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SizedBox(
        height: 36,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: Colors.transparent,
              valueColor: const AlwaysStoppedAnimation<Color>(_accent),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4, top: 4),
              child: Text(
                '$progressPct% complete',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // TOP CONTROLS BAR
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildTopControlsBar(bool isDark, Color muted) {
    final Color barBg = isDark
        ? Colors.black.withValues(alpha: 0.8)
        : Colors.white.withValues(alpha: 0.8);
    final Color iconColor = isDark ? Colors.white : Colors.black87;

    final String displayTitle = _currentChapter.isNotEmpty
        ? _currentChapter
        : (_bookTitle.isNotEmpty ? _bookTitle : 'Loading...');

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        color: barBg,
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 56,
            child: Row(
              children: <Widget>[
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(Icons.arrow_back_ios_new_rounded,
                      color: iconColor, size: 20),
                  onPressed: () => context.pop(),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    displayTitle,
                    style: TextStyle(color: muted, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                const Spacer(),
                // Aa — font settings
                IconButton(
                  icon: Text('Aa',
                      style: TextStyle(
                          color: iconColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  onPressed: _showFontSettingsSheet,
                ),
                // Brightness
                IconButton(
                  icon: Icon(Icons.brightness_6_rounded,
                      color: iconColor, size: 20),
                  onPressed: _toggleBrightnessOverlay,
                ),
                // More
                IconButton(
                  icon: Icon(Icons.more_vert_rounded,
                      color: iconColor, size: 20),
                  onPressed: () {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('More options coming soon'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // BRIGHTNESS OVERLAY
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildBrightnessOverlay(bool isDark) {
    final Color overlayBg = isDark
        ? const Color(0xFF1A1A2E)
        : const Color(0xFFEDE8DF);
    final Color overlayText = isDark
        ? const Color(0xFFF0F0F0)
        : const Color(0xFF1A1A1A);
    final Color overlayMuted = overlayText.withValues(alpha: 0.4);

    return Positioned(
      top: MediaQuery.of(context).padding.top + 56 + 8,
      right: 60,
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: overlayBg,
          borderRadius: BorderRadius.circular(12),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.wb_sunny_rounded, color: overlayMuted, size: 18),
            SizedBox(
              height: 150,
              child: RotatedBox(
                quarterTurns: 3,
                child: Slider(
                  value: _brightness,
                  min: 0.1,
                  max: 1.0,
                  activeColor: _accent,
                  inactiveColor: overlayMuted.withValues(alpha: 0.3),
                  onChanged: (double v) {
                    setState(() => _brightness = v);
                    _setBrightness(v);
                  },
                ),
              ),
            ),
            Icon(Icons.nightlight_round, color: overlayMuted, size: 18),
          ],
        ),
      ),
    );
  }
}