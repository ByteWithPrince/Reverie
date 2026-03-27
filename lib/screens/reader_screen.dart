import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:epub_view/epub_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfx/pdfx.dart' hide DefaultBuilderOptions;
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
    name: 'Dark',
    background: Color(0xFF0F0F1A),
    textColor: Color(0xFFF0F0F0),
  ),
  ReadingTheme(
    name: 'Midnight',
    background: Color(0xFF000000),
    textColor: Color(0xFFFFFFFF),
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
  Timer? _hideTimer;

  // Reading settings
  double _fontSize = 18.0;
  double _lineSpacing = 1.8;
  double _horizontalMargin = 24.0;
  double _brightness = 1.0;
  String _fontFamily = 'Georgia';
  int _selectedFontIndex = 0;
  int _selectedThemeIndex = 0;

  // Progress tracking
  int _currentPage = 1;
  int _totalPages = 1;
  String _currentChapter = '';
  late bool _isEpub;

  // Bookmarks
  List<int> _bookmarks = <int>[];

  EpubController? _epubController;
  PdfController? _pdfController;

  String get _prefsPrefix => 'reader_${widget.filePath.hashCode}';

  @override
  void initState() {
    super.initState();
    _isEpub = widget.filePath.toLowerCase().endsWith('.epub');
    _loadAllSettings();
    _initReader();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _epubController?.dispose();
    _pdfController?.dispose();
    _resetBrightness();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // INIT & PERSISTENCE
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  void _initReader() {
    if (_isEpub) {
      _epubController = EpubController(
        document: EpubDocument.openFile(File(widget.filePath)),
      );
    } else {
      _pdfController = PdfController(
        document: PdfDocument.openFile(widget.filePath),
      );
    }
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
      final int? savedThemeIndex =
          prefs.getInt('${_prefsPrefix}_themeIndex');
      final String? bookmarksJson =
          prefs.getString('bookmarks_${widget.filePath.hashCode}');

      if (mounted) {
        setState(() {
          if (savedFontSize != null) _fontSize = savedFontSize;
          if (savedLineSpacing != null) _lineSpacing = savedLineSpacing;
          if (savedMargin != null) _horizontalMargin = savedMargin;
          if (savedFontIndex != null) {
            _selectedFontIndex = savedFontIndex;
            _fontFamily = _fontFamilyForIndex(savedFontIndex);
          }
          if (savedThemeIndex != null) _selectedThemeIndex = savedThemeIndex;
          if (bookmarksJson != null) {
            _bookmarks = (jsonDecode(bookmarksJson) as List<dynamic>)
                .cast<int>()
                .toList();
          }
        });
      }

      // Load brightness
      try {
        final double currentBrightness =
            await ScreenBrightness().current;
        if (mounted) setState(() => _brightness = currentBrightness);
      } catch (_) {}

      // Restore reading position
      _restorePosition(prefs);
    } catch (_) {}
  }

  void _restorePosition(SharedPreferences prefs) {
    try {
      final int? savedPage =
          prefs.getInt('progress_page_${widget.filePath.hashCode}');
      if (savedPage != null && savedPage > 0) {
        if (_isEpub) {
          // epub_view doesn't support direct position restoration easily
          // Position is auto-restored by the controller for scrollable views
        } else if (_pdfController != null) {
          Future<void>.delayed(const Duration(milliseconds: 500), () {
            if (mounted && _pdfController != null) {
              _pdfController!.jumpToPage(savedPage);
            }
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('fontSize', _fontSize);
      await prefs.setDouble('${_prefsPrefix}_lineSpacing', _lineSpacing);
      await prefs.setDouble('${_prefsPrefix}_margin', _horizontalMargin);
      await prefs.setInt('${_prefsPrefix}_fontIndex', _selectedFontIndex);
      await prefs.setInt('${_prefsPrefix}_themeIndex', _selectedThemeIndex);
    } catch (_) {}
  }

  Future<void> _saveProgress() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final double progress =
          _totalPages > 0 ? _currentPage / _totalPages : 0.0;
      await prefs.setDouble(
          'progress_${widget.filePath.hashCode}', progress);
      await prefs.setInt(
          'progress_page_${widget.filePath.hashCode}', _currentPage);
    } catch (_) {}
  }

  Future<void> _saveBookmarks() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'bookmarks_${widget.filePath.hashCode}',
        jsonEncode(_bookmarks),
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
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startHideTimer();
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleBookmark() {
    setState(() {
      if (_bookmarks.contains(_currentPage)) {
        _bookmarks.remove(_currentPage);
      } else {
        _bookmarks.add(_currentPage);
      }
    });
    _saveBookmarks();
  }

  bool get _isCurrentPageBookmarked => _bookmarks.contains(_currentPage);

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // SETTINGS BOTTOM SHEET
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  void _showSettingsPanel() {
    _hideTimer?.cancel();
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
                    // Handle bar
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
                    const SizedBox(height: 20),

                    // Brightness
                    _buildSettingsRow(
                      icon: Icons.brightness_low_rounded,
                      label:
                          'Brightness  ${(_brightness * 100).round()}%',
                      labelColor: sheetText,
                      iconColor: sheetMuted,
                      child: Expanded(
                        child: Slider(
                          value: _brightness,
                          min: 0.1,
                          max: 1.0,
                          activeColor: _accent,
                          inactiveColor: sheetMuted.withValues(alpha: 0.3),
                          onChanged: (double v) {
                            setSheetState(() => _brightness = v);
                            _setBrightness(v);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Font size
                    _buildSettingsRow(
                      icon: Icons.text_fields_rounded,
                      label: 'Font Size  ${_fontSize.round()}px',
                      labelColor: sheetText,
                      iconColor: sheetMuted,
                      child: Expanded(
                        child: Slider(
                          value: _fontSize,
                          min: 14,
                          max: 28,
                          divisions: 14,
                          activeColor: _accent,
                          inactiveColor: sheetMuted.withValues(alpha: 0.3),
                          onChanged: (double v) {
                            setSheetState(() => _fontSize = v);
                            setState(() {});
                            _saveSettings();
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Font family
                    Row(
                      children: <Widget>[
                        Icon(Icons.font_download_rounded,
                            color: sheetMuted, size: 20),
                        const SizedBox(width: 12),
                        ..._buildFontPills(
                            setSheetState, sheetText, sheetMuted),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Line spacing
                    _buildSettingsRow(
                      icon: Icons.format_line_spacing_rounded,
                      label:
                          'Line Spacing  ${_lineSpacing.toStringAsFixed(1)}',
                      labelColor: sheetText,
                      iconColor: sheetMuted,
                      child: Expanded(
                        child: Slider(
                          value: _lineSpacing,
                          min: 1.2,
                          max: 2.4,
                          divisions: 12,
                          activeColor: _accent,
                          inactiveColor: sheetMuted.withValues(alpha: 0.3),
                          onChanged: (double v) {
                            setSheetState(() => _lineSpacing = v);
                            setState(() {});
                            _saveSettings();
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Reading theme
                    Text('Reading Theme',
                        style: TextStyle(
                            color: sheetText,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List<Widget>.generate(
                        _readingThemes.length,
                        (int i) => _buildThemeCircle(
                            i, setSheetState, sheetText),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Margin
                    _buildSettingsRow(
                      icon: Icons.format_indent_increase_rounded,
                      label:
                          'Margin  ${_horizontalMargin.round()}px',
                      labelColor: sheetText,
                      iconColor: sheetMuted,
                      child: Expanded(
                        child: Slider(
                          value: _horizontalMargin,
                          min: 8,
                          max: 48,
                          divisions: 10,
                          activeColor: _accent,
                          inactiveColor: sheetMuted.withValues(alpha: 0.3),
                          onChanged: (double v) {
                            setSheetState(() => _horizontalMargin = v);
                            setState(() {});
                            _saveSettings();
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
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

  Widget _buildSettingsRow({
    required IconData icon,
    required String label,
    required Color labelColor,
    required Color iconColor,
    required Widget child,
  }) {
    return Row(
      children: <Widget>[
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(color: labelColor, fontSize: 12)),
        child,
      ],
    );
  }

  List<Widget> _buildFontPills(
      StateSetter setSheetState, Color textColor, Color mutedColor) {
    const List<String> labels = <String>['Serif', 'Sans', 'Mono'];
    return List<Widget>.generate(3, (int i) {
      final bool selected = _selectedFontIndex == i;
      return Padding(
        padding: const EdgeInsets.only(left: 8),
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
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? _accent : Colors.transparent,
              border: Border.all(
                color: selected ? _accent : mutedColor,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              labels[i],
              style: TextStyle(
                color: selected ? Colors.white : textColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildThemeCircle(
      int index, StateSetter setSheetState, Color labelColor) {
    final ReadingTheme rt = _readingThemes[index];
    final bool selected = _selectedThemeIndex == index;

    return GestureDetector(
      onTap: () {
        setSheetState(() => _selectedThemeIndex = index);
        setState(() {});
        _saveSettings();
      },
      child: Column(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: rt.background,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? _accent : Colors.grey.withValues(alpha: 0.3),
                width: selected ? 3 : 1,
              ),
            ),
            child: Center(
              child: Text(
                'A',
                style: TextStyle(
                  color: rt.textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            rt.name,
            style: TextStyle(
              color: labelColor.withValues(alpha: 0.6),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  bool _isDarkBackground(Color bg) {
    return bg.computeLuminance() < 0.5;
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

    return Scaffold(
      backgroundColor: bg,
      body: GestureDetector(
        onTapUp: (TapUpDetails details) {
          final double dx = details.globalPosition.dx;
          if (dx < 80) {
            _navigatePrevious();
          } else if (dx > screenWidth - 80) {
            _navigateNext();
          } else {
            _toggleControls();
          }
        },
        onVerticalDragEnd: (DragEndDetails details) {
          if (details.velocity.pixelsPerSecond.dy < -200) {
            _showSettingsPanel();
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
            _isEpub
                ? _buildEpubReader(bg, textColor)
                : _buildPdfReader(),
            _buildProgressBar(),
            if (_showControls) _buildControlsBar(bg, textColor),
          ],
        ),
      ),
    );
  }

  void _navigatePrevious() {
    if (_isEpub) {
      // epub_view uses scrolling — no direct page nav
    } else if (_pdfController != null && _currentPage > 1) {
      _pdfController!.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _navigateNext() {
    if (_isEpub) {
      // epub_view uses scrolling — no direct page nav
    } else if (_pdfController != null && _currentPage < _totalPages) {
      _pdfController!.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Widget _buildEpubReader(Color bg, Color textColor) {
    if (_epubController == null) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    return EpubView(
      controller: _epubController!,
      onChapterChanged: (value) {
        if (value != null && mounted) {
          setState(() {
            _currentChapter = value.chapter?.Title ?? '';
            _currentPage = value.position.index + 1;
          });
          _saveProgress();
        }
      },
      builders: EpubViewBuilders<DefaultBuilderOptions>(
        options: DefaultBuilderOptions(
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

  Widget _buildPdfReader() {
    if (_pdfController == null) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    return PdfView(
      controller: _pdfController!,
      onPageChanged: (int page) {
        if (mounted) {
          setState(() => _currentPage = page);
          _saveProgress();
        }
      },
      onDocumentLoaded: (PdfDocument document) {
        if (mounted) {
          setState(() => _totalPages = document.pagesCount);
        }
      },
    );
  }

  Widget _buildProgressBar() {
    final double progress =
        _totalPages > 0 ? _currentPage / _totalPages : 0.0;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: LinearProgressIndicator(
        value: progress,
        minHeight: 2,
        backgroundColor: Colors.transparent,
        valueColor: const AlwaysStoppedAnimation<Color>(_accent),
      ),
    );
  }

  Widget _buildControlsBar(Color bg, Color textColor) {
    final bool isDarkBg = _isDarkBackground(bg);
    final Color barBg = isDarkBg
        ? Colors.black.withValues(alpha: 0.85)
        : Colors.white.withValues(alpha: 0.85);
    final Color iconColor = isDarkBg ? Colors.white : Colors.black87;
    final Color labelColor = isDarkBg ? Colors.white70 : Colors.black54;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(color: barBg),
            child: SafeArea(
              top: false,
              child: Row(
                children: <Widget>[
                  // Back button
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded,
                        color: iconColor, size: 20),
                    onPressed: () => context.pop(),
                  ),

                  // Chapter / page info
                  Expanded(
                    child: Text(
                      _isEpub
                          ? (_currentChapter.isEmpty
                              ? 'Loading...'
                              : _currentChapter)
                          : '$_currentPage / $_totalPages',
                      style: TextStyle(color: labelColor, fontSize: 13),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  // Aa — settings
                  IconButton(
                    icon: Text('Aa',
                        style: TextStyle(
                            color: iconColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    onPressed: _showSettingsPanel,
                  ),

                  // Bookmark
                  IconButton(
                    icon: Icon(
                      _isCurrentPageBookmarked
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      color: _isCurrentPageBookmarked ? _accent : iconColor,
                      size: 22,
                    ),
                    onPressed: _toggleBookmark,
                  ),

                  // Share placeholder
                  IconButton(
                    icon: Icon(Icons.share_rounded,
                        color: iconColor, size: 20),
                    onPressed: () {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Share coming soon'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}